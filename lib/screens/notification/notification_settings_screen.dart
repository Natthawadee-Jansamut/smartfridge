import 'package:flutter/cupertino.dart'; // วงล้อเลือกเวลาแบบ iPhone (CupertinoDatePicker)
import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล/ผู้ใช้

import 'package:test_app/services/notification_service.dart'; // ตั้งแจ้งเตือนใหม่หลังบันทึก
import 'package:test_app/widgets/app_icons.dart'; // ไอคอน
import 'package:test_app/utils/fridge_age.dart'; // ค่าเริ่มต้น/อ่านค่าตั้งค่าแจ้งเตือน

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

  // 0 = เตือนวันที่ครบกำหนดพอดี — ไม่มีค่ามากกว่า 7 เพราะของในตู้เย็นส่วนใหญ่
  // เก็บได้ไม่กี่วัน ตั้งเยอะไปจะเด้งเตือนทันทีตั้งแต่วันที่ซื้อมา
  static const List<int> options = [0, 1, 2, 3, 5, 7]; // [UI] ตัวเลือกจำนวนวันในดรอปดาวน์ (เพิ่ม/ลบตัวเลขได้)

  // ข้อความที่แสดงของแต่ละตัวเลือก
  static String dayLabel(int day) =>
      day == 0 ? "วันที่ครบกำหนด" : "ล่วงหน้า $day วัน";

  int selected = defaultOldItemDays; // ค่าที่เลือกอยู่
  bool dropdownOpen = false; // ดรอปดาวน์เปิดอยู่ไหม
  bool saving = false; // กำลังบันทึกไหม

  /// เวลาที่ต้องการรับแจ้งเตือนในแต่ละวัน (เก็บเป็น notify_time "HH:mm")
  TimeOfDay notifyTime = const TimeOfDay(
    hour: defaultNotifyHour,
    minute: defaultNotifyMinute,
  );

  @override
  void initState() { // ตอนเปิดหน้า: อ่านค่าที่เคยบันทึกมาแสดง
    super.initState();

    final user = supabase.auth.currentUser;
    selected = readOldItemDays(user); // อ่านค่าวันแจ้งเตือนที่บันทึกไว้
    // ค่าเก่าที่ไม่อยู่ในรายการแล้ว (เช่น 14) ปรับเป็นค่าที่ใกล้ที่สุดในรายการ
    if (!options.contains(selected)) {
      selected = options.reduce( // หาตัวเลือกที่ใกล้ที่สุด
        (a, b) => (a - selected).abs() <= (b - selected).abs() ? a : b,
      );
    }
    final t = readNotifyTime(user); // อ่านเวลาแจ้งเตือนที่บันทึกไว้
    notifyTime = TimeOfDay(hour: t.hour, minute: t.minute);
  }

  /// เลือกเวลาแบบง่าย: วงล้อเลื่อนเลือกชั่วโมง/นาที (ทีละ 1 นาที)
  Future<void> _pickNotifyTime() async {
    var draft = notifyTime; // ค่าชั่วคราวระหว่างหมุนวงล้อ
    final picked = await showModalBottomSheet<TimeOfDay>( // เปิดแผ่นเลื่อนขึ้นจากด้านล่างจอ
      context: context,
      backgroundColor: Colors.white, // [UI] สีพื้นแผ่น
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // [UI] มุมบนโค้ง 24
      ),
      builder: (ctx) => StatefulBuilder( // ทำให้แผ่นวาดใหม่ได้ตอนหมุนวงล้อ
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), // [UI] ระยะในแผ่น ซ้าย 20 บน 20 ขวา 20 ล่าง 12
            child: Column(
              mainAxisSize: MainAxisSize.min, // [UI] สูงเท่าเนื้อหา
              crossAxisAlignment: CrossAxisAlignment.stretch, // [UI] ลูกยืดเต็มความกว้าง
              children: [
                const Text(
                  "เลือกเวลารับแจ้งเตือน",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold), // [UI] หัวข้อขนาด 17 ตัวหนา
                ),
                const SizedBox(height: 8),
                // วงล้อเลื่อนชั่วโมง/นาที (แบบ 24 ชม. ทีละ 1 นาที)
                SizedBox(
                  height: 160, // [UI] ความสูงวงล้อ
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time, // โหมดเลือกเวลาเท่านั้น
                    use24hFormat: true, // [UI] แบบ 24 ชั่วโมง
                    initialDateTime: DateTime( // เวลาเริ่มต้นของวงล้อ (วันที่ไม่สำคัญ ใช้แค่ชั่วโมง/นาที)
                      2000,
                      1,
                      1,
                      draft.hour,
                      draft.minute,
                    ),
                    onDateTimeChanged: (d) => setSheet( // หมุนแล้วจำค่าไว้
                      () => draft = TimeOfDay(hour: d.hour, minute: d.minute),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, draft), // กดแล้วปิดแผ่นพร้อมส่งเวลาที่เลือกกลับ
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff5189C9), // [UI] สีปุ่ม (ฟ้า)
                    padding: const EdgeInsets.symmetric(vertical: 14), // [UI] ความสูงปุ่ม (ระยะบนล่าง 14)
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14), // [UI] มุมโค้ง 14
                    ),
                  ),
                  child: Text(
                    "ใช้เวลา ${notifyTimeText(draft.hour, draft.minute)} น.",
                    style: const TextStyle(
                      fontSize: 15, // [UI] ขนาดตัวอักษรปุ่ม
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => notifyTime = picked); // เลือกแล้ว -> อัปเดตเวลา
  }

  // กล่องแสดงเวลาแจ้งเตือน (กดเพื่อเปลี่ยน)
  Widget buildTimePicker() {
    return Material(
      color: Colors.white, // [UI] พื้นขาว
      borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง 15
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: _pickNotifyTime, // กดแล้วเปิดวงล้อ
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), // [UI] ระยะในกล่อง
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Color(0xff5189C9)), // [UI] ไอคอนนาฬิกาสีฟ้า
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "${notifyTimeText(notifyTime.hour, notifyTime.minute)} น. ของทุกวัน",
                  style: const TextStyle(
                    fontSize: 16, // [UI] ขนาดเวลา
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Icon(Icons.edit_outlined, size: 18, color: Colors.black45), // [UI] ไอคอนดินสอ (บอกว่าแก้ได้)
            ],
          ),
        ),
      ),
    );
  }

  // กดบันทึก -> เก็บค่าลงข้อมูลผู้ใช้ แล้วตั้งแจ้งเตือนใหม่
  Future<void> save() async {
    setState(() => saving = true);

    try {
      await supabase.auth.updateUser( // บันทึกลง user_metadata ของ Supabase
        UserAttributes(
          data: {
            "notify_days": selected, // เตือนล่วงหน้ากี่วัน
            "notify_time": notifyTimeText(notifyTime.hour, notifyTime.minute), // เวลาแจ้งเตือน "HH:mm"
          },
        ),
      );

      // ขอสิทธิ์แจ้งเตือนของระบบ (ถ้ายังไม่เคยอนุญาต จะเด้ง permission dialog)
      await NotificationService.init();

      // ตั้งแจ้งเตือนใหม่ทั้งหมดทันทีตามค่าวันที่เพิ่งบันทึกไป
      // (ไม่ต้องรอให้ไปเปิดหน้าคลังก่อนถึงจะซิงก์)
      await NotificationService.scheduleExpiryReminders();

      if (!mounted) return;
      // แจ้งว่าบันทึกสำเร็จ (SnackBar อยู่ระดับแอป จึงยังเห็นหลังกลับไปหน้าก่อน)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "บันทึกการตั้งค่าแล้ว ✅ แจ้งเตือน${dayLabel(selected)} "
            "เวลา ${notifyTimeText(notifyTime.hour, notifyTime.minute)} น.",
          ),
          backgroundColor: Colors.green, // [UI] แถบข้อความสีเขียว = สำเร็จ
        ),
      );
      Navigator.pop(context, selected); // ปิดหน้าตั้งค่า ส่งค่าที่เลือกกลับ
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
      }
    } finally {
      if (mounted) setState(() => saving = false); // บันทึกเสร็จ หยุดโหลด
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง
      // แถบปุ่ม "ยกเลิก"/"บันทึก" ชิดขอบล่างจอ (เหมือนแถบเมนูด้านล่างของหน้าอื่น)
      // เว้นที่ด้านในให้ขีด Home ของ iPhone แทนการลอยอยู่เหนือขอบจอ
      bottomNavigationBar: Container( // แถบปุ่มด้านล่าง
        padding: EdgeInsets.fromLTRB(
          20, // [UI] ซ้าย 20
          16, // [UI] บน 16
          20, // [UI] ขวา 20
          16 + MediaQuery.of(context).padding.bottom, // [UI] ล่าง 16 + ความสูงขีด Home ของ iPhone
        ),
        decoration: const BoxDecoration(
          color: Colors.white, // [UI] พื้นขาว
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // [UI] มุมบนโค้ง 24
          boxShadow: [
            BoxShadow(
              color: Colors.black12, // [UI] สีเงา
              blurRadius: 8, // [UI] ความฟุ้งเงา
              offset: Offset(0, -2), // [UI] เงาเลื่อนขึ้นบน 2
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: buildCancelButton()), // ปุ่มยกเลิก (ครึ่งซ้าย)
            const SizedBox(width: 12), // [UI] ระยะระหว่างสองปุ่ม
            Expanded(child: buildSaveButton()), // ปุ่มบันทึก (ครึ่งขวา)
          ],
        ),
      ),
      body: SafeArea(
        bottom: false, // ไม่เว้นที่ด้านล่าง (แถบปุ่มจัดการเอง)
        child: Column(
          children: [
            const SizedBox(height: 15), // [UI] ระยะจากขอบบน
            buildHeader(context),
            const SizedBox(height: 25), // [UI] ระยะหัวกับเนื้อหา
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "แจ้งเตือนล่วงหน้าก่อนครบอายุการเก็บรักษา",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16, // [UI] ขนาดหัวข้อส่วน
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  buildDropdown(), // ดรอปดาวน์เลือกจำนวนวัน
                  const SizedBox(height: 8),
                  const Text(
                    "เช่น ตั้ง 1 วัน: อกไก่ (เก็บได้ 2 วัน) จะเตือนตอนอยู่มา 1 วัน "
                    "ส่วนไข่ (เก็บได้ 21 วัน) จะเตือนตอนอยู่มา 20 วัน",
                    style: TextStyle(fontSize: 13, color: Colors.black54), // [UI] ข้อความอธิบาย ขนาด 13 สีเทา
                  ),
                  const SizedBox(height: 24), // [UI] ระยะห่างระหว่างสองส่วน
                  const Text(
                    "เวลาที่ต้องการรับแจ้งเตือน",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  buildTimePicker(), // กล่องเลือกเวลา
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // หัวหน้า: ปุ่มย้อนกลับ + แคปซูลชื่อหน้า
  Widget buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 50, // [UI] ขนาดปุ่มย้อนกลับ 50x50
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีครีม
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Center(child: BackIcon(size: 24)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 50, // [UI] ความสูงแคปซูล
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
              ),
              child: const Row(
                children: [
                  NotificationIcon(size: 22),
                  SizedBox(width: 10),
                  Text(
                    "ตั้งค่า",
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

  // ดรอปดาวน์แบบทำเอง: กล่องค่าที่เลือก + รายการตัวเลือก (โผล่เมื่อเปิด)
  Widget buildDropdown() {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => dropdownOpen = !dropdownOpen), // กดสลับเปิด/ปิดรายการ
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), // [UI] ระยะในกล่อง
            decoration: BoxDecoration(
              color: Colors.white, // [UI] พื้นขาว
              borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
              border: Border.all(
                color: dropdownOpen ? const Color(0xff5189C9) : Colors.black12, // [UI] เปิดอยู่ = ขอบฟ้า, ปิด = ขอบเทาจาง
                width: dropdownOpen ? 1.5 : 1, // [UI] เปิดอยู่ขอบหนาขึ้น
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // [UI] ข้อความชิดซ้าย ลูกศรชิดขวา
              children: [
                Text(
                  dayLabel(selected),
                  style: const TextStyle(fontSize: 15, color: Colors.black87), // [UI] ขนาดตัวอักษร
                ),
                Icon(
                  dropdownOpen // [UI] ลูกศรขึ้นเมื่อเปิด ลงเมื่อปิด
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: const Color(0xff5189C9), // [UI] สีลูกศร
                ),
              ],
            ),
          ),
        ),
        if (dropdownOpen) // แสดงรายการเฉพาะตอนเปิด
          Container(
            margin: const EdgeInsets.only(top: 4), // [UI] ห่างจากกล่องด้านบน 4
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12, // [UI] เงาใต้รายการ
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: options.map((day) { // สร้างแถวตัวเลือกจากลิสต์ options
                final isSelected = day == selected; // แถวนี้คือค่าที่เลือกอยู่ไหม

                return InkWell(
                  onTap: () => setState(() { // กดเลือก -> ตั้งค่าแล้วปิดรายการ
                    selected = day;
                    dropdownOpen = false;
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric( // [UI] ระยะในแต่ละแถว
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xffE3F2FD) // [UI] แถวที่เลือกอยู่ = พื้นฟ้าอ่อน
                          : Colors.transparent,
                    ),
                    child: Text(
                      dayLabel(day),
                      style: TextStyle(
                        fontSize: 15,
                        color: isSelected
                            ? const Color(0xff5189C9) // [UI] ตัวอักษรของแถวที่เลือก = ฟ้า
                            : Colors.black87,
                        fontWeight: isSelected // [UI] แถวที่เลือก = ตัวหนา
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

  // ปุ่มยกเลิก (สีเทา)
  Widget buildCancelButton() {
    return SizedBox(
      height: 50, // [UI] ความสูงปุ่ม
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context), // ปิดหน้าโดยไม่บันทึก
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xffE0E0E0), // [UI] สีเทาอ่อน
          elevation: 0, // [UI] ไม่มีเงา
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
          ),
        ),
        child: const Text(
          "ยกเลิก",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ปุ่มบันทึก (สีฟ้าอ่อน)
  Widget buildSaveButton() {
    return SizedBox(
      height: 50, // [UI] ความสูงปุ่ม
      // ปุ่มสีฟ้าทุกปุ่มในแอปต้องใช้รหัสสี #D7EDFF ตามที่กำหนด (ตัวหนังสือ/
      // ไอคอนใช้สีดำเพื่อให้อ่านง่ายบนพื้นสีฟ้าอ่อนนี้)
      child: OutlinedButton(
        onPressed: saving ? null : save, // กำลังบันทึก = กดไม่ได้
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xffD7EDFF), // [UI] สีพื้นปุ่ม (ฟ้าอ่อน #D7EDFF)
          side: const BorderSide(color: Color(0xffD7EDFF), width: 1.2), // [UI] เส้นขอบสีเดียวกับพื้น หนา 1.2
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: saving
            ? const SizedBox(
                height: 20, // [UI] ขนาดวงหมุนระหว่างบันทึก
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
                  Icon(Icons.check, size: 18, color: Colors.black87), // [UI] ไอคอนติ๊กถูก
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
