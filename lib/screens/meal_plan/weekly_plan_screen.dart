import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart'; // หน้าทำอาหารจากแพลน
import 'package:test_app/screens/meal_plan/cook_meal_screen.dart'; // หน้าแพลนที่บันทึกไว้
import 'package:test_app/screens/meal_plan/my_plan_screen.dart'; // ช่วงเป้าแคลอรี/โปรตีน
import 'package:test_app/services/plan_targets.dart'; // เช็คว่าต้องคำนวณโภชนาการใหม่ไหม
import 'package:test_app/services/meal_nutrition.dart'; // ของพื้นฐาน
import 'package:test_app/services/shopping_suggestion.dart'; // ข้อความ error ของ AI
import 'package:test_app/services/gemini_retry.dart'; // เปลี่ยนเมนูมื้อเดียว
import 'package:test_app/services/meal_regenerate.dart'; // จองของในตู้ให้แต่ละมื้อ
import 'package:test_app/services/plan_allocation.dart'; // ตรวจข้อจำกัดอาหาร
import 'package:test_app/services/diet_check.dart';

// หน้าแผนอาหารรายสัปดาห์ (ตรวจก่อนบันทึก / ดูหลังบันทึก)
class WeeklyPlanScreen extends StatefulWidget {
  final String planId; // id ของแพลนที่จะแสดง

  const WeeklyPlanScreen({super.key, required this.planId});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final supabase = Supabase.instance.client;

  List<dynamic> meals = []; // มื้ออาหารทั้งหมดในแพลน

  /// recipe_id -> สูตรนี้ AI สร้างตอนทำแพลนนี้ (true) หรือมาจากคลังสูตรเดิม (false)
  /// ดูจากเวลาที่สูตรถูกเพิ่มเข้าคลังกลาง เทียบกับเวลาสร้างแพลน
  Map<String, bool> _aiMade = {};
  bool loading = true; // กำลังโหลดไหม
  bool saved = false; // บันทึกแพลนแล้วหรือยัง

  DateTime? createdDate; // วันที่สร้างแพลน (ใช้เรียงวัน)

  // เป้าต่อวันของแพลน (ใช้เทียบยอดรวมแต่ละวัน)
  num targetCalories = 0;
  num targetProtein = 0;
  String? goal; // เป้าหมาย
  String? dietType; // ข้อจำกัดอาหาร

  /// ของในตู้เย็นตอนนี้ ใช้เช็กว่าของ "ต้องซื้อ" ของมื้อเสริมซื้อมาแล้วหรือยัง
  List<Map<String, dynamic>> fridgeItems = [];

  @override
  void initState() {
    super.initState();
    loadMeals(); // เปิดหน้ามาโหลดข้อมูล
  }

