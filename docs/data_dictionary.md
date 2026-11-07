# SmartFridge.AI — Data Dictionary (Supabase / PostgreSQL)

อัปเดตล่าสุด: 5 พ.ย. 2026 · อ้างอิง migration `supabase/migrations/20261104000000_global_recipes.sql` และ `20261104000100_contract_legacy_recipes.sql`

**สัญลักษณ์**

- **\*** = ตารางเดิมที่ไม่มีไฟล์ DDL ในโปรเจกต์ — ชื่อคอลัมน์และชนิดข้อมูล **อนุมานจากโค้ด Flutter** ควรยืนยันอีกครั้งใน Supabase Table Editor
- **ที่มาของข้อมูล:** `ผู้ใช้กรอก` · `Gemini API` · `ระบบ (DB)` = ค่า default / trigger / ฟังก์ชันในฐานข้อมูล · `แอปคำนวณ` = โค้ด Flutter คำนวณก่อนบันทึก
- ทุกตารางอยู่ใน schema `public` · `auth.users` คือตารางผู้ใช้ของ Supabase Auth

## ภาพรวมความสัมพันธ์

```
auth.users ─1:1─ profiles
    │
    ├─1:N─ fridge_items ───────────────N:1─┐
    ├─1:N─ user_saved_recipes ─N:1─┐       │
    ├─1:N─ ai_request_logs ────N:1─┤       │
    ├─1:N─ scanned_recipes_legacy ─┤ (global_recipe_id)
    └─1:N─ meal_plans ─1:N─ weekly_meals ─N:1─┤
                                     ▼        ▼
                                  recipes ─M:N─ ingredients ─1:N─ ingredient_aliases
                                       (ผ่าน recipe_ingredients)
```

| ตาราง | หน้าที่ | สถานะ |
|---|---|---|
| recipes | สูตรอาหารกลาง (cache ลดการเรียก Gemini) | ใหม่ |
| ingredients | วัตถุดิบกลาง 1 ชื่อมาตรฐาน = 1 แถว | ใหม่ |
| ingredient_aliases | ชื่อเรียกอื่นของวัตถุดิบ | ใหม่ |
| recipe_ingredients | ส่วนผสมของแต่ละสูตร (M:N) | ใหม่ |
| user_saved_recipes | สูตรที่ผู้ใช้บันทึก + ส่วนที่แก้เอง | ใหม่ |
| ai_request_logs | Log การเรียก AI / cache hit | ใหม่ |
| fridge_items\* | วัตถุดิบในตู้เย็นของผู้ใช้ | เดิม + เพิ่มคอลัมน์ |
| meal_plans\* | หัวแผนอาหาร | เดิม |
| weekly_meals\* | มื้ออาหารในแผน | เดิม + เพิ่มคอลัมน์ |
| scanned_recipes_legacy\* | คลังสูตรเดิม (อ่านอย่างเดียว) | เลิกใช้ |
| profiles\* | ข้อมูลผู้ใช้ | ไม่มีโค้ดแอปอ้างถึง |

---

## 1. recipes — สูตรอาหารกลาง

