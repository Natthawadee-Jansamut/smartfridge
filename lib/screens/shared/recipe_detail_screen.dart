import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/widgets/deduct_confirm_sheet.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';

/// หน้ารายละเอียดสูตรอาหารที่บันทึกไว้ (ตามดีไซน์ใน Figma: "Smart Recipe" หน้าเมนู)
/// เปิดจากการกดเลือกสูตรในหน้าคลังสูตรอาหาร
/// เทียบวัตถุดิบที่ต้องใช้กับของจริงในตู้เย็น (Supabase) แบบสดเสมอ
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final List<Map<String, dynamic>>
  inventory; // รับข้อมูลคลังเพื่อเอามาเทียบหักลบ
  // ข้อความบนแคปซูลหัวเรื่อง — ค่าเริ่มต้นใช้กับสูตรที่บันทึกไว้แล้ว
  // ส่วนตอนเปิดจากหน้า "สร้างเมนูอาหาร (AI)" จะส่ง "เมนูแนะนำ" มาแทน
  // ให้ตรงกับดีไซน์ Figma ของแต่ละที่มา
  final String headerTitle;

  /// แก้ไขวัตถุดิบ/ขั้นตอนได้ในหน้านี้ (เฉพาะสูตรที่บันทึกไว้ในคลังแล้ว)
  /// หน้า "เมนูแนะนำ" จาก AI ยังไม่ได้บันทึก จึงปิดไว้
  final bool canEdit;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.inventory,
    this.headerTitle = "สูตรเมนูอาหาร",
    this.canEdit = false,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

/// ข้อมูลร่างของวัตถุดิบ 1 แถว ตอนกด "แก้ไข"
class _IngDraft {
  final TextEditingController name;
  num? qty; // ปรับด้วยปุ่ม +/− เท่านั้น
  String? unit;

  _IngDraft({String name = '', this.qty, this.unit})
    : name = TextEditingController(text: name);

  void dispose() => name.dispose();
}

/// ข้อมูลร่างของขั้นตอน 1 ข้อ — ถ้าแก้ข้อความของขั้นตอนที่ AI คิด
/// จะถือว่าผู้ใช้ตรวจแล้ว กลายเป็นขั้นตอนของผู้ใช้ (หายจากสีแดง)
class _StepDraft {
  final TextEditingController ctrl;
  final String _aiText;
  bool isAi;

  _StepDraft({String text = '', this.isAi = false})
    : ctrl = TextEditingController(text: text),
      _aiText = text.trim();

  bool syncAiFlag() {
    if (isAi && ctrl.text.trim() != _aiText) {
      isAi = false;
      return true;
    }
    return false;
  }

  void dispose() => ctrl.dispose();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isCooking = false;
  bool _isDeleting = false;

  // สำเนาสูตรที่แก้ไขได้ (อัปเดตหลังบันทึกการแก้ไขสำเร็จ)
  late Map<String, dynamic> _recipe = Map<String, dynamic>.from(widget.recipe);

  // ----- โหมดแก้ไข (ทีละส่วน: วัตถุดิบ หรือ ขั้นตอน)
  bool _editingIngredients = false;
  bool _editingSteps = false;
  bool _isSavingEdit = false;
  List<_IngDraft> _ingDrafts = [];
  List<_StepDraft> _stepDrafts = [];
  num? _servingsDraft;
  int? _minutesDraft;

  bool get _canEdit => widget.canEdit && widget.recipe['id'] != null;
  bool get _isEditing => _editingIngredients || _editingSteps;

