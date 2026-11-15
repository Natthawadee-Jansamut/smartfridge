import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล
import 'package:test_app/screens/fridge/item_detail_screen.dart'; // หน้ารายละเอียดวัตถุดิบ
import 'package:test_app/screens/ingredient_scan/image_scanning_screen.dart'; // หน้าสแกนวัตถุดิบ
import 'package:test_app/screens/ingredient_scan/result_screen.dart'; // หน้ากรอกวัตถุดิบ
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/widgets/overdue_notice.dart'; // กล่องเตือนของเกินกำหนด
import 'package:test_app/widgets/shelf_days_dialog.dart'; // หน้าต่างแก้ระยะเก็บ
import 'package:test_app/services/fridge_stock.dart'; // ต่อเวลา
import 'package:test_app/services/notification_service.dart'; // ตั้งแจ้งเตือนใหม่

// หน้า "คลัง" ตู้เย็น: ดูของตามหมวดหมู่ ค้นหา ปรับจำนวน ลบ
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String? _selectedCategory; // หมวดหมู่ที่เปิดดูอยู่ (null = หน้ารวมหมวดหมู่)
  List<Map<String, dynamic>> _inventoryItems = []; // ของในตู้ทั้งหมด
  bool _isLoading = true; // กำลังโหลดไหม

  // ช่องค้นหาวัตถุดิบด้านบน — เดิมเป็นแค่ TextField เปล่าๆ พิมพ์แล้วไม่มีอะไร
  // เกิดขึ้นเลย ตอนนี้ผูกกับ state จริง พิมพ์แล้วต้องกรองรายการวัตถุดิบจริง
  // จากคลังให้ขึ้นมา
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = ''; // คำค้นหาปัจจุบัน

  @override
  void initState() {
    super.initState();
    _fetchInventoryData(); // เปิดหน้ามาโหลดของในตู้
  }

  @override
  void dispose() {
    _searchController.dispose(); // ปิดหน้า คืนหน่วยความจำช่องค้นหา
    super.dispose();
  }

  // ดึงของในตู้ทั้งหมดจากฐานข้อมูล
  Future<void> _fetchInventoryData() async {
    setState(() => _isLoading = true); // เริ่มโหลด
    try {
      final response = await Supabase.instance.client
          .from('fridge_items')
          .select()
          .order(
            'item_id',
            ascending: false,
          ); // เรียงตาม item_id ที่มีในฐานข้อมูล

      // เรียงแบบ FIFO: ลอตที่ใกล้หมดอายุ/เก่าที่สุดขึ้นก่อนในแต่ละหมวดหมู่
      final items = List<Map<String, dynamic>>.from(response)
        ..sort(compareFifo); // เรียงแบบ FIFO (ใกล้หมดอายุก่อน)

      setState(() {
        _inventoryItems = items;
      });

      // ทุกครั้งที่โหลด/รีเฟรชคลัง ให้ซิงก์แจ้งเตือนวันหมดอายุใหม่ให้ตรงกับ
      // ของจริงในคลังตอนนี้ (ของที่ถูกลบ/ทำอาหารไปแล้วจะไม่มีแจ้งเตือนค้าง
      // ของที่เพิ่มใหม่จะได้ตั้งแจ้งเตือนให้ด้วย) ทำแบบไม่ต้องรอ (fire-and-
      // forget) จะได้ไม่ทำให้หน้าคลังโหลดช้าลง
      NotificationService.scheduleExpiryReminders().catchError((_) {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("เกิดข้อผิดพลาดในการดึงข้อมูล: $e"),
            backgroundColor: Colors.red, // [UI] แถบสีแดง
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false); // โหลดเสร็จ
    }
  }

  // ลบวัตถุดิบ 1 ชิ้นแล้วโหลดใหม่
  Future<void> _deleteItem(String id) async {
    try {
      await Supabase.instance.client
          .from('fridge_items')
          .delete()
          .eq('item_id', id); // อ้างอิงตาม item_id
      _fetchInventoryData(); // โหลดรายการใหม่
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบข้อมูลไม่สำเร็จ: $e")));
    }
  }

  // ใช้ mapping กลางจาก utils/category_icons.dart (หน้านี้คือต้นแบบที่หน้าอื่น
  // ต้องอ้างอิงตาม เพื่อไม่ให้ชุดอิโมจิหมวดหมู่เพี้ยนไปคนละหน้า)
  String _getCategoryIcon(String category) => categoryEmoji(category);

  num _toNum(dynamic v) => // แปลงค่าเป็นตัวเลข
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  String _formatQty(num v) => // แสดงตัวเลข: จำนวนเต็มไม่มีทศนิยม, ไม่งั้น 1 ตำแหน่ง
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ปรับลด/เพิ่มปริมาณคงเหลือเองแบบ Manual (Manual Override) ให้ตรงกับของจริง
  // ถ้าลดจนเหลือ 0 จะถามก่อนว่าจะลบลอตนี้ออกจากตู้เย็นเลยไหม
  Future<void> _adjustQuantity(Map<String, dynamic> item, num delta) async {
    final id = item['item_id'].toString(); // id ของชิ้นนี้
    final current = _toNum(item['quantity']); // จำนวนตอนนี้
    num next = current + delta; // จำนวนใหม่
    if (next < 0) next = 0; // ไม่ให้ติดลบ

    if (next <= 0) { // ลดจนเหลือ 0 -> ถามว่าจะลบทิ้งไหม
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("ใช้หมดแล้ว?"),
          content: Text("ลบ ${item['name'] ?? 'วัตถุดิบ'} ออกจากตู้เย็นเลยไหม"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("ยกเลิก"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("ลบ", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm == true) await _deleteItem(id); // ยืนยัน -> ลบ
      return;
    }

    // ปุ่ม + ใช้คืนจำนวนที่กดลดไป (เช่นกดลบผิด) ได้ไม่เกินปริมาณทั้งหมดตอนเก็บ
    // ไม่ไปเพิ่ม "ทั้งหมด" ให้เอง — ถ้าซื้อมาเพิ่มจริงควรสแกนเป็นลอตใหม่ ส่วน
    // ถ้าจำนวนตั้งต้นผิด ให้แก้ "ทั้งหมด" ในหน้ารายละเอียด
    final maxQty = _toNum(item['max_quantity']); // จำนวนสูงสุดตอนเก็บเข้าตู้
    if (maxQty > 0 && next > maxQty) { // เกินจำนวนตอนเก็บ -> ไม่ให้เพิ่ม แจ้งเตือนแทน
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${item['name'] ?? 'วัตถุดิบ'} มีครบ ${_formatQty(maxQty)} "
            "${item['unit'] ?? ''} แล้ว — ถ้าซื้อมาเพิ่มให้สแกนเป็นลอตใหม่ "
            "หรือแก้จำนวนทั้งหมดในหน้ารายละเอียด",
          ),
        ),
      );
      return;
    }

    final update = <String, dynamic>{'quantity': next}; // ค่าที่จะบันทึก
    setState(() => item['quantity'] = next); // อัปเดตหน้าจอทันที (ไม่ต้องรอฐานข้อมูล)

    try {
      await Supabase.instance.client
          .from('fridge_items')
          .update(update) // บันทึกลงฐานข้อมูล
          .eq('item_id', id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ปรับจำนวนไม่สำเร็จ: $e")));
      _fetchInventoryData(); // บันทึกไม่ได้ -> โหลดของจริงกลับมา
      return;
    }

    // กดผิดก็กด "เลิกทำ" คืนค่าเดิมได้ทันที
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${item['name'] ?? 'วัตถุดิบ'} เหลือ ${_formatQty(next)} "
          "${item['unit'] ?? ''}",
        ),
        duration: const Duration(seconds: 4), // [UI] แถบแสดง 4 วินาที
        action: SnackBarAction( // ปุ่ม "เลิกทำ" บนแถบข้อความ
          label: "เลิกทำ",
          onPressed: () => _adjustQuantity(item, current - next), // กดเลิกทำ = ปรับกลับเท่าเดิม
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isCategoryView = _selectedCategory == null; // ยังไม่ได้เลือกหมวด = หน้ารวมหมวดหมู่
    final Set<String> uniqueCategories = _inventoryItems // รายชื่อหมวดที่มีของ (ไม่ซ้ำ)
        .map((item) => (item['category'] ?? 'อื่นๆ').toString())
        .toSet();
    final List<Map<String, dynamic>> displayedItems = isCategoryView // ของที่จะแสดง: ทั้งหมด หรือเฉพาะหมวดที่เลือก
        ? _inventoryItems
        : _inventoryItems
              .where(
                (item) => (item['category'] ?? 'อื่นๆ') == _selectedCategory,
              )
              .toList();

    // ถ้ามีการพิมพ์ค้นหา ให้ค้นจากชื่อวัตถุดิบทั้งหมดในคลังจริง (ไม่สนใจว่า
    // ตอนนี้อยู่ในมุมมองหมวดหมู่ไหน) เทียบแบบไม่สนตัวพิมพ์เล็ก/ใหญ่
    final String trimmedQuery = _searchQuery.trim().toLowerCase(); // คำค้นแบบตัวพิมพ์เล็ก
    final bool isSearching = trimmedQuery.isNotEmpty; // กำลังค้นหาไหม
    final List<Map<String, dynamic>> searchResults = isSearching // ผลค้นหา (ชื่อมีคำค้น)
        ? _inventoryItems.where((item) {
            final name = (item['name']?.toString() ?? '').toLowerCase();
            return name.contains(trimmedQuery);
          }).toList()
        : <Map<String, dynamic>>[];

    int totalItems = isCategoryView // จำนวนรายการ
        ? _inventoryItems.length
        : displayedItems.length;
    int nearExpiryCount = 0; // จำนวนใกล้ครบกำหนด
    int expiredCount = 0; // จำนวนเกินกำหนด

    // ของที่ใช้หมดแล้ว (เหลือ 0 ชิ้น) ไม่ควรถูกนับทั้ง "ใกล้หมดอายุ" และ
    // "หมดแล้ว" เพราะไม่มีของเหลือให้ต้องพูดถึงวันหมดอายุอีกต่อไป (ปกติแล้ว
    // พอเหลือ 0 ตอนทำอาหาร ระบบจะลบรายการนี้ออกจากคลังไปเลย)
    for (var item in (isCategoryView ? _inventoryItems : displayedItems)) { // นับใกล้/เกินกำหนด
      if (isUsedUp(item)) continue; // หมดแล้ว ข้าม
      final diff = daysLeft(item); // เหลืออีกกี่วัน
      if (diff == null) continue;
      if (diff < 0) {
        expiredCount++; // ติดลบ = เกินกำหนด
      } else if (diff <= 3) { // 0-3 วัน = ใกล้ครบกำหนด (แก้เลข 3 เพื่อเปลี่ยนเกณฑ์)
        nearExpiryCount++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
      bottomNavigationBar: const AppBottomNav(current: AppTab.inventory), // แถบเมนูล่าง ไฮไลต์ "คลัง"
      body: SafeArea(
        child: RefreshIndicator( // ดึงลงเพื่อรีเฟรช
          onRefresh: _fetchInventoryData,
          color: Colors.blue, // [UI] สีวงหมุนตอนรีเฟรช
          child: Column(
            children: [
              const SizedBox(height: 15), // [UI] ระยะจากขอบบน
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้ายขวา
                child: Row(
                  children: [
                    if (!isCategoryView) ...[ // อยู่ในหมวด -> มีปุ่มย้อนกลับไปหน้ารวมหมวด
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7D0), // [UI] สีปุ่ม
                          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                        ),
                        child: IconButton(
                          icon: const BackIcon(size: 24), // [UI] ไอคอนย้อนกลับ
                          onPressed: () =>
                              setState(() => _selectedCategory = null), // กลับไปหน้ารวมหมวด
                        ),
                      ),
                      const SizedBox(width: 10), // [UI] ระยะปุ่มกับช่องค้นหา
                    ],
                    Expanded(
                      child: Container(
                        height: 50, // [UI] ความสูงช่องค้นหา
                        // สีเดียวกับแถบหัวข้อของหน้าอื่นๆ ในแอป (เหลืองอ่อน)
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7D0), // [UI] สีช่อง (ครีม)
                          borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                        ),
                        child: TextField( // ช่องค้นหา
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value), // พิมพ์แล้วกรองทันที
                          decoration: InputDecoration(
                            hintText: isCategoryView // ข้อความจางในช่อง = ชื่อหน้า/ชื่อหมวด
                                ? "วัตถุดิบทั้งหมด"
                                : _selectedCategory,
                            hintStyle: const TextStyle(
                              fontWeight: FontWeight.bold, // [UI] ตัวหนา
                              color: Colors.black87,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(14), // [UI] ระยะรอบไอคอน
                              child: ListIcon(size: 20), // [UI] ไอคอนรายการ ขนาด 20
                            ),
                            suffixIcon: _searchQuery.isEmpty
                                ? const Icon(Icons.search, color: Colors.black) // ยังไม่พิมพ์ = แว่นขยาย, พิมพ์แล้ว = ปุ่ม X
                                : IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.black,
                                    ),
                                    onPressed: () {
                                      _searchController.clear(); // ล้างคำค้น
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                            border: InputBorder.none, // [UI] ไม่มีเส้นขอบ
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 13, // [UI] ระยะในบนล่าง
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20), // [UI] ระยะห่างก่อนกล่องสรุป
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15), // [UI] ระยะในกล่องสรุปบนล่าง
                  decoration: BoxDecoration(
                    color: Colors.white, // [UI] พื้นขาว
                    borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                  ),
                  child: IntrinsicHeight( // ให้เส้นคั่นสูงเท่ากล่อง
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly, // [UI] กระจาย 3 ช่องเท่าๆ กัน
                      children: [
                        _buildStatColumn("$totalItems", "รายการ"),
                        const VerticalDivider(
                          color: Colors.grey, // [UI] เส้นคั่นสีเทา
                          thickness: 0.5, // [UI] ความหนาเส้นคั่น
                        ),
                        _buildStatColumn("$nearExpiryCount", "ใกล้ครบกำหนด"),
                        const VerticalDivider(
                          color: Colors.grey,
                          thickness: 0.5,
                        ),
                        _buildStatColumn("$expiredCount", "เกินกำหนด"),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ในหน้า inventory_screen.dart ส่วนของ build method
              Expanded(
                child: _isLoading // กำลังโหลด
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.blue), // [UI] วงหมุนสีฟ้า
                      )
                    : isSearching
                    // 🔍 กำลังพิมพ์ค้นหา — โชว์ผลลัพธ์ที่ตรงกับคำค้นจากของ
                    // ทั้งหมดในคลังจริง แทนที่มุมมองหมวดหมู่/รายการปกติ
                    ? (searchResults.isEmpty
                          ? const Center(
                              child: Text(
                                "ไม่พบวัตถุดิบที่ค้นหา",
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 16, // [UI] ขนาด 16
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20, // [UI] ระยะซ้ายขวา
                              ),
                              children: [
                                ...searchResults.map(
                                  (item) => _buildItemCard(context, item), // การ์ดผลค้นหา
                                ),
                                const SizedBox(height: 30), // [UI] ระยะว่างท้าย
                              ],
                            ))
                    : _inventoryItems
                          .isEmpty // 🚀 เช็กตรงนี้ครับ ถ้า list ว่าง
                    ? const Center(
                        child: Text(
                          "ยังไม่มีวัตถุดิบในตู้เย็น", // ข้อความนี้จะขึ้นเมื่อไม่มีของ
                          style: TextStyle(color: Colors.black54, fontSize: 16), // [UI] สีเทา ขนาด 16
                        ),
                      )
                    : ListView(
                        // 🚀 ถ้ามีของค่อยแสดง ListView
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (isCategoryView) // หน้ารวม -> การ์ดหมวดหมู่
                            ...uniqueCategories.map(
                              (cat) => _buildCategoryCard(
                                cat,
                                _getCategoryIcon(cat),
                              ),
                            )
                          else
                            ...displayedItems.map( // ในหมวด -> การ์ดวัตถุดิบ
                              (item) => _buildItemCard(context, item),
                            ),
                          const SizedBox(height: 10),
                          isCategoryView // ปุ่มเพิ่มด้านล่าง (หน้ารวม = เพิ่มหมวด, ในหมวด = เพิ่มวัตถุดิบ)
                              ? _buildAddButton(
                                  "+ เพิ่มหมวดหมู่",
                                  () => _showAddCategorySheet(uniqueCategories),
                                )
                              : _buildAddButton("+ เพิ่มวัตถุดิบ", _openScan),
                          const SizedBox(height: 30),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ช่องตัวเลขสรุป 1 ช่อง
  Widget _buildStatColumn(String number, String label) {
    return Column(
      children: [
        Text(
          number,
          style: const TextStyle(
            fontSize: 18, // [UI] ขนาดตัวเลข
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87), // [UI] ขนาดชื่อช่อง
        ),
      ],
    );
  }

  // การ์ดหมวดหมู่ (กดเพื่อเข้าไปดูของในหมวด)
  Widget _buildCategoryCard(String name, String icon) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = name), // กดแล้วเลือกหมวดนี้
      child: Container(
        margin: const EdgeInsets.only(bottom: 15), // [UI] ระยะใต้การ์ด
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25), // [UI] ระยะใน ซ้ายขวา 30 บนล่าง 25
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7D0), // [UI] สีการ์ด (ครีม)
          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 35)), // [UI] อิโมจิขนาด 35
            const SizedBox(width: 20), // [UI] ระยะอิโมจิกับชื่อ
            Text(
              name,
              style: const TextStyle(
                fontSize: 20, // [UI] ขนาดชื่อหมวด
                fontWeight: FontWeight.w600, // [UI] กึ่งหนา
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ปริมาณที่ตรวจพบจากรูปตอนสแกน แสดงเฉพาะตอนที่ผู้ใช้เลือกแบ่งเป็นส่วน
  // (หน่วยที่ใช้หักต่างจากที่ตรวจพบ) เช่น "ซื้อมา 1 แพ็ค แบ่งเป็น 3 ส่วน"
  String? _detectedText(Map<String, dynamic> item) {
    final detectedUnit = item['detected_unit']?.toString();
    if (detectedUnit == null || detectedUnit == item['unit']?.toString()) { // หน่วยเดียวกับที่ตรวจพบ ไม่ต้องแสดง
      return null;
    }
    final detectedQty = _formatQty(_toNum(item['detected_quantity']));
    return "ซื้อมา $detectedQty $detectedUnit "
        "แบ่งเป็น ${_formatQty(_toNum(item['max_quantity']))} ${item['unit'] ?? ''}";
  }

  // ผู้ใช้ตรวจแล้วว่ายังใช้ได้ ต่อเวลาให้ "เก็บได้อีก X วัน" (ดู extendShelfLife)
  Future<void> _extend(Map<String, dynamic> item, int days) async {
    try { // ต่อเวลาในฐานข้อมูล
      await extendShelfLife(
        supabase: Supabase.instance.client,
        item: item,
        moreDays: days,
      );
      await _fetchInventoryData(); // โหลดใหม่
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

  // [UI] สีพื้นป้ายวันหมดอายุ: ≤1 วัน = ชมพู, ≤3 วัน = ส้มอ่อน, นอกนั้น = เขียวอ่อน
  Color _expiryBadgeColor(int days) {
    if (days <= 1) return const Color(0xFFFADBD8);
    if (days <= 3) return const Color(0xFFFFE0B2);
    return const Color(0xFFDCF3DC);
  }

  // [UI] สีตัวอักษรป้าย: ≤1 วัน = แดง, ≤3 วัน = ส้ม, นอกนั้น = เขียว
  Color _expiryTextColor(int days) {
    if (days <= 1) return const Color(0xffD64545);
    if (days <= 3) return const Color(0xffE67E22);
    return const Color(0xff3F9142);
  }

  // การ์ดวัตถุดิบ 1 ลอต (ตามดีไซน์ในเอกสาร): ชื่อ, หมวดหมู่ + ช่องที่เก็บ,
  // อยู่ในตู้เย็นมาแล้วกี่วัน, แถบปริมาณคงเหลือ "เหลือ 2 จาก 3 ส่วน (67%)",
  // ป้ายวันหมดอายุ และปุ่ม -/+ ปรับปริมาณคงเหลือเอง
  Widget _buildItemCard(BuildContext context, Map<String, dynamic> item) {
    String id = item['item_id'].toString(); // id
    String name = item['name'] ?? 'ไม่ระบุชื่อ'; // ชื่อ
    String icon = _getCategoryIcon(item['category'] ?? ''); // อิโมจิหมวด
    final category = item['category']?.toString() ?? 'อื่นๆ';
    final storage = item['storage']?.toString(); // ช่องที่เก็บ
    final unit = item['unit']?.toString() ?? ''; // หน่วย

    final qty = _toNum(item['quantity']); // เหลือเท่าไหร่
    num maxQty = _toNum(item['max_quantity']); // ทั้งหมดตอนเก็บ
    if (maxQty < qty) maxQty = qty; // กันข้อมูลแปลก (เหลือมากกว่าทั้งหมด)
    final ratio = maxQty > 0 ? (qty / maxQty).clamp(0.0, 1.0) : 0.0; // สัดส่วนที่เหลือ 0-1
    final percent = (ratio * 100).round(); // เปอร์เซ็นต์ที่เหลือ
    const segments = 8; // [UI] จำนวนช่องของแถบปริมาณ (แก้เลขเพื่อให้ละเอียดขึ้น/ลดลง)
    final filled = (ratio * segments).round(); // จำนวนช่องที่ระบายสี

    final expiryDays = daysLeft(item); // เหลืออีกกี่วัน

    return GestureDetector(
      onTap: () { // กดการ์ด -> หน้ารายละเอียด
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailScreen(itemData: item, itemId: id),
          ),
        ).then((_) => _fetchInventoryData()); // กลับมาแล้วโหลดใหม่
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15), // [UI] ระยะใต้การ์ด
        padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7D0), // [UI] สีการ์ด (ครีม)
          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56, // [UI] ขนาดกล่องอิโมจิ
              width: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white, // [UI] พื้นขาว
                borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
              ),
              child: Text(icon, style: const TextStyle(fontSize: 30)), // [UI] อิโมจิขนาด 30
            ),
            const SizedBox(width: 12), // [UI] ระยะอิโมจิกับข้อความ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18, // [UI] ขนาดชื่อวัตถุดิบ
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (expiryDays != null) // มีข้อมูลวันหมดอายุถึงแสดงป้าย
                        Container(
                          margin: const EdgeInsets.only(left: 6), // [UI] ห่างจากชื่อ 6
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, // [UI] ระยะในป้ายซ้ายขวา
                            vertical: 4, // [UI] ระยะในป้ายบนล่าง
                          ),
                          decoration: BoxDecoration(
                            color: _expiryBadgeColor(expiryDays), // [UI] สีพื้นป้ายตามจำนวนวัน
                            borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
                          ),
                          child: Text(
                            expiryText(expiryDays),
                            style: TextStyle(
                              fontSize: 12, // [UI] ขนาดตัวอักษรป้าย
                              fontWeight: FontWeight.bold,
                              color: _expiryTextColor(expiryDays), // [UI] สีตัวอักษรตามจำนวนวัน
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    storage == null
                        ? category
                        : "$category · ${storageEmoji(storage)} ${storageLabel(storage)}",
                    style: const TextStyle(
                      fontSize: 13, // [UI] ขนาด 13
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (item['created_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 15, // [UI] ไอคอนนาฬิกา ขนาด 15
                            color: Color(0xff5189C9),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fridgeAgeText(item['created_at']),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff5189C9), // [UI] สีฟ้า
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // เกินระยะที่เก็บได้แล้ว: คำแนะนำตามชนิดของ และปุ่ม "ตรวจแล้วยังใช้ได้"
                  if (expiryDays != null && expiryDays < 0) // เกินกำหนดแล้วเท่านั้นถึงแสดงกล่องเตือน
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: OverdueNotice(
                        item: item,
                        onExtend: (days) => _extend(item, days), // กด +N วัน -> ต่อเวลา
                      ),
                    ),
                  // ที่มาของระยะที่เก็บได้ + ปุ่มแก้ (เช่นกด +วันผิด จะได้แก้กลับได้)
                  if (displayShelfDays(item) != null) // มีข้อมูลระยะเก็บถึงแสดง
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "เก็บได้ ${formatShelfDays(displayShelfDays(item)!.round())} · "
                            "${shelfSourceShort(item)}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6), // [UI] ระยะในปุ่ม "แก้"
                          ),
                          onPressed: () async {
                            if (await editShelfDaysDialog(context, item)) { // เปิดหน้าต่างแก้ระยะเก็บ บันทึกแล้วโหลดใหม่
                              _fetchInventoryData();
                            }
                          },
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 15, // [UI] ไอคอนดินสอ ขนาด 15
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
                  if (_detectedText(item) != null) // ของที่แบ่งเป็นส่วน -> บอกว่าซื้อมาเท่าไหร่
                    Text(
                      _detectedText(item)!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (int i = 0; i < segments; i++) // สร้างแถบปริมาณทีละช่อง
                        Expanded(
                          child: Container(
                            height: 6, // [UI] ความสูงแถบ
                            margin: EdgeInsets.only(
                              right: i == segments - 1 ? 0 : 3, // [UI] ช่องว่างระหว่างช่อง 3 (ช่องสุดท้ายไม่มี)
                            ),
                            decoration: BoxDecoration(
                              color: i < filled // ช่องที่ระบาย = เขียว, ที่เหลือ = เทาจาง
                                  ? const Color(0xff8BCB6A) // [UI] สีเขียวของแถบ
                                  : Colors.black12,
                              borderRadius: BorderRadius.circular(3), // [UI] มุมโค้ง
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "เหลือ ${_formatQty(qty)} จาก ${_formatQty(maxQty)} $unit ($percent%)",
                          style: const TextStyle(
                            fontSize: 13, // [UI] ขนาดข้อความ
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      _buildQtyButton(
                        Icons.remove,
                        () => _adjustQuantity(item, -1), // ปุ่ม − ลดทีละ 1
                      ),
                      const SizedBox(width: 6), // [UI] ระยะห่างปุ่ม
                      _buildQtyButton(
                        Icons.add,
                        () => _adjustQuantity(item, 1), // ปุ่ม + เพิ่มทีละ 1
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () { // กดถังขยะ -> ถามยืนยัน
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("ยืนยันการลบ"),
                              content: Text("คุณต้องการลบ $name ใช่หรือไม่?"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("ยกเลิก"),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _deleteItem(id); // ลบจริง
                                  },
                                  child: const Text(
                                    "ลบ",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.delete, // [UI] ไอคอนถังขยะ
                          color: Colors.black87,
                          size: 24, // [UI] ขนาด 24
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ปุ่ม − / + ปรับจำนวน
  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30, // [UI] ขนาดปุ่ม 30x30
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white, // [UI] พื้นขาว
          borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
          border: Border.all(color: const Color(0xFFFFD191)), // [UI] ขอบส้มอ่อน
        ),
        child: Icon(icon, size: 18, color: Colors.black87), // [UI] ไอคอนขนาด 18
      ),
    );
  }

  // ปุ่ม "+ เพิ่ม..." ใหญ่ด้านล่าง
  Widget _buildAddButton(String text, VoidCallback onTap) {
    return Material(
      color: const Color(0xFFFFF7D0), // [UI] สีปุ่ม (ครีม)
      borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 25), // [UI] ความสูงปุ่ม (ระยะบนล่าง 25)
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 18, // [UI] ขนาดตัวอักษร
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- เพิ่มของ

  /// เปิดฟอร์มกรอกวัตถุดิบเอง โดยตั้งหมวดหมู่ไว้ให้แล้ว
  void _openManualEntry(String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          foundItems: [],
          manual: true,
          initialCategory: category, // โหมดกรอกเอง
        ), // ตั้งหมวดไว้ให้
      ),
    ).then((_) => _fetchInventoryData()); // กลับมาแล้วโหลดใหม่
  }

  /// "+ เพิ่มวัตถุดิบ": ไปหน้าสแกนวัตถุดิบ (ในหน้านั้นเลือกถ่ายภาพ/คลังรูป/กรอกเองได้)
  void _openScan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImageScanning()),
    ).then((_) => _fetchInventoryData());
  }

  // ตัวเลือก 1 แถวในแผ่นเมนูด้านล่าง
  Widget _sheetOption({
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: leading,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () {
        Navigator.pop(context); // ปิดแผ่นก่อน
        onTap(); // แล้วทำงานที่เลือก
      },
    );
  }

  // เปิดแผ่นเมนูเลื่อนขึ้นจากด้านล่าง
  Future<void> _showSheet(String title, List<Widget> options) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // [UI] พื้นขาว
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // [UI] มุมบนโค้ง 24
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16), // [UI] ระยะบนล่างในแผ่น
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), // [UI] ระยะรอบหัวข้อ
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18, // [UI] ขนาดหัวข้อ
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...options,
            ],
          ),
        ),
      ),
    );
  }

  /// "+ เพิ่มหมวดหมู่": หมวดหมู่เป็นชุดตายตัว (fixedCategories) และจะแสดงเมื่อมี
  /// วัตถุดิบอย่างน้อย 1 ชิ้น จึงให้เลือกหมวดที่ยังไม่มี แล้วกรอกวัตถุดิบชิ้นแรก
  void _showAddCategorySheet(Set<String> shown) {
    final missing = fixedCategories.where((c) => !shown.contains(c)).toList(); // หมวดที่ยังไม่มีของ
    if (missing.isEmpty) { // มีครบทุกหมวดแล้ว
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("มีวัตถุดิบครบทุกหมวดหมู่แล้ว")),
      );
      return;
    }
    _showSheet("เลือกหมวดหมู่ที่จะเพิ่ม", [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          "หมวดหมู่จะแสดงในคลังเมื่อมีวัตถุดิบอย่างน้อย 1 ชิ้น",
          style: TextStyle(color: Colors.black54), // [UI] ข้อความสีเทา
        ),
      ),
      for (final c in missing)
        _sheetOption(
          leading: Text(categoryEmoji(c), style: const TextStyle(fontSize: 24)), // [UI] อิโมจิขนาด 24
          title: c,
          onTap: () => _openManualEntry(c), // เลือกหมวด -> เปิดฟอร์มกรอกวัตถุดิบชิ้นแรก
        ),
    ]);
  }
}
