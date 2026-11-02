import 'package:shared_preferences/shared_preferences.dart';

/// เก็บตัวเลือก "Remember me" ของหน้า Login ไว้ในเครื่อง
///
/// ตัว session เองถูก Supabase เก็บไว้ในเครื่องอยู่แล้ว ค่านี้แค่บอกว่าตอนเปิดแอป
/// ครั้งถัดไปควรใช้ session นั้นต่อ หรือให้ login ใหม่
class RememberMe {
  static const _key = 'remember_me';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
