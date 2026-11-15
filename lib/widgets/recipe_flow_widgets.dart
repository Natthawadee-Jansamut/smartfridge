import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/widgets/app_icons.dart'; // ไอคอน
import 'package:test_app/utils/fridge_age.dart'; // แปลงเวลา created_at
import 'package:test_app/screens/recipe_scan/recipe_search_screen.dart'; // หน้าค้นหาสูตร
import 'package:test_app/services/fridge_images.dart'; // ขอลิงก์รูปส่วนตัว

/// วิดเจ็ตที่ใช้ร่วมกันในกลุ่มหน้า "สแกนสูตรอาหาร" ทั้ง 3 หน้า
/// (คลังสูตรอาหาร / สแกนสูตรอาหาร / ผลการสแกนสูตรอาหาร)
/// เพื่อให้ดีไซน์ตรงกับ Figma แบบเดียวกันทุกหน้า และแก้ที่เดียวจบ

/// แถบหัวเรื่องแบบ "ช่องค้นหา" (ปุ่มย้อนกลับ + แคปซูลไอคอนสแกน/ชื่อหน้า/ไอคอนค้นหา + ปุ่มตัวกรองวงกลม)
class RecipeFlowHeader extends StatelessWidget {
  final String title; // ชื่อหน้า

  /// กดช่องค้นหา — ไม่ส่งมา = เปิดหน้าค้นหาสูตรอาหาร
  final VoidCallback? onSearchTap;

  /// false = ไม่มีไอคอนค้นหา และกดแถบไม่ได้
  /// (ใช้กับหน้า "เมนูแนะนำ" จาก AI ที่ไม่เกี่ยวกับการค้นหาสูตรในคลัง)
  final bool showSearch;

  /// ไอคอนหน้าชื่อหน้า — ไม่ส่งมา = ไอคอนสแกน
  final Widget? icon;

  const RecipeFlowHeader({
    super.key,
    required this.title,
    this.onSearchTap,
    this.showSearch = true,
    this.icon,
  });

  // กดแถบค้นหา: ถ้าส่ง onSearchTap มาใช้อันนั้น ไม่งั้นเปิดหน้าค้นหาสูตร
  void _openSearch(BuildContext context) {
    if (onSearchTap != null) {
      onSearchTap!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeSearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0), // [UI] ระยะ ซ้าย 20 บน 15 ขวา 20 ล่าง 0
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.pop(context), // ปุ่มย้อนกลับ
            child: Container(
              height: 50, // [UI] ขนาดปุ่ม 50x50
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีครีมเหลือง
                borderRadius: BorderRadius.circular(25), // [UI] โค้ง 25 = วงกลม
              ),
              child: const Center(child: BackIcon(size: 24)), // [UI] ไอคอนย้อนกลับ ขนาด 24
            ),
          ),
          const SizedBox(width: 10), // [UI] ระยะปุ่มกับแถบชื่อ
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: showSearch ? () => _openSearch(context) : null, // ปิดค้นหา = กดไม่ได้
              // สีเดียวกับแถบหัวข้อของหน้าอื่นๆ ในแอป (เหลืองอ่อน)
              child: Container(
                height: 50, // [UI] ความสูงแถบ
                padding: const EdgeInsets.symmetric(horizontal: 16), // [UI] ระยะในซ้ายขวา
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7D0), // [UI] สีแถบ
                  borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                ),
                child: Row(
                  children: [
                    icon ?? const ScannerIcon(size: 22), // ไอคอนที่ส่งมา หรือไอคอนสแกน (ขนาด 22)
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15, // [UI] ขนาดชื่อหน้า
                          color: Colors.black87,
                        ),
                        maxLines: 1, // [UI] แสดงบรรทัดเดียว
                        overflow: TextOverflow.ellipsis, // [UI] ยาวเกินตัดเป็น ...
                      ),
                    ),
                    if (showSearch) ...[
                      const Icon(Icons.search, color: Colors.black54, size: 22), // [UI] ไอคอนแว่นขยาย
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
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
  final String label; // ชื่อสูตร/หัวข้อ
  final int have; // มีวัตถุดิบกี่อย่าง
  final int total; // ต้องใช้ทั้งหมดกี่อย่าง

  const RecipeStatusBar({
    super.key,
    required this.label,
    required this.have,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : have / total; // สัดส่วนสำหรับแถบความคืบหน้า (0.0 - 1.0)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, // [UI] ระยะในป้ายชื่อซ้ายขวา
                  vertical: 8, // [UI] ระยะในป้ายชื่อบนล่าง
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7D0), // [UI] สีป้ายชื่อ (ครีมเหลือง)
                  borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15, // [UI] ขนาดชื่อ
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // [UI] ระยะในป้าย X/Y
              decoration: BoxDecoration(
                color: Colors.white, // [UI] พื้นขาว
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black87, width: 1.4), // [UI] เส้นขอบดำ หนา 1.4
              ),
              child: Text(
                "$have/$total", // ตัวเลข มี/ทั้งหมด
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10), // [UI] ระยะป้ายกับแถบ
        ClipRRect(
          borderRadius: BorderRadius.circular(10), // [UI] มุมแถบโค้ง
          child: LinearProgressIndicator( // แถบความคืบหน้า
            value: progress,
            minHeight: 8, // [UI] ความหนาแถบ
            backgroundColor: const Color(0xFFE3F2FD), // [UI] สีพื้นแถบ (ฟ้าอ่อน)
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff5189C9)), // [UI] สีส่วนที่เต็ม (ฟ้า)
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "คุณมีวัตถุดิบครบ $have จาก $total รายการ",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600), // [UI] ข้อความเล็กสีเทา
        ),
      ],
    );
  }
}

