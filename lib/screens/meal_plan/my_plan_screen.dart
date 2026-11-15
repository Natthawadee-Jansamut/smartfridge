import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/screens/meal_plan/weekly_plan_screen.dart'; // หน้าแผนรายสัปดาห์ (เปิดเมื่อกดการ์ด)

import 'package:test_app/widgets/app_bottom_nav.dart'; // แถบเมนูล่าง
import 'package:test_app/widgets/app_icons.dart'; // ไอคอน

// หน้ารายการแพลนอาหารที่ผู้ใช้บันทึกไว้
class MyPlanScreen extends StatefulWidget {
  const MyPlanScreen({super.key});

  @override
  State<MyPlanScreen> createState() => _MyPlanScreenState();
}

class _MyPlanScreenState extends State<MyPlanScreen> {
  final supabase = Supabase.instance.client;

  List plans = []; // แพลนทั้งหมด
  bool loading = true; // กำลังโหลดไหม

  /// id ของแพลนโปรด — มาจากคอลัมน์ meal_plans.is_favorite
  /// (supabase/migrations/20261108000100_meal_plans_is_favorite.sql)
  Set<String> _favorites = {};

  // ดึง id ของแพลนที่เป็นโปรดออกจากข้อมูล
  Set<String> _readFavorites(List data) => {
    for (final p in data)
      if (p['is_favorite'] == true) '${p['id']}',
  };

  // บันทึกสถานะแพลนโปรดลงฐานข้อมูล
  Future<void> _saveFavorite(String id, bool value) => supabase
      .from('meal_plans')
      .update({'is_favorite': value})
      .eq('id', id);

  /// แพลนโปรดขึ้นก่อน แล้วเรียงใหม่ไปเก่า (ข้อมูลเรียงตาม created_at มาแล้ว)
  List _sorted(List data) {
    final fav = [ // กลุ่มแพลนโปรด
      for (final p in data)
        if (_favorites.contains('${p['id']}')) p,
    ];
    final rest = [ // กลุ่มที่เหลือ
      for (final p in data)
        if (!_favorites.contains('${p['id']}')) p,
    ];
    return [...fav, ...rest]; // ต่อกัน (โปรดอยู่บน)
  }

