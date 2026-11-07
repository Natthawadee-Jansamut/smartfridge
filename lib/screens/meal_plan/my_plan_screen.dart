import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/screens/meal_plan/weekly_plan_screen.dart';

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';

class MyPlanScreen extends StatefulWidget {
  const MyPlanScreen({super.key});

  @override
  State<MyPlanScreen> createState() => _MyPlanScreenState();
}

class _MyPlanScreenState extends State<MyPlanScreen> {
  final supabase = Supabase.instance.client;

  List plans = [];
  bool loading = true;

  /// id ของแพลนโปรด — เก็บใน user_metadata ของ Supabase Auth (เหมือนการตั้งค่า
  /// แจ้งเตือน) ไม่ต้องเพิ่มคอลัมน์ในตาราง meal_plans
  static const _favKey = 'favorite_plan_ids';
  Set<String> _favorites = {};

  Set<String> _readFavorites() {
    final raw = supabase.auth.currentUser?.userMetadata?[_favKey];
    return raw is List ? {for (final e in raw) e.toString()} : <String>{};
  }

  Future<void> _saveFavorites(Set<String> ids) =>
      supabase.auth.updateUser(UserAttributes(data: {_favKey: ids.toList()}));

  /// แพลนโปรดขึ้นก่อน แล้วเรียงใหม่ไปเก่า (ข้อมูลเรียงตาม created_at มาแล้ว)
  List _sorted(List data) {
    final fav = [
      for (final p in data)
        if (_favorites.contains('${p['id']}')) p,
    ];
    final rest = [
      for (final p in data)
        if (!_favorites.contains('${p['id']}')) p,
    ];
    return [...fav, ...rest];
  }

  Future<void> _toggleFavorite(dynamic plan) async {
    final id = '${plan['id']}';
    final before = {..._favorites};
    final after = {..._favorites};
    final adding = !after.contains(id);
    adding ? after.add(id) : after.remove(id);
    setState(() {
      _favorites = after;
      plans = _sorted(plans);
    });
    try {
      await _saveFavorites(after);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adding ? "เก็บเป็นแพลนโปรดแล้ว ❤️" : "เอาออกจากแพลนโปรดแล้ว",
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _favorites = before;
        plans = _sorted(plans);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกแพลนโปรดไม่สำเร็จ: $e")));
    }
  }

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

      _favorites = _readFavorites();
      setState(() {
        plans = _sorted(data);
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
      await supabase.rpc('delete_meal_plan', params: {'plan_uuid': id});
      // ลบแพลนโปรด -> เอา id ออกจากรายการโปรดด้วย (ไม่สำเร็จก็ไม่เป็นไร)
      if (_favorites.remove(id)) {
        try {
          await _saveFavorites(_favorites);
        } catch (_) {}
      }

      await loadPlans();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("ลบแพลนเรียบร้อย")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบไม่สำเร็จ: $e")));
    }
  }

  // created_at ใน meal_plans ไม่มีค่าเริ่มต้น แผนเก่าบางแผนจึงเป็น null
  // -> แสดง "-" แทนที่จะทำให้ทั้งหน้าพัง
  String formatDate(Object? date) {
    final d = DateTime.tryParse(date?.toString() ?? '')?.toLocal();
    if (d == null) return '-';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return "${d.day}/${d.month}/${d.year + 543} เวลา $hh:$mm น.";
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan['goal'] ?? "Meal Plan",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _favorites.contains('${plan['id']}')
                              ? "เลิกเป็นแพลนโปรด"
                              : "เก็บเป็นแพลนโปรด",
                          icon: Icon(
                            _favorites.contains('${plan['id']}')
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _favorites.contains('${plan['id']}')
                                ? Colors.redAccent
                                : Colors.black45,
                          ),
                          onPressed: () => _toggleFavorite(plan),
                        ),
                      ],
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
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
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
        ],
      ),
    );
  }
}
