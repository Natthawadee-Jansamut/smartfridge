-- ที่เก็บรูปสูตรอาหารที่ผู้ใช้สแกน (แบบส่วนตัว)
--
-- รูปหน้าตำรา / สูตรลายมือเป็นของผู้ใช้ จึงไม่ผูกกับสูตรในห้องสมุดกลาง (recipes)
-- ที่อยู่ไฟล์เก็บใน user_saved_recipes.overrides -> 'scan_image_path'
-- ไฟล์อยู่ในโฟลเดอร์ชื่อ user id ของเจ้าของ: <user_id>/<ชื่อไฟล์>.jpg
-- เปิดดูได้เฉพาะเจ้าของ (แอปขอลิงก์ชั่วคราวตอนแสดงรูป)
--
-- ไม่ต้องเพิ่มคอลัมน์ใหม่ รันซ้ำได้

insert into storage.buckets (id, name, public)
values ('recipe-scan-images', 'recipe-scan-images', false)
on conflict (id) do nothing;

drop policy if exists "recipe scan images: owner can read" on storage.objects;
create policy "recipe scan images: owner can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'recipe-scan-images'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "recipe scan images: owner can upload" on storage.objects;
create policy "recipe scan images: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-scan-images'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "recipe scan images: owner can delete" on storage.objects;
create policy "recipe scan images: owner can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'recipe-scan-images'
         and (storage.foldername(name))[1] = auth.uid()::text);