ทุกคนอ่านได้ถ้า `is_public = true` (หรือเป็นผู้สร้าง) · เขียนได้เฉพาะผ่าน RPC `save_recipe()`

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id | รหัสสูตรกลาง | UUID | NOT NULL, default `gen_random_uuid()` | PK | ระบบ (DB) | — (อ้างอิงภายใน, ส่งเป็น `global_recipe_id`) |
| name | ชื่อเมนู | TEXT | NOT NULL, ยาว 1–200 ตัวอักษร เช่น `ผัดกะเพราหมูสับ` | — | Gemini API / ผู้ใช้กรอก (หน้าเขียนสูตรเอง) | AiRecipeScreen, SavedRecipesScreen, RecipeDetailScreen, ScanRecipeResultScreen, WeeklyPlanScreen |
| name_key | ชื่อแบบ normalize ใช้ค้นหา/กันซ้ำ (ตัดช่องว่าง เครื่องหมาย ตัวพิมพ์เล็ก NFKC) | TEXT | Generated column จาก `normalize_text(name)` เช่น `ผัดกะเพราหมูสับ` | — | ระบบ (DB) | ไม่แสดง (ใช้ค้นหา) |
| time_text | เวลาทำแบบข้อความ | TEXT | NULL ได้ เช่น `15 นาที`, `1 ชั่วโมง 30 นาที` | — | Gemini API / ผู้ใช้กรอก | AiRecipeScreen, RecipeDetailScreen, SavedRecipesScreen |
| time_minutes | เวลาทำเป็นนาที (ใช้กรอง) | INTEGER | NULL ได้, 0–1440 | — | แอปคำนวณ / ระบบ (DB) แปลงจาก time_text | ไม่แสดง (ใช้กรองใน AiRecipeScreen) |
| servings_text | จำนวนที่ได้ | TEXT | NULL ได้ เช่น `2 ที่` | — | Gemini API / ผู้ใช้กรอก | RecipeDetailScreen, ManualRecipeScreen |
| instructions | ขั้นตอนการทำ (ตัดเลขข้อออกแล้ว) | JSONB | NOT NULL, ต้องเป็น array เช่น `["ตั้งกระทะ...", "ใส่หมูสับ..."]` ไม่เกิน 60 ขั้น | — | Gemini API / ผู้ใช้กรอก | RecipeDetailScreen, ScanRecipeResultScreen, CookMealScreen |
| ai_step_indexes | ตำแหน่งขั้นตอนที่ AI คิดเพิ่ม (แสดงตัวแดง) | INTEGER[] | NOT NULL, default `{}` เช่น `{2,3}` | — | Gemini API (`ai_generated: true`) | RecipeDetailScreen, ScanRecipeResultScreen |
| calories_per_serving | แคลอรี่ต่อที่ | NUMERIC | NULL ได้, 0–10000 | — | Gemini API (แพลนอาหาร) | WeeklyPlanScreen (ผ่าน weekly_meals) |
| protein_per_serving | โปรตีนต่อที่ (กรัม) | NUMERIC | NULL ได้, 0–1000 | — | Gemini API (แพลนอาหาร) | WeeklyPlanScreen |
| diet_tags | ป้ายประเภทอาหาร/ข้อจำกัด | TEXT[] | NOT NULL, default `{}` เช่น `{อาหารไทย}`, `{มังสวิรัติ}`, `{คีโต}` | — | แอปคำนวณ (จากตัวกรองที่เลือกตอนสั่ง Gemini) | ไม่แสดง (ใช้กรอง) |
| image_url | URL รูปเมนู (Supabase Storage `recipe-images`) | TEXT | NULL ได้ | — | ผู้ใช้กรอก (แนบรูป) | SavedRecipesScreen, ManualRecipeScreen, RecipeDetailScreen |
| image_hash | sha256 ของไฟล์รูปที่สแกน (หา cache รูปซ้ำ) | TEXT | NULL ได้, UNIQUE เมื่อ `is_public` | — | แอปคำนวณ | ไม่แสดง |
| source | ที่มาของสูตร | TEXT | NOT NULL, `ai_generated` / `scanned` / `manual` | — | ระบบ (DB) ตามจุดที่บันทึก | ไม่แสดง |
| ingredient_signature | md5 ของ id วัตถุดิบ (เรียงแล้ว) ใช้กันสูตรซ้ำ | TEXT | NOT NULL, UNIQUE คู่กับ name_key เมื่อ `is_public` | — | ระบบ (DB) | ไม่แสดง |
| ingredient_ids | id วัตถุดิบทั้งหมดของสูตร (ค้นหาเร็วด้วย GIN) | BIGINT[] | NOT NULL, default `{}` | — | ระบบ (DB) trigger จาก recipe_ingredients | ไม่แสดง |
| is_public | ให้ผู้ใช้อื่นเห็น/ใช้เป็น cache ได้ไหม | BOOLEAN | NOT NULL, default `true` (สูตรสแกน/เขียนเอง = `false`) | — | แอปคำนวณ | ไม่แสดง |
| created_by | ผู้สร้างสูตร | UUID | NULL ได้ (ผู้ใช้ถูกลบ → NULL), default `auth.uid()` | FK → auth.users(id) ON DELETE SET NULL | ระบบ (DB) | ไม่แสดง |
| use_count | จำนวนครั้งที่ถูกใช้/บันทึกซ้ำ (ใช้จัดอันดับ) | INTEGER | NOT NULL, default 1 | — | ระบบ (DB) | ไม่แสดง |
| created_at | วันที่สร้าง | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | ไม่แสดง |
| updated_at | วันที่แก้ล่าสุด | TIMESTAMPTZ | NOT NULL, default `now()` + trigger | — | ระบบ (DB) | ไม่แสดง |

