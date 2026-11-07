-- ให้ recipe_ingredients.ingredient_id ว่างได้ (เหมือน fridge_items.ingredient_id)
--
-- เหตุผล: ตาราง ingredients เป็น "พจนานุกรมชื่อวัตถุดิบกลาง" ที่ทุกคนใช้ร่วมกัน
-- จะเพิ่มชื่อใหม่ลงไปได้เฉพาะตอนบันทึกสูตรที่มาจาก AI และไม่ได้แก้ไขอะไรเลย
-- สูตรส่วนตัว (เขียนเอง / แก้แล้ว) จะแค่ค้นหาชื่อในพจนานุกรม ถ้าไม่เจอให้ช่องนี้ว่างไว้
-- ชื่อวัตถุดิบยังอยู่ใน display_name ครบ
--
-- ปลอดภัย: primary key ของตารางนี้คือ (recipe_id, sort_order) ไม่ได้ใช้ ingredient_id
-- foreign key ไป ingredients(id) ยังอยู่เหมือนเดิม (ค่าว่าง = ยังไม่ได้จับคู่)

alter table public.recipe_ingredients
  alter column ingredient_id drop not null;
