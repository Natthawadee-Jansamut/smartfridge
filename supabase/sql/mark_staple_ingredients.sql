-- ตั้ง ingredients.is_staple = true ให้ "ของพื้นฐาน" ที่บ้านส่วนใหญ่มีอยู่แล้ว
-- (ข้าว เครื่องปรุง น้ำมัน ฯลฯ) แอปจะถือว่ามีในบ้าน ไม่ใส่ในรายการซื้อของของแพลน
-- และติ๊กว่ามีในหน้าทำอาหาร
--
-- - ชื่อที่มีในตารางแล้ว (เทียบ name_key ด้วย normalize_text) -> ตั้ง is_staple = true
-- - ชื่อที่ยังไม่มี -> เพิ่มแถวใหม่พร้อม is_staple = true
-- ไม่สร้างตาราง ไม่แก้โครงสร้าง รันซ้ำได้
--
-- ตั้งแต่ migration 20261108000000_auto_staple_ingredients.sql วัตถุดิบใหม่ที่ชื่อตรง
-- private.staple_names ได้ is_staple = true อัตโนมัติแล้ว ไฟล์นี้ใช้เมื่ออยากเพิ่มแถวของพื้นฐาน
-- ล่วงหน้า หรือรีเซ็ตรายการ "ไม่ใช่ของพื้นฐาน" ด้านล่าง
-- ถ้าเพิ่มชื่อของพื้นฐานใหม่ ให้เพิ่มใน private.staple_names ด้วย ไม่งั้นแถวใหม่จะยังได้ false
--
-- วิธีใช้: Supabase Dashboard -> SQL Editor -> วางทั้งไฟล์ -> Run
-- เพิ่ม/ลดรายการได้ที่ values ด้านล่าง หรือแก้ is_staple ใน Table Editor ได้ตลอด

drop table if exists _staples;
create temporary table _staples (name text);

-- จับคู่แบบชื่อตรงกัน (name_key) จึงใส่ชื่อสั้นไว้ด้วย เช่น 'น้ำตาล', 'ซีอิ๊ว'
-- ให้ตรงกับชื่อที่ save_recipe() สร้างจากสูตร และรายการสำรองในแอป
-- (lib/services/shopping_suggestion.dart: ShoppingSuggestion.staples)
insert into _staples (name) values
  ('ข้าว'), ('ข้าวสวย'), ('ข้าวสาร'), ('ข้าวหอมมะลิ'), ('ข้าวกล้อง'),
  ('น้ำมัน'), ('น้ำมันพืช'), ('น้ำมันหอย'), ('น้ำปลา'),
  ('ซีอิ๊ว'), ('ซีอิ๊วขาว'), ('ซีอิ๊วดำ'), ('ซอสหอยนางรม'), ('ซอสปรุงรส'), ('ซอสมะเขือเทศ'), ('ซอสพริก'),
  ('เกลือ'), ('น้ำตาล'), ('น้ำตาลทราย'), ('น้ำตาลปี๊บ'),
  ('พริกไทย'), ('ผงปรุงรส'), ('ผงชูรส'),
  ('น้ำ'), ('น้ำเปล่า');

-- ของที่ไม่ใช่ทุกบ้านจะมี -> ไม่นับเป็นของพื้นฐาน (ต้องซื้อถ้าไม่มีในตู้)
-- ถ้าเคยรันไฟล์เวอร์ชันก่อนที่ตั้งพวกนี้เป็น is_staple ไว้ จะถูกตั้งกลับเป็น false
update public.ingredients
set is_staple = false
where is_staple
  and name_key in (
    select public.normalize_text(n) from (values
      ('ซุปก้อน'), ('กระเทียม'), ('หอมแดง'), ('พริกขี้หนู'), ('พริกป่น'),
      ('มะนาว'), ('น้ำส้มสายชู'), ('แป้งมัน'), ('แป้งสาลี'), ('เนย')
    ) v(n)
  );

-- 1) ชื่อที่มีอยู่แล้ว -> ตั้งเป็นของพื้นฐาน
update public.ingredients i
set is_staple = true
where i.name_key in (select public.normalize_text(s.name) from _staples s)
  and i.is_staple = false;

-- 2) ชื่อที่ยังไม่มี -> เพิ่มใหม่
insert into public.ingredients (name, is_staple)
select s.name, true
from _staples s
where not exists (
  select 1 from public.ingredients i
  where i.name_key = public.normalize_text(s.name)
);

-- 3) ดูผล
select id, name, is_staple
from public.ingredients
where is_staple
order by name;

drop table if exists _staples;
