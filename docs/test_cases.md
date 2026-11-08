# SmartFridge.AI — Test Cases

อัปเดตล่าสุด: 7 พ.ย. 2026 · อ้างอิงโค้ดใน `lib/` (branch `main`) และโครงสร้างตารางใน [data_dictionary.md](data_dictionary.md)

เอกสารนี้มี 3 ส่วน

1. **แผนที่ข้อมูล** — ทำอะไรในแอป แล้วข้อมูลไปเก็บที่ตาราง/คอลัมน์ไหน
2. **Test case แบบทดสอบด้วยมือ** — แบ่งตาม 7 กระบวนการใน DFD (P1–P7) แต่ละข้อบอกผลที่หน้าจอ และตาราง.คอลัมน์ที่ต้องเปลี่ยนในฐานข้อมูล
3. **Automated test ที่มีอยู่แล้ว** — `flutter test`

---

## วิธีใช้

**เตรียมก่อนทดสอบ**

- บัญชีทดสอบ 2 บัญชี (A, B) ใช้อีเมลที่รับ OTP ได้จริง — บัญชี B ใช้ทดสอบว่าข้อมูลไม่ข้ามบัญชี
- มือถือหรือ emulator ที่มีกล้อง (หรือรูปในเครื่อง) และเปิดสิทธิ์แจ้งเตือน
- เปิด Supabase → SQL Editor ไว้ตรวจข้อมูล (SQL Editor ใช้สิทธิ์ผู้ดูแล จึงเห็นทุกแถวโดยไม่ติด RLS)

**ตรวจข้อมูลของบัญชีทดสอบ** — แทน `test-a@example.com` ด้วยอีเมลบัญชีทดสอบ

```sql
-- id และข้อมูลใน user_metadata
select id, email, email_confirmed_at, raw_user_meta_data
from auth.users where email = 'test-a@example.com';

-- วัตถุดิบในตู้ของผู้ใช้ ใหม่สุดก่อน
select item_id, name, category, quantity, max_quantity, unit, storage, food_state,
       fridge_days, freezer_days, shelf_type, expiry_date, storage_changed_at,
       days_left_at_freeze, thawed_at, use_per_cook, image_path, ingredient_id, created_at
from public.fridge_items
where user_id = (select id from auth.users where email = 'test-a@example.com')
order by created_at desc;

-- สูตรที่บันทึก + สูตรกลาง
select s.id, s.is_favorite, s.overrides, s.created_at, r.name, r.source, r.is_public, r.image_hash, r.use_count
from public.user_saved_recipes s join public.recipes r on r.id = s.recipe_id
where s.user_id = (select id from auth.users where email = 'test-a@example.com')
order by s.created_at desc;

-- แผนอาหาร + จำนวนมื้อ
select p.id, p.goal, p.meals_per_day, p.target_calories, p.target_protein, p.diet_type, p.saved,
       count(w.id) as meals, count(*) filter (where w.is_cooked) as cooked
from public.meal_plans p left join public.weekly_meals w on w.plan_id = p.id
where p.user_id = (select id from auth.users where email = 'test-a@example.com')
group by p.id order by p.created_at desc;

-- log การเรียก AI ล่าสุด
select event_type, result, model, prompt_tokens, output_tokens, recipe_id, image_hash, created_at
from public.ai_request_logs
where user_id = (select id from auth.users where email = 'test-a@example.com')
order by created_at desc limit 20;
```

**ช่องผลทดสอบ:** ใส่ `Pass` / `Fail` และหมายเหตุในคอลัมน์ "ผล"

---

## 1. แผนที่ข้อมูล: ทำอะไร → เก็บที่ไหน

