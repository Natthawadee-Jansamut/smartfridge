import 'package:shared_preferences/shared_preferences.dart'; // ตัวช่วยเก็บค่าเล็กๆ ลงในเครื่อง (ปิดแอปแล้วค่ายังอยู่)

/// เก็บตัวเลือก "Remember me" ของหน้า Login ไว้ในเครื่อง
///
/// ตัว session เองถูก Supabase เก็บไว้ในเครื่องอยู่แล้ว ค่านี้แค่บอกว่าตอนเปิดแอป
/// ครั้งถัดไปควรใช้ session นั้นต่อ หรือให้ login ใหม่
class RememberMe {
  static const _key = 'remember_me'; // ชื่อช่องที่ใช้เก็บค่าในเครื่อง (เหมือนชื่อลิ้นชัก)

  // ถามว่าครั้งก่อนผู้ใช้ติ๊ก Remember me ไว้หรือเปล่า
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance(); // เปิดที่เก็บค่าในเครื่อง
    return prefs.getBool(_key) ?? false; // อ่านค่า ถ้ายังไม่เคยบันทึกเลยให้ถือว่า "ไม่ได้ติ๊ก" (false)
  }

  // บันทึกว่าผู้ใช้ติ๊ก (true) หรือไม่ติ๊ก (false) Remember me
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance(); // เปิดที่เก็บค่าในเครื่อง
    await prefs.setBool(_key, value); // เขียนค่าลงไป
  }
}
