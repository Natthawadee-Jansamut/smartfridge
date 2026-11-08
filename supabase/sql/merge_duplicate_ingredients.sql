-- =============================================================================
-- รวมวัตถุดิบที่ซ้ำกัน (คนละแถวใน ingredients แต่เป็นของเดียวกัน)
-- เช่น "มะเขือเทศเชอร์รี่" กับ "มะเขือเทศราชินี"
--
-- ทำไมใส่ alias อย่างเดียวไม่พอ: resolve_ingredient_id() เลือกชื่อวัตถุดิบก่อน alias
-- ถ้าทั้งสองชื่อมีแถวใน ingredients อยู่แล้ว alias จะไม่มีผล และสูตรเดิม/ของในตู้ยังชี้คนละ id
--
-- private.merge_ingredients('ชื่อที่จะรวมเข้าไป', 'ชื่อที่จะเก็บไว้') ทำตามลำดับ:
--   1) recipe_ingredients.ingredient_id   ย้ายไปแถวที่เก็บไว้
--      (trigger refresh_recipe_ingredient_ids อัปเดต recipes.ingredient_ids ให้เอง)
--   2) fridge_items.ingredient_id         ย้ายไปแถวที่เก็บไว้
--   3) ingredient_aliases                 alias ของแถวที่รวมเข้าไป ย้ายไปแถวที่เก็บไว้
--   4) is_staple                          ถ้าแถวใดแถวหนึ่งเป็นของพื้นฐาน แถวที่เก็บไว้เป็นด้วย
--   5) ลบแถวที่รวมเข้าไป แล้วเพิ่มชื่อนั้นเป็น alias ของแถวที่เก็บไว้
--      (สูตรใหม่ที่เขียนชื่อนั้นจะได้ id เดียวกัน ไม่สร้างแถวซ้ำอีก)
--   6) recipes.ingredient_signature       คำนวณใหม่ให้สูตรที่ได้รับผล
--      ถ้าคำนวณแล้วชนกับสูตรสาธารณะที่ชื่อ+วัตถุดิบเหมือนกัน (unique index)
--      จะคงลายเซ็นเดิมไว้ และนับเป็น "สูตรซ้ำ" ในผลลัพธ์ (ดูได้จากขั้น 4)
--
-- ไม่แตะ: ชื่อที่แสดงในสูตร (recipe_ingredients.display_name) และชื่อใน fridge_items.name
-- ผู้ใช้ยังเห็นชื่อตามที่สูตร/ตู้เย็นเขียนไว้ แค่ระบบรู้ว่าเป็นวัตถุดิบเดียวกัน
--
-- วิธีใช้ (Supabase Dashboard -> SQL Editor):
--   1) สำรองข้อมูลก่อน
--   2) รันขั้น 1 (สร้างฟังก์ชัน) — รันครั้งเดียว
--   3) รันขั้น 2 ดูคู่ที่น่าจะซ้ำ แล้วตัดสินใจเองว่าคู่ไหนเป็นของเดียวกันจริง
--   4) ใส่คู่ที่ต้องการในขั้น 3 แล้วรัน (ทำใน transaction: ผลไม่ถูกใจให้ rollback)
--   5) รันขั้น 4 ตรวจผล
-- =============================================================================


-- =============================================================================
-- ขั้น 1: ฟังก์ชันรวมวัตถุดิบ
-- =============================================================================
create schema if not exists private;

create or replace function private.merge_ingredients(p_from text, p_to text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from       bigint;
  v_from_name  text;
  v_from_stap  boolean;
  v_to         bigint;
  v_to_name    text;
  v_recipes    uuid[];
  v_rid        uuid;
  v_sig        text;
  v_ri         integer := 0;
  v_fi         integer := 0;
  v_al         integer := 0;
  v_sig_ok     integer := 0;
  v_sig_dup    integer := 0;
begin
  select id, name, is_staple into v_from, v_from_name, v_from_stap
    from public.ingredients where name_key = public.normalize_text(p_from);
  select id, name into v_to, v_to_name
    from public.ingredients where name_key = public.normalize_text(p_to);

  if v_from is null then return format('ข้าม: ไม่พบวัตถุดิบ "%s"', p_from); end if;
  if v_to   is null then return format('ข้าม: ไม่พบวัตถุดิบ "%s"', p_to);   end if;
  if v_from = v_to  then return format('ข้าม: "%s" กับ "%s" เป็นแถวเดียวกัน', p_from, p_to); end if;

  -- สูตรที่ได้รับผล (เก็บไว้ก่อนย้าย id)
  v_recipes := array(
    select distinct recipe_id from public.recipe_ingredients where ingredient_id = v_from);

  -- 1) ส่วนผสมของสูตร
  update public.recipe_ingredients set ingredient_id = v_to where ingredient_id = v_from;
  get diagnostics v_ri = row_count;

  -- 2) ของในตู้เย็น (trigger ของ fridge_items ไม่เปลี่ยน id เพราะชื่อไม่ได้เปลี่ยน)
  update public.fridge_items set ingredient_id = v_to where ingredient_id = v_from;
  get diagnostics v_fi = row_count;

  -- ตารางประวัติ (ถ้าสร้างไว้จาก schema_improvements.sql ขั้น 5)
  if to_regclass('public.fridge_item_events') is not null then
    execute 'update public.fridge_item_events set ingredient_id = $1 where ingredient_id = $2'
      using v_to, v_from;
  end if;

  -- 3) alias เดิมของแถวที่รวมเข้าไป
  update public.ingredient_aliases set ingredient_id = v_to where ingredient_id = v_from;
  get diagnostics v_al = row_count;

  -- 4) ของพื้นฐาน
  if v_from_stap then
    update public.ingredients set is_staple = true where id = v_to;
  end if;

  -- 5) ลบแถวซ้ำ แล้วให้ชื่อเดิมเป็น alias
  delete from public.ingredients where id = v_from;
  insert into public.ingredient_aliases (alias, ingredient_id)
  values (v_from_name, v_to)
  on conflict (alias_key) do nothing;

  -- 6) ลายเซ็นสูตร (สูตรที่ได้รับผล) — สูตรที่กลายเป็นซ้ำกับสูตรสาธารณะอื่นคงค่าเดิมไว้
  foreach v_rid in array v_recipes loop
    select md5(string_agg(x.id::text, ',' order by x.id))
      into v_sig
      from (select distinct ingredient_id as id
              from public.recipe_ingredients
             where recipe_id = v_rid) x;
    begin
      update public.recipes
         set ingredient_signature = v_sig
       where id = v_rid
         and ingredient_signature is distinct from v_sig;
      if found then v_sig_ok := v_sig_ok + 1; end if;
    exception when unique_violation then
      v_sig_dup := v_sig_dup + 1;
    end;
  end loop;

  return format(
    'รวม "%s" (id %s) -> "%s" (id %s): recipe_ingredients %s แถว, fridge_items %s แถว, '
    'alias %s แถว, ลายเซ็นสูตรใหม่ %s สูตร, สูตรซ้ำกับสูตรอื่น %s สูตร',
    v_from_name, v_from, v_to_name, v_to, v_ri, v_fi, v_al, v_sig_ok, v_sig_dup);
