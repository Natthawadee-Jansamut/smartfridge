import 'dart:typed_data'; // Uint8List (ไฟล์รูป)

import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:test_app/services/fridge_images.dart'; // อัปโหลดรูปวัตถุดิบ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล
 // หมวดหมู่ + อิโมจิ
import 'package:test_app/utils/category_icons.dart'; // ตารางอายุการเก็บ
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/widgets/app_icons.dart'; // หน้าคลัง (ไปต่อหลังบันทึก)
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/fridge/inventory_screen.dart';

/// หน้าผลลัพธ์หลังสแกนวัตถุดิบ (ตามดีไซน์ใน Figma: "SCAN" - ผลลัพธ์)
/// รูปที่แสดงในการ์ด "รูปภาพ" คือรูปจริงที่ผู้ใช้ถ่าย/เลือกมา (ไม่ใช่รูป mock)
class ResultScreen extends StatefulWidget {
  final List<dynamic> foundItems; // รายการวัตถุดิบที่ AI เจอ
  final Uint8List? imageBytes; // รูปที่สแกน

  /// true = ผู้ใช้กรอกวัตถุดิบเอง (ไม่มีรูปและไม่ผ่าน AI) ใช้ฟอร์มและการบันทึก
  /// ชุดเดียวกับผลสแกน เผื่อกล้องหรือ AI ใช้งานไม่ได้
  final bool manual;

  /// หมวดหมู่เริ่มต้นของวัตถุดิบที่กรอกเอง (เช่น กด "+ เพิ่มวัตถุดิบ" จากในหมวด
  /// ผัก ในหน้าคลัง) — null = "อื่นๆ"
  final String? initialCategory;

