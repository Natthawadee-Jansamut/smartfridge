import 'package:flutter/material.dart';

import '../utils/shelf_life.dart';

/// กล่องบนการ์ดวัตถุดิบที่เกินระยะที่เก็บได้แล้ว: คำแนะนำตามชนิดของ และถ้าเป็น
/// ของที่ตรวจด้วยตาได้ (ผัก ผลไม้ ไข่ ฯลฯ) มีปุ่ม "ตรวจแล้วยังใช้ได้ +1/+2/+3
/// วัน" ให้ต่อเวลาได้เลย — ของที่ไม่ควรเสี่ยง (เนื้อสัตว์ อาหารทะเล อาหารเหลือ)
/// ไม่มีปุ่มนี้ ใช้ร่วมกันในหน้าคลังและหน้าแจ้งเตือน
class OverdueNotice extends StatelessWidget {
  final Map<String, dynamic> item;

  /// กดต่อเวลา — ส่งจำนวนวันที่ "เก็บได้อีก" นับจากวันนี้
  final ValueChanged<int> onExtend;

  const OverdueNotice({super.key, required this.item, required this.onExtend});

  static const Color _red = Color(0xffD64545);

  @override
  Widget build(BuildContext context) {
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
                  overdueAdvice(item),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xffB03A3A),
                  ),
                ),
              ),
            ],
          ),
          if (canExtendOverdue(item)) ...[
            const SizedBox(height: 8),
            // ใช้ Wrap ให้ปุ่มขึ้นบรรทัดใหม่เองเมื่อการ์ดแคบ (เช่นในหน้าคลัง)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "ตรวจแล้วยังใช้ได้:",
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
