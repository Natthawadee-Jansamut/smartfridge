import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/widgets/deduct_confirm_sheet.dart'; // แผ่นยืนยันหักวัตถุดิบ
import 'package:test_app/services/fridge_stock.dart'; // หักวัตถุดิบ FIFO
import 'package:test_app/services/recipe_repository.dart'; // บันทึก/ลบ/แก้สูตร
import 'package:test_app/widgets/add_recipe_widgets.dart'; // วิดเจ็ตแก้สูตร (แถววัตถุดิบ ปุ่ม +/−)
import 'package:test_app/services/fridge_images.dart'; // ถังเก็บรูปสูตร

/// หน้ารายละเอียดสูตรอาหารที่บันทึกไว้ (ตามดีไซน์ใน Figma: "Smart Recipe" หน้าเมนู)
/// เปิดจากการกดเลือกสูตรในหน้าคลังสูตรอาหาร
/// เทียบวัตถุดิบที่ต้องใช้กับของจริงในตู้เย็น (Supabase) แบบสดเสมอ
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe; // สูตรที่จะแสดง
  final List<Map<String, dynamic>>
  inventory; // รับข้อมูลคลังเพื่อเอามาเทียบหักลบ
  // ข้อความบนแคปซูลหัวเรื่อง — ค่าเริ่มต้นใช้กับสูตรที่บันทึกไว้แล้ว
  // ส่วนตอนเปิดจากหน้า "สร้างเมนูอาหาร (AI)" จะส่ง "เมนูแนะนำ" มาแทน
  // ให้ตรงกับดีไซน์ Figma ของแต่ละที่มา
  final String headerTitle;

  /// แก้ไขวัตถุดิบ/ขั้นตอนได้ในหน้านี้ (เฉพาะสูตรที่บันทึกไว้ในคลังแล้ว)
  /// หน้า "เมนูแนะนำ" จาก AI ยังไม่ได้บันทึก จึงปิดไว้
  final bool canEdit;

  /// แท็บที่ไฮไลต์ในแถบล่าง ให้ตรงกับฟีเจอร์ที่เปิดหน้านี้มา (หน้านี้ใช้ร่วมกัน
  /// ระหว่าง "สแกนสูตรอาหาร" = scan และ "สร้างเมนูอาหาร" = menu)
  final AppTab tab;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.inventory,
    this.headerTitle = "สูตรเมนูอาหาร",
    this.canEdit = false,
    this.tab = AppTab.scan,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

/// ข้อมูลร่างของวัตถุดิบ 1 แถว ตอนกด "แก้ไข"
class _IngDraft {
  final TextEditingController name; // ช่องชื่อวัตถุดิบ
  num? qty; // ปรับด้วยปุ่ม +/− เท่านั้น
  String? unit; // หน่วย

  _IngDraft({String name = '', this.qty, this.unit}) // สร้างช่องชื่อพร้อมใส่ค่าเริ่มต้น
    : name = TextEditingController(text: name);

  void dispose() => name.dispose(); // คืนหน่วยความจำ
}

/// ข้อมูลร่างของขั้นตอน 1 ข้อ — ถ้าแก้ข้อความของขั้นตอนที่ AI คิด
/// จะถือว่าผู้ใช้ตรวจแล้ว กลายเป็นขั้นตอนของผู้ใช้ (หายจากสีแดง)
class _StepDraft {
  final TextEditingController ctrl; // ช่องข้อความขั้นตอน
  final String _aiText; // ข้อความเดิมที่ AI เขียน
  bool isAi; // เป็นขั้นที่ AI แต่งอยู่ไหม

  _StepDraft({String text = '', this.isAi = false})
    : ctrl = TextEditingController(text: text),
      _aiText = text.trim();

  // แก้จนข้อความไม่ตรงของ AI -> ไม่นับเป็นของ AI แล้ว (คืน true ถ้าเพิ่งเปลี่ยน)
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
  bool _isCooking = false; // กำลังหักวัตถุดิบไหม
  bool _isDeleting = false; // กำลังลบสูตรไหม

  // สำเนาสูตรที่แก้ไขได้ (อัปเดตหลังบันทึกการแก้ไขสำเร็จ)
  late Map<String, dynamic> _recipe = Map<String, dynamic>.from(widget.recipe);

