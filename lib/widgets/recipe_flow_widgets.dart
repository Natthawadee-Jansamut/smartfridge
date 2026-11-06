import 'package:flutter/material.dart';

import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/screens/recipe_scan/recipe_search_screen.dart';
import 'package:test_app/services/fridge_images.dart';

/// วิดเจ็ตที่ใช้ร่วมกันในกลุ่มหน้า "สแกนสูตรอาหาร" ทั้ง 3 หน้า
/// (คลังสูตรอาหาร / สแกนสูตรอาหาร / ผลการสแกนสูตรอาหาร)
/// เพื่อให้ดีไซน์ตรงกับ Figma แบบเดียวกันทุกหน้า และแก้ที่เดียวจบ

/// แถบหัวเรื่องแบบ "ช่องค้นหา" (ปุ่มย้อนกลับ + แคปซูลไอคอนสแกน/ชื่อหน้า/ไอคอนค้นหา + ปุ่มตัวกรองวงกลม)
class RecipeFlowHeader extends StatelessWidget {
  final String title;

  /// กดช่องค้นหา — ไม่ส่งมา = เปิดหน้าค้นหาสูตรอาหาร
  final VoidCallback? onSearchTap;

  const RecipeFlowHeader({super.key, required this.title, this.onSearchTap});

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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openSearch(context),
              // สีเดียวกับแถบหัวข้อของหน้าอื่นๆ ในแอป (เหลืองอ่อน)
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7D0),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  children: [
                    const ScannerIcon(size: 22),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xff5189C9)),
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
/// (ถ่ายภาพวัตถุดิบ / ผลลัพธ์หลังสแกน) ต่างจาก [RecipeFlowHeader] ที่เป็นพื้นขาว
/// + ไอคอนค้นหา (ใช้ในฝั่งสแกนสูตรอาหาร) — โครงสร้างเดียวกันแต่สีต่างกันตาม Figma
class IngredientFlowHeader extends StatelessWidget {
  final String title;

  const IngredientFlowHeader({super.key, required this.title});

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
        ],
      ),
    );
  }
}

/// กล่องชื่อเมนู (พื้นขาว ตัวหนา ตรงกลาง) — ส่ง [onRename] มาจะมีไอคอนดินสอ
/// ให้แตะเพื่อเปลี่ยนชื่อ เช่น เมนูเดียวกันแต่มี 2 สูตร: "คั่วไก่ 1" / "คั่วไก่ 2"
class RecipeNameBox extends StatelessWidget {
  final String name;
  final VoidCallback? onRename;

  const RecipeNameBox({super.key, required this.name, this.onRename});

  @override
  Widget build(BuildContext context) {
    final text = name.trim().isEmpty ? 'ไม่มีชื่อเมนู' : name.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onRename,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              // เว้นที่ซ้ายเท่าไอคอนขวา ให้ชื่อยังอยู่ตรงกลาง
              if (onRename != null) const SizedBox(width: 22),
              Expanded(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
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
                    size: 18,
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
  final ctrl = TextEditingController(text: currentName.trim());
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final value = ctrl.text.trim();
        final taken = value.isNotEmpty && (isTaken?.call(value) ?? false);
        void submit() {
          if (value.isEmpty) return;
          Navigator.pop(ctx, value == currentName.trim() ? null : value);
        }

        return AlertDialog(
          title: const Text('เปลี่ยนชื่อเมนู'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setLocal(() {}),
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(hintText: 'เช่น คั่วไก่ 2'),
              ),
              const SizedBox(height: 8),
              Text(
                taken
                    ? 'มีสูตรชื่อนี้ในคลังแล้ว ลองเติมเลขต่อท้าย เช่น "$value 2"'
                    : 'เมนูเดียวกันมีหลายสูตร ตั้งชื่อให้ต่างกันได้ เช่น "คั่วไก่ 1", "คั่วไก่ 2"',
                style: TextStyle(
                  fontSize: 12,
                  color: taken ? Colors.orange.shade800 : Colors.grey.shade600,
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
              onPressed: value.isEmpty ? null : submit,
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
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'เครื่องปรุงพื้นฐาน',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: '  ·  ไม่นับในสถานะวัตถุดิบ',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
      ),
    );
  }
}

/// บรรทัดข้อมูลสั้นๆ เช่น "สำหรับ 2 ที่" / "ใช้เวลาประมาณ 30 นาที"
/// [estimated] = AI ประมาณเอง (ในรูปไม่ได้เขียนไว้) -> มีป้าย "AI ประมาณ" ต่อท้าย
class RecipeInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool estimated;

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
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
        if (estimated) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'AI ประมาณ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade400,
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
  final String bucket;
  final String? path;
  final double height;

  const PrivateScanImage({
    super.key,
    required this.bucket,
    required this.path,
    this.height = 180,
  });

  @override
  State<PrivateScanImage> createState() => _PrivateScanImageState();
}

class _PrivateScanImageState extends State<PrivateScanImage> {
  // จำลิงก์ชั่วคราวไว้ (ใช้ได้ 1 ชม.) รูปย้ายตำแหน่ง/เปิดหน้าซ้ำจะได้ไม่โหลดใหม่
  static final _cache = <String, (String, DateTime)>{};

  String? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null || path.isEmpty) return;
    final key = '${widget.bucket}/$path';
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      _url = cached.$1;
      return;
    }
    final url = await privateImageUrl(widget.bucket, path);
    if (url == null) return;
    _cache[key] = (url, DateTime.now().add(const Duration(minutes: 50)));
    if (mounted) setState(() => _url = url);
  }

  void _openFullScreen(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: const CloseButton(color: Colors.white),
          ),
          body: Center(child: InteractiveViewer(child: Image.network(url))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'รูปที่ใช้สแกน',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openFullScreen(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                height: widget.height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