  const ResultScreen({
    super.key,
    required this.foundItems,
    this.imageBytes,
    this.manual = false,
    this.initialCategory,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState(); // ใส่ลำดับเดิมไว้คู่กับแต่ละชิ้น

    if (widget.manual && widget.foundItems.isEmpty) {
      widget.foundItems.add(_newManualItem());
    }
 // เทียบหมวดหมู่
    // จัดกลุ่มวัตถุดิบที่สแกนเจอให้หมวดหมู่เดียวกันอยู่ติดกัน จะได้ไล่ดูง่าย
    // ใช้ index เดิมเป็นตัวตัดสินลำดับรองเพื่อให้เรียงแบบ stable (ของในหมวด // หมวดเดียวกัน -> ลำดับเดิม
    // เดียวกันยังอยู่ตามลำดับที่สแกนเจอ ไม่สลับกันไปมา)
    final indexed = widget.foundItems.asMap().entries.toList();
    indexed.sort((a, b) {
      final catA = // ใส่กลับตามลำดับใหม่
          (a.value is Map ? a.value['category']?.toString() : null) ?? "อื่นๆ";
      final catB =
          (b.value is Map ? b.value['category']?.toString() : null) ?? "อื่นๆ";
      final catCompare = catA.compareTo(catB);
      if (catCompare != 0) return catCompare; // ข้ามชิ้นที่เตรียมแล้ว
      return a.key.compareTo(b.key); // เตรียมค่าการจัดเก็บเริ่มต้น
    });

    widget.foundItems
      ..clear()
      ..addAll(indexed.map((e) => e.value));

    // คำนวณค่าการจัดเก็บเริ่มต้น (ช่องปกติ + วันหมดอายุตามตาราง/Gemini) ให้
    // ทุกชิ้นตั้งแต่ตอนเปิดหน้า ไม่รอให้การ์ดถูกเลื่อนมาแสดงก่อน (ListView
    // สร้างการ์ดเฉพาะชิ้นที่อยู่บนจอ) — กดบันทึกทันทีก็ยังได้ค่าที่ถูกต้อง
    for (final item in widget.foundItems) {
      if (item is! Map || item.containsKey('storage')) continue;
      _prepareStorage(item);
    }
  }

  // ตั้งค่าการจัดเก็บเริ่มต้นของ 1 ชิ้น (จากตาราง + ค่าที่ AI ประเมิน)
  void _prepareStorage(Map item) {
    item['gemini_fridge_days'] = item['fridge_days']; // จำค่าที่ AI ประเมินไว้
    item['gemini_freezer_days'] = item['freezer_days'];
    final typeKey = findShelfType(item['shelf_type']?.toString())?.key; // ประเภทในตาราง (ไม่เจอ = null)
    final state = defaultStateFor(typeKey); // สถานะเริ่มต้น (เช่น ดิบ)
    final life = resolveShelfLife( // รวมค่าตาราง + AI
      typeKey: typeKey,
      state: state,
      geminiFridgeDays: item['gemini_fridge_days'],
      geminiFreezerDays: item['gemini_freezer_days'],
    );
    item['shelf_type'] = typeKey;
    item['food_state'] = state;
    item['storage'] = storageFridge; // เริ่มที่ช่องปกติ
    item['fridge_days'] = life.fridgeDays;
    item['freezer_days'] = life.freezerDays;
    item['expiry_days'] = life.fridgeDays; // จำนวนวันเริ่มต้น = ช่องปกติ
  }

  // วัตถุดิบว่างสำหรับโหมดกรอกเอง
  Map<String, dynamic> _newManualItem() => {
    'manual': true,
    'name': '',
    'category': widget.initialCategory ?? 'อื่นๆ', // หมวดเริ่มต้น
    'count_mode': 'piece', // นับเป็นชิ้น
    'count': 1, // 1 ชิ้น
    'count_unit': 'ชิ้น',
  };

  // กด "เพิ่มอีกรายการ"
  void _addManualItem() {
    final item = _newManualItem();
    _prepareStorage(item);
    setState(() => widget.foundItems.add(item));
  }

  // ถามก่อนลบรายการ (โหมดกรอกเอง)
  Future<void> _confirmRemoveItem(dynamic item) async {
    final name = (item['name'] ?? '').toString().trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("ลบรายการนี้?"),
        content: Text(
          name.isEmpty
              ? "ข้อมูลที่กรอกในรายการนี้จะหายไป"
              : "ต้องการลบ \"$name\" ออกจากรายการใช่หรือไม่?",
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
    if (confirmed == true && mounted) {
      setState(() => widget.foundItems.remove(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
      body: SafeArea(
        child: Column(
          children: [
            IngredientFlowHeader( // หัวหน้า (ชื่อเปลี่ยนตามโหมด)
              title: widget.manual ? "นำเข้าวัตถุดิบด้วยตัวเอง" : "ผลลัพธ์",
            ),
            const SizedBox(height: 15), // [UI] ระยะใต้หัว

            // --- ป้ายบอกจำนวนวัตถุดิบที่พบ ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้ายขวา
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6), // [UI] ความสูงป้าย (ระยะบนล่าง 6)
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white, // [UI] พื้นขาว
                  borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4, // [UI] ความฟุ้งเงา
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  widget.manual
                      ? "วัตถุดิบ ${widget.foundItems.length} รายการ"
                      : "พบวัตถุดิบ ${widget.foundItems.length} รายการ",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // [UI] ขนาดตัวอักษร
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // --- การ์ด "รูปภาพ" (รูปจริงที่ถ่าย/เลือกมาสแกน) ---
            if (!widget.manual) ...[ // โหมดสแกนเท่านั้นถึงมีการ์ดรูป
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  width: double.infinity,
                  // เพิ่มความสูงจาก 200 เป็น 320 เพื่อให้มีที่พอแสดงรูปเต็มๆ
                  // ไม่ต้องครอปแน่นจนเกินไป (ของเดิมกล่องเตี้ยเกินไปเทียบกับรูปโหมด
                  // แนวตั้งจากกล้อง ทำให้ครอปหายไปเยอะ)
                  height: 320, // [UI] ความสูงการ์ดรูป (เพิ่มเลขเพื่อให้รูปใหญ่ขึ้น)
                  padding: const EdgeInsets.all(12), // [UI] ระยะในการ์ด
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4, // [UI] ความฟุ้งเงา
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, // [UI] ระยะในป้าย "รูปภาพ" ซ้ายขวา
                          vertical: 6, // [UI] ระยะในป้ายบนล่าง
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCDC), // [UI] สีป้าย (ครีม)
                          border: Border.all(color: const Color(0xFFFFD191)), // [UI] ขอบส้มอ่อน
                          borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง
                        ),
                        child: const Text(
                          "รูปภาพ",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14, // [UI] ขนาดป้าย
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10), // [UI] ระยะป้ายกับรูป
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12), // [UI] มุมรูปโค้ง
                          child: Container(
                            width: double.infinity,
                            alignment: Alignment.center,
                            // พื้นหลังสีเทาอ่อนไว้รองรับรูปที่สัดส่วนไม่พอดีกรอบ
                            // (BoxFit.contain จะไม่ครอปรูปแต่จะเห็นแถบพื้นหลังนี้แทน)
                            color: Colors.grey.shade100, // [UI] สีพื้นหลังรูป
                            child: widget.imageBytes != null
                                ? Image.memory(
                                    widget.imageBytes!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    // เปลี่ยนจาก cover เป็น contain เพื่อให้เห็นรูปที่ถ่ายมา
                                    // แบบเต็มๆ ไม่ถูกครอปขอบออกเหมือนก่อนหน้านี้
                                    fit: BoxFit.contain, // [UI] แสดงทั้งรูปไม่ครอบตัด
                                  )
                                : Icon(
                                    Icons.image_outlined,
                                    size: 36, // [UI] ไอคอนรูป (ตอนไม่มีรูป)
                                    color: Colors.grey.shade400,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // --- รายการวัตถุดิบ (List) ---
            Expanded(
              child: widget.foundItems.isEmpty
                  ? const Center(
                      child: Text(
                        "ไม่พบวัตถุดิบ",
                        style: TextStyle(color: Colors.black54, fontSize: 16), // [UI] สีเทา ขนาด 16
                      ),
                    )
                  : ListView.builder( // รายการการ์ดวัตถุดิบ
                      padding: const EdgeInsets.fromLTRB(20, 5, 20, 0), // [UI] ระยะรอบรายการ
                      itemCount:
                          widget.foundItems.length + (widget.manual ? 1 : 0), // โหมดกรอกเองมีปุ่มเพิ่มต่อท้าย (+1)
                      itemBuilder: (context, index) {
                        if (index == widget.foundItems.length) { // แถวสุดท้าย = ปุ่มเพิ่ม
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16), // [UI] ระยะใต้ปุ่ม
                            child: OutlinedButton.icon(
                              onPressed: _addManualItem,
                              icon: const Icon(Icons.add),
                              label: const Text("เพิ่มอีกรายการ"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษร (ฟ้า)
                                backgroundColor: Colors.white, // [UI] พื้นขาว
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13, // [UI] ความสูงปุ่ม
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
                                ),
                              ),
                            ),
                          );
                        }
                        final item = widget.foundItems[index];
                        return IngredientCardItem( // การ์ดวัตถุดิบ 1 ชิ้น
                          // ผูกการ์ดกับข้อมูลชิ้นนั้น ลบรายการแล้วค่าจะได้ไม่สลับการ์ด
                          key: ObjectKey(item),
                          initialData: item as Map<String, dynamic>,
                          onUpdate: (key, value) { // การ์ดแก้ค่า -> เก็บลงข้อมูลชิ้นนั้น
                            item[key] = value;
                          },
                          onRemove: // ลบได้เฉพาะโหมดกรอกเองและเหลือมากกว่า 1 ชิ้น
                              widget.manual && widget.foundItems.length > 1
                              ? () => _confirmRemoveItem(item)
                              : null,
                        );
                      },
                    ),
            ),

            // --- ปุ่มกดด้านล่าง (Footer) ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 15), // [UI] ระยะรอบแถบปุ่ม
              child: Container(
                padding: const EdgeInsets.all(15), // [UI] ระยะในแถบ
                decoration: BoxDecoration(
                  color: Colors.white, // [UI] พื้นขาว
                  borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10, // [UI] ความฟุ้งเงา
                      offset: Offset(0, -2), // [UI] เงาเลื่อนขึ้น 2
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context), // ปุ่มซ้าย = กลับ
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB6B6B6), // [UI] ปุ่มซ้ายสีเทา
                          foregroundColor: Colors.black87,
                          elevation: 0, // [UI] ไม่มีเงา
                          padding: const EdgeInsets.symmetric(vertical: 13), // [UI] ความสูงปุ่ม
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
                          ),
                        ),
                        child: Text(
                          widget.manual ? "ยกเลิก" : "สแกนใหม่",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15), // [UI] ระยะระหว่างปุ่ม
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveToSupabase, // ปุ่มขวา = บันทึก
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD7EDFF), // [UI] ปุ่มขวาสีฟ้าอ่อน
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            CheckIcon(size: 18), // [UI] ไอคอนติ๊ก ขนาด 18
                            SizedBox(width: 5),
                            Text(
                              "บันทึกทั้งหมด",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ฟังก์ชันบันทึกลง Database ---
  Future<void> _saveToSupabase() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) { // ยังไม่ล็อกอิน
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาล็อกอินก่อนบันทึกข้อมูล'),
          backgroundColor: Colors.red, // [UI] แถบแดง
        ),
      );
      return;
    }

