import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'weekly_plan_screen.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';

class MyPlanScreen extends StatefulWidget {
  const MyPlanScreen({super.key});

  @override
  State<MyPlanScreen> createState() => _MyPlanScreenState();
}

class _MyPlanScreenState extends State<MyPlanScreen> {
  final supabase = Supabase.instance.client;

  List plans = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadPlans();
  }

  Future<void> loadPlans() async {
    try {
      final user = supabase.auth.currentUser;

      final data = await supabase
          .from('meal_plans')
          .select()
          .eq('user_id', user!.id)
          .eq('saved', true)
          .order('created_at', ascending: false);

      setState(() {
        plans = data;
        loading = false;
      });
    } catch (e) {
      debugPrint(e.toString());
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> deletePlan(String id) async {
    try {
      await supabase.rpc(
        'delete_meal_plan',
        params: {'plan_uuid': id},
      );

      await loadPlans();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ลบแพลนเรียบร้อย")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("ลบไม่สำเร็จ: $e")),
      );
    }
  }

  String formatDate(String date) {
    final d = DateTime.parse(date).toLocal();
    return "${d.day}/${d.month}/${d.year + 543}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),
            _buildHeader(context),
            const SizedBox(height: 20),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : plans.isEmpty
                      ? const Center(child: Text("ยังไม่มีแพลนที่บันทึก"))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: plans.length,
                          itemBuilder: (context, index) {
                            final plan = plans[index];
                            return _buildPlanCard(plan);
                          },
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black87),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(dynamic plan) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.blue.withOpacity(0.2),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WeeklyPlanScreen(planId: plan['id']),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan['goal'] ?? "Meal Plan",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _infoRow(
                      Icons.calendar_today_outlined,
                      "สร้างเมื่อ: ${formatDate(plan['created_at'])}",
                    ),
                    _infoRow(
                      Icons.brunch_dining,
                      "${plan['meals_per_day'] ?? '-'} มื้อ / วัน",
                    ),
                    _infoRow(
                      Icons.local_fire_department,
                      "${plan['target_calories'] ?? '-'} kcal / วัน",
                    ),
                    _infoRow(
                      Icons.fitness_center,
                      "Protein ${plan['target_protein'] ?? '-'} g",
                    ),
                    _infoRow(
                      Icons.block,
                      "ข้อจำกัด: ${plan['diet_type'] ?? 'ไม่มี'}",
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: const Color(0xfffff7d0),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text("ลบแพลนอาหาร?"),
                          content: const Text(
                            "เมนูอาหารทั้งหมดในแพลนนี้จะถูกลบด้วย",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text("ยกเลิก"),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                deletePlan(plan['id']);
                              },
                              child: const Text(
                                "ลบ",
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "ลบ",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
              child: const Row(
                children: [
                  CalendarIcon(size: 22),
                  SizedBox(width: 10),
                  Text(
                    "แผนอาหารที่บันทึกไว้",
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