| การกระทำในแอป | หน้าจอ | ตาราง | คอลัมน์ที่เขียน |
|---|---|---|---|
| สมัครสมาชิก | RegisterScreen | `auth.users` | `email`, `encrypted_password`, `raw_user_meta_data.first_name / last_name / phone` |
| ยืนยัน OTP | VerifyEmailOtpScreen | `auth.users` | `email_confirmed_at` |
| แก้โปรไฟล์ | EditProfileScreen | `auth.users` | `raw_user_meta_data.first_name / last_name / phone` |
| เปลี่ยน/รีเซ็ตรหัสผ่าน | ChangePassword / ResetPassword | `auth.users` | `encrypted_password` |
| ตั้งค่าแจ้งเตือน | NotificationSettingsScreen | `auth.users` | `raw_user_meta_data.notify_days` |
| แอปแจ้งเตือนของใกล้หมด | (ตอนเปิดแอป) | `auth.users` | `raw_user_meta_data.last_expiry_notify_date` |
| Remember me | LoginScreen | ในเครื่อง (SharedPreferences) | `remember_me` — **ไม่ได้เก็บใน Supabase** |
| ลบบัญชี | DeleteAccountScreen | `auth.users` (ผ่าน Edge Function `delete-user`) | ลบแถว |
| บันทึกวัตถุดิบจากการสแกน | ResultScreen | `fridge_items` | `user_id, created_at, name, category, quantity, max_quantity, unit, detected_quantity, detected_unit, expiry_date, storage, food_state, fridge_days, freezer_days, shelf_type, use_per_cook, image_path` |
| รูปวัตถุดิบ | ResultScreen | Storage `fridge-images` | ไฟล์ `<user_id>/<เวลา>.jpg` |
| ผูกวัตถุดิบกับวัตถุดิบกลาง | (trigger ในฐานข้อมูล) | `fridge_items` | `ingredient_id` |
| ปรับจำนวน +/− | InventoryScreen | `fridge_items` | `quantity` |
| แก้จำนวน/หน่วย | ItemDetailScreen | `fridge_items` | `quantity, max_quantity, unit, use_per_cook` |
| ย้ายเข้าช่องแช่แข็ง | ItemDetailScreen | `fridge_items` | `storage='freezer', storage_changed_at, days_left_at_freeze` (+ `expiry_date`) |
| ย้ายออกจากช่องแช่แข็ง | ItemDetailScreen | `fridge_items` | `storage='fridge', storage_changed_at, thawed_at` (+ `expiry_date`) |
| แก้วันหมดอายุ (เลือกวันที่) | ItemDetailScreen | `fridge_items` | `expiry_date` |
| แก้จำนวนวันเก็บรักษา / ต่อเวลา | ShelfDaysDialog | `fridge_items` | `fridge_days` หรือ `freezer_days`, `expiry_date`, `shelf_type='custom:…'`, `days_left_at_freeze=null` |
| ลบวัตถุดิบ | Inventory / ExpirationAlert | `fridge_items` | ลบแถว |
| ทำอาหาร (หักวัตถุดิบ) | DeductConfirmSheet / CookMealScreen | `fridge_items` | `quantity` ลดลง — ถ้าเหลือ 0 **ลบแถว** |
| เมนูจาก AI / สแกนสูตร / เขียนสูตรเอง | AiRecipe / ScanRecipeResult / ManualRecipe | `recipes`, `recipe_ingredients` (+ `ingredients`) | ผ่าน RPC `save_recipe()` |
| บันทึกสูตรเข้าคลังของฉัน | (หลัง save_recipe) | `user_saved_recipes` | `user_id, recipe_id, overrides` |
| รูปสูตรที่สแกน | ScanRecipe | Storage `recipe-scan-images` | ไฟล์ + `user_saved_recipes.overrides.scan_image_path` |
| แก้สูตรที่บันทึก | ManualRecipeScreen (โหมดแก้) | `user_saved_recipes` | `overrides` |
| กดหัวใจสูตร | SavedRecipesScreen | `user_saved_recipes` | `is_favorite` |
| ลบสูตรออกจากคลัง | SavedRecipesScreen | `user_saved_recipes` | ลบแถว (สูตรใน `recipes` ยังอยู่) |
| ใช้สูตรซ้ำ | (RPC) | `recipes` | `use_count` +1 |
| สร้างแผนอาหาร | MealPlanScreen | `meal_plans` | `user_id, goal, meals_per_day, target_calories, target_protein, diet_type` (`saved=false`) |
| มื้อในแผน | MealPlanScreen | `weekly_meals` | `plan_id, day, meal_type, food_name, calories, protein, ingredients, steps, is_cooked=false, recipe_id` — วัตถุดิบที่ไม่มีในตู้ตอนสร้างแผนติดธง `"to_buy": true` ใน `ingredients` |
| รายการซื้อของ ("🛒 ต้องซื้อ") | WeeklyPlanScreen | — (**คำนวณใหม่ทุกครั้ง ไม่บันทึก**) | อ่าน `weekly_meals.ingredients` + `fridge_items` แล้วจองของในตู้ให้มื้อที่ใกล้ถึงก่อน ส่วนที่ขาด = ต้องซื้อ |
| บันทึกแผน | WeeklyPlanScreen | `meal_plans` | `saved=true` |
| กดหัวใจแผน | MyPlanScreen | `auth.users` | `raw_user_meta_data.favorite_plan_ids` |
| ติ๊กวัตถุดิบ / แก้ขั้นตอน | CookMealScreen | `weekly_meals` | `ingredients` / `steps` |
| ทำมื้อนี้แล้ว / ยกเลิก | CookMealScreen | `weekly_meals` | `is_cooked` |
| เปลี่ยนเมนู / คำนวณแคลอรีใหม่ | WeeklyPlanScreen | `weekly_meals` | `food_name, calories, protein, ingredients, steps, recipe_id` |
| ลบแผน | MyPlanScreen | `meal_plans`, `weekly_meals` | ลบผ่าน RPC `delete_meal_plan(plan_uuid)` |
| ทุกครั้งที่เรียก/ข้าม Gemini | หลายหน้า | `ai_request_logs` | `event_type, result, model, prompt_tokens, output_tokens, recipe_id, image_hash` |

