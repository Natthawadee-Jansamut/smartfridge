import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/services/fridge_images.dart'; // ถังเก็บรูปวัตถุดิบ
import 'package:test_app/widgets/recipe_flow_widgets.dart'; // PrivateScanImage (รูปที่ใช้สแกน)

// หน้ารายละเอียดวัตถุดิบ 1 ชิ้น (แตะแต่ละแถวเพื่อแก้ไข)
class ItemDetailScreen extends StatefulWidget {
  final String itemId; // รับไอดีจากหน้าคลัง

  const ItemDetailScreen({
    super.key,
    required this.itemId,
    required Map<String, dynamic> itemData,
  });

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  Map<String, dynamic>? _item; // ข้อมูลวัตถุดิบ (null = ไม่เจอ)
  bool _isLoading = true; // กำลังโหลดไหม

  @override
  void initState() {
    super.initState();
    _fetchItemDetails(); // เปิดหน้ามาโหลดข้อมูล
  }

  // --- ดึงข้อมูลจาก Supabase ---
  Future<void> _fetchItemDetails() async {
    try {
      final response = await Supabase.instance.client
          .from('fridge_items') // ตารางของในตู้
          .select()
          .eq('item_id', widget.itemId) // เฉพาะชิ้นนี้
          .single(); // เอาแถวเดียว

      if (mounted) {
        setState(() {
          _item = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _item = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // อัปเดต 1 ช่อง (เรียกตัวอัปเดตหลายช่อง)
            content: Text("ดึงข้อมูลไม่สำเร็จ: $e"),
            backgroundColor: Colors.red,
          // อัปเดตหลายช่องพร้อมกัน แล้วโหลดใหม่
          ),
        );
      }
    }
  }

  // --- 🚀 ฟังก์ชันอัปเดตข้อมูลขึ้น Supabase ---
  Future<void> _updateField(String field, dynamic value) =>
      _updateFields({field: value});