---

## 2. ingredients — วัตถุดิบกลาง

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id | รหัสวัตถุดิบ | BIGINT | NOT NULL, identity | PK | ระบบ (DB) | ไม่แสดง |
| name | ชื่อวัตถุดิบมาตรฐาน | TEXT | NOT NULL, 1–100 ตัวอักษร เช่น `ไข่ไก่`, `หมูสับ` | — | Gemini API / ผู้ใช้กรอก (ผ่านสูตร) / ข้อมูลตั้งต้น | ไม่แสดงโดยตรง (ชื่อที่แสดงมาจาก recipe_ingredients.display_name) |
| name_key | ชื่อแบบ normalize | TEXT | Generated, UNIQUE | — | ระบบ (DB) | ไม่แสดง |
| category | หมวดหมู่ | TEXT | NULL ได้ (ยังไม่ได้ใช้) | — | — | ไม่แสดง |
| is_staple | ของพื้นฐาน ไม่นับเป็นของที่ขาด | BOOLEAN | NOT NULL, default `false` เช่น เกลือ น้ำปลา = `true` | — | ข้อมูลตั้งต้น / ผู้ดูแลระบบ | ไม่แสดง (มีผลกับ "ขาด: ..." ใน AiRecipeScreen) |
| default_unit | หน่วยปกติ | TEXT | NULL ได้ (ยังไม่ได้ใช้) | — | — | ไม่แสดง |
| fridge_days | ระยะเก็บในตู้เย็น (วัน) | INTEGER | NULL ได้, ≥ 0 (ยังไม่ได้ใช้) | — | — | ไม่แสดง |
| freezer_days | ระยะเก็บในช่องแช่แข็ง (วัน) | INTEGER | NULL ได้, ≥ 0 (ยังไม่ได้ใช้) | — | — | ไม่แสดง |
| created_at | วันที่สร้าง | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | ไม่แสดง |

### 2.1 ingredient_aliases — ชื่อเรียกอื่นของวัตถุดิบ

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id | รหัส | BIGINT | NOT NULL, identity | PK | ระบบ (DB) | ไม่แสดง |
| alias | ชื่อเรียกอื่น | TEXT | NOT NULL, 1–100 ตัวอักษร เช่น `ไข่`, `หมูบด` | — | ข้อมูลตั้งต้น / ผู้ดูแลระบบ | ไม่แสดง |
| alias_key | alias แบบ normalize | TEXT | Generated, UNIQUE | — | ระบบ (DB) | ไม่แสดง |
| ingredient_id | วัตถุดิบมาตรฐานที่ชื่อนี้หมายถึง | BIGINT | NOT NULL | FK → ingredients(id) ON DELETE CASCADE | ผู้ดูแลระบบ | ไม่แสดง |

---

## 3. recipe_ingredients — ส่วนผสมของสูตร (M:N recipes ↔ ingredients)

PK แบบรวม `(recipe_id, sort_order)`

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| recipe_id | สูตรที่ส่วนผสมนี้อยู่ | UUID | NOT NULL | PK (ร่วม), FK → recipes(id) ON DELETE CASCADE | ระบบ (DB) | ไม่แสดง |
| sort_order | ลำดับวัตถุดิบในสูตร | SMALLINT | NOT NULL, เริ่มที่ 0 | PK (ร่วม) | ระบบ (DB) | กำหนดลำดับรายการใน RecipeDetailScreen |
| ingredient_id | วัตถุดิบมาตรฐาน | BIGINT | NOT NULL | FK → ingredients(id) | ระบบ (DB) แปลงชื่อ → id (รวม alias) | ไม่แสดง |
| display_name | ชื่อตามที่สูตรเขียน | TEXT | NOT NULL เช่น `ไข่ไก่` | — | Gemini API / ผู้ใช้กรอก | RecipeDetailScreen, ScanRecipeResultScreen, AiRecipeScreen (แท็กวัตถุดิบ / "ขาด: ...") |
| quantity | ปริมาณที่ใช้ | NUMERIC | NULL ได้, ≥ 0 เช่น `0.5`, `2` | — | Gemini API / ผู้ใช้กรอก | RecipeDetailScreen, DeductConfirmSheet |
| unit | หน่วย | TEXT | NULL ได้ เช่น `ฟอง`, `ช้อนโต๊ะ`, `ส่วน` | — | Gemini API / ผู้ใช้กรอก | RecipeDetailScreen |
| is_main | เป็นวัตถุดิบหลัก (อยู่ใน ingredients_used) | BOOLEAN | NOT NULL, default `false` | — | Gemini API | แท็กวัตถุดิบบนการ์ดใน AiRecipeScreen |