ค่าที่ใช้ใน `ai_request_logs`:
`event_type` = `scan_ingredient` · `scan_recipe` · `generate_menu` · `meal_plan` —
`result` = `gemini` (เรียก AI จริง) · `cache_hit` (ใช้ของในคลัง ไม่เรียก AI) · `not_recipe` (รูปไม่ใช่สูตร) · `failed`

---

## 2. Test case

### P1 — จัดการผู้ใช้งาน (User Management)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P1-01 | สมัครสมาชิกสำเร็จ | กรอกชื่อ นามสกุล เบอร์ อีเมลใหม่ รหัส `Test@1234` | ไปหน้ากรอก OTP | `auth.users` มีแถวใหม่ `email_confirmed_at` = NULL, `raw_user_meta_data` มี `first_name, last_name, phone` | |
| TC-P1-02 | รหัสผ่านไม่ผ่านเงื่อนไข | ลองทีละแบบ: `Test@12`, `test@1234`, `TEST@1234`, `Test@abcd`, `Test12345` | ขึ้น `Minimum 8 characters` / `Add uppercase letter` / `Add lowercase letter` / `Add a number` / `Add special character !@#$%^&*` ตามลำดับ ไม่ส่งฟอร์ม | ไม่มีแถวใหม่ใน `auth.users` | |
| TC-P1-03 | อีเมลผิดรูปแบบ | `abc`, `abc@`, `abc@mail` | `Enter valid email` | ไม่มีแถวใหม่ | |
| TC-P1-04 | ช่องที่ต้องกรอกว่าง | เว้นชื่อหรือนามสกุล | `Required` | ไม่มีแถวใหม่ | |
| TC-P1-05 | ยืนยัน OTP ถูก | กรอก OTP 6 หลักจากอีเมล | `ยืนยันอีเมลสำเร็จ ✅` แล้วไปหน้า Login | `auth.users.email_confirmed_at` มีค่า | |
| TC-P1-06 | OTP ไม่ครบ / ผิด | กรอก 5 หลัก, กรอก 6 หลักผิด | `กรุณากรอกรหัส OTP 6 หลัก` / แจ้งว่าผิด | `email_confirmed_at` ยังเป็น NULL | |
| TC-P1-07 | Login สำเร็จ | อีเมล + รหัสที่ถูก | เข้าเมนูหลัก ทักทายด้วยชื่อ | `auth.users.last_sign_in_at` อัปเดต | |
| TC-P1-08 | Login รหัสผิด | รหัสผิด | แจ้ง Login ไม่สำเร็จ อยู่หน้าเดิม | ไม่มีการเปลี่ยนแปลง | |
| TC-P1-09 | Remember me เปิด | ติ๊ก Remember me → Login → ปิดแอปแล้วเปิดใหม่ | เข้าเมนูหลักทันที | ไม่มี (เก็บในเครื่อง `remember_me=true`) | |
| TC-P1-10 | Remember me ปิด | ไม่ติ๊ก → Login → ปิดแอปแล้วเปิดใหม่ | กลับไปหน้า Login | ไม่มี | |
| TC-P1-11 | ลืมรหัสผ่าน | กรอกอีเมล → เปิดลิงก์ในอีเมลบนมือถือ → ตั้งรหัสใหม่ `New@5678` | ลิงก์ `smartfridge://` เปิดแอปที่หน้าตั้งรหัสใหม่ → บันทึกแล้วกลับหน้า Login, รหัสใหม่ใช้ได้ รหัสเก่าใช้ไม่ได้ | `auth.users.encrypted_password` เปลี่ยน | |
| TC-P1-12 | ลืมรหัสผ่านไม่กรอกอีเมล | กดส่งโดยช่องว่าง | แจ้งให้กรอกอีเมล | ไม่มี | |
| TC-P1-13 | แก้โปรไฟล์ | เปลี่ยนชื่อ นามสกุล เบอร์ → บันทึก | หน้าโปรไฟล์และคำทักทายเปลี่ยนตาม | `raw_user_meta_data.first_name / last_name / phone` เปลี่ยน | |
| TC-P1-14 | เปลี่ยนรหัสผ่าน | ตั้งรหัสใหม่ที่ผ่านเงื่อนไข | `เปลี่ยนรหัสผ่านเรียบร้อย` | `encrypted_password` เปลี่ยน | |
| TC-P1-15 | ออกจากระบบ | โปรไฟล์ → ออกจากระบบ → ยืนยัน | กลับหน้า Login | ไม่มี (session ในเครื่องถูกล้าง) | |
| TC-P1-16 | ลบบัญชี | โปรไฟล์ → ลบบัญชี → ยืนยัน | ออกจากระบบ กลับหน้า Login, login ด้วยบัญชีเดิมไม่ได้ | แถวใน `auth.users` หายไป · ตรวจว่าแถวของผู้ใช้ใน `user_saved_recipes`, `ai_request_logs`, `weekly_meals`, `fridge_items`, `meal_plans` หายด้วย · `recipes.created_by` ของสูตรสาธารณะเป็น NULL | |

