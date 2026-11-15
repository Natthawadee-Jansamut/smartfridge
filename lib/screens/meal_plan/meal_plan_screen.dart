import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/screens/meal_plan/weekly_plan_screen.dart'; // หน้าแผนรายสัปดาห์ (ไปต่อหลังสร้าง)

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';

import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini
import 'dart:convert'; // jsonDecode
import 'package:test_app/config/api_keys.dart'; // คีย์ AI
import 'package:test_app/services/plan_targets.dart'; // ช่วงเป้าแคลอรี/โปรตีน
import 'package:test_app/services/meal_nutrition.dart'; // คำนวณโภชนาการใหม่
import 'package:test_app/services/plan_allocation.dart'; // จองของให้แต่ละมื้อ
import 'package:test_app/services/diet_check.dart'; // ตรวจข้อจำกัดอาหาร
import 'package:test_app/services/plan_goal.dart'; // เป้าหมาย (คะแนน + คำสั่ง AI)
import 'package:test_app/services/fridge_stock.dart'; // รายการของในตู้สำหรับ prompt
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/services/shopping_suggestion.dart'; // ของพื้นฐาน
import 'package:test_app/services/recipe_repository.dart'; // ค้น/บันทึกสูตรในคลังกลาง
import 'package:test_app/services/non_food_check.dart'; // ตรวจของที่ไม่ใช่อาหาร

