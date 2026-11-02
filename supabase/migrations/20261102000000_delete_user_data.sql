-- ลบข้อมูลทั้งหมดของผู้ใช้ในครั้งเดียว ถ้าตารางใดลบไม่ได้จะยกเลิกทั้งหมด
-- เรียกได้จาก Edge Function delete-user (service_role) เท่านั้น
create or replace function public.delete_user_data(target_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.weekly_meals
  where plan_id in (
    select id from public.meal_plans where user_id = target_user
  );
  delete from public.meal_plans where user_id = target_user;
  delete from public.scanned_recipes where user_id = target_user;
  delete from public.fridge_items where user_id = target_user;
end;
$$;

revoke all on function public.delete_user_data(uuid) from public, anon, authenticated;
grant usage on schema public to service_role;
grant execute on function public.delete_user_data(uuid) to service_role;
