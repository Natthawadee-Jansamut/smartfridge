import 'dart:async'; // Timer (ใช้กดค้างเพื่อเพิ่ม/ลดต่อเนื่อง)

import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:flutter/services.dart'; // ตัวกรองตัวอักษรในช่องกรอก

import 'package:test_app/widgets/app_icons.dart';

/// สีหลักของฟีเจอร์สูตรอาหาร (ตรงกับดีไซน์ใน Figma)
const kRecipeBg = Color(0xFFD8EEFF); // [UI] สีพื้นหลังทุกหน้าในกลุ่มสูตรอาหาร (ฟ้าอ่อน) แก้ที่นี่เปลี่ยนทุกหน้า
const kRecipeYellow = Color(0xFFFFF7D0); // [UI] สีเหลืองครีม (ป้าย/ปุ่ม)
const kRecipeYellowBorder = Color(0xFFF1DE8A); // [UI] สีขอบของป้ายเหลือง
const kRecipeBlue = Color(0xff5189C9); // [UI] สีฟ้าหลัก (วงหมุน/ขอบตอนพิมพ์)
const kRecipeLightBlue = Color(0xFFE3F2FD); // [UI] สีฟ้าอ่อน (ปุ่มบันทึก)

/// ข้อความเตือนบังคับ ทุกครั้งที่ AI สแกนหรือสร้างสูตรอาหาร
const kAiDisclaimerText = // [UI] ข้อความเตือน AI (แก้ข้อความได้ที่บรรทัดถัดไป)
    '⚠️ คำเตือน: สูตรอาหารนี้วิเคราะห์โดย AI โปรดตรวจสอบส่วนผสมและสุขอนามัยก่อนประกอบอาหาร';

// ---------------------------------------------------------------------------
// Bottom Sheet: เลือกวิธีเพิ่มสูตรอาหาร (เปิดจาก FAB ในหน้าคลังสูตร)
// ---------------------------------------------------------------------------

enum AddRecipeOption { scan, manual } // ตัวเลือก: สแกน / เขียนเอง

// เปิดแผ่นเลือกวิธีเพิ่มสูตร คืนตัวเลือกที่กด (null = ปิดไป)
Future<AddRecipeOption?> showAddRecipeSheet(BuildContext context) {
  return showModalBottomSheet<AddRecipeOption>(
    context: context,
    isScrollControlled: true, // [UI] ให้สูงได้เกินครึ่งจอ
    backgroundColor: Colors.transparent, // [UI] พื้นโปร่งใส (ใช้สีของกล่องข้างในแทน)
    builder: (_) => const _AddRecipeSheet(),
  );
}

class _AddRecipeSheet extends StatelessWidget {
  const _AddRecipeSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom; // ความสูงขีด Home ของ iPhone
    return Container(
      decoration: const BoxDecoration(
        color: kRecipeBg, // [UI] สีแผ่น
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)), // [UI] มุมบนโค้ง 28
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset), // [UI] ระยะในแผ่น (ล่างบวกขีด Home)
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, // [UI] ขีดเล็กด้านบน กว้าง 40
              height: 4, // [UI] สูง 4
              decoration: BoxDecoration(
                color: Colors.black26, // [UI] สีขีด
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'เพิ่มสูตรอาหาร',
            style: TextStyle(
              fontSize: 18, // [UI] ขนาดหัวข้อ
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'เลือกวิธีที่สะดวกสำหรับคุณ',
            style: TextStyle(fontSize: 13, color: Colors.black54), // [UI] คำอธิบาย ขนาด 13 สีเทา
          ),
          const SizedBox(height: 16),
          _SheetOption( // ตัวเลือก: สแกน
            icon: Icons.camera_alt_outlined,
            title: 'สแกนสูตรอาหาร',
            subtitle: 'ถ่ายภาพตำราหรือสูตรลายมือ ให้ AI อ่านสูตรให้',
            onTap: () => Navigator.pop(context, AddRecipeOption.scan), // เลือก -> ปิดแผ่นพร้อมส่งค่า scan
          ),
          const SizedBox(height: 12),
          _SheetOption( // ตัวเลือก: เขียนเอง
            icon: Icons.edit_note_rounded,
            title: 'เขียนสูตรเอง',
            subtitle: 'กรอกชื่อเมนู วัตถุดิบ และขั้นตอนด้วยตัวเอง',
            onTap: () => Navigator.pop(context, AddRecipeOption.manual), // เลือก -> ปิดแผ่นพร้อมส่งค่า manual
          ),
        ],
      ),
    );
  }
}

