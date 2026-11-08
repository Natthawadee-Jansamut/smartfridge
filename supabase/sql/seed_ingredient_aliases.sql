-- เติม ingredient_aliases (ชื่อเรียกอื่นของวัตถุดิบเดียวกัน) กลับเข้าไป
--
-- ทำไมต้องมี: resolve_ingredient_id() ใช้ alias แปลงชื่อ -> id มาตรฐาน
--   "ไข่" กับ "ไข่ไก่" จะได้ id เดียวกัน ทำให้
--   - save_recipe() ไม่สร้างวัตถุดิบซ้ำ (ชื่อที่เป็น alias แล้วจะไม่ถูกเพิ่มเป็นแถวใหม่)
--   - fridge_items.ingredient_id ตรงกับ recipe_ingredients.ingredient_id
--   - สูตรเดียวกันที่สะกดวัตถุดิบต่างกันได้ลายเซ็นเดียวกัน
--
-- ตารางนี้ไม่มีอะไรเขียนให้อัตโนมัติ และ ingredient_id เป็น ON DELETE CASCADE
-- ถ้าล้างตาราง ingredients แล้ว alias จะหายตาม ต้องรันไฟล์นี้ใหม่
--
-- รันซ้ำได้: วัตถุดิบมาตรฐานที่ยังไม่มีจะถูกเพิ่ม, alias ที่มีแล้วข้าม
-- ข้าม alias ที่ชื่อซ้ำกับวัตถุดิบที่มีอยู่แล้ว (resolve_ingredient_id เลือกชื่อวัตถุดิบก่อน alias
-- จึงไม่มีผล — ถ้าต้องการรวม 2 แถวที่ซ้ำกันอยู่แล้ว ต้องย้าย id ใน recipe_ingredients /
-- fridge_items ก่อน ซึ่งไม่ได้ทำในไฟล์นี้)
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run
-- เพิ่มคู่ใหม่ได้ที่ values ด้านล่าง (alias, ชื่อมาตรฐาน)

begin;

create temporary table _aliases (alias text, canonical text) on commit drop;

insert into _aliases (alias, canonical) values
  -- ชุดเดิมจาก migration 20261104000000_global_recipes.sql
  ('ไข่',             'ไข่ไก่'),
  ('หมูบด',           'หมูสับ'),
  ('เนื้ออกไก่',      'อกไก่'),
  ('อกไก่ลอกหนัง',    'อกไก่'),
  ('กระเทียมไทย',     'กระเทียม'),
  ('หอมต้น',          'ต้นหอม'),
  -- เพิ่มเติม
  ('ไข่ไก่สด',        'ไข่ไก่'),
  ('อกไก่ไม่มีหนัง',  'อกไก่'),
  ('กระเทียมสับ',     'กระเทียม'),
  ('นมจืด',           'นมสด'),
  ('นมวัว',           'นมสด'),
  ('ข้าวสวยหุงสุก',   'ข้าวสวย');
-- ไม่ใส่ 'น้ำ' / 'น้ำตาลทราย' เป็น alias เพราะ mark_staple_ingredients.sql เพิ่มชื่อเหล่านี้
-- เป็นวัตถุดิบของพื้นฐานแยกไว้แล้ว

-- 1) วัตถุดิบมาตรฐานที่ยังไม่มี -> เพิ่ม (trigger ingredients_set_staple ตั้ง is_staple ให้ถ้าเป็นของพื้นฐาน)
insert into public.ingredients (name)
select distinct a.canonical
from _aliases a
where not exists (
  select 1 from public.ingredients i
  where i.name_key = public.normalize_text(a.canonical)
)
on conflict (name_key) do nothing;

-- 2) alias -> id ของวัตถุดิบมาตรฐาน
insert into public.ingredient_aliases (alias, ingredient_id)
select a.alias, i.id
from _aliases a
join public.ingredients i on i.name_key = public.normalize_text(a.canonical)
where not exists (
  select 1 from public.ingredients x
  where x.name_key = public.normalize_text(a.alias)
)
on conflict (alias_key) do nothing;

commit;

-- 3) ดูผล (alias ที่ไม่ขึ้นในรายการ = ถูกข้ามเพราะมีวัตถุดิบชื่อนั้นอยู่แล้ว)
select a.alias, i.name as canonical
from public.ingredient_aliases a
join public.ingredients i on i.id = a.ingredient_id
order by i.name, a.alias;