  Future<void> _updateFields(Map<String, dynamic> fields) async {
    // แสดง Loading ตอนกำลังเซฟ
    showDialog(
      context: context,
      barrierDismissible: false, // [UI] แตะข้างนอกปิดไม่ได้
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await Supabase.instance.client
          .from('fridge_items')
          .update(fields) // บันทึกลงฐานข้อมูล
          .eq('item_id', widget.itemId);

      if (mounted) Navigator.pop(context); // ปิด Loading
      _fetchItemDetails(); // โหลดข้อมูลใหม่มาโชว์

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตข้อมูลสำเร็จ!'),
            backgroundColor: Colors.green, // [UI] แถบเขียว = สำเร็จ
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red, // [UI] แถบแดง = error
          ),
        );
      }
    }
  }

  // --- 🚀 Popup สำหรับพิมพ์แก้ไขข้อความหรือตัวเลข ---
  // ป๊อปอัปแก้ข้อความ/ตัวเลขทั่วไป (เช่นชื่อ)
  Future<void> _showEditDialog(
    String title, // ชื่อสิ่งที่จะแก้ (แสดงในหัวป๊อปอัป)
    String field, // ชื่อคอลัมน์ในฐานข้อมูล
    String currentValue, { // ค่าปัจจุบัน
    bool isNumber = false, // true = รับเฉพาะตัวเลข
  }) async {
    TextEditingController controller = TextEditingController( // ช่องกรอก ใส่ค่าเดิมไว้ก่อน
      text: currentValue,
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'แก้ไข$title',
          style: const TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
        ),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text, // ตัวเลข = แป้นตัวเลข
          decoration: InputDecoration(
            hintText: 'กรอก$titleใหม่',
            filled: true, // [UI] พื้นช่อง
            fillColor: Colors.grey[100], // [UI] สีเทาอ่อน
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
              borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)), // [UI] ปุ่มยกเลิกสีเทา
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, // [UI] ปุ่มบันทึกสีส้ม
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context); // ปิดป๊อปอัป
              dynamic newValue = isNumber // แปลงค่า (ตัวเลข/ข้อความ)
                  ? int.tryParse(controller.text)
                  : controller.text;
              if (newValue != null && newValue.toString().isNotEmpty) { // ค่าไม่ว่างถึงบันทึก
                _updateField(field, newValue);
              }
            },
            child: const Text('บันทึก', style: TextStyle(color: Colors.white)), // [UI] ตัวอักษรขาว
          ),
        ],
      ),
    );
  }

  // แสดงตัวเลข: จำนวนเต็มไม่มีทศนิยม ไม่งั้น 1 ตำแหน่ง
  String _fmtQty(dynamic v) {
    final n = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }

  // --- 🚀 Popup แก้จำนวน: แก้ได้ทั้ง "เหลืออยู่" และ "ทั้งหมด" (ปริมาณตอนเก็บ
  // เข้าตู้เย็น) — ใช้แก้ตอนใส่จำนวนตั้งต้นผิด หรือกดปุ่มในหน้าคลังผิด ---
  Future<void> _showQuantityDialog() async {
    final currentUnit = _item!['unit']?.toString() ?? 'ชิ้น'; // หน่วยปัจจุบัน
    // วิธีนับ: "แบ่งเป็นส่วน" (หน่วย ส่วน) หรือ "นับเป็นชิ้น" (ฟอง/ผล/หัว ฯลฯ)
    // เปลี่ยนไปมาได้ จำหน่วยนับชิ้นล่าสุดไว้ สลับกลับมาจะได้หน่วยเดิม
    bool isPortion = currentUnit == portionUnit; // แบ่งเป็นส่วนอยู่ไหม
    String pieceUnit = isPortion ? 'ชิ้น' : currentUnit; // หน่วยนับชิ้น (จำไว้ตอนสลับ)
    // หน่วยเก่าที่ไม่อยู่ในรายการ (เช่น กรัม จากข้อมูลก่อนหน้า) ให้ยังเลือกได้
    final units = pieceUnits.contains(pieceUnit) // รายการหน่วยให้เลือก
        ? pieceUnits
        : [pieceUnit, ...pieceUnits];

    final remainController = TextEditingController( // ช่องจำนวนที่เหลือ
      text: _fmtQty(_item!['quantity']),
    );
    final totalController = TextEditingController( // ช่องจำนวนทั้งหมด
      text: _fmtQty(_item!['max_quantity'] ?? _item!['quantity']),
    );
    // นับเป็นชิ้น: ทำอาหาร 1 ครั้งใช้กี่ชิ้น
    final perCookController = TextEditingController( // ช่อง "ใช้ครั้งละ"
      text: _fmtQty(_item!['use_per_cook'] ?? 1),
    );

    // ตัวช่วยตกแต่งช่องกรอก (ป้าย + หน่วยท้ายช่อง)
    InputDecoration deco(String label, String unit) => InputDecoration(
      labelText: label,
      suffixText: unit, // [UI] หน่วยต่อท้ายในช่อง
      filled: true,
      fillColor: Colors.grey[100], // [UI] สีพื้นช่อง
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
        borderSide: BorderSide.none,
      ),
    );

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // ให้ป๊อปอัปวาดใหม่ได้ตอนสลับโหมด
        builder: (context, setDialogState) {
          final unit = isPortion ? portionUnit : pieceUnit; // หน่วยที่ใช้ตอนนี้
          return AlertDialog(
            title: const Text(
              'แก้ไขจำนวน',
              style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8, // [UI] ระยะห่างระหว่างชิป
                    children: [
                      ChoiceChip(
                        label: const Text('นับเป็นชิ้น'),
                        selected: !isPortion,
                        onSelected: (_) =>
                            setDialogState(() => isPortion = false), // เลือก "นับเป็นชิ้น"
                      ),
                      ChoiceChip(
                        label: const Text('แบ่งเป็นส่วน'),
                        selected: isPortion,
                        onSelected: (_) =>
                            setDialogState(() => isPortion = true), // เลือก "แบ่งเป็นส่วน"
                      ),
                    ],
                  ),
                  // อธิบายว่าแต่ละแบบหักวัตถุดิบตอนทำอาหารยังไง
                  Padding(
                    padding: const EdgeInsets.only(top: 6), // [UI] ระยะบน
                    child: Text(
                      isPortion
                          ? '1 ส่วน = ใช้ทำอาหารได้ 1 ครั้ง ทำอาหาร 1 ครั้งหัก 1 ส่วน'
                          : 'ทำอาหาร 1 ครั้ง หักตาม "ใช้ครั้งละ"',
                      style: const TextStyle(
                        fontSize: 12, // [UI] ขนาด 12
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  if (!isPortion) ...[ // นับเป็นชิ้นถึงเลือกหน่วยได้
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: pieceUnit, // หน่วยที่เลือกอยู่
                      decoration: deco('หน่วย', ''),
                      items: units
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => pieceUnit = v); // เลือกหน่วยใหม่
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: remainController,
                    keyboardType: const TextInputType.numberWithOptions( // [UI] แป้นตัวเลขมีจุดทศนิยม
                      decimal: true,
                    ),
                    decoration: deco('เหลืออยู่', unit),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: totalController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: deco('ทั้งหมด (ตอนเก็บเข้าตู้เย็น)', unit),
                  ),
                  if (!isPortion) ...[ // นับเป็นชิ้นถึงมีช่อง "ใช้ครั้งละ"
                    const SizedBox(height: 12),
                    TextField(
                      controller: perCookController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: deco('ใช้ครั้งละ (ทำอาหาร 1 ครั้ง)', unit),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(color: Colors.grey), // [UI] ปุ่มยกเลิกสีเทา
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, // [UI] ปุ่มบันทึกสีส้ม
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
                  ),
                ),
                onPressed: () {
                  final remain = num.tryParse(remainController.text.trim()); // จำนวนที่เหลือ
                  num? total = num.tryParse(totalController.text.trim()); // จำนวนทั้งหมด
                  if (remain == null || remain < 0) return; // ค่าผิด ไม่บันทึก
                  // เหลืออยู่จะมากกว่าทั้งหมดไม่ได้ ถ้ากรอกเกินก็ขยายทั้งหมดตาม
                  if (total == null || total < remain) total = remain; // ทั้งหมดต้องไม่น้อยกว่าที่เหลือ
                  final perCook = num.tryParse(perCookController.text.trim()); // ใช้ครั้งละ
                  Navigator.pop(context);
                  _updateFields({ // บันทึกทุกช่อง
                    'quantity': remain,
                    'max_quantity': total,
                    'unit': unit,
                    // แบ่งเป็นส่วนไม่ใช้ช่องนี้ (1 ครั้ง = 1 ส่วนอยู่แล้ว)
                    'use_per_cook': isPortion || perCook == null || perCook <= 0
                        ? null
                        : perCook,
                  });
                },
                child: const Text(
                  'บันทึก',
                  style: TextStyle(color: Colors.white), // [UI] ตัวอักษรขาว
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- 🚀 Popup สำหรับเลือกหมวดหมู่ — เลือกได้จากรายการที่กำหนดไว้เท่านั้น
  // (fixedCategories) ไม่ให้พิมพ์ข้อความอิสระ เพื่อไม่ให้เกิดหมวดหมู่แปลกๆ
  // ซ้ำซ้อนในหน้าคลังเหมือนที่เคยเป็นปัญหาก่อนแก้ไขนี้
  Future<void> _showCategoryPickerDialog(String currentValue) async {
    final normalized = normalizeCategory(currentValue); // ทำหมวดเดิมให้อยู่ในชุดที่กำหนด
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'แก้ไขหมวดหมู่',
          style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
        ),
        content: SizedBox(
          width: double.maxFinite, // [UI] กว้างเต็มป๊อปอัป
          child: RadioGroup<String>( // กลุ่มปุ่มกลม: เก็บค่าที่เลือกอยู่ + ทำงานเมื่อเลือกใหม่
            groupValue: normalized, // ค่าที่เลือกอยู่
            onChanged: (val) { // เลือกแล้ว
              Navigator.pop(context);
              if (val != null && val != normalized) { // เปลี่ยนจริงถึงบันทึก
                _updateField('category', val);
              }
            },
            child: Column( // เรียงของข้างในจากบนลงล่าง
              mainAxisSize: MainAxisSize.min, // [UI] ขนาดเท่าเนื้อหา ไม่ยืดเต็ม
              children: fixedCategories.map((cat) { // สร้างตัวเลือกจากหมวดที่กำหนดไว้
                return RadioListTile<String>( // ปุ่มกลมเลือกได้ทีละอัน
                  value: cat, // ค่าของตัวเลือกนี้
                  activeColor: Colors.orange, // [UI] สีปุ่มกลมตอนเลือก (ส้ม)
                  title: Text(cat), // หัวข้อ
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // --- 🚀 Popup สำหรับเลือกปฏิทินวันหมดอายุ (ระบบคำนวณให้อัตโนมัติจากตาราง
  // อายุการเก็บรักษา แต่ผู้ใช้ปรับแก้ให้ตรงกับความเป็นจริงได้) ---
  Future<void> _selectExpiryDate() async {
    DateTime initialDate = expiryDayOf(_item!) ?? DateTime.now(); // วันเริ่มต้นในปฏิทิน = วันหมดอายุปัจจุบัน
    // หมดอายุก่อนวันที่เข้าตู้เย็นไม่ได้
    final added = parseCreatedAt(storageStartOf(_item!)); // วันที่เริ่มเก็บในช่องนี้
    final firstDate = added != null // เลือกย้อนหลังได้ถึงวันที่เข้าตู้ (ไม่รู้ = 1 ปี)
        ? DateTime(added.year, added.month, added.day)
        : DateTime.now().subtract(const Duration(days: 365));
    if (initialDate.isBefore(firstDate)) initialDate = firstDate; // วันเริ่มต้นต้องไม่ก่อนวันแรกที่เลือกได้

    final DateTime? picked = await showDatePicker( // เปิดปฏิทินเลือกวัน
      context: context,
      initialDate: initialDate,
      firstDate: firstDate, // ย้อนหลังได้ 1 ปี
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ), // ไปข้างหน้าได้ 10 ปี
      builder: (context, child) { // ปรับสีปฏิทิน
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange, // [UI] สีหลักของปฏิทิน (ส้ม)
              onPrimary: Colors.white, // [UI] สีตัวอักษรบนสีหลัก
              onSurface: Colors.black, // [UI] สีตัวอักษรทั่วไป
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) { // เลือกวันแล้ว
      final fields = <String, dynamic>{
        // expiry_date เป็น timestamptz ต้องส่งเป็นเวลา UTC (มี Z ต่อท้าย)
        'expiry_date': picked.toUtc().toIso8601String(),
      };
      // "เก็บได้อีก X วัน" ทุกหน้าคิดจาก วันที่เข้าตู้เย็น + ระยะที่เก็บได้ จึงต้อง
      // อัปเดตระยะที่เก็บได้ของช่องที่เก็บอยู่ให้ตรงกับวันหมดอายุที่เลือกด้วย
      // (บันทึกที่มาเป็น "คุณกำหนดเอง" โดยจำค่าเดิมไว้ เลือกกลับเป็นวันเดิมได้)
      if (added != null) {
        final days = DateTime( // จำนวนวันจากวันเข้าตู้ถึงวันที่เลือก
          picked.year,
          picked.month,
          picked.day,
        ).difference(DateTime(added.year, added.month, added.day)).inDays;
        final current = shelfDaysOf(_item!); // ระยะเก็บเดิม
        final original = originalShelfSource(
          _item!['shelf_type']?.toString(),
          current,
        );
        fields[_item!['storage'] == storageFreezer // บันทึกลงช่องที่เก็บอยู่
                ? 'freezer_days'
                : 'fridge_days'] =
            days;
        fields['shelf_type'] = (original.days != null && days == original.days) // เท่าค่าแนะนำ = ที่มาเดิม, ไม่งั้น = กำหนดเอง
            ? original.key
            : customShelfType(original.key, original.days);
        // ผู้ใช้เลือกวันเอง ค่านี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
        fields['days_left_at_freeze'] = null;
      }
      _updateFields(fields); // บันทึก
    }
  }

  // --- 🚀 Popup สำหรับย้ายช่องที่เก็บ (ช่องปกติ/ช่องแช่แข็ง) — นับวันที่เก็บได้
  // ของช่องใหม่ตั้งแต่วันที่ย้าย (ดู storageMoveFields) ---
  Future<void> _showStoragePickerDialog() async {
    final current = _item!['storage']?.toString() ?? storageFridge; // ช่องปัจจุบัน
    final fridgeDays = _item!['fridge_days'];
    final hasShelfData = fridgeDays != null; // มีข้อมูลระยะเก็บไหม
    final warnFreeze = freezerNotRecommended(_item!); // ไม่ควรแช่แข็งไหม (ไข่)

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'เก็บไว้ช่องไหน',
          style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
        ),
        content: SizedBox(
          width: double.maxFinite, // [UI] กว้างเต็มป๊อปอัป
          child: RadioGroup<String>( // กลุ่มปุ่มกลม: เก็บค่าที่เลือกอยู่ + ทำงานเมื่อเลือกใหม่
            groupValue: current, // ช่องที่เก็บอยู่ตอนนี้
            onChanged: (val) { // เลือกช่องใหม่แล้ว
              Navigator.pop(context); // เลือกแล้ว
              if (val != null && val != current) { // ถ้า val มีค่า และ val ไม่เท่ากับ current
                _changeStorage(val); // ย้ายช่อง
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // เลือกช่องแช่แข็งได้เสมอ ของที่ไม่มีข้อมูลช่องแช่แข็ง นับวันที่เหลือ
                // เท่าเดิม (ดู storageMoveFields) — เตือนเฉพาะของที่ไม่ควรแช่แข็ง (ไข่)
                for (final st in [storageFridge, storageFreezer]) // ตัวเลือก 2 ช่อง: ช่องปกติ / ช่องแช่แข็ง
                  RadioListTile<String>(
                    value: st,
                    activeColor: Colors.orange, // [UI] สีปุ่มกลม (ส้ม)
                    title: Text("${storageEmoji(st)} ${storageLabel(st)}"),
                    subtitle: !hasShelfData // บอกว่าย้ายแล้วจะเก็บได้อีกกี่วัน
                        ? null
                        : Text(
                            [
                              daysLeftText(
                                (st == current
                                        ? daysLeft(_item!)
                                        : daysLeftAfterMove(_item!, st)) ??
                                    0,
                              ),
                              if (st == storageFreezer && warnFreeze)
                                freezerNotRecommendedText,
                            ].join(' · '),
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // ย้ายช่องที่เก็บ (ถามยืนยันก่อนตามกรณี)
  Future<void> _changeStorage(String storage) async {
    final allowed = storage == storageFreezer
        ? await _confirmFreeze() // ไปช่องแช่แข็ง -> เช็คกรณีพิเศษ
        : await _confirmThaw(); // ไปช่องปกติ -> เตือนวิธีละลาย
    if (allowed && mounted) {
      _updateFields(storageMoveFields(_item!, storage)); // บันทึกค่าที่ต้องเปลี่ยนเมื่อย้ายช่อง
    }
  }

  // แช่แข็งไม่ทำให้ของที่เกินกำหนดกลับมาปลอดภัย และของที่เคยละลายแล้วแช่ซ้ำได้
  // เฉพาะที่ละลายในช่องปกติมาตลอด
  Future<bool> _confirmFreeze() async {
    final overdue = isOverdue(_item!); // เกินกำหนดแล้วไหม
    final thawed = _item!['thawed_at'] != null; // เคยละลายแล้วไหม
    if (!overdue && !thawed) return true; // ปกติ -> ย้ายได้เลย

    final thawedInFridge = !thawed || await _askThawedInFridge(); // เคยละลาย -> ถามว่าละลายในช่องปกติไหม
    if (!thawedInFridge) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ควรทำให้สุกก่อนแช่แข็งซ้ำ")),
        );
      }
      return false;
    }
    if (!overdue || !mounted) return mounted;

    return _confirmMove(
      title: "เกินกำหนดแล้ว",
      message:
          "การแช่แข็งไม่ทำให้ของที่เกินกำหนดกลับมาปลอดภัย "
          "รายการนี้จะยังแสดงว่าเกินกำหนดอยู่ ต้องการย้ายใช่ไหม?",
    );
  }

  // ถาม "ละลายในช่องปกติมาตลอดใช่ไหม"
  Future<bool> _askThawedInFridge() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("เคยละลายแล้ว"),
        content: const Text("รายการนี้ละลายในช่องปกติมาตลอดใช่ไหม?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("ไม่ใช่"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("ใช่"),
          ),
        ],
      ),
    );
    return answer == true;
  }

  // ยืนยันย้ายไปช่องปกติ (บอกวันที่เหลือหลังย้าย)
  Future<bool> _confirmThaw() {
    final left = daysLeftAfterMove(_item!, storageFridge);
    return _confirmMove(
      title: "ย้ายไปช่องปกติ",
      message:
          "ควรละลายในช่องปกติ ไม่วางไว้นอกตู้"
          "${left == null ? '' : '\nหลังย้าย: ${daysLeftText(left)}'}",
    );
  }

  // ป๊อปอัปยืนยันการย้ายทั่วไป (คืน true = ยืนยัน)
  Future<bool> _confirmMove({
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("ย้าย"),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  // --- 🚀 Popup สำหรับเลือกวันที่เอาเข้าตู้เย็น (ใช้แก้กรณีเพิ่มเข้าแอปช้ากว่า
  // วันที่เอาของเข้าตู้เย็นจริง) ---
  Future<void> _selectAddedDate() async {
    final now = DateTime.now();
    DateTime initialDate = now;
    if (_item!['created_at'] != null) { // มีวันเดิม -> ใช้เป็นค่าเริ่มต้น
      initialDate = parseCreatedAt(_item!['created_at']) ?? now;
    }
    final firstDate = now.subtract(
      const Duration(days: 365),
    ); // ย้อนหลังได้ 1 ปี
    if (initialDate.isBefore(firstDate)) initialDate = firstDate; // ไม่ให้ก่อนวันแรก
    if (initialDate.isAfter(now)) initialDate = now; // ไม่ให้เกินวันนี้

    final DateTime? picked = await showDatePicker( // เปิดปฏิทิน
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now, // วันที่เข้าตู้เย็นเป็นวันในอนาคตไม่ได้
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange, // [UI] สีหลักปฏิทิน (ส้ม)
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // เปลี่ยนแค่วันที่ เก็บเวลาที่ใส่ตู้เย็นจริงไว้เหมือนเดิม (เดิมบันทึกเป็น
      // 12:00 เสมอ ทำให้จำนวนชั่วโมงที่อยู่ในตู้เย็นเพี้ยน) — เลือกวันเดิมก็ไม่
      // ต้องบันทึกอะไร และเวลาที่ได้ต้องไม่เลยเวลาปัจจุบัน
      final original = parseCreatedAt(_item!['created_at']) ?? now;
      if (picked.year == original.year && // เลือกวันเดิม -> ไม่ต้องทำอะไร
          picked.month == original.month &&
          picked.day == original.day) {
        return;
      }
      var addedAt = DateTime( // วันใหม่ + เวลาเดิม
        picked.year,
        picked.month,
        picked.day,
        original.hour,
        original.minute,
        original.second,
      );
      if (addedAt.isAfter(DateTime.now())) addedAt = DateTime.now(); // ไม่ให้เกินเวลาปัจจุบัน

      // เลื่อนวันหมดอายุตามไปเท่ากัน (ระยะที่เก็บได้เท่าเดิม) ไม่งั้น "เก็บได้อีก
      // X วัน" และหลอดนับจะไม่เปลี่ยนตามวันที่เข้าตู้เย็นที่แก้
      final fields = <String, dynamic>{
        'created_at': addedAt.toUtc().toIso8601String(),
      };
      // ของที่เคยย้ายช่องนับวันจากวันที่ย้าย วันหมดอายุจึงไม่เกี่ยวกับวันเข้าตู้เย็น
      final expiryRaw = _item!['storage_changed_at'] == null
          ? _item!['expiry_date']
          : null;
      if (expiryRaw != null) { // มีวันหมดอายุ -> เลื่อนตามเท่ากัน
        final expiry = DateTime.parse(expiryRaw.toString()).toLocal();
        fields['expiry_date'] = expiry
            .add(addedAt.difference(original))
            .toUtc()
            .toIso8601String();
      }
      _updateFields(fields); // บันทึก
    }
  }

  // ฟังก์ชันแปลงวันที่
  // แปลงวันที่เป็นภาษาไทย เช่น "5 มกราคม 2569"
  String _formatThaiDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'ไม่ระบุ';
    try {
      DateTime dt = DateTime.parse(isoString).toLocal(); // แปลงเป็นเวลาไทย
      List<String> fullMonths = [ // ชื่อเดือนภาษาไทย
        'มกราคม',
        'กุมภาพันธ์',
        'มีนาคม',
        'เมษายน',
        'พฤษภาคม',
        'มิถุนายน',
        'กรกฎาคม',
        'สิงหาคม',
        'กันยายน',
        'ตุลาคม',
        'พฤศจิกายน',
        'ธันวาคม',
      ];
      return '${dt.day} ${fullMonths[dt.month - 1]} ${dt.year + 543}'; // +543 = ปี พ.ศ.
    } catch (e) {
      return isoString; // แปลงไม่ได้ คืนข้อความเดิม
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) { // กำลังโหลด -> วงหมุน
      return const Scaffold(
        backgroundColor: Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_item == null) { // ไม่เจอข้อมูล
      return const Scaffold(
        backgroundColor: Color(0xFFD8EEFF),
        body: Center(
          child: Text(
            "ไม่พบข้อมูลสินค้า",
            style: TextStyle(fontSize: 18, color: Colors.black), // [UI] ขนาด 18
          ),
        ),
      );
    }

    final item = _item!;

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
      bottomNavigationBar: const AppBottomNav(current: AppTab.inventory), // แถบเมนูล่าง ไฮไลต์ "คลัง"
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20), // [UI] ระยะจากขอบบน

            // --- Header ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0), // [UI] ระยะซ้ายขวา 25
              child: Row(
                children: [
                  Container(
                    width: 55, // [UI] ความกว้างปุ่มย้อนกลับ
                    height: 45, // [UI] ความสูงปุ่ม
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7D0), // [UI] สีครีม
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const BackIcon(size: 24), // [UI] ไอคอนย้อนกลับ
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 15), // [UI] ระยะปุ่มกับแถบชื่อ
                  Expanded(
                    child: Container(
                      height: 45, // [UI] ความสูงแถบชื่อ
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0), // [UI] สีครีม
                        borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "รายละเอียด",
                        style: TextStyle(
                          fontSize: 16, // [UI] ขนาดชื่อหน้า
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40), // [UI] ระยะหัวกับเนื้อหา

            // --- เนื้อหา ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 35.0), // [UI] ระยะซ้ายขวาของเนื้อหา 35
                child: Column(
                  children: [
                    // รูปที่ใช้สแกนวัตถุดิบนี้ — ให้จำได้ว่ามาจากรูปไหน แตะเพื่อดูเต็มจอ
                    PrivateScanImage( // รูปที่ใช้สแกน (ไม่มีรูปจะไม่แสดง)
                      bucket: fridgeImageBucket,
                      path: item['image_path']?.toString(),
                    ),
                    // 🚀 เชื่อมปุ่มแก้ไขชื่อ
                    _buildDetailRow( // แถวชื่อ (ตัวใหญ่)
                      icon: Icons.restaurant,
                      text: item['name'] ?? 'ไม่ระบุชื่อ',
                      isTitle: true,
                      hasEdit: true, // เปิดให้แก้ไขชื่อได้ด้วย
                      onEdit: () => _showEditDialog(
                        'ชื่อวัตถุดิบ',
                        'name',
                        item['name'] ?? '',
                      ),
                    ),
                    const SizedBox(height: 10), // [UI] ระยะห่างระหว่างแถว

                    // 🚀 เชื่อมปุ่มปฏิทินวันหมดอายุ
                    _buildDetailRow( // แถววันหมดอายุ (แตะเปิดปฏิทิน)
                      icon: Icons.event_busy,
                      // วันที่และข้อความคิดจาก daysLeft ตัวเดียวกับทุกหน้า
                      text: daysLeft(item) == null
                          ? "เก็บได้ถึง ไม่ระบุ"
                          : "เก็บได้ถึง ${_formatThaiDate(expiryDayOf(item)!.toIso8601String())} "
                                "(${expiryText(daysLeft(item)!)})",
                      onEdit: _selectExpiryDate,
                    ),
                    const SizedBox(height: 10),

                    // 🚀 ช่องที่เก็บ
                    _buildDetailRow( // แถวช่องที่เก็บ (แตะเลือกช่อง)
                      icon: Icons.kitchen,
                      text:
                          "เก็บใน ${storageEmoji(item['storage']?.toString())} ${storageLabel(item['storage']?.toString())}"
                          "${(item['food_state']?.toString() ?? '').isEmpty ? '' : ' · ${item['food_state']}'}"
                          "${item['thawed_at'] == null ? '' : ' · เคยละลายแล้ว'}",
                      onEdit: _showStoragePickerDialog,
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มปฏิทิน (แก้วันที่เข้าตู้เย็น)
                    _buildDetailRow( // แถววันที่เข้าตู้ (แตะเปิดปฏิทิน)
                      icon: Icons.calendar_month,
                      text: fridgeAgeText(item['created_at']),
                      onEdit: _selectAddedDate,
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มแก้ไขหมวดหมู่
                    _buildDetailRow( // แถวหมวดหมู่
                      icon: Icons.format_list_bulleted,
                      text: "หมวดหมู่ : ${item['category'] ?? 'ไม่ระบุ'}",
                      onEdit: () =>
                          _showCategoryPickerDialog(item['category'] ?? ''),
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มแก้ไขจำนวน (เหลืออยู่ / ทั้งหมด)
                    _buildDetailRow( // แถวจำนวน
                      icon: Icons.add_circle,
                      text:
                          "จำนวน : เหลือ ${_fmtQty(item['quantity'])} จาก ${_fmtQty(item['max_quantity'] ?? item['quantity'])} ${item['unit'] ?? ''}"
                          "${item['unit'] == portionUnit ? '' : ' · ใช้ครั้งละ ${_fmtQty(item['use_per_cook'] ?? 1)} ${item['unit'] ?? ''}'}",
                      onEdit: _showQuantityDialog,
                    ),
                    const SizedBox(height: 30), // [UI] ระยะก่อนข้อมูลเพิ่มเติม

                    if (item['detected_unit'] != null && // แบ่งเป็นส่วน -> บอกปริมาณที่ตรวจพบจากรูป
                        item['detected_unit'] != item['unit'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้
                        child: Text(
                          "ปริมาณที่ตรวจพบจากภาพ: ${item['detected_quantity'] ?? '-'} ${item['detected_unit']} "
                          "(แบ่งเป็น ${item['max_quantity'] ?? '-'} ${item['unit'] ?? ''})",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15, // [UI] ขนาด 15
                            color: Colors.black54, // [UI] สีเทา
                          ),
                        ),
                      ),
                    if (item['created_at'] != null)
                      Text(
                        "เข้าตู้เย็นเมื่อ ${_formatThaiDate(parseCreatedAt(item['created_at'])?.toIso8601String())} "
                        "เวลา ${addedTimeText(item['created_at'])}",
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
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

  // ตามดีไซน์ใน Figma แต่ละแถวไม่มีไอคอนดินสอ/เส้นคั่นให้เห็น แต่ยังแตะทั้งแถว
  // เพื่อแก้ไขได้เหมือนเดิม (ไม่ตัดฟีเจอร์แก้ไขออก แค่ซ่อนไอคอนให้ตรงดีไซน์)
  // แถวข้อมูล 1 แถว (ไอคอน + ข้อความ) แตะทั้งแถวเพื่อแก้
  Widget _buildDetailRow({
    required IconData icon,
    required String text,
    bool isTitle = false, // true = แถวชื่อ (ตัวใหญ่)
    bool hasEdit = true, // แก้ไขได้ไหม
    VoidCallback? onEdit, // แตะแล้วทำอะไร
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0), // [UI] ระยะใต้แต่ละแถว
      child: GestureDetector(
        onTap: hasEdit ? onEdit : null,
        behavior: HitTestBehavior.opaque, // แตะตรงไหนของแถวก็ได้
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0), // [UI] เลื่อนไอคอนลง 2
              child: Icon(icon, size: isTitle ? 32 : 28, color: Colors.black), // [UI] แถวชื่อ = ไอคอน 32, แถวอื่น = 28
            ),
            const SizedBox(width: 15), // [UI] ระยะไอคอนกับข้อความ
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: isTitle ? 28 : 16, // [UI] แถวชื่อ = ตัวอักษร 28, แถวอื่น = 16
                  fontWeight: isTitle ? FontWeight.w900 : FontWeight.normal, // [UI] แถวชื่อ = หนามาก
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
