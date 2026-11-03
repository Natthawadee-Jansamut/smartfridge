import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';

/// หน่วยครัวที่เลือกได้ — รองรับทั้งน้ำหนัก, ช้อน/ถ้วย, นับชิ้น/ส่วน
/// และ "%" สำหรับกะด้วยสายตา (เช่น ใช้นม 50% ของขวด)
/// สัดส่วนอย่าง "ครึ่งหัว" ให้พิมพ์จำนวนเป็น 1/2 แล้วเลือกหน่วย "หัว"
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
  'หัว',
  'กลีบ',
  'เม็ด',
  'ต้น',
  'กำ',
  'แพ็ค',
  'ส่วน',
  '%',
];

/// โหมดของฟอร์มสูตรอาหาร
enum RecipeFormMode {
  /// เขียนสูตรใหม่ -> insert ลง Supabase แล้ว pop(true)
  /// ปุ่ม "สแกนใหม่" -> pop(AddRecipeOption.scan) ให้หน้าคลังสูตรพาไปหน้าสแกน
  create,

  /// แก้สูตรที่ AI สแกนมา (ยังไม่บันทึก) -> pop(Map ที่แก้แล้ว)
  reviewDraft,

  /// แก้สูตรที่บันทึกไว้แล้ว (จากปุ่ม "แก้ไข" ในหน้าคลังสูตร) -> update แล้ว pop(true)
  editSaved,
}

/// หน้า "เขียนสูตรอาหาร" / "แก้ไขสูตรอาหาร" (ตามดีไซน์ใน Figma)
class ManualRecipeScreen extends StatefulWidget {
  final Map<String, dynamic>? initialRecipe;
  final RecipeFormMode mode;
  final bool showAiDisclaimer;

  const ManualRecipeScreen({
    super.key,
    this.initialRecipe,
    this.mode = RecipeFormMode.create,
    this.showAiDisclaimer = false,
  }) : assert(
         mode == RecipeFormMode.create || initialRecipe != null,
         'โหมดแก้ไขต้องส่ง initialRecipe มาด้วย',
       );

  @override
  State<ManualRecipeScreen> createState() => _ManualRecipeScreenState();
}

class _IngredientRow {
  final TextEditingController name;
  final TextEditingController qty;
  String? unit;

  _IngredientRow({String name = '', String qty = '', this.unit})
    : name = TextEditingController(text: name),
      qty = TextEditingController(text: qty);

  void dispose() {
    name.dispose();
    qty.dispose();
  }
}

/// ช่องขั้นตอน 1 ช่อง — จำได้ว่าเป็นขั้นตอนที่ AI คิดเพิ่มหรือไม่
/// ถ้าผู้ใช้แก้ข้อความของขั้นตอน AI จะถือว่าตรวจแล้ว กลายเป็นขั้นตอนของผู้ใช้
class _StepRow {
  final TextEditingController ctrl;
  final String _aiText;
  bool isAi;

  _StepRow({String text = '', this.isAi = false})
    : ctrl = TextEditingController(text: text),
      _aiText = text.trim();

  /// คืน true ถ้าสถานะ AI เพิ่งเปลี่ยน (ต้อง setState)
  bool syncAiFlag() {
    if (isAi && ctrl.text.trim() != _aiText) {
      isAi = false;
      return true;
    }
    return false;
  }

  void dispose() => ctrl.dispose();
}

class _ManualRecipeScreenState extends State<ManualRecipeScreen> {
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _servingsCtrl = TextEditingController();
  final List<_IngredientRow> _ingredients = [];
  final List<_StepRow> _steps = [];

  Uint8List? _imageBytes; // รูปใหม่ที่เพิ่งเลือก
  String? _existingImageUrl; // รูปเดิมของสูตรที่บันทึกไว้ (โหมด editSaved)
  bool _removeExistingImage = false;
  bool _isSaving = false;

  bool get _isCreate => widget.mode == RecipeFormMode.create;
  bool get _isDraft => widget.mode == RecipeFormMode.reviewDraft;
  bool get _hasAiSteps => _steps.any((s) => s.isAi);

