-- =============================================================================
-- ลบข้อมูลทั้งหมดของผู้ใช้ 1 คน (เรียกจาก Edge Function delete-user เท่านั้น)
--
-- รันใน Supabase SQL Editor ได้ซ้ำ (create or replace) — แทนฉบับเดิมที่:
--   1. ไม่ลบสูตรส่วนตัวในตาราง recipes (ตอนลบบัญชี created_by แค่กลายเป็น null
--      ตัวสูตรค้างอยู่ ทั้งที่แอปบอกว่าข้อมูลทั้งหมดจะถูกลบ)
--   2. พังถ้ารัน migration ขั้นที่ 2 (scanned_recipes ถูกเปลี่ยนชื่อเป็น
--      scanned_recipes_legacy) -> ลบบัญชีไม่ได้เลย
--   3. ไม่ได้ปิดสิทธิ์: ผู้ใช้ที่ล็อกอินอยู่อาจเรียก rpc('delete_user_data') เอง
--      แล้วส่ง id ของคนอื่นมาลบข้อมูลของเขาได้ (Postgres ให้ทุกคน execute
--      ฟังก์ชันได้โดยค่าเริ่มต้น)
--
-- ข้อมูลที่ไม่ต้องลบในนี้ (ลบเองตอน Edge Function ลบ auth user — on delete cascade):
--   user_saved_recipes, ai_request_logs
-- สูตรสาธารณะที่ผู้ใช้เคยทำให้เกิด (is_public = true) เก็บไว้ในคลังกลางให้คนอื่น
-- ใช้ต่อ (created_by เป็น null) — เป็นเมนูที่ AI สร้าง ไม่ใช่ข้อมูลส่วนตัว
-- รูปใน Storage ลบที่ Edge Function
-- =============================================================================

create or replace function public.delete_user_data(target_user uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if target_user is null then
    raise exception 'target_user is required';
  end if;

  delete from public.weekly_meals
  where plan_id in (
    select id from public.meal_plans where user_id = target_user
  );
  delete from public.meal_plans where user_id = target_user;

  -- ตารางสูตรแบบเก่า: ก่อนรัน migration ขั้นที่ 2 ชื่อ scanned_recipes
  -- หลังรันชื่อ scanned_recipes_legacy — ลบเฉพาะตารางที่มีอยู่จริง
  if to_regclass('public.scanned_recipes') is not null then
    execute 'delete from public.scanned_recipes where user_id = $1'
      using target_user;
  end if;
  if to_regclass('public.scanned_recipes_legacy') is not null then
    execute 'delete from public.scanned_recipes_legacy where user_id = $1'
      using target_user;
  end if;

  delete from public.fridge_items where user_id = target_user;

  -- สูตรส่วนตัว (สแกนจากตำรา / เขียนเอง / แก้แล้ว) — คนอื่นมองไม่เห็นอยู่แล้ว
  -- recipe_ingredients ลบตาม (cascade), อ้างอิงจากตารางอื่นกลายเป็น null
  delete from public.recipes
  where created_by = target_user
    and is_public = false;
end;
$function$;

-- เรียกได้เฉพาะ service role (Edge Function) — ผู้ใช้ทั่วไปเรียกเองไม่ได้
revoke all on function public.delete_user_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_user_data(uuid) to service_role;

-- ตรวจสิทธิ์หลังรัน: ควรเหลือแค่ postgres กับ service_role
-- select grantee, privilege_type
--   from information_schema.routine_privileges
--  where routine_schema = 'public' and routine_name = 'delete_user_data';