// การ์ดตัวเลือก 1 ใบในแผ่น
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white, // [UI] พื้นการ์ด
      elevation: 1, // [UI] เงาบาง
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: kRecipeBlue.withValues(alpha: 0.12), // [UI] สีคลื่นตอนกด
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
          child: Row(
            children: [
              Container(
                width: 52, // [UI] ขนาดวงกลมไอคอน
                height: 52,
                decoration: const BoxDecoration(
                  color: kRecipeBg, // [UI] สีวงกลม
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kRecipeBlue, size: 26), // [UI] ไอคอนสีฟ้า ขนาด 26
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16, // [UI] ขนาดหัวข้อ
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13, // [UI] ขนาดคำอธิบาย
                        color: Colors.black54,
                        height: 1.35, // [UI] ระยะบรรทัด
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38), // [UI] ลูกศรขวาสีเทาจาง
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// คำเตือน AI (แสดงทุกครั้งที่สูตรมาจาก AI)
// ---------------------------------------------------------------------------

// กล่องคำเตือน AI (สีส้มแดง)
class AiDisclaimerBanner extends StatelessWidget {
  const AiDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), // [UI] ระยะใน
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E6), // [UI] พื้นส้มอ่อน
        borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
        border: Border.all(color: const Color(0xFFE8590C), width: 1.5), // [UI] ขอบส้ม หนา 1.5
      ),
      child: const Text(
        kAiDisclaimerText,
        style: TextStyle(
          color: Color(0xFFC92A2A), // [UI] ตัวอักษรแดง
          fontWeight: FontWeight.w600,
          fontSize: 13.5, // [UI] ขนาด 13.5
          height: 1.45, // [UI] ระยะบรรทัด
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ขั้นตอนที่ AI คิดเพิ่ม (ตัวหนังสือสีแดง)
// ---------------------------------------------------------------------------

const kAiRed = Color(0xFFC92A2A); // [UI] สีแดงของขั้นตอนที่ AI แต่ง
const kAiRedBg = Color(0xFFFFF5F5); // [UI] สีพื้นแดงอ่อน

/// ข้อความอธิบายสีแดง แสดงเหนือรายการขั้นตอน เมื่อมีขั้นตอนที่ AI คิดเพิ่ม
class AiStepsNote extends StatelessWidget {
  final String text; // ข้อความอธิบาย (มีค่าเริ่มต้น)
  const AiStepsNote({
    super.key,
    this.text =
        'ข้อความสีแดง = ขั้นตอนที่ AI คิดเพิ่มให้ เพราะไม่พบในรูปสูตรอาหาร โปรดตรวจสอบก่อนทำ',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้กล่อง
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), // [UI] ระยะใน
      decoration: BoxDecoration(
        color: kAiRedBg,
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: kAiRed), // [UI] ไอคอนประกาย ขนาด 16
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: kAiRed,
                fontSize: 12.5, // [UI] ขนาดตัวอักษร
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ป้ายเล็ก "AI" สีแดง ต่อท้ายขั้นตอนที่ AI คิดเพิ่ม
class AiChip extends StatelessWidget {
  const AiChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), // [UI] ระยะในป้าย
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8), // [UI] มุมโค้ง 8
        border: Border.all(color: kAiRed), // [UI] ขอบแดง
      ),
      child: const Text(
        'AI',
        style: TextStyle(
          color: kAiRed,
          fontSize: 10, // [UI] ขนาดตัวอักษร "AI"
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// รายการขั้นตอนการทำแบบอ่านอย่างเดียว ขั้นตอนที่ AI คิดเพิ่มเป็นสีแดง + ป้าย AI
/// ใช้ได้ทั้งหน้าผลสแกนและหน้ารายละเอียดสูตร:
///   RecipeStepsView(
///     steps: RecipeRepository.stepTextsOf(recipe),
///     aiIndexes: RecipeRepository.aiStepIndexesOf(recipe),
///   )
class RecipeStepsView extends StatelessWidget {
  final List<String> steps; // ขั้นตอนทั้งหมด
  final Set<int> aiIndexes; // ตำแหน่งขั้นที่ AI แต่ง
  final double fontSize; // [UI] ขนาดตัวอักษร
  final double spacing; // [UI] ระยะห่างระหว่างขั้น

  const RecipeStepsView({
    super.key,
    required this.steps,
    this.aiIndexes = const {},
    this.fontSize = 14, // [UI] ค่าเริ่มต้นขนาด 14
    this.spacing = 8, // [UI] ค่าเริ่มต้นระยะ 8
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aiIndexes.isNotEmpty) const AiStepsNote(), // มีขั้นที่ AI แต่ง -> แสดงคำอธิบายด้านบน
        for (var i = 0; i < steps.length; i++) // ไล่ทีละขั้น
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: spacing), // [UI] เยื้องซ้าย 8
            child: Text.rich(
              TextSpan(
                text: '${i + 1}. ${steps[i]}', // "1. ข้อความ"
                children: [
                  if (aiIndexes.contains(i)) ...[ // ขั้นที่ AI แต่ง -> ต่อท้ายด้วยป้าย AI
                    const TextSpan(text: '  '),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: AiChip(),
                    ),
                  ],
                ],
              ),
              style: TextStyle(
                fontSize: fontSize,
                height: 1.5, // [UI] ระยะบรรทัด
                color: aiIndexes.contains(i) ? kAiRed : Colors.black87, // [UI] ขั้นที่ AI แต่ง = แดง, ปกติ = ดำ
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ชิ้นส่วน UI ที่ใช้ซ้ำในหน้าสูตรอาหาร
// ---------------------------------------------------------------------------

/// กล่องสีขาวมุมโค้ง + เงาบางๆ (การ์ดหลักของทุกหน้าในฟีเจอร์นี้)
class RecipeSectionCard extends StatelessWidget {
  final Widget child; // เนื้อหาในการ์ด
  final EdgeInsetsGeometry padding; // ระยะใน

  const RecipeSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16), // [UI] ค่าเริ่มต้นระยะใน 16
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นขาว
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)), // [UI] เงา ความฟุ้ง 5 เลื่อนลง 2
        ],
      ),
      child: child,
    );
  }
}