  // ----- โหมดแก้ไข (ทีละส่วน: วัตถุดิบ หรือ ขั้นตอน)
  bool _editingIngredients = false; // กำลังแก้วัตถุดิบไหม
  bool _editingSteps = false; // กำลังแก้ขั้นตอนไหม
  bool _isSavingEdit = false; // กำลังบันทึกการแก้ไขไหม
  List<_IngDraft> _ingDrafts = []; // ร่างแถววัตถุดิบ
  List<_StepDraft> _stepDrafts = []; // ร่างแถวขั้นตอน
  num? _servingsDraft; // ร่างจำนวนที่
  int? _minutesDraft; // ร่างเวลาทำ (นาที)

  bool get _canEdit => widget.canEdit && widget.recipe['id'] != null; // แก้ได้ต่อเมื่ออนุญาต และสูตรบันทึกแล้ว (มี id)

  /// ลบได้เฉพาะสูตรที่บันทึกในคลังแล้ว (มี id) — "เมนูแนะนำ" จาก AI ยังไม่มี id
  bool get _canDelete => widget.recipe['id'] != null;
  bool get _isEditing => _editingIngredients || _editingSteps; // กำลังแก้ส่วนใดส่วนหนึ่งอยู่ไหม

  @override
  void dispose() { // ปิดหน้า คืนหน่วยความจำทุกช่อง
    for (final d in _ingDrafts) {
      d.dispose();
    }
    for (final d in _stepDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  // แถบข้อความด้านล่างจอพร้อมสีพื้น
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

  // สร้างร่างขั้นตอน และคอยเช็คทุกครั้งที่พิมพ์ว่ายังเป็นข้อความของ AI ไหม
  _StepDraft _newStep({String text = '', bool isAi = false}) {
    final d = _StepDraft(text: text, isAi: isAi);
    d.ctrl.addListener(() {
      if (d.syncAiFlag() && mounted) setState(() {});
    });
    return d;
  }

  // กด "แก้ไข" ที่การ์ดวัตถุดิบ -> คัดลอกข้อมูลเป็นร่างให้แก้
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
    if (_ingDrafts.isEmpty) _ingDrafts.add(_IngDraft()); // ไม่มีวัตถุดิบเลย ใส่แถวว่างไว้ 1 แถว
    _servingsDraft = RecipeRepository.leadingNumber(_recipe['servings']);
    setState(() => _editingIngredients = true); // เปิดโหมดแก้วัตถุดิบ
  }

  // กด "แก้ไข" ที่การ์ดขั้นตอน -> คัดลอกเป็นร่างให้แก้
  void _beginEditSteps() {
    final texts = RecipeRepository.stepTextsOf(_recipe);
    final ai = RecipeRepository.aiStepIndexesOf(_recipe);
    _stepDrafts = [
      for (var i = 0; i < texts.length; i++)
        _newStep(text: texts[i], isAi: ai.contains(i)),
    ];
    if (_stepDrafts.isEmpty) _stepDrafts.add(_newStep());
    _minutesDraft = RecipeRepository.minutesOf(_recipe['time']);
    setState(() => _editingSteps = true); // เปิดโหมดแก้ขั้นตอน
  }

  // ออกจากโหมดแก้ไข (ทิ้งร่าง)
  void _endEdit() {
    FocusScope.of(context).unfocus(); // หุบคีย์บอร์ด
    final old = [
      ..._ingDrafts.map((d) => d.dispose),
      ..._stepDrafts.map((d) => d.dispose),
    ];
    setState(() { // ปิดโหมดแก้ไข
      _editingIngredients = false;
      _editingSteps = false;
      _ingDrafts = [];
      _stepDrafts = [];
    });
    _disposeLater(old); // คืนหน่วยความจำหลังเฟรมนี้
  }

  /// เปลี่ยนชื่อเมนู แล้วบันทึกลงคลังทันที (เก็บใน overrides เหมือนการแก้ไขอื่น)
  Future<void> _renameRecipe() async {
    final name = await showRenameRecipeDialog(
      context,
      currentName: (_recipe['recipe_name'] ?? '').toString(),
    );
    if (name == null || !mounted) return; // ยกเลิก/ชื่อเดิม
    final updated = {..._recipe, 'recipe_name': name};
    setState(() => _isSavingEdit = true); // เริ่มบันทึก
    try {
      final warnings = await RecipeRepository.updateRecipe( // บันทึกชื่อใหม่ลงฐานข้อมูล
        widget.recipe['id'] as Object,
        updated,
      );
      if (!mounted) return;
      setState(() {
        _recipe = updated;
        _isSavingEdit = false;
      });
      _snack(
        warnings.isEmpty
            ? 'เปลี่ยนชื่อเป็น "$name" แล้ว ✏️'
            : 'บันทึกแล้ว แต่${warnings.join(' และ')}',
        warnings.isEmpty ? Colors.green : Colors.orange, // [UI] ไม่มีคำเตือน = เขียว, มีคำเตือน = ส้ม
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      _snack('เปลี่ยนชื่อไม่สำเร็จ: $e', Colors.red);
    }
  }

  // กด "บันทึก" ในโหมดแก้ไข
  Future<void> _saveEdit() async {
    final updated = Map<String, dynamic>.from(_recipe); // ก๊อปสูตรเดิมมาแก้
    if (_editingIngredients) { // กำลังแก้วัตถุดิบ
      final list = <Map<String, dynamic>>[ // รวบรวมแถวที่กรอกชื่อ
        for (final d in _ingDrafts)
          if (d.name.text.trim().isNotEmpty)
            {
              'name': d.name.text.trim(),
              'use_quantity': d.qty,
              'unit': d.unit ?? '',
            },
      ];
      if (list.isEmpty) { // ไม่มีวัตถุดิบเลย -> ไม่ให้บันทึก
        _snack('ต้องมีวัตถุดิบอย่างน้อย 1 รายการ', Colors.red);
        return;
      }
      updated['detailed_ingredients'] = list;
      updated['ingredients_used'] = list.map((e) => e['name']).toList();
      final servings = RecipeRepository.servingsText(_servingsDraft);
      if (servings !=
          RecipeRepository.servingsText(
            RecipeRepository.leadingNumber(_recipe['servings']),
          )) {
        updated['servings_estimated'] = false; // ผู้ใช้แก้เอง
      }
      updated['servings'] = servings;
    } else { // กำลังแก้ขั้นตอน
      final filled = _stepDrafts // เอาเฉพาะขั้นที่ไม่ว่าง
          .where((d) => d.ctrl.text.trim().isNotEmpty)
          .toList();
      updated['instructions'] = [ // ใส่เลขข้อใหม่
        for (var i = 0; i < filled.length; i++)
          '${i + 1}. ${filled[i].ctrl.text.trim()}',
      ];
      updated['ai_step_indexes'] = [ // จำตำแหน่งขั้นที่ AI แต่ง
        for (var i = 0; i < filled.length; i++)
          if (filled[i].isAi) i,
      ];
      final time = RecipeRepository.minutesText(_minutesDraft);
      if (time !=
          RecipeRepository.minutesText(
            RecipeRepository.minutesOf(_recipe['time']),
          )) {
        updated['time_estimated'] = false; // ผู้ใช้แก้เอง
      }
      updated['time'] = time;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSavingEdit = true);
    try {
      final warnings = await RecipeRepository.updateRecipe( // บันทึกลงฐานข้อมูล
        widget.recipe['id'] as Object,
        updated,
      );
      if (!mounted) return;
      setState(() {
        _recipe = updated;
        _isSavingEdit = false;
      });
      _endEdit(); // ออกจากโหมดแก้ไข
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
    if (v is num) return v; // เป็นตัวเลขอยู่แล้ว
    final text = v?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    final direct = num.tryParse(text); // แปลงตรงๆ ได้
    if (direct != null) return direct;

    final fraction = RegExp( // ลองอ่านแบบเศษส่วน เช่น 1/2
      r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)',
    ).firstMatch(text);
    if (fraction != null) {
      final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
      final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
      return denominator == 0 ? 0 : numerator / denominator; // กันหารด้วย 0
    }

    final leadingNumber = RegExp(r'\d+(\.\d+)?').firstMatch(text); // สุดท้าย: ดึงตัวเลขแรกที่เจอ
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
    return combined.isEmpty ? 'ไม่ได้ระบุ' : combined; // ไม่มีอะไรเลย = "ไม่ได้ระบุ"
  }

  // เช็คว่าวัตถุดิบที่สูตรต้องการ มีในตู้เย็นพอไหม (เทียบชื่อ + จำนวน)
  bool _isIngredientAvailable(Map<String, dynamic> needed) {
    final neededName = (needed['name'] ?? '').toString().trim().toLowerCase(); // ชื่อที่ต้องการ
    final neededQty = _toNum(needed['use_quantity']); // จำนวนที่ต้องการ
    // รวมทุกลอตของวัตถุดิบชื่อนี้ (ซื้อซ้ำจะแยกเป็นคนละลอตตามหลัก FIFO)
    final match = widget.inventory
        .where((inv) => ingredientNameMatches(inv['name'], neededName))
        .toList();
    if (match.isEmpty) return false; // ไม่มีในตู้
    final haveQty = availableQuantity(widget.inventory, neededName); // รวมจำนวนทุกลอต
    return haveQty >= neededQty; // มีพอไหม
  }

  // ฟังก์ชันหักวัตถุดิบออกจาก Supabase
  Future<void> _startCooking() async {
    List<dynamic> detailedIngredients = _recipe['detailed_ingredients'] ?? [];

    // ให้ผู้ใช้ยืนยันก่อนว่าใช้ไปเท่าไหร่จริง (กดเลือกแบบกะด้วยตา ไม่ต้องชั่ง)
    // ค่าเริ่มต้นตามที่สูตรบอก — กดยกเลิกก็ไม่หักอะไรเลย
    final choices = await showDeductConfirmSheet( // เปิดแผ่นให้ผู้ใช้ยืนยันจำนวนที่ใช้
      context,
      inventory: widget.inventory,
      requests: [
        for (final needed in detailedIngredients)
          if ((needed['name'] ?? '').toString().trim().isNotEmpty &&
              // เครื่องปรุงพื้นฐานที่ไม่ได้เก็บในตู้เย็น -> ไม่ต้องหัก
              !(RecipeRepository.isStapleIngredient(
                    Map<String, dynamic>.from(needed),
                  ) &&
                  !widget.inventory.any(
                    (inv) => ingredientNameMatches(
                      inv['name'],
                      needed['name'].toString().trim().toLowerCase(),
                    ),
                  )))
            DeductRequest( // คำขอหักวัตถุดิบ 1 รายการ
              name: needed['name'].toString(),
              suggested: _toNum(needed['use_quantity']), // จำนวนตามสูตร
              unit: (needed['unit'] ?? '').toString(),
              isStaple: RecipeRepository.isStapleIngredient(
                Map<String, dynamic>.from(needed),
              ),
            ),
      ],
    );
    if (choices == null || !mounted) return; // กดยกเลิก -> ไม่หักอะไร

    setState(() => _isCooking = true); // เริ่มหัก

    try {
      final supabase = Supabase.instance.client;

      int deductedCount = 0; // นับที่หักสำเร็จ
      List<String> notFoundNames = []; // ชื่อที่หาไม่เจอในตู้
      // เก็บ error จริงตอนยิง update ไป Supabase แยกจากกรณี "หาไม่เจอในคลัง"
      // เพราะสาเหตุคนละแบบกัน (เช่น ฐานข้อมูลปฏิเสธสิทธิ์แก้ไข ไม่ใช่แค่หา
      // วัตถุดิบไม่เจอ) ผู้ใช้จะได้รู้ว่าจริงๆ แล้วเกิดอะไรขึ้นกันแน่
      List<String> updateErrors = [];

      // สำเนาคลังไว้หักในเครื่องด้วย จะได้เห็นจำนวนล่าสุดถ้าเมนูใช้วัตถุดิบ
      // ชื่อเดียวกันซ้ำ (ไม่แก้ลิสต์ของหน้าก่อนหน้าโดยตรง)
      final inventory = widget.inventory // ก๊อปของในตู้มาหักในเครื่อง
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // หักตามปริมาณที่ผู้ใช้ยืนยันแบบ FIFO (ลอตที่ใกล้หมดอายุ/เก่าที่สุดก่อน
      // ถ้าไม่พอหักลอตถัดไปต่อ) ผ่าน fridge_stock.dart
      for (final choice in choices) {
        if (choice.amount == null) { // ไม่มีในตู้
          notFoundNames.add(choice.name);
          continue;
        }
        if (choice.amount! <= 0) continue; // ผู้ใช้เลือก "ไม่ได้ใช้"

        final result = await deductIngredientFifo( // หักแบบ FIFO
          supabase: supabase,
          inventory: inventory,
          name: choice.name,
          amount: choice.amount!,
        );

        if (!result.found) { // หาไม่เจอ
          notFoundNames.add(choice.name);
        } else if (result.error != null) { // บันทึกไม่สำเร็จ
          updateErrors.add("${choice.name}: ${result.error}");
        } else { // สำเร็จ
          deductedCount++;
        }
      }

      if (mounted) {
        final hasNotFound = notFoundNames.isNotEmpty;
        final hasUpdateError = updateErrors.isNotEmpty;
        String message;
        Color bgColor;

        if (hasUpdateError) { // มี error จริงจากฐานข้อมูล
          // ฐานข้อมูลปฏิเสธการอัปเดตจริงๆ (เช่นสิทธิ์ไม่พอ) ต้องโชว์ error ตรงๆ
          // ไม่งั้นจะดูเหมือนกดแล้วไม่มีอะไรเกิดขึ้นเลย ทั้งที่จริงๆ error
          message =
              "หักวัตถุดิบไม่สำเร็จบางรายการ: ${updateErrors.join(' | ')}";
          bgColor = Colors.red; // [UI] สีแดง
        } else if (deductedCount == 0 && !hasNotFound) {
          // ผู้ใช้เลือก "ไม่ได้ใช้" ทุกรายการในหน้ายืนยัน
          message = "ทำอาหารเสร็จสิ้น! ไม่ได้หักวัตถุดิบออกจากตู้เย็น";
          bgColor = Colors.green; // [UI] สีเขียว
        } else if (deductedCount == 0) {
          // ไม่พบวัตถุดิบที่ตรงกันในคลังเลยสักชิ้น ไม่ควรบอกว่า "เรียบร้อยแล้ว"
          message =
              "ไม่พบวัตถุดิบที่ตรงกับในคลังเลย จึงยังไม่ได้หักอะไรออก "
              "(${notFoundNames.join(', ')})";
          bgColor = Colors.orange; // [UI] สีส้ม
        } else if (hasNotFound) {
          message =
              "หักวัตถุดิบไปแล้ว $deductedCount รายการ แต่หาไม่เจอในคลัง: "
              "${notFoundNames.join(', ')}";
          bgColor = Colors.orange;
        } else {
          message = "ทำอาหารเสร็จสิ้น! หักวัตถุดิบเรียบร้อยแล้ว 🍲";
          bgColor = Colors.green; // [UI] สีเขียว
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: bgColor),
        );
        // ถ้ามีที่หักสำเร็จอย่างน้อย 1 ชิ้น ค่อยบอกหน้าเดิมให้รีเฟรชตู้เย็น
        Navigator.pop(context, deductedCount > 0); // ปิดหน้า ส่ง true ถ้าหักไปอย่างน้อย 1 ชิ้น (หน้าก่อนจะรีเฟรช)
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
      if (mounted) setState(() => _isCooking = false); // หยุดโหลด
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
            content: Text(
              "ต้องการลบ \"$recipeName\" ออกจากคลังสูตรอาหารใช่ไหม",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("ยกเลิก"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red), // [UI] ปุ่มลบสีแดง
                child: const Text("ลบ"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return; // ไม่ยืนยัน หยุด

    setState(() => _isDeleting = true); // เริ่มลบ
    try {
      await RecipeRepository.deleteSavedRecipe(widget.recipe['id'] as Object); // ลบสูตรจากคลัง

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ลบสูตรอาหารเรียบร้อยแล้ว"), // [UI] แถบเขียว
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
    final recipe = _recipe; // สูตรปัจจุบัน
    final servingsText = (recipe['servings'] ?? '').toString().trim(); // จำนวนที่
    final timeText = (recipe['time'] ?? '').toString().trim(); // เวลาทำ
    // ขั้นตอนการทำ + ตำแหน่งขั้นตอนที่ AI คิดเพิ่ม (แสดงเป็นสีแดง)
    final steps = RecipeRepository.stepTextsOf(recipe);
    final aiSteps = RecipeRepository.aiStepIndexesOf(recipe);
    List<dynamic> detailedIngredients = recipe['detailed_ingredients'] ?? [];

    // เครื่องปรุงพื้นฐาน (ซอส น้ำปลา น้ำตาล ฯลฯ) แยกไว้ ไม่นับในสถานะวัตถุดิบ
    final allIngredients = [ // วัตถุดิบทั้งหมด
      for (final e in detailedIngredients) Map<String, dynamic>.from(e),
    ];
    final mainIngredients = [ // วัตถุดิบหลัก (ไม่ใช่เครื่องปรุงพื้นฐาน)
      for (final ing in allIngredients)
        if (!RecipeRepository.isStapleIngredient(ing)) ing,
    ];
    final stapleIngredients = [ // เครื่องปรุงพื้นฐาน
      for (final ing in allIngredients)
        if (RecipeRepository.isStapleIngredient(ing)) ing,
    ];
    final availableCount = mainIngredients.where(_isIngredientAvailable).length; // นับวัตถุดิบหลักที่มีในตู้

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
      bottomNavigationBar: AppBottomNav(current: widget.tab), // แถบเมนูล่าง ไฮไลต์ตามหน้าที่เปิดมา
      body: SafeArea(
        child: Column(
          children: [
            // เมนูแนะนำจาก AI (ยังไม่บันทึก = ไม่มี id) ไม่ต้องมีช่องค้นหาสูตรในคลัง
            // และใช้ไอคอนหมวกเชฟให้ตรงกับแท็บ "เมนูอาหาร"
            RecipeFlowHeader(
              title: widget.headerTitle,
              showSearch: _canDelete, // มี id ถึงแสดงช่องค้นหา
              icon: _canDelete ? null : const ChefIcon(size: 22), // ไม่มี id ใช้ไอคอนหมวกเชฟ
            ),
            const SizedBox(height: 15), // [UI] ระยะใต้หัว
            // ตอนแก้ไขวัตถุดิบ/ขั้นตอน ตรึงรูปที่ใช้สแกนไว้ด้านบน ไม่เลื่อนตาม
            // จะได้เทียบกับรูปได้ตลอด (ตอนดูสูตรปกติ รูปเลื่อนไปกับเนื้อหา)
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
                child: PrivateScanImage(
                  bucket: recipeScanImageBucket,
                  path: recipe['scan_image_path']?.toString(),
                  publicUrl: recipe['image_url']?.toString(), // รูปเมนูที่แนบเอง (ใช้เมื่อไม่มีรูปสแกน)
                  height: 150, // [UI] ความสูงรูปตอนแก้ไข
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้ายขวาของเนื้อหา
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ชื่อเมนู (กล่องขาวตรงกลาง ตามดีไซน์) แตะเพื่อเปลี่ยนชื่อ
                    RecipeNameBox(
                      name: (recipe['recipe_name'] ?? '').toString(),
                      onRename: _canEdit && !_isEditing && !_isSavingEdit // แตะเปลี่ยนชื่อได้เฉพาะตอนแก้ได้และไม่ได้แก้ส่วนอื่นอยู่
                          ? _renameRecipe
                          : null,
                    ),
                    const SizedBox(height: 20), // [UI] ระยะห่าง

                    // รูปสูตรที่ผู้ใช้สแกน (มีเฉพาะสูตรที่สแกนแล้วบันทึกหลังมีฟีเจอร์นี้)
                    // ไม่มีรูปสแกน -> แสดงรูปเมนูที่แนบตอนเขียนสูตรเอง (image_url) แทน
                    // ตอนแก้ไข รูปย้ายไปตรึงไว้ด้านบนแทน
                    if (!_isEditing)
                      PrivateScanImage(
                        bucket: recipeScanImageBucket,
                        path: recipe['scan_image_path']?.toString(),
                        publicUrl: recipe['image_url']?.toString(), // รูปเมนูที่แนบเอง (ใช้เมื่อไม่มีรูปสแกน)
                      ),

                    // สถานะวัตถุดิบ (ของจริงจากฐานข้อมูล ไม่ใช่ mock)
                    RecipeStatusBar( // แถบ "มีวัตถุดิบกี่อย่าง"
                      label: "สถานะวัตถุดิบ",
                      have: availableCount,
                      total: mainIngredients.length,
                    ),
                    const SizedBox(height: 20), // [UI] ระยะห่างระหว่างการ์ด

                    // วัตถุดิบที่ต้องใช้
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
                      decoration: BoxDecoration(
                        color: Colors.white, // [UI] พื้นขาว
                        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5, // [UI] ความฟุ้งเงา
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
                                  horizontal: 14, // [UI] ระยะในป้ายซ้ายขวา
                                  vertical: 8, // [UI] ระยะในป้ายบนล่าง
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D0), // [UI] สีป้าย (ครีม)
                                  borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
                                ),
                                child: const Text(
                                  "วัตถุดิบที่ต้องใช้",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14, // [UI] ขนาดป้าย
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (_canEdit && !_isEditing)
                                EditPillButton(onTap: _beginEditIngredients), // ปุ่ม "แก้ไข" (แสดงเมื่อแก้ได้)
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_editingIngredients) // โหมดแก้ -> ฟอร์มแก้วัตถุดิบ
                            ..._buildIngredientEditor()
                          else ...[ // โหมดดู -> รายการวัตถุดิบ
                            if (servingsText.isNotEmpty)
                              _infoLine(
                                Icons.restaurant_outlined,
                                'สำหรับ $servingsText',
                                estimated: recipe['servings_estimated'] == true,
                              ),
                            ...mainIngredients.map((ingMap) { // แถววัตถุดิบหลัก
                              final available = _isIngredientAvailable(ingMap); // มีในตู้ไหม
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10.0), // [UI] ระยะใต้แต่ละแถว
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 20, // [UI] ช่องไอคอนกว้าง 20
                                          child: available
                                              ? const CheckIcon(size: 18) // [UI] มี = ติ๊กถูก ขนาด 18
                                              : null,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          ingMap['name'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 15, // [UI] ขนาดชื่อวัตถุดิบ
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _formatQty(ingMap),
                                      style: TextStyle(
                                        color: Colors.grey.shade700, // [UI] ปริมาณสีเทา
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (stapleIngredients.isNotEmpty) ...[ // เครื่องปรุงพื้นฐาน (สีเทา)
                              const SizedBox(height: 4),
                              const StapleIngredientsHeader(),
                              for (final ing in stapleIngredients)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        child: Icon(
                                          Icons.kitchen_outlined,
                                          size: 16, // [UI] ไอคอนครัว ขนาด 16
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          (ing['name'] ?? '').toString(),
                                          style: TextStyle(
                                            fontSize: 15, // [UI] ขนาด 15
                                            color: Colors.grey.shade600, // [UI] สีเทา
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatQty(ing),
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ขั้นตอนการทำ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
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
                                    fontSize: 14, // [UI] ขนาดป้าย
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (_canEdit && !_isEditing)
                                EditPillButton(onTap: _beginEditSteps), // ปุ่ม "แก้ไข" ขั้นตอน
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_editingSteps) // โหมดแก้ -> ฟอร์มแก้ขั้นตอน
                            ..._buildStepsEditor()
                          else ...[
                            if (timeText.isNotEmpty)
                              _infoLine(
                                Icons.timer_outlined,
                                'ใช้เวลาประมาณ $timeText',
                                estimated: recipe['time_estimated'] == true,
                              ),
                            // ขั้นตอนที่ AI คิดเพิ่ม = ตัวหนังสือสีแดง + ป้าย "AI"
                            RecipeStepsView( // รายการขั้นตอน
                              steps: steps,
                              aiIndexes: aiSteps,
                              fontSize: 15, // [UI] ขนาดตัวอักษรขั้นตอน
                              spacing: 12, // [UI] ระยะห่างระหว่างขั้นตอน
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
              padding: const EdgeInsets.all(20), // [UI] ระยะในแถบปุ่ม
              decoration: const BoxDecoration(
                color: Colors.white, // [UI] พื้นขาว
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10, // [UI] ความฟุ้งเงา
                    offset: Offset(0, -3), // [UI] เงาเลื่อนขึ้นบน 3
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_canDelete) ...[ // มี id ถึงแสดงปุ่มลบ
                    SizedBox(
                      height: 55, // [UI] ขนาดปุ่มลบ 55x55
                      width: 55,
                      child: OutlinedButton(
                        onPressed: _isDeleting ? null : _deleteRecipe, // กำลังลบ = กดไม่ได้
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: Colors.redAccent), // [UI] ขอบแดง
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง 15
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
                                color: Colors.redAccent, // [UI] ไอคอนถังขยะสีแดง
                              ),
                      ),
                    ),
                    const SizedBox(width: 12), // [UI] ระยะปุ่มลบกับปุ่มทำอาหาร
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 55, // [UI] ความสูงปุ่มทำอาหาร
                      child: ElevatedButton(
                        // ระหว่างแก้ไข ให้บันทึก/ยกเลิกก่อน ค่อยกดทำอาหาร
                        onPressed: (_isCooking || _isEditing)
                            ? null
                            : _startCooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7D0), // [UI] สีปุ่ม (ครีม)
                          foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษร (ฟ้า)
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง 15
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
                                    size: 24, // [UI] ไอคอนหม้อ ขนาด 24
                                    color: Color(0xff5189C9),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    "Cooking (หักวัตถุดิบ)",
                                    style: TextStyle(
                                      fontSize: 18, // [UI] ขนาดตัวอักษร
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

  // บรรทัดข้อมูลสั้น (ไอคอน + ข้อความ + ป้าย AI ประมาณ)
  Widget _infoLine(IconData icon, String text, {bool estimated = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10), // [UI] ระยะรอบ
      child: RecipeInfoLine(icon: icon, text: text, estimated: estimated),
    );
  }

  // ฟอร์มแก้วัตถุดิบ (จำนวนที่ + แถววัตถุดิบ + ปุ่มเพิ่ม + ยกเลิก/บันทึก)
  List<Widget> _buildIngredientEditor() {
    return [
      StepperLine(
        label: 'จำนวนที่',
        stepper: NumberStepper(
          value: _servingsDraft,
          max: 50, // สูงสุด 50 ที่
          suffix: 'ที่',
          emptyLabel: 'ไม่ระบุ',
          onChanged: (v) => setState(() => _servingsDraft = v),
        ),
      ),
      const Divider(height: 16), // [UI] เส้นคั่น
      for (var i = 0; i < _ingDrafts.length; i++)
        IngredientEditRow(
          key: ObjectKey(_ingDrafts[i]), // รหัสเฉพาะของแถว
          index: i,
          nameController: _ingDrafts[i].name,
          qty: _ingDrafts[i].qty,
          unit: _ingDrafts[i].unit,
          onQtyChanged: (v) => setState(() => _ingDrafts[i].qty = v), // เปลี่ยนจำนวน
          onUnitChanged: (v) => setState(() { // เปลี่ยนหน่วย
            final d = _ingDrafts[i];
            d.unit = v;
            final max = maxForUnit(v); // หน่วย % ห้ามเกิน 100
            if (d.qty != null && d.qty! > max) d.qty = max;
          }),
          onRemove: _ingDrafts.length > 1 // เหลือแถวเดียวลบไม่ได้
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

  // ฟอร์มแก้ขั้นตอน (เวลาทำ + แถวขั้นตอน + ปุ่มเพิ่ม + ยกเลิก/บันทึก)
  List<Widget> _buildStepsEditor() {
    return [
      StepperLine(
        label: 'เวลาทำ',
        stepper: NumberStepper(
          value: _minutesDraft, // [UI] กด +/− ทีละ 5 นาที
          step: 5, // สูงสุด 600 นาที
          max: 600,
          suffix: 'นาที',
          emptyLabel: 'ไม่ระบุ',
          onChanged: (v) => setState(() => _minutesDraft = v?.round()),
        ),
      ),
      const Divider(height: 16),
      if (_stepDrafts.any((d) => d.isAi)) // มีขั้นที่ AI แต่ง -> แสดงคำอธิบาย
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
          onRemove: _stepDrafts.length > 1 // เหลือแถวเดียวลบไม่ได้
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

  // ปุ่ม "+ เพิ่ม..." ชิดซ้าย
  Widget _addRowButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18), // [UI] ไอคอน + ขนาด 18
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.black87,
          textStyle: const TextStyle(fontSize: 13), // [UI] ขนาดตัวอักษร
        ),
      ),
    );
  }

  /// ปุ่ม ยกเลิก / บันทึก ท้ายการ์ดที่กำลังแก้ไข
  Widget _editActions() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12), // [UI] มุมปุ่มโค้ง 12
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6), // [UI] ระยะบน
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44, // [UI] ความสูงปุ่ม
              child: OutlinedButton(
                onPressed: _isSavingEdit ? null : _endEdit, // ยกเลิก = ออกจากโหมดแก้ไข
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey.shade400), // [UI] ขอบเทา
                  shape: shape,
                ),
                child: const Text('ยกเลิก'),
              ),
            ),
          ),
          const SizedBox(width: 10), // [UI] ระยะระหว่างปุ่ม
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _isSavingEdit ? null : _saveEdit, // บันทึก
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRecipeLightBlue, // [UI] สีปุ่มบันทึก (ฟ้าอ่อน)
                  foregroundColor: Colors.black87,
                  elevation: 0, // [UI] ไม่มีเงา
                  shape: shape,
                ),
                icon: _isSavingEdit
                    ? const SizedBox(
                        width: 16, // [UI] ขนาดวงหมุน
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kRecipeBlue,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18), // [UI] ไอคอนติ๊ก ขนาด 18
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