  _StepRow _newStep({String text = '', bool isAi = false}) {
    final row = _StepRow(text: text, isAi: isAi);
    row.ctrl.addListener(() {
      if (row.syncAiFlag() && mounted) setState(() {});
    });
    return row;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecipe;
    if (r != null) {
      _nameCtrl.text = (r['recipe_name'] ?? '').toString();
      _timeCtrl.text = (r['time'] ?? '').toString();
      _servingsCtrl.text = (r['servings'] ?? '').toString();
      for (final ing in RecipeRepository.ingredientsOf(r)) {
        final unit = (ing['unit'] ?? '').toString().trim();
        _ingredients.add(
          _IngredientRow(
            name: (ing['name'] ?? '').toString(),
            qty: RecipeRepository.formatNum(ing['use_quantity']),
            unit: unit.isEmpty ? null : unit,
          ),
        );
      }
      final aiIdx = RecipeRepository.aiStepIndexesOf(r);
      final texts = RecipeRepository.stepTextsOf(r);
      for (var i = 0; i < texts.length; i++) {
        _steps.add(_newStep(text: texts[i], isAi: aiIdx.contains(i)));
      }
      if (widget.mode == RecipeFormMode.editSaved) {
        final url = (r['image_url'] ?? '').toString().trim();
        _existingImageUrl = url.isEmpty ? null : url;
      }
    }
    // ฟอร์มเปล่าเริ่มที่ 3 ช่อง ตาม Figma
    while (_ingredients.length < 3) {
      _ingredients.add(_IngredientRow());
    }
    while (_steps.length < 3) {
      _steps.add(_newStep());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _timeCtrl.dispose();
    _servingsCtrl.dispose();
    for (final r in _ingredients) {
      r.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  void _snack(String text, {Color color = Colors.red}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // -------------------------------------------------------------- Image

  Future<void> _pickImage() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายภาพ'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากคลังรูปภาพ'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_imageBytes != null || _existingImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'ลบรูปภาพ',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      setState(() {
        _imageBytes = null;
        if (_existingImageUrl != null) {
          _existingImageUrl = null;
          _removeExistingImage = true;
        }
      });
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) _snack('เปิดรูปภาพไม่สำเร็จ: $e');
    }
  }

  // --------------------------------------------------------------- Save

  /// รวมข้อมูลในฟอร์มเป็น Map (รูปแบบเดียวกับสูตรที่ AI สแกน)
  /// คืน null ถ้าข้อมูลยังไม่ครบ (และแจ้งผู้ใช้แล้ว)
  Map<String, dynamic>? _collectRecipe() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('กรุณากรอกชื่อเมนู');
      return null;
    }

    final ingredients = <Map<String, dynamic>>[];
    for (final row in _ingredients) {
      final ingName = row.name.text.trim();
      if (ingName.isEmpty) continue;
      final qtyText = row.qty.text.trim();
      final qty = RecipeRepository.parseQuantity(qtyText);
      if (qtyText.isNotEmpty && qty == null) {
        _snack('จำนวนของ "$ingName" ไม่ถูกต้อง (ใช้ตัวเลข เช่น 2, 0.5 หรือ 1/2)');
        return null;
      }
      ingredients.add({
        'name': ingName,
        'use_quantity': qty,
        'unit': row.unit ?? '',
      });
    }
    if (ingredients.isEmpty) {
      _snack('กรุณาเพิ่มวัตถุดิบอย่างน้อย 1 รายการ');
      return null;
    }

    final steps = _steps.where((s) => s.ctrl.text.trim().isNotEmpty).toList();
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();