/// ปุ่ม "แก้ไข" ทรงแคปซูลขอบดำ ใช้แสดงมุมขวาของหัวข้อการ์ดวัตถุดิบ/ขั้นตอนการทำ
/// (ยังไม่ผูกฟังก์ชันแก้ไขจริง รอสเปกเพิ่มเติมว่าจะให้แก้ไขอะไรได้บ้าง)
class EditPillButton extends StatelessWidget {
  final VoidCallback? onTap; // กดแล้วทำอะไร

  const EditPillButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), // [UI] ระยะในปุ่ม
        decoration: BoxDecoration(
          color: Colors.white, // [UI] พื้นขาว
          borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
          border: Border.all(color: Colors.black87, width: 1.2), // [UI] ขอบดำหนา 1.2
        ),
        child: const Text(
          "แก้ไข",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xff5189C9), // [UI] ตัวอักษรสีฟ้า
            fontSize: 13, // [UI] ขนาด 13
          ),
        ),
      ),
    );
  }
}

/// แปลงเวลาบันทึก (created_at จาก Supabase) เป็นข้อความเวลาแบบสัมพัทธ์ภาษาไทย
/// เช่น "5 นาทีที่แล้ว", "1 ชั่วโมงที่แล้ว" (ของจริงจากฐานข้อมูล ไม่ใช่ตัวเลข mock)
String relativeTimeThai(String? createdAt) {
  if (createdAt == null || createdAt.isEmpty) return '-'; // ไม่มีเวลา
  // created_at เป็นเวลา UTC ที่ไม่มีตัวบอก timezone (ดู parseCreatedAt)
  final dt = parseCreatedAt(createdAt); // แปลงเป็นเวลาเครื่อง
  if (dt == null) return '-';
  final diff = DateTime.now().difference(dt); // ห่างจากตอนนี้เท่าไหร่

  if (diff.inSeconds < 60) return 'เมื่อสักครู่'; // ไม่ถึงนาที
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว'; // ไม่ถึงชั่วโมง -> นาที
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว'; // ไม่ถึงวัน -> ชั่วโมง
  if (diff.inDays < 30) return '${diff.inDays} วันที่แล้ว'; // ไม่ถึงเดือน -> วัน
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} เดือนที่แล้ว'; // ไม่ถึงปี -> เดือน (หาร 30)
  return '${(diff.inDays / 365).floor()} ปีที่แล้ว'; // เกินปี -> ปี
}

