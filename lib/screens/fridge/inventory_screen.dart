import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/screens/fridge/item_detail_screen.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/widgets/overdue_notice.dart';
import 'package:test_app/widgets/shelf_days_dialog.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/notification_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String? _selectedCategory;
  List<Map<String, dynamic>> _inventoryItems = [];
  bool _isLoading = true;

  // ช่องค้นหาวัตถุดิบด้านบน — เดิมเป็นแค่ TextField เปล่าๆ พิมพ์แล้วไม่มีอะไร
  // เกิดขึ้นเลย ตอนนี้ผูกกับ state จริง พิมพ์แล้วต้องกรองรายการวัตถุดิบจริง
  // จากคลังให้ขึ้นมา
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchInventoryData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInventoryData() async {
    setState(() => _isLoading = true);
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
        ..sort(compareFifo);

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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await Supabase.instance.client
          .from('fridge_items')
          .delete()
          .eq('item_id', id); // อ้างอิงตาม item_id
      _fetchInventoryData();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ลบข้อมูลไม่สำเร็จ: $e")));
    }
  }

  // ใช้ mapping กลางจาก utils/category_icons.dart (หน้านี้คือต้นแบบที่หน้าอื่น
  // ต้องอ้างอิงตาม เพื่อไม่ให้ชุดอิโมจิหมวดหมู่เพี้ยนไปคนละหน้า)
  String _getCategoryIcon(String category) => categoryEmoji(category);

  num _toNum(dynamic v) =>
      v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  String _formatQty(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ปรับลด/เพิ่มปริมาณคงเหลือเองแบบ Manual (Manual Override) ให้ตรงกับของจริง
  // ถ้าลดจนเหลือ 0 จะถามก่อนว่าจะลบลอตนี้ออกจากตู้เย็นเลยไหม
  Future<void> _adjustQuantity(Map<String, dynamic> item, num delta) async {
    final id = item['item_id'].toString();
    final current = _toNum(item['quantity']);
    num next = current + delta;
    if (next < 0) next = 0;

    if (next <= 0) {
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
      if (confirm == true) await _deleteItem(id);
      return;
    }

    // ปุ่ม + ใช้คืนจำนวนที่กดลดไป (เช่นกดลบผิด) ได้ไม่เกินปริมาณทั้งหมดตอนเก็บ
    // ไม่ไปเพิ่ม "ทั้งหมด" ให้เอง — ถ้าซื้อมาเพิ่มจริงควรสแกนเป็นลอตใหม่ ส่วน
    // ถ้าจำนวนตั้งต้นผิด ให้แก้ "ทั้งหมด" ในหน้ารายละเอียด
    final maxQty = _toNum(item['max_quantity']);
    if (maxQty > 0 && next > maxQty) {
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

    final update = <String, dynamic>{'quantity': next};
    setState(() => item['quantity'] = next);

    try {
      await Supabase.instance.client
          .from('fridge_items')
          .update(update)
          .eq('item_id', id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ปรับจำนวนไม่สำเร็จ: $e")));
      _fetchInventoryData();
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
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: "เลิกทำ",
          onPressed: () => _adjustQuantity(item, current - next),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isCategoryView = _selectedCategory == null;
    final Set<String> uniqueCategories = _inventoryItems
        .map((item) => (item['category'] ?? 'อื่นๆ').toString())
        .toSet();
    final List<Map<String, dynamic>> displayedItems = isCategoryView
        ? _inventoryItems
        : _inventoryItems
              .where(
                (item) => (item['category'] ?? 'อื่นๆ') == _selectedCategory,
              )
              .toList();

    // ถ้ามีการพิมพ์ค้นหา ให้ค้นจากชื่อวัตถุดิบทั้งหมดในคลังจริง (ไม่สนใจว่า
    // ตอนนี้อยู่ในมุมมองหมวดหมู่ไหน) เทียบแบบไม่สนตัวพิมพ์เล็ก/ใหญ่
    final String trimmedQuery = _searchQuery.trim().toLowerCase();
    final bool isSearching = trimmedQuery.isNotEmpty;
    final List<Map<String, dynamic>> searchResults = isSearching
        ? _inventoryItems.where((item) {
            final name = (item['name']?.toString() ?? '').toLowerCase();
            return name.contains(trimmedQuery);
          }).toList()
        : <Map<String, dynamic>>[];

    int totalItems = isCategoryView
        ? _inventoryItems.length
        : displayedItems.length;
    int nearExpiryCount = 0;
    int expiredCount = 0;

    // ของที่ใช้หมดแล้ว (เหลือ 0 ชิ้น) ไม่ควรถูกนับทั้ง "ใกล้หมดอายุ" และ
    // "หมดแล้ว" เพราะไม่มีของเหลือให้ต้องพูดถึงวันหมดอายุอีกต่อไป (ปกติแล้ว
    // พอเหลือ 0 ตอนทำอาหาร ระบบจะลบรายการนี้ออกจากคลังไปเลย)
    for (var item in (isCategoryView ? _inventoryItems : displayedItems)) {
      if (isUsedUp(item)) continue;
      final diff = daysLeft(item);
      if (diff == null) continue;
      if (diff < 0) {
        expiredCount++;
      } else if (diff <= 3) {
        nearExpiryCount++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.inventory),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchInventoryData,
          color: Colors.blue,
          child: Column(
            children: [
              const SizedBox(height: 15),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    if (!isCategoryView) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7D0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const BackIcon(size: 24),
                          onPressed: () =>
                              setState(() => _selectedCategory = null),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            hintText: isCategoryView
                                ? "วัตถุดิบทั้งหมด"
                                : _selectedCategory,
                            hintStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(14),
                              child: ListIcon(size: 20),
                            ),
                            suffixIcon: _searchQuery.isEmpty
                                ? const Icon(
                                    Icons.search,
                                    color: Colors.black,
                                  )
                                : IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.black,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: const Center(child: FilterIcon(size: 20)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatColumn("$totalItems", "รายการ"),
                        const VerticalDivider(
                          color: Colors.grey,
                          thickness: 0.5,
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
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.blue),
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
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              children: [
                                ...searchResults.map(
                                  (item) => _buildItemCard(context, item),
                                ),
                                const SizedBox(height: 30),
                              ],
                            ))
                    : _inventoryItems
                          .isEmpty // 🚀 เช็กตรงนี้ครับ ถ้า list ว่าง
                    ? const Center(
                        child: Text(
                          "ยังไม่มีวัตถุดิบในตู้เย็น", // ข้อความนี้จะขึ้นเมื่อไม่มีของ
                          style: TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      )
                    : ListView(
                        // 🚀 ถ้ามีของค่อยแสดง ListView
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          if (isCategoryView)
                            ...uniqueCategories.map(
                              (cat) => _buildCategoryCard(
                                cat,
                                _getCategoryIcon(cat),
                              ),
                            )
                          else
                            ...displayedItems.map(
                              (item) => _buildItemCard(context, item),
                            ),
                          const SizedBox(height: 10),
                          _buildAddButton(
                            isCategoryView
                                ? "+ เพิ่มหมวดหมู่"
                                : "+ เพิ่มวัตถุดิบ",
                          ),
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

  Widget _buildStatColumn(String number, String label) {
    return Column(
      children: [
        Text(
          number,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String name, String icon) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 25),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7D0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 35)),
            const SizedBox(width: 20),
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
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
    if (detectedUnit == null || detectedUnit == item['unit']?.toString()) {
      return null;
    }
    final detectedQty = _formatQty(_toNum(item['detected_quantity']));
    return "ซื้อมา $detectedQty $detectedUnit "
        "แบ่งเป็น ${_formatQty(_toNum(item['max_quantity']))} ${item['unit'] ?? ''}";
  }

  // ผู้ใช้ตรวจแล้วว่ายังใช้ได้ ต่อเวลาให้ "เก็บได้อีก X วัน" (ดู extendShelfLife)
  Future<void> _extend(Map<String, dynamic> item, int days) async {
    try {
      await extendShelfLife(
        supabase: Supabase.instance.client,
        item: item,
        moreDays: days,
      );
      await _fetchInventoryData();
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

  Color _expiryBadgeColor(int days) {
    if (days <= 1) return const Color(0xFFFADBD8);
    if (days <= 3) return const Color(0xFFFFE0B2);
    return const Color(0xFFDCF3DC);
  }

  Color _expiryTextColor(int days) {
    if (days <= 1) return const Color(0xffD64545);
    if (days <= 3) return const Color(0xffE67E22);
    return const Color(0xff3F9142);
  }

  // การ์ดวัตถุดิบ 1 ลอต (ตามดีไซน์ในเอกสาร): ชื่อ, หมวดหมู่ + ช่องที่เก็บ,
  // อยู่ในตู้เย็นมาแล้วกี่วัน, แถบปริมาณคงเหลือ "เหลือ 2 จาก 3 ส่วน (67%)",
  // ป้ายวันหมดอายุ และปุ่ม -/+ ปรับปริมาณคงเหลือเอง
  Widget _buildItemCard(BuildContext context, Map<String, dynamic> item) {
    String id = item['item_id'].toString();
    String name = item['name'] ?? 'ไม่ระบุชื่อ';
    String icon = _getCategoryIcon(item['category'] ?? '');
    final category = item['category']?.toString() ?? 'อื่นๆ';
    final storage = item['storage']?.toString();
    final unit = item['unit']?.toString() ?? '';

    final qty = _toNum(item['quantity']);
    num maxQty = _toNum(item['max_quantity']);
    if (maxQty < qty) maxQty = qty;
    final ratio = maxQty > 0 ? (qty / maxQty).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).round();
    const segments = 8;
    final filled = (ratio * segments).round();

    final expiryDays = daysLeft(item);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailScreen(itemData: item, itemId: id),
          ),
        ).then((_) => _fetchInventoryData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7D0),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              width: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(width: 12),
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
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (expiryDays != null)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _expiryBadgeColor(expiryDays),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            expiryText(expiryDays),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _expiryTextColor(expiryDays),
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
                      fontSize: 13,
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
                            size: 15,
                            color: Color(0xff5189C9),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              fridgeAgeText(item['created_at']),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff5189C9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // เกินระยะที่เก็บได้แล้ว: คำแนะนำตามชนิดของ และปุ่ม "ตรวจแล้วยังใช้ได้"
                  if (expiryDays != null && expiryDays < 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: OverdueNotice(
                        item: item,
                        onExtend: (days) => _extend(item, days),
                      ),
                    ),
                  // ที่มาของระยะที่เก็บได้ + ปุ่มแก้ (เช่นกด +วันผิด จะได้แก้กลับได้)
                  if (displayShelfDays(item) != null)
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
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onPressed: () async {
                            if (await editShelfDaysDialog(context, item)) {
                              _fetchInventoryData();
                            }
                          },
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 15,
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
                  if (_detectedText(item) != null)
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
                      for (int i = 0; i < segments; i++)
                        Expanded(
                          child: Container(
                            height: 6,
                            margin: EdgeInsets.only(
                              right: i == segments - 1 ? 0 : 3,
                            ),
                            decoration: BoxDecoration(
                              color: i < filled
                                  ? const Color(0xff8BCB6A)
                                  : Colors.black12,
                              borderRadius: BorderRadius.circular(3),
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
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      _buildQtyButton(
                        Icons.remove,
                        () => _adjustQuantity(item, -1),
                      ),
                      const SizedBox(width: 6),
                      _buildQtyButton(Icons.add, () => _adjustQuantity(item, 1)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
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
                                    _deleteItem(id);
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
                          Icons.delete,
                          color: Colors.black87,
                          size: 24,
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

  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFD191)),
        ),
        child: Icon(icon, size: 18, color: Colors.black87),
      ),
    );
  }

  Widget _buildAddButton(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

}