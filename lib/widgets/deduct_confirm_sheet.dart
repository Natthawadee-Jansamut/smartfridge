import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/services/fridge_stock.dart'; // หาของในตู้ / รวมจำนวนคงเหลือ
import 'package:test_app/utils/fridge_age.dart'; // นับวันที่เหลือ / เรียง FIFO

/// วัตถุดิบ 1 รายการที่สูตรบอกว่าต้องใช้ พร้อมปริมาณที่สูตรแนะนำ
class DeductRequest {
  final String name; // ชื่อวัตถุดิบ
  final num suggested; // จำนวนที่สูตรบอกให้ใช้

  /// หน่วยที่สูตรใช้ (เช่น "กรัม", "ฟอง") — ว่าง = ไม่รู้หน่วย ถือว่าตรงกับในตู้เย็น
  final String unit;

  /// ของพื้นฐาน/เครื่องปรุง (ข้าว น้ำปลา ซีอิ๊ว ซอสต่างๆ) — ถ้ามีในตู้เย็น
  /// ให้เริ่มที่ "ไม่ได้ใช้" เพราะสูตรใช้ทีละช้อน แต่ในตู้มักเก็บเป็นขวด/ถุง
  /// ไม่งั้นค่าเริ่มต้นจะหักทั้งขวดโดยไม่ตั้งใจ ผู้ใช้กดเพิ่มเองได้
  final bool isStaple;

  const DeductRequest({
    required this.name,
    required this.suggested,
    this.unit = '',
    this.isStaple = false,
  });
}

/// ผลที่ผู้ใช้ยืนยันแล้ว — amount = null แปลว่าไม่มีวัตถุดิบนี้ในตู้เย็น
class DeductChoice {
  final String name; // ชื่อวัตถุดิบ
  final num? amount; // จำนวนที่จะหัก (null = ไม่มีในตู้)

  const DeductChoice({required this.name, required this.amount});
}

num _toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0; // ตัวช่วยแปลงค่าเป็นตัวเลข

// แสดงตัวเลขไม่เกิน 2 ตำแหน่ง ตัด 0 ท้ายออก: 1 -> "1", 0.5 -> "0.5", 0.25 -> "0.25"
String _fmt(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString(); // เป็นจำนวนเต็ม -> ไม่แสดงทศนิยม
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// หน้ายืนยันก่อนหักวัตถุดิบตอนทำอาหาร — คนทำอาหารไม่ได้ชั่งตวงจริง จึงให้กด
/// เลือกแบบกะด้วยตา ("ไม่ได้ใช้" / "ครึ่งหนึ่ง" / "ใช้หมด" หรือ −/+ ทีละส่วน
/// ทีละชิ้น) ระบบเลือกค่าเริ่มต้นไว้ให้ตามสูตร ส่วนใหญ่แค่กดยืนยัน
///
/// คืน null ถ้าผู้ใช้กดยกเลิก
Future<List<DeductChoice>?> showDeductConfirmSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> inventory,
  required List<DeductRequest> requests,
}) {
  return showModalBottomSheet<List<DeductChoice>>( // เปิดแผ่นเลื่อนขึ้นจากด้านล่าง
    context: context,
    isScrollControlled: true, // [UI] ให้แผ่นสูงได้มากกว่าครึ่งจอ
    backgroundColor: Colors.white, // [UI] พื้นขาว
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // [UI] มุมบนโค้ง 24
    ),
    builder: (_) =>
        _DeductConfirmSheet(inventory: inventory, requests: requests),
  );
}

// ข้อมูลของแถววัตถุดิบ 1 แถวในแผ่น
class _Line {
  final String name; // ชื่อ
  final num available; // ในตู้มีทั้งหมดเท่าไหร่
  final String unit; // หน่วยของในตู้
  final String? note; // ข้อความบอกลอตที่จะหักก่อน

  /// คำเตือนเมื่อหน่วยในสูตรไม่ตรงกับในตู้เย็น (เช่น สูตรใช้ 200 กรัม แต่ในตู้นับเป็นส่วน)
  final String? warning;
  num amount; // จำนวนที่จะหัก (ผู้ใช้ปรับได้)