  // โหลดมื้ออาหาร + ของในตู้ + ข้อมูลแพลน
  Future<void> loadMeals() async {
    try {
      final response = await supabase
          .from('weekly_meals') // ดึงทุกมื้อในแพลนนี้
          .select()
          .eq('plan_id', widget.planId);

      await ShoppingSuggestion.loadStaples(); // โหลดรายการของพื้นฐาน
      final user = supabase.auth.currentUser;
      final fridge = user == null // ดึงของในตู้
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await supabase
                  .from('fridge_items')
                  .select()
                  .eq('user_id', user.id),
            );

      final plan = await supabase // ดึงข้อมูลแพลน
          .from('meal_plans')
          .select(
            'saved, created_at, target_calories, target_protein, goal, diet_type',
          )
          .eq('id', widget.planId)
          .single(); // เอาแถวเดียว

      // ที่มาของสูตร (ไม่สำเร็จก็ไม่เป็นไร แค่ไม่แสดงป้าย)
      final recipeIds = { // id สูตรทั้งหมดที่ใช้ในแพลน
        for (final m in response)
          if (m['recipe_id'] != null) m['recipe_id'].toString(),
      };
      final planCreated = DateTime.tryParse('${plan['created_at'] ?? ''}'); // เวลาสร้างแพลน
      final aiMade = <String, bool>{};
      if (recipeIds.isNotEmpty) {
        try {
          final rows = await supabase // ดึงเวลาที่สูตรถูกสร้าง
              .from('recipes')
              .select('id, created_at')
              .inFilter('id', recipeIds.toList());
          for (final r in rows) {
            final created = DateTime.tryParse('${r['created_at'] ?? ''}');
            if (created == null || planCreated == null) continue;
            aiMade[r['id'].toString()] = !created.isBefore(planCreated); // สูตรสร้างหลังแพลน = AI สร้างตอนทำแพลนนี้
          }
        } catch (e) {
          debugPrint('โหลดที่มาของสูตรไม่สำเร็จ: $e');
        }
      }

      setState(() { // อัปเดตหน้าจอ
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

  // กด "บันทึกทั้งหมด"
  Future<void> savePlan() async {
    await supabase
        .from('meal_plans')
        .update({'saved': true}) // ตั้งว่าบันทึกแล้ว
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

  // รายชื่อ 7 วัน เรียงเริ่มจากวันที่สร้างแพลน
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
    int startIndex = createdDate!.weekday - 1; // ลำดับวันเริ่ม (จันทร์ = 0)

    return List.generate(7, (index) {
      return days[(startIndex + index) % 7]; // วนรอบสัปดาห์
    });
  }

  // จัดกลุ่มมื้อตามวัน
  Map<String, List<dynamic>> groupByDay() {
    Map<String, List<dynamic>> result = {};

    for (var item in meals) {
      String day = item['day']; // ชื่อวัน (ภาษาอังกฤษ)

      if (!result.containsKey(day)) {
        result[day] = [];
      }

      result[day]!.add(item); // ใส่มื้อลงกลุ่มของวันนั้น
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

  String _fmt(num v) => v.round().toString(); // ปัดเป็นจำนวนเต็มแล้วเป็นข้อความ

  /// ยอดรวมต่อวันเทียบกับเป้า (แคลอรี/โปรตีน) พร้อมหลอดและบอกว่าขาดเท่าไร
  Widget _dayTotals(num calories, num protein) {
    if (targetCalories <= 0 && targetProtein <= 0) { // แพลนไม่มีเป้า -> แสดงแค่ยอดรวม
      return Text(
        "รวมต่อวัน: ${_fmt(calories)} kcal | ${_fmt(protein)} g protein",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xff5189C9), // [UI] สีฟ้า
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
      if (target <= 0) return const SizedBox.shrink(); // ไม่มีเป้าของค่านี้ ไม่แสดง
      final ratio = (value / target).clamp(0.0, 1.0).toDouble(); // สัดส่วนสำหรับหลอด
      final gap = target - value; // ขาดอีกเท่าไหร่
      final reached = gap <= tolerance; // ขาดไม่เกินที่ยอม = ถึงเป้า
      final over = value.round() > target; // เกินเป้า
      return Padding(
        padding: const EdgeInsets.only(top: 6), // [UI] ระยะบน
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
                      fontSize: 13, // [UI] ขนาดข้อความ
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
                    fontSize: 12, // [UI] ขนาดสถานะ
                    fontWeight: FontWeight.bold,
                    color: over
                        ? const Color(0xffE07B00) // [UI] เกิน = ส้ม
                        : reached
                        ? const Color(0xff3F9142) // [UI] ถึงเป้า = เขียว
                        : const Color(0xffD64545), // [UI] ขาด = แดง
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4), // [UI] หลอดโค้ง
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7, // [UI] ความหนาหลอด
                backgroundColor: Colors.black12, // [UI] สีพื้นหลอด
                color: color, // [UI] สีหลอด (ส่งมาตอนเรียก)
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
          Colors.orange, // [UI] หลอดแคลอรีสีส้ม
          tolerance: PlanTargets.calTolerance,
        ),
        row(
          "โปรตีน",
          protein,
          targetProtein,
          "g",
          Colors.blue, // [UI] หลอดโปรตีนสีฟ้า
          tolerance: PlanTargets.proteinTolerance,
        ),
      ],
    );
  }

  /// ป้ายบอกที่มาของสูตร: AI สร้างใหม่ตอนทำแพลน / หยิบจากคลังสูตรในฐานข้อมูล
  Widget _sourceChip(dynamic meal) {
    final id = meal['recipe_id']?.toString();
    final ai = id == null ? null : _aiMade[id];
    if (ai == null) return const SizedBox.shrink(); // ไม่รู้ที่มา ไม่แสดงป้าย
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // [UI] ระยะในป้าย
      decoration: BoxDecoration(
        color: ai ? const Color(0xffEDE7FF) : const Color(0xffE3F1FF), // [UI] AI = ม่วงอ่อน, คลังสูตร = ฟ้าอ่อน
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง
      ),
      child: Text(
        ai ? "✨ AI สร้างใหม่" : "📖 จากคลังสูตร",
        style: TextStyle(
          fontSize: 11, // [UI] ขนาดตัวอักษรป้าย
          fontWeight: FontWeight.w600,
          color: ai ? const Color(0xff6A4BC4) : const Color(0xff2F6DB0), // [UI] AI = ม่วง, คลังสูตร = น้ำเงิน
        ),
      ),
    );
  }

  /// ผลการจองวัตถุดิบให้มื้อที่ใกล้ถึงก่อน (คำนวณใหม่ทุกครั้งที่ build)
  Map<String, List<IngredientStatus>> _allocation = {};

  /// กล่อง "🛒 ต้องซื้อ" ในการ์ดมื้อ — เฉพาะส่วนที่ขาดหลังจองของให้มื้อก่อนหน้าแล้ว
  Widget _toBuyBox(Map<String, dynamic> meal) {
    if (meal['is_cooked'] == true) return const SizedBox.shrink(); // ทำแล้ว ไม่ต้องซื้อ
    // แพลนแบบใช้เฉพาะของในตู้ ไม่มีรายการซื้อ ของที่ไม่พอแค่ไม่ติ๊ก
    if (!MealRegenerate.planAllowsBuying(meals)) return const SizedBox.shrink();
    final pending = [ // รายการที่ยังขาด
      for (final s
          in _allocation[meal['id']?.toString()] ?? const <IngredientStatus>[])
        if (!s.have) "${s.name} ${_qtyText(s.short)} ${s.unit}".trim(),
    ];
    if (pending.isEmpty) return const SizedBox.shrink(); // ไม่ขาด ไม่แสดง
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8), // [UI] ระยะบน
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), // [UI] ระยะใน
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5), // [UI] พื้นส้มอ่อน
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง
        border: Border.all(color: const Color(0xffE67E22)), // [UI] ขอบส้ม
      ),
      child: Text(
        "🛒 ต้องซื้อ: ${pending.join(', ')}",
        style: const TextStyle(fontSize: 13, color: Color(0xffB85C00)), // [UI] ขนาด 13 สีส้มเข้ม
      ),
    );
  }

  // แสดงตัวเลขไม่เกิน 2 ตำแหน่ง ตัด 0 ท้าย
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
        meals: 1, // ใช้เช็คยอดรวมทั้งวัน
      );
      final badDays = <String>[];
      for (final d in weekDays) { // ไล่ทีละวัน
        final dayMeals = grouped[d["en"]] ?? const [];
        if (dayMeals.isEmpty) continue;
        num cal = 0, pro = 0;
        for (final m in dayMeals) { // รวมแคลอรี/โปรตีนของวัน
          cal += num.tryParse('${m['calories']}') ?? 0;
          pro += num.tryParse('${m['protein']}') ?? 0;
        }
        if (!t.dayFits(cal, pro)) badDays.add(d["th"] ?? ''); // ไม่อยู่ในช่วงเป้า
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
    for (final m in meals) { // ไล่ทีละมื้อ
      if (m is! Map) continue;
      final wrong = DietCheck.violations( // วัตถุดิบที่ผิดข้อจำกัด
        dietType,
        DietCheck.namesOf(m['ingredients']),
      );
      if (wrong.isEmpty) continue;
      warnings.add(
        "\"${m['food_name'] ?? ''}\" (${thaiDay[m['day']] ?? m['day']}) "
        "มี ${wrong.join(', ')} ซึ่งอาจขัดกับข้อจำกัดอาหาร \"$dietType\"",
      );
    }

    if (warnings.isEmpty) return const SizedBox.shrink(); // ไม่มีปัญหา ไม่แสดงการ์ด
    const red = Color(0xffD93025); // [UI] สีแดงของการ์ดเตือน
    return Container(
      margin: const EdgeInsets.only(bottom: 16), // [UI] ระยะใต้การ์ด
      padding: const EdgeInsets.all(14), // [UI] ระยะใน
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA), // [UI] พื้นแดงอ่อน
        borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง
        border: Border.all(color: red), // [UI] ขอบแดง
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: red, size: 20), // [UI] ไอคอนเตือน ขนาด 20
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  "แพลนนี้ยังไม่ตรงกับที่คุณกำหนดทั้งหมด",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15, // [UI] ขนาดหัวข้อ
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
                style: const TextStyle(fontSize: 13, color: Colors.black87), // [UI] ขนาด 13
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
    // แพลนแบบใช้เฉพาะของในตู้ ไม่มีรายการซื้อของ
    if (!MealRegenerate.planAllowsBuying(meals)) return const SizedBox.shrink();
    final thaiDay = {for (final d in weekDays) d["en"]: d["th"] ?? ''};
    final items = PlanAllocation.shoppingList( // รวมรายการซื้อทั้งสัปดาห์
      meals: meals,
      allocation: _allocation,
      dayLabel: (key) => thaiDay[key] ?? key,
    );
    if (items.isEmpty) return const SizedBox.shrink(); // ไม่มีของต้องซื้อ ไม่แสดง
    return Container(
      margin: const EdgeInsets.only(bottom: 16), // [UI] ระยะใต้การ์ด
      padding: const EdgeInsets.all(14), // [UI] ระยะใน
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5), // [UI] พื้นส้มอ่อน
        borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง
        border: Border.all(color: const Color(0xffE67E22)), // [UI] ขอบส้ม
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "🛒 ต้องซื้อสำหรับแพลนนี้ (${items.length} รายการ)",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15, // [UI] ขนาดหัวข้อ
              color: Color(0xffB85C00), // [UI] สีส้มเข้ม
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            "คิดจากของในตู้ที่จองให้มื้อที่ใกล้ถึงก่อน ซื้อมาสแกนเข้าตู้ รายการจะลดลงเอง",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          for (final it in items) // แถวของที่ต้องซื้อทีละรายการ
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
                            fontSize: 14, // [UI] ขนาดชื่อ
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "  ${it.days.join(', ')}", // วันที่ใช้
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "${_qtyText(it.amount)} ${it.unit}".trim(), // จำนวนที่ต้องซื้อ
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
    final grouped = groupByDay(); // จัดกลุ่มตามวัน
    _allocation = PlanAllocation.allocate( // จองของให้ทุกมื้อ (คำนวณใหม่ทุกครั้งที่วาดหน้า)
      meals: meals,
      fridgeItems: fridgeItems,
      planStart: createdDate,
    );
    final weekDays = generateWeekDays(); // รายชื่อ 7 วัน

    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15), // [UI] ระยะจากขอบบน
            _buildHeader(context), // หัวหน้า
            const SizedBox(height: 15),

            // แถบยืนยัน (ยกเลิก / บันทึกทั้งหมด) — โชว์เฉพาะตอนที่ยังไม่ได้
            // บันทึกแผนนี้ พอบันทึกแล้วจะซ่อนไปเพราะไม่มีอะไรให้ยืนยันอีก
            if (!loading && !saved)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48, // [UI] ความสูงปุ่ม
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0E0E0), // [UI] ปุ่มยกเลิกสีเทา
                            side: BorderSide.none, // [UI] ไม่มีขอบ
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                            ),
                          ),
                          onPressed: () => Navigator.pop(context), // ยกเลิก = ออกจากหน้า (แพลนยังไม่บันทึก)
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
                        height: 48, // [UI] ความสูงปุ่ม
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF7D0), // [UI] ปุ่มบันทึกสีครีม
                            foregroundColor: Colors.black87,
                            elevation: 0, // [UI] ไม่มีเงา
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: savePlan, // บันทึกแพลน
                          icon: const Icon(Icons.check, size: 18), // [UI] ไอคอนติ๊ก
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
                  ? const Center(child: CircularProgressIndicator()) // กำลังโหลด
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
                      children: [
                        _planWarningsCard(weekDays, grouped), // การ์ดเตือนปัญหาของแพลน
                        _shoppingListCard(weekDays), // การ์ดรายการซื้อ
                        ...weekDays.map((day) { // การ์ดของแต่ละวัน
                          final dayMeals = grouped[day["en"]] ?? []; // มื้อของวันนี้

                          num calories = 0;
                          num protein = 0;

                          for (var meal in dayMeals) { // รวมแคลอรี/โปรตีนของวัน
                            calories +=
                                num.tryParse(meal['calories'].toString()) ?? 0;
                            protein +=
                                num.tryParse(meal['protein'].toString()) ?? 0;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 15), // [UI] ระยะใต้การ์ดวัน
                            padding: const EdgeInsets.all(18), // [UI] ระยะในการ์ด
                            decoration: BoxDecoration(
                              color: Colors.white, // [UI] พื้นขาว
                              borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  day["th"]!, // ชื่อวันภาษาไทย
                                  style: const TextStyle(
                                    fontSize: 20, // [UI] ขนาดชื่อวัน
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff5189C9), // [UI] สีฟ้า
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (dayMeals.isEmpty)
                                  const Text("ไม่มีเมนู")
                                else
                                  ...List.generate(dayMeals.length, (index) { // การ์ดมื้อทีละมื้อ
                                    final meal = dayMeals[index];

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้การ์ดมื้อ
                                      padding: const EdgeInsets.all(12), // [UI] ระยะใน
                                      decoration: BoxDecoration(
                                        color: const Color(0xfffff7d0), // [UI] สีการ์ดมื้อ (ครีม)
                                        borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.dinner_dining,
                                                size: 18, // [UI] ไอคอนจาน ขนาด 18
                                                color: Colors.black87,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "มื้อที่ ${index + 1}",
                                                style: const TextStyle(
                                                  fontSize: 16, // [UI] ขนาดหัวมื้อ
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _sourceChip(meal), // ป้ายที่มาของสูตร
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            meal['food_name'] ?? '', // ชื่อเมนู
                                            style: const TextStyle(
                                              fontSize: 15, // [UI] ขนาดชื่อเมนู
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                "${meal['calories'] ?? 0} kcal",
                                                style: const TextStyle(
                                                  color: Colors.orange, // [UI] แคลอรีสีส้ม
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 20), // [UI] ระยะระหว่างแคลอรีกับโปรตีน
                                              Text(
                                                "${meal['protein'] ?? 0} g",
                                                style: const TextStyle(
                                                  color: Colors.blue, // [UI] โปรตีนสีฟ้า
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
                                                  fontSize: 12, // [UI] ขนาด 12
                                                  color: Color(0xffB85C00), // [UI] สีส้มเข้ม
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
                                            spacing: 8, // [UI] ระยะห่างแนวนอนระหว่างปุ่ม
                                            runSpacing: 8, // [UI] ระยะห่างแนวตั้งเมื่อตกบรรทัด
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
                                const Divider(), // [UI] เส้นคั่น
                                _dayTotals(calories, protein), // ยอดรวมของวัน
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
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan), // แถบเมนูล่าง ไฮไลต์ "แพลน"
    );
  }

  // ปุ่ม "ทำแล้ว/ทำอาหาร" ต่อมื้อ — สถานะ is_cooked ดึงจากของจริงใน
  // weekly_meals เสมอ กดแล้วไปหน้าทำอาหารเพื่อดูวัตถุดิบ/ขั้นตอน แล้วรีเฟรช
  // รายการเมื่อกลับมา
  /// id ของมื้อที่กำลังให้ AI เปลี่ยนเมนูอยู่ (แสดงตัวโหลดที่ปุ่ม)
  final Set<String> _regenerating = {};

  Widget _buildChangeMenuButton(Map<String, dynamic> meal) {
    final id = meal['id']?.toString() ?? ''; // id มื้อนี้
    final busy = _regenerating.contains(id); // มื้อนี้กำลังเปลี่ยนเมนูอยู่ไหม
    return OutlinedButton.icon(
      onPressed: busy || _regenerating.isNotEmpty // มีมื้อไหนกำลังเปลี่ยนอยู่ = กดไม่ได้
          ? null
          : () => _changeMenu(meal),
      icon: busy
          ? const SizedBox( // กำลังเปลี่ยน -> วงหมุนเล็ก
              width: 14, // [UI] ขนาดวงหมุน
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 18), // [UI] ไอคอนรีเฟรช ขนาด 18
      label: Text(busy ? "กำลังเปลี่ยน..." : "เปลี่ยนเมนู"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษร (ฟ้า)
        backgroundColor: Colors.white, // [UI] พื้นขาว
        side: const BorderSide(color: Color(0xff5189C9)), // [UI] ขอบฟ้า
        visualDensity: VisualDensity.compact, // [UI] ปุ่มกระชับ
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [UI] ระยะในปุ่ม
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // [UI] ทรงแคปซูล
        textStyle: const TextStyle(fontWeight: FontWeight.w600), // [UI] กึ่งหนา
      ),
    );
  }

  /// ถามความต้องการ (ไม่บังคับ) แล้วให้ AI สร้างเมนูใหม่แทนมื้อนี้
  Future<void> _changeMenu(Map<String, dynamic> meal) async {
    final hintController = TextEditingController(); // ช่องพิมพ์ความต้องการ
    final confirmed = await showDialog<bool>( // เปิดป๊อปอัปถามยืนยัน
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
              style: const TextStyle(fontSize: 14), // [UI] ขนาดข้อความ
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
    final hint = hintController.text; // เก็บข้อความที่พิมพ์ไว้
    // showDialog คืนค่าตั้งแต่เริ่มปิด แต่ TextField ยังอยู่ระหว่างแอนิเมชันปิด
    // dispose ทันทีจะพัง ("used after being disposed") — รอให้ปิดเสร็จก่อน
    Future.delayed(const Duration(milliseconds: 500), hintController.dispose);
    if (confirmed != true || !mounted) return; // ไม่ยืนยัน หยุด

    final id = meal['id']?.toString() ?? '';
    setState(() => _regenerating.add(id)); // เริ่มโหลด
    try {
      final others = [ // ชื่อเมนูอื่นในแพลน (ห้ามซ้ำ)
        for (final m in meals)
          if (m['id']?.toString() != id) (m['food_name'] ?? '').toString(),
      ];
      final updated = await MealRegenerate.regenerate( // ให้ระบบหาเมนูใหม่
        meal: meal,
        otherNames: others,
        fridgeOnly: !MealRegenerate.planAllowsBuying(meals), // แพลนไม่ซื้อเพิ่ม = ใช้เฉพาะของในตู้
        hint: hint,
        dietType: dietType,
        goal: goal,
        // งบของมื้อนี้คิดจากเป้าต่อวันของแพลน − มื้ออื่นในวันเดียวกัน
        targets: PlanTargets(
          dayCal: targetCalories,
          dayProtein: targetProtein,
          meals: 1,
        ),
        sameDayMeals: [ // มื้ออื่นในวันเดียวกัน
          for (final m in meals)
            if (m['day'] == meal['day'] && m['id']?.toString() != id) m,
        ],
      );
      await loadMeals(); // โหลดใหม่
      if (!mounted) return;
      final warning = updated['warning']?.toString(); // คำเตือนจากระบบ (ถ้ามี)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warning == null
                ? "เปลี่ยนเป็น \"${updated['food_name']}\" แล้ว ✅"
                : "เปลี่ยนเป็น \"${updated['food_name']}\" แล้ว แต่$warning",
          ),
          backgroundColor: warning == null
              ? Colors.green // [UI] สำเร็จ = เขียว
              : const Color(0xffE67E22), // [UI] มีคำเตือน = ส้ม
          duration: Duration(seconds: warning == null ? 4 : 8), // [UI] แสดง 4 วินาที (มีคำเตือน 8 วินาที)
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiErrorMessage(e, fallback: 'เปลี่ยนเมนูไม่สำเร็จ'),
          ),
          backgroundColor: Colors.red, // [UI] แถบแดง
        ),
      );
    } finally {
      if (mounted) setState(() => _regenerating.remove(id)); // เสร็จแล้ว
    }
  }

  Widget _buildCookButton(dynamic meal) {
    final isCooked = meal['is_cooked'] == true; // ทำมื้อนี้แล้วหรือยัง

    // ใช้ widthFactor 1 ให้กว้างเท่าปุ่ม จะได้วางคู่กับปุ่ม "เปลี่ยนเมนู" ในแถวเดียวกัน
    return Align(
      alignment: Alignment.centerLeft, // [UI] ชิดซ้าย
      widthFactor: 1,
      child: Material(
        color: isCooked ? Colors.white : const Color(0xFFFFF7D0), // [UI] ทำแล้ว = ขาว, ยังไม่ทำ = ครีม
        borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final mealId = meal['id']?.toString(); // id มื้อ
            if (mealId == null) return;

            await Navigator.push( // เปิดหน้าทำอาหาร
              context,
              MaterialPageRoute(builder: (_) => CookMealScreen(mealId: mealId)),
            );

            loadMeals(); // กลับมาโหลดใหม่
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [UI] ระยะในปุ่ม
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCooked ? Icons.check_circle : Icons.restaurant, // [UI] ทำแล้ว = ติ๊ก, ยังไม่ทำ = ช้อนส้อม
                  size: 16, // [UI] ขนาดไอคอน
                  color: Colors.black87,
                ),
                const SizedBox(width: 6),
                Text(
                  isCooked ? "ทำแล้ว" : "ทำอาหาร",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13, // [UI] ขนาดตัวอักษร
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
        color: const Color(0xFFFFF7D0), // [UI] สีปุ่ม (ครีม)
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final mealId = meal['id']?.toString();
            if (mealId == null) return;
            await Navigator.push( // เปิดหน้าดูสูตร (โหมดดูอย่างเดียว)
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CookMealScreen(mealId: mealId, previewOnly: true),
              ),
            );
            loadMeals();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [UI] ระยะในปุ่ม
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_rounded, size: 16, color: Colors.black87), // [UI] ไอคอนหนังสือ ขนาด 16
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

  // หัวหน้า: ปุ่มย้อนกลับ + แคปซูลชื่อหน้า
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
              height: 45, // [UI] ขนาดปุ่ม 45x45
              width: 45,
              decoration: BoxDecoration(
                color: const Color(0xfffff7d0), // [UI] สีครีม
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: BackIcon(size: 20)), // [UI] ไอคอนย้อนกลับ
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 50, // [UI] ความสูงแคปซูล
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีครีม
                borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
              ),
              child: Row(
                children: [
                  const CalendarIcon(size: 22), // [UI] ไอคอนปฏิทิน
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      // ก่อนบันทึก: ให้ตรวจสอบแพลนที่เพิ่งสร้าง
                      // หลังบันทึกแล้ว: ดูรายการอาหารรายสัปดาห์
                      saved ? "รายการอาหารรายสัปดาห์" : "ตรวจสอบแพลนเมนูอาหาร",
                      overflow: TextOverflow.ellipsis, // [UI] ยาวเกินตัดเป็น ...
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16, // [UI] ขนาดชื่อหน้า
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
