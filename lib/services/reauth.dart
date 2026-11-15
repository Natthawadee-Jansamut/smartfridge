import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้ระบบล็อกอินของ Supabase

/// ยืนยันตัวตนอีกครั้งด้วยรหัสผ่านปัจจุบัน ก่อนทำสิ่งที่ย้อนกลับไม่ได้
/// (เปลี่ยนรหัสผ่าน / ลบบัญชี) — กันคนอื่นที่หยิบโทรศัพท์ที่ล็อกอินค้างไว้
///
/// ลองล็อกอินด้วยอีเมลของบัญชีที่ใช้อยู่กับรหัสผ่านที่กรอก (บัญชีเดิม ไม่เปลี่ยนผู้ใช้)
/// คืน true = รหัสผ่านถูก, false = ไม่ถูก/ไม่มีอีเมล
/// ปัญหาอื่น (เช่น เน็ตหลุด) โยน error ต่อ ให้หน้าจอแจ้ง "ลองใหม่"
Future<bool> verifyCurrentPassword(String password) async {
  final client = Supabase.instance.client; // ตัวเชื่อมต่อ Supabase
  final email = client.auth.currentUser?.email; // อีเมลของคนที่ล็อกอินอยู่ตอนนี้
  if (email == null || email.isEmpty || password.isEmpty) return false; // ไม่มีอีเมลหรือไม่ได้กรอกรหัส = ไม่ผ่าน
  try {
    await client.auth.signInWithPassword(email: email, password: password); // ลองล็อกอินซ้ำด้วยรหัสที่กรอก
    return true; // ล็อกอินผ่าน = รหัสถูก
  } on AuthException catch (e) { // ถ้าระบบล็อกอินแจ้งข้อผิดพลาด
    // รหัสผ่านผิด = invalid_credentials (400) — อย่างอื่น (เช่น ถูกจำกัดจำนวนครั้ง)
    // ให้หน้าจอแสดงข้อความจาก Supabase
    if (e.code == 'invalid_credentials' ||
        e.message.contains('Invalid login credentials')) {
      return false; // รหัสผิด
    }
    rethrow; // ปัญหาอื่น โยนต่อให้หน้าจอจัดการ
  }
}