  // กดหัวใจ -> สลับแพลนโปรด
  Future<void> _toggleFavorite(dynamic plan) async {
    final id = '${plan['id']}';
    final before = {..._favorites}; // จำค่าเดิมไว้ (เผื่อบันทึกไม่สำเร็จ)
    final after = {..._favorites};
    final adding = !after.contains(id); // เพิ่มหรือเอาออก
    adding ? after.add(id) : after.remove(id);
    setState(() { // อัปเดตจอทันที
      _favorites = after;
      plans = _sorted(plans);
    });
    try {
      await _saveFavorite(id, adding);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adding ? "เก็บเป็นแพลนโปรดแล้ว ❤️" : "เอาออกจากแพลนโปรดแล้ว",
          ),
          duration: const Duration(seconds: 2), // [UI] แสดงข้อความ 2 วินาที
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { // บันทึกไม่ได้ -> คืนค่าเดิม
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
    loadPlans(); // เปิดหน้ามาก็โหลดแพลน
  }

  // โหลดแพลนที่บันทึกไว้จากฐานข้อมูล
  Future<void> loadPlans() async {
    try {
      final user = supabase.auth.currentUser;

      final data = await supabase
          .from('meal_plans') // ตารางแพลน
          .select()
          .eq('user_id', user!.id) // ของผู้ใช้คนนี้
          .eq('saved', true) // เฉพาะที่กดบันทึกแล้ว
          .order('created_at', ascending: false); // ใหม่สุดก่อน

      _favorites = _readFavorites(data);
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

  // ลบแพลน (พร้อมเมนูทั้งหมดในแพลน)
  Future<void> deletePlan(String id) async {
    try {
      await supabase.rpc('delete_meal_plan', params: {'plan_uuid': id}); // เรียกฟังก์ชัน SQL ลบแพลน
      // is_favorite อยู่ในแถวที่ถูกลบไปแล้ว ไม่ต้องล้างค่าที่อื่น
      await loadPlans(); // โหลดรายการใหม่

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
    final d = DateTime.tryParse(date?.toString() ?? '')?.toLocal(); // แปลงเป็นเวลาไทย
    if (d == null) return '-';
    final hh = d.hour.toString().padLeft(2, '0'); // ชั่วโมง 2 หลัก
    final mm = d.minute.toString().padLeft(2, '0'); // นาที 2 หลัก
    return "${d.day}/${d.month}/${d.year + 543} เวลา $hh:$mm น."; // +543 = แปลงเป็นปี พ.ศ.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15), // [UI] ระยะจากขอบบน
            _buildHeader(context), // หัวหน้า
            const SizedBox(height: 20), // [UI] ระยะหัวกับรายการ
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator()) // กำลังโหลด
                  : plans.isEmpty
                  ? const Center(child: Text("ยังไม่มีแพลนที่บันทึก")) // ไม่มีแพลน
                  : ListView.builder( // รายการแพลน
                      padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
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
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan), // แถบเมนูล่าง
    );
  }

  // แถวข้อมูล 1 บรรทัด (ไอคอน + ข้อความ) บนการ์ดแพลน
  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0), // [UI] ระยะห่างระหว่างแถว
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black87), // [UI] ไอคอนขนาด 18
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Colors.black87), // [UI] ขนาดข้อความ
            ),
          ),
        ],
      ),
    );
  }

  // การ์ดแพลน 1 ใบ
  Widget _buildPlanCard(dynamic plan) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.blue.withValues(alpha: 0.2), // [UI] สีคลื่นตอนกด
        onTap: () { // กดการ์ด -> เปิดแผนรายสัปดาห์
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WeeklyPlanScreen(planId: plan['id']),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 15), // [UI] ระยะห่างใต้การ์ด
          padding: const EdgeInsets.all(20), // [UI] ระยะในการ์ด
          decoration: BoxDecoration(
            color: Colors.white, // [UI] พื้นการ์ด
            borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded( // ฝั่งซ้าย: ข้อมูลแพลน
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan['goal'] ?? "Meal Plan", // ชื่อเป้าหมาย เป็นหัวการ์ด
                            style: const TextStyle(
                              fontSize: 20, // [UI] ขนาดหัวการ์ด
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        IconButton( // ปุ่มหัวใจ
                          visualDensity: VisualDensity.compact, // [UI] ปุ่มแบบกระชับ
                          tooltip: _favorites.contains('${plan['id']}')
                              ? "เลิกเป็นแพลนโปรด"
                              : "เก็บเป็นแพลนโปรด",
                          icon: Icon(
                            _favorites.contains('${plan['id']}')
                                ? Icons.favorite // [UI] หัวใจทึบ
                                : Icons.favorite_border, // [UI] หัวใจโปร่ง
                            color: _favorites.contains('${plan['id']}')
                                ? Colors.redAccent // [UI] แดงเมื่อเป็นโปรด
                                : Colors.black45, // [UI] เทาเมื่อไม่ใช่
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
              Material( // ปุ่มลบด้านขวา
                color: const Color(0xfffff7d0), // [UI] สีพื้นปุ่มลบ (ครีม)
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () { // กดลบ -> ถามยืนยัน
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
                                Navigator.pop(context); // ยกเลิก
                              },
                              child: const Text("ยกเลิก"),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context); // ปิดป๊อปอัป
                                deletePlan(plan['id']); // แล้วลบ
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
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), // [UI] ขนาดปุ่มลบ
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red), // [UI] ไอคอนถังขยะแดง
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

  // หัวหน้า: ปุ่มย้อนกลับ + แคปซูลชื่อหน้า
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
      child: Row(
        children: [
          InkWell( // ปุ่มย้อนกลับ
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.pop(context);
            },
            child: Container(
              height: 45, // [UI] ขนาดปุ่ม 45x45
              width: 45,
              decoration: BoxDecoration(
                color: const Color(0xfffff7d0), // [UI] สีปุ่ม
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: BackIcon(size: 20)), // [UI] ไอคอนย้อนกลับ ขนาด 20
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container( // แคปซูลชื่อหน้า
              height: 50, // [UI] ความสูง
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีแคปซูล
                borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
              ),
              child: const Row(
                children: [
                  CalendarIcon(size: 22),
                  SizedBox(width: 10),
                  Text(
                    "แผนอาหารที่บันทึกไว้",
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
      ),
    );
  }
}