---

## 4. user_saved_recipes — สูตรที่ผู้ใช้บันทึก (Bookmark)

RLS: เจ้าของ account เท่านั้น (SELECT / INSERT / UPDATE / DELETE ตาม `auth.uid()`) · UNIQUE `(user_id, recipe_id)`

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id | รหัส Bookmark (แอปใช้เป็น `recipe['id']` สำหรับแก้/ลบ) | UUID | NOT NULL, default `gen_random_uuid()` | PK | ระบบ (DB) | ไม่แสดง |
| user_id | เจ้าของ | UUID | NOT NULL, default `auth.uid()` | FK → auth.users(id) ON DELETE CASCADE | ระบบ (DB) | ไม่แสดง |
| recipe_id | สูตรกลางที่บันทึก | UUID | NOT NULL | FK → recipes(id) ON DELETE CASCADE | ระบบ (DB) จาก `save_recipe()` | ไม่แสดง (ใช้ดึงสูตร) |
| overrides | ส่วนที่ผู้ใช้แก้เอง (ทับสูตรกลางเฉพาะคนนี้) | JSONB | NULL ได้, ต้องเป็น object เช่น `{"recipe_name": "...", "image_url": "..."}` | — | ผู้ใช้กรอก (แก้ไขสูตร) | SavedRecipesScreen, RecipeDetailScreen, ManualRecipeScreen (รวมกับสูตรกลางแล้ว) |
| is_favorite | สูตรโปรด | BOOLEAN | NOT NULL, default `false` | — | — (ยังไม่มีปุ่มในแอป) | ยังไม่แสดง |
| notes | บันทึกส่วนตัว | TEXT | NULL ได้ | — | — (ยังไม่มีในแอป) | ยังไม่แสดง |
| created_at | วันที่บันทึก | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | ScanRecipeScreen ("สูตรล่าสุด" เวลาที่ผ่านมา), เรียงลำดับใน SavedRecipesScreen |
| updated_at | วันที่แก้ล่าสุด | TIMESTAMPTZ | NOT NULL, default `now()` + trigger | — | ระบบ (DB) | ไม่แสดง |

---

## 5. ai_request_logs — Log การเรียก AI

RLS: เจ้าของอ่าน/เพิ่มได้เท่านั้น (แก้/ลบไม่ได้)

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id | รหัส log | BIGINT | NOT NULL, identity | PK | ระบบ (DB) | ไม่แสดง |
| user_id | ผู้ใช้ที่เรียก | UUID | NOT NULL, default `auth.uid()` | FK → auth.users(id) ON DELETE CASCADE | ระบบ (DB) | ไม่แสดง |
| recipe_id | สูตรที่ได้ (ถ้ามี) | UUID | NULL ได้ | FK → recipes(id) ON DELETE SET NULL | แอปคำนวณ | ไม่แสดง |
| event_type | จุดที่เรียก | TEXT | NOT NULL, `scan_recipe` / `generate_menu` / `meal_plan` / `scan_ingredient` | — | แอปคำนวณ | ไม่แสดง (ดูผ่าน RPC `my_ai_usage()`) |
| result | ผลลัพธ์ | TEXT | NOT NULL, `cache_hit` / `gemini` / `not_recipe` / `failed` | — | แอปคำนวณ | ไม่แสดง |
| image_hash | sha256 ของรูป (กรณีสแกน) | TEXT | NULL ได้ | — | แอปคำนวณ | ไม่แสดง |
| model | โมเดล Gemini ที่ใช้ | TEXT | NULL ได้ เช่น `gemini-3.6-flash` | — | แอปคำนวณ | ไม่แสดง |
| prompt_tokens | token ขาเข้า | INTEGER | NULL ได้, ≥ 0 | — | Gemini API (`usageMetadata`) | ไม่แสดง |
| output_tokens | token ขาออก | INTEGER | NULL ได้, ≥ 0 | — | Gemini API (`usageMetadata`) | ไม่แสดง |
| created_at | เวลาเรียก | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | ไม่แสดง |

