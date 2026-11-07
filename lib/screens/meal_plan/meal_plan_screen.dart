import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/screens/meal_plan/weekly_plan_screen.dart';

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/plan_targets.dart';
import 'package:test_app/services/plan_allocation.dart';
import 'package:test_app/services/diet_check.dart';
import 'package:test_app/services/plan_goal.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/services/recipe_repository.dart';

class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  final supabase = Supabase.instance.client;

  final String apiKey = ApiKeys.mealPlanScreen;

  String goal = "ลดน้ำหนัก";

  int meals = 3;

  String diet = "ไม่มี";

  bool loading = false;

  /// true = ใช้เฉพาะของในตู้เย็น (ไม่ต้องออกไปซื้อ แต่อาจไม่ถึงเป้า)
  /// false = ใช้ของในตู้ก่อน แล้วซื้อเพิ่มได้เท่าที่จำเป็น (รวมรายการซื้อในแผนรายสัปดาห์)
  bool fridgeOnly = false;

  final calorieController = TextEditingController();

  final proteinController = TextEditingController();

  // แจ้งเตือนช่องกรอกแบบ Google Forms (ขอบแดง + ข้อความแดงใต้ช่อง)
  // - กรอกผิดรูปแบบ (ตัวอักษร ทศนิยม 0) เตือนทันทีที่พิมพ์ พร้อมตัวอย่าง
  // - ยังไม่ได้กรอก เตือนหลังกดสร้างแผน
  // หายเองเมื่อกรอกตัวเลขที่ใช้ได้
  bool submitted = false;
  final _calorieKey = GlobalKey();
  final _proteinKey = GlobalKey();

  /// แปลงข้อความเป็นเป้าต่อวัน (รับ "1,800" ได้) — null = ใช้ไม่ได้
  static int? _parseTarget(String text) {
    final v = int.tryParse(text.trim().replaceAll(',', ''));
    return v != null && v > 0 ? v : null;
  }

  /// ข้อความแจ้งเตือนของช่อง หรือ null ถ้าไม่มีปัญหา
  /// [example] = ตัวอย่างค่าที่ถูกต้อง เช่น "1800"
  String? _targetError(String text, String example) {
    if (text.trim().isEmpty) return submitted ? "กรุณากรอกช่องนี้" : null;
    if (_parseTarget(text) != null) return null;
    return "กรุณากรอกเป็นตัวเลขจำนวนเต็มที่มากกว่า 0 เช่น $example";
  }

  static const _calorieExample = "1800";
  static const _proteinExample = "90";

  Future<void> createMealPlan() async {
    final user = supabase.auth.currentUser;

    if (user == null) return;

    // ต้องกรอกแคลอรีและโปรตีนต่อวันเอง (ไม่มีค่าเริ่มต้น) — ผู้ใช้กำหนดตาม
    // เป้าหมายของตัวเอง แพลนจะได้ใช้ตัวเลขที่ตรงกับเป้าหมายจริง
    final targetCal = _parseTarget(calorieController.text);
    final targetProtein = _parseTarget(proteinController.text);
    if (targetCal == null || targetProtein == null) {
      setState(() => submitted = true);
      // เลื่อนหน้าจอไปที่ช่องแรกที่ยังไม่ถูกต้อง
      final firstError = targetCal == null ? _calorieKey : _proteinKey;
      final ctx = firstError.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
        );
      }
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      // ===============================
      // ดึงข้อมูลของในตู้เย็น
      // ===============================

      // ของพื้นฐาน (ingredients.is_staple) ใช้ทั้งใน prompt และตอนติดธงต้องซื้อ
      await ShoppingSuggestion.loadStaples();

      final fridgeItems = await supabase
          .from('fridge_items')
          .select()
          .eq('user_id', user.id);

      // รวมลอตที่ชื่อ/หน่วยเดียวกันเป็นรายการเดียวก่อนส่งให้ Gemini
      // ของที่เกินระยะที่เก็บได้แล้วไม่ส่งให้ AI เอาไปวางแผน (อาจไม่ปลอดภัย)
      // withPerCook: แนบ "ใช้ครั้งละ" ที่ผู้ใช้ตั้งไว้ (เช่น "อกไก่ (3 ชิ้น,
      // ใช้ครั้งละ 1 ชิ้น)") ให้ AI ใช้ปริมาณนั้นเป็นหลัก ปริมาณในแพลนจะได้
      // ตรงกับหน้ายืนยันการหักวัตถุดิบตอนกด "ทำแล้ว" ไม่ต้องปรับซ้ำ
      final fridgeList = inventoryPromptList(
        List<Map<String, dynamic>>.from(
          fridgeItems,
        ).where((e) => !isOverdue(e)).toList(),
        withPerCook: true,
      );

      // โหมดใช้เฉพาะของในตู้ ต้องมีของในตู้ (โหมดซื้อเพิ่มได้ ตู้ว่างก็สร้างได้)
      if (fridgeList.isEmpty && fridgeOnly) {
        throw Exception("ไม่มีวัตถุดิบในตู้เย็น");
      }

      // ===============================
      // หาวัตถุดิบที่อยู่ในตู้เย็นนานแล้ว (เอาไว้ให้ Gemini เลือกใช้ก่อน)
      // อิงรูปแบบเดียวกับ ai_recipe_screen.dart
      // ===============================
      final expiringSoon = <Map<String, dynamic>>[];

      for (var item in fridgeItems) {
        // เฉพาะของที่เก็บได้อีกไม่เกินจำนวนวันที่ตั้งแจ้งเตือนไว้ (นับเป็นวัน) และ
        // ยังไม่ได้ใช้หมด
        if (!shouldUseFirst(item, readOldItemDays(user))) continue;

        expiringSoon.add({
          'name': item['name'],
          'days_in_fridge': daysInFridge(item['created_at']),
        });
      }

      // ของที่อยู่ในตู้เย็นนานที่สุดขึ้นก่อน
      expiringSoon.sort(
        (a, b) =>
            (b['days_in_fridge'] as int).compareTo(a['days_in_fridge'] as int),
      );

      final expiringList = expiringSoon.map((e) => e['name']).join(", ");

      // ===============================
      // คลังเมนูที่เคยสร้างไว้แล้ว (ประหยัด token ไม่ต้องยิง Gemini ใหม่
      // ถ้าเมนูเก่ามีวัตถุดิบพอกับของในตู้เย็นตอนนี้อยู่แล้ว)
      // ===============================
      final myPlans = await supabase
          .from('meal_plans')
          .select('id')
          .eq('user_id', user.id);

      final planIds = myPlans.map((p) => p['id']).toList();

      List<dynamic> pastMeals = [];
      if (planIds.isNotEmpty) {
        pastMeals = await supabase
            .from('weekly_meals')
            .select()
            .inFilter('plan_id', planIds);
      }

      // รวมเป็นคลังเมนู ตัดชื่อซ้ำออก (เก็บล่าสุดของแต่ละชื่อ) และข้ามเมนูที่
      // ข้อมูลไม่ครบ (เช่นของเก่าก่อนมีคอลัมน์ steps จึงยังไม่มีขั้นตอนการทำ)
      final Map<String, Map<String, dynamic>> libraryByName = {};
      for (final m in pastMeals) {
        final name = (m['food_name']?.toString() ?? '').trim();
        final ingredients = m['ingredients'];
        final steps = m['steps']?.toString().trim() ?? '';
        if (name.isEmpty ||
            ingredients is! List ||
            ingredients.isEmpty ||
            steps.isEmpty) {
          continue;
        }
        libraryByName[name] = Map<String, dynamic>.from(m);
      }
      final library = libraryByName.values.toList();

      // แยกตัวเลขปริมาณออกจากข้อความ เช่น "1 ชิ้น" -> 1, "1/2 หัว" -> 0.5
      double parseQtyAmount(String qtyText) {
        final fraction = RegExp(
          r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)',
        ).firstMatch(qtyText);
        if (fraction != null) {
          final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
          final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
          return denominator == 0 ? 0 : numerator / denominator;
        }
        final single = RegExp(r'\d+(\.\d+)?').firstMatch(qtyText);
        return double.tryParse(single?.group(0) ?? '') ?? 0;
      }

      // เช็คว่าวัตถุดิบทุกอย่างของเมนูนี้ มีพอในตู้เย็นตอนนี้จริงไหม
      bool allIngredientsAvailable(List ingredients) {
        for (final ing in ingredients) {
          final name = (ing['name']?.toString() ?? '').trim().toLowerCase();
          if (name.isEmpty) continue;

          final needAmount = parseQtyAmount(ing['quantity']?.toString() ?? '');
          if (needAmount <= 0) continue;

          final matches = fridgeItems.where((item) {
            final itemName = (item['name']?.toString() ?? '')
                .trim()
                .toLowerCase();
            return itemName.isNotEmpty &&
                (itemName == name ||
                    itemName.contains(name) ||
                    name.contains(itemName));
          });

          if (matches.isEmpty) return false;

          final haveQty = matches
              .map((m) => num.tryParse(m['quantity']?.toString() ?? '') ?? 0)
              .fold<num>(0, (a, b) => a + b);

          if (haveQty < needAmount.ceil()) return false;
        }
        return true;
      }

      final expiringNamesLower = expiringSoon
          .map((e) => (e['name']?.toString() ?? '').trim().toLowerCase())
          .toSet();

      bool usesExpiringIngredient(List ingredients) {
        return ingredients.any((ing) {
          final name = (ing['name']?.toString() ?? '').trim().toLowerCase();
          return expiringNamesLower.any(
            (e) => e == name || e.contains(name) || name.contains(e),
          );
        });
      }

      // เป้าต่อวันเป็นเพดาน: ยอดรวมทั้งวันห้ามเกิน และขาดได้ไม่เกิน 100 kcal / 10 g
      // (ดู PlanTargets) ใช้ค่าที่ผู้ใช้กรอก (ตรวจไว้แล้วตอนต้นฟังก์ชัน)
      final targets = PlanTargets(
        dayCal: targetCal,
        dayProtein: targetProtein,
        meals: meals,
      );

      // เมนูเก่า/เมนูจากคลังสูตรใช้ได้เฉพาะที่อยู่ในช่วงต่อมื้อ ทั้งแคลอรีและโปรตีน
      bool fitsMealTarget(dynamic calories, dynamic protein) =>
          targets.mealFits(
            RecipeRepository.toNum(calories),
            RecipeRepository.toNum(protein),
          );

      // เมนูเก่าที่วัตถุดิบครบพอใช้ได้เลยตอนนี้ และขนาดมื้อใกล้เป้า — สุ่มลำดับก่อน
      // แล้วเอาเมนูที่ใช้ของที่อยู่ในตู้เย็นนานขึ้นก่อน เพื่อความหลากหลายและช่วยเคลียร์ของเก่า
      // เมนูเก่าต้องผ่านข้อจำกัดอาหารที่เลือกตอนนี้ด้วย (เมนูเก่าไม่มีป้ายข้อจำกัด
      // อาหาร เลยตรวจจากชื่อวัตถุดิบ — เคยทำแพลนปกติแล้วตอนนี้เลือกมังสวิรัติ
      // จะได้ไม่หยิบเมนูที่มีเนื้อสัตว์มาใส่)
      final matched = library
          .where(
            (m) =>
                fitsMealTarget(m['calories'], m['protein']) &&
                DietCheck.fits(diet, DietCheck.namesOf(m['ingredients'])) &&
                allIngredientsAvailable(m['ingredients'] as List),
          )
          .toList();
      matched.shuffle();
      // คะแนนความเหมาะกับเป้าหมาย (ลดน้ำหนัก: โปรตีนต่อแคลอรีสูง,
      // เพิ่มกล้ามเนื้อ: โปรตีนสูง) ทุกเมนูอยู่ในช่วงเป้าต่อมื้ออยู่แล้ว
      double goalScore(Map m) => PlanGoal.score(
        goal,
        RecipeRepository.toNum(m['calories']),
        RecipeRepository.toNum(m['protein']),
      );
      // ใช้ของที่ควรใช้ก่อนมาก่อน แล้วค่อยเลือกเมนูที่เหมาะกับเป้าหมาย
      matched.sort((a, b) {
        final aExp = usesExpiringIngredient(a['ingredients'] as List) ? 0 : 1;
        final bExp = usesExpiringIngredient(b['ingredients'] as List) ? 0 : 1;
        if (aExp != bExp) return aExp.compareTo(bExp);
        return goalScore(b).compareTo(goalScore(a));
      });

      // ช่องมื้ออาหารทั้งสัปดาห์ (วัน x จำนวนมื้อต่อวัน)
      final weekDaysEn = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ];
      final slotGrid = <Map<String, String>>[];
      for (final day in weekDaysEn) {
        for (var i = 1; i <= meals; i++) {
          slotGrid.add({'day': day, 'meal_type': 'มื้อที่ $i'});
        }
      }

      // ===============================
      // จองของในตู้ให้เมนูที่หยิบมาใช้ซ้ำ "รวมกันทั้งสัปดาห์" (เดิมเช็กทีละเมนู
      // อกไก่ 1 ชิ้นเลยทำให้ทุกเมนูที่ใช้อกไก่ผ่าน) — ใช้วิธีจองเดียวกับหน้าแพลน
      // รายสัปดาห์ (PlanAllocation): มื้อที่ใกล้ถึงก่อนได้ของก่อน
      // ===============================
      final planStart = DateTime.now();
      final usableFridge = List<Map<String, dynamic>>.from(
        fridgeItems,
      ).where((e) => !isOverdue(e)).toList();
      // เมนูที่หยิบมาใช้แล้ว + จำนวนของที่ขาดได้ของแต่ละเมนู
      // (เมนูเก่า = ห้ามขาด, คลังกลาง = ขาดได้ 1 อย่างถ้าซื้อเพิ่มได้)
      final picked = <({Map<String, dynamic> meal, int maxShort})>[];

      /// เพิ่ม [meal] ได้ไหม โดยทุกเมนูที่หยิบไว้แล้วยังมีของพอเหมือนเดิม
      bool fitsStock(Map<String, dynamic> meal, int maxShort) {
        final trial = [...picked, (meal: meal, maxShort: maxShort)];
        final alloc = PlanAllocation.allocate(
          meals: [
            for (var k = 0; k < trial.length; k++)
              {...trial[k].meal, 'id': '$k'},
          ],
          fridgeItems: usableFridge,
          planStart: planStart,
        );
        for (var k = 0; k < trial.length; k++) {
          final short = (alloc['$k'] ?? const []).where((st) => !st.have);
          if (short.length > trial[k].maxShort) return false;
        }
        return true;
      }

      final freeSlots = [...slotGrid];

      final reusedMeals = <Map<String, dynamic>>[];
      for (final source in matched) {
        if (freeSlots.isEmpty) break;
        final slot = freeSlots.first;
        final meal = <String, dynamic>{
          'day': slot['day'],
          'meal_type': slot['meal_type'],
          'food_name': source['food_name'],
          'calories': source['calories'],
          'protein': source['protein'],
          'ingredients': source['ingredients'],
          'steps': source['steps'],
          'recipe_id': source['recipe_id'],
        };
        if (!fitsStock(meal, 0)) continue;
        picked.add((meal: meal, maxShort: 0));
        reusedMeals.add(meal);
        freeSlots.removeAt(0);
      }

      // ===============================
      // เติมช่องที่เหลือจากคลังสูตรกลาง (recipes) ก่อนเรียก AI — เมนูที่ทำได้จาก
      // ของในตู้ (ซื้อเพิ่มได้ไม่เกิน 1 อย่างถ้าไม่ได้เปิด "ใช้เฉพาะของในตู้")
      // มีแคลอรี/โปรตีน ตรงข้อจำกัดอาหาร และแคลอรีใกล้เป้าต่อมื้อ
      // ===============================
      final libraryMeals = <Map<String, dynamic>>[];
      if (freeSlots.isNotEmpty) {
        try {
          final candidates = await RecipeRepository.findRecipesForFridge(
            fridgeItems: usableFridge,
            maxMissing: fridgeOnly ? 0 : 1,
            limit: 60,
            requireNutrition: true,
            excludeNames: {
              for (final m in reusedMeals) (m['food_name'] ?? '').toString(),
            },
            useFirstNames: {
              for (final e in expiringSoon) (e['name'] ?? '').toString(),
            },
          );
          final suitable = candidates.where((r) {
            if (diet != 'ไม่มี' && !(r['diet_tags'] as List).contains(diet)) {
              return false;
            }
            // ตรวจซ้ำจากชื่อวัตถุดิบ กันเมนูที่เคยถูกติดป้ายผิด
            final names = [
              for (final ing in RecipeRepository.ingredientsOf(r)) ing['name'],
            ];
            if (!DietCheck.fits(diet, names)) return false;
            return fitsMealTarget(r['calories'], r['protein']);
          }).toList();
          // คงลำดับเดิม (ซื้อเพิ่มน้อยก่อน -> ใช้ของที่ควรใช้ก่อน) แล้วค่อยเลือก
          // เมนูที่เหมาะกับเป้าหมายก่อนในกลุ่มเดียวกัน
          final libOrder = {
            for (var i = 0; i < suitable.length; i++) suitable[i]: i,
          };
          suitable.sort((a, b) {
            final byMissing = (a['missing'] as List).length.compareTo(
              (b['missing'] as List).length,
            );
            if (byMissing != 0) return byMissing;
            final byFirst =
                (b['uses_first'] == true ? 1 : 0) -
                (a['uses_first'] == true ? 1 : 0);
            if (byFirst != 0) return byFirst;
            final byGoal = goalScore(b).compareTo(goalScore(a));
            if (byGoal != 0) return byGoal;
            return libOrder[a]!.compareTo(libOrder[b]!);
          });
          for (final r in suitable) {
            if (freeSlots.isEmpty) break;
            final slot = freeSlots.first;
            final meal = <String, dynamic>{
              'day': slot['day'],
              'meal_type': slot['meal_type'],
              'food_name': r['recipe_name'],
              'calories': RecipeRepository.toNum(r['calories']).round(),
              'protein': RecipeRepository.toNum(r['protein']).round(),
              'ingredients': [
                for (final ing in RecipeRepository.ingredientsOf(r))
                  {
                    'name': ing['name'],
                    'quantity':
                        '${RecipeRepository.formatNum(ing['use_quantity'])} ${ing['unit'] ?? ''}'
                            .trim(),
                  },
              ],
              'steps': RecipeRepository.stepTextsOf(r),
              'recipe_id': r['recipe_id'],
            };
            final maxShort = fridgeOnly ? 0 : 1;
            if (!fitsStock(meal, maxShort)) continue;
            picked.add((meal: meal, maxShort: maxShort));
            libraryMeals.add(meal);
            freeSlots.removeAt(0);
            logAiRequest(
              event: AiEvent.mealPlan,
              result: AiResult.cacheHit,
              recipeId: r['recipe_id'],
            );
          }
        } catch (e) {
          debugPrint('ค้นคลังสูตรสำหรับแพลนไม่สำเร็จ (ใช้ AI แทน): $e');
        }
      }

      // ช่องที่เหลือ (ถ้ามี) ค่อยให้ Gemini สร้างเสริมเฉพาะส่วนที่ขาด — ถ้า
      // เมนูเก่าครบพอทั้งสัปดาห์แล้ว ช่องนี้จะว่างและไม่ต้องเรียก Gemini เลย
      final remainingSlots = freeSlots;

      // ของที่เหลือในตู้หลังจองให้เมนูข้างบนแล้ว — บอก Gemini เฉพาะส่วนนี้
      // ไม่งั้น AI จะเอาของที่ถูกจองไปแล้วมาใช้ซ้ำ
      final fridgeListForAi = picked.isEmpty
          ? fridgeList
          : inventoryPromptList(
              PlanAllocation.leftoverStock(
                meals: [
                  for (var k = 0; k < picked.length; k++)
                    {...picked[k].meal, 'id': '$k'},
                ],
                fridgeItems: usableFridge,
                planStart: planStart,
              ),
              withPerCook: true,
            );

      // ===============================
      // สร้างข้อมูล plan
      // ===============================

      final plan = await supabase
          .from('meal_plans')
          .insert({
            'user_id': user.id,

            'goal': goal,

            'meals_per_day': meals,

            'target_calories': targetCal,

            'target_protein': targetProtein,

            'diet_type': diet,
          })
          .select()
          .single();

      final planId = plan['id'];

      // ===============================
      // Gemini — เรียกเฉพาะตอนที่เมนูเก่าในคลังไม่พอเติมเต็มสัปดาห์เท่านั้น
      // ถ้า remainingSlots ว่าง (เมนูเก่าครบพอแล้ว) จะข้ามส่วนนี้ไปเลย
      // เพื่อประหยัด token/การเรียกใช้ API
      // ===============================

      List<dynamic> geminiMeals = [];

      final usedNames = [...reusedMeals, ...libraryMeals]
          .map((m) => m['food_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(", ");

      String r(num v) => v.round().toString();

      // ช่องมื้อพร้อมช่วงแคลอรี/โปรตีนที่มื้อนั้นต้องอยู่
      Map<String, dynamic> budgetSlot(
        Map slot, {
        required num calMin,
        required num calMax,
        required num proteinMin,
        required num proteinMax,
      }) => {
        'day': slot['day'].toString(),
        'meal_type': slot['meal_type'].toString(),
        'kcal': '${r(calMin)}-${calMax.floor()}',
        'protein': '${r(proteinMin)}-${proteinMax.floor()}',
      };

      // ให้ Gemini สร้างเมนูสำหรับช่องที่กำหนด (แต่ละช่องมีช่วง kcal/protein ของตัวเอง)
      // [extraRule] ใช้ตอนขอแก้วันที่ยอดรวมไม่ตรงเป้า
      Future<List<dynamic>> askGemini(
        List<Map<String, dynamic>> slots, {
        String extraRule = '',
      }) async {
        final slotsJson = slots
            .map(
              (s) =>
                  '{"day":"${s['day']}","meal_type":"${s['meal_type']}",'
                  '"kcal":"${s['kcal']}","protein":"${s['protein']}"}',
            )
            .join(",\n");

        final prompt =
            """

คุณเป็น AI Nutritionist


${fridgeOnly ? "ใช้วัตถุดิบจากตู้เย็นของผู้ใช้เท่านั้น" : "ใช้วัตถุดิบจากตู้เย็นของผู้ใช้เป็นหลัก ซื้อเพิ่มได้เท่าที่จำเป็น"}


วัตถุดิบที่มี:

${fridgeListForAi.isEmpty ? 'ไม่มี (ของในตู้ถูกจองให้มื้ออื่นหมดแล้ว)' : fridgeListForAi}



วัตถุดิบที่อยู่ในตู้เย็นมานานแล้ว (พยายามบังคับใช้ในเมนูก่อนวัตถุดิบอื่น):

${expiringList.isEmpty ? "ไม่มี" : expiringList}



เป้าหมาย:

$goal (${PlanGoal.promptRule(goal)})



Calories:

ยอดรวมทั้งวัน ${targetCal - PlanTargets.calTolerance}-$targetCal kcal (เป้าที่ผู้ใช้ตั้งเป็นเพดาน ห้ามเกิน)



Protein:

ยอดรวมทั้งวัน ${targetProtein - PlanTargets.proteinTolerance}-$targetProtein g (ห้ามเกิน)



ข้อจำกัดอาหาร:

$diet



สร้างเมนูเฉพาะสำหรับช่องต่อไปนี้เท่านั้น จำนวน ${slots.length} มื้อ
(ระบุ day และ meal_type ให้ตรงกับที่กำหนดมาเป๊ะๆ ห้ามเพิ่มหรือลดจำนวน
แต่ละช่องมี "kcal" และ "protein" เป็นช่วงที่มื้อนั้นต้องอยู่ ห้ามต่ำกว่าหรือเกินช่วง):

[
$slotsJson
]

${usedNames.isEmpty ? "" : "ห้ามสร้างเมนูซ้ำกับเมนูต่อไปนี้ที่ใช้ไปแล้วในสัปดาห์นี้: $usedNames"}



กฎ:

${fridgeOnly ? '''- ห้ามสร้างวัตถุดิบที่ไม่มีในรายการ''' : '''- ใช้วัตถุดิบในตู้เย็นก่อนเสมอ (โดยเฉพาะของที่อยู่มานาน) แล้วค่อยซื้อเพิ่ม
- ซื้อเพิ่มได้เฉพาะเท่าที่จำเป็น เพื่อให้เมนูทำได้จริงและใกล้เป้า เลือกของหาง่ายในไทย ราคาไม่แพง
  เข้ากับข้อจำกัดอาหาร และใช้ของที่ซื้อซ้ำในหลายมื้อได้ (จะได้ไม่ต้องซื้อหลายอย่าง)
- วัตถุดิบที่ไม่มีในตู้เย็น ให้ใส่ "to_buy": true ใน ingredients ของมื้อนั้น'''}
- ถือว่าบ้านมีของพื้นฐานอยู่แล้ว ใช้ได้เลยโดยไม่ต้องอยู่ในรายการวัตถุดิบและไม่ต้องซื้อ:
  ${ShoppingSuggestion.stapleNamesForPrompt()}
- ใช้วัตถุดิบที่มีอยู่ให้คุ้มค่า
- ให้ความสำคัญกับวัตถุดิบที่อยู่ในตู้เย็นมานานก่อนเป็นอันดับแรก
- สามารถใช้วัตถุดิบเดิมซ้ำได้
- ระบุ ingredients ของแต่ละมื้อ${fridgeOnly ? " โดยเลือกจากวัตถุดิบที่มีเท่านั้น" : ""} พร้อมปริมาณที่ใช้
- ปริมาณที่ใช้ต้องเป็นหน่วยเดียวกับวัตถุดิบที่มี (เช่น ส่วน, ฟอง, ผล, หัว) ของที่ต้องซื้อใช้หน่วยที่นับได้
  (ชิ้น, ฟอง, กล่อง, แพ็ค, หัว) ห้ามใช้กรัม/กก./มล./ช้อน
  เพราะผู้ใช้ไม่ได้ชั่งตวง (1 ส่วน ≈ ใช้ทำอาหาร 1 ครั้ง ใช้ "1/2 ส่วน" ได้)
- ถ้าวัตถุดิบมีระบุ "ใช้ครั้งละ" ไว้ ให้ใช้ปริมาณนั้นต่อ 1 มื้อเป็นหลัก
  (เช่น "ใช้ครั้งละ 1 ชิ้น" ให้ใส่ "1 ชิ้น" ไม่ใช่ "1/2 ชิ้น") ใช้มากกว่านั้นได้
  เฉพาะเมื่อเมนูจำเป็นจริงๆ และต้องไม่เกินจำนวนที่มี
- calories และ protein ของแต่ละมื้อ ต้องคำนวณจากวัตถุดิบและปริมาณที่ใส่ในมื้อนั้นจริงเท่านั้น
  (เช่น ไข่ไก่ 1 ฟอง ≈ 70 kcal / โปรตีน 6 g) ห้ามเอาเป้าต่อวันมาหารแบ่งเป็นค่าต่อมื้อ
  และห้ามปั้นตัวเลขให้ถึงเป้า ถ้าวัตถุดิบไม่พอถึงเป้า ให้ตอบตัวเลขต่ำตามจริง
  (พยายามเลือกเมนู/ปริมาณให้ใกล้เป้าที่สุดเท่าที่วัตถุดิบจริงทำได้)
- แต่ละมื้อต้องเป็นมื้ออาหารเต็มมื้อ ไม่ใช่ของว่างเล็กๆ (เช่น ไข่ 1/4 ฟอง + ผลไม้ 1/4 ลูก ไม่นับเป็นมื้อ)
  มีแหล่งโปรตีน (เนื้อสัตว์ ไข่ เต้าหู้ ถั่ว ฯลฯ) และแหล่งพลังงาน (ข้าว เส้น ขนมปัง ฯลฯ) ทุกมื้อ
- calories และ protein ของแต่ละมื้อต้องอยู่ในช่วง "kcal" และ "protein" ของช่องนั้น ทั้งสองอย่าง
  ปรับปริมาณให้ลงช่วง: แคลอรีเกิน -> ลดข้าว/น้ำมัน/ของทอด, โปรตีนเกิน -> ลดเนื้อสัตว์ เพิ่มข้าว/ผักแทน,
  โปรตีนขาด -> เพิ่มเนื้อสัตว์ไขมันต่ำ (อกไก่ ปลา ไข่ขาว เต้าหู้)
${fridgeOnly ? '''- ถ้าของในตู้ไม่พอถึงช่วง ให้ใช้ปริมาณมากขึ้นเท่าที่มีจริง (ไม่เกินจำนวนที่มี)''' : '''- ถ้าของในตู้ไม่พอถึงช่วง ให้ซื้อเพิ่ม (โดยเฉพาะแหล่งโปรตีน เช่น อกไก่ ไข่ไก่ เต้าหู้ ปลา)
  ใส่ "to_buy": true ห้ามปล่อยมื้อให้ขาดช่วงเพียงเพราะไม่อยากซื้อของ'''}
$extraRule
- ระบุ steps เป็นขั้นตอนการทำอาหารแบบละเอียด เรียงเป็นข้อๆ (array ของ string ภาษาไทย)
- ส่งออก JSON เท่านั้น




รูปแบบ:

[
{
"day":"Monday",
"meal_type":"มื้อที่ 1",
"food_name":"ข้าวอกไก่ไข่ดาว",
"calories":450,
"protein":35,
"ingredients":[
{"name":"อกไก่","quantity":"1 ชิ้น"},
{"name":"ไข่ไก่","quantity":"1 ฟอง"}${fridgeOnly ? "" : ''',
{"name":"บรอกโคลี","quantity":"1/2 หัว","to_buy":true}'''}
],
"steps":[
"หั่นอกไก่เป็นชิ้นพอดีคำ",
"ทอดไข่ดาวจนสุกตามชอบ",
"นำอกไก่ไปย่างหรือผัดจนสุก จัดใส่จาน"
]
}
]


""";

        // Gemini ตอบ 503 "high demand" ได้เป็นพักๆ ลองใหม่อัตโนมัติก่อนแจ้ง error
        final result = await generateGemini(
          apiKey: apiKey,
          logEvent: AiEvent.mealPlan,
          content: [Content.text(prompt)],
          timeout: const Duration(seconds: 90),
        );

        String json = result.text!
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();

        return jsonDecode(json) as List<dynamic>;
      }

      if (remainingSlots.isNotEmpty) {
        // ช่วงต่อมื้อของช่องที่ให้ AI ทำ: วันที่มีเมนูจากคลังอยู่แล้วบางมื้อ แบ่งงบที่เหลือ
        // ของวันนั้นให้มื้อที่เหลือ (มื้อจากคลังอยู่ในช่วงต่อมื้ออยู่แล้ว)
        final fixedMeals = [...reusedMeals, ...libraryMeals];
        List<Map<String, dynamic>> budgetFor(
          List<Map> slots,
          List<Map> keptMeals,
        ) {
          final out = <Map<String, dynamic>>[];
          final byDay = <String, List<Map>>{};
          for (final s in slots) {
            byDay.putIfAbsent(s['day'].toString(), () => []).add(s);
          }
          byDay.forEach((day, daySlots) {
            final kept = keptMeals.where((m) => m['day'] == day);
            final b = targets.slotBudget(
              fixedCal: kept.fold<num>(
                0,
                (a, m) => a + RecipeRepository.toNum(m['calories']),
              ),
              fixedProtein: kept.fold<num>(
                0,
                (a, m) => a + RecipeRepository.toNum(m['protein']),
              ),
              slots: daySlots.length,
            );
            for (final s in daySlots) {
              out.add(
                budgetSlot(
                  s,
                  calMin: b.calMin,
                  calMax: b.calMax,
                  proteinMin: b.proteinMin,
                  proteinMax: b.proteinMax,
                ),
              );
            }
          });
          return out;
        }

        geminiMeals = await askGemini(budgetFor(remainingSlots, fixedMeals));

        // ตรวจยอดรวมรายวัน: วันที่หลุดช่วง (เกินเป้า หรือขาดเกิน 100 kcal / 10 g)
        // ให้ AI ทำมื้อของวันนั้นใหม่ด้วยงบที่เหลือจริง สูงสุด 2 รอบ ใช้ผลที่ใกล้ช่วงกว่า
        // ยังไม่ผ่านอีก หน้าแพลนจะขึ้น "เกิน"/"ขาด" ให้เห็น
        ({num cal, num protein}) dayTotal(String day) {
          num cal = 0, pro = 0;
          for (final m in [...fixedMeals, ...geminiMeals.whereType<Map>()]) {
            if (m['day'] != day) continue;
            cal += RecipeRepository.toNum(m['calories']);
            pro += RecipeRepository.toNum(m['protein']);
          }
          return (cal: cal, protein: pro);
        }

        for (var round = 0; round < 2; round++) {
          final badDays =
              {
                for (final m in geminiMeals.whereType<Map>())
                  m['day'].toString(),
              }.where((d) {
                final t = dayTotal(d);
                return !targets.dayFits(t.cal, t.protein);
              }).toList();
          if (badDays.isEmpty) break;

          final redo = [
            for (final m in geminiMeals.whereType<Map>())
              if (badDays.contains(m['day'].toString())) m,
          ];
          try {
            final fixed = await askGemini(
              budgetFor(redo, fixedMeals),
              extraRule:
                  '- รอบนี้แก้วันที่ยอดรวมไม่ตรงเป้า (เดิม: ${badDays.map((d) {
                    final t = dayTotal(d);
                    return '$d ${r(t.cal)} kcal โปรตีน ${r(t.protein)} g';
                  }).join(', ')}) ทำทุกมื้อให้อยู่ในช่วง kcal/protein ของช่องให้ได้',
            );
            for (final day in badDays) {
              final before = dayTotal(day);
              final newMeals = fixed
                  .whereType<Map>()
                  .where((f) => f['day'] == day)
                  .toList();
              final oldMeals = [
                for (final m in geminiMeals.whereType<Map>())
                  if (m['day'] == day) m,
              ];
              if (newMeals.length != oldMeals.length) continue;
              geminiMeals.removeWhere((m) => m is Map && m['day'] == day);
              geminiMeals.addAll(newMeals);
              final after = dayTotal(day);
              if (targets.dayDistance(after.cal, after.protein) >=
                  targets.dayDistance(before.cal, before.protein)) {
                // ผลใหม่ไม่ดีกว่า -> ใช้ของเดิม
                geminiMeals.removeWhere((m) => m is Map && m['day'] == day);
                geminiMeals.addAll(oldMeals);
              }
            }
          } catch (e) {
            debugPrint('แก้วันที่ยอดรวมไม่ตรงเป้าไม่สำเร็จ (ใช้ผลเดิม): $e');
            break;
          }
        }

        // ตรวจข้อจำกัดอาหารของเมนูจาก AI (ดูจากชื่อวัตถุดิบ) — ผิด ให้ AI ทำมื้อนั้น
        // ใหม่ 1 รอบ ยังผิดอีก ใช้ในแพลนได้แต่ไม่ติดป้ายข้อจำกัดอาหาร (กันลามไป
        // ผู้ใช้คนอื่นที่หยิบเมนูจากคลังกลางตามป้าย)
        List<String> dietViolations(Map m) =>
            DietCheck.violations(diet, DietCheck.namesOf(m['ingredients']));
        final wrongDiet = [
          for (final m in geminiMeals.whereType<Map>())
            if (dietViolations(m).isNotEmpty) m,
        ];
        if (wrongDiet.isNotEmpty) {
          try {
            final fixed = await askGemini(
              budgetFor(wrongDiet, [
                ...fixedMeals,
                for (final m in geminiMeals.whereType<Map>())
                  if (!wrongDiet.contains(m)) m,
              ]),
              extraRule:
                  '- รอบนี้แก้เมนูที่ผิดข้อจำกัดอาหาร "$diet" (${wrongDiet.map((m) => '${m['food_name']}: ${dietViolations(m).join('/')}').join(', ')}) ห้ามใช้วัตถุดิบเหล่านี้หรือวัตถุดิบประเภทเดียวกัน',
            );
            for (final f in fixed.whereType<Map>()) {
              if (dietViolations(f).isNotEmpty) continue;
              final k = geminiMeals.indexWhere(
                (m) =>
                    m is Map &&
                    m['day'] == f['day'] &&
                    m['meal_type'] == f['meal_type'] &&
                    wrongDiet.contains(m),
              );
              if (k >= 0) geminiMeals[k] = f;
            }
          } catch (e) {
            debugPrint('แก้เมนูที่ผิดข้อจำกัดอาหารไม่สำเร็จ (ใช้ผลเดิม): $e');
          }
        }

        // เก็บเมนูใหม่จาก AI ลงคลังสูตรกลาง ครั้งหน้า (ของผู้ใช้คนไหนก็ได้) จะได้
        // หยิบจากคลังแทนการเรียก AI
        for (final m in geminiMeals.whereType<Map>()) {
          final steps = m['steps'];
          final id = await RecipeRepository.saveAiRecipe(
            {
              'recipe_name': m['food_name'],
              'detailed_ingredients': [
                for (final ing
                    in (m['ingredients'] as List? ?? []).whereType<Map>())
                  {
                    'name': ing['name'],
                    'use_quantity': RecipeRepository.leadingNumber(
                      ing['quantity'],
                    ),
                    'unit': (ing['quantity'] ?? '')
                        .toString()
                        .replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '')
                        .trim(),
                  },
              ],
              'instructions': steps is List
                  ? [
                      for (var k = 0; k < steps.length; k++)
                        '${k + 1}. ${steps[k]}',
                    ]
                  : [steps?.toString() ?? ''],
            },
            caloriesPerServing: RecipeRepository.toNum(m['calories']),
            proteinPerServing: RecipeRepository.toNum(m['protein']),
            // ติดป้ายข้อจำกัดอาหารเฉพาะเมนูที่วัตถุดิบผ่านการตรวจจริง
            dietTags: [
              if (diet != 'ไม่มี' && dietViolations(m).isEmpty) diet,
            ],
          );
          if (id != null) m['recipe_id'] = id;
        }
      }

      // รวมเมนูที่หยิบจากคลังเก่า (ประหยัด token) กับเมนูใหม่จาก Gemini
      // (ถ้ามี) เข้าด้วยกันเป็นแผนอาหารสัปดาห์เดียว
      final List mealsData = [...reusedMeals, ...libraryMeals, ...geminiMeals];

      // ===============================
      // บันทึก weekly_meals
      // ===============================

      // ชื่อวัตถุดิบที่มีจริงในตู้เย็น (normalize ไว้เทียบแบบไม่สนตัวพิมพ์/ช่องว่าง)
      final fridgeNames = fridgeItems
          .map((item) => (item['name']?.toString() ?? '').trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .toList();

      bool inFridge(String ingredientName) {
        final normalized = ingredientName.trim().toLowerCase();
        if (normalized.isEmpty) return false;
        return fridgeNames.any(
          (n) => n.contains(normalized) || normalized.contains(n),
        );
      }

      for (var meal in mealsData) {
        // วัตถุดิบของมื้อนี้ (มาจาก Gemini โดยอิงของจริงในตู้เย็นเท่านั้น)
        // checked สะท้อนของจริงในตู้เย็น ณ ตอนสร้างแผน ไม่ใช่ค่าคงที่
        final ingredientsList = (meal['ingredients'] as List? ?? []).map((ing) {
          final name = ing['name']?.toString() ?? '';
          // ของพื้นฐาน (ข้าว เครื่องปรุง ฯลฯ) ถือว่ามีในบ้าน ไม่ต้องซื้อ
          final have = inFridge(name) || ShoppingSuggestion.isStaple(name);
          return {
            'name': name,
            'quantity': ing['quantity']?.toString() ?? '',
            'checked': have,
            // ไม่มีในตู้เย็น -> ต้องซื้อ (รวมเป็นรายการซื้อของในแผนรายสัปดาห์)
            if (!have) ShoppingSuggestion.toBuyKey: true,
          };
        }).toList();

        // ขั้นตอนการทำอาหารจาก Gemini (อาจส่งมาเป็น array หรือ string ก็ได้)
        final stepsRaw = meal['steps'];
        String stepsText;
        if (stepsRaw is List) {
          stepsText = stepsRaw
              .asMap()
              .entries
              .map((e) => "${e.key + 1}. ${e.value}")
              .join("\n");
        } else {
          stepsText = stepsRaw?.toString() ?? '';
        }

        await supabase.from('weekly_meals').insert({
          'plan_id': planId,

          'day': meal['day'],

          'meal_type': meal['meal_type'],

          'food_name': meal['food_name'],

          'calories': meal['calories'],

          'protein': meal['protein'],

          'ingredients': ingredientsList,

          'steps': stepsText,

          'is_cooked': false,

          // สูตรในคลังกลางที่มื้อนี้มาจาก (ถ้ามี)
          if (meal['recipe_id'] != null) 'recipe_id': meal['recipe_id'],
        });
      }

      Navigator.push(
        context,

        MaterialPageRoute(builder: (_) => WeeklyPlanScreen(planId: planId)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(geminiErrorMessage(e, fallback: "สร้างแผนไม่สำเร็จ")),
        ),
      );
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _buildHeader(context),

              const SizedBox(height: 20),

              buildTitle(Icons.track_changes, "เป้าหมาย"),

              buildChoiceCard(
                "ลดน้ำหนัก",

                "ควบคุม Calories",

                goal == "ลดน้ำหนัก",

                () {
                  setState(() {
                    goal = "ลดน้ำหนัก";
                  });
                },
              ),

              buildChoiceCard(
                "รักษาน้ำหนัก",

                "Balance สุขภาพ",

                goal == "รักษาน้ำหนัก",

                () {
                  setState(() {
                    goal = "รักษาน้ำหนัก";
                  });
                },
              ),

              buildChoiceCard(
                "เพิ่มกล้ามเนื้อ",

                "High Protein",

                goal == "เพิ่มกล้ามเนื้อ",

                () {
                  setState(() {
                    goal = "เพิ่มกล้ามเนื้อ";
                  });
                },
              ),

              const SizedBox(height: 20),

              buildTitle(Icons.brunch_dining, "จำนวนมื้อต่อวัน"),

              _buildMealCounter(),

              const SizedBox(height: 20),

              buildTitle(Icons.local_fire_department, "เป้าหมายโภชนาการ"),

              buildInput(
                "Calories ต่อวัน",
                calorieController,
                "kcal",
                key: _calorieKey,
                error: _targetError(calorieController.text, _calorieExample),
                // อัปเดตข้อความเตือนทันทีที่พิมพ์
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 15),

              buildInput(
                "Protein ต่อวัน",
                proteinController,
                "g",
                key: _proteinKey,
                error: _targetError(proteinController.text, _proteinExample),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 20),

              buildTitle(Icons.block, "ข้อจำกัดอาหาร"),

              _buildDietDropdown(),

              const SizedBox(height: 20),

              _buildFridgeOnlySwitch(),

              const SizedBox(height: 25),

              _buildCreateButton(),
            ],
          ),
        ),
      ),

      bottomNavigationBar: const AppBottomNav(current: AppTab.plan),
    );
  }

  Widget _buildFridgeOnlySwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: fridgeOnly,
        onChanged: (v) => setState(() => fridgeOnly = v),
        title: const Text(
          "ใช้เฉพาะของในตู้เย็น",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          fridgeOnly
              ? "ไม่ต้องออกไปซื้อ แต่บางวันอาจไม่ถึงเป้า"
              : "ใช้ของในตู้ก่อน ซื้อเพิ่มเท่าที่จำเป็น (มีรายการซื้อของให้)",
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.pop(context);
          },
          child: Container(
            height: 45,
            width: 45,
            decoration: BoxDecoration(
              color: const Color(0xfffff7d0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: BackIcon(size: 20)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7D0),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Row(
              children: [
                CalendarIcon(size: 22),
                SizedBox(width: 10),
                Text(
                  "สร้างแพลนอาหาร",
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMealCounter() {
    return Container(
      padding: const EdgeInsets.all(15),

      decoration: boxDecoration(),

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          IconButton(
            icon: const Icon(Icons.remove),

            onPressed: () {
              if (meals > 1) {
                setState(() {
                  meals--;
                });
              }
            },
          ),

          Text(
            "$meals มื้อ",

            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          IconButton(
            icon: const Icon(Icons.add),

            onPressed: () {
              setState(() {
                meals++;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDietDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),

      decoration: boxDecoration(),

      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: diet,

          isExpanded: true,

          items: [
            "ไม่มี",

            "มังสวิรัติ",

            "เจ",

            "ไม่ทานนม",
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),

          onChanged: (value) {
            setState(() {
              diet = value!;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,

      height: 55,

      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFF7D0),

          foregroundColor: Colors.black87,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),

        onPressed: loading ? null : createMealPlan,

        child: loading
            ? const CircularProgressIndicator()
            : const Text(
                "สร้างแผนอาหาร",

                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget buildTitle(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget buildChoiceCard(
    String title,

    String sub,

    bool selected,

    VoidCallback tap,
  ) {
    return GestureDetector(
      onTap: tap,

      child: Container(
        margin: const EdgeInsets.only(bottom: 10),

        padding: const EdgeInsets.all(15),

        decoration: BoxDecoration(
          color: selected ? const Color(0xfffff7d0) : Colors.white,

          borderRadius: BorderRadius.circular(20),
        ),

        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
            ),

            const SizedBox(width: 15),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    fontSize: 16,

                    fontWeight: FontWeight.bold,
                  ),
                ),

                Text(sub),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ช่องกรอกตัวเลข — [error] = ข้อความเตือน (null = ไม่มีปัญหา): ขอบแดง +
  /// ข้อความแดงใต้ช่อง (แบบ Google Forms)
  Widget buildInput(
    String label,

    TextEditingController controller,

    String suffix, {
    Key? key,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    final showError = error != null;
    const errorColor = Color(0xffD93025);
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: boxDecoration().copyWith(
            border: Border.all(
              color: showError ? errorColor : Colors.white,
              width: 1.5,
            ),
          ),

          child: TextField(
            controller: controller,

            onChanged: onChanged,

            keyboardType: TextInputType.number,

            decoration: InputDecoration(
              labelText: label,

              labelStyle: showError
                  ? const TextStyle(color: errorColor)
                  : null,

              suffixText: suffix,

              border: InputBorder.none,

              contentPadding: const EdgeInsets.all(15),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.error_outline, size: 16, color: errorColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(fontSize: 13, color: errorColor),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  BoxDecoration boxDecoration() {
    return BoxDecoration(
      color: Colors.white,

      borderRadius: BorderRadius.circular(20),
    );
  }
}
