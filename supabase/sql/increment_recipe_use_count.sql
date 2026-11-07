-- เพิ่ม recipes.use_count ทีละ 1 เมื่อมีผู้ใช้บันทึกสูตรที่มีอยู่แล้วเข้าคลังของตัวเอง
--
-- ทำไมต้องเป็นฟังก์ชัน: policy ของ recipes ให้แก้ได้เฉพาะสูตรที่ตัวเองสร้าง
-- ฟังก์ชันนี้รันด้วยสิทธิ์เจ้าของ (security definer) แต่ทำได้อย่างเดียวคือ +1 ที่ use_count
-- ไม่สร้างตาราง และไม่แก้โครงสร้างตาราง
--
-- กันการกดนับเล่น: นับได้เฉพาะสูตรที่ผู้เรียกบันทึกไว้ในคลังของตัวเองจริง
-- และสูตรนั้นต้องเป็นสูตรสาธารณะ หรือเป็นสูตรของผู้เรียกเอง
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run
-- แอปเรียกผ่าน: supabase.rpc('increment_recipe_use_count', params: {'p_recipe_id': id})

create or replace function public.increment_recipe_use_count(p_recipe_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  update public.recipes r
  set use_count = r.use_count + 1
  where r.id = p_recipe_id
    and (r.is_public or r.created_by = auth.uid())
    and exists (
      select 1
      from public.user_saved_recipes s
      where s.recipe_id = p_recipe_id
        and s.user_id = auth.uid()
    );
end;
$$;

revoke all on function public.increment_recipe_use_count(uuid) from public, anon;
grant execute on function public.increment_recipe_use_count(uuid) to authenticated;