---

## 6. fridge_items\* — วัตถุดิบในตู้เย็น

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| item_id\* | รหัสวัตถุดิบในตู้เย็น | BIGINT หรือ UUID\* | NOT NULL | PK | ระบบ (DB) | ไม่แสดง (ใช้เปิด ItemDetailScreen) |
| user_id\* | เจ้าของ | UUID | NOT NULL | FK → auth.users(id) | แอปคำนวณ (ผู้ใช้ที่ login) | ไม่แสดง |
| name\* | ชื่อวัตถุดิบ | TEXT | NOT NULL เช่น `อกไก่` | — | Gemini API (ถ่ายภาพวัตถุดิบ) / ผู้ใช้แก้ | InventoryScreen, ItemDetailScreen, ExpirationAlertScreen, AiRecipeScreen, ResultScreen |
| category\* | หมวดหมู่ | TEXT | `ผัก` / `ผลไม้` / `เนื้อสัตว์` / `แป้ง/ข้าว` / `นม/เครื่องดื่ม` / `ขนม` / `อื่นๆ` | — | Gemini API (enum) / ผู้ใช้แก้ | InventoryScreen (ไอคอน/ตัวกรอง), ItemDetailScreen, ExpirationAlertScreen |
| quantity\* | จำนวนคงเหลือ | NUMERIC\* | ≥ 0 (0 = ใช้หมดแล้ว) | — | Gemini API → ผู้ใช้ยืนยัน · หักอัตโนมัติตอนทำอาหาร | InventoryScreen, ItemDetailScreen, AiRecipeScreen |
| max_quantity\* | จำนวนตอนเพิ่มเข้าตู้ (ใช้คำนวณ % คงเหลือ) | NUMERIC\* | ≥ 0 | — | แอปคำนวณ (= quantity ตอนบันทึก) | InventoryScreen, ItemDetailScreen |
| unit\* | หน่วยเก็บ | TEXT | เช่น `ชิ้น`, `ฟอง`, `ส่วน` | — | Gemini API → ผู้ใช้ยืนยัน | InventoryScreen, ItemDetailScreen, AiRecipeScreen |
| detected_quantity\* | จำนวนที่ AI นับได้จากรูป | NUMERIC\* | NULL ได้ | — | Gemini API | ItemDetailScreen |
| detected_unit\* | หน่วยที่ AI ตรวจได้ | TEXT | NULL ได้ | — | Gemini API | ItemDetailScreen |
| storage\* | ช่องที่เก็บ | TEXT | `fridge` / `freezer` | — | ผู้ใช้เลือก (ResultScreen / ย้ายช่องใน ItemDetailScreen) | InventoryScreen, ItemDetailScreen, ExpirationAlertScreen |
| food_state\* | สภาพอาหาร | TEXT | NULL ได้ เช่น `ดิบ`, `สุก` | — | ผู้ใช้เลือก (ค่าเริ่มต้นจากประเภทอาหาร) | ResultScreen, ItemDetailScreen |
| fridge_days\* | ระยะเก็บในตู้เย็น (วัน) | INTEGER\* | NULL ได้, ≥ 0 | — | ตาราง shelf life ในแอป / Gemini API / ผู้ใช้แก้ | ItemDetailScreen, ExpirationAlertScreen |
| freezer_days\* | ระยะเก็บในช่องแช่แข็ง (วัน) | INTEGER\* | NULL ได้, ≥ 0 | — | ตาราง shelf life ในแอป / Gemini API / ผู้ใช้แก้ | ItemDetailScreen, ExpirationAlertScreen |
| shelf_type\* | ประเภทอายุการเก็บที่ใช้คำนวณ | TEXT | NULL = Gemini ประเมิน, key ของตาราง shelf life, หรือ `custom:<key>:<วัน>` = ผู้ใช้แก้เอง | — | แอปคำนวณ | ExpirationAlertScreen (บอกที่มาของจำนวนวัน), ItemDetailScreen |
| expiry_date\* | วันครบกำหนดเก็บ | TIMESTAMPTZ | NOT NULL\* (บันทึกเป็น UTC) | — | แอปคำนวณ (วันที่เพิ่ม + ระยะเก็บ) | ExpirationAlertScreen, InventoryScreen, ItemDetailScreen, การแจ้งเตือน |
| storage_changed_at\* | เวลาที่ย้ายช่องเก็บล่าสุด | TIMESTAMPTZ | NULL ได้ | — | แอปคำนวณ (ย้ายช่อง) | ItemDetailScreen (คำนวณวันคงเหลือ) |
| days_left_at_freeze\* | จำนวนวันที่เหลือตอนย้ายเข้าช่องแช่แข็ง | INTEGER\* | NULL ได้ | — | แอปคำนวณ | ItemDetailScreen |
| thawed_at\* | เวลาที่ย้ายออกจากช่องแช่แข็ง (ละลาย) | TIMESTAMPTZ | NULL ได้ | — | แอปคำนวณ | ItemDetailScreen ("เคยละลายแล้ว") |
| created_at\* | วันที่เพิ่มเข้าตู้ | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | InventoryScreen, AiRecipeScreen ("อยู่ในตู้ X วัน"), ExpirationAlertScreen |
| ingredient_id | วัตถุดิบกลางที่ตรงกับชื่อนี้ | BIGINT | NULL ได้ | FK → ingredients(id) ON DELETE SET NULL | ระบบ (DB) trigger จากชื่อ (ตรงชื่อ/alias เท่านั้น) | ไม่แสดง |

