import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';

/// ข้อผิดพลาดที่ตั้งใจแสดงให้ผู้ใช้เห็นตรงๆ
class RecipeAiException implements Exception {
  final String message;

  /// true = รูปนี้ไม่ใช่สูตรอาหาร (Gemini ตอบ {"error": "not_recipe"})
  final bool notRecipe;
  const RecipeAiException(this.message, {this.notRecipe = false});
  @override
  String toString() => message;
}

/// งานฝั่ง Gemini ของฟีเจอร์สูตรอาหาร: สแกนสูตรจากรูป
class RecipeAiService {
  RecipeAiService._();

  static const _timeout = Duration(seconds: 60);
  static final _stepNumberPrefix = RegExp(r'^\s*\d+\s*[\.\)]\s*');

  static const _schema = '''
ตอบกลับเป็น JSON Object เท่านั้น ตามรูปแบบนี้เป๊ะๆ:
{
  "recipe_name": "ชื่อเมนู",
  "time": "เวลาทำ (เช่น 30 นาที)",
  "time_estimated": false,
  "servings": "จำนวนที่ได้ (เช่น 2 ที่)",
  "servings_estimated": false,
  "ingredients_used": ["วัตถุดิบหลัก1", "วัตถุดิบหลัก2"],
  "detailed_ingredients": [
    {"name": "ชื่อวัตถุดิบภาษาไทย", "use_quantity": 1, "unit": "หน่วย", "is_staple": false}
  ],
  "instructions": [
    {"text": "ขั้นตอนแรก (ไม่ต้องใส่เลขข้อ)", "ai_generated": false}
  ]
}
- use_quantity ต้องเป็นตัวเลขเท่านั้น (เช่น 0.5 แทน "ครึ่ง") ถ้าไม่ระบุให้ใส่ null
- time / servings: ถ้าในรูปเขียนไว้ ให้ใช้ตามรูป และใส่ "time_estimated" / "servings_estimated" เป็น false
  ถ้าในรูปไม่ได้เขียนไว้ ให้ประมาณเองตามสูตร และใส่ "time_estimated" / "servings_estimated" เป็น true
- unit ใช้หน่วยครัวไทย เช่น กรัม, ช้อนโต๊ะ, ช้อนชา, ถ้วย, ฟอง, ชิ้น, ลูก, กลีบ, ส่วน
- is_staple: true เฉพาะเครื่องปรุงพื้นฐานที่ทุกบ้านมีอยู่แล้ว เช่น น้ำปลา ซีอิ๊ว ซอสหอยนางรม
  ซอสปรุงรส น้ำตาล เกลือ พริกไทย น้ำมันพืช ผงปรุงรส น้ำเปล่า
  วัตถุดิบหลัก (เนื้อสัตว์ ผัก ไข่ เส้น ข้าว สมุนไพรสด เช่น กระเทียม พริก ใบกะเพรา) ให้เป็น false
- ห้ามมีข้อความอธิบายอื่น และห้ามมี Markdown
''';

