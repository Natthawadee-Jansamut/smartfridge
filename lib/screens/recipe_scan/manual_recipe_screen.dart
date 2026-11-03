import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';

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

  /// รูปสูตรที่ผู้ใช้สแกน (โหมด reviewDraft) — แสดงไว้ด้านบนให้เทียบตอนแก้
  final Uint8List? referenceImage;

  const ManualRecipeScreen({
    super.key,
    this.initialRecipe,
    this.mode = RecipeFormMode.create,
    this.showAiDisclaimer = false,
    this.referenceImage,
  }) : assert(
         mode == RecipeFormMode.create || initialRecipe != null,
         'โหมดแก้ไขต้องส่ง initialRecipe มาด้วย',
       );

  @override
  State<ManualRecipeScreen> createState() => _ManualRecipeScreenState();
}

class _IngredientRow {
  final TextEditingController name;
  num? qty; // ปรับด้วยปุ่ม +/− เท่านั้น (null = ไม่ได้ระบุ)
  String? unit;

  _IngredientRow({String name = '', this.qty, this.unit})
    : name = TextEditingController(text: name);

  void dispose() => name.dispose();
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
  int? _minutes; // เวลาทำ (นาที) — ปุ่ม +/−
  num? _servings; // จำนวนที่ — ปุ่ม +/−
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
      _minutes = RecipeRepository.minutesOf(r['time']);
      _servings = RecipeRepository.leadingNumber(r['servings']);
      for (final ing in RecipeRepository.ingredientsOf(r)) {
        final unit = (ing['unit'] ?? '').toString().trim();
        _ingredients.add(
          _IngredientRow(
            name: (ing['name'] ?? '').toString(),
            qty: RecipeRepository.parseQuantity(ing['use_quantity']) ??
                RecipeRepository.leadingNumber(ing['use_quantity']),
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
      ingredients.add({
        'name': ingName,
        'use_quantity': row.qty,
        'unit': row.unit ?? '',
      });
    }
    if (ingredients.isEmpty) {
      _snack('กรุณาเพิ่มวัตถุดิบอย่างน้อย 1 รายการ');
      return null;
    }

    final steps = _steps.where((s) => s.ctrl.text.trim().isNotEmpty).toList();

    return {
      ...?widget.initialRecipe,
      'recipe_name': name,
      'time': RecipeRepository.minutesText(_minutes),
      'servings': RecipeRepository.servingsText(_servings),
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
                    if (_isDraft && widget.referenceImage != null) ...[
                      ScannedImagePreview(
                        bytes: widget.referenceImage!,
                        height: 170,
                      ),
                      const SizedBox(height: 14),
                    ],
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
                    // เวลาทำ / จำนวนที่ — ปรับด้วยปุ่ม +/− เท่านั้น
                    RecipeSectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          _stepperLine(
                            'เวลาทำ',
                            NumberStepper(
                              value: _minutes,
                              step: 5,
                              max: 600,
                              suffix: 'นาที',
                              emptyLabel: 'ไม่ระบุ',
                              onChanged: (v) =>
                                  setState(() => _minutes = v?.round()),
                            ),
                          ),
                          const Divider(height: 8),
                          _stepperLine(
                            'จำนวนที่',
                            NumberStepper(
                              value: _servings,
                              max: 50,
                              suffix: 'ที่',
                              emptyLabel: 'ไม่ระบุ',
                              onChanged: (v) => setState(() => _servings = v),
                            ),
                          ),
                        ],
                      ),
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

  Widget _stepperLine(String label, Widget stepper) =>
      StepperLine(label: label, stepper: stepper);

  Widget _buildIngredientRow(int i) {
    final row = _ingredients[i];
    return IngredientEditRow(
      key: ObjectKey(row),
      index: i,
      nameController: row.name,
      qty: row.qty,
      unit: row.unit,
      onQtyChanged: (v) => setState(() => row.qty = v),
      onUnitChanged: (v) => setState(() {
        row.unit = v;
        // เปลี่ยนเป็น % แล้วค่าเกิน 100 -> ปัดลง
        final max = maxForUnit(v);
        if (row.qty != null && row.qty! > max) row.qty = max;
      }),
      onRemove: _ingredients.length > 1
          ? () => setState(() {
              _ingredients.removeAt(i);
              // dispose หลังเฟรมนี้ ไม่งั้น TextField ที่ยังค้างอยู่จะใช้ controller ที่ถูกทำลายแล้ว
              WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
            })
          : null,
    );
  }

  Widget _buildStepRow(int i) {
    final row = _steps[i];
    return StepEditRow(
      key: ObjectKey(row),
      index: i,
      controller: row.ctrl,
      isAi: row.isAi,
      onRemove: _steps.length > 1
          ? () => setState(() {
              _steps.removeAt(i);
              WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
            })
          : null,
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