/// ป้ายหัวข้อทรงแคปซูลสีเหลือง เช่น "วัตถุดิบที่ต้องใช้"
class SectionPill extends StatelessWidget {
  final String text;
  const SectionPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), // [UI] ระยะในป้าย
      decoration: BoxDecoration(
        color: kRecipeYellow, // [UI] สีป้าย
        borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
        border: Border.all(color: kRecipeYellowBorder), // [UI] ขอบเหลือง
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14, // [UI] ขนาดตัวอักษร
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// ปุ่ม "แก้ไข" ทรงแคปซูลสีเหลือง (กดได้จริง)
class EditPill extends StatelessWidget {
  final VoidCallback onTap; // กดแล้วทำอะไร
  final String label; // ข้อความบนปุ่ม
  const EditPill({super.key, required this.onTap, this.label = 'แก้ไข'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kRecipeYellow, // [UI] สีปุ่ม
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
        side: const BorderSide(color: kRecipeYellowBorder), // [UI] ขอบเหลือง
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // [UI] ระยะในปุ่ม
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13, // [UI] ขนาดตัวอักษร
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

/// แถบปุ่มล่าง 2 ปุ่ม: ปุ่มเทา (สแกนใหม่/ยกเลิก) + ปุ่มฟ้า (✓ บันทึกสูตร)
class RecipeBottomActions extends StatelessWidget {
  final String secondaryLabel; // ข้อความปุ่มซ้าย
  final VoidCallback onSecondary; // กดปุ่มซ้าย
  final String primaryLabel; // ข้อความปุ่มขวา
  final VoidCallback onPrimary; // กดปุ่มขวา
  final bool isLoading; // กำลังโหลด (ปุ่มขวาจะหมุน)

  const RecipeBottomActions({
    super.key,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12), // [UI] มุมปุ่มโค้ง 12
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10), // [UI] ระยะรอบแถบ
      padding: const EdgeInsets.all(12), // [UI] ระยะในแถบ
      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นขาว
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)), // [UI] เงา ความฟุ้ง 8
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50, // [UI] ความสูงปุ่ม
              child: ElevatedButton(
                onPressed: isLoading ? null : onSecondary, // กำลังโหลด = กดไม่ได้
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFADADAD), // [UI] ปุ่มซ้ายสีเทา
                  foregroundColor: Colors.black87,
                  elevation: 0, // [UI] ไม่มีเงา
                  shape: shape,
                ),
                child: Text(
                  secondaryLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15, // [UI] ขนาดตัวอักษร
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12), // [UI] ระยะระหว่างปุ่ม
          Expanded(
            child: SizedBox(
              height: 50, // [UI] ความสูงปุ่ม
              child: ElevatedButton(
                onPressed: isLoading ? null : onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRecipeLightBlue, // [UI] ปุ่มขวาสีฟ้าอ่อน
                  foregroundColor: Colors.black87,
                  disabledBackgroundColor: kRecipeLightBlue, // [UI] สีเดิมแม้กดไม่ได้
                  elevation: 0,
                  shape: shape,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22, // [UI] ขนาดวงหมุน
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5, // [UI] ความหนาวงหมุน
                          color: kRecipeBlue,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CheckIcon(size: 18), // [UI] ไอคอนติ๊ก ขนาด 18
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              primaryLabel,
                              overflow: TextOverflow.ellipsis, // [UI] ยาวเกินตัดเป็น ...
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15, // [UI] ขนาดตัวอักษร
                              ),
                            ),
                          ),
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

/// หน้าต่างโหลดแบบกดปิดไม่ได้ ระหว่างรอ AI
/// คืนค่าฟังก์ชันสำหรับปิด (ปลอดภัยแม้หน้าจอที่เรียกจะถูกปิดไปก่อนแล้ว)
VoidCallback showBlockingLoader(BuildContext context, String message) {
  final navigator = Navigator.of(context, rootNavigator: true); // ตัวนำทางระดับบนสุด
  var isOpen = true; // ป๊อปอัปยังเปิดอยู่ไหม
  showDialog<void>(
    context: context,
    useRootNavigator: true, // ใช้ตัวนำทางระดับบนสุด
    barrierDismissible: false, // [UI] แตะข้างนอกปิดไม่ได้
    builder: (_) => PopScope(
      canPop: false, // กดย้อนกลับปิดไม่ได้
      child: Center(
        child: Material(
          color: Colors.white, // [UI] กล่องขาว
          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24), // [UI] ระยะในกล่อง
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: kRecipeBlue), // [UI] วงหมุนสีฟ้า
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black87), // [UI] ขนาดข้อความ
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return () { // คืนฟังก์ชันปิดป๊อปอัป (ปิดได้ครั้งเดียว)
    if (isOpen) {
      isOpen = false;
      navigator.pop();
    }
  };
}

// ---------------------------------------------------------------------------
// หน่วยครัว + ปุ่มบวก/ลบตัวเลข (กันผู้ใช้พิมพ์ตัวหนังสือลงช่องตัวเลข)
// ---------------------------------------------------------------------------

/// หน่วยครัวที่เลือกได้ — รองรับทั้งน้ำหนัก, ช้อน/ถ้วย, นับชิ้น/ส่วน
/// และ "%" สำหรับกะด้วยสายตา (เช่น ใช้นม 50% ของขวด)
const kRecipeUnits = <String>[ // [UI] รายการหน่วยให้เลือกในดรอปดาวน์ (เพิ่ม/ลบได้)
  'กรัม',
  'กิโลกรัม',
  'มิลลิลิตร',
  'ลิตร',
  'ช้อนโต๊ะ',
  'ช้อนชา',
  'ถ้วย',
  'ฟอง',
  'ชิ้น',
  'ลูก',
  'แผ่น',
  'หัว',
  'กลีบ',
  'เม็ด',
  'ต้น',
  'กำ',
  'แพ็ค',
  'ส่วน',
  '%',
];

/// กดบวก/ลบครั้งละเท่าไหร่ ตามหน่วย
/// เช่น กรัม +10, ช้อนโต๊ะ +0.5, ฟอง +1, หัวกะหล่ำ +0.5 (ครึ่งหัว)
num stepForUnit(String? unit) {
  switch ((unit ?? '').trim()) { // เลือกตามหน่วย
    case 'กรัม':
    case 'มิลลิลิตร':
    case '%':
      return 10; // [UI] กรัม/มล./% กดทีละ 10
    case 'กิโลกรัม':
    case 'ลิตร':
      return 0.25; // [UI] กิโล/ลิตร กดทีละ 0.25
    case 'ช้อนโต๊ะ':
    case 'ช้อนชา':
    case 'ถ้วย':
    case 'ลูก':
    case 'หัว':
    case 'แพ็ค':
    case 'ส่วน':
      return 0.5; // [UI] ช้อน/ถ้วย/ลูก/หัว ฯลฯ กดทีละ 0.5
    default: // ฟอง ชิ้น กลีบ เม็ด ต้น กำ และหน่วยอื่นๆ
      return 1; // [UI] นอกนั้นกดทีละ 1
  }
}

/// ค่าสูงสุดตามหน่วย (% ไม่เกิน 100)
num maxForUnit(String? unit) => (unit ?? '').trim() == '%' ? 100 : 9999;

/// ปุ่ม [−] ค่า [+] สำหรับค่าตัวเลขทุกช่อง (จำนวนวัตถุดิบ, เวลาทำ, จำนวนที่)
/// - ค่า 0 / null แสดงเป็น [emptyLabel] และถือว่า "ไม่ได้ระบุ"
/// - กดค้างเพื่อเพิ่ม/ลดต่อเนื่อง
/// - แตะที่ตัวเลขตรงกลางเพื่อพิมพ์ค่าเองได้เลย (เช่น 250 กรัม ไม่ต้องกด + ทีละขั้น)
class NumberStepper extends StatefulWidget {
  final num? value; // ค่าปัจจุบัน
  final ValueChanged<num?> onChanged; // ส่งค่าใหม่กลับเมื่อเปลี่ยน
  final num step; // เพิ่ม/ลดทีละเท่าไหร่
  final num min; // ค่าต่ำสุด
  final num max; // ค่าสูงสุด
  final String? suffix; // หน่วยต่อท้าย
  final String emptyLabel; // ข้อความตอนไม่มีค่า
  final bool compact; // [UI] true = ขนาดเล็ก

  const NumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.max = 9999,
    this.suffix,
    this.emptyLabel = '—',
    this.compact = false,
  });

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  Timer? _repeat; // ตัวจับเวลาตอนกดค้าง
  num? _current; // ค่าระหว่างกดค้าง

  // โหมดพิมพ์ตัวเลขเอง
  bool _typing = false; // กำลังพิมพ์ตัวเลขเองอยู่ไหม
  final _textCtrl = TextEditingController(); // ช่องพิมพ์
  final _focus = FocusNode(); // โฟกัสของช่องพิมพ์

  @override
  void initState() {
    super.initState();
    // แตะที่อื่น/ปิดคีย์บอร์ด = ยืนยันค่าที่พิมพ์
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commitTyped(); // เสียโฟกัสระหว่างพิมพ์ = ยืนยันค่า
    });
  }

  String _plain(num v) => // แสดงตัวเลข: จำนวนเต็มไม่มีทศนิยม
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // แตะตัวเลข -> เข้าโหมดพิมพ์ (เลือกข้อความทั้งหมดไว้)
  void _startTyping() {
    setState(() {
      _typing = true;
      _textCtrl.text = _v == 0 ? '' : _plain(_v);
      _textCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textCtrl.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus(); // เปิดคีย์บอร์ด
    });
  }

  // ยืนยันค่าที่พิมพ์
  void _commitTyped() {
    final raw = _textCtrl.text.trim().replaceAll(',', '.'); // เปลี่ยนลูกน้ำเป็นจุด
    setState(() => _typing = false); // ออกจากโหมดพิมพ์
    if (raw.isEmpty) {
      // ลบจนว่าง = ไม่ระบุ
      if (_v != 0) widget.onChanged(null);
      return;
    }
    final parsed = num.tryParse(raw);
    if (parsed == null) return; // พิมพ์ไม่ใช่ตัวเลข -> คงค่าเดิม
    final clamped = parsed.clamp(widget.min, widget.max); // บีบให้อยู่ในช่วง min-max
    final clean = double.parse(clamped.toStringAsFixed(2)); // ทศนิยมไม่เกิน 2 ตำแหน่ง
    final value = clean == clean.roundToDouble() ? clean.toInt() : clean;
    if (value == _v) return;
    widget.onChanged(value == 0 ? null : value); // ส่งค่ากลับ (0 = ไม่ระบุ)
  }

  num get _v => _current ?? widget.value ?? 0; // ค่าที่ใช้แสดง (ระหว่างกดค้าง > ค่าที่ส่งมา > 0)

  @override
  void didUpdateWidget(covariant NumberStepper old) {
    super.didUpdateWidget(old);
    if (_repeat == null) _current = null; // ไม่ได้กดค้างอยู่ = ใช้ค่าที่ส่งมา
  }

  @override
  void dispose() {
    _repeat?.cancel(); // หยุดตัวจับเวลา
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // กด + (dir = 1) หรือ − (dir = -1) 1 ครั้ง
  void _bump(int dir) {
    if (_typing) _commitTyped();
    // ปัดให้ตรงจังหวะ step เสมอ (กันเลขทศนิยมเพี้ยน เช่น 0.30000000004)
    final raw = _v + dir * widget.step;
    final snapped = (raw / widget.step).round() * widget.step;
    final next = snapped.clamp(widget.min, widget.max); // บีบให้อยู่ในช่วง
    final clean = double.parse(next.toStringAsFixed(2));
    final value = clean == clean.roundToDouble() ? clean.toInt() : clean;
    if (value == _v) return; // ไม่เปลี่ยน ไม่ต้องทำอะไร
    _current = value;
    widget.onChanged(value == 0 ? null : value);
  }

  // เริ่มกดค้าง -> เพิ่ม/ลดซ้ำเรื่อยๆ
  void _startRepeat(int dir) {
    _repeat?.cancel();
    _repeat = Timer.periodic(
      const Duration(milliseconds: 110), // [UI] เร็วแค่ไหนตอนกดค้าง (มิลลิวินาที น้อย = เร็ว)
      (_) => _bump(dir),
    );
  }

  // ปล่อยนิ้ว -> หยุด
  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
    _current = null;
  }

  // ข้อความที่แสดง เช่น "250 กรัม" (0 = ข้อความว่าง)
  String _label() {
    final v = _v;
    if (v == 0) return widget.emptyLabel;
    final n = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return widget.suffix == null ? n : '$n ${widget.suffix}';
  }

  // ปุ่มกลม − / +
  Widget _button(IconData icon, int dir, bool enabled) {
    final size = widget.compact ? 30.0 : 36.0; // [UI] ขนาดปุ่ม: เล็ก 30 / ปกติ 36
    return GestureDetector(
      onLongPressStart: enabled ? (_) => _startRepeat(dir) : null, // เริ่มกดค้าง
      onLongPressEnd: enabled ? (_) => _stopRepeat() : null, // ปล่อยนิ้ว
      onLongPressCancel: _stopRepeat,
      child: Material(
        color: enabled ? kRecipeYellow : Colors.grey.shade200, // [UI] กดได้ = เหลือง, กดไม่ได้ = เทา
        shape: const CircleBorder(), // [UI] ทรงกลม
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _bump(dir) : null, // แตะ 1 ครั้ง
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: widget.compact ? 18 : 20, // [UI] ขนาดไอคอน: เล็ก 18 / ปกติ 20
              color: enabled ? Colors.black87 : Colors.black26, // [UI] สีไอคอน
            ),
          ),
        ),
      ),
    );
  }

  /// ค่าตรงกลาง (มีกรอบบางๆ ให้รู้ว่าแตะเพื่อพิมพ์ได้)
  Widget _tapToType(num v) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _startTyping, // แตะ -> เข้าโหมดพิมพ์
      child: Container(
        constraints: BoxConstraints(minWidth: widget.compact ? 52 : 70), // [UI] กว้างอย่างน้อย: เล็ก 52 / ปกติ 70
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), // [UI] ระยะใน
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), // [UI] มุมโค้ง 8
          border: Border.all(color: Colors.grey.shade300), // [UI] ขอบเทาอ่อน
        ),
        child: Text(
          _label(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.compact ? 13 : 14, // [UI] ขนาดตัวอักษร
            fontWeight: FontWeight.w600,
            color: v == 0 ? Colors.black38 : Colors.black87, // [UI] ไม่มีค่า = เทาจาง
          ),
        ),
      ),
    );
  }

  /// ช่องพิมพ์ตัวเลข (แสดงตอนแตะที่ค่า)
  Widget _typingField() {
    return SizedBox(
      width: widget.compact ? 64 : 84, // [UI] ความกว้างช่องพิมพ์
      child: TextField(
        controller: _textCtrl,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true), // [UI] แป้นตัวเลขมีจุดทศนิยม
        textInputAction: TextInputAction.done, // [UI] ปุ่มคีย์บอร์ด = เสร็จ
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ], // พิมพ์ได้แค่ตัวเลข จุด ลูกน้ำ
        onSubmitted: (_) => _focus.unfocus(), // กดเสร็จ = ปิดคีย์บอร์ด (แล้วยืนยันค่า)
        style: TextStyle(
          fontSize: widget.compact ? 13 : 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 8,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: kRecipeBlue, width: 1.5), // [UI] ขอบฟ้าตอนพิมพ์
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.remove_rounded, -1, v > widget.min), // ปุ่ม − (ถึงค่าต่ำสุดแล้วกดไม่ได้)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4), // [UI] ระยะซ้ายขวาของค่าตรงกลาง
          child: _typing ? _typingField() : _tapToType(v), // กำลังพิมพ์ = ช่องพิมพ์, ไม่งั้น = ค่าที่แตะได้
        ),
        _button(Icons.add_rounded, 1, v < widget.max), // ปุ่ม + (ถึงค่าสูงสุดแล้วกดไม่ได้)
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// รูปสูตรที่ผู้ใช้อัปโหลด (ให้เทียบว่า AI อ่านถูกไหม) — แตะเพื่อขยาย/ซูม
// ---------------------------------------------------------------------------

