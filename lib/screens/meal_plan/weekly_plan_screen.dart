import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/screens/meal_plan/cook_meal_screen.dart';
import 'package:test_app/screens/meal_plan/my_plan_screen.dart';
import 'package:test_app/services/plan_targets.dart';
import 'package:test_app/services/meal_nutrition.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/services/meal_regenerate.dart';
import 'package:test_app/services/plan_allocation.dart';
import 'package:test_app/services/diet_check.dart';

class WeeklyPlanScreen extends StatefulWidget {
  final String planId;

  const WeeklyPlanScreen({super.key, required this.planId});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final supabase = Supabase.instance.client;

  List<dynamic> meals = [];

  /// recipe_id -> สูตรนี้ AI สร้างตอนทำแพลนนี้ (true) หรือมาจากคลังสูตรเดิม (false)
  /// ดูจากเวลาที่สูตรถูกเพิ่มเข้าคลังกลาง เทียบกับเวลาสร้างแพลน
  Map<String, bool> _aiMade = {};
  bool loading = true;
  bool saved = false;

  DateTime? createdDate;

  // เป้าต่อวันของแพลน (ใช้เทียบยอดรวมแต่ละวัน)
  num targetCalories = 0;
  num targetProtein = 0;
  String? goal;
  String? dietType;

  /// ของในตู้เย็นตอนนี้ ใช้เช็กว่าของ "ต้องซื้อ" ของมื้อเสริมซื้อมาแล้วหรือยัง
  List<Map<String, dynamic>> fridgeItems = [];

  @override
  void initState() {
    super.initState();
    loadMeals();
  }

