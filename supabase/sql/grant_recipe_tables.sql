-- สิทธิ์ที่ฟีเจอร์ "สแกนสูตรอาหาร / คลังสูตร" ต้องใช้ สำหรับผู้ใช้ที่ล็อกอินแล้ว (authenticated)
-- ไม่สร้างตารางใหม่ และไม่แก้โครงสร้างตาราง แค่เพิ่มสิทธิ์ + policy
-- รันซ้ำได้ (policy ชื่อเดียวกันจะถูกลบแล้วสร้างใหม่)
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run

-- ---------------------------------------------------------------------------
-- ingredients : รายชื่อวัตถุดิบกลาง (อ่านได้ทุกคน, เพิ่มชื่อใหม่ได้)
-- ---------------------------------------------------------------------------
grant select, insert on table public.ingredients to authenticated;

drop policy if exists "authenticated can read ingredients" on public.ingredients;
create policy "authenticated can read ingredients"
  on public.ingredients for select to authenticated
  using (true);

drop policy if exists "authenticated can add ingredients" on public.ingredients;
create policy "authenticated can add ingredients"
  on public.ingredients for insert to authenticated
  with check (true);

-- ingredient_aliases : ชื่อเรียกอื่น (อ่านอย่างเดียว)
grant select on table public.ingredient_aliases to authenticated;

drop policy if exists "authenticated can read ingredient aliases" on public.ingredient_aliases;
create policy "authenticated can read ingredient aliases"
  on public.ingredient_aliases for select to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- recipes : อ่านสูตรสาธารณะ + สูตรของตัวเอง, สร้าง/แก้/ลบได้เฉพาะสูตรที่ตัวเองสร้าง
-- (UPDATE ต้องมี เพราะ trigger ของ recipe_ingredients อัปเดต recipes.ingredient_ids)
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on table public.recipes to authenticated;

drop policy if exists "read public or own recipes" on public.recipes;
create policy "read public or own recipes"
  on public.recipes for select to authenticated
  using (is_public or created_by = auth.uid());

drop policy if exists "create own recipes" on public.recipes;
create policy "create own recipes"
  on public.recipes for insert to authenticated
  with check (created_by = auth.uid());

drop policy if exists "update own recipes" on public.recipes;
create policy "update own recipes"
  on public.recipes for update to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

drop policy if exists "delete own recipes" on public.recipes;
create policy "delete own recipes"
  on public.recipes for delete to authenticated
  using (created_by = auth.uid());

-- ---------------------------------------------------------------------------
-- recipe_ingredients : อ่านได้ถ้าอ่านสูตรนั้นได้, เพิ่ม/ลบได้เฉพาะสูตรของตัวเอง
-- ---------------------------------------------------------------------------
grant select, insert, delete on table public.recipe_ingredients to authenticated;

drop policy if exists "read ingredients of visible recipes" on public.recipe_ingredients;
create policy "read ingredients of visible recipes"
  on public.recipe_ingredients for select to authenticated
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and (r.is_public or r.created_by = auth.uid())
  ));

drop policy if exists "add ingredients to own recipes" on public.recipe_ingredients;
create policy "add ingredients to own recipes"
  on public.recipe_ingredients for insert to authenticated
  with check (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and r.created_by = auth.uid()
  ));

drop policy if exists "delete ingredients of own recipes" on public.recipe_ingredients;
create policy "delete ingredients of own recipes"
  on public.recipe_ingredients for delete to authenticated
  using (exists (
    select 1 from public.recipes r
    where r.id = recipe_id and r.created_by = auth.uid()
  ));

-- ---------------------------------------------------------------------------
-- user_saved_recipes : คลังสูตรของแต่ละคน (จัดการได้เฉพาะของตัวเอง)
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on table public.user_saved_recipes to authenticated;

drop policy if exists "manage own saved recipes" on public.user_saved_recipes;
create policy "manage own saved recipes"
  on public.user_saved_recipes for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- ai_request_logs : บันทึกการใช้ AI (เพิ่มและอ่านได้เฉพาะของตัวเอง)
-- ---------------------------------------------------------------------------
grant select, insert on table public.ai_request_logs to authenticated;

drop policy if exists "read own ai logs" on public.ai_request_logs;
create policy "read own ai logs"
  on public.ai_request_logs for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "add own ai logs" on public.ai_request_logs;
create policy "add own ai logs"
  on public.ai_request_logs for insert to authenticated
  with check (user_id = auth.uid());