/// แถบหัวเรื่องสีครีมเหลืองทั้งแถบ ใช้ในกลุ่มหน้า "สแกนวัตถุดิบเข้าตู้เย็น"
/// (ถ่ายภาพวัตถุดิบ / ผลลัพธ์หลังสแกน) ต่างจาก [RecipeFlowHeader] ที่เป็นพื้นขาว
/// + ไอคอนค้นหา (ใช้ในฝั่งสแกนสูตรอาหาร) — โครงสร้างเดียวกันแต่สีต่างกันตาม Figma
class IngredientFlowHeader extends StatelessWidget {
  final String title; // ชื่อหน้า

  const IngredientFlowHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0), // [UI] ระยะรอบหัว
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () => Navigator.pop(context), // ปุ่มย้อนกลับ
            child: Container(
              height: 50, // [UI] ขนาดปุ่ม 50x50
              width: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีครีม
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Center(child: BackIcon(size: 24)), // [UI] ไอคอนย้อนกลับ ขนาด 24
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 50, // [UI] ความสูงแถบ
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D0), // [UI] สีแถบ
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center, // [UI] ชื่ออยู่กึ่งกลาง
                children: [
                  const ScannerIcon(size: 20), // [UI] ไอคอนสแกน ขนาด 20
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15, // [UI] ขนาดชื่อ
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// กล่องชื่อเมนู (พื้นขาว ตัวหนา ตรงกลาง) — ส่ง [onRename] มาจะมีไอคอนดินสอ
/// ให้แตะเพื่อเปลี่ยนชื่อ เช่น เมนูเดียวกันแต่มี 2 สูตร: "คั่วไก่ 1" / "คั่วไก่ 2"
class RecipeNameBox extends StatelessWidget {
  final String name; // ชื่อเมนู
  final VoidCallback? onRename; // กดเพื่อเปลี่ยนชื่อ (null = เปลี่ยนไม่ได้)

  const RecipeNameBox({super.key, required this.name, this.onRename});

  @override
  Widget build(BuildContext context) {
    final text = name.trim().isEmpty ? 'ไม่มีชื่อเมนู' : name.trim(); // ชื่อว่าง -> แสดง "ไม่มีชื่อเมนู"
    return Material(
      color: Colors.white, // [UI] พื้นขาว
      borderRadius: BorderRadius.circular(14), // [UI] มุมโค้ง 14
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onRename,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), // [UI] ระยะใน บนล่าง 12 ซ้ายขวา 16
          child: Row(
            children: [
              // เว้นที่ซ้ายเท่าไอคอนขวา ให้ชื่อยังอยู่ตรงกลาง
              if (onRename != null) const SizedBox(width: 22),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16, // [UI] ขนาดชื่อเมนู
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (onRename != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18, // [UI] ไอคอนดินสอ ขนาด 18
                    color: Colors.black54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// หน้าต่างเปลี่ยนชื่อเมนู คืนชื่อใหม่ (null = ยกเลิก/ไม่เปลี่ยน)
/// [isTaken] = เช็คว่าชื่อนี้ซ้ำกับสูตรอื่นในคลังไหม (ซ้ำ = เตือน แต่ยังใช้ได้)
Future<String?> showRenameRecipeDialog(
  BuildContext context, {
  required String currentName,
  bool Function(String name)? isTaken,
}) {
  final ctrl = TextEditingController(text: currentName.trim()); // ช่องกรอกชื่อ ใส่ชื่อเดิมไว้ก่อน
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length); // เลือกข้อความทั้งหมดไว้ พิมพ์ทับได้เลย
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final value = ctrl.text.trim(); // ชื่อที่พิมพ์
        final taken = value.isNotEmpty && (isTaken?.call(value) ?? false); // ชื่อนี้ซ้ำกับสูตรอื่นไหม
        void submit() { // กดบันทึก
          if (value.isEmpty) return; // ชื่อว่าง ไม่ทำอะไร
          Navigator.pop(ctx, value == currentName.trim() ? null : value); // ชื่อเดิม -> คืน null (ไม่เปลี่ยน)
        }

        return AlertDialog(
          title: const Text('เปลี่ยนชื่อเมนู'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true, // [UI] เปิดมาคีย์บอร์ดขึ้นทันที
                textInputAction: TextInputAction.done,
                onChanged: (_) => setLocal(() {}), // พิมพ์แล้ววาดใหม่ (อัปเดตข้อความเตือนชื่อซ้ำ)
                onSubmitted: (_) => submit(), // กด Enter = บันทึก
                decoration: const InputDecoration(hintText: 'เช่น คั่วไก่ 2'),
              ),
              const SizedBox(height: 8),
              Text(
                taken
                    ? 'มีสูตรชื่อนี้ในคลังแล้ว ลองเติมเลขต่อท้าย เช่น "$value 2"'
                    : 'เมนูเดียวกันมีหลายสูตร ตั้งชื่อให้ต่างกันได้ เช่น "คั่วไก่ 1", "คั่วไก่ 2"',
                style: TextStyle(
                  fontSize: 12,
                  color: taken ? Colors.orange.shade800 : Colors.grey.shade600, // [UI] ชื่อซ้ำ = ส้ม, ปกติ = เทา
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: value.isEmpty ? null : submit, // ชื่อว่าง = ปุ่มกดไม่ได้
              child: const Text('บันทึกชื่อ'),
            ),
          ],
        );
      },
    ),
  );
}

/// หัวข้อย่อย "เครื่องปรุงพื้นฐาน" ในรายการวัตถุดิบ — ซอส น้ำปลา น้ำตาล ฯลฯ
/// ที่ทุกบ้านน่าจะมี แสดงเป็นสีเทา และไม่นับในสถานะวัตถุดิบ
class StapleIngredientsHeader extends StatelessWidget {
  const StapleIngredientsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8), // [UI] ระยะบนล่าง
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'เครื่องปรุงพื้นฐาน',
              style: TextStyle(fontWeight: FontWeight.w600), // [UI] กึ่งหนา
            ),
            TextSpan(
              text: '  ·  ไม่นับในสถานะวัตถุดิบ',
              style: TextStyle(color: Colors.grey.shade500), // [UI] สีเทาจาง
            ),
          ],
        ),
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700), // [UI] ขนาด 13 สีเทา
      ),
    );
  }
}

