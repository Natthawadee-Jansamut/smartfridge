-- 1) "ใช้ครั้งละ" สำหรับวัตถุดิบที่นับเป็นชิ้น
--    ผู้ใช้กำหนดไว้ว่าทำอาหาร 1 ครั้งใช้กี่ชิ้น (เช่น ไข่ ครั้งละ 2 ฟอง)
--    ใช้เป็นค่าเริ่มต้นตอนหักวัตถุดิบ ถ้าหน่วยในสูตรไม่ตรง หรือสูตรไม่บอกปริมาณ
--    (แบ่งเป็นส่วน ไม่ใช้ช่องนี้ เพราะ 1 ส่วน = ทำอาหาร 1 ครั้งอยู่แล้ว)
--
-- 2) รูปที่ผู้ใช้สแกนตอนเอาวัตถุดิบเข้าตู้เย็น
--    เก็บเป็น path ในที่เก็บไฟล์ fridge-images (ไม่ใช่ URL สาธารณะ)
--    รูปในบ้าน/ตู้เย็นเป็นของส่วนตัว จึงเปิดดูได้เฉพาะเจ้าของ
--
-- รันซ้ำได้

alter table public.fridge_items
  add column if not exists use_per_cook numeric check (use_per_cook > 0),
  add column if not exists image_path text;

-- ที่เก็บรูปแบบส่วนตัว (public = false)
insert into storage.buckets (id, name, public)
values ('fridge-images', 'fridge-images', false)
on conflict (id) do nothing;

-- ไฟล์อยู่ในโฟลเดอร์ชื่อ user id ของเจ้าของ: <user_id>/<ชื่อไฟล์>.jpg
drop policy if exists "fridge images: owner can read" on storage.objects;
create policy "fridge images: owner can read"
  on storage.objects for select to authenticated
  using (bucket_id = 'fridge-images'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "fridge images: owner can upload" on storage.objects;
create policy "fridge images: owner can upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'fridge-images'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "fridge images: owner can delete" on storage.objects;
create policy "fridge images: owner can delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'fridge-images'
         and (storage.foldername(name))[1] = auth.uid()::text);
