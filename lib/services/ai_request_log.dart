import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ประเภทงาน AI (ตรงกับ ai_request_logs.event_type)
abstract final class AiEvent {
  static const scanRecipe = 'scan_recipe';
  static const generateMenu = 'generate_menu';
  static const mealPlan = 'meal_plan';
  static const scanIngredient = 'scan_ingredient';
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
  required String event,
  required String result,
  String? model,
  UsageMetadata? usage,
  Object? recipeId,
  String? imageHash,
}) {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return;

  client
      .from('ai_request_logs')
      .insert({
        'event_type': event,
        'result': result,
        'model': model,
        'prompt_tokens': usage?.promptTokenCount,
        'output_tokens': usage?.candidatesTokenCount,
        'recipe_id': recipeId,
        'image_hash': imageHash,
      })
      .then<void>((_) {})
      .catchError((Object e) {
        debugPrint('บันทึก ai_request_logs ไม่สำเร็จ: $e');
      });
}