### P2 — ประมวลผลภาพวัตถุดิบ (Image Scanning)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P2-01 | สแกนวัตถุดิบ 1 อย่าง | ถ่ายรูปไข่ไก่ 10 ฟอง | การ์ดแสดงชื่อ หมวด จำนวน หน่วย ช่องเก็บ และจำนวนวันเก็บรักษา | `ai_request_logs` เพิ่ม 1 แถว `event_type='scan_ingredient'`, `result='gemini'`, มี `prompt_tokens/output_tokens` | |
| TC-P2-02 | บันทึกผลสแกน | กดบันทึกจาก TC-P2-01 | กลับหน้าก่อน ขึ้นข้อความบันทึกสำเร็จ ของอยู่ในตู้เย็น | `fridge_items` เพิ่ม 1 แถว: `name`, `category`, `quantity = max_quantity`, `unit`, `detected_quantity/unit`, `storage`, `fridge_days/freezer_days`, `expiry_date` = วันนี้ + จำนวนวัน (UTC), `created_at` ≈ ตอนนี้, `image_path` = `<user_id>/....jpg` · ไฟล์อยู่ใน bucket `fridge-images` | |
| TC-P2-03 | สแกนหลายอย่างในรูปเดียว | รูปมีไข่ นม แครอท | ได้การ์ดแยกตามชนิด | บันทึกแล้วได้แถวละชนิดใน `fridge_items` | |
| TC-P2-04 | แก้ผลก่อนบันทึก | เปลี่ยนชื่อ จำนวน หน่วย และเลือกช่องแช่แข็ง | ค่าที่แก้แสดงในการ์ด | แถวใหม่ใช้ค่าที่แก้ `storage='freezer'` และ `expiry_date` คิดจาก `freezer_days` | |
| TC-P2-05 | นับเป็นชิ้น + ใช้ครั้งละ | เลือกนับเป็นชิ้น จำนวน 6 ใช้ครั้งละ 2 | แสดง "ใช้ครั้งละ 2" | `unit` = หน่วยชิ้น (เช่น `ฟอง`), `use_per_cook=2` | |
| TC-P2-06 | ไม่นับเป็นชิ้น | หน่วยเป็นกรัม/ขีด | เก็บเป็น "ส่วน" | `unit='ส่วน'`, `use_per_cook` = NULL | |
| TC-P2-07 | แก้จำนวนวันเก็บเอง | แก้จำนวนวันในการ์ดเป็น 4 วัน | แสดง 4 วัน | `fridge_days=4` (หรือ `freezer_days`), `shelf_type` ขึ้นต้นด้วย `custom:` | |
| TC-P2-08 | ของที่ไม่แนะนำแช่แข็ง | สแกนไข่แล้วเลือกช่องแช่แข็ง | มีคำเตือนว่าไม่แนะนำ แต่ยังบันทึกได้ | บันทึกได้ `storage='freezer'` | |
| TC-P2-09 | รูปไม่มีวัตถุดิบ | ถ่ายรูปโต๊ะว่าง | ขึ้น `ไม่พบวัตถุดิบ` ไม่มีการ์ดให้บันทึก | ไม่มีแถวใหม่ใน `fridge_items` | |
| TC-P2-10 | ไม่มีอินเทอร์เน็ต | ปิดเน็ตแล้วสแกน | แจ้งข้อผิดพลาด แอปไม่ค้าง | ไม่มีแถวใหม่ | |
| TC-P2-11 | ผูกวัตถุดิบกลาง | บันทึกชื่อที่มีในคลังกลาง เช่น `ไข่ไก่` | — | `fridge_items.ingredient_id` มีค่า (trigger จับคู่ชื่อ/alias) ถ้าชื่อไม่ตรงจะเป็น NULL | |