---

## 7. meal_plans\* — หัวแผนอาหาร

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id\* | รหัสแผน | BIGINT หรือ UUID\* | NOT NULL | PK | ระบบ (DB) | ไม่แสดง |
| user_id\* | เจ้าของแผน | UUID | NOT NULL | FK → auth.users(id) | แอปคำนวณ | ไม่แสดง |
| goal\* | เป้าหมาย | TEXT | เช่น `ลดน้ำหนัก` | — | ผู้ใช้เลือก | MealPlanScreen, MyPlanScreen |
| meals_per_day\* | จำนวนมื้อต่อวัน | INTEGER | > 0 เช่น `3` | — | ผู้ใช้เลือก | MealPlanScreen, MyPlanScreen |
| target_calories\* | เป้าแคลอรี่ต่อวัน | INTEGER | default ในแอป `2000` | — | ผู้ใช้กรอก | MealPlanScreen, MyPlanScreen |
| target_protein\* | เป้าโปรตีนต่อวัน (กรัม) | INTEGER | default ในแอป `100` | — | ผู้ใช้กรอก | MealPlanScreen, MyPlanScreen |
| diet_type\* | ข้อจำกัดอาหาร | TEXT | `ไม่มี` / `มังสวิรัติ` / `เจ` / `ไม่ทานนม` | — | ผู้ใช้เลือก | MealPlanScreen, MyPlanScreen |
| saved\* | ผู้ใช้กดบันทึกแผนแล้วหรือยัง | BOOLEAN | default `false` | — | ผู้ใช้กด (WeeklyPlanScreen) | MyPlanScreen (แสดงเฉพาะ `true`), WeeklyPlanScreen |
| created_at\* | วันที่สร้างแผน | TIMESTAMPTZ | NOT NULL, default `now()` | — | ระบบ (DB) | MyPlanScreen, WeeklyPlanScreen |

