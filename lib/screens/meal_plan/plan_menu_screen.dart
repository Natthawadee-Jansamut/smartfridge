import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/screens/meal_plan/meal_plan_screen.dart'; // หน้าสร้างแพลนใหม่
import 'package:test_app/screens/meal_plan/my_plan_screen.dart'; // หน้าแพลนที่บันทึกไว้
import 'package:test_app/widgets/app_bottom_nav.dart'; // แถบเมนูล่าง
import 'package:test_app/widgets/app_icons.dart'; // ไอคอนที่วาดเอง

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
    return Scaffold( // โครงหน้าจอพื้นฐาน
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลังหน้า (ฟ้าอ่อน)
      bottomNavigationBar: const AppBottomNav(current: AppTab.plan), // แถบเมนูล่าง โดยไฮไลต์แท็บ "แพลน"
      body: SafeArea( // กันเนื้อหาไปทับรอยบาก/แถบสถานะ
        child: Column( // เรียงจากบนลงล่าง
          children: [
            const SizedBox(height: 15), // [UI] ระยะห่างจากขอบบน

            // แถบหัวเรื่อง: แคปซูลสีครีม + ไอคอนปฏิทิน + ปุ่มตัวกรองวงกลม
            // (ตรงกับหน้า root ของแท็บอื่นๆ ในแถบเมนูด้านล่าง)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะห่างซ้าย-ขวา 20
              child: Row(
                children: [
                  Expanded( // ให้แคปซูลยืดเต็มความกว้าง
                    child: Container(
                      height: 50, // [UI] ความสูงแคปซูลหัวเรื่อง
                      padding: const EdgeInsets.symmetric(horizontal: 16), // [UI] ระยะในซ้าย-ขวา
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0), // [UI] สีแคปซูล (ครีมเหลือง)
                        borderRadius: BorderRadius.circular(25), // [UI] โค้ง 25 = ครึ่งความสูง จึงเป็นทรงแคปซูล
                      ),
                      child: const Row(
                        children: [
                          CalendarIcon(size: 22), // [UI] ไอคอนปฏิทิน ขนาด 22
                          SizedBox(width: 10), // [UI] ระยะไอคอนกับข้อความ
                          Text(
                            "แพลนเมนูอาหาร", // ชื่อหน้า
                            style: TextStyle(
                              fontWeight: FontWeight.w500, // [UI] ความหนาปานกลาง
                              fontSize: 16, // [UI] ขนาดตัวอักษร
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25), // [UI] ระยะห่างระหว่างหัวเรื่องกับการ์ด

            Expanded( // ส่วนที่เหลือของจอให้เป็นรายการเลื่อนได้
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้าย-ขวาของรายการ
                children: [
                  // การ์ดที่ 1: ไปหน้าสร้างแพลนใหม่
                  _buildCard(
                    Icons.add, // [UI] ไอคอนบวก
                    "สร้างแพลนอาหาร",
                    "สร้างเมนูอาหารประจำสัปดาห์",
                    () {
                      Navigator.push( // เปิดหน้าใหม่ซ้อนขึ้นไป (กดย้อนกลับมาที่นี่ได้)
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MealPlanScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20), // [UI] ระยะห่างระหว่างการ์ด

                  // การ์ดที่ 2: ไปหน้าแพลนที่เคยบันทึก
                  _buildCard(
                    Icons.calendar_month, // [UI] ไอคอนปฏิทิน
                    "แพลนอาหารที่บันทึกไว้",
                    "ดูแผนอาหารที่เคยสร้างไว้",
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyPlanScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 20), // [UI] ระยะว่างท้ายรายการ
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // สร้างการ์ดเมนู 1 ใบ (ไอคอนวงกลม + หัวข้อ + คำอธิบาย) กดแล้วทำ onTap
  Widget _buildCard(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material( // ต้องมีเพื่อให้เอฟเฟกต์กดแสดง
      color: Colors.transparent,
      child: InkWell( // ทำให้การ์ดกดได้
        borderRadius: BorderRadius.circular(20), // [UI] ขอบเขตเอฟเฟกต์กดโค้งตามการ์ด
        splashColor: Colors.blue.withOpacity(0.2), // [UI] สีคลื่นตอนกด
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20), // [UI] ระยะในการ์ดทุกด้าน 20
          decoration: BoxDecoration(
            color: Colors.white, // [UI] พื้นการ์ดสีขาว
            borderRadius: BorderRadius.circular(20), // [UI] มุมการ์ดโค้ง 20
          ),
          child: Row(
            children: [
              Container( // วงกลมรองไอคอน
                height: 56, // [UI] ขนาดวงกลม
                width: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F0F0), // [UI] สีวงกลม (เทาอ่อน)
                  shape: BoxShape.circle, // [UI] ทรงกลม
                ),
                child: Icon(icon, color: Colors.black87, size: 26), // [UI] ไอคอนขนาด 26
              ),
              const SizedBox(width: 20), // [UI] ระยะวงกลมกับข้อความ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // [UI] ข้อความชิดซ้าย
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18, // [UI] ขนาดหัวข้อการ์ด
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600), // [UI] คำอธิบายสีเทา
                    ),
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