class ScannedImagePreview extends StatelessWidget {
  final Uint8List bytes; // ไฟล์รูป
  final double height; // [UI] ความสูงรูป

  const ScannedImagePreview({
    super.key,
    required this.bytes,
    this.height = 200, // [UI] ค่าเริ่มต้นสูง 200
  });

  // แตะรูป -> เปิดเต็มจอ
  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImage(bytes: bytes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'รูปสูตรที่คุณอัปโหลด',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14, // [UI] ขนาดหัวข้อ
              color: Colors.black87,
            ),
          ),
        ),
        Material(
          color: Colors.white, // [UI] พื้นขาว
          borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
          clipBehavior: Clip.antiAlias, // ตัดรูปให้โค้งตามมุม
          child: InkWell(
            onTap: () => _openFullScreen(context),
            child: Stack(
              children: [
                Container(
                  height: height, // [UI] ความสูงรูป
                  width: double.infinity,
                  color: const Color(0xFFF3F6FA), // [UI] สีพื้นหลังรูป
                  child: Image.memory(bytes, fit: BoxFit.contain), // [UI] แสดงรูปทั้งรูปไม่ครอบตัด
                ),
                Positioned(
                  right: 10, // [UI] ป้าย "แตะเพื่อขยาย" มุมขวาล่าง
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54, // [UI] พื้นดำจาง
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.zoom_in_rounded,
                          size: 16, // [UI] ไอคอนแว่นขยาย ขนาด 16
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'แตะเพื่อขยาย',
                          style: TextStyle(color: Colors.white, fontSize: 12), // [UI] ข้อความขาว ขนาด 12
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 6),
          child: Text(
            'เทียบกับข้อมูลด้านล่างว่า AI อ่านถูกต้องหรือไม่',
            style: TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
          ),
        ),
      ],
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  final Uint8List bytes;
  const _FullScreenImage({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // [UI] พื้นดำ
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // ไม่ใส่ปุ่มย้อนกลับอัตโนมัติ
        // ธีมหลักของแอป (main.dart) ตั้งไอคอน AppBar เป็นสีดำ
        // บนพื้นดำจะมองไม่เห็น -> บังคับเป็นสีขาวที่หน้านี้
        iconTheme: const IconThemeData(color: Colors.white),
        // ปุ่มปิด (X) ออกจากหน้าดูรูปเต็มจอ
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28), // [UI] ปุ่ม X สีขาว ขนาด 28
          tooltip: 'ปิด',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('รูปสูตรที่อัปโหลด', style: TextStyle(fontSize: 16)), // [UI] ขนาดหัวข้อ
      ),
      body: InteractiveViewer( // ซูม/เลื่อนรูปได้
        minScale: 1, // ซูมออกต่ำสุด 1 เท่า
        maxScale: 5, // [UI] ซูมเข้าได้สูงสุด 5 เท่า
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// แถวแก้ไขวัตถุดิบ / ขั้นตอน (ใช้ร่วมกัน: หน้าเขียนสูตร + หน้ารายละเอียดสูตร)
// ---------------------------------------------------------------------------

// ตกแต่งช่องกรอกในฟอร์มสูตร (ขั้นตอนของ AI จะเป็นสีแดง)
InputDecoration recipeBoxDecoration(
  String hint, {
  Widget? prefix,
  Widget? suffix,
  bool isAi = false,
}) {
  final radius = BorderRadius.circular(10); // [UI] มุมโค้ง 10
  return InputDecoration(
    isDense: true, // [UI] แบบกระชับ
    filled: isAi, // ขั้นของ AI = มีสีพื้น
    fillColor: isAi ? kAiRedBg : null, // [UI] พื้นแดงอ่อน
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500), // [UI] สีข้อความจาง
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // [UI] ระยะใน
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: isAi ? kAiRed.withValues(alpha: 0.5) : Colors.grey.shade400, // [UI] ขอบปกติ: AI = แดงจาง, ปกติ = เทา
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: isAi ? kAiRed : kRecipeBlue, width: 1.5), // [UI] ขอบตอนพิมพ์: AI = แดง, ปกติ = ฟ้า
    ),
  );
}

