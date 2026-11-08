import 'package:flutter/material.dart';

import 'package:test_app/utils/shelf_life.dart';

/// กล่องบนการ์ดวัตถุดิบที่เกินระยะเก็บที่แนะนำแล้ว ใช้ร่วมกันในหน้าคลังและหน้าแจ้งเตือน
///
/// - ของที่ต่อเวลาได้ (ผัก ผลไม้ ขนมปัง ไข่ นม ฯลฯ): ให้ดูวันบนฉลากก่อน —
///   "ควรบริโภคก่อน" (BBF) ยังใช้ได้ถ้าสภาพปกติ, "หมดอายุ" (EXP) ไม่ควรกิน —
///   ถ้าไม่มีฉลาก (เช่น ซื้อตลาดสด) ใช้คำแนะนำตามชนิดของ แล้วมีปุ่ม
///   "ตรวจแล้วยังใช้ได้ +1/+2/+3 วัน"
/// - ของที่ไม่ควรเสี่ยง (เนื้อสัตว์ อาหารทะเล อาหารเหลือ แปรรูปที่เปิดแล้ว):
///   บอกให้ทิ้ง ไม่มีปุ่มต่อเวลา
///
/// ใช้คำว่า "เกินระยะเก็บที่แนะนำ" ไม่ใช่ "หมดอายุ" เพราะวันในแอปเป็นค่าประมาณ
/// ตามชนิดวัตถุดิบ ไม่ใช่วันบนฉลากจริง
class OverdueNotice extends StatelessWidget {
  final Map<String, dynamic> item;

  /// กดต่อเวลา — ส่งจำนวนวันที่ "เก็บได้อีก" นับจากวันนี้
  final ValueChanged<int> onExtend;

  const OverdueNotice({super.key, required this.item, required this.onExtend});

  static const Color _red = Color(0xffD64545);

  static const _textStyle = TextStyle(fontSize: 12, color: Color(0xff7A2E2E));

  @override
  Widget build(BuildContext context) {
    final canExtend = canExtendOverdue(item);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFADBD8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: _red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  canExtend
                      ? "เกินระยะเก็บที่แนะนำ ตรวจก่อนใช้"
                      : "เกินระยะเก็บที่แนะนำ ${overdueAdvice(item)}",
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xffB03A3A),
                  ),
                ),
              ),
            ],
          ),
          if (canExtend) ...[
            const SizedBox(height: 4),
            const Text(
              "ฉลาก \"ควรบริโภคก่อน\" ใช้ได้ถ้าสภาพปกติ, \"หมดอายุ\" ควรทิ้ง",
              style: _textStyle,
            ),
            Text("ไม่มีฉลาก: ${overdueAdvice(item)}", style: _textStyle),
            const SizedBox(height: 8),
            // ใช้ Wrap ให้ปุ่มขึ้นบรรทัดใหม่เองเมื่อการ์ดแคบ (เช่นในหน้าคลัง)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "ยังใช้ได้:",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                for (final days in const [1, 2, 3]) _buildButton(days),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButton(int days) {
    return InkWell(
      onTap: () => onExtend(days),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8A0A0)),
        ),
        child: Text(
          "+$days วัน",
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
