import 'package:flutter/material.dart';

import '../services/fridge_stock.dart';
import '../utils/fridge_age.dart';

/// วัตถุดิบ 1 รายการที่สูตรบอกว่าต้องใช้ พร้อมปริมาณที่สูตรแนะนำ
class DeductRequest {
  final String name;
  final num suggested;

  const DeductRequest({required this.name, required this.suggested});
}

/// ผลที่ผู้ใช้ยืนยันแล้ว — amount = null แปลว่าไม่มีวัตถุดิบนี้ในตู้เย็น
class DeductChoice {
  final String name;
  final num? amount;

  const DeductChoice({required this.name, required this.amount});
}

num _toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

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
  return showModalBottomSheet<List<DeductChoice>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DeductConfirmSheet(inventory: inventory, requests: requests),
  );
}

class _Line {
  final String name;
  final num available;
  final String unit;
  final String? note;
  num amount;

  _Line({
    required this.name,
    required this.available,
    required this.unit,
    required this.note,
    required this.amount,
  });

  bool get found => available > 0;

  // ของที่นับเป็น "ส่วน" ปรับได้ทีละครึ่งส่วน ของที่นับเป็นชิ้นปรับทีละชิ้น
  num get step => unit == 'ส่วน' ? 0.5 : 1;
}

class _DeductConfirmSheet extends StatefulWidget {
  final List<Map<String, dynamic>> inventory;
  final List<DeductRequest> requests;

  const _DeductConfirmSheet({required this.inventory, required this.requests});

  @override
  State<_DeductConfirmSheet> createState() => _DeductConfirmSheetState();
}

class _DeductConfirmSheetState extends State<_DeductConfirmSheet> {
  late final List<_Line> lines;

  @override
  void initState() {
    super.initState();
    lines = widget.requests.map((req) {
      final lots =
          widget.inventory
              .where(
                (lot) =>
                    ingredientNameMatches(lot['name'], req.name) &&
                    _toNum(lot['quantity']) > 0,
              )
              .toList()
            ..sort(compareFifo);
      final available = availableQuantity(lots, req.name);
      final unit = lots.isEmpty ? '' : (lots.first['unit']?.toString() ?? '');

      // บอกลอตที่จะถูกหักก่อน (ใกล้หมดอายุที่สุด) ให้ผู้ใช้เห็น
      String? note;
      if (lots.isNotEmpty) {
        final expiry = daysLeft(lots.first);
        note = expiry == null ? null : expiryText(expiry);
      }

      // ค่าเริ่มต้นตามสูตร ปัดให้เป็นหน่วยที่กดได้จริง (ครึ่งส่วน / ทีละชิ้น)
      // และไม่เกินที่มีอยู่
      final step = unit == 'ส่วน' ? 0.5 : 1;
      num amount = (req.suggested / step).round() * step;
      if (req.suggested > 0 && amount == 0) amount = step;
      if (amount > available) amount = available;

      return _Line(
        name: req.name,
        available: available,
        unit: unit,
        note: note,
        amount: amount,
      );
    }).toList();
  }

  void _set(_Line line, num value) {
    setState(() {
      line.amount = value.clamp(0, line.available);
    });
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7D0) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFFD191) : Colors.black12,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFD191)),
        ),
        child: Icon(icon, size: 18, color: Colors.black87),
      ),
    );
  }

  Widget _buildLine(_Line line) {
    if (!line.found) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                line.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black38,
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

    final half = line.available / 2;
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
                "เหลือ ${_fmt(line.available)} ${line.unit}",
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          if (line.note != null)
            Text(
              "หักจากลอตที่${line.note}ก่อน",
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stepButton(Icons.remove, () => _set(line, line.amount - line.step)),
              SizedBox(
                width: 70,
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
              _stepButton(Icons.add, () => _set(line, line.amount + line.step)),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    _chip("ไม่ได้ใช้", line.amount == 0, () => _set(line, 0)),
                    if (line.available > line.step)
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
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "ใช้วัตถุดิบไปเท่าไหร่?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "ระบบเลือกไว้ให้ตามสูตรแล้ว ถ้าใช้ไม่ตรงกดเปลี่ยนได้เลย",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _buildLine(lines[i]),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffE0E0E0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
                        onPressed: () => Navigator.pop(
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
                          backgroundColor: const Color(0xffD7EDFF),
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
