import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:permission_handler/permission_handler.dart';
import '../services/notification_service.dart';
import '../widgets/app_icons.dart';
import '../utils/fridge_age.dart';

/// หน้า "ตั้งค่า" การแจ้งเตือน (ตามดีไซน์ใน Figma กลุ่ม "ALERT") — เก็บค่า
/// "แจ้งเตือนล่วงหน้ากี่วันก่อนครบอายุการเก็บรักษา" ไว้ใน user_metadata ของ Supabase Auth
/// (แนวทางเดียวกับ first_name/last_name/phone ใน edit_profile_screen.dart)
/// เพื่อไม่ต้องสร้างตารางใหม่หรือขอสิทธิ์ฐานข้อมูลเพิ่ม
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final supabase = Supabase.instance.client;

  static const List<int> options = [1, 3, 7, 14];

  int selected = defaultOldItemDays;
  bool dropdownOpen = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();

    selected = readOldItemDays(supabase.auth.currentUser);
  }

  Future<void> save() async {
    setState(() => saving = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(data: {"notify_days": selected}),
      );

      // ขอสิทธิ์แจ้งเตือนของระบบ (ถ้ายังไม่เคยอนุญาต จะเด้ง permission dialog)
      await NotificationService.init();

      // ตั้งแจ้งเตือนใหม่ทั้งหมดทันทีตามค่าวันที่เพิ่งบันทึกไป
      // (ไม่ต้องรอให้ไปเปิดหน้าคลังก่อนถึงจะซิงก์)
      await NotificationService.scheduleExpiryReminders();

      if (mounted) Navigator.pop(context, selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15),
            buildHeader(context),
            const SizedBox(height: 25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "แจ้งเตือนล่วงหน้าก่อนครบอายุการเก็บรักษา",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  buildDropdown(),
                  const SizedBox(height: 8),
                  const Text(
                    "เช่น ตั้ง 1 วัน: อกไก่ (เก็บได้ 2 วัน) จะเตือนตอนอยู่มา 1 วัน "
                    "ส่วนไข่ (เก็บได้ 21 วัน) จะเตือนตอนอยู่มา 20 วัน",
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  // ปุ่มทดสอบแจ้งเตือน — ใช้เช็กว่าได้รับสิทธิ์แจ้งเตือนแล้ว
                  // จริงไหม และแจ้งเตือนจริงๆ ขึ้นบนเครื่องไหม โดยไม่ต้องรอ
                  // ให้มีวัตถุดิบที่อยู่นานจริงหรือรอถึงเวลาที่ตั้งไว้เลย
                  Center(
                    child: TextButton.icon(
                      onPressed: _testNotification,
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        color: Color(0xff5189C9),
                      ),
                      label: const Text(
                        "ทดสอบการแจ้งเตือนตอนนี้",
                        style: TextStyle(
                          color: Color(0xff5189C9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              // มีการ์ดสีขาวล้อมรอบปุ่ม "ยกเลิก"/"บันทึก" ทั้งคู่ ตามดีไซน์
              // Figma แทนที่จะปล่อยปุ่มลอยอยู่บนพื้นหลังตรงๆ
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(child: buildCancelButton()),
                    const SizedBox(width: 12),
                    Expanded(child: buildSaveButton()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // เช็กสิทธิ์แจ้งเตือนของเครื่องก่อน ถ้ายังไม่ได้อนุญาต จะพาไปหน้าตั้งค่า
  // ของระบบให้เปิดเอง (เพราะแอปขอซ้ำไม่ได้ถ้าผู้ใช้เคยกดปฏิเสธไปแล้ว) ถ้า
  // อนุญาตแล้วจะยิงแจ้งเตือนทดสอบขึ้นทันที ใช้เช็กได้เลยว่าระบบแจ้งเตือน
  // ทำงานจริงหรือเปล่า โดยไม่ต้องรอให้มีของที่อยู่นานจริงหรือรอถึงเวลาที่ตั้งไว้
  Future<void> _testNotification() async {
    final status = await Permission.notification.status;

    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "ยังไม่ได้รับสิทธิ์แจ้งเตือน — กด \"เปิดการตั้งค่า\" แล้วเปิด "
            "อนุญาตการแจ้งเตือนให้แอปนี้",
          ),
          action: SnackBarAction(
            label: "เปิดการตั้งค่า",
            onPressed: openAppSettings,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    await NotificationService.init();
    await NotificationService.showExpiryAlert(
      message: "นี่คือการแจ้งเตือนทดสอบจาก SmartFridge.AI 🔔 ถ้าเห็นข้อความนี้"
          " แปลว่าระบบแจ้งเตือนทำงานถูกต้องแล้ว",
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ส่งแจ้งเตือนทดสอบไปแล้ว ลองปาดแถบด้านบนดู")),
    );
  }

  Widget buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Center(child: BackIcon(size: 24)),
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
                  NotificationIcon(size: 22),
                  SizedBox(width: 10),
                  Text(
                    "ตั้งค่า",
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
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7D0),
              shape: BoxShape.circle,
            ),
            child: const Center(child: FilterIcon(size: 20)),
          ),
        ],
      ),
    );
  }

  Widget buildDropdown() {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => dropdownOpen = !dropdownOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dropdownOpen ? const Color(0xff5189C9) : Colors.black12,
                width: dropdownOpen ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "$selected วัน",
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                Icon(
                  dropdownOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xff5189C9),
                ),
              ],
            ),
          ),
        ),
        if (dropdownOpen)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: options.map((day) {
                final isSelected = day == selected;

                return InkWell(
                  onTap: () => setState(() {
                    selected = day;
                    dropdownOpen = false;
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xffE3F2FD)
                          : Colors.transparent,
                    ),
                    child: Text(
                      "$day วัน",
                      style: TextStyle(
                        fontSize: 15,
                        color: isSelected
                            ? const Color(0xff5189C9)
                            : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget buildCancelButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xffE0E0E0),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text(
          "ยกเลิก",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget buildSaveButton() {
    return SizedBox(
      height: 50,
      // ปุ่มสีฟ้าทุกปุ่มในแอปต้องใช้รหัสสี #D7EDFF ตามที่กำหนด (ตัวหนังสือ/
      // ไอคอนใช้สีดำเพื่อให้อ่านง่ายบนพื้นสีฟ้าอ่อนนี้)
      child: OutlinedButton(
        onPressed: saving ? null : save,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xffD7EDFF),
          side: const BorderSide(color: Color(0xffD7EDFF), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black87,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 18, color: Colors.black87),
                  SizedBox(width: 8),
                  Text(
                    "บันทึก",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