end;
$$;

revoke all on function private.merge_ingredients(text, text) from public, anon, authenticated;


-- =============================================================================
-- ขั้น 2: หาคู่ที่น่าจะซ้ำ (อ่านอย่างเดียว) — ต้องดูเองว่าเป็นของเดียวกันจริงไหม
--   contains   = ชื่อหนึ่งอยู่ในอีกชื่อ (ไข่ / ไข่ไก่ — แต่ น้ำ / น้ำปลา ไม่ใช่ของเดียวกัน!)
--   similarity = ความคล้ายของตัวอักษร 0–1
--   *_recipes / *_fridge = จำนวนแถวที่อ้างถึง (รวมเข้าแถวที่ถูกใช้มากกว่ามักดีกว่า)
-- =============================================================================
select a.name as name_a,
       b.name as name_b,
       (strpos(a.name_key, b.name_key) > 0 or strpos(b.name_key, a.name_key) > 0) as contains,
       round(extensions.similarity(a.name_key, b.name_key)::numeric, 2)          as similarity,
       (select count(*) from public.recipe_ingredients r where r.ingredient_id = a.id) as a_recipes,
       (select count(*) from public.recipe_ingredients r where r.ingredient_id = b.id) as b_recipes,
       (select count(*) from public.fridge_items f where f.ingredient_id = a.id)       as a_fridge,
       (select count(*) from public.fridge_items f where f.ingredient_id = b.id)       as b_fridge
from public.ingredients a
join public.ingredients b on a.id < b.id
where strpos(a.name_key, b.name_key) > 0
   or strpos(b.name_key, a.name_key) > 0
   or extensions.similarity(a.name_key, b.name_key) >= 0.4
order by similarity desc, a.name;


-- =============================================================================
-- ขั้น 3: รวมคู่ที่เลือก — แก้ชื่อในรายการแล้วรันทั้งบล็อก
--   ซ้าย = ชื่อที่จะรวมเข้าไป (แถวนี้ถูกลบ ชื่อกลายเป็น alias)
--   ขวา  = ชื่อที่จะเก็บไว้
--   ผลไม่ถูกใจ: เปลี่ยน commit เป็น rollback แล้วรันใหม่
-- =============================================================================
begin;

select private.merge_ingredients(m.from_name, m.to_name) as result
from (values
  -- ('มะเขือเทศเชอร์รี่', 'มะเขือเทศราชินี')    -- ตัวอย่าง: เอา -- หน้าบรรทัดออกเมื่อแน่ใจ
  (null::text, null::text)                        -- บรรทัดว่างกันรายการว่าง (ถูกข้ามเอง)
) as m(from_name, to_name)
where m.from_name is not null;

commit;


-- =============================================================================
-- ขั้น 4: ตรวจผล
-- =============================================================================

-- alias ทั้งหมด
select a.alias, i.name as canonical
from public.ingredient_aliases a
join public.ingredients i on i.id = a.ingredient_id
order by i.name, a.alias;

-- ส่วนผสมที่ชี้ไป id ที่ไม่มีแล้ว (ต้องเป็น 0)
select count(*) as orphan_recipe_ingredients
from public.recipe_ingredients ri
left join public.ingredients i on i.id = ri.ingredient_id
where i.id is null;

-- recipes.ingredient_ids ตรงกับ recipe_ingredients ไหม (ต้องเป็น 0)
select count(*) as stale_ingredient_ids
from public.recipes r
where r.ingredient_ids is distinct from coalesce(
  (select array_agg(distinct ri.ingredient_id order by ri.ingredient_id)
     from public.recipe_ingredients ri where ri.recipe_id = r.id), '{}');

-- สูตรสาธารณะที่ชื่อเหมือนกันและวัตถุดิบชุดเดียวกัน (หลังรวมแล้วกลายเป็นซ้ำ)
with s as (
  select r.id, r.name_key, r.use_count,
         (select array_agg(distinct ri.ingredient_id order by ri.ingredient_id)
            from public.recipe_ingredients ri where ri.recipe_id = r.id) as ids
  from public.recipes r
  where r.is_public
)
select name_key, count(*) as recipes, array_agg(id order by use_count desc) as recipe_ids
from s
group by name_key, ids
having count(*) > 1;
