-- เติมวันที่เข้าตู้เย็น (created_at) ให้วัตถุดิบที่ยังไม่มีวันที่
-- วันจริงไม่ได้ถูกบันทึกไว้ จึงตั้งเป็น "ตอนนี้" — นับวันในตู้เย็นจะเริ่มจากวันนี้
-- แค่เติมข้อมูล ไม่แก้โครงสร้างตาราง
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run

-- 1) ดูก่อนว่ามีกี่ชิ้น ชิ้นไหนบ้าง
select item_id, name, storage, created_at
from public.fridge_items
where created_at is null
order by name;

-- 2) เติมวันที่เป็นตอนนี้
update public.fridge_items
set created_at = now()
where created_at is null;

-- 3) เช็กอีกรอบ ต้องได้ 0
select count(*) as still_missing
from public.fridge_items
where created_at is null;