// ปุ่ม X ลบแถว (null = ไม่แสดงปุ่ม)
Widget _removeIcon(VoidCallback? onTap) => SizedBox(
  width: 28, // [UI] ช่องกว้าง 28
  child: onTap == null
      ? null
      : IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: 'ลบ',
          icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500), // [UI] ไอคอน X ขนาด 18 สีเทา
          onPressed: onTap,
        ),
);

/// บรรทัด "ชื่อ ........ [−] ค่า [+]" เช่น เวลาทำ / จำนวนที่
class StepperLine extends StatelessWidget {
  final String label;
  final Widget stepper;
  const StepperLine({super.key, required this.label, required this.stepper});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4), // [UI] ระยะบนล่าง
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14, // [UI] ขนาดชื่อ
                fontWeight: FontWeight.w600, // [UI] กึ่งหนา
                color: Colors.black87,
              ),
            ),
          ),
          stepper,
        ],
      ),
    );
  }
}

/// แถวแก้ไขวัตถุดิบ 2 บรรทัด:
///   [เลข] [ชื่อวัตถุดิบ.........] [x]
///         [−] จำนวน [+]  [หน่วย ▾]
/// จำนวนปรับได้ด้วยปุ่ม +/− เท่านั้น (พิมพ์ตัวหนังสือไม่ได้)
class IngredientEditRow extends StatelessWidget {
  final int index; // ลำดับแถว (เริ่ม 0)
  final TextEditingController nameController; // ช่องชื่อวัตถุดิบ
  final num? qty; // จำนวน
  final String? unit; // หน่วย
  final ValueChanged<num?> onQtyChanged; // เปลี่ยนจำนวน
  final ValueChanged<String?> onUnitChanged; // เปลี่ยนหน่วย
  final VoidCallback? onRemove; // ลบแถว (null = ลบไม่ได้)

