-- =============================================================================
-- SmartFridge.AI — แพลนโปรดเป็นคอลัมน์ meal_plans.is_favorite
--
-- เดิม: id ของแพลนโปรดเก็บเป็น array ใน auth.users.raw_user_meta_data.favorite_plan_ids
-- ใหม่: meal_plans.is_favorite (boolean) — แอป (MyPlanScreen) อ่าน/เขียนคอลัมน์นี้
--
-- ต้องรันไฟล์นี้ก่อนใช้แอปเวอร์ชันที่อ่าน is_favorite
-- (ถ้ายังไม่รัน แอปจะไม่เห็นแพลนโปรด และกดหัวใจแล้วขึ้น error)
--
-- ไม่ลบ favorite_plan_ids ออกจาก user_metadata — แอปเวอร์ชันเก่ายังอ่านได้ตามเดิม
-- รันซ้ำได้ · รันทั้งไฟล์ใน Supabase SQL Editor (ทำใน transaction เดียว)
-- =============================================================================

begin;

alter table public.meal_plans
  add column if not exists is_favorite boolean not null default false;

-- ย้ายแพลนโปรดเดิมจาก user_metadata
update public.meal_plans p
set is_favorite = true
from auth.users u
where p.user_id = u.id
  and not p.is_favorite
  and jsonb_typeof(u.raw_user_meta_data -> 'favorite_plan_ids') = 'array'
  and (u.raw_user_meta_data -> 'favorite_plan_ids') ? p.id::text;

-- หน้าแผนของฉัน: แพลนที่บันทึกแล้วของผู้ใช้ เรียงใหม่ไปเก่า
create index if not exists meal_plans_user_created_idx
  on public.meal_plans (user_id, created_at desc);

commit;

-- ดูผล
select p.id, p.goal, p.saved, p.is_favorite, p.created_at, u.email
from public.meal_plans p
join auth.users u on u.id = p.user_id
where p.is_favorite
order by u.email, p.created_at desc;
