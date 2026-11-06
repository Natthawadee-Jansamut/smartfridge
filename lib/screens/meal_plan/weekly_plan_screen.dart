import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/screens/meal_plan/cook_meal_screen.dart';
import 'package:test_app/screens/meal_plan/my_plan_screen.dart';
import 'package:test_app/services/meal_nutrition.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/services/meal_regenerate.dart';

class WeeklyPlanScreen extends StatefulWidget {
  final String planId;

  const WeeklyPlanScreen({super.key, required this.planId});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final supabase = Supabase.instance.client;

  List<dynamic> meals = [];
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
                  .select('name, quantity')
                  .eq('user_id', user.id),
            );

      final plan = await supabase
          .from('meal_plans')
          .select(
            'saved, created_at, target_calories, target_protein, goal, diet_type',
          )
          .eq('id', widget.planId)
          .single();

      setState(() {
        meals = response;
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
    Widget row(String label, num value, num target, String unit, Color color) {
      if (target <= 0) return const SizedBox.shrink();
      final ratio = (value / target).clamp(0.0, 1.0).toDouble();
      final gap = target - value;
      final reached = value >= target * ShoppingSuggestion.shortfallRatio;
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
                  reached
                      ? (gap > 0 ? "ใกล้ถึงเป้า" : "ถึงเป้า ✓")
                      : "ขาด ${_fmt(gap)} $unit",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: reached
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
        row("พลังงาน", calories, targetCalories, "kcal", Colors.orange),
        row("โปรตีน", protein, targetProtein, "g", Colors.blue),
      ],
    );
  }

  bool _inFridge(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    return fridgeItems.any((f) {
      final fn = (f['name'] ?? '').toString().trim().toLowerCase();
      return fn.isNotEmpty &&
          (fn == n || fn.contains(n) || n.contains(fn)) &&
          (num.tryParse('${f['quantity']}') ?? 0) > 0;
    });
  }

  /// กล่อง "🛒 ต้องซื้อ" ในการ์ดมื้อ — เฉพาะวัตถุดิบที่ติดธง to_buy และยังไม่มีในตู้เย็น
  Widget _toBuyBox(Map<String, dynamic> meal) {
    final raw = meal['ingredients'];
    if (raw is! List) return const SizedBox.shrink();
    final pending = [
      for (final e in raw.whereType<Map>())
        if (e[ShoppingSuggestion.toBuyKey] == true &&
            !_inFridge((e['name'] ?? '').toString()) &&
            !ShoppingSuggestion.isStaple((e['name'] ?? '').toString()))
          "${e['name']} ${e['quantity'] ?? ''}".trim(),
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

  /// ตัวเลขข้างหน้าของปริมาณ เช่น "2 ฟอง" -> 2, "1/2 หัว" -> 0.5 (ไม่มี = 0)
  num _qtyAmount(String text) {
    final frac = RegExp(
      r'(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)',
    ).firstMatch(text);
    if (frac != null) {
      final b = num.parse(frac.group(2)!);
      return b == 0 ? 0 : num.parse(frac.group(1)!) / b;
    }
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    return m == null ? 0 : num.parse(m.group(0)!);
  }

  String _qtyText(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+\$'), '')
        .replaceFirst(RegExp(r'\.\$'), '');
  }

  /// การ์ดด้านบน: รายการของที่ต้องซื้อทั้งสัปดาห์ของแพลนนี้
  /// รวมวัตถุดิบที่ติดธง to_buy จากทุกมื้อ (ชื่อ+หน่วยเดียวกันบวกจำนวนกัน)
  /// ตัดของที่มีในตู้เย็นแล้วออก — ซื้อมาสแกนเข้าตู้ รายการจะหายไปเอง
  Widget _shoppingListCard(
    List<Map<String, String>> weekDays,
    Map<String, List<dynamic>> grouped,
  ) {
    final totals =
        <
          String,
          ({
            String name,
            String unit,
            num amount,
            List<String> extra,
            List<String> days,
          })
        >{};
    for (final day in weekDays) {
      for (final meal in grouped[day["en"]] ?? []) {
        final raw = meal['ingredients'];
        if (raw is! List) continue;
        for (final e in raw.whereType<Map>()) {
          if (e[ShoppingSuggestion.toBuyKey] != true) continue;
          final name = (e['name'] ?? '').toString().trim();
          if (name.isEmpty ||
              _inFridge(name) ||
              ShoppingSuggestion.isStaple(name)) {
            continue;
          }
          final qty = (e['quantity'] ?? '').toString().trim();
          final amount = _qtyAmount(qty);
          final unit = qty.replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '').trim();
          final key = '${name.toLowerCase()}|$unit';
          final prev = totals[key];
          final dayTh = day["th"] ?? '';
          totals[key] = (
            name: name,
            unit: unit,
            amount: (prev?.amount ?? 0) + amount,
            // ปริมาณที่ไม่มีตัวเลข (เช่น "เล็กน้อย") เก็บเป็นข้อความไว้แสดง
            extra: [...?prev?.extra, if (amount == 0 && qty.isNotEmpty) qty],
            days: [
              ...?prev?.days,
              if (!(prev?.days.contains(dayTh) ?? false)) dayTh,
            ],
          );
        }
      }
    }
    if (totals.isEmpty) return const SizedBox.shrink();

    final items = totals.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
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
            "ซื้อมาแล้วสแกนเข้าตู้เย็น รายการจะหายไปเอง",
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
                    [
                      if (it.amount > 0)
                        "${_qtyText(it.amount)} ${it.unit}".trim(),
                      ...it.extra,
                    ].join(' + '),
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
                        _shoppingListCard(weekDays, grouped),
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
                                              if (saved) _buildCookButton(meal),
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
              "แคลอรีและโปรตีนใกล้เคียงเดิม",
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
      );
      await loadMeals();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("เปลี่ยนเป็น \"${updated['food_name']}\" แล้ว ✅"),
          backgroundColor: Colors.green,
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
