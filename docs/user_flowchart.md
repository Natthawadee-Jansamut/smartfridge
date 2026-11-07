# SmartFridge.AI — User Flowchart (ฉบับย่อ)

อัปเดตล่าสุด: 6 พ.ย. 2026 · อ้างอิงการนำทางจริงใน `lib/screens/`

```mermaid
flowchart TD
    Start([เปิดแอป]) --> Session{มี session และ<br/>ติ๊ก Remember me?}
    Session -- ใช่ --> Home
    Session -- ไม่ --> Login

    subgraph Auth[เข้าสู่ระบบ]
        Login[Login] --> Register[สมัครสมาชิก] --> OTP[ยืนยันอีเมล OTP] --> Login
        Login --> Forgot[ลืมรหัสผ่าน] -. ลิงก์ smartfridge:// .-> Reset[ตั้งรหัสผ่านใหม่] --> Login
    end
    Login -- สำเร็จ --> Home

    Home[[เมนูหลัก]]

    Home --> F1[ถ่ายภาพวัตถุดิบ]
    F1 --> F1a[Gemini วิเคราะห์รูป] --> F1b[ตรวจ/แก้ชื่อ จำนวน ช่องเก็บ] --> Fridge

    Home --> Fridge[เช็คตู้เย็น<br/>รายการวัตถุดิบ]
    Fridge --> FridgeD[รายละเอียด<br/>แก้จำนวน / ย้ายช่องแช่แข็ง / ลบ]

    Home --> F3[แจ้งเตือน<br/>ของใกล้ครบระยะเก็บ]
    F3 --> FridgeD

    Home --> F4[สร้างเมนูอาหาร]
    F4 --> Lib1{คลังกลางมีเมนู<br/>ตรงของในตู้ ≥ 3?}
    Lib1 -- มี --> Menu[แสดงเมนู + ของที่ขาด]
    Lib1 -- ไม่มี / กด ให้ AI คิดใหม่ --> AI1[Gemini สร้างเมนู<br/>แล้วเก็บเข้าคลังกลาง] --> Menu
    Menu --> Detail[ดูสูตร] --> Cook[ทำอาหาร → หักวัตถุดิบในตู้]
    Detail --> Saved

    Home --> F5[สแกนสูตรอาหาร] --> Saved[คลังสูตรของฉัน]
    Saved --> Capture[ถ่าย/เลือกรูปสูตร]
    Capture --> Lib2{รูปนี้เคยสแกนแล้ว?}
    Lib2 -- ใช่ --> Review
    Lib2 -- ไม่ --> AI2[Gemini อ่านสูตร] --> Review[ตรวจ/แก้สูตร<br/>เทียบของในตู้] --> Saved
    Saved --> Manual[เขียนสูตรเอง] --> Saved
    Saved --> Detail

    Home --> F6[แพลนอาหาร]
    F6 --> NewPlan[ตั้งเป้าหมาย แคลอรี่ ข้อจำกัดอาหาร] --> AI3[ใช้เมนูจากคลังก่อน<br/>ขาดค่อยให้ Gemini สร้าง] --> Week[แผนรายสัปดาห์ → บันทึก]
    F6 --> MyPlan[แผนของฉัน] --> Week
    Week --> CookMeal[ทำมื้อนี้ → ติ๊กทำแล้ว]

    Home --> Profile[โปรไฟล์]
    Profile --> P1[แก้ไขข้อมูล / เปลี่ยนรหัสผ่าน /<br/>ตั้งค่าแจ้งเตือน / ลบบัญชี]
    Profile --> Logout([ออกจากระบบ]) --> Login
```

## สรุป 6 ฟีเจอร์จากเมนูหลัก

| ฟีเจอร์ | หน้าแรก | ผลลัพธ์ |
|---|---|---|
| ถ่ายภาพวัตถุดิบ | `ImageScanning` → `ResultScreen` | เพิ่มของเข้า `fridge_items` |
| เช็คตู้เย็น | `InventoryScreen` → `ItemDetailScreen` | ดู/แก้/ย้ายช่องเก็บ |
| แจ้งเตือน | `ExpirationAlertScreen` | เห็นของใกล้ครบระยะเก็บ |
| สร้างเมนูอาหาร | `AiRecipeScreen` | เมนูจากคลังกลางหรือ Gemini |
| สแกนสูตรอาหาร | `SavedRecipesScreen` → `ScanRecipeCaptureScreen` | บันทึกสูตรลง `user_saved_recipes` |
| แพลนอาหาร | `PlanMenuScreen` → `MealPlanScreen` / `MyPlanScreen` | แผนใน `meal_plans` + `weekly_meals` |

ทุกจุดที่เรียก AI จะ **ค้นคลังกลาง (`recipes`) ก่อน** แล้วค่อยเรียก Gemini เพื่อประหยัด token
