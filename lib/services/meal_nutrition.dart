import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';

/// ค่าโภชนาการของมื้ออาหารในแพลน (weekly_meals)
///
/// calories / protein ถูกประมาณโดย AI ตอนสร้างแพลน ถ้าผู้ใช้แก้วัตถุดิบ
/// ค่าพวกนี้จะไม่ตรงอีกต่อไป — แอปจะติดธง `nutrition_stale: true` ไว้ที่
/// วัตถุดิบแต่ละรายการใน weekly_meals.ingredients (jsonb เดิม ไม่ต้องแก้ตาราง)
/// แล้วให้ผู้ใช้กด "คำนวณใหม่" เอง (เรียก AI เฉพาะตอนกด ประหยัด token)
class MealNutrition {
  MealNutrition._();

  static const staleKey = 'nutrition_stale';

  /// "ค่าเดิม" ก่อนแก้วัตถุดิบครั้งแรก: {calories, protein, ingredients: [ข้อความ]}
  /// เก็บซ้ำไว้ในทุกรายการ (ลบรายการไหนทิ้งก็ยังมีค่าเดิมเหลือ)
  static const baseKey = 'nutrition_base';

  static List<Map<String, dynamic>> _ingredientsOf(Map<String, dynamic> meal) {
    final raw = meal['ingredients'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// แคลอรี/โปรตีนของมื้อนี้ยังเป็นค่าของเมนูเดิม (ก่อนแก้วัตถุดิบ) หรือไม่
  static bool isStale(Map<String, dynamic>? meal) =>
      meal != null && _ingredientsOf(meal).any((e) => e[staleKey] == true);

  /// ค่าเดิมที่จำไว้ (null = ไม่มี เช่น แก้วัตถุดิบไปก่อนมีฟีเจอร์นี้)
  static Map<String, dynamic>? baseOf(Map<String, dynamic>? meal) {
    if (meal == null) return null;
    for (final e in _ingredientsOf(meal)) {
      final base = e[baseKey];
      if (base is Map) return Map<String, dynamic>.from(base);
    }
    return null;
  }

  static String _describe(Map<String, dynamic> e) {
    final qty = (e['quantity'] ?? '').toString().trim();
    return '${e['name']}${qty.isEmpty ? '' : ' $qty'}';
  }

  /// สร้าง "ค่าเดิม" จากมื้อก่อนแก้ — null ถ้ามื้อนี้ไม่มีค่าแคลอรี/โปรตีนให้อ้างอิง
  static Map<String, dynamic>? snapshot(
    Map<String, dynamic>? meal,
    List<Map<String, dynamic>> ingredientsBefore,
  ) {
    if (meal == null) return null;
    final calories = meal['calories'];
    final protein = meal['protein'];
    if (calories == null || protein == null) return null;
    return {
      'calories': calories,
      'protein': protein,
      'ingredients': ingredientsBefore.map(_describe).toList(),
    };
  }

  /// ให้ AI ประมาณแคลอรี/โปรตีนใหม่จากวัตถุดิบปัจจุบัน แล้วบันทึกลง weekly_meals
  /// (ล้างธง nutrition_stale ออก) คืนค่า meal ที่อัปเดตแล้ว
  static Future<Map<String, dynamic>> recalculate(
    Map<String, dynamic> meal,
  ) async {
    final ingredients = _ingredientsOf(meal);
    final list = ingredients.map((e) => '- ${_describe(e)}').join('\n');
    final base = baseOf(meal);
    final baseList = base?['ingredients'] is List
        ? (base!['ingredients'] as List).map((e) => '- $e').join('\n')
        : null;

    // มีค่าเดิม -> ให้ปรับจากค่าเดิมตามส่วนที่เปลี่ยน (ตัวเลขจะสอดคล้องกับแพลนเดิม
    // ไม่กระโดดไปมาเพราะ AI เดาน้ำหนักของ "1 ส่วน/1 ชิ้น" ไม่เหมือนเดิม)
    // ไม่มีค่าเดิม -> ประมาณใหม่ทั้งหมดจากวัตถุดิบปัจจุบัน
    final prompt = baseList != null
        ? '''
ปรับค่าโภชนาการของอาหาร 1 มื้อ (1 ที่) หลังผู้ใช้แก้วัตถุดิบ
ชื่อเมนู: ${meal['food_name'] ?? ''}

ค่าเดิม: ${base!['calories']} kcal, โปรตีน ${base['protein']} g
จากวัตถุดิบเดิม:
$baseList

วัตถุดิบใหม่:
$list

กติกา:
- ยึดค่าเดิมเป็นฐาน แล้วปรับเฉพาะส่วนที่วัตถุดิบเปลี่ยน (เพิ่ม/ลด/เปลี่ยนปริมาณ/เปลี่ยนชนิด)
- วัตถุดิบที่ไม่เปลี่ยน ให้ถือว่าให้พลังงาน/โปรตีนเท่าเดิม
- ถ้าวัตถุดิบไม่ได้เปลี่ยนในส่วนที่มีผลต่อค่า ให้ตอบค่าเดิม

ตอบกลับเป็น JSON Object เท่านั้น ห้ามมีข้อความอื่นและห้ามมี Markdown:
{"calories": 450, "protein": 30}
- calories = พลังงาน (kcal) เป็นจำนวนเต็ม
- protein = โปรตีน (กรัม) เป็นจำนวนเต็ม
'''
        : '''
ประมาณค่าโภชนาการของอาหาร 1 มื้อ (1 ที่) จากชื่อเมนูและวัตถุดิบด้านล่าง
ชื่อเมนู: ${meal['food_name'] ?? ''}
วัตถุดิบ:
$list

ตอบกลับเป็น JSON Object เท่านั้น ห้ามมีข้อความอื่นและห้ามมี Markdown:
{"calories": 450, "protein": 30}
- calories = พลังงาน (kcal) เป็นจำนวนเต็ม
- protein = โปรตีน (กรัม) เป็นจำนวนเต็ม
''';

    final res = await generateGemini(
      apiKey: ApiKeys.mealPlanScreen,
      logEvent: AiEvent.mealPlan,
      content: [Content.text(prompt)],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.2,
      ),
      timeout: const Duration(seconds: 45),
    );

    final text = (res.text ?? '')
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw 'อ่านผลการคำนวณจาก AI ไม่ได้ กรุณาลองใหม่';
    }
    final json = jsonDecode(text.substring(start, end + 1));
    num? toNum(Object? v) =>
        v is num ? v : num.tryParse(v?.toString().replaceAll(',', '') ?? '');
    final calories = toNum(json is Map ? json['calories'] : null);
    final protein = toNum(json is Map ? json['protein'] : null);
    if (calories == null || protein == null || calories < 0 || protein < 0) {
      throw 'อ่านผลการคำนวณจาก AI ไม่ได้ กรุณาลองใหม่';
    }

    final cleaned = [
      for (final e in ingredients)
        {...e}
          ..remove(staleKey)
          ..remove(baseKey),
    ];
    final update = {
      'calories': calories.round(),
      'protein': protein.round(),
      'ingredients': cleaned,
    };
    await Supabase.instance.client
        .from('weekly_meals')
        .update(update)
        .eq('id', meal['id']);
    return {...meal, ...update};
  }
}
