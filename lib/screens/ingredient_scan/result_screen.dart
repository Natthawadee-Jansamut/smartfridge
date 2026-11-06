import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:test_app/services/fridge_images.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/fridge/inventory_screen.dart';

/// หน้าผลลัพธ์หลังสแกนวัตถุดิบ (ตามดีไซน์ใน Figma: "SCAN" - ผลลัพธ์)
/// รูปที่แสดงในการ์ด "รูปภาพ" คือรูปจริงที่ผู้ใช้ถ่าย/เลือกมา (ไม่ใช่รูป mock)
class ResultScreen extends StatefulWidget {
  final List<dynamic> foundItems;
  final Uint8List? imageBytes;

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
    super.initState();

    if (widget.manual && widget.foundItems.isEmpty) {
      widget.foundItems.add(_newManualItem());
    }

    // จัดกลุ่มวัตถุดิบที่สแกนเจอให้หมวดหมู่เดียวกันอยู่ติดกัน จะได้ไล่ดูง่าย
    // ใช้ index เดิมเป็นตัวตัดสินลำดับรองเพื่อให้เรียงแบบ stable (ของในหมวด
    // เดียวกันยังอยู่ตามลำดับที่สแกนเจอ ไม่สลับกันไปมา)
    final indexed = widget.foundItems.asMap().entries.toList();
    indexed.sort((a, b) {
      final catA =
          (a.value is Map ? a.value['category']?.toString() : null) ?? "อื่นๆ";
      final catB =
          (b.value is Map ? b.value['category']?.toString() : null) ?? "อื่นๆ";
      final catCompare = catA.compareTo(catB);
      if (catCompare != 0) return catCompare;
      return a.key.compareTo(b.key);
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

  void _prepareStorage(Map item) {
    item['gemini_fridge_days'] = item['fridge_days'];
    item['gemini_freezer_days'] = item['freezer_days'];
    final typeKey = findShelfType(item['shelf_type']?.toString())?.key;
    final state = defaultStateFor(typeKey);
    final life = resolveShelfLife(
      typeKey: typeKey,
      state: state,
      geminiFridgeDays: item['gemini_fridge_days'],
      geminiFreezerDays: item['gemini_freezer_days'],
    );
    item['shelf_type'] = typeKey;
    item['food_state'] = state;
    item['storage'] = storageFridge;
    item['fridge_days'] = life.fridgeDays;
    item['freezer_days'] = life.freezerDays;
    item['expiry_days'] = life.fridgeDays;
  }

  Map<String, dynamic> _newManualItem() => {
    'manual': true,
    'name': '',
    'category': widget.initialCategory ?? 'อื่นๆ',
    'count_mode': 'piece',
    'count': 1,
    'count_unit': 'ชิ้น',
  };

  void _addManualItem() {
    final item = _newManualItem();
    _prepareStorage(item);
    setState(() => widget.foundItems.add(item));
  }

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
      backgroundColor: const Color(0xFFD8EEFF),
      body: SafeArea(
        child: Column(
          children: [
            IngredientFlowHeader(
              title: widget.manual ? "นำเข้าวัตถุดิบด้วยตัวเอง" : "ผลลัพธ์",
            ),
            const SizedBox(height: 15),

            // --- ป้ายบอกจำนวนวัตถุดิบที่พบ ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
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
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // --- การ์ด "รูปภาพ" (รูปจริงที่ถ่าย/เลือกมาสแกน) ---
            if (!widget.manual) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  width: double.infinity,
                  // เพิ่มความสูงจาก 200 เป็น 320 เพื่อให้มีที่พอแสดงรูปเต็มๆ
                  // ไม่ต้องครอปแน่นจนเกินไป (ของเดิมกล่องเตี้ยเกินไปเทียบกับรูปโหมด
                  // แนวตั้งจากกล้อง ทำให้ครอปหายไปเยอะ)
                  height: 320,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCDC),
                          border: Border.all(color: const Color(0xFFFFD191)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "รูปภาพ",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            alignment: Alignment.center,
                            // พื้นหลังสีเทาอ่อนไว้รองรับรูปที่สัดส่วนไม่พอดีกรอบ
                            // (BoxFit.contain จะไม่ครอปรูปแต่จะเห็นแถบพื้นหลังนี้แทน)
                            color: Colors.grey.shade100,
                            child: widget.imageBytes != null
                                ? Image.memory(
                                    widget.imageBytes!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    // เปลี่ยนจาก cover เป็น contain เพื่อให้เห็นรูปที่ถ่ายมา
                                    // แบบเต็มๆ ไม่ถูกครอปขอบออกเหมือนก่อนหน้านี้
                                    fit: BoxFit.contain,
                                  )
                                : Icon(
                                    Icons.image_outlined,
                                    size: 36,
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
                        style: TextStyle(color: Colors.black54, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
                      itemCount:
                          widget.foundItems.length + (widget.manual ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == widget.foundItems.length) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: OutlinedButton.icon(
                              onPressed: _addManualItem,
                              icon: const Icon(Icons.add),
                              label: const Text("เพิ่มอีกรายการ"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xff5189C9),
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          );
                        }
                        final item = widget.foundItems[index];
                        return IngredientCardItem(
                          // ผูกการ์ดกับข้อมูลชิ้นนั้น ลบรายการแล้วค่าจะได้ไม่สลับการ์ด
                          key: ObjectKey(item),
                          initialData: item as Map<String, dynamic>,
                          onUpdate: (key, value) {
                            item[key] = value;
                          },
                          onRemove:
                              widget.manual && widget.foundItems.length > 1
                              ? () => _confirmRemoveItem(item)
                              : null,
                        );
                      },
                    ),
            ),

            // --- ปุ่มกดด้านล่าง (Footer) ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB6B6B6),
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          widget.manual ? "ยกเลิก" : "สแกนใหม่",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveToSupabase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD7EDFF),
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
                            CheckIcon(size: 18),
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

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาล็อกอินก่อนบันทึกข้อมูล'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.foundItems.any(
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );

    try {
      // รูปที่ใช้สแกน: อัปโหลดครั้งเดียว ทุกวัตถุดิบจากรูปนี้ชี้ไปที่รูปเดียวกัน
      // (ไม่สำเร็จก็บันทึกวัตถุดิบต่อได้ แค่ไม่มีรูป)
      final imagePath = widget.imageBytes == null
          ? null
          : await uploadFridgeImage(user.id, widget.imageBytes!);

      // หลัก FIFO: ซื้อวัตถุดิบชนิดเดิมมาเพิ่มเมื่อไหร่ ก็บันทึกแยกเป็นลอตใหม่
      // (แถวใหม่) เสมอ ไม่รวมเข้ากับลอตเดิม เพื่อให้แต่ละลอตมีวันที่เข้าตู้เย็น
      // และวันหมดอายุของตัวเอง ตอนทำอาหารระบบจะหักจากลอตที่ใกล้หมดอายุก่อน
      for (var item in widget.foundItems) {
        String name = item['name'].toString().trim();
        final storage = item['storage']?.toString() ?? storageFridge;
        int days = int.tryParse(item['expiry_days'].toString()) ?? 7;
        DateTime expiryDate = DateTime.now().add(Duration(days: days));
        final foodState = item['food_state']?.toString() ?? '';

        // ปริมาณที่ตรวจพบจากรูป (เช่น 1 แพ็ค 500 กรัม) เก็บไว้แสดงเฉยๆ ว่าซื้อมา
        // เท่าไหร่ ส่วนที่ใช้นับ/หักตอนทำอาหารคือจำนวนชิ้นหรือจำนวนส่วนที่ผู้ใช้
        // ยืนยัน (คนทำอาหารไม่ได้ชั่ง จึงไม่นับเป็นกรัม)
        final detectedQty = num.tryParse(item['quantity'].toString());
        final detectedUnit = item['unit']?.toString();
        // (การ์ดที่ยังไม่ถูกเลื่อนมาแสดงจะยังไม่ได้ normalize ค่าจาก Gemini จึง
        // กันไว้ตรงนี้อีกชั้น: หน่วยที่นับเป็นชิ้นไม่ได้ เช่น กรัม → เป็นส่วน)
        final rawCountUnit = item['count_unit']?.toString().trim() ?? '';
        final isPiece =
            item['count_mode'] == 'piece' && pieceUnits.contains(rawCountUnit);
        final num stockQty =
            (num.tryParse(item['count']?.toString() ?? '') ?? 1).round().clamp(
              1,
              1 << 30,
            );
        final stockUnit = isPiece ? rawCountUnit : 'ส่วน';
        // กรอกเองแล้วไม่ได้เลือกประเภท ค่าวันมาจากผู้ใช้ ไม่ใช่ AI หรือตาราง
        final isCustom =
            item['expiry_custom'] == true ||
            (item['manual'] == true && item['shelf_type'] == null);

        await supabase.from('fridge_items').insert({
          'user_id': user.id,
          // วันที่เข้าตู้เย็น — ตาราง fridge_items ไม่มีค่าเริ่มต้นให้คอลัมน์นี้
          // ถ้าไม่ใส่จะเป็นค่าว่าง แล้วหน้าแจ้งเตือน/การนับวันจะไม่เห็นของชิ้นนี้
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'name': name,
          'category': item['category'],
          'quantity': stockQty,
          'max_quantity': stockQty,
          'unit': stockUnit,
          'detected_quantity': detectedQty,
          'detected_unit': detectedUnit,
          // expiry_date เป็น timestamptz ต้องส่งเป็น UTC (มี Z) ไม่งั้นเลื่อน 7 ชม.
          'expiry_date': expiryDate.toUtc().toIso8601String(),
          'storage': storage,
          'food_state': foodState.isEmpty ? null : foodState,
          'fridge_days': item['fridge_days'],
          'freezer_days': item['freezer_days'],
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
          if (imagePath != null) 'image_path': imagePath,
        });
      }

      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกข้อมูลเรียบร้อย!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const InventoryScreen()),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
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
  final Map<String, dynamic> initialData;
  final Function(String key, dynamic value) onUpdate;
  final VoidCallback? onRemove;

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
  late TextEditingController nameController;
  late TextEditingController expiryController;
  // วิธีนับเพื่อหักใช้ตอนทำอาหาร (ไม่มีกรัม — คนทำอาหารไม่ได้ชั่ง):
  // 'piece' = นับเป็นชิ้น (ฟอง/ผล/หัว ฯลฯ), 'portion' = แบ่งเป็นส่วนเอง
  late String countMode;
  late int count;
  late String countUnit;

  // นับเป็นชิ้น: ทำอาหาร 1 ครั้งใช้กี่ชิ้น (เช่น ไข่ ครั้งละ 2 ฟอง)
  // ใช้เป็นค่าเริ่มต้นตอนกด Cooking ถ้าหน่วยในสูตรไม่ตรง/สูตรไม่บอกปริมาณ
  late int usePerCook;

  // หน่วยนับชิ้นล่าสุด (เช่น "ผล") จำไว้ตอนสลับไป "แบ่งเป็นส่วน" แล้วกลับมา
  // "นับเป็นชิ้น" จะได้คืนเป็นหน่วยเดิม ไม่ใช่กลายเป็น "ชิ้น"
  String lastPieceUnit = 'ชิ้น';
  late String category;

  // การจัดเก็บ: ประเภทตามตารางอายุการเก็บรักษา (null = ไม่ตรงกับตาราง ใช้ค่า
  // ที่ Gemini ประเมิน), สถานะ (ดิบ/สุก ฯลฯ) และช่องที่เก็บ
  ShelfType? shelfType;
  late String foodState;
  late String storage;
  late ResolvedShelfLife shelfLife;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;

    nameController = TextEditingController(text: data['name'] ?? '');

    // ค่าเริ่มต้นถูกคำนวณไว้แล้วใน ResultScreen.initState อ่านกลับมาจากข้อมูล
    // ของชิ้นนี้ (การ์ดที่ถูกสร้างใหม่ตอนเลื่อนจอจะได้ไม่รีเซ็ตค่าที่ผู้ใช้เลือก)
    shelfType = findShelfType(data['shelf_type']?.toString());
    foodState =
        data['food_state']?.toString() ?? defaultStateFor(shelfType?.key);
    storage = data['storage']?.toString() ?? storageFridge;
    shelfLife = _resolve();
    expiryController = TextEditingController(
      text: (data['expiry_days'] ?? shelfLife.daysFor(storage) ?? 7).toString(),
    );

    // ค่าเริ่มต้นจาก Gemini (ดู prompt ใน image_scanning_screen.dart) ถ้า Gemini ตอบ
    // หน่วยที่นับเป็นชิ้นไม่ได้ (เช่น กรัม) ให้เปลี่ยนเป็นแบ่งเป็นส่วนแทน
    final rawUnit = data['count_unit']?.toString().trim() ?? '';
    countMode = data['count_mode'] == 'piece' && rawUnit != 'ส่วน'
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
    if (count < 1) count = 1;
    usePerCook = (num.tryParse(data['use_per_cook']?.toString() ?? '') ?? 1)
        .round();
    if (usePerCook < 1) usePerCook = 1;
    _pushCount();

    // กันเหนียว: normalize หมวดหมู่ให้เข้าเซ็ตที่กำหนดไว้เสมอ (fixedCategories)
    // เผื่อ AI ตอบมาไม่ตรงเป๊ะ หรือเป็นข้อมูลเก่าก่อนแก้ไขนี้
    category = normalizeCategory((data['category'] ?? 'อื่นๆ').toString());

    nameController.addListener(() {
      widget.onUpdate('name', nameController.text);
    });

    expiryController.addListener(() {
      int? val = int.tryParse(expiryController.text);
      if (val != null) widget.onUpdate('expiry_days', val);
      // จำไว้ว่าผู้ใช้แก้จำนวนวันเองหรือไม่ เพื่อบอกที่มาให้ถูก (และบันทึกเป็น
      // "กำหนดเองโดยผู้ใช้" ตอนบันทึก)
      widget.onUpdate('expiry_custom', _isCustomDays);
      setState(() {});
    });
  }

