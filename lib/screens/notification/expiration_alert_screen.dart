import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/overdue_notice.dart'; // กล่องเตือนของเกินกำหนด
import 'package:test_app/widgets/shelf_days_dialog.dart'; // หน้าต่างแก้ระยะเก็บ
import 'package:test_app/services/fridge_stock.dart'; // ต่อเวลา
import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/screens/notification/notification_settings_screen.dart'; // หน้าตั้งค่าแจ้งเตือน

/// หน้า "แจ้งเตือน" วัตถุดิบ (ตามดีไซน์ใน Figma กลุ่ม "ALERT") — กรองตามจำนวน
/// วันที่อยู่ในตู้เย็น (0 / 1 / 3 / 7 / 14 วัน) และทุกการ์ดแสดงตัวเลขที่ใช้ตัดสิน (อยู่มาแล้วกี่วัน เทียบกับ
/// เก็บได้กี่วัน) พร้อมที่มาของตัวเลข เพื่อให้ผู้ใช้เห็นเหตุผลเองและเชื่อถือได้
/// เป็นหน้า root ของแท็บ "แจ้งเตือน" ในแถบเมนูด้านล่าง จึงไม่มีปุ่มย้อนกลับ
class ExpirationAlertScreen extends StatefulWidget {
  const ExpirationAlertScreen({super.key});

  @override
  State<ExpirationAlertScreen> createState() => _ExpirationAlertScreenState();
}

class _ExpirationAlertScreenState extends State<ExpirationAlertScreen> {
  final supabase = Supabase.instance.client;

  String selectedCategory = "ทั้งหมด"; // หมวดหมู่ที่เลือกอยู่
  int aheadDays = defaultOldItemDays; // เตือนล่วงหน้ากี่วัน (อ่านจากตั้งค่าผู้ใช้)

  // ตัวกรอง "อยู่ในตู้เย็นมาแล้ว" แบบช่วงที่ไม่ซ้อนกัน (ของแต่ละชิ้นอยู่ช่อง
  // เดียว): value = วันเริ่ม, max = วันสุดท้าย (null = ไม่มีเพดาน)
  // ยังไม่เลือกช่องไหน (null) = แสดงทั้งหมด กดช่องเดิมซ้ำเพื่อยกเลิกตัวกรอง
  static const List<Map<String, int?>> dayOptions = [ // [UI] ช่วงวันของชิปตัวกรอง (แก้ช่วงได้ที่นี่)
    {'value': 0, 'max': 0},
    {'value': 1, 'max': 2},
    {'value': 3, 'max': 6},
    {'value': 7, 'max': 13},
    {'value': 14, 'max': null},
  ];
  int? selectedDays; // ช่วงวันที่เลือกอยู่ (null = ทั้งหมด)

  Map<String, int?>? get _selectedOption => selectedDays == null // ข้อมูลช่วงที่เลือก
      ? null
      : dayOptions.firstWhere((o) => o['value'] == selectedDays);

  // ข้อความช่วงวัน เช่น "1–2 วัน"
  String _rangeLabel(Map<String, int?> o) {
    final min = o['value']!;
    final max = o['max'];
    if (max == null) return "$min วันขึ้นไป";
    if (max == min) return "$min วัน";
    return "$min–$max วัน";
  }

  List<Map<String, dynamic>> items = []; // ของในตู้ทั้งหมด
  bool loading = true; // กำลังโหลดไหม

  @override
  void initState() {
    super.initState();
    loadItems(); // เปิดหน้ามาโหลดข้อมูล
  }

  // ดึงของในตู้จากฐานข้อมูล
  Future<void> loadItems() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final data = await supabase // ดึงของในตู้ของผู้ใช้
        .from('fridge_items')
        .select()
        .eq('user_id', user.id);
    aheadDays = readOldItemDays(user); // อ่านค่าเตือนล่วงหน้า

