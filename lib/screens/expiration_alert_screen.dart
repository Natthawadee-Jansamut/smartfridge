import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';
import '../widgets/overdue_notice.dart';
import '../widgets/shelf_days_dialog.dart';
import '../services/fridge_stock.dart';
import '../utils/category_icons.dart';
import '../utils/fridge_age.dart';
import '../utils/shelf_life.dart';
import 'notification_settings_screen.dart';

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

  String selectedCategory = "ทั้งหมด";
  int aheadDays = defaultOldItemDays;

  // ตัวกรอง "อยู่ในตู้เย็นมาแล้ว" แบบช่วงที่ไม่ซ้อนกัน (ของแต่ละชิ้นอยู่ช่อง
  // เดียว): value = วันเริ่ม, max = วันสุดท้าย (null = ไม่มีเพดาน)
  // ยังไม่เลือกช่องไหน (null) = แสดงทั้งหมด กดช่องเดิมซ้ำเพื่อยกเลิกตัวกรอง
  static const List<Map<String, int?>> dayOptions = [
    {'value': 0, 'max': 0},
    {'value': 1, 'max': 2},
    {'value': 3, 'max': 6},
    {'value': 7, 'max': 13},
    {'value': 14, 'max': null},
  ];
  int? selectedDays;

  Map<String, int?>? get _selectedOption => selectedDays == null
      ? null
      : dayOptions.firstWhere((o) => o['value'] == selectedDays);

  String _rangeLabel(Map<String, int?> o) {
    final min = o['value']!;
    final max = o['max'];
    if (max == null) return "$min วันขึ้นไป";
    if (max == min) return "$min วัน";
    return "$min–$max วัน";
  }

  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadItems();
  }

  Future<void> loadItems() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final data = await supabase
        .from('fridge_items')
        .select()
        .eq('user_id', user.id);
    aheadDays = readOldItemDays(user);

    // ของที่ใช้หมดแล้ว (เหลือ 0) ไม่ต้องเตือนอีก เพราะไม่มีของเหลือให้รีบใช้
    final result = data
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .where((item) => item['created_at'] != null && !isUsedUp(item))
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

  List<String> categories() {
    final list = statusItems()
        .map((item) => item['category']?.toString() ?? "อื่นๆ")
        .toSet()
        .toList();
    list.sort();
    return ["ทั้งหมด", ...list];
  }

  // รายการตามตัวกรองจำนวนวัน (ใช้คำนวณหมวดหมู่ที่มีให้เลือกด้วย)
  List<Map<String, dynamic>> statusItems() {
    final option = _selectedOption;
    if (option == null) return items;
    return items.where((i) {
      final days = daysInFridge(i['created_at']);
      final max = option['max'];
      return days >= option['value']! && (max == null || days <= max);
    }).toList();
  }

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

  String _fmtDays(num days) {
    if (days >= 60 && days % 30 == 0) return "${days ~/ 30} เดือน";
    return "${days == days.roundToDouble() ? days.toInt() : days.toStringAsFixed(1)} วัน";
  }

  // สีหลอดนับ (นับเป็นวัน): ครบกำหนด/เกินแล้ว = แดง, เหลือไม่เกินจำนวนวันที่
  // ตั้งแจ้งเตือนไว้ = ส้ม, นอกนั้น = เขียว
  Color _daysLeftColor(int? left) {
    if (left == null) return Colors.grey;
    if (left <= 0) return const Color(0xffD64545);
    if (left <= aheadDays) return const Color(0xffE67E22);
    return const Color(0xff3F9142);
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
            const SizedBox(height: 12),
            buildSettingsButton(context),
            const SizedBox(height: 15),
            buildStatusSelector(),
            const SizedBox(height: 15),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: loadItems,
                      child: buildContent(),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.alert),
    );
  }

  Widget buildHeader(BuildContext context) {
    return Padding(
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
                  NotificationIcon(size: 22),
                  SizedBox(width: 10),
                  Text(
                    "แจ้งเตือนวัตถุดิบ",
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

  Widget buildSettingsButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.black87, width: 1.2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications, color: Colors.black87, size: 18),
                SizedBox(width: 8),
                Text(
                  "ตั้งค่า",
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildStatusSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "อยู่ในตู้เย็นมาแล้ว",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          // ให้ชิปทั้ง 5 อันขยายเท่าๆ กันจนเต็มความกว้างการ์ดพอดี
          Row(
            children: [
              for (int i = 0; i < dayOptions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _buildDayChip(dayOptions[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayChip(Map<String, int?> opt) {
    final value = opt['value']!;
    final selected = selectedDays == value;
    return GestureDetector(
      onTap: () => setState(() {
        selectedDays = selected ? null : value;
        selectedCategory = "ทั้งหมด";
      }),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: Colors.black12),
        ),
        child: Text(
          "$value วัน",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget buildContent() {
    final showItems = filteredItems();
    final option = _selectedOption;
    final label = option == null ? "ทั้งหมด" : "อยู่มา ${_rangeLabel(option)}";

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // สรุปจำนวนรายการ
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                height: 55,
                width: 55,
                decoration: const BoxDecoration(
                  color: Color(0xffE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time,
                  color: Color(0xff5189C9),
                  size: 30,
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
                        fontSize: 16,
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
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          "หมวดหมู่",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 10),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categories().map((cat) {
            final selected = selectedCategory == cat;
            return GestureDetector(
              onTap: () => setState(() => selectedCategory = cat),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFFF7D0) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: selected ? null : Border.all(color: Colors.black12),
                ),
                child: Text(
                  cat == "ทั้งหมด" ? "📦 ทั้งหมด" : "${categoryEmoji(cat)} $cat",
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

        if (showItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                "ไม่มีรายการวัตถุดิบในช่วงนี้",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),

        ...showItems.map(_buildItemCard),
        const SizedBox(height: 20),
      ],
    );
  }

  // การ์ดวัตถุดิบ: ไม่มีป้ายความสด แสดงเป็นหลอดนับ (อยู่มาแล้ว · เก็บได้)
  // ข้อความนับเป็นวัน (เก็บได้อีก X วัน / ครบกำหนดวันนี้ / เกินมาแล้ว X วัน)
  // พร้อมที่มาของตัวเลข และปุ่มแก้ระยะที่เก็บได้
  Widget _buildItemCard(Map<String, dynamic> item) {
    final left = daysLeft(item);
    final color = _daysLeftColor(left);
    final shelf = displayShelfDays(item);
    // หลอดคิดจากตัวเลขเดียวกับข้อความ "เก็บได้อีก X วัน" (วันหมดอายุตามวันใน
    // ปฏิทิน) ผ่านไปแล้ว = เก็บได้ − เก็บได้อีก ทั้งสองอย่างจะขยับไปพร้อมกัน
    final ratio = (shelf == null || left == null)
        ? null
        : ((shelf - left) / shelf).clamp(0.0, 1.0).toDouble();
    final storage = item['storage']?.toString();
    final state = item['food_state']?.toString() ?? '';
    final category = item['category']?.toString() ?? "อื่นๆ";

    String remainingText() => left == null ? "" : daysLeftText(left);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(categoryEmoji(category), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['name'] ?? "ไม่ระบุ",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, color: Colors.black54),
                onPressed: () => deleteItem(item),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shelf == null
                ? fridgeAgeText(item['created_at'])
                : "${fridgeAgeShort(item['created_at'])} · "
                      "เก็บได้ ${_fmtDays(shelf)}",
            style: const TextStyle(
              fontSize: 14,
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
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: Colors.black12,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    remainingText(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // เกินระยะที่เก็บได้แล้ว: บอกคำแนะนำตามชนิดของ (ทิ้ง / ตรวจก่อนใช้)
          if (left != null && left < 0) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OverdueNotice(
                item: item,
                onExtend: (days) => _extend(item, days),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              if (state.isNotEmpty) state,
              "${storageEmoji(storage)} ${storageLabel(storage)}",
              "เข้าตู้เย็น ${formatDate(item['created_at'].toString())} "
                  "${addedTimeText(item['created_at'])}",
            ].join(" · "),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          // ที่มาของ "เก็บได้กี่วัน" แสดงบนการ์ดเลย พร้อมปุ่มแก้เองได้
          Row(
            children: [
              Expanded(
                child: Text(
                  shelfSourceShort(item),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _editShelfDays(item),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
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
      await extendShelfLife(supabase: supabase, item: item, moreDays: days);
      await loadItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${item['name'] ?? 'วัตถุดิบ'} เก็บได้อีก $days วัน")),
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
    final d = parseCreatedAt(date) ?? DateTime.parse(date);
    return "${d.day}/${d.month}/${d.year + 543}";
  }

  // แก้ระยะที่เก็บได้ (หน้าต่างกลาง ใช้ร่วมกับหน้าคลัง)
  Future<void> _editShelfDays(Map<String, dynamic> item) async {
    if (await editShelfDaysDialog(context, item)) await loadItems();
  }

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
    if (confirmed != true || !mounted) return;

    try {
      await supabase.from('fridge_items').delete().eq('item_id', item['item_id']);
      await loadItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบไม่สำเร็จ: $e")));
    }
  }
}
