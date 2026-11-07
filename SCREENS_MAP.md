# แผนที่หน้าจอ (Screens Map) - SmartFridge.AI

ไฟล์ใน `lib/screens/` แยกโฟลเดอร์ตามเมนูในหน้า Home

## 🏠 `home/` — หน้าหลักและหน้ารวมเมนู
- `main_menu_screen.dart` — หน้าเมนูหลัก มีปุ่มลิงก์ไปทุกฟีเจอร์
- `scan_menu_screen.dart` — แท็บ "สแกน" ใน bottom nav (เปิดได้ทั้งฟีเจอร์ 1 และ 5)

## 📷 `ingredient_scan/` — 1. ถ่ายภาพวัตถุดิบ
- `image_scanning_screen.dart` — ถ่ายภาพวัตถุดิบ วิเคราะห์ด้วย Gemini (เดิมชื่อ `ImageScanning.dart`)
- `result_screen.dart` — ผลลัพธ์วัตถุดิบที่สแกนได้ (ก่อนบันทึกเข้าคลัง)

## 📅 `meal_plan/` — 2. แพลนอาหาร
- `plan_menu_screen.dart` — เมนูเลือกว่าจะวางแผนแบบไหน
- `meal_plan_screen.dart` — สร้างแผนมื้ออาหารรายสัปดาห์ด้วย AI
- `my_plan_screen.dart` — แผนมื้ออาหารของฉัน (ภาพรวม)
- `weekly_plan_screen.dart` — ดูแผนมื้ออาหารที่สร้างไว้รายสัปดาห์
- `cook_meal_screen.dart` — หน้าทำอาหารตามสูตร ทีละขั้นตอน

## 🔔 `notification/` — 3. แจ้งเตือน
- `expiration_alert_screen.dart` — แจ้งเตือนวัตถุดิบที่อยู่ในตู้เย็นนาน
- `notification_settings_screen.dart` — ตั้งค่าการแจ้งเตือน

## 🧊 `fridge/` — 4. เช็คตู้เย็น
- `inventory_screen.dart` — รายการวัตถุดิบทั้งหมดในตู้เย็น
- `item_detail_screen.dart` — รายละเอียด/แก้ไขวัตถุดิบทีละชิ้น

## 📖 `recipe_scan/` — 5. สแกนสูตรอาหาร
- `scan_recipe_screen.dart` — ถ่ายภาพสูตรอาหาร วิเคราะห์ด้วย Gemini
- `scan_recipe_result_screen.dart` — ผลลัพธ์สูตรที่สแกนได้ เทียบกับรูปต้นฉบับ
- `saved_recipes_screen.dart` — คลังสูตรอาหารที่บันทึกไว้
- `manual_recipe_screen.dart` — เขียนสูตรเอง / แก้สูตรจาก AI

## 🍳 `menu_generator/` — 6. สร้างเมนูอาหาร
- `ai_recipe_screen.dart` — ให้ AI แนะนำเมนูจากวัตถุดิบที่มี

## 🔗 `shared/` — หน้าที่หลายฟีเจอร์ใช้ร่วมกัน
- `recipe_detail_screen.dart` — รายละเอียดสูตร + แก้ไข + ปุ่มเริ่มทำ (ฟีเจอร์ 5 และ 6)

## 🔐 `auth/` — ระบบสมาชิก
- `login_screen.dart` — หน้าล็อกอิน (มี Remember me)
- `register_screen.dart` — หน้าสมัครสมาชิก (เดิมชื่อ `register.dart`)
- `forgot_password_screen.dart` — ขอลิงก์รีเซ็ตรหัสผ่าน
- `reset_password_screen.dart` — ตั้งรหัสผ่านใหม่ (จากลิงก์อีเมล)
- `verify_email_otp_screen.dart` — ยืนยัน OTP ทางอีเมลหลังสมัคร

## 👤 `profile/` — โปรไฟล์ & ตั้งค่าบัญชี
- `profile_screen.dart` — หน้าโปรไฟล์ผู้ใช้
- `edit_profile_screen.dart` — แก้ไขข้อมูลโปรไฟล์
- `change_password_screen.dart` — เปลี่ยนรหัสผ่าน (ตอนล็อกอินอยู่)
- `delete_account_screen.dart` — ลบบัญชี

---
### ไฟล์ระบบสำคัญที่เกี่ยวข้อง
- `lib/main.dart` — จุดเริ่มต้นแอป
- `lib/services/notification_service.dart` — จัดการแจ้งเตือน local notification
- `lib/config/api_keys.dart` — เก็บ API Key (ไม่ขึ้น git)
- `lib/config/supabase_config.dart` — URL และ anon key ของ Supabase (ไม่ขึ้น git, ดูตัวอย่างที่ `supabase_config.example.dart`)
- `lib/widgets/` — widget ที่ใช้ซ้ำหลายหน้า (bottom nav, header, icons)
- `lib/utils/category_icons.dart` — ไอคอนตามหมวดหมู่วัตถุดิบ
- `lib/utils/fridge_age.dart` — คำนวณว่าอยู่ในตู้เย็นมาแล้วกี่วัน / เหลืออีกกี่วันหมดอายุ / ลำดับ FIFO
- `lib/utils/shelf_life.dart` — ตารางอายุการเก็บรักษา (ช่องปกติ/แช่แข็ง, ดิบ/สุก ฯลฯ) ใช้เป็นค่าเริ่มต้นตอนสแกน
- `lib/services/fridge_stock.dart` — หักวัตถุดิบตามสัดส่วนแบบ FIFO (ลอตที่ใกล้หมดอายุก่อน)
- `supabase/fridge_items_storage.sql` — SQL เพิ่มคอลัมน์ storage / food_state / fridge_days / freezer_days