  static GenerativeModel _model() => GenerativeModel(
    model: geminiModel,
    apiKey: ApiKeys.scanRecipeScreen,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0.4,
    ),
  );

  /// สแกนสูตรอาหารจากรูป (ตำรา หนังสือ ลายมือ ฯลฯ)
  /// [imageHash] = SHA-256 ของรูป ใช้บันทึกลง ai_request_logs
  static Future<Map<String, dynamic>> scanRecipeImage(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? imageHash,
  }) async {
    final prompt = '''
วิเคราะห์สูตรอาหารจากรูปภาพนี้ (อาจเป็นภาพถ่ายจากตำรา หนังสือ ใบสั่งอาหาร ลายมือ
หรือรูปที่มีแค่ชื่อเมนูอาหาร)
- ถ้ารูปมีแค่ชื่อเมนูอาหาร (ไม่มีวัตถุดิบ/วิธีทำ) ถือว่าใช้ได้: ให้คิดวัตถุดิบและขั้นตอนเอง
  ตามสูตรมาตรฐานของเมนูนั้น และใส่ "ai_generated": true ทุกขั้นตอน
- ตอบ {"error": "not_recipe"} เฉพาะเมื่อในรูปไม่มีชื่อเมนูอาหารหรือสูตรอาหารเลย
  (เช่น รูปวิว รูปคน เอกสารที่ไม่เกี่ยวกับอาหาร)

กติกาของ "instructions" (สำคัญมาก):
- ขั้นตอนที่เขียนไว้ในรูป ให้คัดลอกตามจริง ห้ามแต่งเติมหรือแก้ความหมาย และใส่ "ai_generated": false
- ถ้าในรูปไม่มีวิธีทำเลย หรือขาดขั้นตอนสำคัญจนทำตามไม่ได้ ให้คิดขั้นตอนเพิ่มเอง
  และใส่ "ai_generated": true ทุกขั้นตอนที่คิดเอง
- ขั้นตอนที่คิดเอง ต้องทำง่าย ใช้เฉพาะวัตถุดิบในสูตร และปรุงเนื้อสัตว์/ไข่ให้สุกอย่างปลอดภัย
- เรียงขั้นตอนตามลำดับการทำจริง (แทรกขั้นตอนที่คิดเพิ่มไว้ตรงตำแหน่งที่เหมาะสม)
$_schema''';

    return _callAndLog(
      prompt: prompt,
      bytes: bytes,
      mimeType: mimeType,
      imageHash: imageHash,
      parse: _parse,
    );
  }

  /// ขั้นที่ 1 (ประหยัด token): ถามสั้นๆ แค่ว่ารูปนี้คือเมนูอะไร
  /// และในรูปมีรายการวัตถุดิบ / วิธีทำเขียนไว้หรือไม่ — ยังไม่อ่านรายละเอียด
  /// เพื่อเอาชื่อไปค้นสูตรในระบบก่อน ถ้าเจอจะไม่ต้องให้ AI อ่าน/แต่งสูตรทั้งสูตร
  static Future<RecipeImageInfo> identifyRecipeImage(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? imageHash,
  }) {
    const prompt = '''
ดูรูปนี้แล้วตอบสั้นๆ ว่าเป็นสูตรอาหารหรือชื่อเมนูอาหารอะไร (ยังไม่ต้องอ่านรายละเอียด)
- รูปที่มีแค่ชื่อเมนูอาหาร (เช่น เขียนว่า "กะเพราหมูสับ" อย่างเดียว) ถือว่าใช้ได้
  ให้ตอบชื่อเมนูนั้น โดย has_ingredients และ has_steps เป็น false
- ตอบ {"error": "not_recipe"} เฉพาะเมื่อในรูปไม่มีชื่อเมนูอาหารหรือสูตรอาหารเลย
  (เช่น รูปวิว รูปคน เอกสารที่ไม่เกี่ยวกับอาหาร)
ตอบกลับเป็น JSON Object เท่านั้น:
{"recipe_name": "ชื่อเมนูภาษาไทยตามที่เขียนในรูป", "has_ingredients": true, "has_steps": false}
- has_ingredients = ในรูปมีรายการวัตถุดิบเขียนไว้หรือไม่
- has_steps = ในรูปมีวิธีทำ/ขั้นตอนการทำเขียนไว้หรือไม่
- ห้ามมีข้อความอธิบายอื่น และห้ามมี Markdown
''';
    return _callAndLog(
      prompt: prompt,
      bytes: bytes,
      mimeType: mimeType,
      imageHash: imageHash,
      parse: (text) {
        final json = _decodeObject(text);
        if (json['error'] != null) {
          throw const RecipeAiException(
            'ไม่พบสูตรอาหารในรูปนี้ ลองถ่ายให้เห็นตัวหนังสือชัดขึ้น',
            notRecipe: true,
          );
        }
        bool flag(Object? v) => v == true || v == 'true';
        return RecipeImageInfo(
          name: (json['recipe_name'] ?? '').toString().trim(),
          hasIngredients: flag(json['has_ingredients']),
          hasSteps: flag(json['has_steps']),
        );
      },
    );
  }

  /// ส่งรูป + prompt ให้ Gemini (ลองใหม่อัตโนมัติถ้า 503) แล้วแปลงผลด้วย [parse]
  /// บันทึก ai_request_logs ทุกครั้ง: สำเร็จ / ไม่ใช่สูตรอาหาร / ไม่สำเร็จ
  static Future<T> _callAndLog<T>({
    required String prompt,
    required Uint8List bytes,
    required String mimeType,
    required String? imageHash,
    required T Function(String? text) parse,
  }) async {
    void log(String result, [UsageMetadata? usage]) => logAiRequest(
      event: AiEvent.scanRecipe,
      result: result,
      model: geminiModel,
      usage: usage,
      imageHash: imageHash,
    );

    final GenerateContentResponse res;
    try {
      res = await generateContentWithRetry(_model(), [
        Content.multi([TextPart(prompt), DataPart(mimeType, bytes)]),
      ], timeout: _timeout);
    } catch (_) {
      log(AiResult.failed);
      rethrow;
    }
    try {
      final result = parse(res.text);
      log(AiResult.gemini, res.usageMetadata);
      return result;
    } on RecipeAiException catch (e) {
      log(
        e.notRecipe ? AiResult.notRecipe : AiResult.failed,
        res.usageMetadata,
      );
      rethrow;
    } catch (_) {
      log(AiResult.failed, res.usageMetadata);
      rethrow;
    }
  }

  /// ตัด ```json ออก แล้วอ่านเป็น JSON Object
  static Map<String, dynamic> _decodeObject(String? text) {
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
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> _parse(String? text) {
    final recipe = _decodeObject(text);
    if (recipe['error'] != null) {
      throw const RecipeAiException(
        'ไม่พบสูตรอาหารในรูปนี้ ลองถ่ายให้เห็นตัวหนังสือชัดขึ้น',
        notRecipe: true,
      );
    }

    final rawIng = recipe['detailed_ingredients'];
    recipe['detailed_ingredients'] = rawIng is List
        ? rawIng
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
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
    // AI ประมาณเวลา/จำนวนที่เอง (ในรูปไม่ได้เขียนไว้) -> แสดงป้าย "AI ประมาณ"
    bool flag(Object? v) => v == true || v == 'true';
    recipe['time_estimated'] = flag(recipe['time_estimated']);
    recipe['servings_estimated'] = flag(recipe['servings_estimated']);
    return recipe;
  }

  /// ข้อความ error ที่อ่านเข้าใจง่ายสำหรับแสดงใน SnackBar
  static String friendlyError(Object e) {
    if (e is TimeoutException) {
      return 'AI ใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง (เช็คสัญญาณอินเทอร์เน็ตด้วย)';
    }
    if (e is RecipeAiException) return e.message;
    if (e is FormatException) return 'อ่านผลลัพธ์จาก AI ไม่ได้ กรุณาลองใหม่';
    // 503 คนใช้เยอะ / 429 ครบโควตา -> ข้อความภาษาไทยแบบเดียวกับหน้าอื่น
    return geminiErrorMessage(e, fallback: 'สแกนสูตรอาหารไม่สำเร็จ');
  }
}

/// ผลจากขั้นที่ 1: รูปนี้คือเมนูอะไร และในรูปมีอะไรเขียนไว้บ้าง
class RecipeImageInfo {
  final String name;
  final bool hasIngredients;
  final bool hasSteps;

  const RecipeImageInfo({
    required this.name,
    required this.hasIngredients,
    required this.hasSteps,
  });

  /// รูปมีแค่ชื่อเมนู (ไม่มีวิธีทำ) -> ถ้าให้ AI อ่านต่อ AI ต้องแต่งขั้นตอนเองเกือบทั้งหมด
  bool get isNameOnly => !hasSteps;
}