    return {
      ...?widget.initialRecipe,
      'recipe_name': name,
      'time': orNull(_timeCtrl.text),
      'servings': orNull(_servingsCtrl.text),
      'ingredients_used': ingredients.map((e) => e['name']).toList(),
      'detailed_ingredients': ingredients,
      'instructions': [
        for (var i = 0; i < steps.length; i++)
          '${i + 1}. ${steps[i].ctrl.text.trim()}',
      ],
      'ai_step_indexes': [
        for (var i = 0; i < steps.length; i++)
          if (steps[i].isAi) i,
      ],
    };
  }

  Future<void> _onPrimary() async {
    FocusScope.of(context).unfocus();
    final recipe = _collectRecipe();
    if (recipe == null) return;

    if (_isDraft) {
      Navigator.pop(context, recipe);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final warnings = _isCreate
          ? await RecipeRepository.saveRecipe(recipe, imageBytes: _imageBytes)
          : await RecipeRepository.updateRecipe(
              widget.initialRecipe!['id'] as Object,
              recipe,
              imageBytes: _imageBytes,
              removeImage: _removeExistingImage,
            );
      if (!mounted) return;
      final done = _isCreate
          ? 'บันทึกสูตรอาหารเรียบร้อยแล้ว 📖'
          : 'บันทึกการแก้ไขเรียบร้อยแล้ว ✏️';
      _snack(
        warnings.isEmpty ? done : 'บันทึกแล้ว แต่${warnings.join(' และ')}',
        color: warnings.isEmpty ? Colors.green : Colors.orange,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack('บันทึกไม่สำเร็จ: $e');
    }
  }

  void _onSecondary() {
    if (_isCreate) {
      Navigator.pop(context, AddRecipeOption.scan);
    } else {
      Navigator.pop(context);
    }
  }

  // -------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecipeBg,
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(
              title: _isCreate ? 'เขียนสูตรอาหาร' : 'แก้ไขสูตรอาหาร',
            ),
            const SizedBox(height: 15),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (widget.showAiDisclaimer || _hasAiSteps) ...[
                      const AiDisclaimerBanner(),
                      const SizedBox(height: 14),
                    ],
                    if (!_isDraft) ...[
                      _buildImagePicker(),
                      const SizedBox(height: 18),
                    ],
                    _label('ชื่อเมนู'),
                    _plainField(_nameCtrl, 'เช่น ผัดกะเพราไก่'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('เวลาทำ'),
                              _plainField(_timeCtrl, 'เช่น 15 นาที'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('จำนวนที่'),
                              _plainField(_servingsCtrl, 'เช่น 1 ที่'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('วัตถุดิบที่ต้องใช้'),
                    RecipeSectionCard(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < _ingredients.length; i++)
                            _buildIngredientRow(i),
                          _addButton('เพิ่มวัตถุดิบ', () {
                            setState(() => _ingredients.add(_IngredientRow()));
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('ขั้นตอนการทำ'),
                    RecipeSectionCard(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                      child: Column(
                        children: [
                          if (_hasAiSteps)
                            const AiStepsNote(
                              text:
                                  'ข้อความสีแดง = ขั้นตอนที่ AI คิดเพิ่มให้ ถ้าแก้ไขข้อความ จะถือว่าเป็นขั้นตอนของคุณ',
                            ),
                          for (var i = 0; i < _steps.length; i++)
                            _buildStepRow(i),
                          _addButton('เพิ่มขั้นตอน', () {
                            setState(() => _steps.add(_newStep()));
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            RecipeBottomActions(
              secondaryLabel: _isCreate ? 'สแกนใหม่' : 'ยกเลิก',
              onSecondary: _onSecondary,
              primaryLabel: switch (widget.mode) {
                RecipeFormMode.create => 'บันทึกสูตร',
                RecipeFormMode.reviewDraft => 'ใช้การแก้ไข',
                RecipeFormMode.editSaved => 'บันทึกการแก้ไข',
              },
              onPrimary: _onPrimary,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pickImage,
        child: (_imageBytes == null && _existingImageUrl == null)
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: kRecipeYellow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kRecipeYellowBorder),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 30,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'เพิ่มรูปภาพเมนูอาหาร',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'แตะเพื่อเลือกรูปภาพหรือถ่ายภาพ',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  if (_imageBytes != null)
                    Image.memory(
                      _imageBytes!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  else
                    Image.network(
                      _existingImageUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.black38,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Colors.black87,
      ),
    ),
  );

  Widget _plainField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kRecipeBlue, width: 1.5),
        ),
      ),
    );
  }

  InputDecoration _boxDecoration(
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
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      prefixIcon: prefix,
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: isAi ? kAiRed.withOpacity(0.5) : Colors.grey.shade400,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: isAi ? kAiRed : kRecipeBlue,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _removeButton(VoidCallback? onTap) {
    return SizedBox(
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
  }

  Widget _buildIngredientRow(int i) {
    final row = _ingredients[i];
    final units = <String>{
      ...kRecipeUnits,
      if (row.unit != null && row.unit!.isNotEmpty) row.unit!,
    }.toList();

    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: TextField(
              controller: row.name,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 13),
              decoration: _boxDecoration('ชื่อวัตถุดิบ'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.qty,
              // ใช้คีย์บอร์ดตัวอักษรเพื่อให้พิมพ์เศษส่วน เช่น 1/2 ได้
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
              decoration: _boxDecoration('จำนวน'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Container(
              height: 40,
              padding: const EdgeInsets.only(left: 8, right: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: (row.unit == null || row.unit!.isEmpty)
                      ? null
                      : row.unit,
                  isExpanded: true,
                  isDense: true,
                  hint: Text(
                    'หน่วย',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
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
                  onChanged: (v) => setState(() => row.unit = v),
                ),
              ),
            ),
          ),
          _removeButton(
            _ingredients.length > 1
                ? () => setState(() {
                    _ingredients.removeAt(i);
                    // dispose หลังเฟรมนี้ ไม่งั้น TextField ที่ยังค้างอยู่จะใช้ controller ที่ถูกทำลายแล้ว
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => row.dispose(),
                    );
                  })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int i) {
    final row = _steps[i];
    final color = row.isAi ? kAiRed : Colors.black87;
    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: row.ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 13, height: 1.4, color: color),
              decoration: _boxDecoration(
                'อธิบายขั้นตอน',
                isAi: row.isAi,
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Text(
                    '${i + 1}.',
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                suffix: row.isAi
                    ? const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: AiChip(),
                      )
                    : null,
              ),
            ),
          ),
          _removeButton(
            _steps.length > 1
                ? () => setState(() {
                    _steps.removeAt(i);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => row.dispose(),
                    );
                  })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback onTap) {
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
}
