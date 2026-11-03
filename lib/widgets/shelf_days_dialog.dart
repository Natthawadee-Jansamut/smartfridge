import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/fridge_age.dart';
import '../utils/shelf_life.dart';

/// หน้าต่าง "แก้ระยะที่เก็บได้" ใช้ร่วมกันในหน้าคลังและหน้าแจ้งเตือน — แก้ได้ทั้ง
/// พิมพ์จำนวนวันเอง และกด "ใช้ค่าแนะนำ" เพื่อคืนค่าเดิม (เช่นกด +วันผิด)
/// ถ้าแก้กลับเป็นค่าเดิม ที่มาจะกลับเป็นแหล่งข้อมูลเดิม ไม่ค้างเป็น "คุณกำหนดเอง"
///
/// คืน true ถ้าบันทึกสำเร็จ (หน้าที่เรียกควรโหลดข้อมูลใหม่)
Future<bool> editShelfDaysDialog(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  final current = shelfDaysOf(item);
  final original = originalShelfSource(item['shelf_type']?.toString(), current);
  final age = daysInFridge(storageStartOf(item));
  final controller = TextEditingController(
    text: current?.toInt().toString() ?? '',
  );

  final days = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        "แก้ระยะที่เก็บได้",
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "เก็บใน${storageLabel(item['storage']?.toString())}ได้",
              suffixText: "วัน",
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "อยู่ในช่องนี้มาแล้ว $age วัน"
            "${original.days == null ? '' : ' · ค่าแนะนำ ${formatShelfDays(original.days!)}'}",
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
      actions: [
        if (original.days != null && original.days != current?.round())
          TextButton(
            onPressed: () => Navigator.pop(ctx, original.days),
            child: const Text("ใช้ค่าแนะนำ"),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("ยกเลิก"),
        ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(controller.text.trim());
            if (v != null && v > 0) Navigator.pop(ctx, v);
          },
          child: const Text("บันทึก"),
        ),
      ],
    ),
  );
  if (days == null) return false;

  final newShelfType = (original.days != null && days == original.days)
      ? original.key
      : customShelfType(original.key, original.days);
  final added = parseCreatedAt(storageStartOf(item)) ?? DateTime.now();

  try {
    await Supabase.instance.client
        .from('fridge_items')
        .update({
          item['storage'] == storageFreezer ? 'freezer_days' : 'fridge_days':
              days,
          // expiry_date เป็น timestamptz ต้องส่งเป็น UTC (มี Z)
          'expiry_date': added
              .add(Duration(days: days))
              .toUtc()
              .toIso8601String(),
          'shelf_type': newShelfType,
          // ผู้ใช้กำหนดเอง ค่านี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
          'days_left_at_freeze': null,
        })
        .eq('item_id', item['item_id']);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
    }
    return false;
  }
}