/// บรรทัดข้อมูลสั้นๆ เช่น "สำหรับ 2 ที่" / "ใช้เวลาประมาณ 30 นาที"
/// [estimated] = AI ประมาณเอง (ในรูปไม่ได้เขียนไว้) -> มีป้าย "AI ประมาณ" ต่อท้าย
class RecipeInfoLine extends StatelessWidget {
  final IconData icon; // ไอคอนหน้าข้อความ
  final String text; // ข้อความ
  final bool estimated; // AI ประมาณเองไหม (แสดงป้ายแดง)

  const RecipeInfoLine({
    super.key,
    required this.icon,
    required this.text,
    this.estimated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black54), // [UI] ไอคอนขนาด 16 สีเทา
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black54), // [UI] ขนาด 13 สีเทา
          ),
        ),
        if (estimated) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), // [UI] ระยะในป้าย "AI ประมาณ"
            decoration: BoxDecoration(
              color: Colors.red.shade50, // [UI] พื้นแดงอ่อน
              borderRadius: BorderRadius.circular(6), // [UI] มุมโค้ง 6
              border: Border.all(color: Colors.red.shade200), // [UI] ขอบแดง
            ),
            child: Text(
              'AI ประมาณ',
              style: TextStyle(
                fontSize: 11, // [UI] ขนาด 11
                fontWeight: FontWeight.w600,
                color: Colors.red.shade400, // [UI] ตัวอักษรแดง
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "รูปที่ใช้สแกน" จากที่เก็บไฟล์ส่วนตัว — ขอลิงก์ชั่วคราวเอง แตะเพื่อดูเต็มจอ/ซูม
/// ไม่มีรูป หรือโหลดไม่สำเร็จ = ไม่แสดงอะไรเลย
class PrivateScanImage extends StatefulWidget {
  final String bucket; // ถังเก็บรูป
  final String? path; // ที่อยู่ไฟล์
  final double height; // [UI] ความสูงรูป

  const PrivateScanImage({
    super.key,
    required this.bucket,
    required this.path,
    this.height = 180, // [UI] ค่าเริ่มต้นสูง 180
  });

  @override
  State<PrivateScanImage> createState() => _PrivateScanImageState();
}

class _PrivateScanImageState extends State<PrivateScanImage> {
  // จำลิงก์ชั่วคราวไว้ (ใช้ได้ 1 ชม.) รูปย้ายตำแหน่ง/เปิดหน้าซ้ำจะได้ไม่โหลดใหม่
  static final _cache = <String, (String, DateTime)>{}; // แคชลิงก์: key -> (ลิงก์, เวลาหมดอายุ)

  String? _url; // ลิงก์รูปที่โหลดได้

  @override
  void initState() {
    super.initState();
    _load(); // เปิดมาโหลดลิงก์รูป
  }

  Future<void> _load() async {
    final path = widget.path; // ที่อยู่ไฟล์
    if (path == null || path.isEmpty) return; // ไม่มีรูป ไม่ต้องโหลด
    final key = '${widget.bucket}/$path';
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.$2)) { // มีในแคชและยังไม่หมดอายุ ใช้เลย
      _url = cached.$1;
      return;
    }
    final url = await privateImageUrl(widget.bucket, path); // ขอลิงก์ใหม่จาก Supabase
    if (url == null) return;
    _cache[key] = (url, DateTime.now().add(const Duration(minutes: 50))); // จำไว้ 50 นาที (ลิงก์จริงใช้ได้ 60 นาที)
    if (mounted) setState(() => _url = url);
  }

  // กดรูปแล้วเปิดเต็มจอ (ซูมได้)
  void _openFullScreen(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true, // เปิดแบบหน้าต่างเต็มจอ (มีปุ่ม X)
        builder: (_) => Scaffold(
          backgroundColor: Colors.black, // [UI] พื้นดำ
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: const CloseButton(color: Colors.white),
          ),
          body: Center(child: InteractiveViewer(child: Image.network(url))), // InteractiveViewer = ซูม/เลื่อนรูปได้
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return const SizedBox.shrink(); // ยังไม่มีลิงก์ ไม่แสดงอะไร
    return Padding(
      padding: const EdgeInsets.only(bottom: 20), // [UI] ระยะใต้รูป
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'รูปที่ใช้สแกน',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold, // [UI] ขนาดหัวข้อ
                color: Colors.black87,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openFullScreen(url), // กดรูปเปิดเต็มจอ
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16), // [UI] มุมรูปโค้ง 16
              child: Image.network(
                url,
                height: widget.height, // [UI] ความสูงรูป
                width: double.infinity, // [UI] กว้างเต็ม
                fit: BoxFit.cover, // [UI] ครอบตัดให้เต็มกรอบ (ไม่บิดสัดส่วน)
                errorBuilder: (_, _, _) => const SizedBox.shrink(), // โหลดรูปไม่ได้ ไม่แสดงอะไร
              ),
            ),
          ),
        ],
      ),
    );
  }
}
