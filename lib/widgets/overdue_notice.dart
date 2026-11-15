import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/utils/shelf_life.dart'; // ฟังก์ชันเรื่องอายุการเก็บ (ต่อเวลาได้ไหม / คำแนะนำ)

/// กล่องบนการ์ดวัตถุดิบที่เกินระยะเก็บที่แนะนำแล้ว ใช้ร่วมกันในหน้าคลังและหน้าแจ้งเตือน
///
/// - ของที่ต่อเวลาได้ (ผัก ผลไม้ ขนมปัง ไข่ นม ฯลฯ): ให้ตรวจฉลากสินค้า (ควรบริโภค
///   ก่อน / หมดอายุ) และสภาพก่อนตัดสินใจ แล้วมีปุ่ม "ยังใช้ได้ +1/+2/+3 วัน"
/// - ของที่ไม่ควรเสี่ยง (เนื้อสัตว์ อาหารทะเล อาหารเหลือ แปรรูปที่เปิดแล้ว):
///   บอกให้ทิ้ง ไม่มีปุ่มต่อเวลา
///
/// ใช้คำว่า "เกินระยะเก็บที่แนะนำ" ไม่ใช่ "หมดอายุ" เพราะวันในแอปเป็นค่าประมาณ
/// ตามชนิดวัตถุดิบ ไม่ใช่วันบนฉลากจริง
class OverdueNotice extends StatelessWidget {
  final Map<String, dynamic> item; // ข้อมูลวัตถุดิบชิ้นนั้น

  /// กดต่อเวลา — ส่งจำนวนวันที่ "เก็บได้อีก" นับจากวันนี้
  final ValueChanged<int> onExtend;

  const OverdueNotice({super.key, required this.item, required this.onExtend});

  static const Color _red = Color(0xffD64545); // [UI] สีแดงของไอคอนเตือน

  @override
  Widget build(BuildContext context) {
    final canExtend = canExtendOverdue(item); // ของชิ้นนี้ต่อเวลาได้ไหม
    return Container( // กล่องพื้นชมพูอ่อน
      width: double.infinity, // [UI] กว้างเต็มการ์ด
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8), // [UI] ระยะในกล่อง ซ้าย 10 บน 8 ขวา 10 ล่าง 8
      decoration: BoxDecoration(
        color: const Color(0xFFFADBD8), // [UI] สีพื้นกล่อง (ชมพูอ่อน)
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
      ),
      child: Column( // เรียงข้อความกับปุ่มจากบนลงล่าง
        crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดซ้าย
        children: [
          Row( // แถวไอคอน + ข้อความเตือน
            crossAxisAlignment: CrossAxisAlignment.start, // [UI] ไอคอนชิดบรรทัดบนสุดของข้อความ
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: _red), // [UI] ไอคอนสามเหลี่ยมเตือน ขนาด 16
              const SizedBox(width: 6), // [UI] ช่องว่างระหว่างไอคอนกับข้อความ
              Expanded( // ให้ข้อความกินพื้นที่ที่เหลือและตัดบรรทัดได้
                child: Text(
                  // ต่อเวลาได้ -> ให้ตรวจฉลาก, ต่อไม่ได้ -> แสดงคำแนะนำ (เช่นควรทิ้ง)
                  "เกินระยะเก็บที่แนะนำ ${canExtend ? "ควรตรวจดูฉลากสินค้าและสภาพก่อนตัดสินใจรับประทาน" : overdueAdvice(item)}",
                  style: const TextStyle(
                    fontSize: 12.5, // [UI] ขนาดตัวอักษร
                    fontWeight: FontWeight.w600, // [UI] ความหนา (w400 ปกติ, w700 หนา)
                    color: Color(0xffB03A3A), // [UI] สีตัวอักษรแดงเข้ม
                  ),
                ),
              ),
            ],
          ),
          if (canExtend) ...[ // แสดงปุ่มต่อเวลาเฉพาะของที่ต่อได้
            const SizedBox(height: 8), // [UI] ระยะห่างจากข้อความถึงแถวปุ่ม
            // ใช้ Wrap ให้ปุ่มขึ้นบรรทัดใหม่เองเมื่อการ์ดแคบ (เช่นในหน้าคลัง)
            Wrap(
              spacing: 6, // [UI] ระยะห่างแนวนอนระหว่างปุ่ม
              runSpacing: 6, // [UI] ระยะห่างแนวตั้งเมื่อปุ่มตกบรรทัด
              crossAxisAlignment: WrapCrossAlignment.center, // [UI] จัดกึ่งกลางแนวตั้ง
              children: [
                const Text(
                  "ยังใช้ได้:",
                  style: TextStyle(fontSize: 12, color: Colors.black54), // [UI] ตัวเล็กสีเทา
                ),
                for (final days in const [1, 2, 3]) _buildButton(days), // [UI] สร้างปุ่ม +1 +2 +3 วัน (แก้ลิสต์เพื่อเปลี่ยนตัวเลือก)
              ],
            ),
          ],
        ],
      ),
    );
  }

  // สร้างปุ่ม "+N วัน" 1 ปุ่ม
  Widget _buildButton(int days) {
    return InkWell( // ทำให้กดได้ (มีเอฟเฟกต์คลื่นตอนกด)
      onTap: () => onExtend(days), // กดแล้วส่งจำนวนวันกลับไปให้หน้าที่เรียกใช้
      borderRadius: BorderRadius.circular(14), // [UI] ขอบเขตเอฟเฟกต์ตอนกดให้โค้งตามปุ่ม
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), // [UI] ระยะในปุ่ม ซ้ายขวา 10 บนล่าง 5
        decoration: BoxDecoration(
          color: Colors.white, // [UI] พื้นปุ่มสีขาว
          borderRadius: BorderRadius.circular(14), // [UI] ปุ่มทรงแคปซูล
          border: Border.all(color: const Color(0xFFE8A0A0)), // [UI] เส้นขอบชมพู
        ),
        child: Text(
          "+$days วัน",
          style: const TextStyle(
            fontSize: 12, // [UI] ขนาดตัวอักษรในปุ่ม
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