// หน้าสร้างแพลนอาหารรายสัปดาห์ (ตั้งเป้า -> ใช้เมนูเก่า/คลังสูตร -> ให้ AI เติมที่ขาด)
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  final supabase = Supabase.instance.client;

  final String apiKey = ApiKeys.mealPlanScreen; // คีย์ AI ของหน้านี้

  String goal = "ลดน้ำหนัก"; // [UI] เป้าหมายที่เลือกเริ่มต้น

  int meals = 3; // [UI] จำนวนมื้อต่อวันเริ่มต้น

  String diet = "ไม่มี"; // [UI] ข้อจำกัดอาหารเริ่มต้น

  bool loading = false; // กำลังสร้างแพลนไหม

  /// true = ใช้เฉพาะของในตู้เย็น (ไม่ต้องออกไปซื้อ แต่อาจไม่ถึงเป้า)
  /// false = ใช้ของในตู้ก่อน แล้วซื้อเพิ่มได้เท่าที่จำเป็น (รวมรายการซื้อในแผนรายสัปดาห์)
  bool fridgeOnly = false;

  final calorieController = TextEditingController(); // ช่องแคลอรีต่อวัน

  final proteinController = TextEditingController(); // ช่องโปรตีนต่อวัน

  // แจ้งเตือนช่องกรอกแบบ Google Forms (ขอบแดง + ข้อความแดงใต้ช่อง)
  // - กรอกผิดรูปแบบ (ตัวอักษร ทศนิยม 0) เตือนทันทีที่พิมพ์ พร้อมตัวอย่าง
  // - ยังไม่ได้กรอก เตือนหลังกดสร้างแผน
  // หายเองเมื่อกรอกตัวเลขที่ใช้ได้
  bool submitted = false; // กดสร้างแผนแล้วหรือยัง (ใช้เตือนช่องว่าง)
  final _calorieKey = GlobalKey(); // กุญแจของช่องแคลอรี (ไว้เลื่อนจอไปหา)
  final _proteinKey = GlobalKey(); // กุญแจของช่องโปรตีน

  /// แปลงข้อความเป็นเป้าต่อวัน (รับ "1,800" ได้) — null = ใช้ไม่ได้
  static int? _parseTarget(String text) {
    final v = int.tryParse(text.trim().replaceAll(',', '')); // ตัดลูกน้ำออกแล้วแปลงเป็นเลข
    return v != null && v > 0 ? v : null; // ต้องมากกว่า 0
  }

  /// ข้อความแจ้งเตือนของช่อง หรือ null ถ้าไม่มีปัญหา
  /// [example] = ตัวอย่างค่าที่ถูกต้อง เช่น "1800"
  String? _targetError(String text, String example) {
    if (text.trim().isEmpty) return submitted ? "กรุณากรอกช่องนี้" : null; // ว่าง -> เตือนเฉพาะหลังกดสร้าง
    if (_parseTarget(text) != null) return null; // ถูกต้อง -> ไม่มีปัญหา
    return "กรุณากรอกเป็นตัวเลขจำนวนเต็มที่มากกว่า 0 เช่น $example";
  }

  static const _calorieExample = "1800"; // [UI] ตัวอย่างแคลอรีในข้อความเตือน
  static const _proteinExample = "90"; // [UI] ตัวอย่างโปรตีนในข้อความเตือน

  // กด "สร้างแผนอาหาร" — ขั้นตอนหลักทั้งหมดของการสร้างแพลน
  Future<void> createMealPlan() async {
    final user = supabase.auth.currentUser;

    if (user == null) return; // ยังไม่ล็อกอิน

    // ต้องกรอกแคลอรีและโปรตีนต่อวันเอง (ไม่มีค่าเริ่มต้น) — ผู้ใช้กำหนดตาม
    // เป้าหมายของตัวเอง แพลนจะได้ใช้ตัวเลขที่ตรงกับเป้าหมายจริง
    final targetCal = _parseTarget(calorieController.text);
    final targetProtein = _parseTarget(proteinController.text);
    if (targetCal == null || targetProtein == null) { // ช่องไหนผิด -> เตือนและเลื่อนจอไปหา
      setState(() => submitted = true);
      // เลื่อนหน้าจอไปที่ช่องแรกที่ยังไม่ถูกต้อง
      final firstError = targetCal == null ? _calorieKey : _proteinKey;
      final ctx = firstError.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300), // [UI] ความเร็วเลื่อนจอ 0.3 วินาที
          alignment: 0.3, // [UI] ให้ช่องอยู่ที่ 30% จากบนจอ
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
      await ShoppingSuggestion.loadStaples(); // โหลดรายการของพื้นฐาน

      final fridgeItems = await supabase // ดึงของในตู้ของผู้ใช้
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
      if (fridgeList.isEmpty && fridgeOnly) { // ใช้เฉพาะของในตู้แต่ตู้ว่าง -> error
        throw Exception("ไม่มีวัตถุดิบในตู้เย็น");
      }

      // ===============================
      // หาวัตถุดิบที่อยู่ในตู้เย็นนานแล้ว (เอาไว้ให้ Gemini เลือกใช้ก่อน)
      // อิงรูปแบบเดียวกับ ai_recipe_screen.dart
      // ===============================
      final expiringSoon = <Map<String, dynamic>>[]; // ของที่ควรใช้ก่อน

      for (var item in fridgeItems) { // ไล่ทีละชิ้น
        // เฉพาะของที่เก็บได้อีกไม่เกินจำนวนวันที่ตั้งแจ้งเตือนไว้ (นับเป็นวัน) และ
        // ยังไม่ได้ใช้หมด
        if (!shouldUseFirst(item, readOldItemDays(user))) continue;
        // บุหรี่ / สุราสำหรับดื่ม ไม่ส่งให้ AI
        if (NonFoodCheck.isNotForCooking(item['name'])) continue;

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

      final expiringList = expiringSoon.map((e) => e['name']).join(", "); // ต่อชื่อเป็นข้อความเดียว

      // ===============================
      // คลังเมนูที่เคยสร้างไว้แล้ว (ประหยัด token ไม่ต้องยิง Gemini ใหม่
      // ถ้าเมนูเก่ามีวัตถุดิบพอกับของในตู้เย็นตอนนี้อยู่แล้ว)
      // ===============================
      final myPlans = await supabase // ดึง id แพลนเก่าทั้งหมดของผู้ใช้
          .from('meal_plans')
          .select('id')
          .eq('user_id', user.id);

      final planIds = myPlans.map((p) => p['id']).toList();

      List<dynamic> pastMeals = [];
      if (planIds.isNotEmpty) {
        pastMeals = await supabase // ดึงมื้อจากแพลนเก่า
            .from('weekly_meals')
            .select()
            .inFilter('plan_id', planIds);
      }

      // รวมเป็นคลังเมนู ตัดชื่อซ้ำออก (เก็บล่าสุดของแต่ละชื่อ) และข้ามเมนูที่
      // ข้อมูลไม่ครบ (เช่นของเก่าก่อนมีคอลัมน์ steps จึงยังไม่มีขั้นตอนการทำ)
      final Map<String, Map<String, dynamic>> libraryByName = {}; // คลังเมนูเก่า (ชื่อ -> มื้อ)
      for (final m in pastMeals) { // ไล่ทีละมื้อเก่า
        final name = (m['food_name']?.toString() ?? '').trim();
        final ingredients = m['ingredients'];
        final steps = m['steps']?.toString().trim() ?? '';
        if (name.isEmpty ||
            ingredients is! List ||
            ingredients.isEmpty ||
            steps.isEmpty) {
          continue;
        }
        libraryByName[name] = Map<String, dynamic>.from(m); // เก็บมื้อล่าสุดของชื่อนี้
      }
      final library = libraryByName.values.toList();

      // แยกตัวเลขปริมาณออกจากข้อความ เช่น "1 ชิ้น" -> 1, "1/2 หัว" -> 0.5
      double parseQtyAmount(String qtyText) {
        final fraction = RegExp( // หาเศษส่วน
          r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)',
        ).firstMatch(qtyText);
        if (fraction != null) {
          final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
          final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
          return denominator == 0 ? 0 : numerator / denominator; // กันหารด้วย 0
        }
        final single = RegExp(r'\d+(\.\d+)?').firstMatch(qtyText); // ไม่มีเศษส่วน -> ตัวเลขแรก
        return double.tryParse(single?.group(0) ?? '') ?? 0;
      }

      // เช็คว่าวัตถุดิบทุกอย่างของเมนูนี้ มีพอในตู้เย็นตอนนี้จริงไหม
      bool allIngredientsAvailable(List ingredients) {
        for (final ing in ingredients) { // ไล่ทีละวัตถุดิบ
          final name = (ing['name']?.toString() ?? '').trim().toLowerCase();
          if (name.isEmpty) continue;

          final needAmount = parseQtyAmount(ing['quantity']?.toString() ?? '');
          if (needAmount <= 0) continue; // ไม่รู้จำนวน ข้าม

          final matches = fridgeItems.where((item) { // หาของในตู้ที่ชื่อตรง/คล้าย
            final itemName = (item['name']?.toString() ?? '')
                .trim()
                .toLowerCase();
            return itemName.isNotEmpty &&
                (itemName == name ||
                    itemName.contains(name) ||
                    name.contains(itemName));
          });

          if (matches.isEmpty) return false; // ไม่มีในตู้

          final haveQty = matches // รวมจำนวนทุกลอต
              .map((m) => num.tryParse(m['quantity']?.toString() ?? '') ?? 0)
              .fold<num>(0, (a, b) => a + b);

          if (haveQty < needAmount.ceil()) return false; // ไม่พอ
        }
        return true;
      }

      final expiringNamesLower = expiringSoon // ชื่อของที่ควรใช้ก่อน (ตัวพิมพ์เล็ก)
          .map((e) => (e['name']?.toString() ?? '').trim().toLowerCase())
          .toSet();

      // เมนูนี้ใช้ของที่ควรใช้ก่อนไหม
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
      final targets = PlanTargets( // ตัวคำนวณช่วงเป้า
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
      final matched = library // เมนูเก่าที่ผ่านเงื่อนไข
          .where(
            (m) =>
                fitsMealTarget(m['calories'], m['protein']) && // อยู่ในช่วงเป้าต่อมื้อ
                DietCheck.fits(diet, DietCheck.namesOf(m['ingredients'])) && // ผ่านข้อจำกัดอาหาร
                allIngredientsAvailable(m['ingredients'] as List), // มีวัตถุดิบครบ
          )
          .toList();
      matched.shuffle(); // สุ่มลำดับ (ให้หลากหลาย)
      // คะแนนความเหมาะกับเป้าหมาย (ลดน้ำหนัก: โปรตีนต่อแคลอรีสูง,
      // เพิ่มกล้ามเนื้อ: โปรตีนสูง) ทุกเมนูอยู่ในช่วงเป้าต่อมื้ออยู่แล้ว
      double goalScore(Map m) => PlanGoal.score(
        goal,
        RecipeRepository.toNum(m['calories']),
        RecipeRepository.toNum(m['protein']),
      );
      // ใช้ของที่ควรใช้ก่อนมาก่อน แล้วค่อยเลือกเมนูที่เหมาะกับเป้าหมาย
      matched.sort((a, b) { // เรียง: ใช้ของควรใช้ก่อน -> เหมาะกับเป้าหมาย
        final aExp = usesExpiringIngredient(a['ingredients'] as List) ? 0 : 1;
        final bExp = usesExpiringIngredient(b['ingredients'] as List) ? 0 : 1;
        if (aExp != bExp) return aExp.compareTo(bExp);
        return goalScore(b).compareTo(goalScore(a));
      });

      // ช่องมื้ออาหารทั้งสัปดาห์ (วัน x จำนวนมื้อต่อวัน)
      final weekDaysEn = [ // ชื่อวัน 7 วัน
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ];
      final slotGrid = <Map<String, String>>[]; // ช่องทั้งหมด = 7 วัน x จำนวนมื้อ
      for (final day in weekDaysEn) {
        for (var i = 1; i <= meals; i++) { // สร้างช่อง "มื้อที่ 1, 2, ..."
          slotGrid.add({'day': day, 'meal_type': 'มื้อที่ $i'});
        }
      }

      // ===============================
      // จองของในตู้ให้เมนูที่หยิบมาใช้ซ้ำ "รวมกันทั้งสัปดาห์" (เดิมเช็กทีละเมนู
      // อกไก่ 1 ชิ้นเลยทำให้ทุกเมนูที่ใช้อกไก่ผ่าน) — ใช้วิธีจองเดียวกับหน้าแพลน
      // รายสัปดาห์ (PlanAllocation): มื้อที่ใกล้ถึงก่อนได้ของก่อน
      // ===============================
      final planStart = DateTime.now(); // เวลาเริ่มแพลน
      final usableFridge = List<Map<String, dynamic>>.from( // ของในตู้ที่ยังไม่เกินกำหนด
        fridgeItems,
      ).where((e) => !isOverdue(e)).toList();
      // เมนูที่หยิบมาใช้แล้ว + จำนวนของที่ขาดได้ของแต่ละเมนู
      // (เมนูเก่า = ห้ามขาด, คลังกลาง = ขาดได้ 1 อย่างถ้าซื้อเพิ่มได้)
      final picked = <({Map<String, dynamic> meal, int maxShort})>[]; // เมนูที่หยิบมาแล้ว

      /// เพิ่ม [meal] ได้ไหม โดยทุกเมนูที่หยิบไว้แล้วยังมีของพอเหมือนเดิม
      bool fitsStock(Map<String, dynamic> meal, int maxShort) {
        final trial = [...picked, (meal: meal, maxShort: maxShort)]; // ลองใส่เมนูใหม่เพิ่ม
        final alloc = PlanAllocation.allocate( // จองของให้ทุกเมนู
          meals: [
            for (var k = 0; k < trial.length; k++)
              {...trial[k].meal, 'id': '$k'},
          ],
          fridgeItems: usableFridge,
          planStart: planStart,
        );
        for (var k = 0; k < trial.length; k++) { // เช็คทุกเมนูว่าขาดไม่เกินที่ยอม
          final short = (alloc['$k'] ?? const []).where((st) => !st.have);
          if (short.length > trial[k].maxShort) return false;
        }
        return true;
      }

      final freeSlots = [...slotGrid]; // ช่องที่ยังว่าง

      final reusedMeals = <Map<String, dynamic>>[]; // เมนูเก่าที่ใช้ซ้ำ
      for (final source in matched) { // ไล่ใส่เมนูเก่าลงช่องว่าง
        if (freeSlots.isEmpty) break; // เต็มแล้ว หยุด
        final slot = freeSlots.first; // ช่องว่างแรก
        final meal = <String, dynamic>{ // มื้อในรูปแบบที่จะบันทึก
          'day': slot['day'],
          'meal_type': slot['meal_type'],
          'food_name': source['food_name'],
          'calories': source['calories'],
          'protein': source['protein'],
          'ingredients': source['ingredients'],
          'steps': source['steps'],
          'recipe_id': source['recipe_id'],
        };
        if (!fitsStock(meal, 0)) continue; // ของไม่พอ -> ข้ามเมนูนี้
        picked.add((meal: meal, maxShort: 0)); // หยิบเมนูนี้
        reusedMeals.add(meal);
        freeSlots.removeAt(0); // ช่องนี้ไม่ว่างแล้ว
      }

      // ===============================
      // เติมช่องที่เหลือจากคลังสูตรกลาง (recipes) ก่อนเรียก AI — เมนูที่ทำได้จาก
      // ของในตู้ครบ (ไม่ต้องซื้อเพิ่ม — ของที่ต้องซื้อให้มาจากเมนูที่ Gemini สร้าง
      // ซึ่งมีเกณฑ์ "ซื้อเฉพาะวัตถุดิบทั่วไป" คุมอยู่ แทนการไล่กรองชื่อวัตถุดิบ)
      // มีแคลอรี/โปรตีน ตรงข้อจำกัดอาหาร และแคลอรีใกล้เป้าต่อมื้อ
      // ===============================
      final libraryMeals = <Map<String, dynamic>>[]; // เมนูจากคลังสูตรกลาง
      if (freeSlots.isNotEmpty) { // ยังมีช่องว่าง -> ค้นคลังสูตร
        try {
          final candidates = await RecipeRepository.findRecipesForFridge( // ค้นสูตรที่ทำได้จากของในตู้
            fridgeItems: usableFridge,
            maxMissing: 0, // ห้ามขาดวัตถุดิบ
            limit: 60, // ดูมา 60 สูตร
            requireNutrition: true, // ต้องมีแคลอรี/โปรตีน
            excludeNames: { // ห้ามซ้ำกับเมนูเก่าที่หยิบแล้ว
              for (final m in reusedMeals) (m['food_name'] ?? '').toString(),
            },
            useFirstNames: { // ให้คะแนนสูตรที่ใช้ของควรใช้ก่อน
              for (final e in expiringSoon) (e['name'] ?? '').toString(),
            },
          );
          final suitable = candidates.where((r) { // กรองสูตรที่เหมาะ
            if (diet != 'ไม่มี' && !(r['diet_tags'] as List).contains(diet)) { // ป้ายข้อจำกัดอาหารไม่ตรง -> ตัด
              return false;
            }
            // ตรวจซ้ำจากชื่อวัตถุดิบ กันเมนูที่เคยถูกติดป้ายผิด
            final names = [
              for (final ing in RecipeRepository.ingredientsOf(r)) ing['name'],
            ];
            if (!DietCheck.fits(diet, names)) return false;
            return fitsMealTarget(r['calories'], r['protein']); // ต้องอยู่ในช่วงเป้าต่อมื้อ
          }).toList();
          // คงลำดับเดิม (ซื้อเพิ่มน้อยก่อน -> ใช้ของที่ควรใช้ก่อน) แล้วค่อยเลือก
          // เมนูที่เหมาะกับเป้าหมายก่อนในกลุ่มเดียวกัน
          final libOrder = {
            for (var i = 0; i < suitable.length; i++) suitable[i]: i,
          };
          suitable.sort((a, b) { // เรียง: ขาดน้อย -> ใช้ของควรใช้ก่อน -> เหมาะกับเป้าหมาย -> ลำดับเดิม
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
          for (final r in suitable) { // ไล่ใส่ลงช่องว่าง
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
              'steps': RecipeRepository.stepTextsOf(r), // ขั้นตอน
              'recipe_id': r['recipe_id'],
            };
            const maxShort = 0;
            if (!fitsStock(meal, maxShort)) continue; // ของไม่พอ -> ข้าม
            picked.add((meal: meal, maxShort: maxShort)); // หยิบเมนูนี้
            libraryMeals.add(meal);
            freeSlots.removeAt(0);
            logAiRequest( // บันทึกว่าใช้คลัง (ไม่เปลือง AI)
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
      final remainingSlots = freeSlots; // ช่องที่ยังต้องให้ AI ทำ

      // ของที่เหลือในตู้หลังจองให้เมนูข้างบนแล้ว — บอก Gemini เฉพาะส่วนนี้
      // ไม่งั้น AI จะเอาของที่ถูกจองไปแล้วมาใช้ซ้ำ
      final fridgeListForAi = picked.isEmpty // ไม่ได้หยิบอะไรเลย -> ใช้รายการเต็ม
          ? fridgeList
          : inventoryPromptList(
              PlanAllocation.leftoverStock( // ของที่เหลือหลังจองให้เมนูที่หยิบแล้ว
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

      final plan = await supabase // สร้างแถวแพลนใหม่ในฐานข้อมูล
          .from('meal_plans')
          .insert({
            'user_id': user.id, // เจ้าของแพลน

            'goal': goal, // เป้าหมาย

            'meals_per_day': meals, // จำนวนมื้อต่อวัน

            'target_calories': targetCal, // เป้าแคลอรี

            'target_protein': targetProtein, // เป้าโปรตีน

            'diet_type': diet, // ข้อจำกัดอาหาร
          })
          .select() // ขอข้อมูลแถวที่สร้างกลับมา
          .single();

      final planId = plan['id']; // id ของแพลนใหม่

      // ===============================
      // Gemini — เรียกเฉพาะตอนที่เมนูเก่าในคลังไม่พอเติมเต็มสัปดาห์เท่านั้น
      // ถ้า remainingSlots ว่าง (เมนูเก่าครบพอแล้ว) จะข้ามส่วนนี้ไปเลย
      // เพื่อประหยัด token/การเรียกใช้ API
      // ===============================

      List<dynamic> geminiMeals = []; // เมนูที่ AI สร้าง

      final usedNames = [...reusedMeals, ...libraryMeals] // ชื่อเมนูที่ใช้ไปแล้ว (ห้าม AI ซ้ำ)
          .map((m) => m['food_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(", ");

      String r(num v) => v.round().toString(); // ตัวช่วยปัดเป็นจำนวนเต็ม

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
        'kcal': '${r(calMin)}-${calMax.floor()}', // ช่วงแคลอรี "ต่ำสุด-สูงสุด"
        'protein': '${r(proteinMin)}-${proteinMax.floor()}', // ช่วงโปรตีน
      };

      // ให้ Gemini สร้างเมนูสำหรับช่องที่กำหนด (แต่ละช่องมีช่วง kcal/protein ของตัวเอง)
      // [extraRule] ใช้ตอนขอแก้วันที่ยอดรวมไม่ตรงเป้า
      Future<List<dynamic>> askGemini(
        List<Map<String, dynamic>> slots, {
        String extraRule = '',
      }) async {
        final slotsJson = slots // แปลงช่องเป็นข้อความ JSON สำหรับ prompt
            .map(
              (s) =>
                  '{"day":"${s['day']}","meal_type":"${s['meal_type']}",'
                  '"kcal":"${s['kcal']}","protein":"${s['protein']}"}',
            )
            .join(",\n");

        final prompt = // คำสั่งที่ส่งให้ AI (ข้อความในเครื่องหมาย """ คือสิ่งที่ AI อ่าน ไม่ใช่คอมเมนต์)
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



สร้างเมนูเฉพาะสำหรับช่องต่อไปนี้เท่านั้น ${fridgeOnly ? "ไม่เกิน" : "จำนวน"} ${slots.length} มื้อ
(ระบุ day และ meal_type ให้ตรงกับที่กำหนดมาเป๊ะๆ ${fridgeOnly ? "ห้ามเพิ่มช่อง ถ้าวัตถุดิบไม่พอทำครบทุกช่อง ให้ทำเท่าที่ทำได้จริงเรียงจากช่องแรก แล้วข้ามช่องที่เหลือไปเลย" : "ห้ามเพิ่มหรือลดจำนวน"}
แต่ละช่องมี "kcal" และ "protein" เป็นช่วงที่มื้อนั้นต้องอยู่ ห้ามต่ำกว่าหรือเกินช่วง):

[
$slotsJson
]

${usedNames.isEmpty ? "" : "ห้ามสร้างเมนูซ้ำกับเมนูต่อไปนี้ที่ใช้ไปแล้วในสัปดาห์นี้: $usedNames"}



กฎ:

${fridgeOnly ? '''- ห้ามสร้างวัตถุดิบที่ไม่มีในรายการ''' : '''- ใช้วัตถุดิบในตู้เย็นก่อนเสมอ (โดยเฉพาะของที่อยู่มานาน) แล้วค่อยซื้อเพิ่ม
- ซื้อเพิ่มได้เฉพาะเท่าที่จำเป็น เพื่อให้เมนูทำได้จริงและใกล้เป้า ราคาไม่แพง
- ซื้อเพิ่มได้เฉพาะวัตถุดิบทั่วไปที่หาซื้อได้ในซูเปอร์มาร์เก็ตหรือตลาดสดทั่วไปและคนส่วนใหญ่รับประทาน ห้ามแนะนำให้ซื้อวัตถุดิบที่รับประทานเฉพาะกลุ่มหรือเฉพาะถิ่น (เช่น แมลง งู กบ หอยทาก สัตว์ป่า)
  เข้ากับข้อจำกัดอาหาร และใช้ของที่ซื้อซ้ำในหลายมื้อได้ (จะได้ไม่ต้องซื้อหลายอย่าง)
- วัตถุดิบที่ไม่มีในตู้เย็น ให้ใส่ "to_buy": true ใน ingredients ของมื้อนั้น'''}
- ถ้ารายการวัตถุดิบมีของที่ไม่ใช่อาหารหรือไม่ปลอดภัยต่อการบริโภค (เช่น ยา สารเคมี น้ำยาทำความสะอาด ของใช้) ห้ามนำมาใช้ในเมนูเด็ดขาด
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
${fridgeOnly ? '''- ถ้าของในตู้ไม่พอถึงช่วง ให้ใช้ปริมาณมากขึ้นเท่าที่มีจริง (ไม่เกินจำนวนที่มี)
- รวมทุกมื้อที่สร้างแล้ว ห้ามใช้วัตถุดิบแต่ละอย่างเกินจำนวนที่มี (ไม่ต้องครบทุกวัน ได้กี่มื้อก็เท่านั้น)''' : '''- ถ้าของในตู้ไม่พอถึงช่วง ให้ซื้อเพิ่ม (โดยเฉพาะแหล่งโปรตีน เช่น อกไก่ ไข่ไก่ เต้าหู้ ปลา)
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
        final result = await generateGemini( // ส่ง prompt ให้ Gemini
          apiKey: apiKey,
          logEvent: AiEvent.mealPlan, // บันทึกประวัติการใช้ AI
          content: [Content.text(prompt)],
          timeout: const Duration(seconds: 90), // รอนานสุด 90 วินาที (แพลนทั้งสัปดาห์ใช้เวลานาน)
        );

        String json = result.text! // ล้างเครื่องหมาย ``` ออก
            .replaceAll("```json", "")
            .replaceAll("```", "")
            .trim();

        return jsonDecode(json) as List<dynamic>; // แปลงเป็นลิสต์มื้อ
      }

      if (remainingSlots.isNotEmpty) { // มีช่องที่ AI ต้องทำ
        // ช่วงต่อมื้อของช่องที่ให้ AI ทำ: วันที่มีเมนูจากคลังอยู่แล้วบางมื้อ แบ่งงบที่เหลือ
        // ของวันนั้นให้มื้อที่เหลือ (มื้อจากคลังอยู่ในช่วงต่อมื้ออยู่แล้ว)
        final fixedMeals = [...reusedMeals, ...libraryMeals]; // มื้อที่ล็อกไว้แล้ว (เมนูเก่า + คลังสูตร)
        List<Map<String, dynamic>> budgetFor( // คำนวณช่วงแคลอรี/โปรตีนของแต่ละช่องที่เหลือ
          List<Map> slots,
          List<Map> keptMeals,
        ) {
          final out = <Map<String, dynamic>>[];
          final byDay = <String, List<Map>>{}; // จัดกลุ่มช่องตามวัน
          for (final s in slots) {
            byDay.putIfAbsent(s['day'].toString(), () => []).add(s);
          }
          byDay.forEach((day, daySlots) {
            final kept = keptMeals.where((m) => m['day'] == day); // มื้อที่ล็อกไว้ของวันนั้น
            final b = targets.slotBudget( // งบที่เหลือของวัน ÷ จำนวนช่อง
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

        geminiMeals = await askGemini(budgetFor(remainingSlots, fixedMeals)); // ให้ AI สร้างเมนูให้ทุกช่องที่เหลือ

        // ตรวจยอดรวมรายวัน: วันที่หลุดช่วง (เกินเป้า หรือขาดเกิน 100 kcal / 10 g)
        // ให้ AI ทำมื้อของวันนั้นใหม่ด้วยงบที่เหลือจริง สูงสุด 2 รอบ ใช้ผลที่ใกล้ช่วงกว่า
        // ยังไม่ผ่านอีก หน้าแพลนจะขึ้น "เกิน"/"ขาด" ให้เห็น
        ({num cal, num protein}) dayTotal(String day) { // ยอดรวมแคลอรี/โปรตีนของวัน
          num cal = 0, pro = 0;
          for (final m in [...fixedMeals, ...geminiMeals.whereType<Map>()]) {
            if (m['day'] != day) continue;
            cal += RecipeRepository.toNum(m['calories']);
            pro += RecipeRepository.toNum(m['protein']);
          }
          return (cal: cal, protein: pro);
        }

        for (var round = 0; round < 2; round++) { // ลองแก้ได้ 2 รอบ
          final badDays = // วันที่ยอดรวมไม่อยู่ในช่วงเป้า
              {
                for (final m in geminiMeals.whereType<Map>())
                  m['day'].toString(),
              }.where((d) {
                final t = dayTotal(d);
                return !targets.dayFits(t.cal, t.protein);
              }).toList();
          if (badDays.isEmpty) break; // ผ่านหมด หยุด

          final redo = [ // มื้อของวันที่ต้องแก้
            for (final m in geminiMeals.whereType<Map>())
              if (badDays.contains(m['day'].toString())) m,
          ];
          try {
            final fixed = await askGemini( // ให้ AI ทำมื้อของวันนั้นใหม่
              budgetFor(redo, fixedMeals),
              extraRule:
                  '- รอบนี้แก้วันที่ยอดรวมไม่ตรงเป้า (เดิม: ${badDays.map((d) {
                    final t = dayTotal(d);
                    return '$d ${r(t.cal)} kcal โปรตีน ${r(t.protein)} g';
                  }).join(', ')}) ทำทุกมื้อให้อยู่ในช่วง kcal/protein ของช่องให้ได้',
            );
            for (final day in badDays) { // ไล่ทีละวันที่แก้
              final before = dayTotal(day); // ยอดรวมก่อนแก้
              final newMeals = fixed
                  .whereType<Map>()
                  .where((f) => f['day'] == day)
                  .toList();
              final oldMeals = [
                for (final m in geminiMeals.whereType<Map>())
                  if (m['day'] == day) m,
              ];
              if (newMeals.length != oldMeals.length) continue; // จำนวนมื้อไม่เท่าเดิม -> ไม่ใช้
              geminiMeals.removeWhere((m) => m is Map && m['day'] == day); // เอาของเดิมออก
              geminiMeals.addAll(newMeals); // ใส่ของใหม่
              final after = dayTotal(day); // ยอดรวมหลังแก้
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
        List<String> dietViolations(Map m) => // วัตถุดิบที่ผิดข้อจำกัดของมื้อ
            DietCheck.violations(diet, DietCheck.namesOf(m['ingredients']));
        final wrongDiet = [ // มื้อที่ผิดข้อจำกัด
          for (final m in geminiMeals.whereType<Map>())
            if (dietViolations(m).isNotEmpty) m,
        ];
        if (wrongDiet.isNotEmpty) { // มี -> ให้ AI ทำใหม่ 1 รอบ
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
            for (final f in fixed.whereType<Map>()) { // ไล่มื้อที่ AI แก้มา
              if (dietViolations(f).isNotEmpty) continue; // ยังผิดอยู่ ไม่ใช้
              final k = geminiMeals.indexWhere( // หาตำแหน่งมื้อเดิม
                (m) =>
                    m is Map &&
                    m['day'] == f['day'] &&
                    m['meal_type'] == f['meal_type'] &&
                    wrongDiet.contains(m),
              );
              if (k >= 0) geminiMeals[k] = f; // แทนที่
            }
          } catch (e) {
            debugPrint('แก้เมนูที่ผิดข้อจำกัดอาหารไม่สำเร็จ (ใช้ผลเดิม): $e');
          }
        }

        // เก็บเมนูใหม่จาก AI ลงคลังสูตรกลาง ครั้งหน้า (ของผู้ใช้คนไหนก็ได้) จะได้
        // หยิบจากคลังแทนการเรียก AI
        for (final m in geminiMeals.whereType<Map>()) { // บันทึกเมนูจาก AI ลงคลังกลางทีละเมนู
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
            dietTags: [if (diet != 'ไม่มี' && dietViolations(m).isEmpty) diet],
          );
          if (id != null) m['recipe_id'] = id; // ได้ id ก็จำไว้ในมื้อ
        }
      }

      // รวมเมนูที่หยิบจากคลังเก่า (ประหยัด token) กับเมนูใหม่จาก Gemini
      // (ถ้ามี) เข้าด้วยกันเป็นแผนอาหารสัปดาห์เดียว
      List mealsData = [...reusedMeals, ...libraryMeals, ...geminiMeals]; // รวมมื้อทั้งหมด

      // โหมดใช้เฉพาะของในตู้: ไม่มีรายการซื้อของ — เก็บเฉพาะมื้อที่ของในตู้พอจริง
      // (ไล่จากมื้อแรกของสัปดาห์ จองของแบบเดียวกับหน้าแผนรายสัปดาห์) มื้อที่ของ
      // ไม่พอหรือใช้ของที่ไม่มีในตู้ ตัดทิ้ง แพลนจึงอาจไม่ครบสัปดาห์ (ได้แค่ไหนแค่นั้น)
      if (fridgeOnly) { // โหมดใช้เฉพาะของในตู้ -> คัดเฉพาะมื้อที่ของพอจริง
        int slotIndex(Map m) => slotGrid.indexWhere( // ลำดับช่องของมื้อ
          (s) => s['day'] == m['day'] && s['meal_type'] == m['meal_type'],
        );
        final ordered = mealsData.whereType<Map>().toList() // เรียงตามลำดับช่อง (วันแรก มื้อแรกก่อน)
          ..sort((a, b) => slotIndex(a).compareTo(slotIndex(b)));
        final kept = <Map>[]; // มื้อที่เก็บไว้
        for (final m in ordered) { // ไล่ทีละมื้อ
          final trial = [...kept, m];
          final alloc = PlanAllocation.allocate( // จองของให้มื้อที่เก็บไว้ + มื้อนี้
            meals: [
              for (var k = 0; k < trial.length; k++)
                {...Map<String, dynamic>.from(trial[k]), 'id': '$k'},
            ],
            fridgeItems: usableFridge,
            planStart: planStart,
          );
          final allHave = alloc.values.every( // ทุกมื้อมีของครบไหม
            (list) => list.every((s) => s.have),
          );
          if (allHave) kept.add(m); // ครบ -> เก็บมื้อนี้
        }
        mealsData = kept; // ใช้เฉพาะมื้อที่เก็บไว้
        if (mealsData.isEmpty) { // ไม่ได้สักมื้อ
          await supabase.from('meal_plans').delete().eq('id', planId); // ลบแพลนที่สร้างไว้ทิ้ง
          throw Exception(
            "วัตถุดิบในตู้เย็นไม่พอทำได้แม้แต่ 1 มื้อ ลองปิด \"ใช้เฉพาะของในตู้เย็น\"",
          );
        }
      }

      // ===============================
      // บันทึก weekly_meals
      // ===============================

      // ชื่อวัตถุดิบที่มีจริงในตู้เย็น (normalize ไว้เทียบแบบไม่สนตัวพิมพ์/ช่องว่าง)
      final fridgeNames = fridgeItems // ชื่อของในตู้ (ตัวพิมพ์เล็ก)
          .map((item) => (item['name']?.toString() ?? '').trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .toList();

      // ของชื่อนี้มีในตู้ไหม (ชื่อหนึ่งอยู่ในอีกชื่อ)
      bool inFridge(String ingredientName) {
        final normalized = ingredientName.trim().toLowerCase();
        if (normalized.isEmpty) return false;
        return fridgeNames.any(
          (n) => n.contains(normalized) || normalized.contains(n),
        );
      }

      // มื้อที่แปลงหน่วยวัตถุดิบ -> คำนวณแคลอรีใหม่หลังบันทึก (พร้อมกันทุกมื้อ)
      final recalcJobs = <Future<void>>[]; // งานคำนวณแคลอรีใหม่ (ทำพร้อมกันตอนท้าย)

      for (var meal in mealsData) { // บันทึกทีละมื้อ
        // วัตถุดิบของมื้อนี้ (มาจาก Gemini โดยอิงของจริงในตู้เย็นเท่านั้น)
        // checked สะท้อนของจริงในตู้เย็น ณ ตอนสร้างแผน ไม่ใช่ค่าคงที่
        final ingredientsList = (meal['ingredients'] as List? ?? []).map((ing) { // แปลงวัตถุดิบเป็นรูปแบบที่บันทึก
          final name = ing['name']?.toString() ?? '';
          // ของพื้นฐาน (ข้าว เครื่องปรุง ฯลฯ) ถือว่ามีในบ้าน ไม่ต้องซื้อ
          final have = inFridge(name) || ShoppingSuggestion.isStaple(name); // มีในตู้หรือเป็นของพื้นฐาน
          return {
            'name': name,
            // หน่วยให้ตรงกับของในตู้ (เช่น ผู้ใช้แบ่งเป็นส่วนไว้ แต่ AI บอก "ลูก")
            'quantity': PlanAllocation.quantityInFridgeUnit(
              name,
              ing['quantity']?.toString() ?? '',
              usableFridge,
            ),
            'checked': have, // ติ๊กไว้ถ้ามี
            // ไม่มีในตู้เย็น -> ต้องซื้อ (รวมเป็นรายการซื้อของในแผนรายสัปดาห์)
            // โหมดใช้เฉพาะของในตู้ไม่มีรายการซื้อ (แค่ไม่ติ๊ก)
            if (!have && !fridgeOnly) ShoppingSuggestion.toBuyKey: true,
          };
        }).toList();
        // ปริมาณก่อนแปลงหน่วย (แคลอรีของมื้อคิดจากค่านี้)
        final before = [ // ข้อความวัตถุดิบก่อนแปลงหน่วย
          for (final ing in (meal['ingredients'] as List? ?? []))
            '${ing['name'] ?? ''} ${ing['quantity'] ?? ''}'.trim(),
        ];
        final unitChanged = [ // มีวัตถุดิบไหนถูกแปลงหน่วยไหม
          for (var k = 0; k < ingredientsList.length; k++)
            if ('${ingredientsList[k]['name']} ${ingredientsList[k]['quantity']}'
                    .trim() !=
                before[k])
              k,
        ].isNotEmpty;

        // ขั้นตอนการทำอาหารจาก Gemini (อาจส่งมาเป็น array หรือ string ก็ได้)
        final stepsRaw = meal['steps'];
        String stepsText;
        if (stepsRaw is List) { // ลิสต์ -> ใส่เลขข้อทีละบรรทัด
          stepsText = stepsRaw
              .asMap()
              .entries
              .map((e) => "${e.key + 1}. ${e.value}")
              .join("\n");
        } else { // ข้อความอยู่แล้ว
          stepsText = stepsRaw?.toString() ?? '';
        }

        final inserted = await supabase // บันทึกมื้อลงฐานข้อมูล
            .from('weekly_meals')
            .insert({
              'plan_id': planId, // แพลนที่มื้อนี้อยู่

              'day': meal['day'], // วัน

              'meal_type': meal['meal_type'], // มื้อที่

              'food_name': meal['food_name'], // ชื่อเมนู

              'calories': meal['calories'], // แคลอรี

              'protein': meal['protein'], // โปรตีน

              'ingredients': ingredientsList, // วัตถุดิบ

              'steps': stepsText, // ขั้นตอน

              'is_cooked': false, // ยังไม่ได้ทำ

              // สูตรในคลังกลางที่มื้อนี้มาจาก (ถ้ามี)
              if (meal['recipe_id'] != null) 'recipe_id': meal['recipe_id'],
            })
            .select() // ขอแถวที่บันทึกกลับมา
            .single();
        if (unitChanged) { // ถูกแปลงหน่วย -> คำนวณแคลอรีใหม่
          recalcJobs.add(
            MealNutrition.recalculateAfterUnitChange(
              Map<String, dynamic>.from(inserted),
              before,
            ).then((_) {}),
          );
        }
      }
      // ไม่สำเร็จบางมื้อ: มื้อนั้นมีธงเตือนให้กด "คำนวณใหม่" เอง
      await Future.wait(recalcJobs); // รอคำนวณใหม่ให้ครบทุกมื้อ
      if (!mounted) return; // หน้านี้ถูกปิดไปแล้ว ไม่ต้องแสดงข้อความ

      Navigator.push( // ไปหน้าแผนรายสัปดาห์
        context,

        MaterialPageRoute(builder: (_) => WeeklyPlanScreen(planId: planId)),
      );
    } catch (e) {
      if (!mounted) return; // หน้านี้ถูกปิดไปแล้ว ไม่ต้องแสดงข้อความ
      ScaffoldMessenger.of(context).showSnackBar( // แสดง error
        SnackBar(
          content: Text(geminiErrorMessage(e, fallback: "สร้างแผนไม่สำเร็จ")),
        ),
      );
    } finally {
      if (mounted) { // หยุดโหลด (ถ้าหน้ายังเปิดอยู่)
        setState(() { // หยุดโหลด
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง

      body: SafeArea(
        child: SingleChildScrollView( // เลื่อนได้
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              _buildHeader(context), // หัวหน้า

              const SizedBox(height: 20), // [UI] ระยะห่างระหว่างส่วน

              buildTitle(Icons.track_changes, "เป้าหมาย"), // หัวข้อ "เป้าหมาย"

              buildChoiceCard( // การ์ดเป้าหมาย: ลดน้ำหนัก
                "ลดน้ำหนัก",

                "ควบคุม Calories", // [UI] คำอธิบายใต้ตัวเลือก

                goal == "ลดน้ำหนัก", // เลือกอยู่ไหม

                () {
                  setState(() {
                    goal = "ลดน้ำหนัก";
                  });
                },
              ),

              buildChoiceCard( // การ์ดเป้าหมาย: รักษาน้ำหนัก
                "รักษาน้ำหนัก",

                "Balance สุขภาพ",

                goal == "รักษาน้ำหนัก",

                () {
                  setState(() {
                    goal = "รักษาน้ำหนัก";
                  });
                },
              ),

              buildChoiceCard( // การ์ดเป้าหมาย: เพิ่มกล้ามเนื้อ
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

              buildTitle(Icons.brunch_dining, "จำนวนมื้อต่อวัน"), // หัวข้อ "จำนวนมื้อต่อวัน"

              _buildMealCounter(), // ตัวปรับจำนวนมื้อ

              const SizedBox(height: 20),

              buildTitle(Icons.local_fire_department, "เป้าหมายโภชนาการ"), // หัวข้อ "เป้าหมายโภชนาการ"

              buildInput( // ช่องแคลอรีต่อวัน
                "Calories ต่อวัน",
                calorieController,
                "kcal", // [UI] หน่วยต่อท้าย
                key: _calorieKey,
                error: _targetError(calorieController.text, _calorieExample), // ข้อความเตือน (ถ้ามี)
                // อัปเดตข้อความเตือนทันทีที่พิมพ์
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 15), // [UI] ระยะห่างระหว่างช่อง

              buildInput( // ช่องโปรตีนต่อวัน
                "Protein ต่อวัน",
                proteinController,
                "g",
                key: _proteinKey,
                error: _targetError(proteinController.text, _proteinExample),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 20),

              buildTitle(Icons.block, "ข้อจำกัดอาหาร"), // หัวข้อ "ข้อจำกัดอาหาร"

              _buildDietDropdown(), // ดรอปดาวน์ข้อจำกัดอาหาร

              const SizedBox(height: 20),

              _buildFridgeOnlySwitch(), // สวิตช์ "ใช้เฉพาะของในตู้เย็น"

              const SizedBox(height: 25), // [UI] ระยะก่อนปุ่ม

              _buildCreateButton(), // ปุ่มสร้างแผน
            ],
          ),
        ),
      ),

      bottomNavigationBar: const AppBottomNav(current: AppTab.plan), // แถบเมนูล่าง ไฮไลต์ "แพลน"
    );
  }

  // กล่องสวิตช์ "ใช้เฉพาะของในตู้เย็น"
  Widget _buildFridgeOnlySwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // [UI] ระยะในกล่อง
      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นขาว
        borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero, // [UI] ไม่มีระยะขอบใน
        value: fridgeOnly,
        onChanged: (v) => setState(() => fridgeOnly = v), // สลับเปิด/ปิด
        title: const Text(
          "ใช้เฉพาะของในตู้เย็น",
          style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
        ),
        subtitle: Text(
          fridgeOnly // คำอธิบายเปลี่ยนตามสถานะสวิตช์
              ? "ไม่ต้องออกไปซื้อ แต่บางวันอาจไม่ถึงเป้า"
              : "ใช้ของในตู้ก่อน ซื้อเพิ่มเท่าที่จำเป็น (มีรายการซื้อของให้)",
          style: const TextStyle(fontSize: 13), // [UI] ขนาด 13
        ),
      ),
    );
  }

  // หัวหน้า: ปุ่มย้อนกลับ + แคปซูลชื่อหน้า
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.pop(context);
          },
          child: Container(
            height: 45, // [UI] ขนาดปุ่ม 45x45
            width: 45,
            decoration: BoxDecoration(
              color: const Color(0xfffff7d0), // [UI] สีครีม
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: BackIcon(size: 20)), // [UI] ไอคอนย้อนกลับ
          ),
        ),
        const SizedBox(width: 12), // [UI] ระยะปุ่มกับแคปซูล
        Expanded(
          child: Container(
            height: 50, // [UI] ความสูงแคปซูล
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7D0), // [UI] สีครีม
              borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
            ),
            child: const Row(
              children: [
                CalendarIcon(size: 22), // [UI] ไอคอนปฏิทิน
                SizedBox(width: 10),
                Text(
                  "สร้างแพลนอาหาร",
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16, // [UI] ขนาดชื่อหน้า
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

  // ตัวปรับจำนวนมื้อ [−] N มื้อ [+]
  Widget _buildMealCounter() {
    return Container(
      padding: const EdgeInsets.all(15), // [UI] ระยะในกล่อง

      decoration: boxDecoration(), // [UI] กล่องขาวมุมโค้ง

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // [UI] ปุ่มชิดซ้าย/ขวา ตัวเลขอยู่กลาง

        children: [
          IconButton(
            icon: const Icon(Icons.remove), // [UI] ไอคอนลบ

            onPressed: () {
              if (meals > 1) { // ไม่ต่ำกว่า 1 มื้อ
                setState(() {
                  meals--;
                });
              }
            },
          ),

          Text(
            "$meals มื้อ",

            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), // [UI] ขนาดตัวเลข 20
          ),

          IconButton(
            icon: const Icon(Icons.add), // [UI] ไอคอนบวก

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

  // ดรอปดาวน์เลือกข้อจำกัดอาหาร
  Widget _buildDietDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15), // [UI] ระยะในซ้ายขวา

      decoration: boxDecoration(), // [UI] กล่องขาวมุมโค้ง

      child: DropdownButtonHideUnderline( // ซ่อนเส้นใต้ดรอปดาวน์
        child: DropdownButton<String>(
          value: diet, // ค่าที่เลือกอยู่

          isExpanded: true, // [UI] กว้างเต็มกล่อง

          items: [ // [UI] ตัวเลือก (ต้องตรงกับ DietCheck)
            "ไม่มี",

            "มังสวิรัติ",

            "เจ",

            "ไม่ทานนม",
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),

          onChanged: (value) { // เลือกค่าใหม่
            setState(() {
              diet = value!;
            });
          },
        ),
      ),
    );
  }

  // ปุ่มใหญ่ "สร้างแผนอาหาร"
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity, // [UI] กว้างเต็ม

      height: 55, // [UI] ความสูงปุ่ม

      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFF7D0), // [UI] สีปุ่ม (ครีม)

          foregroundColor: Colors.black87, // [UI] สีตัวอักษร

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
          ),
        ),

        onPressed: loading ? null : createMealPlan, // กำลังสร้าง = กดไม่ได้

        child: loading
            ? const CircularProgressIndicator() // วงหมุนตอนสร้าง
            : const Text(
                "สร้างแผนอาหาร",

                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), // [UI] ขนาดตัวอักษร
              ),
      ),
    );
  }

  // หัวข้อของแต่ละส่วน (ไอคอน + ข้อความ)
  Widget buildTitle(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้หัวข้อ
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black87), // [UI] ไอคอนขนาด 20
          const SizedBox(width: 8), // [UI] ระยะไอคอนกับข้อความ
          Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // [UI] ขนาดหัวข้อ 18
          ),
        ],
      ),
    );
  }

  // การ์ดตัวเลือกเป้าหมาย (กดเลือกได้ทีละอัน)
  Widget buildChoiceCard(
    String title, // หัวข้อ

    String sub, // คำอธิบาย

    bool selected, // เลือกอยู่ไหม

    VoidCallback tap, // กดแล้วทำอะไร
  ) {
    return GestureDetector(
      onTap: tap,

      child: Container(
        margin: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้การ์ด

        padding: const EdgeInsets.all(15), // [UI] ระยะในการ์ด

        decoration: BoxDecoration(
          color: selected ? const Color(0xfffff7d0) : Colors.white, // [UI] เลือกอยู่ = ครีม, ไม่เลือก = ขาว

          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
        ),

        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off, // [UI] ปุ่มกลม: เลือก = ทึบ, ไม่เลือก = โปร่ง
            ),

            const SizedBox(width: 15), // [UI] ระยะปุ่มกลมกับข้อความ

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    fontSize: 16, // [UI] ขนาดหัวข้อ

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
    String label, // ป้ายในช่อง

    TextEditingController controller, // ตัวเก็บข้อความ

    String suffix, { // หน่วยต่อท้าย
    Key? key, // กุญแจ (ไว้เลื่อนจอไปหา)
    String? error, // ข้อความเตือน
    ValueChanged<String>? onChanged, // พิมพ์แล้วทำอะไร
  }) {
    final showError = error != null; // มีข้อความเตือนไหม
    const errorColor = Color(0xffD93025); // [UI] สีแดงของข้อความเตือน
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: boxDecoration().copyWith(
            border: Border.all(
              color: showError ? errorColor : Colors.white, // [UI] มี error = ขอบแดง, ไม่มี = ขอบขาว (มองไม่เห็น)
              width: 1.5, // [UI] ความหนาขอบ
            ),
          ),

          child: TextField(
            controller: controller,

            onChanged: onChanged,

            keyboardType: TextInputType.number, // [UI] แป้นตัวเลข

            decoration: InputDecoration(
              labelText: label,

              labelStyle: showError ? const TextStyle(color: errorColor) : null, // [UI] มี error = ป้ายสีแดง

              suffixText: suffix,

              border: InputBorder.none, // [UI] ไม่มีเส้นขอบของช่องเอง

              contentPadding: const EdgeInsets.all(15), // [UI] ระยะใน
            ),
          ),
        ),
        if (error != null) // มี error ถึงแสดงข้อความเตือน
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6), // [UI] ระยะซ้าย 12 บน 6
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.error_outline, size: 16, color: errorColor), // [UI] ไอคอนเตือน ขนาด 16
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(fontSize: 13, color: errorColor), // [UI] ขนาด 13 สีแดง
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // การตกแต่งกล่องขาวมุมโค้ง (ใช้ซ้ำหลายจุดในหน้านี้)
  BoxDecoration boxDecoration() {
    return BoxDecoration(
      color: Colors.white, // [UI] พื้นขาว

      borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
    );
  }
}
