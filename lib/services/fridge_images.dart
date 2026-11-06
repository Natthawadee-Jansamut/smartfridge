import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// รูปที่ผู้ใช้สแกน เก็บในที่เก็บไฟล์แบบส่วนตัว (ไม่ใช่สาธารณะ)
/// ไฟล์อยู่ในโฟลเดอร์ชื่อ user id และเปิดดูได้เฉพาะเจ้าของ
///
/// - [fridgeImageBucket]: รูปวัตถุดิบตอนเอาเข้าตู้เย็น
///   (supabase/sql/fridge_items_use_per_cook_and_image.sql)
/// - [recipeScanImageBucket]: รูปสูตรอาหารที่สแกน
///   (supabase/sql/recipe_scan_images_bucket.sql)
const fridgeImageBucket = 'fridge-images';
const recipeScanImageBucket = 'recipe-scan-images';

/// อัปโหลดรูป คืน path ของไฟล์ (ไม่สำเร็จ = null ให้บันทึกข้อมูลต่อได้ แค่ไม่มีรูป)
Future<String?> uploadPrivateImage(
  String bucket,
  String userId,
  Uint8List bytes,
) async {
  try {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  } catch (e) {
    debugPrint('อัปโหลดรูปไป $bucket ไม่สำเร็จ: $e');
    return null;
  }
}

/// ลิงก์ชั่วคราว 1 ชั่วโมงสำหรับแสดงรูป (ที่เก็บแบบส่วนตัวต้องขอลิงก์เอง)
/// ไม่สำเร็จ = null
Future<String?> privateImageUrl(String bucket, String path) async {
  try {
    return await Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(path, 60 * 60);
  } catch (e) {
    debugPrint('โหลดรูปจาก $bucket ไม่สำเร็จ: $e');
    return null;
  }
}

Future<String?> uploadFridgeImage(String userId, Uint8List bytes) =>
    uploadPrivateImage(fridgeImageBucket, userId, bytes);

Future<String?> fridgeImageUrl(String path) =>
    privateImageUrl(fridgeImageBucket, path);
