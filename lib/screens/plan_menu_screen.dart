import 'package:flutter/material.dart';

import 'meal_plan_screen.dart';
import 'my_plan_screen.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';

/// หน้า "แพลนเมนูอาหาร" (ตามดีไซน์ใน Figma: กลุ่ม "PLANNING" เฟรมแรก)
/// เป็นหน้า root ของแท็บ "แพลน" ในแถบเมนูด้านล่าง จึงไม่มีปุ่มย้อนกลับ
/// (แก้จากของเดิมที่มีปุ่มย้อนกลับผิดๆ เหมือนบัคที่เจอในหน้าอื่นก่อนหน้านี้)
class PlanMenuScreen extends StatefulWidget {
  const PlanMenuScreen({super.key});

  @override
  State<PlanMenuScreen> createState() => _PlanMenuScreenState();
}

class _PlanMenuScreenState extends State<PlanMenuScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),

            // แถบหัวเรื่อง: แคปซูลสีครีม + ไอคอนปฏิทิน + ปุ่มตัวกรองวงกลม
            // (ตรงกับหน้า root ของแท็บอื่นๆ ในแถบเมนูด้านล่าง)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
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
                            "แพลนเมนูอาหาร",
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
            ),

            const SizedBox(height: 25),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildCard(
                    Icons.add,
                    "สร้างแพลนอาหาร",
                    "สร้างเมนูอาหารประจำสัปดาห์",
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MealPlanScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  _buildCard(
                    Icons.calendar_month,
                    "แพลนอาหารที่บันทึกไว้",
                    "ดูแผนอาหารที่เคยสร้างไว้",
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MyPlanScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.blue.withOpacity(0.2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F0F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.black87, size: 26),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
