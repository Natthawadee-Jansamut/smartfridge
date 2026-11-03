import 'package:flutter/material.dart';

import 'app_icons.dart';
import '../utils/fridge_age.dart';

/// วิดเจ็ตที่ใช้ร่วมกันในกลุ่มหน้า "สแกนสูตรอาหาร" ทั้ง 3 หน้า
/// (คลังสูตรอาหาร / สแกนสูตรอาหาร / ผลการสแกนสูตรอาหาร)
/// เพื่อให้ดีไซน์ตรงกับ Figma แบบเดียวกันทุกหน้า และแก้ที่เดียวจบ

/// แถบหัวเรื่องแบบ "ช่องค้นหา" (ปุ่มย้อนกลับ + แคปซูลไอคอนสแกน/ชื่อหน้า/ไอคอนค้นหา + ปุ่มตัวกรองวงกลม)
class RecipeFlowHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onFilterTap;

  const RecipeFlowHeader({super.key, required this.title, this.onFilterTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Center(child: BackIcon(size: 24)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(27),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7D0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const ScannerIcon(size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.search, color: Colors.black54, size: 22),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onFilterTap,
              child: const Center(child: FilterIcon(size: 20)),
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบ "ป้ายชื่อ/หัวข้อ (สีเหลือง) + สัดส่วนวัตถุดิบ X/Y (ขาวขอบดำ) + แถบความคืบหน้า + คำอธิบาย"
/// ใช้ทั้งในหน้ารายการสูตร (label = ชื่อเมนู) และหน้าผลการสแกน (label = "สถานะวัตถุดิบ")
/// ตัวเลข X/Y ต้องมาจากข้อมูลจริงใน Supabase เสมอ (ห้ามใช้ตัวเลข mock ของ Figma)
class RecipeStatusBar extends StatelessWidget {
  final String label;
  final int have;
  final int total;

  const RecipeStatusBar({
    super.key,
    required this.label,
    required this.have,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : have / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7D0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black87, width: 1.4),
              ),
              child: Text(
                "$have/$total",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE3F2FD),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xff5189C9),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "คุณมีวัตถุดิบครบ $have จาก $total รายการ",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// ปุ่ม "แก้ไข" ทรงแคปซูลขอบดำ ใช้แสดงมุมขวาของหัวข้อการ์ดวัตถุดิบ/ขั้นตอนการทำ
/// (ยังไม่ผูกฟังก์ชันแก้ไขจริง รอสเปกเพิ่มเติมว่าจะให้แก้ไขอะไรได้บ้าง)
class EditPillButton extends StatelessWidget {
  final VoidCallback? onTap;

  const EditPillButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black87, width: 1.2),
        ),
        child: const Text(
          "แก้ไข",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xff5189C9),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// แปลงเวลาบันทึก (created_at จาก Supabase) เป็นข้อความเวลาแบบสัมพัทธ์ภาษาไทย
/// เช่น "5 นาทีที่แล้ว", "1 ชั่วโมงที่แล้ว" (ของจริงจากฐานข้อมูล ไม่ใช่ตัวเลข mock)
String relativeTimeThai(String? createdAt) {
  if (createdAt == null || createdAt.isEmpty) return '-';
  // created_at เป็นเวลา UTC ที่ไม่มีตัวบอก timezone (ดู parseCreatedAt)
  final dt = parseCreatedAt(createdAt);
  if (dt == null) return '-';
  final diff = DateTime.now().difference(dt);

  if (diff.inSeconds < 60) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 30) return '${diff.inDays} วันที่แล้ว';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} เดือนที่แล้ว';
  return '${(diff.inDays / 365).floor()} ปีที่แล้ว';
}

/// แถบหัวเรื่องสีครีมเหลืองทั้งแถบ ใช้ในกลุ่มหน้า "สแกนวัตถุดิบเข้าตู้เย็น"
/// (ถ่ายรูปวัตถุดิบ / ผลลัพธ์หลังสแกน) ต่างจาก [RecipeFlowHeader] ที่เป็นพื้นขาว
/// + ไอคอนค้นหา (ใช้ในฝั่งสแกนสูตรอาหาร) — โครงสร้างเดียวกันแต่สีต่างกันตาม Figma
class IngredientFlowHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onFilterTap;

  const IngredientFlowHeader({
    super.key,
    required this.title,
    this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Center(child: BackIcon(size: 24)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ScannerIcon(size: 20),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 50,
            width: 50,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7D0),
              shape: BoxShape.circle,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onFilterTap,
              child: const Center(child: FilterIcon(size: 20)),
            ),
          ),
        ],
      ),
    );
  }
}