  Future<void> loadMeals() async {
    try {
      final response = await supabase
          .from('weekly_meals')
          .select()
          .eq('plan_id', widget.planId);

      await ShoppingSuggestion.loadStaples();
      final user = supabase.auth.currentUser;
      final fridge = user == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await supabase
                  .from('fridge_items')
                  .select()
                  .eq('user_id', user.id),
            );

      final plan = await supabase
          .from('meal_plans')
          .select(
            'saved, created_at, target_calories, target_protein, goal, diet_type',
          )
          .eq('id', widget.planId)
          .single();

      // ที่มาของสูตร (ไม่สำเร็จก็ไม่เป็นไร แค่ไม่แสดงป้าย)
      final recipeIds = {
        for (final m in response)
          if (m['recipe_id'] != null) m['recipe_id'].toString(),
      };
      final planCreated = DateTime.tryParse('${plan['created_at'] ?? ''}');
      final aiMade = <String, bool>{};
      if (recipeIds.isNotEmpty) {
        try {
          final rows = await supabase
              .from('recipes')
              .select('id, created_at')
              .inFilter('id', recipeIds.toList());
          for (final r in rows) {
            final created = DateTime.tryParse('${r['created_at'] ?? ''}');
            if (created == null || planCreated == null) continue;
            aiMade[r['id'].toString()] = !created.isBefore(planCreated);
          }
        } catch (e) {
          debugPrint('โหลดที่มาของสูตรไม่สำเร็จ: $e');
        }
      }

      setState(() {
        meals = response;
        _aiMade = aiMade;
        fridgeItems = fridge;
        saved = plan['saved'] ?? false;
        targetCalories = num.tryParse('${plan['target_calories']}') ?? 0;
        targetProtein = num.tryParse('${plan['target_protein']}') ?? 0;
        goal = plan['goal']?.toString();
        dietType = plan['diet_type']?.toString();

        // แปลงเวลา UTC เป็นเวลาไทย
        // created_at อาจเป็น null (แผนเก่าที่บันทึกโดยไม่ได้ใส่เวลา)
        createdDate = DateTime.tryParse(
          plan['created_at']?.toString() ?? '',
        )?.toLocal();

        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> savePlan() async {
    await supabase
        .from('meal_plans')
        .update({'saved': true})
        .eq('id', widget.planId);

    setState(() {
      saved = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("บันทึกแผนอาหารเรียบร้อย")));

    // บันทึกเสร็จแล้วพาไปหน้าแผนที่บันทึกไว้เลย
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MyPlanScreen()),
    );
  }

  List<Map<String, String>> generateWeekDays() {
    final days = [
      {"en": "Monday", "th": "วันจันทร์"},
      {"en": "Tuesday", "th": "วันอังคาร"},
      {"en": "Wednesday", "th": "วันพุธ"},
      {"en": "Thursday", "th": "วันพฤหัสบดี"},
      {"en": "Friday", "th": "วันศุกร์"},
      {"en": "Saturday", "th": "วันเสาร์"},
      {"en": "Sunday", "th": "วันอาทิตย์"},
    ];

    if (createdDate == null) {
      return days;
    }

    // weekday ของ Dart: Monday = 1, Sunday = 7
    int startIndex = createdDate!.weekday - 1;

    return List.generate(7, (index) {
      return days[(startIndex + index) % 7];
    });
  }

  Map<String, List<dynamic>> groupByDay() {
    Map<String, List<dynamic>> result = {};

    for (var item in meals) {
      String day = item['day'];

      if (!result.containsKey(day)) {
        result[day] = [];
      }

      result[day]!.add(item);
    }

    // เรียงตาม meal_type ("มื้อที่ 1", "มื้อที่ 2", ...) ไม่ใช่ลำดับแถวจากฐานข้อมูล
    // ให้เลขมื้อบนการ์ดตรงกับหน้าดูสูตรและลำดับที่ใช้จองของในตู้
    for (final list in result.values) {
      list.sort(
        (a, b) => PlanAllocation.mealRank(
          a['meal_type']?.toString(),
        ).compareTo(PlanAllocation.mealRank(b['meal_type']?.toString())),
      );
    }

    return result;
  }

  String _fmt(num v) => v.round().toString();

  /// ยอดรวมต่อวันเทียบกับเป้า (แคลอรี/โปรตีน) พร้อมหลอดและบอกว่าขาดเท่าไร
  Widget _dayTotals(num calories, num protein) {
    if (targetCalories <= 0 && targetProtein <= 0) {
      return Text(
        "รวมต่อวัน: ${_fmt(calories)} kcal | ${_fmt(protein)} g protein",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xff5189C9),
        ),
      );
    }
    // ช่วงเดียวกับตอนสร้างแพลน (PlanTargets): เป้าเป็นเพดาน เกินเมื่อไรก็เตือน
    // ขาดไม่เกิน [tolerance] ถือว่าถึงเป้า
    Widget row(
      String label,
      num value,
      num target,
      String unit,
      Color color, {
      required num tolerance,
    }) {
      if (target <= 0) return const SizedBox.shrink();
      final ratio = (value / target).clamp(0.0, 1.0).toDouble();
      final gap = target - value;
      final reached = gap <= tolerance;
      final over = value.round() > target;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "$label ${_fmt(value)} / ${_fmt(target)} $unit",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  over
                      ? "เกิน ${_fmt(-gap)} $unit"
                      : reached
                      ? (gap > 0 ? "ใกล้ถึงเป้า" : "ถึงเป้า ✓")
                      : "ขาด ${_fmt(gap)} $unit",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: over
                        ? const Color(0xffE07B00)
                        : reached
                        ? const Color(0xff3F9142)
                        : const Color(0xffD64545),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: Colors.black12,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "รวมต่อวัน",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xff5189C9),
          ),
        ),
        row(
          "พลังงาน",
          calories,
          targetCalories,
          "kcal",
          Colors.orange,
          tolerance: PlanTargets.calTolerance,
        ),
        row(
          "โปรตีน",
          protein,
          targetProtein,
          "g",
          Colors.blue,
          tolerance: PlanTargets.proteinTolerance,
        ),
      ],
    );
  }

  /// ป้ายบอกที่มาของสูตร: AI สร้างใหม่ตอนทำแพลน / หยิบจากคลังสูตรในฐานข้อมูล
  Widget _sourceChip(dynamic meal) {
    final id = meal['recipe_id']?.toString();
    final ai = id == null ? null : _aiMade[id];
    if (ai == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: ai ? const Color(0xffEDE7FF) : const Color(0xffE3F1FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        ai ? "✨ AI สร้างใหม่" : "📖 จากคลังสูตร",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ai ? const Color(0xff6A4BC4) : const Color(0xff2F6DB0),
        ),
      ),
    );
  }

  /// ผลการจองวัตถุดิบให้มื้อที่ใกล้ถึงก่อน (คำนวณใหม่ทุกครั้งที่ build)
  Map<String, List<IngredientStatus>> _allocation = {};

  /// กล่อง "🛒 ต้องซื้อ" ในการ์ดมื้อ — เฉพาะส่วนที่ขาดหลังจองของให้มื้อก่อนหน้าแล้ว
  Widget _toBuyBox(Map<String, dynamic> meal) {
    if (meal['is_cooked'] == true) return const SizedBox.shrink();
    final pending = [
      for (final s
          in _allocation[meal['id']?.toString()] ?? const <IngredientStatus>[])
        if (!s.have) "${s.name} ${_qtyText(s.short)} ${s.unit}".trim(),
    ];
    if (pending.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffE67E22)),
      ),
      child: Text(
        "🛒 ต้องซื้อ: ${pending.join(', ')}",
        style: const TextStyle(fontSize: 13, color: Color(0xffB85C00)),
      ),
    );
  }

  String _qtyText(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// การ์ดแจ้งปัญหาของแพลน — ระบบพยายามทำตามที่ผู้ใช้กำหนดแล้ว (ให้ AI ทำใหม่)
  /// แต่ยังไม่ได้ จึงบอกให้ผู้ใช้รู้และแก้เองได้ (กด "เปลี่ยนเมนู"):
  /// 1. วันที่แคลอรี/โปรตีนรวมไม่ตรงเป้า
  /// 2. เมนูที่อาจขัดกับข้อจำกัดอาหาร (ตรวจจากชื่อวัตถุดิบ)
  /// 3. แพลนแบบใช้เฉพาะของในตู้ แต่ของในตู้ไม่พอ
  Widget _planWarningsCard(
    List<Map<String, String>> weekDays,
    Map<String, List<dynamic>> grouped,
  ) {
    final warnings = <String>[];

    // 1. ยอดรวมรายวันไม่อยู่ในช่วงเป้า
    if (targetCalories > 0 && targetProtein > 0) {
      final t = PlanTargets(
        dayCal: targetCalories,
        dayProtein: targetProtein,
        meals: 1,
      );
      final badDays = <String>[];
      for (final d in weekDays) {
        final dayMeals = grouped[d["en"]] ?? const [];
        if (dayMeals.isEmpty) continue;
        num cal = 0, pro = 0;
        for (final m in dayMeals) {
          cal += num.tryParse('${m['calories']}') ?? 0;
          pro += num.tryParse('${m['protein']}') ?? 0;
        }
        if (!t.dayFits(cal, pro)) badDays.add(d["th"] ?? '');
      }
      if (badDays.isNotEmpty) {
        warnings.add(
          "แคลอรี/โปรตีนรวมยังไม่ตรงเป้า: ${badDays.join(', ')} "
          "(ดูว่าเกินหรือขาดที่การ์ดของแต่ละวัน)",
        );
      }
    }

    // 2. เมนูที่อาจขัดกับข้อจำกัดอาหาร
    final thaiDay = {for (final d in weekDays) d["en"]: d["th"] ?? ''};
    for (final m in meals) {
      if (m is! Map) continue;
      final wrong = DietCheck.violations(
        dietType,
        DietCheck.namesOf(m['ingredients']),
      );
      if (wrong.isEmpty) continue;
      warnings.add(
        "\"${m['food_name'] ?? ''}\" (${thaiDay[m['day']] ?? m['day']}) "
        "มี ${wrong.join(', ')} ซึ่งอาจขัดกับข้อจำกัดอาหาร \"$dietType\"",
      );
    }

    // 3. ใช้เฉพาะของในตู้ (ไม่มีของต้องซื้อตอนสร้าง) แต่ของในตู้ไม่พอ
    if (!MealRegenerate.planAllowsBuying(meals)) {
      final short = PlanAllocation.shoppingList(
        meals: meals,
        allocation: _allocation,
        dayLabel: (key) => thaiDay[key] ?? key,
      );
      if (short.isNotEmpty) {
        warnings.add(
          "แพลนนี้ใช้เฉพาะของในตู้เย็น แต่ของในตู้ไม่พอ ${short.length} รายการ "
          "(ดูรายการต้องซื้อด้านล่าง)",
        );
      }
    }

    if (warnings.isEmpty) return const SizedBox.shrink();
    const red = Color(0xffD93025);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: red, size: 20),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  "แพลนนี้ยังไม่ตรงกับที่คุณกำหนดทั้งหมด",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "• $w",
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            "กด \"เปลี่ยนเมนู\" ที่มื้อนั้นเพื่อให้ระบบหาเมนูใหม่",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// การ์ดด้านบน: รายการของที่ต้องซื้อทั้งสัปดาห์ = ส่วนที่ขาดจริงของทุกมื้อ
  /// (ของในตู้จองให้มื้อที่ใกล้ถึงก่อน) — ซื้อมาสแกนเข้าตู้ รายการจะลดลงเอง
  Widget _shoppingListCard(List<Map<String, String>> weekDays) {
    final thaiDay = {for (final d in weekDays) d["en"]: d["th"] ?? ''};
    final items = PlanAllocation.shoppingList(
      meals: meals,
      allocation: _allocation,
      dayLabel: (key) => thaiDay[key] ?? key,
    );
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE67E22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "🛒 ต้องซื้อสำหรับแพลนนี้ (${items.length} รายการ)",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xffB85C00),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            "คิดจากของในตู้ที่จองให้มื้อที่ใกล้ถึงก่อน ซื้อมาสแกนเข้าตู้ รายการจะลดลงเอง",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "• ${it.name}",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "  ${it.days.join(', ')}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "${_qtyText(it.amount)} ${it.unit}".trim(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupByDay();
    _allocation = PlanAllocation.allocate(
      meals: meals,
      fridgeItems: fridgeItems,
      planStart: createdDate,
    );
    final weekDays = generateWeekDays();

    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),
            _buildHeader(context),
            const SizedBox(height: 15),

            // แถบยืนยัน (ยกเลิก / บันทึกทั้งหมด) — โชว์เฉพาะตอนที่ยังไม่ได้
            // บันทึกแผนนี้ พอบันทึกแล้วจะซ่อนไปเพราะไม่มีอะไรให้ยืนยันอีก
            if (!loading && !saved)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0E0E0),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "ยกเลิก",
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF7D0),
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: savePlan,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text(
                            "บันทึกทั้งหมด",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 15),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _planWarningsCard(weekDays, grouped),
                        _shoppingListCard(weekDays),
                        ...weekDays.map((day) {
                          final dayMeals = grouped[day["en"]] ?? [];

                          num calories = 0;
                          num protein = 0;

                          for (var meal in dayMeals) {
                            calories +=
                                num.tryParse(meal['calories'].toString()) ?? 0;
                            protein +=
                                num.tryParse(meal['protein'].toString()) ?? 0;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 15),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  day["th"]!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff5189C9),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (dayMeals.isEmpty)
                                  const Text("ไม่มีเมนู")
                                else
                                  ...List.generate(dayMeals.length, (index) {
                                    final meal = dayMeals[index];

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfffff7d0),
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.dinner_dining,
                                                size: 18,
                                                color: Colors.black87,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "มื้อที่ ${index + 1}",
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _sourceChip(meal),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            meal['food_name'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                "${meal['calories'] ?? 0} kcal",
                                                style: const TextStyle(
                                                  color: Colors.orange,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              Text(
                                                "${meal['protein'] ?? 0} g",
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          // แก้วัตถุดิบแล้วแต่ยังไม่ได้คำนวณใหม่
                                          if (MealNutrition.isStale(
                                            Map<String, dynamic>.from(meal),
                                          ))
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: Text(
                                                "⚠️ ค่าเดิมก่อนแก้วัตถุดิบ กดทำอาหารเพื่อคำนวณใหม่",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xffB85C00),
                                                ),
                                              ),
                                            ),
                                          // ของที่ต้องซื้อสำหรับมื้อนี้ (มื้อเสริมที่ AI เพิ่มให้)
                                          // หายไปเองเมื่อซื้อมาแล้ว/มีในตู้เย็น
                                          _toBuyBox(
                                            Map<String, dynamic>.from(meal),
                                          ),
                                          // ปุ่มทำอาหารให้โชว์เฉพาะตอนบันทึกแผนแล้ว
                                          // (ตอนตรวจสอบแพลนก่อนบันทึกยังไม่มีปุ่มนี้)
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              // ปุ่มทำอาหารโชว์เฉพาะตอนบันทึกแผนแล้ว
                                              // บันทึกแล้ว = ทำอาหาร, ยังไม่บันทึก = ดูสูตร (ไม่มีปุ่มทำแล้ว)
                                              saved
                                                  ? _buildCookButton(meal)
                                                  : _buildPreviewButton(meal),
                                              // เปลี่ยนเมนูได้ทั้งก่อนและหลังบันทึก
                                              // (ยกเว้นมื้อที่ทำไปแล้ว)
                                              if (meal['is_cooked'] != true)
                                                _buildChangeMenuButton(
                                                  Map<String, dynamic>.from(
                                                    meal,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                const Divider(),
                                _dayTotals(calories, protein),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan),
    );
  }

  // ปุ่ม "ทำแล้ว/ทำอาหาร" ต่อมื้อ — สถานะ is_cooked ดึงจากของจริงใน
  // weekly_meals เสมอ กดแล้วไปหน้าทำอาหารเพื่อดูวัตถุดิบ/ขั้นตอน แล้วรีเฟรช
  // รายการเมื่อกลับมา
  /// id ของมื้อที่กำลังให้ AI เปลี่ยนเมนูอยู่ (แสดงตัวโหลดที่ปุ่ม)
  final Set<String> _regenerating = {};

  Widget _buildChangeMenuButton(Map<String, dynamic> meal) {
    final id = meal['id']?.toString() ?? '';
    final busy = _regenerating.contains(id);
    return OutlinedButton.icon(
      onPressed: busy || _regenerating.isNotEmpty
          ? null
          : () => _changeMenu(meal),
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(busy ? "กำลังเปลี่ยน..." : "เปลี่ยนเมนู"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xff5189C9),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xff5189C9)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// ถามความต้องการ (ไม่บังคับ) แล้วให้ AI สร้างเมนูใหม่แทนมื้อนี้
  Future<void> _changeMenu(Map<String, dynamic> meal) async {
    final hintController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("เปลี่ยนเมนูนี้?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "AI จะสร้างเมนูใหม่แทน \"${meal['food_name'] ?? ''}\" "
              "ให้แคลอรีและโปรตีนรวมของวันนี้อยู่ในเป้าของแพลน",
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hintController,
              decoration: const InputDecoration(
                labelText: "อยากได้แบบไหน (ไม่บังคับ)",
                hintText: "เช่น ไม่เอาปลา, อยากได้เมนูต้ม",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ยกเลิก"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("เปลี่ยนเมนู"),
          ),
        ],
      ),
    );
    final hint = hintController.text;
    hintController.dispose();
    if (confirmed != true || !mounted) return;

    final id = meal['id']?.toString() ?? '';
    setState(() => _regenerating.add(id));
    try {
      final others = [
        for (final m in meals)
          if (m['id']?.toString() != id) (m['food_name'] ?? '').toString(),
      ];
      final updated = await MealRegenerate.regenerate(
        meal: meal,
        otherNames: others,
        fridgeOnly: !MealRegenerate.planAllowsBuying(meals),
        hint: hint,
        dietType: dietType,
        goal: goal,
        // งบของมื้อนี้คิดจากเป้าต่อวันของแพลน − มื้ออื่นในวันเดียวกัน
        targets: PlanTargets(
          dayCal: targetCalories,
          dayProtein: targetProtein,
          meals: 1,
        ),
        sameDayMeals: [
          for (final m in meals)
            if (m['day'] == meal['day'] && m['id']?.toString() != id) m,
        ],
      );
      await loadMeals();
      if (!mounted) return;
      final warning = updated['warning']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warning == null
                ? "เปลี่ยนเป็น \"${updated['food_name']}\" แล้ว ✅"
                : "เปลี่ยนเป็น \"${updated['food_name']}\" แล้ว แต่$warning",
          ),
          backgroundColor: warning == null
              ? Colors.green
              : const Color(0xffE67E22),
          duration: Duration(seconds: warning == null ? 4 : 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiErrorMessage(e, fallback: 'เปลี่ยนเมนูไม่สำเร็จ'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _regenerating.remove(id));
    }
  }

  Widget _buildCookButton(dynamic meal) {
    final isCooked = meal['is_cooked'] == true;

    // ใช้ widthFactor 1 ให้กว้างเท่าปุ่ม จะได้วางคู่กับปุ่ม "เปลี่ยนเมนู" ในแถวเดียวกัน
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Material(
        color: isCooked ? Colors.white : const Color(0xFFFFF7D0),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final mealId = meal['id']?.toString();
            if (mealId == null) return;

            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CookMealScreen(mealId: mealId)),
            );

            loadMeals();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCooked ? Icons.check_circle : Icons.restaurant,
                  size: 16,
                  color: Colors.black87,
                ),
                const SizedBox(width: 6),
                Text(
                  isCooked ? "ทำแล้ว" : "ทำอาหาร",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ก่อนบันทึกแพลน: เปิดดูวัตถุดิบ/วิธีทำ/ค่าโภชนาการได้ แต่ไม่มีปุ่ม "ทำแล้ว"
  Widget _buildPreviewButton(dynamic meal) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Material(
        color: const Color(0xFFFFF7D0),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final mealId = meal['id']?.toString();
            if (mealId == null) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CookMealScreen(mealId: mealId, previewOnly: true),
              ),
            );
            loadMeals();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_rounded, size: 16, color: Colors.black87),
                SizedBox(width: 6),
                Text(
                  "ดูสูตร",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
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
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  const CalendarIcon(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      // ก่อนบันทึก: ให้ตรวจสอบแพลนที่เพิ่งสร้าง
                      // หลังบันทึกแล้ว: ดูรายการอาหารรายสัปดาห์
                      saved ? "รายการอาหารรายสัปดาห์" : "ตรวจสอบแพลนเมนูอาหาร",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
