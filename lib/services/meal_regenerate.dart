import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/diet_check.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/services/plan_goal.dart';
import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/utils/fridge_age.dart';

/// เปลี่ยนเมนูของมื้อเดียวในแพลน (weekly_meals) — ให้ AI สร้างเมนูใหม่แทนช่องเดิม
/// (วันเดิม มื้อเดิม) แคลอรี/โปรตีนใกล้ของเดิม ไม่ซ้ำเมนูอื่นในสัปดาห์
/// ใช้ AI แค่มื้อเดียว ถูกกว่าสร้างแพลนใหม่ทั้งหมด
class MealRegenerate {
  MealRegenerate._();

  /// [meal] = แถว weekly_meals ที่จะเปลี่ยน, [otherNames] = ชื่อเมนูอื่นในแพลน (กันซ้ำ)
  /// [fridgeOnly] = ใช้เฉพาะของในตู้เย็น, [hint] = ความต้องการของผู้ใช้ (ไม่บังคับ)
  /// คืนแถวที่อัปเดตแล้ว
  static Future<Map<String, dynamic>> regenerate({
    required Map<String, dynamic> meal,
    required List<String> otherNames,
    required bool fridgeOnly,
    String? hint,
    String? dietType,
    String? goal,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    await ShoppingSuggestion.loadStaples();
    final fridge = List<Map<String, dynamic>>.from(
      await supabase.from('fridge_items').select().eq('user_id', user.id),
    );
    final usable = fridge.where((e) => !isOverdue(e)).toList();
    final fridgeList = inventoryPromptList(usable, withPerCook: true);
    if (fridgeOnly && fridgeList.isEmpty) {
      throw 'ไม่มีวัตถุดิบในตู้เย็นให้สร้างเมนูใหม่';
    }

    final oldName = (meal['food_name'] ?? '').toString();
    final avoid = {
      ...otherNames,
      oldName,
    }.where((n) => n.trim().isNotEmpty).join(', ');
    final userHint = (hint ?? '').trim();

    // ===== ลองหยิบจากคลังสูตรกลางก่อน (ไม่ใช้ AI) =====
    // ข้ามถ้าผู้ใช้พิมพ์ความต้องการมา (คลังเลือกตามคำขอไม่ได้ ให้ AI ทำแทน)
    if (userHint.isEmpty) {
      try {
        final oldCal = RecipeRepository.toNum(meal['calories']);
        final candidates = await RecipeRepository.findRecipesForFridge(
          fridgeItems: usable,
          maxMissing: fridgeOnly ? 0 : 1,
          limit: 30,
          requireNutrition: true,
          excludeNames: {...otherNames, oldName},
        );
        final fitting = candidates.where((r) {
          if (dietType != null &&
              dietType != 'ไม่มี' &&
              !(r['diet_tags'] as List).contains(dietType)) {
            return false;
          }
          // ตรวจซ้ำจากชื่อวัตถุดิบ กันเมนูที่เคยถูกติดป้ายข้อจำกัดอาหารผิด
          final names = [
            for (final ing in RecipeRepository.ingredientsOf(r)) ing['name'],
          ];
          if (!DietCheck.fits(dietType, names)) return false;
          final cal = RecipeRepository.toNum(r['calories']);
          return oldCal <= 0 || (cal >= oldCal * 0.65 && cal <= oldCal * 1.35);
        }).toList();
        // เลือกเมนูที่เหมาะกับเป้าหมายของแพลนก่อน (คะแนนเท่ากัน = คงลำดับเดิม)
        double goalScore(Map<String, dynamic> r) => PlanGoal.score(
          goal,
          RecipeRepository.toNum(r['calories']),
          RecipeRepository.toNum(r['protein']),
        );
        Map<String, dynamic>? pick;
        for (final r in fitting) {
          if (pick == null || goalScore(r) > goalScore(pick)) pick = r;
        }
        if (pick != null) {
          final libIngredients = [
            for (final ing in RecipeRepository.ingredientsOf(pick))
              () {
                final name = (ing['name'] ?? '').toString().trim();
                final have =
                    inFridgeOf(usable, name) ||
                    ShoppingSuggestion.isStaple(name);
                return <String, dynamic>{
                  'name': name,
                  'quantity':
                      '${RecipeRepository.formatNum(ing['use_quantity'])} ${ing['unit'] ?? ''}'
                          .trim(),
                  'checked': have,
                  if (!have) ShoppingSuggestion.toBuyKey: true,
                };
              }(),
          ];
          final steps = RecipeRepository.stepTextsOf(pick);
          final update = <String, dynamic>{
            'food_name': pick['recipe_name'],
            'calories': RecipeRepository.toNum(pick['calories']).round(),
            'protein': RecipeRepository.toNum(pick['protein']).round(),
            'ingredients': libIngredients,
            'steps': [
              for (var k = 0; k < steps.length; k++) '${k + 1}. ${steps[k]}',
            ].join('\n'),
            'is_cooked': false,
            'recipe_id': pick['recipe_id'],
          };
          await supabase
              .from('weekly_meals')
              .update(update)
              .eq('id', meal['id']);
          logAiRequest(
            event: AiEvent.mealPlan,
            result: AiResult.cacheHit,
            recipeId: pick['recipe_id'],
          );
          return {...meal, ...update};
        }
      } catch (e) {
        // ค้นคลังไม่สำเร็จ -> ใช้ AI ต่อตามปกติ
      }
    }

    final prompt =
        '''
คุณเป็น AI Nutritionist ช่วยเปลี่ยนเมนูอาหาร 1 มื้อในแพลนของผู้ใช้
มื้อเดิม: $oldName (${meal['calories'] ?? '-'} kcal, โปรตีน ${meal['protein'] ?? '-'} g)
ข้อจำกัดอาหาร: ${dietType ?? 'ไม่มี'}
${userHint.isEmpty ? '' : 'ผู้ใช้อยากได้: $userHint'}

วัตถุดิบที่มีในตู้เย็น:
${fridgeList.isEmpty ? 'ไม่มี' : fridgeList}

กฎ:
- สร้างเมนูใหม่ 1 เมนู ห้ามซ้ำกับเมนูเหล่านี้: $avoid
- calories และ protein ให้ใกล้มื้อเดิม และต้องคำนวณจากวัตถุดิบและปริมาณจริงเท่านั้น ห้ามปั้นตัวเลข
${fridgeOnly ? '- ใช้เฉพาะวัตถุดิบในตู้เย็นเท่านั้น ห้ามใช้ของที่ไม่มีในรายการ' : '''- ใช้วัตถุดิบในตู้เย็นก่อน ซื้อเพิ่มได้เท่าที่จำเป็น (ของหาง่าย ราคาไม่แพง)
- วัตถุดิบที่ไม่มีในตู้เย็น ให้ใส่ "to_buy": true'''}
- ถือว่าบ้านมีของพื้นฐานอยู่แล้ว ไม่ต้องซื้อ: ${ShoppingSuggestion.stapleNamesForPrompt()}
- ปริมาณเป็นหน่วยเดียวกับวัตถุดิบในตู้เย็น (ส่วน, ชิ้น, ฟอง, หัว) ห้ามใช้กรัม/มล./ช้อน
  ถ้ามี "ใช้ครั้งละ" ให้ใช้ปริมาณนั้นเป็นหลัก
- steps เป็นขั้นตอนภาษาไทยเรียงเป็นข้อ (array ของ string)

ตอบกลับเป็น JSON Object เท่านั้น ห้ามมีข้อความอื่นและห้ามมี Markdown:
{"food_name":"ข้าวอกไก่ไข่ดาว","calories":450,"protein":35,
"ingredients":[{"name":"อกไก่","quantity":"1 ชิ้น"},{"name":"บรอกโคลี","quantity":"1/2 หัว","to_buy":true}],
"steps":["หั่นอกไก่","ผัดจนสุก","จัดใส่จาน"]}
''';

    // เมนูจาก AI ต้องผ่านข้อจำกัดอาหาร (ตรวจจากชื่อวัตถุดิบ) — ผิด ให้ AI ทำใหม่
    // อีก 1 รอบ ยังผิดอีก แจ้งผู้ใช้ ไม่บันทึกเมนูที่ผิดลงแพลน/คลังกลาง
    Map json = const {};
    var extraRule = '';
    for (var attempt = 0; attempt < 2; attempt++) {
      final res = await generateGemini(
        apiKey: ApiKeys.mealPlanScreen,
        logEvent: AiEvent.mealPlan,
        content: [Content.text(prompt + extraRule)],
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.8,
        ),
        timeout: const Duration(seconds: 60),
      );

      final text = (res.text ?? '')
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end <= start) {
        throw 'อ่านเมนูใหม่จาก AI ไม่ได้ กรุณาลองใหม่';
      }
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map || (decoded['food_name'] ?? '').toString().trim().isEmpty) {
        throw 'อ่านเมนูใหม่จาก AI ไม่ได้ กรุณาลองใหม่';
      }
      json = decoded;
      final wrong = DietCheck.violations(
        dietType,
        DietCheck.namesOf(decoded['ingredients']),
      );
      if (wrong.isEmpty) break;
      if (attempt == 1) {
        throw 'เมนูที่ได้ยังมี ${wrong.join(', ')} ซึ่งขัดกับข้อจำกัดอาหาร '
            '"$dietType" กรุณาลองใหม่ หรือพิมพ์บอกสิ่งที่ไม่ต้องการ';
      }
      extraRule =
          '\n- เมนูก่อนหน้า "${decoded['food_name']}" ใช้ ${wrong.join(', ')} '
          'ซึ่งผิดข้อจำกัดอาหาร "$dietType" ห้ามใช้วัตถุดิบเหล่านี้หรือประเภทเดียวกัน';
    }

    bool inFridge(String name) {
      final n = name.trim().toLowerCase();
      if (n.isEmpty) return false;
      return usable.any((f) {
        final fn = (f['name'] ?? '').toString().trim().toLowerCase();
        return fn.isNotEmpty &&
            (fn == n || fn.contains(n) || n.contains(fn)) &&
            !isUsedUp(f);
      });
    }

    num toNum(Object? v) => v is num
        ? v
        : num.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;

    final ingredients = [
      for (final i in (json['ingredients'] as List? ?? []).whereType<Map>())
        if ((i['name'] ?? '').toString().trim().isNotEmpty)
          () {
            final name = i['name'].toString().trim();
            final have = inFridge(name) || ShoppingSuggestion.isStaple(name);
            return <String, dynamic>{
              'name': name,
              'quantity': (i['quantity'] ?? '').toString().trim(),
              'checked': have,
              if (!have) ShoppingSuggestion.toBuyKey: true,
            };
          }(),
    ];
    final stepsRaw = json['steps'];
    final steps = stepsRaw is List
        ? [for (var k = 0; k < stepsRaw.length; k++) '${k + 1}. ${stepsRaw[k]}']
              .join('\n')
        : (stepsRaw ?? '').toString();

    // เก็บเมนูใหม่จาก AI ลงคลังสูตรกลาง แล้วผูกกับมื้อนี้
    final recipeId = await RecipeRepository.saveAiRecipe(
      {
        'recipe_name': json['food_name'],
        'detailed_ingredients': [
          for (final i in ingredients)
            {
              'name': i['name'],
              'use_quantity': RecipeRepository.leadingNumber(i['quantity']),
              'unit': (i['quantity'] ?? '')
                  .toString()
                  .replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '')
                  .trim(),
            },
        ],
        'instructions': steps.split('\n'),
      },
      caloriesPerServing: toNum(json['calories']),
      proteinPerServing: toNum(json['protein']),
      dietTags: [if (dietType != null && dietType != 'ไม่มี') dietType],
    );

    final update = <String, dynamic>{
      'food_name': json['food_name'].toString().trim(),
      'calories': toNum(json['calories']).round(),
      'protein': toNum(json['protein']).round(),
      'ingredients': ingredients,
      'steps': steps,
      'is_cooked': false,
      'recipe_id': recipeId,
    };
    await supabase.from('weekly_meals').update(update).eq('id', meal['id']);
    return {...meal, ...update};
  }

  static bool inFridgeOf(List<Map<String, dynamic>> fridge, String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    return fridge.any((f) {
      final fn = (f['name'] ?? '').toString().trim().toLowerCase();
      return fn.isNotEmpty &&
          (fn == n || fn.contains(n) || n.contains(fn)) &&
          !isUsedUp(f);
    });
  }

  /// แพลนนี้สร้างแบบ "ซื้อเพิ่มได้" ไหม — ดูจากว่ามีมื้อไหนติดธงต้องซื้อหรือเปล่า
  /// (ไม่ได้เก็บโหมดไว้ในตาราง ถ้าไม่มีของต้องซื้อเลย ถือว่าใช้เฉพาะของในตู้)
  static bool planAllowsBuying(List<dynamic> meals) {
    for (final m in meals) {
      final raw = m is Map ? m['ingredients'] : null;
      if (raw is! List) continue;
      if (raw.whereType<Map>().any(
        (e) => e[ShoppingSuggestion.toBuyKey] == true,
      )) {
        return true;
      }
    }
    return false;
  }
}
