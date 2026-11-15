import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

// หน้าจอปลายทางของแต่ละแท็บ
import 'package:test_app/screens/home/main_menu_screen.dart';
import 'package:test_app/screens/home/scan_menu_screen.dart';
import 'package:test_app/screens/fridge/inventory_screen.dart';
import 'package:test_app/screens/menu_generator/ai_recipe_screen.dart';
import 'package:test_app/screens/notification/expiration_alert_screen.dart';
import 'package:test_app/screens/meal_plan/plan_menu_screen.dart';
import 'package:test_app/widgets/app_icons.dart'; // ไอคอนที่วาดเอง

/// แท็บทั้งหมดที่มีอยู่ใน Bottom Navigation ของแอป
/// (อ้างอิงตามดีไซน์ใหม่ใน Figma: หน้าหลัก / สแกน / คลัง / เมนูอาหาร / แจ้งเตือน / แพลน)
enum AppTab { home, scan, inventory, menu, alert, plan }

/// Bottom Navigation Bar กลางของแอป ใช้ร่วมกันทุกหน้าฟังก์ชัน
/// เพื่อให้สลับไปมาระหว่างแท็บได้จริงและมีสไตล์เดียวกันทั้งแอป
/// (ปรับตามดีไซน์ใหม่จาก Figma: พื้นขาว มุมโค้งด้านบน แท็บที่เลือกอยู่มีพื้นหลังสีเหลืองพาสเทล)
class AppBottomNav extends StatelessWidget {
  final AppTab current; // แท็บที่กำลังเปิดอยู่ (จะถูกไฮไลต์)

  const AppBottomNav({super.key, required this.current});

  static const Color activeColor = Color(0xFFFFF7D0); // [UI] สีพื้นหลังของแท็บที่เลือกอยู่ (เหลืองพาสเทล)

  // กดแท็บแล้วพาไปหน้านั้น
  void _navigate(BuildContext context, AppTab tab) {
    if (tab == current) return; // กดแท็บเดิมที่อยู่แล้ว ไม่ต้องทำอะไร

    final Widget page; // หน้าที่จะไป
    switch (tab) { // เลือกหน้าตามแท็บที่กด
      case AppTab.home:
        page = const MainMenuScreen(); // หน้าหลัก
        break;
      case AppTab.scan:
        page = const ScanMenuScreen(); // หน้าเลือกสแกน
        break;
      case AppTab.inventory:
        page = const InventoryScreen(); // หน้าคลังตู้เย็น
        break;
      case AppTab.menu:
        page = const AiRecipeScreen(); // หน้าสร้างเมนูด้วย AI
        break;
      case AppTab.alert:
        page = const ExpirationAlertScreen(); // หน้าแจ้งเตือน
        break;
      case AppTab.plan:
        page = const PlanMenuScreen(); // หน้าแพลนอาหาร
        break;
    }

    // เปลี่ยนหน้าแบบแทนที่หน้าเดิม (ไม่ซ้อนหน้า กดย้อนกลับจะไม่วนแท็บเก่า)
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Container( // กล่องแถบเมนูล่าง
      height: 72, // [UI] ความสูงแถบเมนูล่าง
      decoration: const BoxDecoration(
        color: Colors.white, // [UI] พื้นแถบสีขาว
        borderRadius: BorderRadius.only( // [UI] มุมโค้งเฉพาะด้านบน
          topLeft: Radius.circular(24), // [UI] มุมบนซ้ายโค้ง 24
          topRight: Radius.circular(24), // [UI] มุมบนขวาโค้ง 24
        ),
        boxShadow: [ // [UI] เงาของแถบ
          BoxShadow(
            color: Colors.black12, // [UI] สีเงาดำจาง 12%
            blurRadius: 8, // [UI] ความฟุ้งของเงา (มาก = นุ่ม)
            offset: Offset(0, -2), // [UI] เลื่อนเงาขึ้นบน 2 (ค่าลบ = ขึ้น) ให้ดูลอยเหนือเนื้อหา
          ),
        ],
      ),
      child: Row( // เรียงปุ่มแท็บแนวนอน
        mainAxisAlignment: MainAxisAlignment.spaceAround, // [UI] กระจายปุ่มให้ห่างเท่าๆ กัน
        children: [
          // [UI] แต่ละบรรทัด = 1 แท็บ (ไอคอน ขนาด 24 + ชื่อแท็บ) แก้ชื่อ/ไอคอน/ลำดับได้ที่นี่
          _item(context, AppTab.home, const FridgeIcon(size: 24), "หน้าหลัก"),
          _item(context, AppTab.scan, const ScannerIcon(size: 24), "สแกน"),
          _item(context, AppTab.inventory, const ListIcon(size: 24), "คลัง"),
          _item(context, AppTab.menu, const ChefIcon(size: 24), "เมนูอาหาร"),
          _item(
            context,
            AppTab.alert,
            const NotificationIcon(size: 24),
            "แจ้งเตือน",
          ),
          _item(context, AppTab.plan, const CalendarIcon(size: 24), "แพลน"),
        ],
      ),
    );
  }

  // สร้างปุ่มแท็บ 1 ปุ่ม (ไอคอน + ชื่อ)
  Widget _item(
    BuildContext context,
    AppTab tab, // แท็บนี้คืออะไร
    Widget iconWidget, // ไอคอนที่จะแสดง
    String label, // ชื่อใต้ไอคอน
  ) {
    final bool active = tab == current; // แท็บนี้ถูกเลือกอยู่หรือเปล่า
    return Material( // ต้องมี Material ครอบเพื่อให้เอฟเฟกต์คลื่นตอนกดแสดงได้
      color: Colors.transparent, // [UI] โปร่งใส
      child: InkWell( // ทำให้กดได้
        borderRadius: BorderRadius.circular(16), // [UI] ขอบเขตเอฟเฟกต์กดโค้ง 16
        splashColor: Colors.blue.withValues(alpha: 0.2), // [UI] สีคลื่นตอนกด (ฟ้าจาง 20%)
        onTap: () => _navigate(context, tab), // กดแล้วไปหน้านั้น
        child: Container(
          width: 58, // [UI] ความกว้างของแต่ละปุ่มแท็บ
          padding: const EdgeInsets.symmetric(vertical: 8), // [UI] ระยะบน-ล่างในปุ่ม
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent, // [UI] เลือกอยู่ = พื้นเหลือง ไม่เลือก = โปร่งใส
            borderRadius: BorderRadius.circular(16), // [UI] มุมโค้งของพื้นไฮไลต์
          ),
          child: Column( // ไอคอนอยู่บน ชื่ออยู่ล่าง
            mainAxisAlignment: MainAxisAlignment.center, // [UI] จัดกึ่งกลางแนวตั้ง
            children: [
              iconWidget,
              const SizedBox(height: 4), // [UI] ระยะห่างไอคอนกับชื่อ
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10, // [UI] ขนาดชื่อแท็บ
                  fontWeight: FontWeight.w600, // [UI] กึ่งหนา
                  color: Colors.black87, // [UI] ดำเกือบเต็ม
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