  /// ปรับได้ทีละเท่าไหร่ (ปุ่ม −/+): ครึ่งหนึ่ง หรือทีละ 1
  final num step;

  _Line({
    required this.name,
    required this.available,
    required this.unit,
    required this.note,
    required this.amount,
    required this.step,
    this.warning,
  });

  bool get found => available > 0; // มีของในตู้ไหม
}

class _DeductConfirmSheet extends StatefulWidget {
  final List<Map<String, dynamic>> inventory;
  final List<DeductRequest> requests;

  const _DeductConfirmSheet({required this.inventory, required this.requests});

  @override
  State<_DeductConfirmSheet> createState() => _DeductConfirmSheetState();
}

class _DeductConfirmSheetState extends State<_DeductConfirmSheet> {
  late final List<_Line> lines; // รายการแถวทั้งหมด

  @override
  void initState() { // ตอนเปิดแผ่น: เตรียมข้อมูลแต่ละแถว
    super.initState();
    lines = widget.requests.map((req) { // แปลงคำขอแต่ละรายการเป็นแถว
      final lots = // หาลอตในตู้ที่ชื่อตรงและยังเหลือ
          widget.inventory
              .where(
                (lot) =>
                    ingredientNameMatches(lot['name'], req.name) &&
                    _toNum(lot['quantity']) > 0,
              )
              .toList()
            ..sort(compareFifo); // เรียงให้ลอตที่ควรใช้ก่อนอยู่หน้า
      final available = availableQuantity(lots, req.name); // รวมจำนวนทุกลอต
      final unit = lots.isEmpty ? '' : (lots.first['unit']?.toString() ?? ''); // หน่วยของลอตแรก

      // บอกลอตที่จะถูกหักก่อน (ใกล้หมดอายุที่สุด) ให้ผู้ใช้เห็น
      String? note;
      if (lots.isNotEmpty) {
        final expiry = daysLeft(lots.first);
        note = expiry == null ? null : expiryText(expiry);
      }

      // ค่าเริ่มต้นตามสูตร ปัดให้เป็นหน่วยที่กดได้จริง (ครึ่งส่วน / ทีละชิ้น)
      // และไม่เกินที่มีอยู่
      // ความละเอียดของปุ่ม −/+ : ของที่นับเป็น "ส่วน" เริ่มที่ทีละครึ่งส่วน
      // ของที่นับเป็นชิ้นเริ่มที่ทีละ 1 แต่ถ้าสูตรใช้ หรือในตู้เหลือ เป็นเศษ
      // (เช่น 1/2 ชิ้น, 0.25 ส่วน) ให้ละเอียดลงตามนั้น (ครึ่ง / หนึ่งในสี่)
      // ไม่งั้นค่าเริ่มต้นจะถูกปัดจนไม่ตรงกับวัตถุดิบที่ต้องใช้
      num stepFor(num v) {
        if (v <= 0 || v == v.roundToDouble()) return 1; // เป็นจำนวนเต็ม -> ปรับทีละ 1
        if ((v * 2) == (v * 2).roundToDouble()) return 0.5; // เป็นครึ่ง -> ทีละ 0.5
        return 0.25; // ละเอียดกว่านั้น -> ทีละ 0.25
      }

      final num step = [ // เลือกความละเอียดที่ละเอียดที่สุดจาก 3 อย่าง
        unit == 'ส่วน' ? 0.5 : 1,
        stepFor(req.suggested),
        stepFor(available),
      ].reduce((a, b) => a < b ? a : b);
      final recipeUnit = req.unit.trim(); // หน่วยที่สูตรใช้
      // หน่วยไม่ตรงกัน (เช่น สูตร 200 กรัม / ในตู้ 3 ส่วน) เอาเลขมาเทียบตรงๆ ไม่ได้
      // ถ้าใช้เลขของสูตร ค่าเริ่มต้นจะกลายเป็น "ใช้หมด" -> เริ่มที่ 1 ชิ้น/1 ส่วน แทน
      final unitMismatch =
          lots.isNotEmpty &&
          req.suggested > 0 &&
          recipeUnit.isNotEmpty &&
          recipeUnit != unit.trim();
      // ค่าเริ่มต้นที่ผู้ใช้ตั้งไว้เองว่าทำอาหาร 1 ครั้งใช้เท่าไหร่
      // นับเป็นชิ้น = "ใช้ครั้งละ" (use_per_cook), แบ่งเป็นส่วน = 1 ส่วน
      final perCookRaw = lots.isEmpty ? null : lots.first['use_per_cook'];
      final perCook = unit == 'ส่วน' // แบ่งเป็นส่วน -> ครั้งละ 1 ส่วน
          ? 1
          : (perCookRaw == null ? 0 : _toNum(perCookRaw));
      final perCookText = perCook > 0
          ? "ใช้ตามที่ตั้งไว้ ครั้งละ ${_fmt(perCook)} $unit"
          : null;
      num amount;
      String? warning;
      if (req.isStaple && lots.isNotEmpty) { // ของพื้นฐาน -> เริ่มที่ 0 (ไม่หัก)
        amount = 0;
        warning =
            "ของพื้นฐาน ไม่หักให้อัตโนมัติ"
            "${recipeUnit.isNotEmpty && req.suggested > 0 ? ' (สูตรใช้ ${_fmt(req.suggested)} $recipeUnit)' : ''}"
            " — ถ้าใช้หมดกดเพิ่มได้";
      } else if (unitMismatch) { // หน่วยไม่ตรง -> ใช้ "ใช้ครั้งละ" หรือ 1
        amount = perCook > 0 ? perCook : 1;
        warning =
            "สูตรใช้ ${_fmt(req.suggested)} $recipeUnit — "
            "${perCookText ?? 'ปรับให้ตรงกับที่ใช้จริง'}";
      } else if (lots.isNotEmpty && req.suggested <= 0) {
        // สูตรไม่ได้บอกปริมาณ -> ใช้ค่าที่ผู้ใช้ตั้งไว้ (ไม่งั้นเป็น "ไม่ใช้" แล้วลืมหัก)
        amount = perCook > 0 ? perCook : 1;
        warning =
            "สูตรไม่ได้ระบุปริมาณ — "
            "${perCookText ?? 'ปรับให้ตรงกับที่ใช้จริง'}";
      } else { // ปกติ -> ใช้ตามสูตร ปัดให้ลงตัวกับ step
        amount = (req.suggested / step).round() * step;
        if (req.suggested > 0 && amount == 0) amount = step; // ปัดแล้วเป็น 0 แต่สูตรใช้ -> ให้อย่างน้อย 1 step
      }
      if (amount > available) amount = available; // ห้ามเกินที่มีในตู้

      return _Line(
        name: req.name,
        available: available,
        unit: unit,
        note: note,
        amount: amount,
        step: step,
        warning: warning,
      );
    }).toList();
  }

