import 'package:crypto/crypto.dart'; // ใช้คำนวณ sha256 (ลายนิ้วมือของไฟล์รูป)
import 'package:flutter/foundation.dart'; // ใช้ debugPrint / Uint8List
import 'package:google_generative_ai/google_generative_ai.dart'; // ใช้ชนิด UsageMetadata
import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้ฐานข้อมูล

import 'package:test_app/services/gemini_retry.dart'; // ชื่อโมเดล Gemini
import 'package:test_app/services/recipe_repository.dart'; // ตัวช่วยแปลงเวลาทำอาหารเป็นนาที

/// คลังสูตรอาหารกลางบน Supabase (ตาราง recipes) — ค้นที่นี่ก่อนเรียก Gemini
/// เพื่อประหยัด token แล้วเก็บผลลัพธ์ใหม่จาก Gemini กลับเข้าคลังให้คนถัดไปใช้
///
/// ทุกเมธอดไม่ throw: ถ้ายังไม่ได้รัน migration (ไม่มี RPC / ตาราง) หรือเน็ตมีปัญหา
/// จะคืนผลว่าง แล้วหน้าจอเรียก Gemini ต่อเหมือนเดิม — แอปจึงไม่พังเพราะคลังกลาง
/// (ดู supabase/migrations/20261104000000_global_recipes.sql)
class GlobalRecipeService {
  GlobalRecipeService._(); // ห้ามสร้างตัวแปรจากคลาสนี้

  static SupabaseClient get _db => Supabase.instance.client; // ทางลัดเรียกฐานข้อมูล

  /// เจอว่ายังไม่มี RPC / ตารางบนเซิร์ฟเวอร์แล้ว ไม่ต้องลองซ้ำจนกว่าจะเปิดแอปใหม่
  static bool _unavailable = false;

  // เช็คว่า error เกิดเพราะบนเซิร์ฟเวอร์ยังไม่มีตาราง/ฟังก์ชันนี้หรือเปล่า
  static bool _isMissingOnServer(Object e) {
    if (e is! PostgrestException) return false; // ไม่ใช่ error จากฐานข้อมูล
    // PGRST202 = ไม่พบฟังก์ชัน, PGRST205 / 42P01 = ไม่พบตาราง, 42883 = ไม่พบฟังก์ชัน (SQL)
    return const {'PGRST202', 'PGRST205', '42P01', '42883'}.contains(e.code);
  }

  // จัดการ error กลาง: ถ้าเซิร์ฟเวอร์ไม่มีของ ให้ปิดใช้คลังกลางไปเลย แล้วพิมพ์ error
  static void _handleError(String what, Object e) {
    if (_isMissingOnServer(e)) _unavailable = true;
    debugPrint('คลังสูตรกลาง: $what ไม่สำเร็จ — $e');
  }

  /// sha256 ของไฟล์รูป (รูปเดียวกันเป๊ะ = hash เดียวกัน)
  static String imageHash(Uint8List bytes) => sha256.convert(bytes).toString();

  /// ชื่อวัตถุดิบในตู้เย็นที่ยังใช้ทำอาหารได้ (ส่งให้ match_recipes_by_ingredients)
  static List<String> fridgeNames(Iterable<Map<String, dynamic>> items) => items
      .map((e) => (e['name'] ?? '').toString().trim()) // ดึงชื่อออกมา
      .where((n) => n.isNotEmpty) // ทิ้งชื่อว่าง
      .toSet() // ตัดชื่อซ้ำ
      .toList();

  // ------------------------------------------------------------------ Search

  /// สูตรที่ทำได้จากวัตถุดิบที่มี เรียงจากขาดของน้อยที่สุด
  /// แต่ละสูตรมี `missing_ingredients` (ชื่อวัตถุดิบที่ยังขาด) ติดมาด้วย
  static Future<List<Map<String, dynamic>>> matchByIngredients(
    List<String> ingredients, { // วัตถุดิบที่มี
    int maxMissing = 2, // ยอมให้ขาดวัตถุดิบได้ไม่เกิน 2 อย่าง
    double minMatchRatio = 0.5, // ต้องมีวัตถุดิบตรงอย่างน้อย 50% ของสูตร
    int? maxMinutes, // เวลาทำสูงสุด (นาที)
    num? maxCalories, // แคลอรีสูงสุด
    List<String>? dietTags, // ข้อจำกัดอาหาร
    int limit = 10, // เอามากี่สูตร
  }) async {
    if (_unavailable || ingredients.isEmpty) return []; // คลังกลางใช้ไม่ได้ หรือไม่มีวัตถุดิบ
    try {
      final rows = await _db.rpc( // เรียกฟังก์ชัน SQL บนเซิร์ฟเวอร์
        'match_recipes_by_ingredients',
        params: {
          'p_ingredients': ingredients,
          'p_max_missing': maxMissing,
          'p_min_match_ratio': minMatchRatio,
          'p_max_time_minutes': maxMinutes,
          'p_max_calories': maxCalories,
          'p_diet_tags': dietTags,
          'p_limit': limit,
        },
      );
      if (rows is! List) return []; // ผลไม่ใช่ลิสต์ = ไม่มีผล
      return rows.whereType<Map>().map((row) {
        final recipe = Map<String, dynamic>.from(row['recipe'] as Map); // ตัวสูตร
        recipe['missing_ingredients'] = List<String>.from( // แนบรายชื่อของที่ขาด
          (row['missing_ingredients'] as List?) ?? const [],
        );
        return recipe;
      }).toList();
    } catch (e) {
      _handleError('ค้นสูตรจากวัตถุดิบ', e);
      return [];
    }
  }