### P3 — จัดการคลังวัตถุดิบ (Inventory Management)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P3-01 | ดูรายการ | เปิดหน้าเช็คตู้เย็น | เห็นเฉพาะของบัญชีตัวเอง พร้อมจำนวนวันที่อยู่ในตู้ / วันคงเหลือ | — | |
| TC-P3-02 | ข้อมูลไม่ข้ามบัญชี | Login บัญชี B | ไม่เห็นของบัญชี A | (RLS) | |
| TC-P3-03 | ลดจำนวน | กด − 1 ครั้ง | จำนวนลด 1 | `fridge_items.quantity` ลด 1 | |
| TC-P3-04 | เพิ่มเกินจำนวนตั้งต้น | กด + จน `quantity = max_quantity` แล้วกดอีก | ขึ้น "มีครบ ... แล้ว — ถ้าซื้อมาเพิ่มให้สแกนเป็นลอตใหม่..." | `quantity` ไม่เกิน `max_quantity` | |
| TC-P3-05 | แก้จำนวน/หน่วยในหน้ารายละเอียด | แก้คงเหลือ 3 ทั้งหมด 6 | แสดงค่าใหม่ แถบ % เปลี่ยน | `quantity=3`, `max_quantity=6`, `unit` ตามที่เลือก | |
| TC-P3-06 | ย้ายเข้าช่องแช่แข็ง | รายละเอียด → ย้ายไปช่องแช่แข็ง | แสดงว่าอยู่ช่องแช่แข็ง วันคงเหลือนับใหม่ | `storage='freezer'`, `storage_changed_at` ≈ ตอนนี้, `days_left_at_freeze` = วันที่เหลือตอนย้าย, `expiry_date` ใหม่ | |
| TC-P3-07 | ย้ายออกจากช่องแช่แข็ง | ย้ายกลับตู้เย็น | ขึ้น "เคยละลายแล้ว" | `storage='fridge'`, `thawed_at` ≈ ตอนนี้, `storage_changed_at` อัปเดต | |
| TC-P3-08 | แช่แข็งของที่ไม่มีข้อมูลช่องแช่แข็ง | ย้ายผักเข้าช่องแช่แข็ง | วันคงเหลือ **ไม่เพิ่ม** นับต่อจากเดิม | `expiry_date` ไม่ถูกยืดออก | |
| TC-P3-09 | แก้วันหมดอายุ | เลือกวันที่ใหม่จากปฏิทิน | วันคงเหลือเปลี่ยน | `expiry_date` = วันที่เลือก (UTC) | |
| TC-P3-10 | ลบวัตถุดิบ | ลบ 1 รายการ | หายจากรายการ | แถวใน `fridge_items` หายไป | |

### P4 — สร้างและแนะนำสูตรอาหาร (AI Recipe Generation)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P4-01 | ใช้เมนูจากคลังกลาง | ตู้มีของที่ตรงกับสูตรในคลัง ≥ 3 สูตร → สร้างเมนู | แสดงเมนู + "ขาด: ..." ไม่ต้องรอ AI | `ai_request_logs` `event_type='generate_menu'`, `result='cache_hit'`, ไม่มี token · ไม่มีแถวใหม่ใน `recipes` | |
| TC-P4-02 | ให้ AI คิดใหม่ | กด "ให้ AI คิดใหม่" | ได้เมนูใหม่ | `ai_request_logs` `result='gemini'` มี token · `recipes` เพิ่มแถว `source='ai_generated'`, `is_public=true`, `created_by` = ผู้ใช้ · `recipe_ingredients` มีส่วนผสม · `recipes.ingredient_ids` ถูกเติมโดย trigger | |
| TC-P4-03 | ตู้เย็นว่าง | ลบของในตู้ทั้งหมดแล้วสร้างเมนู | `ไม่มีวัตถุดิบในตู้เย็น กรุณาเพิ่มวัตถุดิบก่อน` | ไม่เรียก AI · ไม่มีแถวใหม่ใน `ai_request_logs` | |
| TC-P4-04 | ตัวกรองหมวด | เลือก `คลีน` / `คีโต` | เมนูตรงหมวด | สูตรใหม่ที่ได้มี `diet_tags` ตามหมวด | |
| TC-P4-05 | ของพื้นฐานไม่นับว่าขาด | สูตรใช้เกลือ น้ำปลา ซึ่งไม่มีในตู้ | "ขาด" ไม่แสดงเกลือ/น้ำปลา | `ingredients.is_staple=true` ของรายการนั้น | |
| TC-P4-05a | วัตถุดิบใหม่ที่เป็นของพื้นฐานถูกตั้งค่าให้อัตโนมัติ | ให้ AI คิดเมนูที่ใช้ของพื้นฐานชื่อที่ยังไม่มีในตาราง เช่น `ซีอิ๊วดำ`, `น้ำมันมะกอก` | ไม่ขึ้นใน "ขาด" | `ingredients` แถวใหม่ของชื่อนั้น `is_staple=true` · ชื่อทั่วไป เช่น `ข้าวโพด`, `น้ำมะนาว` ได้ `is_staple=false` | |
| TC-P4-06 | บันทึกเมนู | กดบันทึกสูตร | อยู่ในคลังสูตรของฉัน | `user_saved_recipes` เพิ่ม 1 แถว (`user_id`, `recipe_id`), บันทึกซ้ำไม่เกิดแถวซ้ำ (UNIQUE `user_id, recipe_id`) | |
| TC-P4-07 | ทำอาหาร → หักวัตถุดิบ | ดูสูตร → ทำอาหาร → ยืนยันการหัก | ข้อความหักสำเร็จ จำนวนในตู้ลด | `fridge_items.quantity` ลดตามที่ยืนยัน หักจากลอตที่เข้าตู้ก่อน (FIFO) | |
| TC-P4-08 | หักจนหมด | หักเท่ากับที่มีพอดี | รายการหายจากตู้ | แถวใน `fridge_items` ถูกลบ | |
| TC-P4-09 | ของพื้นฐานเริ่มที่ "ไม่ได้ใช้" | หน้ายืนยันหัก มีซอส/ข้าว | ซอส/ข้าวเริ่มที่ "ไม่ได้ใช้" | ไม่หัก ถ้าไม่เปลี่ยน | |

