
import 'package:flutter/foundation.dart'; // ใช้ debugPrint พิมพ์ข้อความตอนทดสอบ
import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้ที่เก็บไฟล์ (Storage) ของ Supabase

/// รูปที่ผู้ใช้สแกน เก็บในที่เก็บไฟล์แบบส่วนตัว (ไม่ใช่สาธารณะ)
/// ไฟล์อยู่ในโฟลเดอร์ชื่อ user id และเปิดดูได้เฉพาะเจ้าของ
///
/// - [fridgeImageBucket]: รูปวัตถุดิบตอนเอาเข้าตู้เย็น
///   (supabase/sql/fridge_items_use_per_cook_and_image.sql)
/// - [recipeScanImageBucket]: รูปสูตรอาหารที่สแกน
///   (supabase/sql/recipe_scan_images_bucket.sql)
const fridgeImageBucket = 'fridge-images'; // ชื่อถังเก็บรูปวัตถุดิบ
const recipeScanImageBucket = 'recipe-scan-images'; // ชื่อถังเก็บรูปสูตรอาหาร

/// อัปโหลดรูป คืน path ของไฟล์ (ไม่สำเร็จ = null ให้บันทึกข้อมูลต่อได้ แค่ไม่มีรูป)
Future<String?> uploadPrivateImage(
  String bucket, // ถังที่จะเก็บ
  String userId, // id ของผู้ใช้ (ใช้เป็นชื่อโฟลเดอร์)
  Uint8List bytes, // ตัวไฟล์รูป
) async {
  try {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg'; // ตั้งชื่อไฟล์ = เวลาปัจจุบัน (ไม่ซ้ำกัน)
    await Supabase.instance.client.storage
        .from(bucket) // เลือกถัง
        .uploadBinary( // อัปโหลดไฟล์ขึ้นไป
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'), // บอกว่าเป็นไฟล์รูป jpg
        );
    return path; // ส่งที่อยู่ไฟล์กลับไปให้บันทึกในฐานข้อมูล
  } catch (e) {
    debugPrint('อัปโหลดรูปไป $bucket ไม่สำเร็จ: $e'); // พิมพ์ error ไว้ดูตอนพัฒนา
    return null; // ไม่สำเร็จก็ไม่เป็นไร แค่ไม่มีรูป
  }
}

/// ลิงก์ชั่วคราว 1 ชั่วโมงสำหรับแสดงรูป (ที่เก็บแบบส่วนตัวต้องขอลิงก์เอง)
/// ไม่สำเร็จ = null
Future<String?> privateImageUrl(String bucket, String path) async {
  try {
    return await Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(path, 60 * 60); // ขอลิงก์ที่ใช้ได้ 60*60 วินาที = 1 ชั่วโมง (แก้ตัวเลขเพื่อเปลี่ยนอายุลิงก์)
  } catch (e) {
    debugPrint('โหลดรูปจาก $bucket ไม่สำเร็จ: $e');
    return null;
  }
}

// ทางลัด: อัปโหลดรูปวัตถุดิบเข้าถังของตู้เย็น
Future<String?> uploadFridgeImage(String userId, Uint8List bytes) =>
    uploadPrivateImage(fridgeImageBucket, userId, bytes);