    if (widget.foundItems.any( // มีรายการที่ยังไม่กรอกชื่อ
      (item) => (item['name'] ?? '').toString().trim().isEmpty,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกชื่อวัตถุดิบให้ครบทุกรายการ'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ช่องแช่แข็งของที่ไม่มีข้อมูล (กรอกเอง) ไม่มีค่าเริ่มต้น ต้องให้ผู้ใช้กรอกจำนวนวัน
    final missingDays = [ // รายการที่ยังไม่มีจำนวนวัน
      for (final item in widget.foundItems)
        if ((int.tryParse('${item['expiry_days']}') ?? 0) <= 0)
          (item['name'] ?? '').toString().trim(),
    ];
    if (missingDays.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'กรุณากรอกจำนวนวันที่เก็บได้ของ: ${missingDays.join(', ')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog( // แสดงวงหมุนระหว่างบันทึก
      context: context,
      barrierDismissible: false, // [UI] แตะข้างนอกปิดไม่ได้
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );

    try {
      // รูปที่ใช้สแกน: อัปโหลดครั้งเดียว ทุกวัตถุดิบจากรูปนี้ชี้ไปที่รูปเดียวกัน
      // (ไม่สำเร็จก็บันทึกวัตถุดิบต่อได้ แค่ไม่มีรูป)
      final imagePath = widget.imageBytes == null // อัปโหลดรูปครั้งเดียว ได้ที่อยู่ไฟล์
          ? null
          : await uploadFridgeImage(user.id, widget.imageBytes!);

      // หลัก FIFO: ซื้อวัตถุดิบชนิดเดิมมาเพิ่มเมื่อไหร่ ก็บันทึกแยกเป็นลอตใหม่
      // (แถวใหม่) เสมอ ไม่รวมเข้ากับลอตเดิม เพื่อให้แต่ละลอตมีวันที่เข้าตู้เย็น
      // และวันหมดอายุของตัวเอง ตอนทำอาหารระบบจะหักจากลอตที่ใกล้หมดอายุก่อน
      for (var item in widget.foundItems) { // บันทึกทีละชิ้น
        String name = item['name'].toString().trim();
        final storage = item['storage']?.toString() ?? storageFridge; // ช่องที่เก็บ
        int days = int.tryParse(item['expiry_days'].toString()) ?? 7; // จำนวนวันที่เก็บได้ (ไม่มี = 7)
        DateTime expiryDate = DateTime.now().add(Duration(days: days)); // วันหมดอายุ = วันนี้ + จำนวนวัน
        final foodState = item['food_state']?.toString() ?? ''; // สถานะ

        // ปริมาณที่ตรวจพบจากรูป (เช่น 1 แพ็ค 500 กรัม) เก็บไว้แสดงเฉยๆ ว่าซื้อมา
        // เท่าไหร่ ส่วนที่ใช้นับ/หักตอนทำอาหารคือจำนวนชิ้นหรือจำนวนส่วนที่ผู้ใช้
        // ยืนยัน (คนทำอาหารไม่ได้ชั่ง จึงไม่นับเป็นกรัม)
        final detectedQty = num.tryParse(item['quantity'].toString());
        final detectedUnit = item['unit']?.toString();
        // (การ์ดที่ยังไม่ถูกเลื่อนมาแสดงจะยังไม่ได้ normalize ค่าจาก Gemini จึง
        // กันไว้ตรงนี้อีกชั้น: หน่วยที่นับเป็นชิ้นไม่ได้ เช่น กรัม → เป็นส่วน)
        final rawCountUnit = item['count_unit']?.toString().trim() ?? '';
        final isPiece = // หน่วยนับต้องอยู่ในรายการหน่วยนับชิ้น
            item['count_mode'] == 'piece' && pieceUnits.contains(rawCountUnit);
        final num stockQty = // จำนวน (อย่างน้อย 1)
            (num.tryParse(item['count']?.toString() ?? '') ?? 1).round().clamp(
              1,
              1 << 30,
            );
        final stockUnit = isPiece ? rawCountUnit : 'ส่วน'; // นับชิ้น = หน่วยที่เลือก, ไม่งั้น = ส่วน
        // กรอกเองแล้วไม่ได้เลือกประเภท ค่าวันมาจากผู้ใช้ ไม่ใช่ AI หรือตาราง
        final isCustom = // ผู้ใช้กำหนดวันเองไหม
            item['expiry_custom'] == true ||
            (item['manual'] == true && item['shelf_type'] == null);

        await supabase.from('fridge_items').insert({ // เพิ่มแถวใหม่ในตารางของในตู้
          'user_id': user.id,
          // วันที่เข้าตู้เย็น — ตาราง fridge_items ไม่มีค่าเริ่มต้นให้คอลัมน์นี้
          // ถ้าไม่ใส่จะเป็นค่าว่าง แล้วหน้าแจ้งเตือน/การนับวันจะไม่เห็นของชิ้นนี้
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'name': name, // ชื่อ
          'category': item['category'], // หมวดหมู่
          'quantity': stockQty, // จำนวนที่เหลือ
          'max_quantity': stockQty, // จำนวนทั้งหมดตอนเก็บ
          'unit': stockUnit, // หน่วย
          'detected_quantity': detectedQty, // ปริมาณที่ตรวจพบจากรูป
          'detected_unit': detectedUnit,
          // expiry_date เป็น timestamptz ต้องส่งเป็น UTC (มี Z) ไม่งั้นเลื่อน 7 ชม.
          'expiry_date': expiryDate.toUtc().toIso8601String(),
          'storage': storage, // ช่องที่เก็บ
          'food_state': foodState.isEmpty ? null : foodState,
          'fridge_days': item['fridge_days'], // ช่องปกติเก็บได้กี่วัน
          'freezer_days': item['freezer_days'], // ช่องแช่แข็งเก็บได้กี่วัน
          // จำไว้ว่าระยะที่เก็บได้มาจากตารางประเภทไหน (null = Gemini ประเมิน,
          // custom = ผู้ใช้แก้จำนวนวันเอง) เพื่อบอกที่มาให้ผู้ใช้เห็นในหน้าแจ้งเตือน
          'shelf_type': isCustom
              ? customShelfType(
                  item['shelf_type']?.toString(),
                  storage == storageFreezer
                      ? item['freezer_days']
                      : item['fridge_days'],
                )
              : item['shelf_type'],
          if (isCustom)
            storage == storageFreezer ? 'freezer_days' : 'fridge_days': days,
          // นับเป็นชิ้น: ทำอาหาร 1 ครั้งใช้กี่ชิ้น (แบ่งเป็นส่วน 1 ครั้ง = 1 ส่วนอยู่แล้ว)
          if (isPiece)
            'use_per_cook':
                (num.tryParse(item['use_per_cook']?.toString() ?? '') ?? 1)
                    .clamp(1, stockQty),
          if (imagePath != null) 'image_path': imagePath, // ที่อยู่รูป (ถ้ามี)
        });
      }

      if (mounted) Navigator.pop(context); // ปิดวงหมุน

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลเรียบร้อย!'),
            backgroundColor: Colors.green, // [UI] แถบเขียว
          ),
        );

        Navigator.pushAndRemoveUntil( // ไปหน้าคลัง (ล้างหน้าระหว่างทาง เหลือแค่หน้าแรก)
          context,
          MaterialPageRoute(builder: (context) => const InventoryScreen()),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // ปิดวงหมุน
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ==================================================================
// Widget ย่อย: การ์ดสำหรับแสดงผลวัตถุดิบ 1 ชิ้น
// ==================================================================
class IngredientCardItem extends StatefulWidget {
  final Map<String, dynamic> initialData; // ข้อมูลเริ่มต้นของชิ้นนี้
  final Function(String key, dynamic value) onUpdate; // ส่งค่าที่แก้กลับไป (ชื่อช่อง, ค่า)
  final VoidCallback? onRemove; // ลบการ์ด (null = ลบไม่ได้)

  const IngredientCardItem({
    super.key,
    required this.initialData,
    required this.onUpdate,
    this.onRemove,
  });

  @override
  State<IngredientCardItem> createState() => _IngredientCardItemState();
}

class _IngredientCardItemState extends State<IngredientCardItem> {
  late TextEditingController nameController; // ช่องชื่อ
  late TextEditingController expiryController; // ช่องจำนวนวันที่เก็บได้
  // วิธีนับเพื่อหักใช้ตอนทำอาหาร (ไม่มีกรัม — คนทำอาหารไม่ได้ชั่ง):
  // 'piece' = นับเป็นชิ้น (ฟอง/ผล/หัว ฯลฯ), 'portion' = แบ่งเป็นส่วนเอง
  late String countMode; // วิธีนับ
  late int count; // จำนวน
  late String countUnit; // หน่วยนับ

  // นับเป็นชิ้น: ทำอาหาร 1 ครั้งใช้กี่ชิ้น (เช่น ไข่ ครั้งละ 2 ฟอง)
  // ใช้เป็นค่าเริ่มต้นตอนกด Cooking ถ้าหน่วยในสูตรไม่ตรง/สูตรไม่บอกปริมาณ
  late int usePerCook;

  // หน่วยนับชิ้นล่าสุด (เช่น "ผล") จำไว้ตอนสลับไป "แบ่งเป็นส่วน" แล้วกลับมา
  // "นับเป็นชิ้น" จะได้คืนเป็นหน่วยเดิม ไม่ใช่กลายเป็น "ชิ้น"
  String lastPieceUnit = 'ชิ้น';
  late String category; // หมวดหมู่

  // การจัดเก็บ: ประเภทตามตารางอายุการเก็บรักษา (null = ไม่ตรงกับตาราง ใช้ค่า
  // ที่ Gemini ประเมิน), สถานะ (ดิบ/สุก ฯลฯ) และช่องที่เก็บ
  ShelfType? shelfType; // ประเภทในตาราง
  late String foodState; // สถานะ
  late String storage; // ช่องที่เก็บ
  late ResolvedShelfLife shelfLife; // จำนวนวันที่คำนวณได้

  @override
  void initState() {
    super.initState();
    final data = widget.initialData; // ข้อมูลของชิ้นนี้

    nameController = TextEditingController(text: data['name'] ?? ''); // ช่องชื่อ ใส่ค่าเริ่มต้น

    // ค่าเริ่มต้นถูกคำนวณไว้แล้วใน ResultScreen.initState อ่านกลับมาจากข้อมูล
    // ของชิ้นนี้ (การ์ดที่ถูกสร้างใหม่ตอนเลื่อนจอจะได้ไม่รีเซ็ตค่าที่ผู้ใช้เลือก)
    shelfType = findShelfType(data['shelf_type']?.toString());
    foodState =
        data['food_state']?.toString() ?? defaultStateFor(shelfType?.key);
    storage = data['storage']?.toString() ?? storageFridge;
    shelfLife = _resolve(); // คำนวณจำนวนวัน
    expiryController = TextEditingController(
      text: (data['expiry_days'] ?? shelfLife.daysFor(storage) ?? 7).toString(), // จำนวนวันเริ่มต้น
    );

    // ค่าเริ่มต้นจาก Gemini (ดู prompt ใน image_scanning_screen.dart) ถ้า Gemini ตอบ
    // หน่วยที่นับเป็นชิ้นไม่ได้ (เช่น กรัม) ให้เปลี่ยนเป็นแบ่งเป็นส่วนแทน
    final rawUnit = data['count_unit']?.toString().trim() ?? '';
    countMode = data['count_mode'] == 'piece' && rawUnit != 'ส่วน' // หน่วยจาก AI
        ? 'piece'
        : 'portion';
    if (countMode == 'piece' && !pieceUnits.contains(rawUnit)) {
      countMode = rawUnit.isEmpty ? 'piece' : 'portion';
    }
    countUnit = countMode == 'piece'
        ? (pieceUnits.contains(rawUnit) ? rawUnit : 'ชิ้น')
        : 'ส่วน';
    lastPieceUnit = pieceUnits.contains(rawUnit) ? rawUnit : 'ชิ้น';
    count = (num.tryParse(data['count']?.toString() ?? '') ?? 1).round();
    if (count < 1) count = 1; // อย่างน้อย 1
    usePerCook = (num.tryParse(data['use_per_cook']?.toString() ?? '') ?? 1)
        .round();
    if (usePerCook < 1) usePerCook = 1; // อย่างน้อย 1
    _pushCount(); // ส่งค่าเริ่มต้นกลับไป

    // กันเหนียว: normalize หมวดหมู่ให้เข้าเซ็ตที่กำหนดไว้เสมอ (fixedCategories)
    // เผื่อ AI ตอบมาไม่ตรงเป๊ะ หรือเป็นข้อมูลเก่าก่อนแก้ไขนี้
    category = normalizeCategory((data['category'] ?? 'อื่นๆ').toString());

    nameController.addListener(() { // พิมพ์ชื่อ -> ส่งกลับทันที
      widget.onUpdate('name', nameController.text);
    });

    expiryController.addListener(() { // แก้จำนวนวัน -> ส่งกลับ
      // ว่าง = ยังไม่ได้กรอก (ช่องแช่แข็งของที่ไม่มีข้อมูล) -> ตอนบันทึกจะเตือนให้กรอก
      widget.onUpdate('expiry_days', int.tryParse(expiryController.text));
      // จำไว้ว่าผู้ใช้แก้จำนวนวันเองหรือไม่ เพื่อบอกที่มาให้ถูก (และบันทึกเป็น
      // "กำหนดเองโดยผู้ใช้" ตอนบันทึก)
      widget.onUpdate('expiry_custom', _isCustomDays);
      setState(() {}); // วาดใหม่ (อัปเดตวันที่/ที่มา)
    });
  }

  @override
  void dispose() { // ปิดการ์ด คืนหน่วยความจำ
    nameController.dispose();
    expiryController.dispose();
    super.dispose();
  }

  // ใช้ mapping กลางเดียวกับหน้าคลัง (Inventory) เพื่อให้อิโมจิหมวดหมู่ตรงกันทุกหน้า
  String _getEmoji(String cat) => categoryEmoji(cat);

  String _formatNum(num v) => // แสดงตัวเลข: จำนวนเต็มไม่มีทศนิยม
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ส่งค่าการนับทั้งหมดกลับไป
  void _pushCount() {
    widget.onUpdate('count_mode', countMode);
    widget.onUpdate('count', count);
    widget.onUpdate('count_unit', countUnit);
    widget.onUpdate('use_per_cook', usePerCook);
  }

  // บอกให้ชัดว่า 1 ส่วนมีเท่าไหร่ เช่น "3 ลูก แบ่ง 3 ส่วน = ส่วนละประมาณ 1 ลูก"
  // ผู้ใช้จะได้รู้ว่าทำอาหาร 1 ครั้ง (หัก 1 ส่วน) ใช้ของไปเท่าไหร่
  String _portionHint() {
    final q = num.tryParse(widget.initialData['quantity']?.toString() ?? '');
    final u = widget.initialData['unit']?.toString() ?? '';
    if (q != null && q > 0 && count > 0) {
      final per = q / count; // ปริมาณต่อ 1 ส่วน
      final perText = per == per.roundToDouble()
          ? per.toInt().toString()
          : per.toStringAsFixed(1);
      return "${_formatNum(q)} $u แบ่ง $count ส่วน = ส่วนละประมาณ $perText $u "
          "(ทำอาหาร 1 ครั้ง ใช้ 1 ส่วน)";
    }
    return "1 ส่วน = ใช้ทำอาหารได้ 1 ครั้ง";
  }

  // "นับเป็นชิ้น" หักยังไง (สั้นๆ — สูตรที่ระบุจำนวนไว้จะใช้ตามสูตร และแก้ได้ตอนยืนยัน)
  String _pieceHint() => "ทำอาหาร 1 ครั้ง หัก $usePerCook $countUnit";

  // ข้อความ "ตรวจพบจากรูป: 1 แพ็ค" (แสดงอย่างเดียว ไม่ใช้หัก)
  String? _detectedText() {
    final q = num.tryParse(widget.initialData['quantity']?.toString() ?? '');
    final u = widget.initialData['unit']?.toString() ?? '';
    if (q == null) return null;
    return "${_formatNum(q)} $u".trim();
  }

  // ตกแต่งช่องกรอก/ดรอปดาวน์ในการ์ด
  InputDecoration _boxDecoration() => InputDecoration(
    isDense: true, // [UI] แบบกระชับ
    filled: true,
    fillColor: Colors.grey[50], // [UI] สีพื้นช่อง (เทาอ่อนมาก)
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), // [UI] ระยะใน
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
      borderSide: BorderSide(color: Colors.grey.shade300), // [UI] ขอบเทาอ่อน
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  );

  // ป้ายหัวข้อเล็กของแต่ละส่วน
  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.black87,
      fontSize: 13, // [UI] ขนาด 13
      fontWeight: FontWeight.w500, // [UI] หนาปานกลาง
    ),
  );