  const IngredientEditRow({
    super.key,
    required this.index,
    required this.nameController,
    required this.qty,
    required this.unit,
    required this.onQtyChanged,
    required this.onUnitChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final units = <String>{ // รายการหน่วย + หน่วยปัจจุบัน (ถ้าไม่อยู่ในรายการ)
      ...kRecipeUnits,
      if (unit != null && unit!.isNotEmpty) unit!,
    }.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8), // [UI] ระยะใต้แถว
      padding: const EdgeInsets.fromLTRB(8, 8, 2, 8), // [UI] ระยะใน
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
        border: Border.all(color: Colors.grey.shade300), // [UI] ขอบเทาอ่อน
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 18, // [UI] ช่องเลขลำดับกว้าง 18
                child: Text(
                  '${index + 1}', // เลขลำดับ (เริ่มที่ 1)
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next, // [UI] ปุ่มคีย์บอร์ด = ถัดไป
                  style: const TextStyle(fontSize: 13), // [UI] ขนาดตัวอักษร
                  decoration: recipeBoxDecoration('ชื่อวัตถุดิบ'),
                ),
              ),
              _removeIcon(onRemove),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 28), // [UI] เยื้องให้ตรงกับช่องชื่อ
            child: Row(
              children: [
                NumberStepper(
                  value: qty,
                  step: stepForUnit(unit), // ทีละเท่าไหร่ตามหน่วย
                  max: maxForUnit(unit), // ค่าสูงสุดตามหน่วย
                  compact: true, // [UI] ปุ่มขนาดเล็ก
                  onChanged: onQtyChanged,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 38, // [UI] ความสูงดรอปดาวน์หน่วย
                    padding: const EdgeInsets.only(left: 8, right: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
                      border: Border.all(color: Colors.grey.shade400), // [UI] ขอบเทา
                    ),
                    child: DropdownButtonHideUnderline( // ซ่อนเส้นใต้ของดรอปดาวน์
                      child: DropdownButton<String>(
                        value: (unit == null || unit!.isEmpty) ? null : unit,
                        isExpanded: true, // [UI] กว้างเต็มช่อง
                        isDense: true,
                        hint: Text(
                          'หน่วย',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        menuMaxHeight: 320, // [UI] ความสูงรายการสูงสุด (เลื่อนได้)
                        items: units
                            .map(
                              (u) => DropdownMenuItem(
                                value: u,
                                child: Text(u, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: onUnitChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ช่องแก้ไขขั้นตอน 1 ข้อ (ขั้นตอนที่ AI คิดเพิ่ม = ตัวหนังสือสีแดง + ป้าย AI)
class StepEditRow extends StatelessWidget {
  final int index;
  final TextEditingController controller; // ช่องข้อความขั้นตอน
  final bool isAi; // เป็นขั้นที่ AI แต่งไหม
  final VoidCallback? onRemove; // ลบแถว (null = ลบไม่ได้)

  const StepEditRow({
    super.key,
    required this.index,
    required this.controller,
    this.isAi = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = isAi ? kAiRed : Colors.black87; // [UI] สีตัวอักษร: AI = แดง, ปกติ = ดำ
    return Padding(
      padding: const EdgeInsets.only(bottom: 8), // [UI] ระยะใต้แถว
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1, // [UI] สูงอย่างน้อย 1 บรรทัด
              maxLines: 4, // [UI] สูงสุด 4 บรรทัด (เกินเลื่อนในช่อง)
              textInputAction: TextInputAction.newline, // [UI] ปุ่มคีย์บอร์ด = ขึ้นบรรทัดใหม่
              style: TextStyle(fontSize: 13, height: 1.4, color: color), // [UI] ขนาดตัวอักษร
              decoration: recipeBoxDecoration(
                'อธิบายขั้นตอน',
                isAi: isAi,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Text(
                    '${index + 1}.', // เลขข้อหน้าช่อง
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                suffix: isAi // ขั้นของ AI -> ป้าย AI ท้ายช่อง
                    ? const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: AiChip(),
                      )
                    : null,
              ),
            ),
          ),
          _removeIcon(onRemove),
        ],
      ),
    );
  }
}
