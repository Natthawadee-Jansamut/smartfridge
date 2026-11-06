// เทมเพลตสำหรับค่าเชื่อมต่อ Supabase ของโปรเจกต์
// วิธีใช้: คัดลอกไฟล์นี้ แล้วเปลี่ยนชื่อเป็น supabase_config.dart (อยู่โฟลเดอร์เดียวกัน)
// จากนั้นใส่ Project URL และ anon key จาก Supabase Dashboard > Project Settings > API
// ไฟล์ supabase_config.dart จะไม่ถูก commit เข้า git (อยู่ใน .gitignore แล้ว)
class SupabaseConfig {
  static const String url = 'https://YOUR_PROJECT_REF.supabase.co';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY_HERE';
}
