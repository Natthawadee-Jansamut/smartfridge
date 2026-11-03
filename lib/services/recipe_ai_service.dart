import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'package:test_app/config/api_keys.dart';

/// ข้อผิดพลาดที่ตั้งใจแสดงให้ผู้ใช้เห็นตรงๆ
class RecipeAiException implements Exception {
  final String message;
  const RecipeAiException(this.message);
  @override
  String toString() => message;
}

/// งานฝั่ง Gemini ของฟีเจอร์สูตรอาหาร: สแกนสูตรจากรูป
class RecipeAiService {
  RecipeAiService._();

  static const _modelName = 'gemini-3.6-flash';
  static const _timeout = Duration(seconds: 60);
  static final _stepNumberPrefix = RegExp(r'^\s*\d+\s*[\.\)]\s*');

  static const _schema = '''
ตอบกลับเป็น JSON Object เท่านั้น ตามรูปแบบนี้เป๊ะๆ:
{
  "recipe_name": "ชื่อเมนู",
  "time": "เวลาทำ (เช่น 30 นาที)",
  "servings": "จำนวนที่ได้ (เช่น 2 ที่)",
  "ingredients_used": ["วัตถุดิบหลัก1", "วัตถุดิบหลัก2"],
  "detailed_ingredients": [
    {"name": "ชื่อวัตถุดิบภาษาไทย", "use_quantity": 1, "unit": "หน่วย"}
  ],
  "instructions": [
    {"text": "ขั้นตอนแรก (ไม่ต้องใส่เลขข้อ)", "ai_generated": false}
  ]
}
- use_quantity ต้องเป็นตัวเลขเท่านั้น (เช่น 0.5 แทน "ครึ่ง") ถ้าไม่ระบุให้ใส่ null
- unit ใช้หน่วยครัวไทย เช่น กรัม, ช้อนโต๊ะ, ช้อนชา, ถ้วย, ฟอง, ชิ้น, ลูก, กลีบ, ส่วน
- ห้ามมีข้อความอธิบายอื่น และห้ามมี Markdown
''';

  static GenerativeModel _model() => GenerativeModel(
    model: _modelName,
    apiKey: ApiKeys.scanRecipeScreen,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0.4,
    ),
  );

  /// สแกนสูตรอาหารจากรูป (ตำรา หนังสือ ลายมือ ฯลฯ)
  static Future<Map<String, dynamic>> scanRecipeImage(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    final prompt = '''
วิเคราะห์สูตรอาหารจากรูปภาพนี้ (อาจเป็นภาพถ่ายจากตำรา หนังสือ ใบสั่งอาหาร หรือลายมือ)
ถ้ารูปนี้ไม่ใช่สูตรอาหาร ให้ตอบ {"error": "not_recipe"}

กติกาของ "instructions" (สำคัญมาก):
- ขั้นตอนที่เขียนไว้ในรูป ให้คัดลอกตามจริง ห้ามแต่งเติมหรือแก้ความหมาย และใส่ "ai_generated": false
- ถ้าในรูปไม่มีวิธีทำเลย หรือขาดขั้นตอนสำคัญจนทำตามไม่ได้ ให้คิดขั้นตอนเพิ่มเอง
  และใส่ "ai_generated": true ทุกขั้นตอนที่คิดเอง
- ขั้นตอนที่คิดเอง ต้องทำง่าย ใช้เฉพาะวัตถุดิบในสูตร และปรุงเนื้อสัตว์/ไข่ให้สุกอย่างปลอดภัย
- เรียงขั้นตอนตามลำดับการทำจริง (แทรกขั้นตอนที่คิดเพิ่มไว้ตรงตำแหน่งที่เหมาะสม)
$_schema''';

    final res = await _model()
        .generateContent([
          Content.multi([TextPart(prompt), DataPart(mimeType, bytes)]),
        ])
        .timeout(_timeout);
    return _parse(res.text);
  }

  static Map<String, dynamic> _parse(String? text) {
    if (text == null || text.trim().isEmpty) {
      throw const RecipeAiException('AI ไม่ได้ส่งผลลัพธ์กลับมา กรุณาลองใหม่');
    }
    final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}');
    if (start == -1 || end <= start) {
      debugPrint('AI response อ่านไม่ได้: $text');
      throw const RecipeAiException('อ่านผลลัพธ์จาก AI ไม่ได้ กรุณาลองใหม่');
    }

    final decoded = jsonDecode(clean.substring(start, end + 1));
    if (decoded is! Map) {
      throw const RecipeAiException('อ่านผลลัพธ์จาก AI ไม่ได้ กรุณาลองใหม่');
    }
    final recipe = Map<String, dynamic>.from(decoded);
    if (recipe['error'] != null) {
      throw const RecipeAiException(
        'ไม่พบสูตรอาหารในรูปนี้ ลองถ่ายให้เห็นตัวหนังสือชัดขึ้น',
      );
    }

    final rawIng = recipe['detailed_ingredients'];
    recipe['detailed_ingredients'] = rawIng is List
        ? rawIng.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    // instructions: แปลงเป็น List<String> แบบมีเลขข้อ ("1. ...")
    // และเก็บตำแหน่งขั้นตอนที่ AI คิดเพิ่มไว้ใน ai_step_indexes
    final rawSteps = recipe['instructions'];
    final steps = <String>[];
    final aiIndexes = <int>[];
    if (rawSteps is List) {
      for (final item in rawSteps) {
        String text;
        var isAi = false;
        if (item is Map) {
          text = (item['text'] ?? '').toString();
          isAi = item['ai_generated'] == true || item['ai_generated'] == 'true';
        } else {
          text = item?.toString() ?? '';
        }
        text = text.replaceFirst(_stepNumberPrefix, '').trim();
        if (text.isEmpty) continue;
        if (isAi) aiIndexes.add(steps.length);
        steps.add('${steps.length + 1}. $text');
      }
    }
    recipe['instructions'] = steps;
    recipe['ai_step_indexes'] = aiIndexes;
    return recipe;
  }

  /// ข้อความ error ที่อ่านเข้าใจง่ายสำหรับแสดงใน SnackBar
  static String friendlyError(Object e) {
    if (e is TimeoutException) {
      return 'AI ใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง (เช็คสัญญาณอินเทอร์เน็ตด้วย)';
    }
    if (e is RecipeAiException) return e.message;
    if (e is FormatException) return 'อ่านผลลัพธ์จาก AI ไม่ได้ กรุณาลองใหม่';
    return 'เกิดข้อผิดพลาด: $e';
  }
}