### 7.1 weekly_meals\* — มื้ออาหารในแผน

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id\* | รหัสมื้อ | BIGINT หรือ UUID\* | NOT NULL | PK | ระบบ (DB) | ไม่แสดง (ใช้เปิด CookMealScreen) |
| plan_id\* | แผนที่มื้อนี้อยู่ | ชนิดเดียวกับ meal_plans.id | NOT NULL | FK → meal_plans(id) | แอปคำนวณ | ไม่แสดง |
| day\* | วัน | TEXT | `Monday` … `Sunday` | — | Gemini API / แอปคำนวณ | WeeklyPlanScreen |
| meal_type\* | มื้อ | TEXT | เช่น `มื้อที่ 1` | — | แอปคำนวณ | WeeklyPlanScreen |
| food_name\* | ชื่อเมนู (เลิกใช้หลัง Contract → ใช้ recipes.name) | TEXT | NULL ได้หลัง Contract | — | Gemini API / คลังเมนูเก่า | WeeklyPlanScreen, CookMealScreen |
| calories\* | แคลอรี่ของมื้อ (เลิกใช้หลัง Contract) | NUMERIC\* | NULL ได้ | — | Gemini API | WeeklyPlanScreen |
| protein\* | โปรตีนของมื้อ (เลิกใช้หลัง Contract) | NUMERIC\* | NULL ได้ | — | Gemini API | WeeklyPlanScreen |
| ingredients\* | วัตถุดิบ + สถานะติ๊ก | JSONB\* | array เช่น `[{"name":"อกไก่","quantity":"1 ชิ้น","checked":true}]` | — | Gemini API + แอปคำนวณ (`checked` เทียบตู้เย็น) / ผู้ใช้ติ๊ก | CookMealScreen |
| steps\* | ขั้นตอน (ข้อความหลายบรรทัด) | TEXT\* | เช่น `1. ...\n2. ...` | — | Gemini API / ผู้ใช้แก้ | CookMealScreen |
| is_cooked\* | ทำมื้อนี้แล้ว | BOOLEAN | default `false` | — | ผู้ใช้กด (CookMealScreen) | WeeklyPlanScreen, CookMealScreen |
| recipe_id | สูตรกลางของมื้อนี้ | UUID | NULL ได้ | FK → recipes(id) ON DELETE SET NULL | ระบบ (DB) migration | ยังไม่แสดง |
| user_id | เจ้าของ (ไม่ต้อง join ผ่าน meal_plans) | UUID | NULL ได้, default `auth.uid()` | FK → auth.users(id) ON DELETE CASCADE | ระบบ (DB) | ไม่แสดง |

---

## 8. scanned_recipes_legacy\* — คลังสูตรเดิม (เดิมชื่อ scanned_recipes)

**เลิกใช้แล้ว / อ่านอย่างเดียว** — ข้อมูลทั้งหมดย้ายไป `recipes` + `user_saved_recipes` แล้ว แอปไม่ได้อ่านหรือเขียนตารางนี้ · หน้าที่ "ประวัติการเรียก AI" อยู่ที่ `ai_request_logs`

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| id\* | รหัสสูตรเดิม | BIGINT หรือ UUID\* | NOT NULL | PK | ระบบ (DB) | ไม่แสดง (เลิกใช้) |
| user_id\* | เจ้าของ | UUID | NOT NULL\* | FK → auth.users(id)\* | แอปเวอร์ชันเก่า | ไม่แสดง |
| recipe_name\* | ชื่อเมนู | TEXT | — | — | Gemini API / ผู้ใช้กรอก | ไม่แสดง (เลิกใช้) |
| time\* | เวลาทำ | TEXT | เช่น `30 นาที` | — | Gemini API / ผู้ใช้กรอก | ไม่แสดง |
| servings\* | จำนวนที่ได้ | TEXT | เช่น `2 ที่` | — | Gemini API / ผู้ใช้กรอก | ไม่แสดง |
| ingredients_used\* | วัตถุดิบหลัก | JSONB / TEXT[]\* | array ของชื่อ | — | Gemini API | ไม่แสดง |
| detailed_ingredients\* | วัตถุดิบละเอียด | JSONB\* | `[{"name","use_quantity","unit"}]` | — | Gemini API / ผู้ใช้กรอก | ไม่แสดง |
| instructions\* | ขั้นตอน | JSONB / TEXT[]\* | array ของข้อความ | — | Gemini API / ผู้ใช้กรอก | ไม่แสดง |
| ai_step_indexes\* | ขั้นตอนที่ AI คิดเพิ่ม | JSONB / INTEGER[]\* | — | — | Gemini API | ไม่แสดง |
| image_url\* | รูปเมนู | TEXT | NULL ได้ | — | ผู้ใช้แนบ | ไม่แสดง |
| created_at\* | วันที่บันทึก | TIMESTAMPTZ | default `now()` | — | ระบบ (DB) | ไม่แสดง |
| global_recipe_id | สูตรกลางที่ย้ายไปแล้ว | UUID | NULL = ยังไม่ได้ย้าย | FK → recipes(id) ON DELETE SET NULL | ระบบ (DB) migration | ไม่แสดง |

