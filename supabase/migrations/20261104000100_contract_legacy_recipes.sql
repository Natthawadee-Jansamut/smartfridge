-- =============================================================================
-- SmartFridge.AI — ขั้นที่ 2: CONTRACT
--
-- !! ยังไม่ต้องรัน !! รันเมื่อ:
--   1. รัน 20261104000000_global_recipes.sql แล้ว
--   2. แอปเวอร์ชันใหม่ (อ่านสูตรจาก my_saved_recipes() / บันทึกด้วย save_recipe()
--      / แพลนอาหารผูก weekly_meals.recipe_id) ขึ้น Store และผู้ใช้อัปเดตกันแล้ว
-- ถ้ารันก่อน แอปเวอร์ชันเก่าจะบันทึก/อ่านสูตรไม่ได้ (scanned_recipes ถูกเปลี่ยนชื่อ)
--
-- ไม่ลบข้อมูลใดๆ: scanned_recipes เปลี่ยนชื่อเป็น scanned_recipes_legacy (อ่านอย่างเดียว)
-- ย้อนกลับได้ด้วย: alter table public.scanned_recipes_legacy rename to scanned_recipes;
--                  แล้ว grant insert, update, delete กลับให้ authenticated
-- =============================================================================

begin;

-- 1) เก็บแถวที่แอปเวอร์ชันเก่าเขียนเพิ่มหลังขั้นที่ 1 เข้าตารางกลางให้ครบก่อน
select private.migrate_legacy_data() as migrate_result;

-- 2) scanned_recipes -> คลังเก่าแบบอ่านอย่างเดียว
--    (หน้าที่ "Log การเรียก AI" ย้ายไปอยู่ที่ ai_request_logs แล้ว)
alter table public.scanned_recipes rename to scanned_recipes_legacy;
revoke insert, update, delete, truncate on public.scanned_recipes_legacy from anon, authenticated;
comment on table public.scanned_recipes_legacy is
  'เลิกใช้แล้ว — สูตรทั้งหมดย้ายไป recipes + user_saved_recipes (ดู global_recipe_id). เก็บไว้อ้างอิงเท่านั้น';

-- 3) weekly_meals: สูตรอ่านจาก recipes ผ่าน recipe_id แล้ว
--    คอลัมน์สูตรเดิมไม่บังคับกรอกอีกต่อไป (ยังเก็บไว้ ไม่ลบ)
alter table public.weekly_meals alter column food_name drop not null;
alter table public.weekly_meals alter column ingredients drop not null;
alter table public.weekly_meals alter column steps drop not null;
alter table public.weekly_meals alter column calories drop not null;
alter table public.weekly_meals alter column protein drop not null;

comment on column public.weekly_meals.food_name is 'เลิกใช้แล้ว — ใช้ recipes.name ผ่าน recipe_id';
comment on column public.weekly_meals.steps is 'เลิกใช้แล้ว — ใช้ recipes.instructions ผ่าน recipe_id';
comment on column public.weekly_meals.calories is 'เลิกใช้แล้ว — ใช้ recipes.calories_per_serving ผ่าน recipe_id';
comment on column public.weekly_meals.protein is 'เลิกใช้แล้ว — ใช้ recipes.protein_per_serving ผ่าน recipe_id';
comment on column public.weekly_meals.ingredients is
  'ใช้เฉพาะสถานะ checked ของมื้อนี้ — รายการวัตถุดิบจริงอยู่ที่ recipe_ingredients ผ่าน recipe_id';

commit;
