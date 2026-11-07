import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            subtitle: 'ถ่ายภาพตำราหรือสูตรลายมือ ให้ AI อ่านสูตรให้',
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
  final double fontSize;
  final double spacing;

  const RecipeStepsView({
    super.key,
    required this.steps,
    this.aiIndexes = const {},
    this.fontSize = 14,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aiIndexes.isNotEmpty) const AiStepsNote(),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: spacing),
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
                fontSize: fontSize,
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

// ---------------------------------------------------------------------------
// หน่วยครัว + ปุ่มบวก/ลบตัวเลข (กันผู้ใช้พิมพ์ตัวหนังสือลงช่องตัวเลข)
// ---------------------------------------------------------------------------

/// หน่วยครัวที่เลือกได้ — รองรับทั้งน้ำหนัก, ช้อน/ถ้วย, นับชิ้น/ส่วน
/// และ "%" สำหรับกะด้วยสายตา (เช่น ใช้นม 50% ของขวด)
const kRecipeUnits = <String>[
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
  switch ((unit ?? '').trim()) {
    case 'กรัม':
    case 'มิลลิลิตร':
    case '%':
      return 10;
    case 'กิโลกรัม':
    case 'ลิตร':
      return 0.25;
    case 'ช้อนโต๊ะ':
    case 'ช้อนชา':
    case 'ถ้วย':
    case 'ลูก':
    case 'หัว':
    case 'แพ็ค':
    case 'ส่วน':
      return 0.5;
    default: // ฟอง ชิ้น กลีบ เม็ด ต้น กำ และหน่วยอื่นๆ
      return 1;
  }
}

/// ค่าสูงสุดตามหน่วย (% ไม่เกิน 100)
num maxForUnit(String? unit) => (unit ?? '').trim() == '%' ? 100 : 9999;

/// ปุ่ม [−] ค่า [+] สำหรับค่าตัวเลขทุกช่อง (จำนวนวัตถุดิบ, เวลาทำ, จำนวนที่)
/// - ค่า 0 / null แสดงเป็น [emptyLabel] และถือว่า "ไม่ได้ระบุ"
/// - กดค้างเพื่อเพิ่ม/ลดต่อเนื่อง
/// - แตะที่ตัวเลขตรงกลางเพื่อพิมพ์ค่าเองได้เลย (เช่น 250 กรัม ไม่ต้องกด + ทีละขั้น)
class NumberStepper extends StatefulWidget {
  final num? value;
  final ValueChanged<num?> onChanged;
  final num step;
  final num min;
  final num max;
  final String? suffix;
  final String emptyLabel;
  final bool compact;

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
  Timer? _repeat;
  num? _current;

