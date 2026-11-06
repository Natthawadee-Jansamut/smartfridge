-- ย้อนสิทธิ์ที่ grant_recipe_tables.sql (ไฟล์เก่า ลบออกจากโค้ดแล้ว) เคยเปิดไว้
-- กลับไปตามที่ migration ของทีมออกแบบ (20261104000000_global_recipes.sql):
--   ตารางกลาง (ingredients, ingredient_aliases, recipes, recipe_ingredients)
--   = ทุกคนอ่านได้ / เขียนผ่าน public.save_recipe() เท่านั้น
--
-- ไม่สร้าง/ลบตาราง ไม่แตะข้อมูล แค่ปิดสิทธิ์และลบ policy ที่ไฟล์เก่าสร้างไว้
-- policy ของทีม ("...: public read", "...: owner ...") ไม่ถูกแตะ รันซ้ำได้
--
-- ⚠️ รันหลังจากทุกคนใช้แอปเวอร์ชัน branch integrate-team-db แล้วเท่านั้น
--    แอปเวอร์ชันเก่า (เขียนตาราง recipes/ingredients ตรงๆ) จะบันทึกสูตรไม่ได้หลังรันไฟล์นี้
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run

-- ---------------------------------------------------------------------------
-- 1) ปิดสิทธิ์เขียนตารางกลาง (เหลือแค่อ่าน ตามที่ทีมกำหนด)
-- ---------------------------------------------------------------------------
revoke insert, update, delete, truncate
  on public.ingredients, public.ingredient_aliases, public.recipes, public.recipe_ingredients
  from anon, authenticated;

grant select
  on public.ingredients, public.ingredient_aliases, public.recipes, public.recipe_ingredients
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) ลบ policy ที่ grant_recipe_tables.sql สร้างไว้
--    (ทีมมี policy อ่านของตัวเองอยู่แล้ว: "ingredients: public read",
--     "recipes: public read", "recipe_ingredients: read with recipe" ฯลฯ)
-- ---------------------------------------------------------------------------
drop policy if exists "authenticated can read ingredients"        on public.ingredients;
drop policy if exists "authenticated can add ingredients"         on public.ingredients;
drop policy if exists "authenticated can read ingredient aliases" on public.ingredient_aliases;

drop policy if exists "read public or own recipes" on public.recipes;
drop policy if exists "create own recipes"         on public.recipes;
drop policy if exists "update own recipes"         on public.recipes;
drop policy if exists "delete own recipes"         on public.recipes;

drop policy if exists "read ingredients of visible recipes" on public.recipe_ingredients;
drop policy if exists "add ingredients to own recipes"      on public.recipe_ingredients;
drop policy if exists "delete ingredients of own recipes"   on public.recipe_ingredients;

-- ตารางของผู้ใช้: ทีมมี policy "user_saved_recipes: owner ..." และ
-- "ai_request_logs: owner ..." อยู่แล้ว -> ลบตัวซ้ำของไฟล์เก่า (สิทธิ์ไม่ลดลง)
drop policy if exists "manage own saved recipes" on public.user_saved_recipes;
drop policy if exists "read own ai logs"         on public.ai_request_logs;
drop policy if exists "add own ai logs"          on public.ai_request_logs;

-- ---------------------------------------------------------------------------
-- 3) ปิด TRUNCATE ของ user_saved_recipes (ค่าเริ่มต้นของ Supabase ที่ migration ทีมตกไป)
--    TRUNCATE ล้างทั้งตารางในคำสั่งเดียวและ RLS กันไม่ได้ -> ผู้ใช้คนไหนก็ลบคลังสูตร
--    ของทุกคนได้ แอปไม่ได้ใช้ TRUNCATE (ลบทีละแถวด้วย DELETE + RLS) จึงปิดได้เลย
-- ---------------------------------------------------------------------------
revoke truncate on public.user_saved_recipes from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) ตรวจผล: ตารางกลางต้องเหลือแค่ SELECT สำหรับ authenticated
--    user_saved_recipes ต้องไม่มี TRUNCATE
-- ---------------------------------------------------------------------------
select table_name, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where grantee = 'authenticated'
  and table_schema = 'public'
  and table_name in ('ingredients', 'ingredient_aliases', 'recipes', 'recipe_ingredients',
                     'user_saved_recipes', 'ai_request_logs')
group by table_name
order by table_name;