    // ของที่ใช้หมดแล้ว (เหลือ 0) ไม่ต้องเตือนอีก เพราะไม่มีของเหลือให้รีบใช้
    final result =
        data
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            // (ของเก่าที่ไม่มีวันที่เข้าตู้เย็น ยังแสดงอยู่ นับเป็นเพิ่งใส่)
            .where((item) => !isUsedUp(item))
            .toList()
          // เหลือวันน้อยที่สุดขึ้นก่อน ตรงกับ "เหลืออีก X วัน" บนหลอดนับของการ์ด
          ..sort(compareDaysLeft);

    if (mounted) {
      setState(() {
        items = result;
        loading = false;
      });
    }
  }

  // รายชื่อหมวดหมู่ที่มีของอยู่ (ใส่ "ทั้งหมด" ไว้หน้าสุด)
  List<String> categories() {
    final list = statusItems()
        .map((item) => item['category']?.toString() ?? "อื่นๆ")
        .toSet()
        .toList();
    list.sort(); // เรียงตามตัวอักษร
    return ["ทั้งหมด", ...list];
  }

  // รายการตามตัวกรองจำนวนวัน (ใช้คำนวณหมวดหมู่ที่มีให้เลือกด้วย)
  List<Map<String, dynamic>> statusItems() {
    final option = _selectedOption;
    if (option == null) return items; // ไม่ได้เลือกช่วง = ทุกชิ้น
    return items.where((i) {
      final days = daysInFridge(i['created_at']); // อยู่ในตู้มากี่วัน
      final max = option['max'];
      return days >= option['value']! && (max == null || days <= max); // อยู่ในช่วงที่เลือก
    }).toList();
  }

  // กรองตามหมวดหมู่ซ้ำอีกชั้น
  List<Map<String, dynamic>> filteredItems() {
    final list = statusItems();
    if (selectedCategory == "ทั้งหมด") return list;
    return list
        .where(
          (item) =>
              (item['category']?.toString() ?? "อื่นๆ") == selectedCategory,
        )
        .toList();
  }

  // แปลงวันเป็นข้อความ (60 วันขึ้นไปที่หาร 30 ลงตัว = เดือน)
  String _fmtDays(num days) {
    if (days >= 60 && days % 30 == 0) return "${days ~/ 30} เดือน";
    return "${days == days.roundToDouble() ? days.toInt() : days.toStringAsFixed(1)} วัน";
  }

  // สีหลอดนับ (นับเป็นวัน): ครบกำหนด/เกินแล้ว = แดง, เหลือไม่เกินจำนวนวันที่
  // ตั้งแจ้งเตือนไว้ = ส้ม, นอกนั้น = เขียว
  Color _daysLeftColor(int? left) {
    if (left == null) return Colors.grey; // ไม่มีข้อมูล = เทา
    if (left <= 0) return const Color(0xffD64545); // [UI] ครบ/เกินกำหนด = แดง
    if (left <= aheadDays) return const Color(0xffE67E22); // [UI] ถึงช่วงเตือน = ส้ม
    return const Color(0xff3F9142); // [UI] ยังอีกนาน = เขียว
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 15), // [UI] ระยะจากขอบบน
            buildHeader(context), // หัวหน้า
            const SizedBox(height: 12),
            buildSettingsButton(context), // ปุ่มตั้งค่า
            const SizedBox(height: 15),
            buildStatusSelector(), // ชิปเลือกช่วงวัน
            const SizedBox(height: 15),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator()) // กำลังโหลด
                  : RefreshIndicator( // ดึงลงเพื่อรีเฟรช
                      onRefresh: loadItems,
                      child: buildContent(),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.alert), // แถบเมนูล่าง ไฮไลต์ "แจ้งเตือน"
    );
  }

  // หัวหน้า: แคปซูลชื่อหน้า
  Widget buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50, // [UI] ความสูง
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีครีม
                borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
              ),
              child: const Row(
                children: [
                  NotificationIcon(size: 22), // [UI] ไอคอนกระดิ่ง
                  SizedBox(width: 10),
                  Text(
                    "แจ้งเตือนวัตถุดิบ",
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

  // ปุ่ม "ตั้งค่า" ชิดขวา
  Widget buildSettingsButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerRight, // [UI] ชิดขวา
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: () {
            Navigator.push( // เปิดหน้าตั้งค่าแจ้งเตือน
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // [UI] ระยะในปุ่ม
            decoration: BoxDecoration(
              color: Colors.white, // [UI] พื้นขาว
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.black87, width: 1.2), // [UI] ขอบดำหนา 1.2
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications, color: Colors.black87, size: 18), // [UI] ไอคอนกระดิ่ง ขนาด 18
                SizedBox(width: 8),
                Text(
                  "ตั้งค่า",
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14, // [UI] ขนาดตัวอักษร
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // กล่องชิปเลือกช่วงวัน
  Widget buildStatusSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะห่างซ้ายขวาจากขอบจอ
      padding: const EdgeInsets.all(18), // [UI] ระยะในกล่อง
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "อยู่ในตู้เย็นมาแล้ว",
            style: TextStyle(
              fontSize: 16, // [UI] ขนาดหัวข้อ
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          // ชิป "ทั้งหมด" + ชิปช่วงวันทั้ง 5 อัน ขยายเท่าๆ กันจนเต็มความกว้างการ์ด
          Row(
            children: [
              Expanded(flex: 2, child: _buildDayChip(null)), // [UI] ชิป "ทั้งหมด" กว้าง 2 ส่วน
              for (final opt in dayOptions) ...[
                const SizedBox(width: 6), // [UI] ระยะห่างระหว่างชิป
                Expanded(flex: 1, child: _buildDayChip(opt)), // [UI] ชิปช่วงวันกว้าง 1 ส่วน
              ],
            ],
          ),
        ],
      ),
    );
  }

  // opt == null คือชิป "ทั้งหมด" (ล้างตัวกรองจำนวนวัน)
  Widget _buildDayChip(Map<String, int?>? opt) {
    final value = opt?['value'];
    final selected = selectedDays == value; // ชิปนี้ถูกเลือกอยู่ไหม
    return GestureDetector(
      onTap: () => setState(() {
        selectedDays = (selected || value == null) ? null : value; // กดซ้ำ/กด "ทั้งหมด" = ยกเลิกตัวกรอง
        selectedCategory = "ทั้งหมด"; // เปลี่ยนช่วงแล้วรีเซ็ตหมวดหมู่
      }),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9), // [UI] ความสูงชิป (ระยะบนล่าง 9)
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white, // [UI] เลือกอยู่ = ครีม ไม่เลือก = ขาว
          borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
          border: selected ? null : Border.all(color: Colors.black12), // [UI] ไม่เลือก = มีขอบเทาจาง
        ),
        child: Text(
          value == null ? "ทั้งหมด" : "$value วัน",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5, // [UI] ขนาดตัวอักษรชิป
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget buildContent() {
    final showItems = filteredItems(); // รายการที่จะแสดง
    final option = _selectedOption;
    final label = option == null ? "ทั้งหมด" : "อยู่มา ${_rangeLabel(option)}";

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
      children: [
        // สรุปจำนวนรายการ
        Container(
          padding: const EdgeInsets.all(18), // [UI] ระยะในกล่องสรุป
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                height: 55, // [UI] ขนาดวงกลมไอคอน
                width: 55,
                decoration: const BoxDecoration(
                  color: Color(0xffE3F2FD), // [UI] สีวงกลม (ฟ้าอ่อน)
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time,
                  color: Color(0xff5189C9),
                  size: 30, // [UI] ไอคอนนาฬิกา ขนาด 30
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16, // [UI] ขนาดหัวข้อสรุป
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      "${showItems.length} รายการ",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Text(
                "${showItems.length}",
                style: const TextStyle(
                  fontSize: 32, // [UI] ตัวเลขใหญ่ ขนาด 32
                  fontWeight: FontWeight.bold,
                  color: Colors.orange, // [UI] สีส้ม
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          "หมวดหมู่",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // [UI] ขนาดหัวข้อหมวดหมู่
        ),

        const SizedBox(height: 10),

        Wrap( // ชิปหมวดหมู่ (ตกบรรทัดได้)
          spacing: 10, // [UI] ระยะห่างแนวนอน
          runSpacing: 10, // [UI] ระยะห่างแนวตั้ง
          children: categories().map((cat) {
            final selected = selectedCategory == cat;
            return GestureDetector(
              onTap: () => setState(() => selectedCategory = cat), // กดเลือกหมวด
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, // [UI] ระยะในชิปซ้ายขวา
                  vertical: 10, // [UI] ระยะในชิปบนล่าง
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFFF7D0) : Colors.white, // [UI] เลือกอยู่ = ครีม
                  borderRadius: BorderRadius.circular(20),
                  border: selected ? null : Border.all(color: Colors.black12),
                ),
                child: Text(
                  cat == "ทั้งหมด"
                      ? "📦 ทั้งหมด"
                      : "${categoryEmoji(cat)} $cat",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 15),

        if (showItems.isEmpty) // ไม่มีรายการ
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40), // [UI] ระยะบนล่างของข้อความว่าง
            child: Center(
              child: Text(
                "ไม่มีรายการวัตถุดิบในช่วงนี้",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),

        ...showItems.map(_buildItemCard), // การ์ดวัตถุดิบทีละชิ้น
        const SizedBox(height: 20),
      ],
    );
  }

  // การ์ดวัตถุดิบ: ไม่มีป้ายความสด แสดงเป็นหลอดนับ (อยู่มาแล้ว · เก็บได้)
  // ข้อความนับเป็นวัน (เก็บได้อีก X วัน / ครบกำหนดวันนี้ / เกินมาแล้ว X วัน)
  // พร้อมที่มาของตัวเลข และปุ่มแก้ระยะที่เก็บได้
  Widget _buildItemCard(Map<String, dynamic> item) {
    final left = daysLeft(item); // เหลืออีกกี่วัน
    final color = _daysLeftColor(left); // สีตามจำนวนวัน
    final shelf = displayShelfDays(item); // เก็บได้ทั้งหมดกี่วัน
    // หลอดคิดจากตัวเลขเดียวกับข้อความ "เก็บได้อีก X วัน" (วันหมดอายุตามวันใน
    // ปฏิทิน) ผ่านไปแล้ว = เก็บได้ − เก็บได้อีก ทั้งสองอย่างจะขยับไปพร้อมกัน
    final ratio = (shelf == null || left == null) // สัดส่วนที่ผ่านไปแล้ว (0-1) สำหรับหลอด
        ? null
        : ((shelf - left) / shelf).clamp(0.0, 1.0).toDouble();
    final storage = item['storage']?.toString(); // ช่องที่เก็บ
    final state = item['food_state']?.toString() ?? ''; // สถานะ (ดิบ/สุก ฯลฯ)
    final category = item['category']?.toString() ?? "อื่นๆ";

    String remainingText() => left == null ? "" : daysLeftText(left);

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // [UI] ระยะใต้การ์ด
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14), // [UI] ระยะในการ์ด
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                categoryEmoji(category),
                style: const TextStyle(fontSize: 28), // [UI] อิโมจิขนาด 28
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['name'] ?? "ไม่ระบุ",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17, // [UI] ขนาดชื่อวัตถุดิบ
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact, // [UI] ปุ่มกระชับ
                icon: const Icon(Icons.delete_outline, color: Colors.black54), // [UI] ไอคอนถังขยะสีเทา
                onPressed: () => deleteItem(item), // กดลบ
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shelf == null // ไม่มีข้อมูลระยะเก็บ -> บอกแค่อยู่มากี่วัน
                ? fridgeAgeText(item['created_at'])
                : "${fridgeAgeShort(item['created_at'])} · "
                      "เก็บได้ ${_fmtDays(shelf)}",
            style: const TextStyle(
              fontSize: 14, // [UI] ขนาดข้อความ
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (ratio != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4), // [UI] หลอดโค้ง
                      child: LinearProgressIndicator( // หลอดแสดงเวลาที่ผ่านไป
                        value: ratio,
                        minHeight: 8, // [UI] ความหนาหลอด
                        backgroundColor: Colors.black12, // [UI] สีพื้นหลอด
                        color: color, // [UI] สีหลอด (แดง/ส้ม/เขียว)
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    remainingText(),
                    style: TextStyle(
                      fontSize: 12, // [UI] ขนาดข้อความวันที่เหลือ
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // เกินระยะที่เก็บได้แล้ว: บอกคำแนะนำตามชนิดของ (ทิ้ง / ตรวจก่อนใช้)
          if (left != null && left < 0) ...[ // เกินกำหนดแล้วเท่านั้นถึงแสดงกล่องเตือน
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OverdueNotice(
                item: item,
                onExtend: (days) => _extend(item, days), // กด +N วัน -> ต่อเวลา
              ),
            ),
          ],
          const SizedBox(height: 8),
          // วันที่และเวลาที่เอาเข้าตู้เย็น แสดงทุกการ์ดเป็นบรรทัดของตัวเอง
          // ของที่ไม่มี created_at (เพิ่มจากที่อื่นที่ไม่ได้ใส่วันที่) บอกให้รู้ว่าไม่ทราบ
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 15, // [UI] ไอคอนนาฬิกา ขนาด 15
                color: Colors.black54,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  parseCreatedAt(item['created_at']) == null
                      ? "ไม่ทราบวันที่เข้าตู้เย็น"
                      : "เข้าตู้เย็นเมื่อ ${formatDate(item['created_at'].toString())} "
                            "เวลา ${addedTimeText(item['created_at'])}",
                  style: const TextStyle(
                    fontSize: 13, // [UI] ขนาดข้อความ
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (state.isNotEmpty) state,
              "${storageEmoji(storage)} ${storageLabel(storage)}", // ช่องที่เก็บ เช่น "🧊 ช่องปกติ"
            ].join(" · "),
            style: const TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
          ),
          // ที่มาของ "เก็บได้กี่วัน" แสดงบนการ์ดเลย พร้อมปุ่มแก้เองได้
          Row(
            children: [
              Expanded(
                child: Text(
                  shelfSourceShort(item), // ที่มาของตัวเลข
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact, // [UI] ปุ่มกระชับ
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _editShelfDays(item), // กดแก้ระยะเก็บ
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16, // [UI] ไอคอนดินสอ ขนาด 16 สีฟ้า
                  color: Color(0xff5189C9),
                ),
                label: const Text(
                  "แก้",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xff5189C9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ผู้ใช้ตรวจแล้วว่ายังใช้ได้ ต่อเวลาให้ "เก็บได้อีก X วัน" (ดู extendShelfLife)
  Future<void> _extend(Map<String, dynamic> item, int days) async {
    try {
      await extendShelfLife(supabase: supabase, item: item, moreDays: days); // ต่อเวลาในฐานข้อมูล
      await loadItems(); // โหลดใหม่
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${item['name'] ?? 'วัตถุดิบ'} เก็บได้อีก $days วัน"),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
    }
  }

  // created_at จาก Supabase เป็นเวลา UTC ที่ไม่มีตัวบอก timezone ต้องแปลงผ่าน
  // parseCreatedAt ก่อน ไม่งั้นวันที่จะเพี้ยนไป 7 ชั่วโมง
  String formatDate(String date) {
    final d = parseCreatedAt(date) ?? DateTime.parse(date); // แปลงเวลา UTC เป็นเวลาไทย
    return "${d.day}/${d.month}/${d.year + 543}"; // +543 = ปี พ.ศ.
  }

  // แก้ระยะที่เก็บได้ (หน้าต่างกลาง ใช้ร่วมกับหน้าคลัง)
  Future<void> _editShelfDays(Map<String, dynamic> item) async {
    if (await editShelfDaysDialog(context, item)) await loadItems(); // บันทึกแล้วโหลดใหม่
  }

  // ลบวัตถุดิบ (ถามยืนยันก่อน)
  Future<void> deleteItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("ลบวัตถุดิบ?"),
        content: Text(
          "ต้องการลบ \"${item['name'] ?? 'วัตถุดิบนี้'}\" ออกจากตู้เย็นใช่หรือไม่?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("ลบ", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return; // ไม่ยืนยัน หยุด

    try {
      await supabase
          .from('fridge_items')
          .delete() // ลบออกจากฐานข้อมูล
          .eq('item_id', item['item_id']);
      await loadItems(); // โหลดใหม่
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบไม่สำเร็จ: $e")));
    }
  }
}