---

## 9. profiles\* — ข้อมูลผู้ใช้งาน

**ตาราง `profiles` มีอยู่บน Supabase แต่โค้ดแอปไม่ได้อ่านหรือเขียนตารางนี้** — คอลัมน์ต้องตรวจจาก Supabase โดยตรง
ข้อมูลผู้ใช้ที่แอปใช้จริงเก็บใน **`auth.users.raw_user_meta_data`** (Supabase Auth `user_metadata`) ดังนี้:

| Element Name | Description | Data Type | Permissible Value | Key Type | Data Source / Input | Display Screen |
|---|---|---|---|---|---|---|
| auth.users.id | รหัสผู้ใช้ (ทุกตารางอ้างถึง) | UUID | NOT NULL | PK (Supabase Auth) | ระบบ (Supabase Auth) | ไม่แสดง |
| auth.users.email | อีเมลที่ใช้ login | TEXT | UNIQUE | — | ผู้ใช้กรอก (RegisterScreen) | ProfileScreen, LoginScreen |
| user_metadata.first_name | ชื่อ | TEXT (ใน JSONB) | — | — | ผู้ใช้กรอก (RegisterScreen / EditProfileScreen) | MainMenuScreen (ทักทาย), ProfileScreen, EditProfileScreen |
| user_metadata.last_name | นามสกุล | TEXT (ใน JSONB) | — | — | ผู้ใช้กรอก | MainMenuScreen, ProfileScreen, EditProfileScreen |
| user_metadata.phone | เบอร์โทร | TEXT (ใน JSONB) | — | — | ผู้ใช้กรอก | EditProfileScreen |
| user_metadata.notify_days | แจ้งเตือนล่วงหน้ากี่วันก่อนครบระยะเก็บ | INTEGER (ใน JSONB) | NULL = ใช้ค่าเริ่มต้นของแอป | — | ผู้ใช้เลือก (NotificationSettingsScreen) | NotificationSettingsScreen, ExpirationAlertScreen, AiRecipeScreen |
| user_metadata.last_expiry_notify_date | วันที่แจ้งเตือนครั้งล่าสุด (กันเตือนซ้ำ) | TEXT (ใน JSONB) | รูปแบบวันที่ | — | แอปคำนวณ (NotificationService) | ไม่แสดง |

> ถ้าต้องการให้ `profiles` เป็นแหล่งข้อมูลหลัก (เช่น เพิ่ม allergies / diet_preference ในอนาคต) ต้องแก้แอปให้อ่าน/เขียนตารางนี้แทน `user_metadata`

---

## RPC (Supabase Functions) ที่แอปเรียก

| Function | ใช้ทำอะไร | เรียกจากหน้า |
|---|---|---|
| `match_recipes_by_ingredients(...)` | หาสูตรจากของในตู้เย็น (ก่อนเรียก Gemini) | AiRecipeScreen, MealPlanScreen |
| `find_recipe_by_image_hash(p_image_hash)` | หาสูตรจากรูปที่เคยสแกน | ScanRecipeScreen |
| `search_recipes_by_name(p_query)` | ค้นสูตรจากชื่อ | (ยังไม่ได้ใช้ในแอป) |
| `save_recipe(p_recipe, p_source, p_image_hash, p_is_public, p_bookmark)` | บันทึกสูตรเข้าคลังกลาง (+ Bookmark) | ScanRecipeResultScreen, ManualRecipeScreen, AiRecipeScreen, MealPlanScreen |
| `my_saved_recipes()` | สูตรที่ผู้ใช้บันทึก (รวม overrides) | SavedRecipesScreen, ScanRecipeScreen |
| `my_ai_usage(p_days)` | สรุป cache hit / token | (ยังไม่ได้ใช้ในแอป) |