### P5 — สกัดข้อมูลจากสูตรอาหาร (Smart Recipe Capture)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P5-01 | สแกนสูตรจากรูป | ถ่ายรูปหน้าตำราอาหาร | ได้ชื่อ วัตถุดิบ ขั้นตอน ขั้นที่ AI คิดเพิ่มเป็นตัวแดง เทียบกับของในตู้ | `ai_request_logs` `event_type='scan_recipe'`, `result='gemini'`, มี `image_hash` | |
| TC-P5-02 | บันทึกสูตรที่สแกน | กดบันทึก | อยู่ในคลังสูตรของฉัน | `recipes` เพิ่ม `source='scanned'`, `is_public=false`, `image_hash` = sha256 ของรูป · `user_saved_recipes` เพิ่มแถว · `overrides.scan_image_path` มีค่า · ไฟล์อยู่ใน bucket `recipe-scan-images` | |
| TC-P5-03 | สแกนรูปเดิมซ้ำ | สแกนรูปเดิมจาก TC-P5-01 | ได้ผลทันที ไม่รอ AI | `ai_request_logs` `result='cache_hit'` ไม่มี token | |
| TC-P5-04 | รูปไม่ใช่สูตร | ถ่ายรูปวิว | แจ้งว่าไม่ใช่สูตรอาหาร | `ai_request_logs` `result='not_recipe'` · ไม่มีแถวใหม่ใน `recipes` | |
| TC-P5-05 | แก้สูตรก่อนบันทึก | แก้ชื่อเมนู/ขั้นตอน | บันทึกตามที่แก้ | `user_saved_recipes.overrides` มี `recipe_name` / `instructions` ที่แก้ · สูตรกลาง `recipes` ไม่ถูกแก้ | |
| TC-P5-06 | เขียนสูตรเอง | คลังสูตร → เขียนสูตรเอง → บันทึก | อยู่ในคลัง | `recipes` `source='manual'`, `is_public=false` · `user_saved_recipes` เพิ่มแถว | |
| TC-P5-07 | สูตรส่วนตัวไม่ข้ามบัญชี | บัญชี B ค้นชื่อสูตรจาก TC-P5-02 | ไม่เจอ | (`is_public=false`) | |
| TC-P5-08 | กดหัวใจสูตร | กดหัวใจ | สูตรขึ้นเป็นสูตรโปรด | `user_saved_recipes.is_favorite=true` (กดซ้ำ = `false`) | |
| TC-P5-09 | ค้นหาสูตรด้วยชื่อสะกดผิด | ค้น `กะเพา` | เจอ `ผัดกะเพรา...` | (RPC `search_recipes_by_name`) | |
| TC-P5-10 | ลบสูตรออกจากคลัง | ลบสูตร | หายจากคลังของฉัน | แถวใน `user_saved_recipes` หายไป · แถวใน `recipes` ยังอยู่ | |

