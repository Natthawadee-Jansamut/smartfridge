-- =============================================================================
-- SmartFridge.AI — ตั้ง ingredients.is_staple ให้อัตโนมัติเมื่อเพิ่มวัตถุดิบใหม่
--
-- ปัญหาเดิม: save_recipe() (private.upsert_global_recipe) เพิ่มวัตถุดิบชื่อใหม่ด้วย
--   insert into public.ingredients (name) ...
-- จึงได้ is_staple = false เสมอ ของพื้นฐานอย่างน้ำปลา น้ำตาล ซีอิ๊ว ถูกนับเป็น "ของที่ขาด"
-- ใน match_recipes_by_ingredients() แล้วสูตรที่ใช้เครื่องปรุงเยอะถูกคัดทิ้ง
--
-- ไฟล์นี้:
--   1) private.staple_names        รายชื่อของพื้นฐาน (แก้/เพิ่มที่ตารางนี้ที่เดียว)
--   2) private.is_staple_name()    เช็กว่าชื่อเป็นของพื้นฐานไหม
--   3) trigger ingredients_set_staple   ทุกครั้งที่เพิ่มแถวใน ingredients (รวมจาก save_recipe)
--      ถ้าชื่อตรงรายการ -> ตั้ง is_staple = true ให้
--   4) ตั้งค่าให้แถวที่มีอยู่แล้ว
--
-- ไม่แก้ save_recipe() / upsert_global_recipe() และไม่แก้แอป
-- trigger ทำงานเฉพาะตอน INSERT — ผู้ดูแลยังปิด is_staple เองใน Table Editor ได้ตามปกติ
-- รันซ้ำได้ · รันทั้งไฟล์ใน Supabase SQL Editor (ทำใน transaction เดียว)
-- =============================================================================

begin;

create schema if not exists private;

-- -----------------------------------------------------------------------------
-- 1) รายชื่อของพื้นฐาน
--    match_prefix = true  -> ชื่อที่ขึ้นต้นด้วยคำนี้ก็นับ เช่น ซีอิ๊ว -> ซีอิ๊วขาว, ซีอิ๊วดำ
--    match_prefix = false -> ต้องตรงทั้งคำ (ใช้กับคำสั้นที่ขึ้นต้นของสดได้ เช่น
--                            ข้าว -> ข้าวโพด, น้ำ -> น้ำมะนาว ไม่ใช่ของพื้นฐาน)
--    ให้ตรงกับรายการสำรองในแอป lib/services/shopping_suggestion.dart (ShoppingSuggestion.staples)
-- -----------------------------------------------------------------------------
create table if not exists private.staple_names (
  name_key     text primary key,
  name         text not null,
  match_prefix boolean not null default false
);

revoke all on private.staple_names from anon, authenticated;

insert into private.staple_names (name_key, name, match_prefix)
select public.normalize_text(v.name), v.name, v.match_prefix
from (values
  ('ข้าว',        false),
  ('ข้าวสวย',     true),
  ('ข้าวสาร',     true),
  ('ข้าวหอมมะลิ', true),
  ('ข้าวกล้อง',   true),
  ('น้ำ',         false),
  ('น้ำเปล่า',    false),
  ('น้ำมัน',      true),   -- น้ำมันพืช, น้ำมันหอย, น้ำมันมะกอก
  ('น้ำปลา',      true),
  ('น้ำตาล',      true),   -- น้ำตาลทราย, น้ำตาลปี๊บ
  ('ซีอิ๊ว',      true),   -- ซีอิ๊วขาว, ซีอิ๊วดำ
  ('ซอส',         true),   -- ซอสหอยนางรม, ซอสปรุงรส, ซอสมะเขือเทศ, ซอสพริก
  ('เกลือ',       true),
  ('พริกไทย',     true),
  ('ผงปรุงรส',    true),
  ('ผงชูรส',      true)
) as v(name, match_prefix)
on conflict (name_key) do update
  set name = excluded.name,
      match_prefix = excluded.match_prefix;


-- -----------------------------------------------------------------------------
-- 2) ชื่อนี้เป็นของพื้นฐานไหม (เทียบหลัง normalize_text: ไม่สนช่องว่าง/เครื่องหมาย)
-- -----------------------------------------------------------------------------
create or replace function private.is_staple_name(p_name text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
      from private.staple_names s,
           (select public.normalize_text(p_name) as k) x
     where x.k is not null
       and (x.k = s.name_key
            or (s.match_prefix and starts_with(x.k, s.name_key)))
  );
$$;


-- -----------------------------------------------------------------------------
-- 3) trigger: เพิ่มวัตถุดิบใหม่ที่เป็นของพื้นฐาน -> is_staple = true
--    (ค่า default false ถูกใส่ก่อน BEFORE trigger ทำงาน จึงเช็ก new.is_staple ได้เลย)
-- -----------------------------------------------------------------------------
create or replace function private.ingredients_set_staple()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(new.is_staple, false) and private.is_staple_name(new.name) then
    new.is_staple := true;
  end if;
  return new;
end;
$$;

drop trigger if exists ingredients_set_staple on public.ingredients;
create trigger ingredients_set_staple
  before insert on public.ingredients
  for each row execute function private.ingredients_set_staple();


-- -----------------------------------------------------------------------------
-- 4) แถวที่มีอยู่แล้ว
-- -----------------------------------------------------------------------------
update public.ingredients
set is_staple = true
where not is_staple
  and private.is_staple_name(name);

commit;

-- ดูผล
select id, name, is_staple
from public.ingredients
where is_staple
order by name;
