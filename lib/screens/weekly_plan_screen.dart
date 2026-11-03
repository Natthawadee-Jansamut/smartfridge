import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';
import 'cook_meal_screen.dart';
import 'my_plan_screen.dart';

class WeeklyPlanScreen extends StatefulWidget {
  final String planId;

  const WeeklyPlanScreen({
    super.key,
    required this.planId,
  });

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final supabase = Supabase.instance.client;

  List<dynamic> meals = [];
  bool loading = true;
  bool saved = false;

  DateTime? createdDate;

  @override
  void initState() {
    super.initState();
    loadMeals();
  }

  Future<void> loadMeals() async {
    try {
      final response =
          await supabase.from('weekly_meals').select().eq('plan_id', widget.planId);

      final plan = await supabase
          .from('meal_plans')
          .select('saved, created_at')
          .eq('id', widget.planId)
          .single();

      setState(() {
        meals = response;
        saved = plan['saved'] ?? false;

        // แปลงเวลา UTC เป็นเวลาไทย
        createdDate = DateTime.parse(plan['created_at']).toLocal();

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
    await supabase.from('meal_plans').update({'saved': true}).eq(
      'id',
      widget.planId,
    );

    setState(() {
      saved = true;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("บันทึกแผนอาหารเรียบร้อย")),
    );

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
                                      margin:
                                          const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfffff7d0),
                                        borderRadius:
                                            BorderRadius.circular(15),
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
                                            style:
                                                const TextStyle(fontSize: 15),
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
                                          // ปุ่มทำอาหารให้โชว์เฉพาะตอนบันทึกแผนแล้ว
                                          // (ตอนตรวจสอบแพลนก่อนบันทึกยังไม่มีปุ่มนี้)
                                          if (saved) ...[
                                            const SizedBox(height: 10),
                                            _buildCookButton(meal),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                const Divider(),
                                Text(
                                  "รวมต่อวัน: $calories kcal | $protein g protein",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xff5189C9),
                                  ),
                                ),
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
  Widget _buildCookButton(dynamic meal) {
    final isCooked = meal['is_cooked'] == true;

    return Align(
      alignment: Alignment.centerLeft,
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
              MaterialPageRoute(
                builder: (_) => CookMealScreen(mealId: mealId),
              ),
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
          const SizedBox(width: 10),
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const InkWell(
              customBorder: CircleBorder(),
              child: Center(child: FilterIcon(size: 20)),
            ),
          ),
        ],
      ),
    );
  }
}