  @override
  void dispose() {
    nameController.dispose();
    expiryController.dispose();
    super.dispose();
  }

  // ใช้ mapping กลางเดียวกับหน้าคลัง (Inventory) เพื่อให้อิโมจิหมวดหมู่ตรงกันทุกหน้า
  String _getEmoji(String cat) => categoryEmoji(cat);

  String _formatNum(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      final per = q / count;
      final perText = per == per.roundToDouble()
          ? per.toInt().toString()
          : per.toStringAsFixed(1);
      return "${_formatNum(q)} $u แบ่ง $count ส่วน = ส่วนละประมาณ $perText $u "
          "(ทำอาหาร 1 ครั้ง ใช้ 1 ส่วน)";
    }
    return "1 ส่วน = ใช้ทำอาหารได้ 1 ครั้ง";
  }

  // บอกให้ชัดว่า "นับเป็นชิ้น" หักยังไง เช่น "มี 6 ฟอง ใช้ไปกี่ฟองก็หักเท่านั้น"
  String _pieceHint() =>
      "ทำอาหาร 1 ครั้ง ระบบจะเสนอให้หัก $usePerCook $countUnit "
      "(ถ้าสูตรบอกจำนวน$countUnitไว้ จะใช้ตามสูตร) แก้ได้ก่อนยืนยันทุกครั้ง";

  // ข้อความ "ตรวจพบจากรูป: 1 แพ็ค" (แสดงอย่างเดียว ไม่ใช้หัก)
  String? _detectedText() {
    final q = num.tryParse(widget.initialData['quantity']?.toString() ?? '');
    final u = widget.initialData['unit']?.toString() ?? '';
    if (q == null) return null;
    return "${_formatNum(q)} $u".trim();
  }

  InputDecoration _boxDecoration() => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: Colors.grey[50],
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.black87,
      fontSize: 13,
      fontWeight: FontWeight.w500,
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
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildChip(
              label: "นับเป็นชิ้น",
              selected: countMode == 'piece',
              onTap: () {
                setState(() {
                  countMode = 'piece';
                  countUnit = lastPieceUnit;
                });
                _pushCount();
              },
            ),
            _buildChip(
              label: "แบ่งเป็นส่วน",
              selected: countMode == 'portion',
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
            _buildCounterButton("-", () {
              if (count > 1) {
                setState(() => count--);
                _pushCount();
              }
            }),
            Container(
              width: 50,
              alignment: Alignment.center,
              child: Text(
                "$count",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87,
                ),
              ),
            ),
            _buildCounterButton("+", () {
              setState(() => count++);
              _pushCount();
            }),
            const SizedBox(width: 12),
            if (countMode == 'piece')
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: countUnit,
                  decoration: _boxDecoration(),
                  items: pieceUnits
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      countUnit = val;
                      lastPieceUnit = val;
                    });
                    _pushCount();
                  },
                ),
              )
            else
              const Text(
                "ส่วน",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
          ],
        ),
        if (countMode == 'piece') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                "ใช้ครั้งละ",
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(width: 10),
              _buildCounterButton("-", () {
                if (usePerCook > 1) {
                  setState(() => usePerCook--);
                  _pushCount();
                }
              }),
              Container(
                width: 44,
                alignment: Alignment.center,
                child: Text(
                  "$usePerCook",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildCounterButton("+", () {
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
          countMode == 'portion' ? _portionHint() : _pieceHint(),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  ResolvedShelfLife _resolve() => resolveShelfLife(
    typeKey: shelfType?.key,
    state: foodState,
    geminiFridgeDays: widget.initialData['gemini_fridge_days'],
    geminiFreezerDays: widget.initialData['gemini_freezer_days'],
  );

  // ส่งค่าการจัดเก็บกลับไปเก็บในข้อมูลของวัตถุดิบชิ้นนี้ เพื่อใช้ตอนบันทึก
  void _pushShelfLife() {
    widget.onUpdate('storage', storage);
    widget.onUpdate('food_state', foodState);
    widget.onUpdate('fridge_days', shelfLife.fridgeDays);
    widget.onUpdate('freezer_days', shelfLife.freezerDays);
    widget.onUpdate(
      'expiry_days',
      int.tryParse(expiryController.text) ?? shelfLife.fridgeDays,
    );
  }

  // เปลี่ยนช่องที่เก็บ/สถานะแล้ว คำนวณวันหมดอายุเริ่มต้นใหม่ตามตาราง
  void _changeStorage({String? newStorage, String? newState}) {
    setState(() {
      if (newState != null) foodState = newState;
      shelfLife = _resolve();
      if (newStorage != null) storage = newStorage;
      if (shelfLife.daysFor(storage) == null) storage = storageFridge;
      expiryController.text = shelfLife.daysFor(storage).toString();
    });
    _pushShelfLife();
  }

  int? get _defaultDays => shelfLife.daysFor(storage);

  bool get _isManual => widget.initialData['manual'] == true;

  // กรอกเองไม่มี AI ช่วยเลือกประเภท ให้ผู้ใช้เลือกเพื่อใช้ค่าจากตารางอายุการเก็บรักษา
  Widget _buildShelfTypePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel("ประเภทวัตถุดิบ"),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          value: shelfType?.key,
          isExpanded: true,
          decoration: _boxDecoration(),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text("ไม่ตรงประเภทไหน (กำหนดวันเอง)"),
            ),
            ...shelfTypes.map(
              (t) => DropdownMenuItem<String?>(
                value: t.key,
                child: Text(t.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (key) {
            shelfType = findShelfType(key);
            widget.onUpdate('shelf_type', shelfType?.key);
            _changeStorage(newState: defaultStateFor(shelfType?.key));
          },
        ),
      ],
    );
  }

  bool get _isCustomDays {
    final typed = int.tryParse(expiryController.text);
    return typed != null && typed != _defaultDays;
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
    if (_isCustomDays) {
      icon = Icons.edit_outlined;
      color = const Color(0xff5189C9);
      title = "คุณกำหนดเอง";
      detail = "ค่าแนะนำคือ $defaultText";
    } else if (_isManual && shelfType == null) {
      icon = Icons.info_outline;
      color = const Color(0xffE67E22);
      title = "ค่าเริ่มต้น $defaultText";
      detail = "เลือกประเภทวัตถุดิบ หรือแก้จำนวนวันให้ตรงกับของจริง";
    } else if (shelfType != null) {
      icon = Icons.verified_outlined;
      color = const Color(0xff3F9142);
      title =
          "${shelfType!.label}$stateText ${storageLabel(storage)} "
          "เก็บได้ $defaultText";
      detail = "ข้อมูลจาก ${shelfType!.source}";
    } else {
      icon = Icons.auto_awesome_outlined;
      color = const Color(0xffE67E22);
      title = "AI ประเมินให้ว่าเก็บได้ $defaultText";
      detail = "ควรตรวจสอบอีกครั้ง";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFFD191) : Colors.black12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: disabled ? Colors.black26 : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildStorageSection() {
    final canFreeze = shelfLife.freezerDays != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "เก็บไว้ช่องไหน",
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
          children: [
            _buildChip(
              label: "${storageEmoji(storageFridge)} ช่องปกติ",
              selected: storage == storageFridge,
              onTap: () => _changeStorage(newStorage: storageFridge),
            ),
            // แสดงตัวเลือกช่องแช่แข็งเฉพาะวัตถุดิบที่มีข้อมูลการแช่แข็ง
            if (canFreeze)
              _buildChip(
                label: "${storageEmoji(storageFreezer)} ช่องแช่แข็ง",
                selected: storage == storageFreezer,
                onTap: () => _changeStorage(newStorage: storageFreezer),
              ),
          ],
        ),
        if (shelfType?.noFreeze ?? false)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "*ไม่ควรเก็บในช่องแช่แข็ง",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        if (shelfType != null && shelfType!.stateNames.isNotEmpty) ...[
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
                    onTap: () => _changeStorage(newState: st),
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
    int daysToAdd = int.tryParse(expiryController.text) ?? 7;
    final expiryDate = DateTime.now().add(Duration(days: daysToAdd));
    final expiryDateString =
        "${expiryDate.day}/${expiryDate.month}/${expiryDate.year + 543}";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCDC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD191)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: category,
                    isDense: true,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    items: fixedCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => category = val);
                      widget.onUpdate('category', val);
                    },
                  ),
                ),
              ),
              const Spacer(),
              Text(_getEmoji(category), style: const TextStyle(fontSize: 30)),
              if (widget.onRemove != null)
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: "ลบรายการนี้",
                  icon: const Icon(Icons.close, color: Colors.black54),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // 2. ชื่อวัตถุดิบ
          const Text(
            "ชื่อวัตถุดิบ",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          TextFormField(
            controller: nameController,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3. วิธีนับเพื่อหักใช้ (นับเป็นชิ้น / แบ่งเป็นส่วน)
          _buildCountSection(),

          const SizedBox(height: 12),

          if (_isManual) ...[
            _buildShelfTypePicker(),
            const SizedBox(height: 12),
          ],

          // 4. ช่องที่เก็บ + สถานะ (ใช้คำนวณวันหมดอายุเริ่มต้น)
          _buildStorageSection(),

          const SizedBox(height: 12),

          // 5. อายุการเก็บรักษา (คำนวณอัตโนมัติจากตาราง แก้ไขเองได้)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCDC),
              border: Border.all(color: const Color(0xFFFFD191)),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "อายุการเก็บรักษา:",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      SizedBox(
                        height: 30,
                        child: TextFormField(
                          controller: expiryController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            suffixText: "วัน",
                          ),
                          onChanged: (val) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: const Color(0xFFFFD191)),
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
                        color: Color(0xFFE62020),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildShelfSource(),
        ],
      ),
    );
  }

  Widget _buildCounterButton(String icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCDC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFD191)),
        ),
        child: Text(
          icon,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
