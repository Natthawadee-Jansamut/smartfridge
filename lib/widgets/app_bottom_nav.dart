import 'package:flutter/material.dart';

import '../screens/main_menu_screen.dart';
import '../screens/scan_menu_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/ai_recipe_screen.dart';
import '../screens/expiration_alert_screen.dart';
import '../screens/plan_menu_screen.dart';
import 'app_icons.dart';

/// แท็บทั้งหมดที่มีอยู่ใน Bottom Navigation ของแอป
/// (อ้างอิงตามดีไซน์ใหม่ใน Figma: หน้าหลัก / สแกน / คลัง / เมนูอาหาร / แจ้งเตือน / แพลน)
enum AppTab { home, scan, inventory, menu, alert, plan }

/// Bottom Navigation Bar กลางของแอป ใช้ร่วมกันทุกหน้าฟังก์ชัน
/// เพื่อให้สลับไปมาระหว่างแท็บได้จริงและมีสไตล์เดียวกันทั้งแอป
/// (ปรับตามดีไซน์ใหม่จาก Figma: พื้นขาว มุมโค้งด้านบน แท็บที่เลือกอยู่มีพื้นหลังสีเหลืองพาสเทล)
class AppBottomNav extends StatelessWidget {
  final AppTab current;

  const AppBottomNav({super.key, required this.current});

  static const Color activeColor = Color(0xFFFFF7D0);

  void _navigate(BuildContext context, AppTab tab) {
    if (tab == current) return;

    final Widget page;
    switch (tab) {
      case AppTab.home:
        page = const MainMenuScreen();
        break;
      case AppTab.scan:
        page = const ScanMenuScreen();
        break;
      case AppTab.inventory:
        page = const InventoryScreen();
        break;
      case AppTab.menu:
        page = const AiRecipeScreen();
        break;
      case AppTab.alert:
        page = const ExpirationAlertScreen();
        break;
      case AppTab.plan:
        page = const PlanMenuScreen();
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _item(context, AppTab.home, const FridgeIcon(size: 24), "หน้าหลัก"),
          _item(context, AppTab.scan, const ScannerIcon(size: 24), "สแกน"),
          _item(context, AppTab.inventory, const ListIcon(size: 24), "คลัง"),
          _item(context, AppTab.menu, const ChefIcon(size: 24), "เมนูอาหาร"),
          _item(context, AppTab.alert, const NotificationIcon(size: 24), "แจ้งเตือน"),
          _item(context, AppTab.plan, const CalendarIcon(size: 24), "แพลน"),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, AppTab tab, Widget iconWidget, String label) {
    final bool active = tab == current;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withOpacity(0.2),
        onTap: () => _navigate(context, tab),
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
