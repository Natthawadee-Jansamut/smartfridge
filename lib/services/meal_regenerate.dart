import 'dart:convert'; // jsonDecode

import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/config/api_keys.dart'; // คีย์ AI
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/diet_check.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/services/meal_nutrition.dart';
import 'package:test_app/services/plan_allocation.dart';
import 'package:test_app/services/plan_goal.dart';
import 'package:test_app/services/plan_targets.dart';
import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/utils/fridge_age.dart';

/// เปลี่ยนเมนูของมื้อเดียวในแพลน (weekly_meals) — ให้ AI สร้างเมนูใหม่แทนช่องเดิม
/// (วันเดิม มื้อเดิม) แคลอรี/โปรตีนใกล้ของเดิม ไม่ซ้ำเมนูอื่นในสัปดาห์
/// ใช้ AI แค่มื้อเดียว ถูกกว่าสร้างแพลนใหม่ทั้งหมด
class MealRegenerate {
  MealRegenerate._(); // ห้ามสร้างตัวแปรจากคลาสนี้

  /// [meal] = แถว weekly_meals ที่จะเปลี่ยน, [otherNames] = ชื่อเมนูอื่นในแพลน (กันซ้ำ)
  /// [fridgeOnly] = ใช้เฉพาะของในตู้เย็น, [hint] = ความต้องการของผู้ใช้ (ไม่บังคับ)
  /// คืนแถวที่อัปเดตแล้ว
  static Future<Map<String, dynamic>> regenerate({
    required Map<String, dynamic> meal, // มื้อที่จะเปลี่ยน
    required List<String> otherNames, // ชื่อเมนูอื่นในแพลน (ห้ามซ้ำ)
    required bool fridgeOnly, // ใช้เฉพาะของในตู้ไหม
    String? hint, // สิ่งที่ผู้ใช้พิมพ์บอก (เช่น "อยากกินเส้น")
    String? dietType, // ข้อจำกัดอาหาร
    String? goal, // เป้าหมาย
    PlanTargets? targets, // เป้าแคลอรี/โปรตีน
    List<dynamic> sameDayMeals = const [], // มื้ออื่นในวันเดียวกัน
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่'; // ยังไม่ล็อกอิน

    await ShoppingSuggestion.loadStaples(); // โหลดรายการของพื้นฐาน
    final fridge = List<Map<String, dynamic>>.from(
      await supabase.from('fridge_items').select().eq('user_id', user.id), // ดึงของในตู้ทั้งหมด
    );
    var usable = fridge.where((e) => !isOverdue(e)).toList(); // ตัดของที่เกินกำหนดออก

    // โหมดใช้เฉพาะของในตู้: เมนูใหม่ใช้ได้เฉพาะของที่เหลือหลังจองให้มื้ออื่นในแพลน
    // แล้ว (ห้ามแย่งของจากมื้ออื่น) และต้องมีของครบจริงถึงจะบันทึก
    DateTime? planStart;
    if (fridgeOnly && meal['plan_id'] != null) {
      final planMeals = await supabase // ดึงทุกมื้อในแพลนนี้
          .from('weekly_meals')
          .select()
          .eq('plan_id', meal['plan_id']);
      final plan = await supabase // ดึงวันที่สร้างแพลน
          .from('meal_plans')
          .select('created_at')
          .eq('id', meal['plan_id'])
          .maybeSingle();
      planStart = DateTime.tryParse(
        plan?['created_at']?.toString() ?? '',
      )?.toLocal();
      usable = PlanAllocation.leftoverStock( // เหลือเฉพาะของที่ยังไม่ถูกจองให้มื้ออื่น
        meals: [
          for (final m in planMeals)
            if (m['id']?.toString() != meal['id']?.toString()) m, // ยกเว้นมื้อที่กำลังเปลี่ยน
        ],
        fridgeItems: usable,
        planStart: planStart,
      );
    }

    /// วัตถุดิบที่ของในตู้ (ที่เหลือ) ไม่พอสำหรับเมนูนี้ — ว่าง = ทำได้จริง
    List<String> missingFor(List ingredients) { // ลองจองของให้เมนูใหม่ แล้วคืนชื่อที่ไม่พอ
      final alloc = PlanAllocation.allocate(
        meals: [
          {
            'id': 'new',
            'day': meal['day'],
            'meal_type': meal['meal_type'],
            'ingredients': ingredients,
          },
        ],
        fridgeItems: usable,
        planStart: planStart,
      );
      return [
        for (final s in alloc['new'] ?? const <IngredientStatus>[])
          if (!s.have) s.name,
      ];
    }

    final fridgeList = inventoryPromptList(usable, withPerCook: true); // รายการของในตู้สำหรับใส่ prompt
    if (fridgeOnly && fridgeList.isEmpty) { // ใช้เฉพาะของในตู้ แต่ตู้ว่าง -> แจ้ง error
      throw meal['plan_id'] != null
          ? 'ของในตู้เย็นถูกใช้กับมื้ออื่นในแพลนหมดแล้ว เมนูเดิมยังอยู่'
          : 'ไม่มีวัตถุดิบในตู้เย็นให้สร้างเมนูใหม่';
    }

    final oldName = (meal['food_name'] ?? '').toString(); // ชื่อเมนูเดิม
    final avoid = { // ชื่อที่ห้ามซ้ำ (เมนูอื่น + เมนูเดิม)
      ...otherNames,
      oldName,
    }.where((n) => n.trim().isNotEmpty).join(', ');
    final userHint = (hint ?? '').trim(); // สิ่งที่ผู้ใช้พิมพ์

    // งบแคลอรี/โปรตีนของมื้อนี้ = เป้าต่อวันที่ผู้ใช้ตั้ง − มื้ออื่นของวันเดียวกัน
    // (ช่วงเดียวกับตอนสร้างแพลน) — แพลนเก่าที่ไม่มีเป้า หรือมื้ออื่นกินงบหมดแล้ว
    // ใช้วิธีเดิม (ใกล้มื้อเดิม) แล้วแจ้งผู้ใช้
    final otherCal = sameDayMeals.whereType<Map>().fold<num>( // แคลอรีรวมของมื้ออื่นในวัน
      0,
      (a, m) => a + RecipeRepository.toNum(m['calories']),
    );
    final otherPro = sameDayMeals.whereType<Map>().fold<num>( // โปรตีนรวมของมื้ออื่นในวัน
      0,
      (a, m) => a + RecipeRepository.toNum(m['protein']),
    );
    final rawBudget = // ช่วงแคลอรี/โปรตีนที่มื้อนี้ใช้ได้
        targets == null || targets.dayCal <= 0 || targets.dayProtein <= 0
        ? null
        : targets.slotBudget(
            fixedCal: otherCal,
            fixedProtein: otherPro,
            slots: 1,
          );
    final budget = rawBudget == null || rawBudget.calMax <= 0 // งบเป็น 0 หรือติดลบ = ไม่มีงบให้ใช้
        ? null
        : rawBudget;
    String? warning = rawBudget != null && budget == null
        ? 'มื้ออื่นของวันนี้รวมกันเกินเป้าแคลอรีแล้ว ยอดรวมวันนี้จะเกินเป้า'
        : null;
    bool inBudget(num cal, num pro) => // อยู่ในงบไหม
        budget != null &&
        cal >= budget.calMin &&
        cal <= budget.calMax &&
        pro >= budget.proteinMin &&
        pro <= budget.proteinMax;
    String r(num v) => v.round().toString(); // ตัวช่วยปัดเป็นจำนวนเต็มแล้วเป็นข้อความ

    // ===== ลองหยิบจากคลังสูตรกลางก่อน (ไม่ใช้ AI) =====
    // ข้ามถ้าผู้ใช้พิมพ์ความต้องการมา (คลังเลือกตามคำขอไม่ได้ ให้ AI ทำแทน)
    if (userHint.isEmpty) {
      try {
        final oldCal = RecipeRepository.toNum(meal['calories']);
        final candidates = await RecipeRepository.findRecipesForFridge( // ค้นสูตรในคลังที่ทำได้จากของในตู้
          fridgeItems: usable,
          // ของในตู้ครบ (ของที่ต้องซื้อให้มาจาก Gemini ที่มีเกณฑ์ซื้อเฉพาะวัตถุดิบทั่วไป)
          maxMissing: 0,
          limit: 30, // เอามาดู 30 สูตร
          requireNutrition: true, // ต้องมีแคลอรี/โปรตีน
          excludeNames: {...otherNames, oldName}, // ห้ามซ้ำกับเมนูอื่น/เมนูเดิม
        );
        final fitting = candidates.where((r) { // กรองสูตรที่ใช้ได้
          if (dietType != null &&
              dietType != 'ไม่มี' &&
              !(r['diet_tags'] as List).contains(dietType)) {
            return false;
          }
          // ตรวจซ้ำจากชื่อวัตถุดิบ กันเมนูที่เคยถูกติดป้ายข้อจำกัดอาหารผิด
          final names = [
            for (final ing in RecipeRepository.ingredientsOf(r)) ing['name'],
          ];
          if (!DietCheck.fits(dietType, names)) return false; // ผิดข้อจำกัดอาหาร -> ตัดทิ้ง
          // ใช้เฉพาะของในตู้: ของที่เหลือต้องพอทุกอย่าง (รวมปริมาณ)
          if (fridgeOnly &&
              missingFor([
                for (final ing in RecipeRepository.ingredientsOf(r))
                  {
                    'name': ing['name'],
                    'quantity':
                        '${RecipeRepository.formatNum(ing['use_quantity'])} ${ing['unit'] ?? ''}'
                            .trim(),
                  },
              ]).isNotEmpty) {
            return false;
          }
          final cal = RecipeRepository.toNum(r['calories']);
          if (budget != null) { // มีงบ -> ต้องอยู่ในงบ
            return inBudget(cal, RecipeRepository.toNum(r['protein']));
          }
          return oldCal <= 0 || (cal >= oldCal * 0.65 && cal <= oldCal * 1.35); // ไม่มีงบ -> แคลอรีต้องใกล้มื้อเดิม (±35%)
        }).toList();
        // เลือกเมนูที่เหมาะกับเป้าหมายของแพลนก่อน (คะแนนเท่ากัน = คงลำดับเดิม)
        double goalScore(Map<String, dynamic> r) => PlanGoal.score(
          goal,
          RecipeRepository.toNum(r['calories']),
          RecipeRepository.toNum(r['protein']),
        );
        Map<String, dynamic>? pick;
        for (final r in fitting) { // เลือกสูตรที่คะแนนเป้าหมายสูงสุด
          if (pick == null || goalScore(r) > goalScore(pick)) pick = r;
        }
        if (pick != null) { // เจอสูตรที่ใช้ได้ -> ใช้เลยไม่ต้องเรียก AI
          String origQty(Map ing) =>
              '${RecipeRepository.formatNum(ing['use_quantity'])} ${ing['unit'] ?? ''}'
                  .trim();
          final libBefore = [ // ข้อความวัตถุดิบก่อนแปลงหน่วย (ไว้เทียบ)
            for (final ing in RecipeRepository.ingredientsOf(pick))
              '${(ing['name'] ?? '').toString().trim()} ${origQty(ing)}',
          ];
          final libIngredients = [ // วัตถุดิบในรูปแบบของมื้อในแพลน
            for (final ing in RecipeRepository.ingredientsOf(pick))
              () {
                final name = (ing['name'] ?? '').toString().trim();
                final have = // มีในตู้หรือเป็นของพื้นฐาน
                    inFridgeOf(usable, name) ||
                    ShoppingSuggestion.isStaple(name);
                return <String, dynamic>{
                  'name': name,
                  // หน่วยให้ตรงกับของในตู้ (เช่น ผู้ใช้แบ่งเป็นส่วนไว้)
                  'quantity': PlanAllocation.quantityInFridgeUnit(
                    name,
                    origQty(ing),
                    fridge,
                  ),
                  'checked': have, // ติ๊กไว้ถ้ามีของ
                  if (!have && !fridgeOnly) ShoppingSuggestion.toBuyKey: true, // ไม่มีของ และซื้อเพิ่มได้ -> ติดธงต้องซื้อ
                };
              }(),
          ];
          final steps = RecipeRepository.stepTextsOf(pick);
          final update = <String, dynamic>{ // ค่าที่จะบันทึกแทนมื้อเดิม
            'food_name': pick['recipe_name'],
            'calories': RecipeRepository.toNum(pick['calories']).round(),
            'protein': RecipeRepository.toNum(pick['protein']).round(),
            'ingredients': libIngredients,
            'steps': [
              for (var k = 0; k < steps.length; k++) '${k + 1}. ${steps[k]}',
            ].join('\n'),
            'is_cooked': false, // เมนูใหม่ยังไม่ได้ทำ
            'recipe_id': pick['recipe_id'],
          };
          await supabase // บันทึกลงฐานข้อมูล
              .from('weekly_meals')
              .update(update)
              .eq('id', meal['id']);
          logAiRequest( // บันทึกว่าใช้คลังสูตร (ไม่เปลือง AI)
            event: AiEvent.mealPlan,
            result: AiResult.cacheHit,
            recipeId: pick['recipe_id'],
          );
          // แปลงหน่วยแล้ว -> แคลอรีของคลังสูตรคิดจากปริมาณเดิม ให้ AI คำนวณใหม่
          final libChanged = [ // เช็คว่ามีวัตถุดิบไหนถูกแปลงหน่วยไหม
            for (var k = 0; k < libIngredients.length; k++)
              if ('${libIngredients[k]['name']} ${libIngredients[k]['quantity']}' !=
                  libBefore[k])
                k,
          ].isNotEmpty;
          final saved = libChanged // ถูกแปลง -> คำนวณแคลอรีใหม่
              ? await MealNutrition.recalculateAfterUnitChange({
                  ...meal,
                  ...update,
                }, libBefore)
              : {...meal, ...update};
          return {...saved, if (warning != null) 'warning': warning};
        }
      } catch (e) {
        // ค้นคลังไม่สำเร็จ -> ใช้ AI ต่อตามปกติ
      }
    }

    // คำสั่งที่ส่งให้ AI (ข้อความในเครื่องหมาย ''' คือสิ่งที่ AI อ่าน)
    final prompt =
        '''
คุณเป็น AI Nutritionist ช่วยเปลี่ยนเมนูอาหาร 1 มื้อในแพลนของผู้ใช้
มื้อเดิม: $oldName (${meal['calories'] ?? '-'} kcal, โปรตีน ${meal['protein'] ?? '-'} g)
ข้อจำกัดอาหาร: ${dietType ?? 'ไม่มี'}
${goal == null ? '' : 'เป้าหมาย: $goal (${PlanGoal.promptRule(goal)})'}
${userHint.isEmpty ? '' : 'ผู้ใช้อยากได้: $userHint'}

วัตถุดิบที่มีในตู้เย็น:
${fridgeList.isEmpty ? 'ไม่มี' : fridgeList}

กฎ:
- สร้างเมนูใหม่ 1 เมนู ห้ามซ้ำกับเมนูเหล่านี้: $avoid
${budget == null ? '- calories และ protein ให้ใกล้มื้อเดิม' : '- calories ต้องอยู่ในช่วง ${r(budget.calMin)}-${r(budget.calMax)} kcal และ protein ${r(budget.proteinMin)}-${r(budget.proteinMax)} g (งบที่เหลือของวันนี้ตามเป้าที่ผู้ใช้ตั้ง ห้ามเกิน)'}
- calories และ protein ต้องคำนวณจากวัตถุดิบและปริมาณจริงเท่านั้น ห้ามปั้นตัวเลข
${fridgeOnly ? '- ใช้เฉพาะวัตถุดิบในตู้เย็นเท่านั้น ห้ามใช้ของที่ไม่มีในรายการ' : '''- ใช้วัตถุดิบในตู้เย็นก่อน ซื้อเพิ่มได้เท่าที่จำเป็น (ราคาไม่แพง)
- ซื้อเพิ่มได้เฉพาะวัตถุดิบทั่วไปที่หาซื้อได้ในซูเปอร์มาร์เก็ตหรือตลาดสดทั่วไปและคนส่วนใหญ่รับประทาน ห้ามแนะนำให้ซื้อวัตถุดิบที่รับประทานเฉพาะกลุ่มหรือเฉพาะถิ่น (เช่น แมลง งู กบ หอยทาก สัตว์ป่า)
- วัตถุดิบที่ไม่มีในตู้เย็น ให้ใส่ "to_buy": true'''}
- ถ้ารายการวัตถุดิบมีของที่ไม่ใช่อาหารหรือไม่ปลอดภัยต่อการบริโภค (เช่น ยา สารเคมี น้ำยาทำความสะอาด ของใช้) ห้ามนำมาใช้ในเมนูเด็ดขาด
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
    Map json = const {}; // ผลจาก AI
    var extraRule = ''; // กฎเพิ่มเติมเมื่อต้องลองใหม่
    for (var attempt = 0; attempt < 2; attempt++) { // ลองได้ 2 รอบ
      final res = await generateGemini( // ส่ง prompt ให้ Gemini
        apiKey: ApiKeys.mealPlanScreen,
        logEvent: AiEvent.mealPlan,
        content: [Content.text(prompt + extraRule)],
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json', // ตอบเป็น JSON
          temperature: 0.8, // ความสุ่มสูง (0.8) ให้ได้เมนูหลากหลาย
        ),
        timeout: const Duration(seconds: 60), // รอนานสุด 60 วินาที
      );

      final text = (res.text ?? '') // ล้างเครื่องหมาย ``` ออก
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end <= start) {
        throw 'อ่านเมนูใหม่จาก AI ไม่ได้ กรุณาลองใหม่';
      }
      final decoded = jsonDecode(text.substring(start, end + 1)); // แปลงข้อความเป็นข้อมูล
      if (decoded is! Map ||
          (decoded['food_name'] ?? '').toString().trim().isEmpty) {
        throw 'อ่านเมนูใหม่จาก AI ไม่ได้ กรุณาลองใหม่';
      }
      json = decoded;
      final wrong = DietCheck.violations( // วัตถุดิบที่ผิดข้อจำกัดอาหาร
        dietType,
        DietCheck.namesOf(decoded['ingredients']),
      );
      final cal = RecipeRepository.toNum(decoded['calories']);
      final pro = RecipeRepository.toNum(decoded['protein']);
      final offBudget = budget != null && !inBudget(cal, pro); // ไม่อยู่ในงบ
      // ใช้เฉพาะของในตู้: ห้ามมีของที่ไม่มีในตู้หรือใช้เกินที่เหลือ
      final missing = fridgeOnly
          ? missingFor(decoded['ingredients'] as List? ?? const [])
          : const <String>[];
      if (wrong.isEmpty && !offBudget && missing.isEmpty) break; // ผ่านหมด -> ใช้เมนูนี้
      if (attempt == 1) { // รอบสุดท้ายแล้วยังไม่ผ่าน
        if (missing.isNotEmpty) {
          throw 'หาเมนูที่ทำได้จากของในตู้เย็นไม่ได้ (ของไม่พอ: ${missing.join(', ')}) '
              'เมนูเดิมยังอยู่ ลองใหม่อีกครั้ง หรือเพิ่มวัตถุดิบในตู้เย็น';
        }
        if (wrong.isNotEmpty) {
          throw 'เมนูที่ได้ยังมี ${wrong.join(', ')} ซึ่งขัดกับข้อจำกัดอาหาร '
              '"$dietType" กรุณาลองใหม่ หรือพิมพ์บอกสิ่งที่ไม่ต้องการ';
        }
        // ลองใหม่แล้วยังไม่อยู่ในงบ: ใช้เมนูนี้ แต่บอกผู้ใช้ว่ายอดวันนี้จะไม่ตรงเป้า
        warning =
            'เมนูใหม่ ${r(cal)} kcal โปรตีน ${r(pro)} g ไม่อยู่ในงบที่เหลือของวันนี้ '
            '(${r(budget!.calMin)}-${r(budget.calMax)} kcal, '
            '${r(budget.proteinMin)}-${r(budget.proteinMax)} g) '
            'ยอดรวมวันนี้จะไม่ตรงเป้า ลองเปลี่ยนเมนูอีกครั้งได้';
        break;
      }
      extraRule = [ // สร้างกฎเพิ่มบอก AI ว่ารอบก่อนผิดตรงไหน
        if (wrong.isNotEmpty)
          '\n- เมนูก่อนหน้า "${decoded['food_name']}" ใช้ ${wrong.join(', ')} '
              'ซึ่งผิดข้อจำกัดอาหาร "$dietType" ห้ามใช้วัตถุดิบเหล่านี้หรือประเภทเดียวกัน',
        if (offBudget)
          '\n- เมนูก่อนหน้าได้ ${r(cal)} kcal โปรตีน ${r(pro)} g ซึ่งไม่อยู่ในช่วงที่กำหนด '
              'ปรับวัตถุดิบหรือปริมาณให้อยู่ในช่วงให้ได้',
        if (missing.isNotEmpty)
          '\n- เมนูก่อนหน้า "${decoded['food_name']}" ใช้ ${missing.join(', ')} '
              'ซึ่งไม่มีในตู้เย็นหรือเกินจำนวนที่เหลือ ใช้เฉพาะวัตถุดิบในรายการและไม่เกินจำนวนที่มี',
      ].join();
    }

    bool inFridge(String name) { // ของชิ้นนี้มีในตู้ไหม
      final n = name.trim().toLowerCase();
      if (n.isEmpty) return false;
      return usable.any((f) {
        final fn = (f['name'] ?? '').toString().trim().toLowerCase();
        return fn.isNotEmpty &&
            (fn == n || fn.contains(n) || n.contains(fn)) &&
            !isUsedUp(f);
      });
    }

    num toNum(Object? v) => v is num // ตัวช่วยแปลงเป็นตัวเลข (ตัดลูกน้ำ)
        ? v
        : num.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;

    // ปริมาณตามที่ AI ตอบ (ก่อนแปลงเป็นหน่วยของตู้) — ใช้เก็บลงคลังสูตรกลาง
    // ให้ตรงกับแคลอรีที่ AI คิด และใช้เป็นค่าเดิมตอนคำนวณใหม่
    final aiIngredients = [
      for (final i in (json['ingredients'] as List? ?? []).whereType<Map>())
        if ((i['name'] ?? '').toString().trim().isNotEmpty)
          {
            'name': i['name'].toString().trim(),
            'quantity': (i['quantity'] ?? '').toString().trim(),
          },
    ];
    final ingredients = [ // วัตถุดิบที่จะบันทึก (แปลงหน่วยให้ตรงตู้แล้ว)
      for (final i in (json['ingredients'] as List? ?? []).whereType<Map>())
        if ((i['name'] ?? '').toString().trim().isNotEmpty)
          () {
            final name = i['name'].toString().trim();
            final have = inFridge(name) || ShoppingSuggestion.isStaple(name);
            return <String, dynamic>{
              'name': name,
              // หน่วยให้ตรงกับของในตู้ (เช่น ผู้ใช้แบ่งเป็นส่วนไว้)
              'quantity': PlanAllocation.quantityInFridgeUnit(
                name,
                (i['quantity'] ?? '').toString().trim(),
                fridge,
              ),
              'checked': have,
              if (!have && !fridgeOnly) ShoppingSuggestion.toBuyKey: true,
            };
          }(),
    ];
    final stepsRaw = json['steps']; // ขั้นตอน: ลิสต์ -> ข้อความใส่เลขข้อ
    final steps = stepsRaw is List
        ? [for (var k = 0; k < stepsRaw.length; k++) '${k + 1}. ${stepsRaw[k]}']
              .join('\n')
        : (stepsRaw ?? '').toString();

    // เก็บเมนูใหม่จาก AI ลงคลังสูตรกลาง แล้วผูกกับมื้อนี้
    final recipeId = await RecipeRepository.saveAiRecipe( // บันทึกเมนูลงคลังสูตรกลาง ได้ id กลับมา
      {
        'recipe_name': json['food_name'],
        'detailed_ingredients': [
          for (final i in aiIngredients)
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

    final update = <String, dynamic>{ // ค่าที่จะบันทึกแทนมื้อเดิม
      'food_name': json['food_name'].toString().trim(),
      'calories': toNum(json['calories']).round(),
      'protein': toNum(json['protein']).round(),
      'ingredients': ingredients,
      'steps': steps,
      'is_cooked': false,
      'recipe_id': recipeId,
    };
    await supabase.from('weekly_meals').update(update).eq('id', meal['id']); // บันทึกลงฐานข้อมูล
    // แปลงหน่วยแล้ว -> แคลอรีที่ AI คิดมาจากปริมาณเดิม ให้คำนวณใหม่
    final aiBefore = [
      for (final i in aiIngredients) '${i['name']} ${i['quantity']}',
    ];
    final aiChanged = [ // มีวัตถุดิบถูกแปลงหน่วยไหม
      for (var k = 0; k < ingredients.length; k++)
        if (ingredients[k]['quantity'] != aiIngredients[k]['quantity']) k,
    ].isNotEmpty;
    final saved = aiChanged // ถูกแปลง -> คำนวณแคลอรีใหม่
        ? await MealNutrition.recalculateAfterUnitChange({
            ...meal,
            ...update,
          }, aiBefore)
        : {...meal, ...update};
    return {...saved, if (warning != null) 'warning': warning}; // ส่งมื้อใหม่กลับ (พร้อมคำเตือนถ้ามี)
  }

  // ของชื่อนี้มีในตู้ไหม (ชื่อตรงหรือคล้าย และยังไม่หมด)
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
  static bool planAllowsBuying(List<dynamic> meals) { // มีวัตถุดิบติดธง "ต้องซื้อ" อย่างน้อย 1 อย่าง = แพลนซื้อเพิ่มได้
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
