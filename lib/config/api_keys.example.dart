// เทมเพลตสำหรับเก็บ API Key ของโปรเจกต์
// วิธีใช้: คัดลอกไฟล์นี้ แล้วเปลี่ยนชื่อเป็น api_keys.dart (อยู่โฟลเดอร์เดียวกัน)
// จากนั้นใส่ API Key จริงของคุณแทนค่า YOUR_..._KEY_HERE ด้านล่าง
// ไฟล์ api_keys.dart จะไม่ถูก commit เข้า git (อยู่ใน .gitignore แล้ว)
//
// แยกคีย์รายฟังก์ชัน เผื่อบางหน้าอยากใช้คีย์คนละตัว (เช่น จำกัดโควตา/โทเคน
// แยกกันในอนาคต) ถ้ายังใช้คีย์เดียวกันทั้งหมดก็ใส่ค่าเดียวกันได้เลย
class ApiKeys {
  static const String aiRecipeScreen = 'YOUR_GEMINI_API_KEY_HERE';
  static const String mealPlanScreen = 'YOUR_GEMINI_API_KEY_HERE';
  static const String scanRecipeScreen = 'YOUR_GEMINI_API_KEY_HERE';
  static const String imageScanning = 'YOUR_GEMINI_API_KEY_HERE';
}
