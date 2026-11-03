import 'package:flutter/material.dart';

import 'package:test_app/widgets/app_icons.dart';

/// สีหลักของฟีเจอร์สูตรอาหาร (ตรงกับดีไซน์ใน Figma)
const kRecipeBg = Color(0xFFD8EEFF);
const kRecipeYellow = Color(0xFFFFF7D0);
const kRecipeYellowBorder = Color(0xFFF1DE8A);
const kRecipeBlue = Color(0xff5189C9);
const kRecipeLightBlue = Color(0xFFE3F2FD);

/// ข้อความเตือนบังคับ ทุกครั้งที่ AI สแกนหรือสร้างสูตรอาหาร
const kAiDisclaimerText =
    '⚠️ คำเตือน: สูตรอาหารนี้วิเคราะห์โดย AI โปรดตรวจสอบส่วนผสมและสุขอนามัยก่อนประกอบอาหาร';

// ---------------------------------------------------------------------------
// Bottom Sheet: เลือกวิธีเพิ่มสูตรอาหาร (เปิดจาก FAB ในหน้าคลังสูตร)
// ---------------------------------------------------------------------------

enum AddRecipeOption { scan, manual }

Future<AddRecipeOption?> showAddRecipeSheet(BuildContext context) {
  return showModalBottomSheet<AddRecipeOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddRecipeSheet(),
  );
}

class _AddRecipeSheet extends StatelessWidget {
  const _AddRecipeSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: kRecipeBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'เพิ่มสูตรอาหาร',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'เลือกวิธีที่สะดวกสำหรับคุณ',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _SheetOption(
            icon: Icons.camera_alt_outlined,
            title: 'สแกนสูตรอาหาร',
            subtitle: 'ถ่ายรูปตำราหรือสูตรลายมือ ให้ AI อ่านสูตรให้',
            onTap: () => Navigator.pop(context, AddRecipeOption.scan),
          ),
          const SizedBox(height: 12),
          _SheetOption(
            icon: Icons.edit_note_rounded,
            title: 'เขียนสูตรเอง',
            subtitle: 'กรอกชื่อเมนู วัตถุดิบ และขั้นตอนด้วยตัวเอง',
            onTap: () => Navigator.pop(context, AddRecipeOption.manual),
          ),
        ],
      ),
    );
  }
}

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
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: kRecipeBlue.withOpacity(0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: kRecipeBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kRecipeBlue, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
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

class AiDisclaimerBanner extends StatelessWidget {
  const AiDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8590C), width: 1.5),
      ),
      child: const Text(
        kAiDisclaimerText,
        style: TextStyle(
          color: Color(0xFFC92A2A),
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ขั้นตอนที่ AI คิดเพิ่ม (ตัวหนังสือสีแดง)
// ---------------------------------------------------------------------------

const kAiRed = Color(0xFFC92A2A);
const kAiRedBg = Color(0xFFFFF5F5);

/// ข้อความอธิบายสีแดง แสดงเหนือรายการขั้นตอน เมื่อมีขั้นตอนที่ AI คิดเพิ่ม
class AiStepsNote extends StatelessWidget {
  final String text;
  const AiStepsNote({
    super.key,
    this.text =
        'ข้อความสีแดง = ขั้นตอนที่ AI คิดเพิ่มให้ เพราะไม่พบในรูปสูตรอาหาร โปรดตรวจสอบก่อนทำ',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kAiRedBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: kAiRed),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: kAiRed,
                fontSize: 12.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAiRed),
      ),
      child: const Text(
        'AI',
        style: TextStyle(
          color: kAiRed,
          fontSize: 10,
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
  final List<String> steps;
  final Set<int> aiIndexes;

  const RecipeStepsView({
    super.key,
    required this.steps,
    this.aiIndexes = const {},
    required int fontSize,
    required int spacing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aiIndexes.isNotEmpty) const AiStepsNote(),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text.rich(
              TextSpan(
                text: '${i + 1}. ${steps[i]}',
                children: [
                  if (aiIndexes.contains(i)) ...[
                    const TextSpan(text: '  '),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: AiChip(),
                    ),
                  ],
                ],
              ),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: aiIndexes.contains(i) ? kAiRed : Colors.black87,
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
  final Widget child;
  final EdgeInsetsGeometry padding;

  const RecipeSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: kRecipeYellow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kRecipeYellowBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// ปุ่ม "แก้ไข" ทรงแคปซูลสีเหลือง (กดได้จริง)
class EditPill extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const EditPill({super.key, required this.onTap, this.label = 'แก้ไข'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kRecipeYellow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kRecipeYellowBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
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
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool isLoading;

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
      borderRadius: BorderRadius.circular(12),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : onSecondary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFADADAD),
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: shape,
                ),
                child: Text(
                  secondaryLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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
                onPressed: isLoading ? null : onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRecipeLightBlue,
                  foregroundColor: Colors.black87,
                  disabledBackgroundColor: kRecipeLightBlue,
                  elevation: 0,
                  shape: shape,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: kRecipeBlue,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CheckIcon(size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              primaryLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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
  final navigator = Navigator.of(context, rootNavigator: true);
  var isOpen = true;
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: kRecipeBlue),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return () {
    if (isOpen) {
      isOpen = false;
      navigator.pop();
    }
  };
}