  // ส่วน "ปริมาณ" — วิธีนับที่ใช้หักตอนทำอาหาร นับเป็นชิ้นที่มองเห็นได้
  // (ไข่ 10 ฟอง) หรือแบ่งเป็นส่วนเอง (หมูสับ 1 แพ็ค แบ่ง 3 ส่วน) ไม่มีกรัม
  Widget _buildCountSection() {
    final detected = _detectedText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("ปริมาณ"),
        if (detected != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              "ตรวจพบจากรูป: $detected",
              style: const TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, // [UI] ระยะห่างชิปแนวนอน
          runSpacing: 8, // [UI] ระยะห่างชิปแนวตั้ง
          children: [
            _buildChip(
              label: "นับเป็นชิ้น",
              selected: countMode == 'piece',
              onTap: () { // เลือก "นับเป็นชิ้น" (คืนหน่วยเดิม)
                setState(() {
                  countMode = 'piece';
                  countUnit = lastPieceUnit;
                });
                _pushCount();
              },
            ),
            _buildChip(
              label: "แบ่งเป็นส่วน",
              selected: countMode == 'portion', // เลือก "แบ่งเป็นส่วน"
              onTap: () {
                setState(() {
                  countMode = 'portion';
                  countUnit = 'ส่วน';
                });
                _pushCount();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildCounterButton("-", () { // ปุ่ม − (ไม่ต่ำกว่า 1)
              if (count > 1) {
                setState(() => count--);
                _pushCount();
              }
            }),
            Container(
              width: 50, // [UI] ความกว้างช่องตัวเลข
              alignment: Alignment.center,
              child: Text(
                "$count",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18, // [UI] ขนาดตัวเลข
                  color: Colors.black87,
                ),
              ),
            ),
            _buildCounterButton("+", () { // ปุ่ม +
              setState(() => count++);
              _pushCount();
            }),
            const SizedBox(width: 12), // [UI] ระยะห่าง
            if (countMode == 'piece') // นับชิ้น -> ดรอปดาวน์เลือกหน่วย
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: countUnit,
                  decoration: _boxDecoration(),
                  items: pieceUnits
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) { // เลือกหน่วยใหม่
                    if (val == null) return;
                    setState(() {
                      countUnit = val;
                      lastPieceUnit = val;
                    });
                    _pushCount();
                  },
                ),
              )
            else // แบ่งส่วน -> หน่วยตายตัว "ส่วน"
              const Text(
                "ส่วน",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
          ],
        ),
        if (countMode == 'piece') ...[ // นับชิ้นถึงมี "ใช้ครั้งละ"
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                "ใช้ครั้งละ",
                style: TextStyle(fontSize: 13, color: Colors.black87), // [UI] ขนาด 13
              ),
              const SizedBox(width: 10),
              _buildCounterButton("-", () { // ปุ่ม − (ไม่ต่ำกว่า 1)
                if (usePerCook > 1) {
                  setState(() => usePerCook--);
                  _pushCount();
                }
              }),
              Container(
                width: 44, // [UI] ความกว้างช่องตัวเลข
                alignment: Alignment.center,
                child: Text(
                  "$usePerCook",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // [UI] ขนาดตัวเลข
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildCounterButton("+", () { // ปุ่ม +
                setState(() => usePerCook++);
                _pushCount();
              }),
              const SizedBox(width: 8),
              Text(
                countUnit,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          countMode == 'portion' ? _portionHint() : _pieceHint(), // คำอธิบายใต้ส่วน (แบ่งส่วน / นับชิ้น)
          style: const TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
        ),
      ],
    );
  }

  // คำนวณจำนวนวันใหม่จากประเภท + สถานะปัจจุบัน
  ResolvedShelfLife _resolve() => resolveShelfLife(
    typeKey: shelfType?.key,
    state: foodState,
    geminiFridgeDays: widget.initialData['gemini_fridge_days'],
    geminiFreezerDays: widget.initialData['gemini_freezer_days'],
  );

  // ส่งค่าการจัดเก็บกลับไปเก็บในข้อมูลของวัตถุดิบชิ้นนี้ เพื่อใช้ตอนบันทึก
  void _pushShelfLife() {
    widget.onUpdate('storage', storage); // ช่องที่เก็บ
    widget.onUpdate('food_state', foodState); // สถานะ
    widget.onUpdate('fridge_days', shelfLife.fridgeDays); // วันช่องปกติ
    // ไม่มีข้อมูลช่องแช่แข็งแต่ผู้ใช้เลือกแช่แข็ง: ใช้จำนวนวันที่ AI ประเมิน (ของที่สแกน)
    // หรือที่ผู้ใช้กรอกเอง — แอปไม่เดาตัวเลขให้
    widget.onUpdate(
      'freezer_days',
      shelfLife.freezerDays ??
          (storage == storageFreezer
              ? int.tryParse(expiryController.text)
              : null),
    );
    widget.onUpdate('expiry_days', int.tryParse(expiryController.text)); // จำนวนวันที่พิมพ์
  }

  // เปลี่ยนช่องที่เก็บ/สถานะแล้ว คำนวณวันหมดอายุเริ่มต้นใหม่ตามตาราง
  void _changeStorage({String? newStorage, String? newState}) {
    setState(() {
      if (newState != null) foodState = newState; // เปลี่ยนสถานะ (ถ้าส่งมา)
      shelfLife = _resolve(); // คำนวณใหม่
      if (newStorage != null) storage = newStorage; // เปลี่ยนช่อง (ถ้าส่งมา)
      expiryController.text = _defaultDays?.toString() ?? ''; // ใส่จำนวนวันเริ่มต้นของช่องใหม่ลงช่องกรอก
    });
    _pushShelfLife(); // ส่งค่ากลับ
  }

  /// จำนวนวันเริ่มต้น: ตามตาราง — ช่องแช่แข็งของที่ไม่มีข้อมูล: ของที่สแกนใช้ค่าที่ AI
  /// ประเมิน ส่วนของที่กรอกเองไม่มีค่าเริ่มต้น (null) ให้ผู้ใช้กรอกเอง
  int? get _defaultDays { // ค่าตามตาราง
    final table = shelfLife.daysFor(storage); // มีในตาราง -> ใช้เลย
    if (table != null) return table; // ไม่มี: ช่องแช่แข็ง = ค่าของ AI, ช่องปกติ = ค่าที่คำนวณได้
    return storage == storageFreezer ? _aiFreezerDays : shelfLife.fridgeDays;
  }

  /// จำนวนวันช่องแช่แข็งที่ AI ประเมินจากรูป (ของที่กรอกเองไม่มี)
  int? get _aiFreezerDays {
    if (_isManual) return null; // กรอกเองไม่มีค่า AI
    final v = num.tryParse('${widget.initialData['gemini_freezer_days']}');
    return (v == null || v <= 0) ? null : v.round();
  }

  /// เตือนว่าไม่แนะนำให้แช่แข็ง เฉพาะของที่ไม่ควรแช่แข็ง (ไข่)
  bool get _warnFreeze => shelfType?.noFreeze ?? false;

  /// ช่องแช่แข็งของประเภทที่ระบบไม่มีข้อมูล -> ใช้จำนวนวันจาก AI (ของที่สแกน)
  /// หรือให้ผู้ใช้กรอกเอง (ของที่กรอกเอง)
  bool get _noFreezerData =>
      storage == storageFreezer &&
      shelfType != null &&
      !shelfType!.hasFreezerData(foodState);

  bool get _isManual => widget.initialData['manual'] == true; // โหมดกรอกเองไหม

  // กรอกเองไม่มี AI ช่วยเลือกประเภท ให้ผู้ใช้เลือกเพื่อใช้ค่าจากตารางอายุการเก็บรักษา
  Widget _buildShelfTypePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("ประเภทวัตถุดิบ"),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          value: shelfType?.key, // ประเภทที่เลือกอยู่
          isExpanded: true, // [UI] กว้างเต็มช่อง
          decoration: _boxDecoration(),
          items: [
            const DropdownMenuItem<String?>(
              value: null, // ตัวเลือก "ไม่ตรงประเภทไหน"
              child: Text("ไม่ตรงประเภทไหน (กำหนดวันเอง)"),
            ),
            ...shelfTypes.map( // ตัวเลือกตามตารางประเภท
              (t) => DropdownMenuItem<String?>(
                value: t.key,
                child: Text(t.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (key) { // เลือกประเภทใหม่
            shelfType = findShelfType(key); // หาประเภท
            widget.onUpdate('shelf_type', shelfType?.key); // ส่งกลับ
            _changeStorage(newState: defaultStateFor(shelfType?.key)); // คำนวณวันใหม่ตามสถานะเริ่มต้นของประเภท
          },
        ),
      ],
    );
  }

  bool get _isCustomDays {
    final typed = int.tryParse(expiryController.text); // ตัวเลขที่พิมพ์
    return typed != null && typed != _defaultDays; // พิมพ์ต่างจากค่าเริ่มต้น = กำหนดเอง
  }

  // กล่องบอกที่มาของวันหมดอายุ — ตารางอายุการเก็บรักษา (พร้อมแหล่งอ้างอิง) /
  // AI ประเมินให้ / ผู้ใช้กำหนดเอง ผู้ใช้จะได้รู้ว่าตัวเลขเชื่อได้แค่ไหน
  Widget _buildShelfSource() {
    final stateText = foodState.isEmpty ? "" : " ($foodState)";
    final defaultText = _defaultDays == null
        ? ""
        : formatShelfDays(_defaultDays!);

    final IconData icon;
    final Color color;
    final String title;
    final String detail;
    if (_isCustomDays) { // ผู้ใช้กำหนดเอง
      icon = Icons.edit_outlined; // [UI] ไอคอนดินสอ
      color = const Color(0xff5189C9); // [UI] สีฟ้า
      title = "คุณกำหนดเอง";
      final warn = _warnFreeze && storage == storageFreezer
          ? " · $freezerNotRecommendedText"
          : "";
      detail = _defaultDays == null
          ? "ไม่มีข้อมูลสำหรับช่องแช่แข็ง$warn"
          : _noFreezerData
          ? "AI ประเมินไว้ $defaultText$warn"
          : "ค่าแนะนำคือ $defaultText";
    } else if (_noFreezerData) { // ไม่มีข้อมูลช่องแช่แข็ง
      // ระบบไม่มีข้อมูลช่องแช่แข็ง -> ของที่สแกนใช้ค่าที่ AI ประเมิน, กรอกเองให้กรอก
      final warn = _warnFreeze ? " · $freezerNotRecommendedText" : "";
      icon = _warnFreeze
          ? Icons.warning_amber_rounded
          : Icons.auto_awesome_outlined;
      color = const Color(0xffE67E22); // [UI] สีส้ม
      if (_defaultDays == null) {
        title = "ไม่มีข้อมูลสำหรับช่องแช่แข็ง";
        detail = "กรอกจำนวนวันที่เก็บได้เอง$warn";
      } else {
        title = "AI ประเมินให้ว่าเก็บได้ $defaultText";
        detail = "ควรตรวจสอบอีกครั้ง$warn";
      }
    } else if (_isManual && shelfType == null) { // กรอกเองและไม่ได้เลือกประเภท
      icon = Icons.info_outline;
      color = const Color(0xffE67E22); // [UI] สีส้ม
      title = "ค่าเริ่มต้น $defaultText";
      detail = "เลือกประเภทวัตถุดิบ หรือแก้จำนวนวันให้ตรงกับของจริง";
    } else if (shelfType != null) { // มีในตาราง
      icon = Icons.verified_outlined; // [UI] ไอคอนยืนยัน
      color = const Color(0xff3F9142); // [UI] สีเขียว
      title =
          "${shelfType!.label}$stateText ${storageLabel(storage)} "
          "เก็บได้ $defaultText";
      detail = "ข้อมูลจาก ${shelfType!.sourceFor(foodState, storage)}";
    } else { // AI ประเมิน
      icon = Icons.auto_awesome_outlined;
      color = const Color(0xffE67E22); // [UI] สีส้ม
      title = "AI ประเมินให้ว่าเก็บได้ $defaultText";
      detail = "ควรตรวจสอบอีกครั้ง";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10), // [UI] ระยะในกล่อง
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08), // [UI] สีพื้น = สีหลักจาง 8%
        borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color), // [UI] ไอคอนขนาด 18
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5, // [UI] ขนาดหัวข้อ
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12, // [UI] ขนาดรายละเอียด
                    color: Colors.black54,
                    height: 1.4, // [UI] ระยะบรรทัด
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ชิปตัวเลือก (เลือกอยู่ = ครีม)
  Widget _buildChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null; // ไม่มี onTap = กดไม่ได้
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [UI] ระยะในชิป
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white, // [UI] เลือกอยู่ = ครีม, ไม่เลือก = ขาว
          borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
          border: Border.all(
            color: selected ? const Color(0xFFFFD191) : Colors.black12, // [UI] เลือกอยู่ = ขอบส้มอ่อน, ไม่เลือก = ขอบเทาจาง
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13, // [UI] ขนาดตัวอักษร
            color: disabled ? Colors.black26 : Colors.black87, // [UI] กดไม่ได้ = จาง
          ),
        ),
      ),
    );
  }

  // ส่วนเลือกช่องที่เก็บ + สถานะ (ดิบ/สุก ฯลฯ)
  Widget _buildStorageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "เก็บไว้ช่องไหน",
          style: TextStyle(
            color: Colors.black87,
            fontSize: 13, // [UI] ขนาด 13
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, // [UI] ระยะห่างชิปแนวนอน
          runSpacing: 8,
          children: [
            _buildChip(
              label: "${storageEmoji(storageFridge)} ช่องปกติ",
              selected: storage == storageFridge,
              onTap: () => _changeStorage(newStorage: storageFridge), // เลือกช่องปกติ
            ),
            // เลือกช่องแช่แข็งได้เสมอ ของที่ไม่มีข้อมูลช่องแช่แข็งแค่ขึ้นว่าไม่แนะนำ
            _buildChip(
              label: "${storageEmoji(storageFreezer)} ช่องแช่แข็ง",
              selected: storage == storageFreezer,
              onTap: () => _changeStorage(newStorage: storageFreezer), // เลือกช่องแช่แข็ง
            ),
          ],
        ),
        if (_warnFreeze) // ของที่ไม่ควรแช่แข็ง -> เตือน
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "*$freezerNotRecommendedText",
              style: TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
            ),
          ),
        if (shelfType != null && shelfType!.stateNames.isNotEmpty) ...[ // มีสถานะให้เลือกถึงแสดง
          const SizedBox(height: 10),
          const Text(
            "สถานะ",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: shelfType!.stateNames
                .map(
                  (st) => _buildChip(
                    label: st,
                    selected: foodState == st,
                    onTap: () => _changeStorage(newState: st), // เลือกสถานะ -> คำนวณวันใหม่
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysToAdd = int.tryParse(expiryController.text); // จำนวนวันที่พิมพ์
    final expiryDate = daysToAdd == null // วันหมดอายุ = วันนี้ + จำนวนวัน
        ? null
        : DateTime.now().add(Duration(days: daysToAdd));
    final expiryDateString = expiryDate == null
        ? "-"
        : "${expiryDate.day}/${expiryDate.month}/${expiryDate.year + 543}"; // แสดงเป็น วัน/เดือน/ปี พ.ศ.

    return Container(
      margin: const EdgeInsets.only(bottom: 16), // [UI] ระยะใต้การ์ด
      padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นขาว
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)), // [UI] เงา ความฟุ้ง 4
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ส่วนหัว: หมวดหมู่ (เลือกได้จากรายการที่กำหนดไว้เท่านั้น) และ Emoji
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12), // [UI] ระยะในกล่องหมวดหมู่
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCDC), // [UI] สีครีม
                  borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง
                  border: Border.all(color: const Color(0xFFFFD191)), // [UI] ขอบส้มอ่อน
                ),
                child: DropdownButtonHideUnderline( // ซ่อนเส้นใต้ดรอปดาวน์
                  child: DropdownButton<String>(
                    value: category, // หมวดที่เลือก
                    isDense: true,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    items: fixedCategories // ตัวเลือก = หมวดที่กำหนดไว้
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) { // เลือกหมวดใหม่
                      if (val == null) return;
                      setState(() => category = val);
                      widget.onUpdate('category', val);
                    },
                  ),
                ),
              ),
              const Spacer(), // ดันอิโมจิไปชิดขวา
              Text(_getEmoji(category), style: const TextStyle(fontSize: 30)), // [UI] อิโมจิหมวด ขนาด 30
              if (widget.onRemove != null) // มีปุ่มลบถึงแสดง
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: "ลบรายการนี้",
                  icon: const Icon(Icons.close, color: Colors.black54), // [UI] ไอคอน X สีเทา
                ),
            ],
          ),

          const SizedBox(height: 12), // [UI] ระยะห่างระหว่างส่วน

          // 2. ชื่อวัตถุดิบ
          const Text(
            "ชื่อวัตถุดิบ",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 13, // [UI] ขนาด 13
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          TextFormField( // ช่องชื่อวัตถุดิบ
            controller: nameController,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey[50], // [UI] สีพื้นช่อง
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
                borderSide: BorderSide(color: Colors.grey.shade300), // [UI] ขอบเทาอ่อน
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, // [UI] ระยะในซ้ายขวา
                vertical: 12, // [UI] ระยะในบนล่าง
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3. วิธีนับเพื่อหักใช้ (นับเป็นชิ้น / แบ่งเป็นส่วน)
          _buildCountSection(), // ส่วนปริมาณ

          const SizedBox(height: 12),

          if (_isManual) ...[ // กรอกเอง -> ให้เลือกประเภท
            _buildShelfTypePicker(),
            const SizedBox(height: 12),
          ],

          // 4. ช่องที่เก็บ + สถานะ (ใช้คำนวณวันหมดอายุเริ่มต้น)
          _buildStorageSection(), // ส่วนช่องที่เก็บ

          const SizedBox(height: 12),

          // 5. อายุการเก็บรักษา (คำนวณอัตโนมัติจากตาราง แก้ไขเองได้)
          Container(
            padding: const EdgeInsets.all(12), // [UI] ระยะในกล่อง
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCDC), // [UI] สีครีม
              border: Border.all(color: const Color(0xFFFFD191)), // [UI] ขอบส้มอ่อน
              borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง 15
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "อายุการเก็บรักษา:",
                        style: TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
                      ),
                      SizedBox(
                        height: 30, // [UI] ความสูงช่องกรอกจำนวนวัน
                        child: TextFormField(
                          controller: expiryController,
                          keyboardType: TextInputType.number, // [UI] แป้นตัวเลข
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none, // [UI] ไม่มีเส้นขอบ
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            suffixText: "วัน", // [UI] คำว่า "วัน" ต่อท้าย
                            hintText: "กรอกจำนวนวัน", // [UI] ข้อความจางตอนว่าง
                            hintStyle: TextStyle(
                              fontWeight: FontWeight.normal,
                              color: Colors.black38,
                            ),
                          ),
                          onChanged: (val) => setState(() {}), // พิมพ์แล้ววาดใหม่ (อัปเดตวันที่)
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: const Color(0xFFFFD191)), // [UI] เส้นคั่นแนวตั้ง
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "เก็บได้ถึงวันที่",
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    Text(
                      expiryDateString,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE62020), // [UI] วันที่สีแดง
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildShelfSource(), // กล่องบอกที่มาของจำนวนวัน
        ],
      ),
    );
  }

  // ปุ่ม − / + (ข้อความในปุ่ม = icon)
  Widget _buildCounterButton(String icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 38, // [UI] ขนาดปุ่ม 38x38
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCDC), // [UI] สีครีม
          borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
          border: Border.all(color: const Color(0xFFFFD191)), // [UI] ขอบส้มอ่อน
        ),
        child: Text(
          icon,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20, // [UI] ขนาดเครื่องหมาย
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