  // โหมดพิมพ์ตัวเลขเอง
  bool _typing = false;
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // แตะที่อื่น/ปิดคีย์บอร์ด = ยืนยันค่าที่พิมพ์
    _focus.addListener(() {
      if (!_focus.hasFocus && _typing) _commitTyped();
    });
  }

  String _plain(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

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
      if (mounted) _focus.requestFocus();
    });
  }

  void _commitTyped() {
    final raw = _textCtrl.text.trim().replaceAll(',', '.');
    setState(() => _typing = false);
    if (raw.isEmpty) {
      // ลบจนว่าง = ไม่ระบุ
      if (_v != 0) widget.onChanged(null);
      return;
    }
    final parsed = num.tryParse(raw);
    if (parsed == null) return; // พิมพ์ไม่ใช่ตัวเลข -> คงค่าเดิม
    final clamped = parsed.clamp(widget.min, widget.max);
    final clean = double.parse(clamped.toStringAsFixed(2));
    final value = clean == clean.roundToDouble() ? clean.toInt() : clean;
    if (value == _v) return;
    widget.onChanged(value == 0 ? null : value);
  }

  num get _v => _current ?? widget.value ?? 0;

  @override
  void didUpdateWidget(covariant NumberStepper old) {
    super.didUpdateWidget(old);
    if (_repeat == null) _current = null;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bump(int dir) {
    if (_typing) _commitTyped();
    // ปัดให้ตรงจังหวะ step เสมอ (กันเลขทศนิยมเพี้ยน เช่น 0.30000000004)
    final raw = _v + dir * widget.step;
    final snapped = (raw / widget.step).round() * widget.step;
    final next = snapped.clamp(widget.min, widget.max);
    final clean = double.parse(next.toStringAsFixed(2));
    final value = clean == clean.roundToDouble() ? clean.toInt() : clean;
    if (value == _v) return;
    _current = value;
    widget.onChanged(value == 0 ? null : value);
  }

  void _startRepeat(int dir) {
    _repeat?.cancel();
    _repeat = Timer.periodic(
      const Duration(milliseconds: 110),
      (_) => _bump(dir),
    );
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
    _current = null;
  }

  String _label() {
    final v = _v;
    if (v == 0) return widget.emptyLabel;
    final n = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return widget.suffix == null ? n : '$n ${widget.suffix}';
  }

  Widget _button(IconData icon, int dir, bool enabled) {
    final size = widget.compact ? 30.0 : 36.0;
    return GestureDetector(
      onLongPressStart: enabled ? (_) => _startRepeat(dir) : null,
      onLongPressEnd: enabled ? (_) => _stopRepeat() : null,
      onLongPressCancel: _stopRepeat,
      child: Material(
        color: enabled ? kRecipeYellow : Colors.grey.shade200,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => _bump(dir) : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: widget.compact ? 18 : 20,
              color: enabled ? Colors.black87 : Colors.black26,
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
      onTap: _startTyping,
      child: Container(
        constraints: BoxConstraints(minWidth: widget.compact ? 52 : 70),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          _label(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.compact ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: v == 0 ? Colors.black38 : Colors.black87,
          ),
        ),
      ),
    );
  }

  /// ช่องพิมพ์ตัวเลข (แสดงตอนแตะที่ค่า)
  Widget _typingField() {
    return SizedBox(
      width: widget.compact ? 64 : 84,
      child: TextField(
        controller: _textCtrl,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        onSubmitted: (_) => _focus.unfocus(),
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
            borderSide: const BorderSide(color: kRecipeBlue, width: 1.5),
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
        _button(Icons.remove_rounded, -1, v > widget.min),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _typing ? _typingField() : _tapToType(v),
        ),
        _button(Icons.add_rounded, 1, v < widget.max),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// รูปสูตรที่ผู้ใช้อัปโหลด (ให้เทียบว่า AI อ่านถูกไหม) — แตะเพื่อขยาย/ซูม
// ---------------------------------------------------------------------------

class ScannedImagePreview extends StatelessWidget {
  final Uint8List bytes;
  final double height;

  const ScannedImagePreview({
    super.key,
    required this.bytes,
    this.height = 200,
  });

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
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openFullScreen(context),
            child: Stack(
              children: [
                Container(
                  height: height,
                  width: double.infinity,
                  color: const Color(0xFFF3F6FA),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.zoom_in_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'แตะเพื่อขยาย',
                          style: TextStyle(color: Colors.white, fontSize: 12),
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
            style: TextStyle(fontSize: 12, color: Colors.black54),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        // ธีมหลักของแอป (main.dart) ตั้งไอคอน AppBar เป็นสีดำ
        // บนพื้นดำจะมองไม่เห็น -> บังคับเป็นสีขาวที่หน้านี้
        iconTheme: const IconThemeData(color: Colors.white),
        // ปุ่มปิด (X) ออกจากหน้าดูรูปเต็มจอ
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          tooltip: 'ปิด',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('รูปสูตรที่อัปโหลด', style: TextStyle(fontSize: 16)),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// แถวแก้ไขวัตถุดิบ / ขั้นตอน (ใช้ร่วมกัน: หน้าเขียนสูตร + หน้ารายละเอียดสูตร)
// ---------------------------------------------------------------------------

InputDecoration recipeBoxDecoration(
  String hint, {
  Widget? prefix,
  Widget? suffix,
  bool isAi = false,
}) {
  final radius = BorderRadius.circular(10);
  return InputDecoration(
    isDense: true,
    filled: isAi,
    fillColor: isAi ? kAiRedBg : null,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(
        color: isAi ? kAiRed.withOpacity(0.5) : Colors.grey.shade400,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: isAi ? kAiRed : kRecipeBlue, width: 1.5),
    ),
  );
}

Widget _removeIcon(VoidCallback? onTap) => SizedBox(
  width: 28,
  child: onTap == null
      ? null
      : IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tooltip: 'ลบ',
          icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
  final int index;
  final TextEditingController nameController;
  final num? qty;
  final String? unit;
  final ValueChanged<num?> onQtyChanged;
  final ValueChanged<String?> onUnitChanged;
  final VoidCallback? onRemove;

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
    final units = <String>{
      ...kRecipeUnits,
      if (unit != null && unit!.isNotEmpty) unit!,
    }.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 13),
                  decoration: recipeBoxDecoration('ชื่อวัตถุดิบ'),
                ),
              ),
              _removeIcon(onRemove),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 28),
            child: Row(
              children: [
                NumberStepper(
                  value: qty,
                  step: stepForUnit(unit),
                  max: maxForUnit(unit),
                  compact: true,
                  onChanged: onQtyChanged,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.only(left: 8, right: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: (unit == null || unit!.isEmpty) ? null : unit,
                        isExpanded: true,
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
                        menuMaxHeight: 320,
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
  final TextEditingController controller;
  final bool isAi;
  final VoidCallback? onRemove;

  const StepEditRow({
    super.key,
    required this.index,
    required this.controller,
    this.isAi = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = isAi ? kAiRed : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 13, height: 1.4, color: color),
              decoration: recipeBoxDecoration(
                'อธิบายขั้นตอน',
                isAi: isAi,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Text(
                    '${index + 1}.',
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                suffix: isAi
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
