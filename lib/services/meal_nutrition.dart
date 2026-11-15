import 'dart:convert'; // ใช้ jsonDecode แปลงข้อความ JSON จาก AI เป็นข้อมูล

import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/config/api_keys.dart'; // คีย์ AI
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';

/// ค่าโภชนาการของมื้ออาหารในแพลน (weekly_meals)
///
/// calories / protein ถูกประมาณโดย AI ตอนสร้างแพลน ถ้าผู้ใช้แก้วัตถุดิบ
/// ค่าพวกนี้จะไม่ตรงอีกต่อไป — แอปจะติดธง `nutrition_stale: true` ไว้ที่
/// วัตถุดิบแต่ละรายการใน weekly_meals.ingredients (jsonb เดิม ไม่ต้องแก้ตาราง)
/// แล้วให้ผู้ใช้กด "คำนวณใหม่" เอง (เรียก AI เฉพาะตอนกด ประหยัด token)
class MealNutrition {
  MealNutrition._(); // ห้ามสร้างตัวแปรจากคลาสนี้

  // ชื่อธงที่ติดไว้ในวัตถุดิบ = ค่าโภชนาการไม่ตรงแล้ว ต้องคำนวณใหม่
  static const staleKey = 'nutrition_stale';

  /// "ค่าเดิม" ก่อนแก้วัตถุดิบครั้งแรก: {calories, protein, ingredients: [ข้อความ]}
  /// เก็บซ้ำไว้ในทุกรายการ (ลบรายการไหนทิ้งก็ยังมีค่าเดิมเหลือ)
  static const baseKey = 'nutrition_base';

  // ดึงรายการวัตถุดิบของมื้อออกมาเป็นลิสต์ (ข้อมูลผิดรูปแบบ = ลิสต์ว่าง)
  static List<Map<String, dynamic>> _ingredientsOf(Map<String, dynamic> meal) {
    final raw = meal['ingredients'];
    if (raw is! List) return []; // ไม่ใช่ลิสต์ = ไม่มีวัตถุดิบ
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
    for (final e in _ingredientsOf(meal)) { // หาในวัตถุดิบทีละรายการ
      final base = e[baseKey];
      if (base is Map) return Map<String, dynamic>.from(base); // เจอค่าเดิมแล้ว ส่งกลับเลย
    }
    return null;
  }

  // แปลงวัตถุดิบเป็นข้อความ เช่น "ไข่ไก่ 2 ฟอง"
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
    if (calories == null || protein == null) return null; // ไม่มีค่าเดิมให้จำ
    return { // จำแคลอรี/โปรตีน และรายการวัตถุดิบก่อนแก้
      'calories': calories,
      'protein': protein,
      'ingredients': ingredientsBefore.map(_describe).toList(),
    };
  }

  /// แอปแปลงปริมาณวัตถุดิบเป็นหน่วยของตู้เย็นเอง (เช่น "เมลอน 1 ลูก" -> "1 ส่วน")
  /// แต่แคลอรี/โปรตีนของ [meal] (บันทึกแล้ว) ยังคิดจากปริมาณก่อนแปลง [before]
  /// — ติดค่าเดิม+ธงไว้ แล้วให้ AI คำนวณใหม่ทันที ถ้าไม่สำเร็จ ธงยังอยู่
  /// หน้าแพลนจะเตือนให้กด "คำนวณใหม่" เอง
  static Future<Map<String, dynamic>> recalculateAfterUnitChange(
    Map<String, dynamic> meal,
    List<String> before,
  ) async {
    final base = {
      'calories': meal['calories'],
      'protein': meal['protein'],
      'ingredients': before,
    };
    // ติดธง "ต้องคำนวณใหม่" + ค่าเดิม ให้วัตถุดิบทุกรายการ
    final flagged = {
      ...meal,
      'ingredients': [
        for (final e in _ingredientsOf(meal))
          {...e, staleKey: true, baseKey: base},
      ],
    };
    await Supabase.instance.client
        .from('weekly_meals')
        .update({'ingredients': flagged['ingredients']}) // บันทึกธงลงฐานข้อมูลก่อน
        .eq('id', meal['id']);
    try {
      return await recalculate(flagged); // ให้ AI คำนวณใหม่ทันที
    } catch (_) {
      return flagged; // AI ไม่สำเร็จ ส่งมื้อที่ติดธงกลับไป (ผู้ใช้กดคำนวณใหม่เองได้)
    }
  }

  /// ให้ AI ประมาณแคลอรี/โปรตีนใหม่จากวัตถุดิบปัจจุบัน แล้วบันทึกลง weekly_meals
  /// (ล้างธง nutrition_stale ออก) คืนค่า meal ที่อัปเดตแล้ว
  static Future<Map<String, dynamic>> recalculate(
    Map<String, dynamic> meal,
  ) async {
    final ingredients = _ingredientsOf(meal); // วัตถุดิบปัจจุบัน
    final list = ingredients.map((e) => '- ${_describe(e)}').join('\n'); // ทำเป็นรายการทีละบรรทัดสำหรับ prompt
    final base = baseOf(meal); // ค่าเดิมก่อนแก้ (ถ้ามี)
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

    // ส่ง prompt ไปให้ Gemini
    final res = await generateGemini(
      apiKey: ApiKeys.mealPlanScreen,
      logEvent: AiEvent.mealPlan, // บันทึกประวัติการใช้ AI
      content: [Content.text(prompt)],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json', // บังคับให้ตอบเป็น JSON
        temperature: 0.2, // ความสุ่มของคำตอบ (ต่ำ = ตอบนิ่ง ตรงไปตรงมา)
      ),
      timeout: const Duration(seconds: 45), // รอนานสุด 45 วินาที
    );

    // ล้างเครื่องหมาย ``` ที่ AI อาจใส่มา
    final text = (res.text ?? '')
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final start = text.indexOf('{'); // หาจุดเริ่ม JSON
    final end = text.lastIndexOf('}'); // หาจุดจบ JSON
    if (start == -1 || end <= start) {
      throw 'อ่านผลการคำนวณจาก AI ไม่ได้ กรุณาลองใหม่';
    }
    final json = jsonDecode(text.substring(start, end + 1)); // แปลงข้อความเป็นข้อมูล
    // ตัวช่วยแปลงค่าเป็นตัวเลข (ตัดลูกน้ำออกก่อน เช่น "1,200")
    num? toNum(Object? v) =>
        v is num ? v : num.tryParse(v?.toString().replaceAll(',', '') ?? '');
    final calories = toNum(json is Map ? json['calories'] : null);
    final protein = toNum(json is Map ? json['protein'] : null);
    if (calories == null || protein == null || calories < 0 || protein < 0) { // ค่าผิดปกติ
      throw 'อ่านผลการคำนวณจาก AI ไม่ได้ กรุณาลองใหม่';
    }

    // ลบธงและค่าเดิมออกจากวัตถุดิบ (คำนวณใหม่แล้ว ไม่ต้องเตือนอีก)
    final cleaned = [
      for (final e in ingredients)
        {...e}
          ..remove(staleKey)
          ..remove(baseKey),
    ];
    final update = { // ค่าที่จะบันทึก (ปัดเป็นจำนวนเต็ม)
      'calories': calories.round(),
      'protein': protein.round(),
      'ingredients': cleaned,
    };
    await Supabase.instance.client
        .from('weekly_meals')
        .update(update) // บันทึกลงฐานข้อมูล
        .eq('id', meal['id']);
    return {...meal, ...update}; // ส่งมื้อที่อัปเดตแล้วกลับ
  }
}
