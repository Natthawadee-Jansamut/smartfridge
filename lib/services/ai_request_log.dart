import 'package:flutter/foundation.dart'; // ใช้ debugPrint
import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini (ใช้ชนิด UsageMetadata = จำนวน token)
import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้บันทึกลงฐานข้อมูล

/// ประเภทงาน AI (ตรงกับ ai_request_logs.event_type)
abstract final class AiEvent {
  static const scanRecipe = 'scan_recipe'; // สแกนรูปสูตรอาหาร
  static const generateMenu = 'generate_menu'; // สร้างเมนูจากของในตู้
  static const mealPlan = 'meal_plan'; // สร้างแพลนอาหารรายสัปดาห์
  static const scanIngredient = 'scan_ingredient'; // สแกนรูปวัตถุดิบ
}

/// ผลลัพธ์ของคำขอ (ตรงกับ ai_request_logs.result)
abstract final class AiResult {
  /// เจอผลเดิมในฐานข้อมูล ไม่ได้เรียก Gemini
  static const cacheHit = 'cache_hit';

  /// เรียก Gemini สำเร็จ
  static const gemini = 'gemini';

  /// เรียก Gemini สำเร็จ แต่รูปไม่ใช่สูตรอาหาร
  static const notRecipe = 'not_recipe';

  /// เรียก Gemini ไม่สำเร็จ (503, หมดโควตา, timeout ฯลฯ)
  static const failed = 'failed';
}

/// บันทึกการใช้ AI ลงตาราง ai_request_logs (ใช้ดูสถิติ/จำนวน token ที่ใช้)
///
/// ทำงานเบื้องหลังเสมอ: ไม่ต้อง await และถ้าบันทึกไม่สำเร็จ
/// จะแค่ debugPrint ไม่ทำให้ฟีเจอร์หลักพัง
void logAiRequest({
  required String event, // งานอะไร (ค่าจาก AiEvent)
  required String result, // ผลเป็นยังไง (ค่าจาก AiResult)
  String? model, // ชื่อโมเดล Gemini ที่ใช้
  UsageMetadata? usage, // จำนวน token ที่ใช้
  Object? recipeId, // id สูตรที่เกี่ยวข้อง (ถ้ามี)
  String? imageHash, // รหัสลายนิ้วมือของรูป (ไว้เช็ครูปซ้ำ)
}) {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return; // ยังไม่ล็อกอิน ไม่ต้องบันทึก

  client
      .from('ai_request_logs') // ตารางเก็บประวัติการใช้ AI
      .insert({ // เพิ่มแถวใหม่ 1 แถว
        'event_type': event,
        'result': result,
        'model': model,
        'prompt_tokens': usage?.promptTokenCount, // token ขาส่ง (คำถาม)
        'output_tokens': usage?.candidatesTokenCount, // token ขากลับ (คำตอบ)
        'recipe_id': recipeId,
        'image_hash': imageHash,
      })
      .then<void>((_) {}) // สำเร็จก็ไม่ต้องทำอะไรต่อ
      .catchError((Object e) { // ไม่สำเร็จ แค่พิมพ์ error ไม่ให้แอปพัง
        debugPrint('บันทึก ai_request_logs ไม่สำเร็จ: $e');
      });
}