### P6 — วางแผนมื้ออาหารล่วงหน้า (AI Meal Planning)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P6-01 | สร้างแผน | เป้าหมาย `ลดน้ำหนัก`, 3 มื้อ/วัน, 1800 kcal, โปรตีน 100 g, ไม่มีข้อจำกัด | ได้แผน 7 วัน (Monday–Sunday) วันละ 3 มื้อ | `meal_plans` เพิ่ม 1 แถว `saved=false` · `weekly_meals` 21 แถว (`plan_id`, `day`, `meal_type`, `food_name`, `calories`, `protein`, `ingredients`, `steps`, `is_cooked=false`) · มื้อที่มาจากคลังมี `recipe_id` | |
| TC-P6-02 | แคลอรีต่อวันไม่เกินเป้า | ดูยอดรวมแต่ละวันจาก TC-P6-01 | ทุกวัน ≤ 1800 kcal และขาดไม่เกิน 100 kcal · โปรตีนขาดไม่เกิน 10 g | `sum(weekly_meals.calories)` ต่อวัน ≤ `target_calories` | |
| TC-P6-03 | ใช้คลังก่อน AI | สร้างแผนเมื่อคลังมีเมนูพอ | — | `ai_request_logs` `event_type='meal_plan'` เป็น `cache_hit` ถ้าเมนูพอ, เป็น `gemini` ถ้าต้องให้ AI เติม | |
| TC-P6-04 | ข้อจำกัดอาหาร | เลือก `มังสวิรัติ` | ไม่มีเมนูเนื้อสัตว์ | — | |
| TC-P6-05 | บันทึกแผน | กดบันทึกแผน | แผนอยู่ใน "แผนของฉัน" | `meal_plans.saved=true` | |
| TC-P6-06 | แผนที่ไม่บันทึก | สร้างแผนแล้วออกโดยไม่บันทึก | ไม่อยู่ในแผนของฉัน | แถวยังอยู่แต่ `saved=false` | |
| TC-P6-07 | กดหัวใจแผน | กดหัวใจแผน | แผนโปรดขึ้นก่อน | `auth.users.raw_user_meta_data.favorite_plan_ids` มี id ของแผน | |
| TC-P6-08 | ทำมื้อนี้แล้ว | เปิดมื้อ → ทำแล้ว → ยืนยันหัก | มื้อแสดงว่าทำแล้ว | `weekly_meals.is_cooked=true` · `fridge_items.quantity` ลด | |
| TC-P6-09 | กดทำแล้วซ้ำ | กดทำแล้วซ้ำในมื้อเดิม | ไม่หักวัตถุดิบซ้ำ | `fridge_items.quantity` ไม่ลดเพิ่ม | |
| TC-P6-10 | ยกเลิกทำแล้ว | ยกเลิกสถานะทำแล้ว | กลับเป็นยังไม่ทำ | `weekly_meals.is_cooked=false` | |
| TC-P6-11 | ติ๊กวัตถุดิบ / แก้ขั้นตอน | ติ๊กวัตถุดิบ 1 รายการ, แก้ขั้นตอน | ค่าคงอยู่หลังเปิดใหม่ | `weekly_meals.ingredients[].checked` / `weekly_meals.steps` เปลี่ยน | |
| TC-P6-12 | เปลี่ยนเมนูในมื้อ | กดเปลี่ยนเมนู | ได้เมนูใหม่ แคลอรีรวมยังไม่เกินเป้า | `weekly_meals` แถวนั้นเปลี่ยน `food_name, calories, protein, ingredients, steps, recipe_id` | |
| TC-P6-13 | รายการซื้อของ | สร้างแผนแบบซื้อเพิ่มได้ → เปิดแผนรายสัปดาห์ | การ์ด "🛒 ต้องซื้อสำหรับแพลนนี้ (n รายการ)" ด้านบน และกล่อง "🛒 ต้องซื้อ" ในการ์ดมื้อ แสดงเฉพาะส่วนที่ขาด · ไม่รวมของพื้นฐาน (ข้าว น้ำมัน เครื่องปรุง) | วัตถุดิบที่ขาดใน `weekly_meals.ingredients` มี `"to_buy": true` · ตัวรายการไม่ได้บันทึกที่ไหน | |
| TC-P6-14a | รายการซื้อของลดเองเมื่อซื้อมา | สแกนของในรายการเข้าตู้ แล้วเปิดแผนอีกครั้ง | รายการนั้นหายจาก "ต้องซื้อ" (หรือลดจำนวน) | `fridge_items` มีแถวใหม่ · `weekly_meals` ไม่เปลี่ยน | |
| TC-P6-14b | มื้อที่ทำแล้วไม่อยู่ในรายการซื้อ | ทำมื้อหนึ่งให้เป็นทำแล้ว | ของของมื้อนั้นไม่อยู่ใน "ต้องซื้อ" | `weekly_meals.is_cooked=true` | |
| TC-P6-14 | ลบแผน | แผนของฉัน → ลบ | แผนหายไป | `meal_plans` และ `weekly_meals` ของแผนนั้นหายทั้งหมด | |

