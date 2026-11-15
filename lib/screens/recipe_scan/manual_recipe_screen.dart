import 'dart:typed_data'; // Uint8List (ไฟล์รูป)

import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:image_picker/image_picker.dart'; // เปิดกล้อง/คลังรูป

import 'package:test_app/services/recipe_repository.dart'; // บันทึก/แก้สูตร
import 'package:test_app/widgets/add_recipe_widgets.dart'; // วิดเจ็ตฟอร์มสูตร (แถววัตถุดิบ ปุ่ม +/− ฯลฯ)
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
  final Map<String, dynamic>? initialRecipe; // สูตรเริ่มต้น (โหมดแก้ไข)
  final RecipeFormMode mode; // โหมดของฟอร์ม
  final bool showAiDisclaimer; // แสดงคำเตือน AI ไหม

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

// ข้อมูลแถววัตถุดิบ 1 แถว
class _IngredientRow {
  final TextEditingController name; // ช่องชื่อวัตถุดิบ
  num? qty; // ปรับด้วยปุ่ม +/− เท่านั้น (null = ไม่ได้ระบุ)
  String? unit; // หน่วย

  _IngredientRow({String name = '', this.qty, this.unit})
    : name = TextEditingController(text: name);

  void dispose() => name.dispose(); // คืนหน่วยความจำ
}

/// ช่องขั้นตอน 1 ช่อง — จำได้ว่าเป็นขั้นตอนที่ AI คิดเพิ่มหรือไม่
/// ถ้าผู้ใช้แก้ข้อความของขั้นตอน AI จะถือว่าตรวจแล้ว กลายเป็นขั้นตอนของผู้ใช้
class _StepRow {
  final TextEditingController ctrl; // ช่องข้อความขั้นตอน
  final String _aiText; // ข้อความเดิมที่ AI เขียน
  bool isAi; // เป็นขั้นตอนที่ AI แต่งอยู่ไหม

  _StepRow({String text = '', this.isAi = false})
    : ctrl = TextEditingController(text: text),
      _aiText = text.trim();

  /// คืน true ถ้าสถานะ AI เพิ่งเปลี่ยน (ต้อง setState)
  bool syncAiFlag() {
    if (isAi && ctrl.text.trim() != _aiText) { // แก้ข้อความจนไม่ตรงของ AI แล้ว
      isAi = false; // ไม่นับเป็นขั้นตอนของ AI อีก
      return true;
    }
    return false;
  }

  void dispose() => ctrl.dispose();
}

class _ManualRecipeScreenState extends State<ManualRecipeScreen> {
  final _picker = ImagePicker(); // ตัวเปิดกล้อง/คลังรูป
  final _nameCtrl = TextEditingController(); // ช่องชื่อเมนู
  int? _minutes; // เวลาทำ (นาที) — ปุ่ม +/−
  num? _servings; // จำนวนที่ — ปุ่ม +/−
  final List<_IngredientRow> _ingredients = []; // รายการแถววัตถุดิบ
  final List<_StepRow> _steps = []; // รายการแถวขั้นตอน

  Uint8List? _imageBytes; // รูปใหม่ที่เพิ่งเลือก
  String? _existingImageUrl; // รูปเดิมของสูตรที่บันทึกไว้ (โหมด editSaved)
  bool _removeExistingImage = false; // ผู้ใช้กดลบรูปเดิม
  bool _isSaving = false; // กำลังบันทึกไหม

  bool get _isCreate => widget.mode == RecipeFormMode.create; // โหมดเขียนใหม่
  bool get _isDraft => widget.mode == RecipeFormMode.reviewDraft; // โหมดตรวจร่างจาก AI
  bool get _hasAiSteps => _steps.any((s) => s.isAi); // มีขั้นตอนที่ AI แต่งไหม