  @override
  void dispose() {
    for (final d in _ingDrafts) {
      d.dispose();
    }
    for (final d in _stepDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  /// dispose controller หลังเฟรมนี้ (TextField ที่ยังค้างอยู่จะได้ไม่ใช้ของที่ถูกทำลาย)
  void _disposeLater(List<void Function()> disposers) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final d in disposers) {
        d();
      }
    });
  }

  _StepDraft _newStep({String text = '', bool isAi = false}) {
    final d = _StepDraft(text: text, isAi: isAi);
    d.ctrl.addListener(() {
      if (d.syncAiFlag() && mounted) setState(() {});
    });
    return d;
  }

  void _beginEditIngredients() {
    _ingDrafts = [
      for (final ing in RecipeRepository.ingredientsOf(_recipe))
        _IngDraft(
          name: (ing['name'] ?? '').toString(),
          qty:
              RecipeRepository.parseQuantity(ing['use_quantity']) ??
              RecipeRepository.leadingNumber(ing['use_quantity']),
          unit: (ing['unit'] ?? '').toString().trim().isEmpty
              ? null
              : ing['unit'].toString().trim(),
        ),
    ];
    if (_ingDrafts.isEmpty) _ingDrafts.add(_IngDraft());
    _servingsDraft = RecipeRepository.leadingNumber(_recipe['servings']);
    setState(() => _editingIngredients = true);
  }

  void _beginEditSteps() {
    final texts = RecipeRepository.stepTextsOf(_recipe);
    final ai = RecipeRepository.aiStepIndexesOf(_recipe);
    _stepDrafts = [
      for (var i = 0; i < texts.length; i++)
        _newStep(text: texts[i], isAi: ai.contains(i)),
    ];
    if (_stepDrafts.isEmpty) _stepDrafts.add(_newStep());
    _minutesDraft = RecipeRepository.minutesOf(_recipe['time']);
    setState(() => _editingSteps = true);
  }

  void _endEdit() {
    FocusScope.of(context).unfocus();
    final old = [..._ingDrafts.map((d) => d.dispose), ..._stepDrafts.map((d) => d.dispose)];
    setState(() {
      _editingIngredients = false;
      _editingSteps = false;
      _ingDrafts = [];
      _stepDrafts = [];
    });
    _disposeLater(old);
  }

  Future<void> _saveEdit() async {
    final updated = Map<String, dynamic>.from(_recipe);
    if (_editingIngredients) {
      final list = <Map<String, dynamic>>[
        for (final d in _ingDrafts)
          if (d.name.text.trim().isNotEmpty)
            {
              'name': d.name.text.trim(),
              'use_quantity': d.qty,
              'unit': d.unit ?? '',
            },
      ];
      if (list.isEmpty) {
        _snack('ต้องมีวัตถุดิบอย่างน้อย 1 รายการ', Colors.red);
        return;
      }
      updated['detailed_ingredients'] = list;
      updated['ingredients_used'] = list.map((e) => e['name']).toList();
      updated['servings'] = RecipeRepository.servingsText(_servingsDraft);
    } else {
      final filled = _stepDrafts
          .where((d) => d.ctrl.text.trim().isNotEmpty)
          .toList();
      updated['instructions'] = [
        for (var i = 0; i < filled.length; i++)
          '${i + 1}. ${filled[i].ctrl.text.trim()}',
      ];
      updated['ai_step_indexes'] = [
        for (var i = 0; i < filled.length; i++)
          if (filled[i].isAi) i,
      ];
      updated['time'] = RecipeRepository.minutesText(_minutesDraft);
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSavingEdit = true);
    try {
      final warnings = await RecipeRepository.updateRecipe(
        widget.recipe['id'] as Object,
        updated,
      );
      if (!mounted) return;
      setState(() {
        _recipe = updated;
        _isSavingEdit = false;
      });
      _endEdit();
      _snack(
        warnings.isEmpty
            ? 'บันทึกการแก้ไขเรียบร้อยแล้ว ✏️'
            : 'บันทึกแล้ว แต่${warnings.join(' และ')}',
        warnings.isEmpty ? Colors.green : Colors.orange,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      _snack('บันทึกไม่สำเร็จ: $e', Colors.red);
    }
  }

  // แปลงค่าจำนวนให้เป็นตัวเลขแบบทนทาน เผื่อ AI ตอบ use_quantity มาเป็น
  // ข้อความปนหน่วย (เช่น "1 ลูก") หรือเป็นเศษส่วน (เช่น "1/2") แทนที่จะเป็น
  // ตัวเลขล้วนๆ ตามที่ขอไว้ในพรอมป์เป๊ะๆ เสมอไป ถ้าแปลงตรงๆ ไม่ได้เลยจะได้
  // ลองดึงแค่ตัวเลขนำหน้าออกมาก่อน แทนที่จะปัดเป็น 0 แล้วข้ามการหักไปเฉยๆ
  num _toNum(dynamic v) {
    if (v is num) return v;
    final text = v?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    final direct = num.tryParse(text);
    if (direct != null) return direct;

    final fraction = RegExp(r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)').firstMatch(text);
    if (fraction != null) {
      final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
      final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
      return denominator == 0 ? 0 : numerator / denominator;
    }

    final leadingNumber = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    return double.tryParse(leadingNumber?.group(0) ?? '') ?? 0;
  }

  // แสดง "ไม่ได้ระบุ" แทนที่จะปล่อยว่างเปล่า เมื่อ AI ไม่ได้ระบุปริมาณ/หน่วยของ
  // วัตถุดิบชิ้นนั้นมาให้ (เช่น รูปสูตรต้นฉบับไม่ได้เขียนปริมาณกำกับไว้)
  String _formatQty(Map<String, dynamic> ing) {
    final qty = ing['use_quantity'];
    final unit = (ing['unit'] ?? '').toString().trim();
    final qtyText = (qty == null || qty.toString().trim().isEmpty)
        ? ''
        : qty.toString().trim();
    final combined = [qtyText, unit].where((s) => s.isNotEmpty).join(' ');
    return combined.isEmpty ? 'ไม่ได้ระบุ' : combined;
  }

  // เช็คว่าวัตถุดิบที่สูตรต้องการ มีในตู้เย็นพอไหม (เทียบชื่อ + จำนวน)
  bool _isIngredientAvailable(Map<String, dynamic> needed) {
    final neededName = (needed['name'] ?? '').toString().trim().toLowerCase();
    final neededQty = _toNum(needed['use_quantity']);
    // รวมทุกลอตของวัตถุดิบชื่อนี้ (ซื้อซ้ำจะแยกเป็นคนละลอตตามหลัก FIFO)
    final match = widget.inventory
        .where((inv) => ingredientNameMatches(inv['name'], neededName))
        .toList();
    if (match.isEmpty) return false;
    final haveQty = availableQuantity(widget.inventory, neededName);
    return haveQty >= neededQty;
  }

  // ฟังก์ชันหักวัตถุดิบออกจาก Supabase
  Future<void> _startCooking() async {
    List<dynamic> detailedIngredients =
        _recipe['detailed_ingredients'] ?? [];

    // ให้ผู้ใช้ยืนยันก่อนว่าใช้ไปเท่าไหร่จริง (กดเลือกแบบกะด้วยตา ไม่ต้องชั่ง)
    // ค่าเริ่มต้นตามที่สูตรบอก — กดยกเลิกก็ไม่หักอะไรเลย
    final choices = await showDeductConfirmSheet(
      context,
      inventory: widget.inventory,
      requests: [
        for (final needed in detailedIngredients)
          if ((needed['name'] ?? '').toString().trim().isNotEmpty)
            DeductRequest(
              name: needed['name'].toString(),
              suggested: _toNum(needed['use_quantity']),
            ),
      ],
    );
    if (choices == null || !mounted) return;

    setState(() => _isCooking = true);

    try {
      final supabase = Supabase.instance.client;

      int deductedCount = 0;
      List<String> notFoundNames = [];
      // เก็บ error จริงตอนยิง update ไป Supabase แยกจากกรณี "หาไม่เจอในคลัง"
      // เพราะสาเหตุคนละแบบกัน (เช่น ฐานข้อมูลปฏิเสธสิทธิ์แก้ไข ไม่ใช่แค่หา
      // วัตถุดิบไม่เจอ) ผู้ใช้จะได้รู้ว่าจริงๆ แล้วเกิดอะไรขึ้นกันแน่
      List<String> updateErrors = [];

      // สำเนาคลังไว้หักในเครื่องด้วย จะได้เห็นจำนวนล่าสุดถ้าเมนูใช้วัตถุดิบ
      // ชื่อเดียวกันซ้ำ (ไม่แก้ลิสต์ของหน้าก่อนหน้าโดยตรง)
      final inventory = widget.inventory
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // หักตามปริมาณที่ผู้ใช้ยืนยันแบบ FIFO (ลอตที่ใกล้หมดอายุ/เก่าที่สุดก่อน
      // ถ้าไม่พอหักลอตถัดไปต่อ) ผ่าน fridge_stock.dart
      for (final choice in choices) {
        if (choice.amount == null) {
          notFoundNames.add(choice.name);
          continue;
        }
        if (choice.amount! <= 0) continue; // ผู้ใช้เลือก "ไม่ได้ใช้"

        final result = await deductIngredientFifo(
          supabase: supabase,
          inventory: inventory,
          name: choice.name,
          amount: choice.amount!,
        );

        if (!result.found) {
          notFoundNames.add(choice.name);
        } else if (result.error != null) {
          updateErrors.add("${choice.name}: ${result.error}");
        } else {
          deductedCount++;
        }
      }

      if (mounted) {
        final hasNotFound = notFoundNames.isNotEmpty;
        final hasUpdateError = updateErrors.isNotEmpty;
        String message;
        Color bgColor;

        if (hasUpdateError) {
          // ฐานข้อมูลปฏิเสธการอัปเดตจริงๆ (เช่นสิทธิ์ไม่พอ) ต้องโชว์ error ตรงๆ
          // ไม่งั้นจะดูเหมือนกดแล้วไม่มีอะไรเกิดขึ้นเลย ทั้งที่จริงๆ error
          message = "หักวัตถุดิบไม่สำเร็จบางรายการ: ${updateErrors.join(' | ')}";
          bgColor = Colors.red;
        } else if (deductedCount == 0 && !hasNotFound) {
          // ผู้ใช้เลือก "ไม่ได้ใช้" ทุกรายการในหน้ายืนยัน
          message = "ทำอาหารเสร็จสิ้น! ไม่ได้หักวัตถุดิบออกจากตู้เย็น";
          bgColor = Colors.green;
        } else if (deductedCount == 0) {
          // ไม่พบวัตถุดิบที่ตรงกันในคลังเลยสักชิ้น ไม่ควรบอกว่า "เรียบร้อยแล้ว"
          message = "ไม่พบวัตถุดิบที่ตรงกับในคลังเลย จึงยังไม่ได้หักอะไรออก "
              "(${notFoundNames.join(', ')})";
          bgColor = Colors.orange;
        } else if (hasNotFound) {
          message =
              "หักวัตถุดิบไปแล้ว $deductedCount รายการ แต่หาไม่เจอในคลัง: "
              "${notFoundNames.join(', ')}";
          bgColor = Colors.orange;
        } else {
          message = "ทำอาหารเสร็จสิ้น! หักวัตถุดิบเรียบร้อยแล้ว 🍲";
          bgColor = Colors.green;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: bgColor),
        );
        // ถ้ามีที่หักสำเร็จอย่างน้อย 1 ชิ้น ค่อยบอกหน้าเดิมให้รีเฟรชตู้เย็น
        Navigator.pop(context, deductedCount > 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("เกิดข้อผิดพลาด: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCooking = false);
    }
  }

  // ลบสูตรอาหารนี้ออกจาก Supabase จริง
  Future<void> _deleteRecipe() async {
    final recipeName = widget.recipe['recipe_name'] ?? 'สูตรนี้';
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("ลบสูตรอาหารนี้?"),
            content: Text("ต้องการลบ \"$recipeName\" ออกจากคลังสูตรอาหารใช่ไหม"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("ยกเลิก"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("ลบ"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isDeleting = true);
    try {
      await Supabase.instance.client
          .from('scanned_recipes')
          .delete()
          .eq('id', widget.recipe['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ลบสูตรอาหารเรียบร้อยแล้ว"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // กลับไปหน้ารายการแล้วรีเฟรช
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final servingsText = (recipe['servings'] ?? '').toString().trim();
    final timeText = (recipe['time'] ?? '').toString().trim();
    // ขั้นตอนการทำ + ตำแหน่งขั้นตอนที่ AI คิดเพิ่ม (แสดงเป็นสีแดง)
    final steps = RecipeRepository.stepTextsOf(recipe);
    final aiSteps = RecipeRepository.aiStepIndexesOf(recipe);
    List<dynamic> detailedIngredients = recipe['detailed_ingredients'] ?? [];

    final availableCount = detailedIngredients
        .where((e) => _isIngredientAvailable(Map<String, dynamic>.from(e)))
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: widget.headerTitle),
            const SizedBox(height: 15),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ชื่อเมนู (กล่องขาวตรงกลาง ตามดีไซน์)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // สถานะวัตถุดิบ (ของจริงจากฐานข้อมูล ไม่ใช่ mock)
                    RecipeStatusBar(
                      label: "สถานะวัตถุดิบ",
                      have: availableCount,
                      total: detailedIngredients.length,
                    ),
                    const SizedBox(height: 20),

                    // วัตถุดิบที่ต้องใช้
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "วัตถุดิบที่ต้องใช้",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (_canEdit && !_isEditing)
                                EditPillButton(onTap: _beginEditIngredients),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_editingIngredients)
                            ..._buildIngredientEditor()
                          else ...[
                          if (servingsText.isNotEmpty)
                            _infoLine(Icons.restaurant_outlined, 'สำหรับ $servingsText'),
                          ...detailedIngredients.map((ing) {
                            final ingMap = Map<String, dynamic>.from(ing);
                            final available = _isIngredientAvailable(ingMap);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        child: available
                                            ? const CheckIcon(size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        ingMap['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _formatQty(ingMap),
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ขั้นตอนการทำ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "ขั้นตอนการทำ",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (_canEdit && !_isEditing)
                                EditPillButton(onTap: _beginEditSteps),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_editingSteps)
                            ..._buildStepsEditor()
                          else ...[
                            if (timeText.isNotEmpty)
                              _infoLine(
                                Icons.timer_outlined,
                                'ใช้เวลาประมาณ $timeText',
                              ),
                            // ขั้นตอนที่ AI คิดเพิ่ม = ตัวหนังสือสีแดง + ป้าย "AI"
                            RecipeStepsView(
                              steps: steps,
                              aiIndexes: aiSteps,
                              fontSize: 15,
                              spacing: 12,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ปุ่มด้านล่าง: ลบสูตรนี้ / เริ่มทำอาหาร (หักวัตถุดิบ)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    height: 55,
                    width: 55,
                    child: OutlinedButton(
                      onPressed: _isDeleting ? null : _deleteRecipe,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isDeleting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.redAccent,
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 55,
                      child: ElevatedButton(
                        // ระหว่างแก้ไข ให้บันทึก/ยกเลิกก่อน ค่อยกดทำอาหาร
                        onPressed: (_isCooking || _isEditing)
                            ? null
                            : _startCooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7D0),
                          foregroundColor: const Color(0xff5189C9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: _isCooking
                            ? const CircularProgressIndicator(
                                color: Color(0xff5189C9),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.soup_kitchen,
                                    size: 24,
                                    color: Color(0xff5189C9),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    "Cooking (หักวัตถุดิบ)",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xff5189C9),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Edit UI

  Widget _infoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildIngredientEditor() {
    return [
      StepperLine(
        label: 'จำนวนที่',
        stepper: NumberStepper(
          value: _servingsDraft,
          max: 50,
          suffix: 'ที่',
          emptyLabel: 'ไม่ระบุ',
          onChanged: (v) => setState(() => _servingsDraft = v),
        ),
      ),
      const Divider(height: 16),
      for (var i = 0; i < _ingDrafts.length; i++)
        IngredientEditRow(
          key: ObjectKey(_ingDrafts[i]),
          index: i,
          nameController: _ingDrafts[i].name,
          qty: _ingDrafts[i].qty,
          unit: _ingDrafts[i].unit,
          onQtyChanged: (v) => setState(() => _ingDrafts[i].qty = v),
          onUnitChanged: (v) => setState(() {
            final d = _ingDrafts[i];
            d.unit = v;
            final max = maxForUnit(v);
            if (d.qty != null && d.qty! > max) d.qty = max;
          }),
          onRemove: _ingDrafts.length > 1
              ? () {
                  final d = _ingDrafts[i];
                  setState(() => _ingDrafts.removeAt(i));
                  _disposeLater([d.dispose]);
                }
              : null,
        ),
      _addRowButton(
        'เพิ่มวัตถุดิบ',
        () => setState(() => _ingDrafts.add(_IngDraft())),
      ),
      _editActions(),
    ];
  }

  List<Widget> _buildStepsEditor() {
    return [
      StepperLine(
        label: 'เวลาทำ',
        stepper: NumberStepper(
          value: _minutesDraft,
          step: 5,
          max: 600,
          suffix: 'นาที',
          emptyLabel: 'ไม่ระบุ',
          onChanged: (v) => setState(() => _minutesDraft = v?.round()),
        ),
      ),
      const Divider(height: 16),
      if (_stepDrafts.any((d) => d.isAi))
        const AiStepsNote(
          text:
              'ข้อความสีแดง = ขั้นตอนที่ AI คิดเพิ่มให้ ถ้าแก้ไขข้อความ จะถือว่าเป็นขั้นตอนของคุณ',
        ),
      for (var i = 0; i < _stepDrafts.length; i++)
        StepEditRow(
          key: ObjectKey(_stepDrafts[i]),
          index: i,
          controller: _stepDrafts[i].ctrl,
          isAi: _stepDrafts[i].isAi,
          onRemove: _stepDrafts.length > 1
              ? () {
                  final d = _stepDrafts[i];
                  setState(() => _stepDrafts.removeAt(i));
                  _disposeLater([d.dispose]);
                }
              : null,
        ),
      _addRowButton(
        'เพิ่มขั้นตอน',
        () => setState(() => _stepDrafts.add(_newStep())),
      ),
      _editActions(),
    ];
  }

  Widget _addRowButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.black87,
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  /// ปุ่ม ยกเลิก / บันทึก ท้ายการ์ดที่กำลังแก้ไข
  Widget _editActions() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: _isSavingEdit ? null : _endEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey.shade400),
                  shape: shape,
                ),
                child: const Text('ยกเลิก'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _isSavingEdit ? null : _saveEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRecipeLightBlue,
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  shape: shape,
                ),
                icon: _isSavingEdit
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kRecipeBlue,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'บันทึก',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