  // ตั้งจำนวนใหม่ (บีบให้อยู่ระหว่าง 0 ถึงที่มี)
  void _set(_Line line, num value) {
    setState(() {
      line.amount = value.clamp(0, line.available);
    });
  }

  // ปุ่มทางลัดแบบแคปซูล (ไม่ได้ใช้ / ครึ่งหนึ่ง / ใช้หมด)
  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), // [UI] ระยะในปุ่ม
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white, // [UI] เลือกอยู่ = พื้นครีม ไม่เลือก = ขาว
          borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
          border: Border.all(
            color: selected ? const Color(0xFFFFD191) : Colors.black12, // [UI] เลือกอยู่ = ขอบส้มอ่อน ไม่เลือก = ขอบเทาจาง
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13, // [UI] ขนาดตัวอักษร
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  // ปุ่ม − / + ปรับจำนวน
  Widget _stepButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32, // [UI] ขนาดปุ่ม 32x32
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
          border: Border.all(color: const Color(0xFFFFD191)), // [UI] เส้นขอบสีส้มอ่อน
        ),
        child: Icon(icon, size: 18, color: Colors.black87), // [UI] ไอคอนขนาด 18
      ),
    );
  }

  // สร้างแถววัตถุดิบ 1 แถว
  Widget _buildLine(_Line line) {
    if (!line.found) { // ไม่มีในตู้ -> แถวสีจางพร้อมข้อความ
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10), // [UI] ระยะบนล่างของแถว
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black38, // [UI] สีจาง (ไม่มีของ)
                ),
              ),
            ),
            const Text(
              "ไม่มีในตู้เย็น",
              style: TextStyle(fontSize: 13, color: Colors.black38),
            ),
          ],
        ),
      );
    }

    final half = line.available / 2; // ค่าครึ่งหนึ่งของที่มี
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Text(
                "เหลือ ${_fmt(line.available)} ${line.unit}", // บอกว่าในตู้เหลือเท่าไหร่
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          if (line.note != null)
            Text(
              "หักจากลอตที่${line.note}ก่อน",
              style: const TextStyle(fontSize: 12, color: Colors.black45), // [UI] ข้อความเล็กสีเทา
            ),
          if (line.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.orange.shade800, // [UI] สีส้มเข้ม (คำเตือน)
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      line.warning!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stepButton(
                Icons.remove,
                () => _set(line, line.amount - line.step), // กด − ลดทีละ step
              ),
              SizedBox(
                width: 70, // [UI] ความกว้างช่องแสดงจำนวน
                child: Text(
                  line.amount == 0
                      ? "ไม่ใช้"
                      : "${_fmt(line.amount)} ${line.unit}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _stepButton(Icons.add, () => _set(line, line.amount + line.step)), // กด + เพิ่มทีละ step
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6, // [UI] ระยะห่างแนวนอนระหว่างปุ่มทางลัด
                  runSpacing: 6,
                  alignment: WrapAlignment.end, // [UI] ปุ่มทางลัดชิดขวา
                  children: [
                    _chip("ไม่ได้ใช้", line.amount == 0, () => _set(line, 0)),
                    if (line.available > line.step) // มีมากกว่า 1 step ถึงจะแสดง "ครึ่งหนึ่ง"
                      _chip(
                        "ครึ่งหนึ่ง",
                        line.amount == half,
                        () => _set(line, half),
                      ),
                    _chip(
                      "ใช้หมด",
                      line.amount == line.available,
                      () => _set(line, line.available),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8; // [UI] แผ่นสูงสุด 80% ของจอ
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), // [UI] ระยะในแผ่น
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container( // ขีดเล็กๆ ด้านบน (บอกว่าลากลงเพื่อปิดได้)
                  width: 40, // [UI] ความกว้างขีด
                  height: 4, // [UI] ความสูงขีด
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "ใช้วัตถุดิบไปเท่าไหร่?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), // [UI] หัวข้อขนาด 18
              ),
              const SizedBox(height: 4),
              const Text(
                "ระบบเลือกไว้ให้ตามสูตรแล้ว ถ้าใช้ไม่ตรงกดเปลี่ยนได้เลย",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated( // รายการวัตถุดิบ (เลื่อนได้)
                  shrinkWrap: true, // สูงเท่าเนื้อหา
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1), // [UI] เส้นคั่นระหว่างแถว
                  itemBuilder: (_, i) => _buildLine(lines[i]),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50, // [UI] ความสูงปุ่ม
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context), // ยกเลิก -> ปิดแผ่นโดยไม่ส่งค่า (null)
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffE0E0E0), // [UI] ปุ่มเทา
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
                          ),
                        ),
                        child: const Text(
                          "ยกเลิก",
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop( // ยืนยัน -> ปิดแผ่นพร้อมส่งรายการที่เลือกกลับ
                          context,
                          lines
                              .map(
                                (l) => DeductChoice(
                                  name: l.name,
                                  amount: l.found ? l.amount : null,
                                ),
                              )
                              .toList(),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffD7EDFF), // [UI] ปุ่มฟ้าอ่อน
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "ยืนยัน หักวัตถุดิบ",
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