  // สร้างแถวขั้นตอนใหม่ และคอยเช็คทุกครั้งที่พิมพ์ว่ายังเป็นข้อความของ AI ไหม
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
    final r = widget.initialRecipe; // สูตรเริ่มต้น
    if (r != null) { // มีสูตร -> ใส่ข้อมูลลงฟอร์ม
      _nameCtrl.text = (r['recipe_name'] ?? '').toString();
      _minutes = RecipeRepository.minutesOf(r['time']); // "30 นาที" -> 30
      _servings = RecipeRepository.leadingNumber(r['servings']); // "2 ที่" -> 2
      for (final ing in RecipeRepository.ingredientsOf(r)) { // ใส่วัตถุดิบทีละแถว
        final unit = (ing['unit'] ?? '').toString().trim();
        _ingredients.add(
          _IngredientRow(
            name: (ing['name'] ?? '').toString(),
            qty:
                RecipeRepository.parseQuantity(ing['use_quantity']) ??
                RecipeRepository.leadingNumber(ing['use_quantity']),
            unit: unit.isEmpty ? null : unit,
          ),
        );
      }
      final aiIdx = RecipeRepository.aiStepIndexesOf(r);
      final texts = RecipeRepository.stepTextsOf(r);
      for (var i = 0; i < texts.length; i++) { // ใส่ขั้นตอนทีละแถว
        _steps.add(_newStep(text: texts[i], isAi: aiIdx.contains(i)));
      }
      if (widget.mode == RecipeFormMode.editSaved) { // โหมดแก้สูตรที่บันทึกแล้ว -> โหลดรูปเดิม
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
  void dispose() { // ปิดหน้า คืนหน่วยความจำทุกช่อง
    _nameCtrl.dispose();
    for (final r in _ingredients) {
      r.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  // แถบข้อความด้านล่างจอ (ค่าเริ่มต้นสีแดง)
  void _snack(String text, {Color color = Colors.red}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // -------------------------------------------------------------- Image

  // กดช่องรูป -> เลือกถ่ายภาพ / เลือกจากคลัง / ลบรูป
  Future<void> _pickImage() async {
    final action = await showModalBottomSheet<String>( // เปิดแผ่นเมนูด้านล่าง
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)), // [UI] มุมบนโค้ง 24
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined), // [UI] ไอคอนกล้อง
              title: const Text('ถ่ายภาพ'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined), // [UI] ไอคอนคลังรูป
              title: const Text('เลือกจากคลังรูปภาพ'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_imageBytes != null || _existingImageUrl != null) // มีรูปอยู่ถึงจะแสดงปุ่มลบ
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red), // [UI] ไอคอนถังขยะสีแดง
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
    if (action == 'remove') { // เลือก "ลบรูป"
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
      final file = await _picker.pickImage( // เปิดกล้อง/คลังรูป
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1200, // ย่อรูปกว้างไม่เกิน 1200px
        imageQuality: 80, // คุณภาพ 80%
      );
      if (file == null) return;
      final bytes = await file.readAsBytes(); // อ่านรูปเป็นไบต์
      if (mounted) setState(() => _imageBytes = bytes);
    } catch (e) {
      if (mounted) _snack('เปิดรูปภาพไม่สำเร็จ: $e');
    }
  }

  // --------------------------------------------------------------- Save

  /// รวมข้อมูลในฟอร์มเป็น Map (รูปแบบเดียวกับสูตรที่ AI สแกน)
  /// คืน null ถ้าข้อมูลยังไม่ครบ (และแจ้งผู้ใช้แล้ว)
  Map<String, dynamic>? _collectRecipe() {
    final name = _nameCtrl.text.trim(); // ชื่อเมนู
    if (name.isEmpty) { // ไม่มีชื่อ -> เตือน
      _snack('กรุณากรอกชื่อเมนู');
      return null;
    }

    final ingredients = <Map<String, dynamic>>[]; // รวบรวมวัตถุดิบ
    for (final row in _ingredients) {
      final ingName = row.name.text.trim();
      if (ingName.isEmpty) continue; // ข้ามแถวที่ไม่ได้กรอกชื่อ
      ingredients.add({
        'name': ingName,
        'use_quantity': row.qty,
        'unit': row.unit ?? '',
      });
    }
    if (ingredients.isEmpty) { // ไม่มีวัตถุดิบเลย -> เตือน
      _snack('กรุณาเพิ่มวัตถุดิบอย่างน้อย 1 รายการ');
      return null;
    }

    final steps = _steps.where((s) => s.ctrl.text.trim().isNotEmpty).toList(); // ขั้นตอนที่ไม่ว่าง
    final time = RecipeRepository.minutesText(_minutes); // 30 -> "30 นาที"
    final servings = RecipeRepository.servingsText(_servings); // 2 -> "2 ที่"
    final initial = widget.initialRecipe;

    return {
      ...?initial, // ข้อมูลเดิมทั้งหมด (ถ้ามี) แล้วเขียนทับด้วยค่าใหม่
      'recipe_name': name,
      'time': time,
      'servings': servings,
      // ผู้ใช้เปลี่ยนค่าเอง -> ไม่ใช่ค่าที่ AI ประมาณแล้ว
      'time_estimated':
          initial?['time_estimated'] == true &&
          RecipeRepository.minutesText(
                RecipeRepository.minutesOf(initial?['time']),
              ) ==
              time,
      'servings_estimated':
          initial?['servings_estimated'] == true &&
          RecipeRepository.servingsText(
                RecipeRepository.leadingNumber(initial?['servings']),
              ) ==
              servings,
      'ingredients_used': ingredients.map((e) => e['name']).toList(),
      'detailed_ingredients': ingredients,
      'instructions': [ // ขั้นตอน ใส่เลขข้อ
        for (var i = 0; i < steps.length; i++)
          '${i + 1}. ${steps[i].ctrl.text.trim()}',
      ],
      'ai_step_indexes': [ // ตำแหน่งขั้นตอนที่ AI แต่ง
        for (var i = 0; i < steps.length; i++)
          if (steps[i].isAi) i,
      ],
    };
  }

  // กดปุ่มหลัก (บันทึก / ใช้การแก้ไข)
  Future<void> _onPrimary() async {
    FocusScope.of(context).unfocus(); // หุบคีย์บอร์ด
    final recipe = _collectRecipe(); // รวบรวมข้อมูลในฟอร์ม
    if (recipe == null) return; // ข้อมูลไม่ครบ หยุด

    if (_isDraft) { // โหมดตรวจร่าง -> ส่งสูตรกลับไปหน้าก่อน (ยังไม่บันทึก)
      Navigator.pop(context, recipe);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final warnings = _isCreate
          ? await RecipeRepository.saveRecipe(recipe, imageBytes: _imageBytes) // เขียนใหม่ -> บันทึกสูตรใหม่
          : await RecipeRepository.updateRecipe( // แก้สูตรเดิม -> อัปเดตสูตร
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
        color: warnings.isEmpty ? Colors.green : Colors.orange, // [UI] ไม่มีคำเตือน = เขียว, มีคำเตือน = ส้ม
      );
      Navigator.pop(context, true); // ปิดหน้า ส่ง true = บันทึกแล้ว
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack('บันทึกไม่สำเร็จ: $e');
    }
  }

  // กดปุ่มรอง: โหมดเขียนใหม่ = ไปสแกนแทน, โหมดอื่น = ยกเลิก
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
      backgroundColor: kRecipeBg, // [UI] สีพื้นหลัง
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan), // แถบเมนูล่าง
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(
              title: _isCreate ? 'เขียนสูตรอาหาร' : 'แก้ไขสูตรอาหาร',
            ),
            const SizedBox(height: 15), // [UI] ระยะใต้หัว
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(), // แตะที่ว่างเพื่อหุบคีย์บอร์ด
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), // [UI] ระยะรอบฟอร์ม
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag, // [UI] เลื่อนแล้วคีย์บอร์ดหุบ
                  children: [
                    if (_isDraft && widget.referenceImage != null) ...[ // โหมดตรวจร่าง -> แสดงรูปต้นฉบับไว้เทียบ
                      ScannedImagePreview(
                        bytes: widget.referenceImage!,
                        height: 170, // [UI] ความสูงรูปต้นฉบับ
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (widget.showAiDisclaimer || _hasAiSteps) ...[ // มี AI เกี่ยว -> แสดงคำเตือน
                      const AiDisclaimerBanner(),
                      const SizedBox(height: 14),
                    ],
                    if (!_isDraft) ...[ // โหมดอื่นนอกจากตรวจร่าง -> มีช่องเพิ่มรูป
                      _buildImagePicker(),
                      const SizedBox(height: 18),
                    ],
                    _label('ชื่อเมนู'),
                    _plainField(_nameCtrl, 'เช่น ผัดกะเพราไก่'),
                    const SizedBox(height: 12),
                    // เวลาทำ / จำนวนที่ — ปรับด้วยปุ่ม +/− เท่านั้น
                    RecipeSectionCard( // การ์ดเวลาทำ/จำนวนที่
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, // [UI] ระยะในซ้ายขวา
                        vertical: 8, // [UI] ระยะในบนล่าง
                      ),
                      child: Column(
                        children: [
                          _stepperLine(
                            'เวลาทำ',
                            NumberStepper(
                              value: _minutes,
                              step: 5, // [UI] กด +/− ทีละ 5 นาที
                              max: 600, // สูงสุด 600 นาที
                              suffix: 'นาที',
                              emptyLabel: 'ไม่ระบุ',
                              onChanged: (v) =>
                                  setState(() => _minutes = v?.round()),
                            ),
                          ),
                          const Divider(height: 8), // [UI] เส้นคั่น
                          _stepperLine(
                            'จำนวนที่',
                            NumberStepper(
                              value: _servings,
                              max: 50, // สูงสุด 50 ที่
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
                    RecipeSectionCard( // การ์ดวัตถุดิบ
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 4), // [UI] ระยะใน ซ้าย 10 บน 14 ขวา 10 ล่าง 4
                      child: Column(
                        children: [
                          for (var i = 0; i < _ingredients.length; i++)
                            _buildIngredientRow(i),
                          _addButton('เพิ่มวัตถุดิบ', () { // ปุ่ม "+ เพิ่มวัตถุดิบ"
                            setState(() => _ingredients.add(_IngredientRow()));
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('ขั้นตอนการทำ'),
                    RecipeSectionCard( // การ์ดขั้นตอน
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
                          _addButton('เพิ่มขั้นตอน', () { // ปุ่ม "+ เพิ่มขั้นตอน"
                            setState(() => _steps.add(_newStep()));
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            RecipeBottomActions( // ปุ่มด้านล่าง
              secondaryLabel: _isCreate ? 'สแกนใหม่' : 'ยกเลิก',
              onSecondary: _onSecondary,
              primaryLabel: switch (widget.mode) { // ข้อความปุ่มหลักตามโหมด
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

  // ช่องเพิ่มรูปเมนู (ยังไม่มีรูป = ไอคอนกล้อง, มีรูปแล้ว = แสดงรูป)
  Widget _buildImagePicker() {
    return Material(
      color: Colors.white, // [UI] พื้นขาว
      elevation: 1, // [UI] เงาบาง
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
      clipBehavior: Clip.antiAlias, // ตัดรูปให้โค้งตามมุม
      child: InkWell(
        onTap: _pickImage,
        child: (_imageBytes == null && _existingImageUrl == null)
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 22), // [UI] ความสูงช่องว่าง
                child: Column(
                  children: [
                    Container(
                      width: 56, // [UI] ขนาดกล่องไอคอน
                      height: 56,
                      decoration: BoxDecoration(
                        color: kRecipeYellow, // [UI] สีเหลือง
                        borderRadius: BorderRadius.circular(14), // [UI] มุมโค้ง 14
                        border: Border.all(color: kRecipeYellowBorder),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        size: 30, // [UI] ไอคอนขนาด 30
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'เพิ่มรูปภาพเมนูอาหาร',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15, // [UI] ขนาดข้อความ
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'แตะเพื่อเลือกรูปภาพหรือถ่ายภาพ',
                      style: TextStyle(fontSize: 12, color: Colors.black54), // [UI] ข้อความเล็กสีเทา
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  if (_imageBytes != null)
                    Image.memory( // รูปที่เพิ่งเลือก
                      _imageBytes!,
                      height: 180, // [UI] ความสูงรูป
                      width: double.infinity,
                      fit: BoxFit.cover, // [UI] ครอบให้เต็มกรอบ
                    )
                  else
                    Image.network( // รูปเดิมจากอินเทอร์เน็ต
                      _existingImageUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container( // โหลดรูปไม่ได้ -> แสดงไอคอนรูปเสีย
                        height: 180,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.black38,
                        ),
                      ),
                    ),
                  Positioned( // ไอคอนดินสอมุมขวาบนของรูป
                    top: 10, // [UI] ห่างขอบบน 10
                    right: 10, // [UI] ห่างขอบขวา 10
                    child: Container(
                      padding: const EdgeInsets.all(6), // [UI] ระยะรอบไอคอน
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_outlined, size: 18), // [UI] ไอคอนขนาด 18
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ป้ายหัวข้อของแต่ละส่วน
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8), // [UI] ระยะรอบป้าย
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15, // [UI] ขนาดหัวข้อ
        color: Colors.black87,
      ),
    ),
  );

  // ช่องกรอกข้อความธรรมดา (ชื่อเมนู)
  Widget _plainField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      textInputAction: TextInputAction.next, // [UI] ปุ่มบนคีย์บอร์ด = ถัดไป
      style: const TextStyle(fontSize: 14), // [UI] ขนาดตัวอักษร
      decoration: InputDecoration(
        isDense: true, // [UI] แบบกระชับ
        filled: true,
        fillColor: Colors.white, // [UI] พื้นขาว
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500), // [UI] สีข้อความจางตอนว่าง
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, // [UI] ระยะในซ้ายขวา
          vertical: 13, // [UI] ระยะในบนล่าง
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
          borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบปกติ
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kRecipeBlue, width: 1.5), // [UI] ตอนกำลังพิมพ์ = ขอบฟ้าหนา 1.5
        ),
      ),
    );
  }

  // แถว ป้ายชื่อ + ปุ่ม +/−
  Widget _stepperLine(String label, Widget stepper) =>
      StepperLine(label: label, stepper: stepper);

  // สร้างแถววัตถุดิบลำดับที่ i
  Widget _buildIngredientRow(int i) {
    final row = _ingredients[i];
    return IngredientEditRow(
      key: ObjectKey(row), // รหัสเฉพาะของแถว (กันสลับข้อมูลตอนลบแถว)
      index: i,
      nameController: row.name,
      qty: row.qty,
      unit: row.unit,
      onQtyChanged: (v) => setState(() => row.qty = v), // เปลี่ยนจำนวน
      onUnitChanged: (v) => setState(() { // เปลี่ยนหน่วย
        row.unit = v;
        // เปลี่ยนเป็น % แล้วค่าเกิน 100 -> ปัดลง
        final max = maxForUnit(v);
        if (row.qty != null && row.qty! > max) row.qty = max;
      }),
      onRemove: _ingredients.length > 1 // เหลือแถวเดียวจะลบไม่ได้
          ? () => setState(() {
              _ingredients.removeAt(i);
              // dispose หลังเฟรมนี้ ไม่งั้น TextField ที่ยังค้างอยู่จะใช้ controller ที่ถูกทำลายแล้ว
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => row.dispose(),
              );
            })
          : null,
    );
  }

  // สร้างแถวขั้นตอนลำดับที่ i
  Widget _buildStepRow(int i) {
    final row = _steps[i];
    return StepEditRow(
      key: ObjectKey(row),
      index: i,
      controller: row.ctrl,
      isAi: row.isAi,
      onRemove: _steps.length > 1 // เหลือแถวเดียวจะลบไม่ได้
          ? () => setState(() {
              _steps.removeAt(i);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => row.dispose(),
              );
            })
          : null,
    );
  }

  // ปุ่ม "+ เพิ่ม..." ชิดซ้าย
  Widget _addButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft, // [UI] ชิดซ้าย
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add, size: 18), // [UI] ไอคอน + ขนาด 18
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.black87, // [UI] สีตัวอักษร
          textStyle: const TextStyle(fontSize: 13), // [UI] ขนาดตัวอักษร
        ),
      ),
    );
  }
}