  /// สูตรที่เคยสแกนจากรูปเดียวกันนี้ (null = ไม่เคย)
  static Future<Map<String, dynamic>?> findByImageHash(String hash) async {
    if (_unavailable) return null;
    try {
      final rows = await _db.rpc(
        'find_recipe_by_image_hash', // ฟังก์ชันค้นสูตรจากลายนิ้วมือรูป
        params: {'p_image_hash': hash},
      );
      if (rows is! List || rows.isEmpty) return null; // ไม่เจอ
      return Map<String, dynamic>.from(rows.first['recipe'] as Map); // เจอ ส่งสูตรแรกกลับ
    } catch (e) {
      _handleError('ค้นสูตรจากรูป', e);
      return null;
    }
  }

  // -------------------------------------------------------------------- Save

  /// เก็บสูตรเข้าคลังกลาง (ไม่ Bookmark ให้ผู้ใช้) คืน recipe_id หรือ null
  /// [source]: 'ai_generated' | 'scanned' | 'manual'
  static Future<String?> cacheRecipe(
    Map<String, dynamic> recipe, {
    required String source, // ที่มาของสูตร
    String? imageHash,
    bool isPublic = true, // ให้คนอื่นเห็นได้ไหม
    List<String> dietTags = const [],
  }) async {
    if (_unavailable) return null;
    try {
      final payload = Map<String, dynamic>.from(recipe); // ก๊อปสูตรมาก่อน ไม่แก้ของเดิม
      if (dietTags.isNotEmpty) payload['diet_tags'] = dietTags; // แนบป้ายข้อจำกัดอาหาร
      final minutes = RecipeRepository.minutesOf(payload['time']); // แปลง "30 นาที" -> 30
      if (minutes != null) payload['time_minutes'] = minutes;

      final id = await _db.rpc( // เรียกฟังก์ชันบันทึกสูตรบนเซิร์ฟเวอร์
        'save_recipe',
        params: {
          'p_recipe': payload,
          'p_source': source,
          'p_image_hash': imageHash,
          'p_is_public': isPublic,
          'p_bookmark': false, // ไม่บันทึกเข้าคลังส่วนตัวของผู้ใช้
        },
      );
      return id?.toString(); // ส่ง id สูตรกลับ
    } catch (e) {
      _handleError('บันทึกสูตรเข้าคลัง', e);
      return null;
    }
  }

  /// เก็บหลายสูตรพร้อมกัน (เช่น เมนูที่ Gemini เพิ่งสร้าง) — ไม่ต้องรอผล
  static void cacheRecipesInBackground(
    Iterable<Map<String, dynamic>> recipes, {
    required String source,
    List<String> dietTags = const [],
  }) {
    for (final r in recipes) {
      cacheRecipe(r, source: source, dietTags: dietTags); // ไม่ await = ทำเบื้องหลัง
    }
  }

  // --------------------------------------------------------------------- Log

  /// บันทึกว่าครั้งนี้ใช้ cache หรือเรียก Gemini (ไว้ดูว่าประหยัด token ได้เท่าไหร่)
  /// [eventType]: 'scan_recipe' | 'generate_menu' | 'meal_plan' | 'scan_ingredient'
  /// [result]: 'cache_hit' | 'gemini' | 'not_recipe' | 'failed'
  static Future<void> log({
    required String eventType,
    required String result,
    String? recipeId,
    String? imageHash,
    UsageMetadata? usage,
  }) async {
    if (_unavailable || _db.auth.currentUser == null) return; // ใช้ไม่ได้ หรือยังไม่ล็อกอิน
    try {
      await _db.from('ai_request_logs').insert({ // เพิ่มแถวประวัติ
        'event_type': eventType,
        'result': result,
        'recipe_id': recipeId,
        'image_hash': imageHash,
        if (result == 'gemini') 'model': geminiModel, // ใส่ชื่อโมเดลเฉพาะตอนเรียก Gemini จริง
        'prompt_tokens': usage?.promptTokenCount,
        'output_tokens': usage?.candidatesTokenCount,
      });
    } catch (e) {
      _handleError('บันทึก log', e);
    }
  }
}
