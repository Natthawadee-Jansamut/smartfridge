# SmartFridge.AI — ER Diagram

อัปเดตล่าสุด: 7 พ.ย. 2026 · ตรงกับ [data_dictionary.md](data_dictionary.md) และ migration `20261104000000_global_recipes.sql` + `20261104000100_contract_legacy_recipes.sql`

- ชื่อตาราง/คอลัมน์ตรวจกับ Supabase จริงแล้ว (7 พ.ย. 2026) · ชนิดข้อมูลของตาราง **\*** ยังอนุมานจากโค้ด
- `auth_users` = ตาราง `auth.users` ของ Supabase Auth
- **\*** ในคำอธิบาย = ตารางเดิมที่ไม่มี DDL ในโปรเจกต์ (ชนิดข้อมูลอนุมานจากโค้ด Flutter)
- `scanned_recipes_legacy` ไม่พบผ่าน REST API แล้ว จึงเอาออกจากแผนภาพ (ดูหัวข้อ 8 ใน data_dictionary.md)
- ชนิด `*_array` = array ของ PostgreSQL เช่น `bigint_array` = `BIGINT[]`

```mermaid
erDiagram
    auth_users ||--o| profiles : "มีโปรไฟล์"
    auth_users ||--o{ fridge_items : "เป็นเจ้าของ"
    auth_users ||--o{ user_saved_recipes : "บันทึกสูตร"
    auth_users ||--o{ ai_request_logs : "เรียก AI"
    auth_users ||--o{ meal_plans : "สร้างแผน"
    auth_users |o--o{ weekly_meals : "เจ้าของมื้อ"
    auth_users |o--o{ recipes : "created_by"

    meal_plans ||--o{ weekly_meals : "มีมื้อ"

    recipes ||--o{ recipe_ingredients : "ประกอบด้วย"
    ingredients ||--o{ recipe_ingredients : "ใช้ใน"
    ingredients ||--o{ ingredient_aliases : "ชื่อเรียกอื่น"

    recipes ||--o{ user_saved_recipes : "ถูกบันทึกเป็น"
    recipes |o--o{ ai_request_logs : "ผลลัพธ์"
    recipes |o--o{ weekly_meals : "สูตรของมื้อ"
    ingredients |o--o{ fridge_items : "จับคู่ชื่อ"

    auth_users {
        uuid id PK
        text email UK
        jsonb raw_user_meta_data "first_name, last_name, phone, notify_days, last_expiry_notify_date"
    }

    profiles {
        uuid id PK, FK "* ยังไม่มีโค้ดแอปอ้างถึง"
        text first_name "ซ้ำกับ user_metadata"
        text last_name "ซ้ำกับ user_metadata"
        text phone "ซ้ำกับ user_metadata"
        timestamptz created_at
    }

    recipes {
        uuid id PK
        text name
        text name_key "generated: normalize_text(name)"
        text time_text
        int time_minutes
        text servings_text
        jsonb instructions
        int_array ai_step_indexes
        numeric calories_per_serving
        numeric protein_per_serving
        text_array diet_tags
        text image_url
        text image_hash "UNIQUE เมื่อ is_public"
        text source "ai_generated | scanned | manual"
        text ingredient_signature
        bigint_array ingredient_ids "sync โดย trigger"
        boolean is_public
        uuid created_by FK
        int use_count
        timestamptz created_at
        timestamptz updated_at
    }

    ingredients {
        bigint id PK
        text name
        text name_key UK
        text category
        boolean is_staple
        text default_unit
        timestamptz created_at
    }

    ingredient_aliases {
        bigint id PK
        text alias
        text alias_key UK
        bigint ingredient_id FK
    }

    recipe_ingredients {
        uuid recipe_id PK, FK
        smallint sort_order PK
        bigint ingredient_id FK
        text display_name
        numeric quantity
        text unit
        boolean is_main
    }

    user_saved_recipes {
        uuid id PK
        uuid user_id FK "UNIQUE (user_id, recipe_id)"
        uuid recipe_id FK
        jsonb overrides "รวม scan_image_path"
        boolean is_favorite
        timestamptz created_at
        timestamptz updated_at
    }

    ai_request_logs {
        bigint id PK
        uuid user_id FK
        uuid recipe_id FK
        text event_type "scan_recipe | generate_menu | meal_plan | scan_ingredient"
        text result "cache_hit | gemini | not_recipe | failed"
        text image_hash
        text model
        int prompt_tokens
        int output_tokens
        timestamptz created_at
    }

    fridge_items {
        bigint item_id PK "*"
        uuid user_id FK
        bigint ingredient_id FK "ใหม่, trigger จากชื่อ"
        text name
        text category
        numeric quantity
        numeric max_quantity
        text unit
        numeric detected_quantity
        text detected_unit
        text storage "fridge | freezer"
        text food_state
        int fridge_days
        int freezer_days
        text shelf_type
        timestamptz expiry_date
        timestamptz storage_changed_at
        int days_left_at_freeze
        timestamptz thawed_at
        numeric use_per_cook "> 0"
        text image_path "bucket fridge-images"
        timestamptz created_at
    }

    meal_plans {
        bigint id PK "*"
        uuid user_id FK
        text goal
        int meals_per_day
        int target_calories
        int target_protein
        text diet_type
        boolean saved
        boolean is_favorite "แพลนโปรด"
        timestamptz created_at
    }

    weekly_meals {
        bigint id PK "*"
        bigint plan_id FK
        uuid recipe_id FK "ใหม่"
        uuid user_id FK "ใหม่"
        text day
        text meal_type
        text food_name "legacy"
        numeric calories "legacy"
        numeric protein "legacy"
        jsonb ingredients
        text steps
        boolean is_cooked
        timestamptz created_at
    }
```

## วิธีอ่านเส้นความสัมพันธ์

| สัญลักษณ์ | ความหมาย | ตัวอย่าง |
|---|---|---|
| `\|\|--o{` | 1 ต่อ 0..N (FK ห้ามว่าง) | 1 สูตร มีส่วนผสม 0..N แถว |
| `\|o--o{` | 0..1 ต่อ 0..N (FK เป็น NULL ได้) | มื้ออาหารอาจยังไม่ผูกสูตรกลาง |
| `\|\|--o\|` | 1 ต่อ 0..1 | ผู้ใช้ 1 คน มีโปรไฟล์ได้ไม่เกิน 1 แถว |

## จุดสำคัญ

- **recipes ↔ ingredients เป็น M:N** ผ่าน `recipe_ingredients` (PK รวม `recipe_id + sort_order`)
- **user_saved_recipes** เป็นตารางกลางระหว่างผู้ใช้กับสูตรกลาง — ผู้ใช้แก้สูตรได้ผ่าน `overrides` โดยไม่กระทบสูตรของคนอื่น
- **fridge_items.ingredient_id** และ **weekly_meals.recipe_id** เป็น FK ที่ NULL ได้ (ข้อมูลเดิมอาจจับคู่ไม่ได้)
- **profiles** มี first_name / last_name / phone แต่แอปอ่าน-เขียนค่าเหล่านี้ที่ `user_metadata` แทน (ข้อมูลซ้ำสองที่)
- **แพลนโปรด** เก็บที่ `meal_plans.is_favorite` (เดิมอยู่ใน `user_metadata.favorite_plan_ids` ซึ่งเลิกใช้แล้ว)
- ON DELETE: ลบผู้ใช้ → ลบ fridge/saved/logs/meals ของผู้ใช้ (CASCADE) แต่ `recipes.created_by` กลายเป็น NULL (สูตรสาธารณะยังอยู่)