### P7 — ตรวจสอบและแจ้งเตือนวันหมดอายุ (Expiration Alert)

| ID | กรณีทดสอบ | ขั้นตอน / ข้อมูลทดสอบ | ผลที่คาดหวัง (หน้าจอ) | ผลที่คาดหวัง (ฐานข้อมูล) | ผล |
|---|---|---|---|---|---|
| TC-P7-01 | ตั้งค่าแจ้งเตือนล่วงหน้า | เลือก 3 วัน (ตัวเลือก 0, 1, 2, 3, 5, 7) | บันทึกสำเร็จ | `auth.users.raw_user_meta_data.notify_days=3` | |
| TC-P7-02 | หน้าแจ้งเตือน | มีของที่เหลือ ≤ 3 วัน และของที่เหลือ 10 วัน | เห็นเฉพาะของที่ใกล้ครบ พร้อมบอกที่มาของจำนวนวัน | — (อ่าน `fridge_items.expiry_date`) | |
| TC-P7-03 | แจ้งเตือนตอนเปิดแอป | มีของถึงช่วงเตือน เปิดแอปครั้งแรกของวัน | ได้ notification 1 ข้อความรวมทุกรายการ | `raw_user_meta_data.last_expiry_notify_date` = วันนี้ | |
| TC-P7-04 | ไม่เตือนซ้ำในวันเดียว | ปิดแล้วเปิดแอปอีกครั้งวันเดียวกัน | ไม่มี notification ซ้ำ | `last_expiry_notify_date` ไม่เปลี่ยน | |
| TC-P7-05 | แจ้งเตือนล่วงหน้าตอนแอปปิด | ตั้งของให้ครบช่วงเตือนพรุ่งนี้ แล้วปิดแอป | ได้ notification เวลา 09:00 | — (local notification ในเครื่อง) | |
| TC-P7-06 | กด notification | แตะ notification | เปิดหน้าแจ้งเตือน | — | |
| TC-P7-07 | ต่อเวลาของที่เกินกำหนด | ของที่เลยวันแล้ว → ต่อเวลา / แก้จำนวนวัน | วันคงเหลือใหม่ | `fridge_days`/`freezer_days`, `expiry_date`, `shelf_type='custom:…'` เปลี่ยน | |
| TC-P7-08 | ลบจากหน้าแจ้งเตือน | ลบ → ยืนยัน | หายจากรายการ | แถวใน `fridge_items` หายไป | |
| TC-P7-09 | ลบบัญชีแล้วไม่มีแจ้งเตือนค้าง | ทำ TC-P1-16 กับบัญชีที่ตั้งแจ้งเตือนไว้ | ไม่มี notification ของบัญชีเดิม | — | |

---

## 3. Automated test ที่มีอยู่แล้ว

รันด้วย:

```bash
flutter test
```

ผลล่าสุด (7 พ.ย. 2026): **ผ่านครบ 32 ข้อ** — ทดสอบตรรกะในแอปเท่านั้น ไม่ได้เชื่อม Supabase หรือ Gemini

| ไฟล์ | ทดสอบอะไร | กระบวนการ |
|---|---|---|
| `test/fridge_age_test.dart` | นับวันคงเหลือ ย้ายเข้า/ออกช่องแช่แข็ง ของที่ไม่มีข้อมูลระยะเก็บ | P3, P7 |
| `test/shelf_life_source_test.dart` | ที่มาของอายุการเก็บรักษาตามประเภท ตัวเลือกช่องแช่แข็ง คำเตือน หน่วย `แผ่น` | P2, P3, P7 |
| `test/diet_check_test.dart` | ตรวจวัตถุดิบตามข้อจำกัด: ไม่มี / มังสวิรัติ / เจ / ไม่ทานนม | P6 |
| `test/plan_goal_test.dart` | เลือกเมนูและกติกา prompt ตามเป้าหมาย (ลดน้ำหนัก / เพิ่มกล้ามเนื้อ / รักษาน้ำหนัก) | P6 |
| `test/plan_targets_test.dart` | ช่วงแคลอรี/โปรตีนต่อมื้อ ยอดรวมต่อวันห้ามเกินเป้า | P6 |
| `test/plan_allocation_test.dart` | จองวัตถุดิบให้มื้อที่ใกล้ถึงก่อน มื้อที่ทำแล้วไม่จองซ้ำ | P6 |

ยังไม่มี automated test ของ P1 (auth), P4 (หักวัตถุดิบ FIFO) และ P5 — กรณีเหล่านี้ทดสอบด้วยมือตามตารางด้านบน
