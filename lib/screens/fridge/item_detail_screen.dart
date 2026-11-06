import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/services/fridge_images.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';

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
  Map<String, dynamic>? _item;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchItemDetails();
  }

  // --- ดึงข้อมูลจาก Supabase ---
  Future<void> _fetchItemDetails() async {
    try {
      final response = await Supabase.instance.client
          .from('fridge_items')
          .select()
          .eq('item_id', widget.itemId)
          .single();

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
            content: Text("ดึงข้อมูลไม่สำเร็จ: $e"),
            backgroundColor: Colors.red,
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
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await Supabase.instance.client
          .from('fridge_items')
          .update(fields)
          .eq('item_id', widget.itemId);

      if (mounted) Navigator.pop(context); // ปิด Loading
      _fetchItemDetails(); // โหลดข้อมูลใหม่มาโชว์

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตข้อมูลสำเร็จ!'),
            backgroundColor: Colors.green,
          ),
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

  // --- 🚀 Popup สำหรับพิมพ์แก้ไขข้อความหรือตัวเลข ---
  Future<void> _showEditDialog(
    String title,
    String field,
    String currentValue, {
    bool isNumber = false,
  }) async {
    TextEditingController controller = TextEditingController(
      text: currentValue,
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'แก้ไข$title',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: 'กรอก$titleใหม่',
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              dynamic newValue = isNumber
                  ? int.tryParse(controller.text)
                  : controller.text;
              if (newValue != null && newValue.toString().isNotEmpty) {
                _updateField(field, newValue);
              }
            },
            child: const Text('บันทึก', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _fmtQty(dynamic v) {
    final n = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }

  // --- 🚀 Popup แก้จำนวน: แก้ได้ทั้ง "เหลืออยู่" และ "ทั้งหมด" (ปริมาณตอนเก็บ
  // เข้าตู้เย็น) — ใช้แก้ตอนใส่จำนวนตั้งต้นผิด หรือกดปุ่มในหน้าคลังผิด ---
  Future<void> _showQuantityDialog() async {
    final currentUnit = _item!['unit']?.toString() ?? 'ชิ้น';
    // วิธีนับ: "แบ่งเป็นส่วน" (หน่วย ส่วน) หรือ "นับเป็นชิ้น" (ฟอง/ผล/หัว ฯลฯ)
    // เปลี่ยนไปมาได้ จำหน่วยนับชิ้นล่าสุดไว้ สลับกลับมาจะได้หน่วยเดิม
    bool isPortion = currentUnit == portionUnit;
    String pieceUnit = isPortion ? 'ชิ้น' : currentUnit;
    // หน่วยเก่าที่ไม่อยู่ในรายการ (เช่น กรัม จากข้อมูลก่อนหน้า) ให้ยังเลือกได้
    final units = pieceUnits.contains(pieceUnit)
        ? pieceUnits
        : [pieceUnit, ...pieceUnits];

    final remainController = TextEditingController(
      text: _fmtQty(_item!['quantity']),
    );
    final totalController = TextEditingController(
      text: _fmtQty(_item!['max_quantity'] ?? _item!['quantity']),
    );
    // นับเป็นชิ้น: ทำอาหาร 1 ครั้งใช้กี่ชิ้น
    final perCookController = TextEditingController(
      text: _fmtQty(_item!['use_per_cook'] ?? 1),
    );

    InputDecoration deco(String label, String unit) => InputDecoration(
      labelText: label,
      suffixText: unit,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final unit = isPortion ? portionUnit : pieceUnit;
          return AlertDialog(
            title: const Text(
              'แก้ไขจำนวน',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('นับเป็นชิ้น'),
                        selected: !isPortion,
                        onSelected: (_) =>
                            setDialogState(() => isPortion = false),
                      ),
                      ChoiceChip(
                        label: const Text('แบ่งเป็นส่วน'),
                        selected: isPortion,
                        onSelected: (_) =>
                            setDialogState(() => isPortion = true),
                      ),
                    ],
                  ),
                  // อธิบายว่าแต่ละแบบหักวัตถุดิบตอนทำอาหารยังไง
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      isPortion
                          ? '1 ส่วน = ใช้ทำอาหารได้ 1 ครั้ง ทำอาหาร 1 ครั้งหัก 1 ส่วน'
                          : 'ทำอาหาร 1 ครั้ง ระบบจะเสนอให้หักตาม "ใช้ครั้งละ" '
                                '(ถ้าสูตรบอกจำนวน$pieceUnitไว้ จะใช้ตามสูตร)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  if (!isPortion) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: pieceUnit,
                      decoration: deco('หน่วย', ''),
                      items: units
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => pieceUnit = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: remainController,
                    keyboardType: const TextInputType.numberWithOptions(
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
                  if (!isPortion) ...[
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
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  final remain = num.tryParse(remainController.text.trim());
                  num? total = num.tryParse(totalController.text.trim());
                  if (remain == null || remain < 0) return;
                  // เหลืออยู่จะมากกว่าทั้งหมดไม่ได้ ถ้ากรอกเกินก็ขยายทั้งหมดตาม
                  if (total == null || total < remain) total = remain;
                  final perCook = num.tryParse(perCookController.text.trim());
                  Navigator.pop(context);
                  _updateFields({
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
                  style: TextStyle(color: Colors.white),
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
    final normalized = normalizeCategory(currentValue);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'แก้ไขหมวดหมู่',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: fixedCategories.map((cat) {
              return RadioListTile<String>(
                value: cat,
                groupValue: normalized,
                activeColor: Colors.orange,
                title: Text(cat),
                onChanged: (val) {
                  Navigator.pop(context);
                  if (val != null && val != normalized) {
                    _updateField('category', val);
                  }
                },
              );
            }).toList(),
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
    DateTime initialDate = expiryDayOf(_item!) ?? DateTime.now();
    // หมดอายุก่อนวันที่เข้าตู้เย็นไม่ได้
    final added = parseCreatedAt(storageStartOf(_item!));
    final firstDate = added != null
        ? DateTime(added.year, added.month, added.day)
        : DateTime.now().subtract(const Duration(days: 365));
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate, // ย้อนหลังได้ 1 ปี
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ), // ไปข้างหน้าได้ 10 ปี
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final fields = <String, dynamic>{
        // expiry_date เป็น timestamptz ต้องส่งเป็นเวลา UTC (มี Z ต่อท้าย)
        'expiry_date': picked.toUtc().toIso8601String(),
      };
      // "เก็บได้อีก X วัน" ทุกหน้าคิดจาก วันที่เข้าตู้เย็น + ระยะที่เก็บได้ จึงต้อง
      // อัปเดตระยะที่เก็บได้ของช่องที่เก็บอยู่ให้ตรงกับวันหมดอายุที่เลือกด้วย
      // (บันทึกที่มาเป็น "คุณกำหนดเอง" โดยจำค่าเดิมไว้ เลือกกลับเป็นวันเดิมได้)
      if (added != null) {
        final days = DateTime(
          picked.year,
          picked.month,
          picked.day,
        ).difference(DateTime(added.year, added.month, added.day)).inDays;
        final current = shelfDaysOf(_item!);
        final original = originalShelfSource(
          _item!['shelf_type']?.toString(),
          current,
        );
        fields[_item!['storage'] == storageFreezer
                ? 'freezer_days'
                : 'fridge_days'] =
            days;
        fields['shelf_type'] = (original.days != null && days == original.days)
            ? original.key
            : customShelfType(original.key, original.days);
        // ผู้ใช้เลือกวันเอง ค่านี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
        fields['days_left_at_freeze'] = null;
      }
      _updateFields(fields);
    }
  }

  // --- 🚀 Popup สำหรับย้ายช่องที่เก็บ (ช่องปกติ/ช่องแช่แข็ง) — นับวันที่เก็บได้
  // ของช่องใหม่ตั้งแต่วันที่ย้าย (ดู storageMoveFields) ---
  Future<void> _showStoragePickerDialog() async {
    final current = _item!['storage']?.toString() ?? storageFridge;
    final fridgeDays = _item!['fridge_days'];
    final freezerDays = _item!['freezer_days'];
    final hasShelfData = fridgeDays != null;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'เก็บไว้ช่องไหน',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final st in [
                storageFridge,
                // ไม่มีข้อมูลช่องแช่แข็ง (เช่น ผัก นม) ก็ไม่ต้องมีตัวเลือกนี้
                if (!hasShelfData || freezerDays != null) storageFreezer,
              ])
                RadioListTile<String>(
                  value: st,
                  groupValue: current,
                  activeColor: Colors.orange,
                  title: Text("${storageEmoji(st)} ${storageLabel(st)}"),
                  subtitle: !hasShelfData
                      ? null
                      : Text(
                          st == storageFreezer && freezerDays == null
                              ? "ไม่ควรเก็บในช่องแช่แข็ง"
                              : daysLeftText(
                                  (st == current
                                          ? daysLeft(_item!)
                                          : daysLeftAfterMove(_item!, st)) ??
                                      0,
                                ),
                        ),
                  onChanged:
                      (hasShelfData &&
                          st == storageFreezer &&
                          freezerDays == null)
                      ? null
                      : (val) {
                          Navigator.pop(context);
                          if (val != null && val != current) {
                            _changeStorage(val);
                          }
                        },
                ),
            ],
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

  Future<void> _changeStorage(String storage) async {
    final allowed = storage == storageFreezer
        ? await _confirmFreeze()
        : await _confirmThaw();
    if (allowed && mounted) {
      _updateFields(storageMoveFields(_item!, storage));
    }
  }

  // แช่แข็งไม่ทำให้ของที่เกินกำหนดกลับมาปลอดภัย และของที่เคยละลายแล้วแช่ซ้ำได้
  // เฉพาะที่ละลายในช่องปกติมาตลอด
  Future<bool> _confirmFreeze() async {
    final overdue = isOverdue(_item!);
    final thawed = _item!['thawed_at'] != null;
    if (!overdue && !thawed) return true;

    final thawedInFridge = !thawed || await _askThawedInFridge();
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

  Future<bool> _confirmThaw() {
    final left = daysLeftAfterMove(_item!, storageFridge);
    return _confirmMove(
      title: "ย้ายไปช่องปกติ",
      message:
          "ควรละลายในช่องปกติ ไม่วางไว้นอกตู้"
          "${left == null ? '' : '\nหลังย้าย: ${daysLeftText(left)}'}",
    );
  }

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
    if (_item!['created_at'] != null) {
      initialDate = parseCreatedAt(_item!['created_at']) ?? now;
    }
    final firstDate = now.subtract(
      const Duration(days: 365),
    ); // ย้อนหลังได้ 1 ปี
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(now)) initialDate = now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now, // วันที่เข้าตู้เย็นเป็นวันในอนาคตไม่ได้
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange,
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
      if (picked.year == original.year &&
          picked.month == original.month &&
          picked.day == original.day) {
        return;
      }
      var addedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        original.hour,
        original.minute,
        original.second,
      );
      if (addedAt.isAfter(DateTime.now())) addedAt = DateTime.now();

      // เลื่อนวันหมดอายุตามไปเท่ากัน (ระยะที่เก็บได้เท่าเดิม) ไม่งั้น "เก็บได้อีก
      // X วัน" และหลอดนับจะไม่เปลี่ยนตามวันที่เข้าตู้เย็นที่แก้
      final fields = <String, dynamic>{
        'created_at': addedAt.toUtc().toIso8601String(),
      };
      // ของที่เคยย้ายช่องนับวันจากวันที่ย้าย วันหมดอายุจึงไม่เกี่ยวกับวันเข้าตู้เย็น
      final expiryRaw = _item!['storage_changed_at'] == null
          ? _item!['expiry_date']
          : null;
      if (expiryRaw != null) {
        final expiry = DateTime.parse(expiryRaw.toString()).toLocal();
        fields['expiry_date'] = expiry
            .add(addedAt.difference(original))
            .toUtc()
            .toIso8601String();
      }
      _updateFields(fields);
    }
  }

  // ฟังก์ชันแปลงวันที่
  String _formatThaiDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'ไม่ระบุ';
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      List<String> fullMonths = [
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
      return '${dt.day} ${fullMonths[dt.month - 1]} ${dt.year + 543}';
    } catch (e) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFD8EEFF),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_item == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFD8EEFF),
        body: Center(
          child: Text(
            "ไม่พบข้อมูลสินค้า",
            style: TextStyle(fontSize: 18, color: Colors.black),
          ),
        ),
      );
    }

    final item = _item!;

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.inventory),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // --- Header ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Row(
                children: [
                  Container(
                    width: 55,
                    height: 45,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7D0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const BackIcon(size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "รายละเอียด",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- เนื้อหา ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 35.0),
                child: Column(
                  children: [
                    // รูปที่ใช้สแกนวัตถุดิบนี้ — ให้จำได้ว่ามาจากรูปไหน แตะเพื่อดูเต็มจอ
                    PrivateScanImage(
                      bucket: fridgeImageBucket,
                      path: item['image_path']?.toString(),
                    ),
                    // 🚀 เชื่อมปุ่มแก้ไขชื่อ
                    _buildDetailRow(
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
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มปฏิทินวันหมดอายุ
                    _buildDetailRow(
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
                    _buildDetailRow(
                      icon: Icons.kitchen,
                      text:
                          "เก็บใน ${storageEmoji(item['storage']?.toString())} ${storageLabel(item['storage']?.toString())}"
                          "${(item['food_state']?.toString() ?? '').isEmpty ? '' : ' · ${item['food_state']}'}"
                          "${item['thawed_at'] == null ? '' : ' · เคยละลายแล้ว'}",
                      onEdit: _showStoragePickerDialog,
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มปฏิทิน (แก้วันที่เข้าตู้เย็น)
                    _buildDetailRow(
                      icon: Icons.calendar_month,
                      text: fridgeAgeText(item['created_at']),
                      onEdit: _selectAddedDate,
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มแก้ไขหมวดหมู่
                    _buildDetailRow(
                      icon: Icons.format_list_bulleted,
                      text: "หมวดหมู่ : ${item['category'] ?? 'ไม่ระบุ'}",
                      onEdit: () =>
                          _showCategoryPickerDialog(item['category'] ?? ''),
                    ),
                    const SizedBox(height: 10),

                    // 🚀 เชื่อมปุ่มแก้ไขจำนวน (เหลืออยู่ / ทั้งหมด)
                    _buildDetailRow(
                      icon: Icons.add_circle,
                      text:
                          "จำนวน : เหลือ ${_fmtQty(item['quantity'])} จาก ${_fmtQty(item['max_quantity'] ?? item['quantity'])} ${item['unit'] ?? ''}"
                          "${item['unit'] == portionUnit ? '' : ' · ใช้ครั้งละ ${_fmtQty(item['use_per_cook'] ?? 1)} ${item['unit'] ?? ''}'}",
                      onEdit: _showQuantityDialog,
                    ),
                    const SizedBox(height: 30),

                    if (item['detected_unit'] != null &&
                        item['detected_unit'] != item['unit'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          "ปริมาณที่ตรวจพบจากภาพ: ${item['detected_quantity'] ?? '-'} ${item['detected_unit']} "
                          "(แบ่งเป็น ${item['max_quantity'] ?? '-'} ${item['unit'] ?? ''})",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
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
  Widget _buildDetailRow({
    required IconData icon,
    required String text,
    bool isTitle = false,
    bool hasEdit = true,
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: GestureDetector(
        onTap: hasEdit ? onEdit : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(icon, size: isTitle ? 32 : 28, color: Colors.black),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: isTitle ? 28 : 16,
                  fontWeight: isTitle ? FontWeight.w900 : FontWeight.normal,
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
