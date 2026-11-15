import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้บันทึกลงฐานข้อมูล

import 'package:test_app/utils/fridge_age.dart'; // ฟังก์ชันนับวันที่อยู่ในตู้
import 'package:test_app/utils/shelf_life.dart'; // ฟังก์ชันอายุการเก็บ

/// หน้าต่าง "แก้ระยะที่เก็บได้" ใช้ร่วมกันในหน้าคลังและหน้าแจ้งเตือน — แก้ได้ทั้ง
/// พิมพ์จำนวนวันเอง และกด "ใช้ค่าแนะนำ" เพื่อคืนค่าเดิม (เช่นกด +วันผิด)
/// ถ้าแก้กลับเป็นค่าเดิม ที่มาจะกลับเป็นแหล่งข้อมูลเดิม ไม่ค้างเป็น "คุณกำหนดเอง"
///
/// คืน true ถ้าบันทึกสำเร็จ (หน้าที่เรียกควรโหลดข้อมูลใหม่)
Future<bool> editShelfDaysDialog(
  BuildContext context,
  Map<String, dynamic> item, // วัตถุดิบที่จะแก้
) async {
  final current = shelfDaysOf(item); // จำนวนวันที่เก็บได้ตอนนี้
  final original = recommendedShelf(item); // ค่าแนะนำ (ค่าตายตัวดูจากตาราง)
  final age = daysInFridge(storageStartOf(item)); // อยู่ในตู้มาแล้วกี่วัน
  final controller = TextEditingController( // ตัวควบคุมช่องกรอกตัวเลข
    text: current?.toInt().toString() ?? '', // ใส่ค่าปัจจุบันไว้ให้ก่อน
  );

  // เปิดหน้าต่างป๊อปอัป แล้วรอผลว่าผู้ใช้เลือกกี่วัน (null = กดยกเลิก)
  final days = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog( // กล่องป๊อปอัปแบบมาตรฐาน
      title: const Text(
        "แก้ระยะที่เก็บได้", // หัวข้อป๊อปอัป
        style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
      ),
      content: Column( // เนื้อหาในป๊อปอัป
        mainAxisSize: MainAxisSize.min, // [UI] สูงเท่าเนื้อหา ไม่ยืดเต็มจอ
        crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดซ้าย
        children: [
          TextField( // ช่องกรอกจำนวนวัน
            controller: controller,
            keyboardType: TextInputType.number, // [UI] เปิดแป้นตัวเลข
            autofocus: true, // [UI] เปิดป๊อปอัปแล้วคีย์บอร์ดขึ้นทันที
            decoration: InputDecoration(
              labelText:
                  "เก็บใน${storageLabel(item['storage']?.toString())}ได้", // ป้ายกำกับ เช่น "เก็บในช่องเย็นได้"
              suffixText: "วัน", // [UI] คำว่า "วัน" ต่อท้ายในช่อง
            ),
          ),
          const SizedBox(height: 10), // [UI] ระยะห่างใต้ช่องกรอก
          Text(
            "อยู่ในช่องนี้มาแล้ว $age วัน"
            "${original.days == null ? '' : ' · ค่าแนะนำ ${formatShelfDays(original.days!)}'}", // มีค่าแนะนำก็แสดงต่อท้าย
            style: const TextStyle(fontSize: 13, color: Colors.black54), // [UI] ตัวเล็กสีเทา
          ),
        ],
      ),
      actions: [ // ปุ่มด้านล่างป๊อปอัป
        if (original.days != null && original.days != current?.round()) // แสดงเฉพาะเมื่อค่าตอนนี้ต่างจากค่าแนะนำ
          TextButton(
            onPressed: () => Navigator.pop(ctx, original.days), // ปิดป๊อปอัปพร้อมส่งค่าแนะนำกลับ
            child: const Text("ใช้ค่าแนะนำ"),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx), // ปิดโดยไม่ส่งค่า = ยกเลิก
          child: const Text("ยกเลิก"),
        ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(controller.text.trim()); // แปลงข้อความเป็นตัวเลข
            if (v != null && v > 0) Navigator.pop(ctx, v); // ตัวเลขถูกต้องและมากกว่า 0 ถึงจะปิดพร้อมส่งค่า
          },
          child: const Text("บันทึก"),
        ),
      ],
    ),
  );
  if (days == null) return false; // ผู้ใช้กดยกเลิก

  // ถ้ากลับไปเท่าค่าแนะนำ ใช้ที่มาเดิม ไม่งั้นติดป้าย "กำหนดเอง"
  final newShelfType = shelfTypeForDays(item, days); // เท่าค่าแนะนำ = ที่มาเดิม, ไม่งั้น = กำหนดเอง
  final added = parseCreatedAt(storageStartOf(item)) ?? DateTime.now(); // วันที่เริ่มเก็บในช่องนี้

  try {
    await Supabase.instance.client
        .from('fridge_items') // ตารางของในตู้เย็น
        .update({
          // อยู่ช่องแช่แข็งบันทึกที่ freezer_days ไม่งั้นบันทึกที่ fridge_days
          item['storage'] == storageFreezer ? 'freezer_days' : 'fridge_days':
              days,
          // expiry_date เป็น timestamptz ต้องส่งเป็น UTC (มี Z)
          'expiry_date': added
              .add(Duration(days: days)) // วันหมด = วันเริ่มเก็บ + จำนวนวัน
              .toUtc()
              .toIso8601String(),
          'shelf_type': newShelfType, // ที่มาของค่า
          // ผู้ใช้กำหนดเอง ค่านี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
          'days_left_at_freeze': null,
        })
        .eq('item_id', item['item_id']); // อัปเดตเฉพาะชิ้นนี้
    return true; // บันทึกสำเร็จ
  } catch (e) {
    if (context.mounted) { // หน้ายังเปิดอยู่ไหม (กันแอปพังถ้าปิดหน้าไปแล้ว)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e"))); // แจ้ง error ด้านล่างจอ
    }
    return false;
  }
}
