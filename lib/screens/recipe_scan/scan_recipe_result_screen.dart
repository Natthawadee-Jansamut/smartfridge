import 'dart:typed_data'; // Uint8List (ไฟล์รูป)

import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/services/recipe_ai_service.dart'; // เรียก AI สแกนสูตร
import 'package:test_app/services/recipe_repository.dart'; // บันทึก/ดึงสูตร
import 'package:test_app/widgets/add_recipe_widgets.dart'; // วิดเจ็ตหน้าสูตร (การ์ด ปุ่ม ป้าย)
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/recipe_scan/manual_recipe_screen.dart'; // หน้าแก้ไขสูตร

/// หน้าตรวจสอบสูตรที่ AI สแกน/สร้างมา (ตามดีไซน์ใน Figma: "สูตรเมนูอาหาร")
/// - เทียบวัตถุดิบที่สูตรต้องใช้กับของจริงในตู้เย็น (Supabase) แบบสด
/// - ปุ่ม "แก้ไข" เปิดฟอร์มที่กรอกข้อมูลจาก AI ไว้ให้แล้ว
/// - แสดงคำเตือน AI ชัดเจนก่อนบันทึก
///
/// ผลลัพธ์ที่ pop กลับ: true = บันทึกแล้ว, false = กดสแกนใหม่/สร้างใหม่, null = ย้อนกลับ
class ScanRecipeResultScreen extends StatefulWidget {
  final Map<String, dynamic> recipe; // สูตรที่จะแสดง
  final bool isAiGenerated; // สูตรนี้มาจาก AI ไหม (แสดงคำเตือน)
  final String retryLabel; // ข้อความปุ่มรอง (เช่น "สแกนใหม่")

  /// รูปสูตรที่ผู้ใช้อัปโหลด — แสดงด้านบนให้เทียบกับผลที่ AI อ่านได้
  final Uint8List? imageBytes;

  /// SHA-256 ของรูปที่สแกน — บันทึกลง recipes.image_hash ตอนสร้างสูตรใหม่
  final String? imageHash;

  /// true = [recipe] เป็นสูตรที่มีอยู่แล้วในฐานข้อมูล (เจอจาก image_hash หรือชื่อเมนู)
  final bool fromDatabase;

  /// สูตรที่ AI อ่านจากรูป — มีเฉพาะตอนที่เจอสูตรในฐานข้อมูลจากชื่อเมนู
  /// ให้ผู้ใช้กดเปลี่ยนไปใช้สูตรจากรูปแทนได้
  final Map<String, dynamic>? scannedRecipe;

  /// สูตรในระบบที่เจอจากชื่อเมนู/รูปเดียวกัน — ให้ผู้ใช้สลับกลับมาใช้ได้
  /// แม้จะเลือกให้ AI สร้างสูตรไปแล้ว (ถ้า [fromDatabase] จะรวม [recipe] ให้เอง)
  final List<Map<String, dynamic>> systemRecipes;

  const ScanRecipeResultScreen({
    super.key,
    required this.recipe,
    this.isAiGenerated = true,
    this.retryLabel = 'สแกนใหม่',
    this.imageBytes,
    this.imageHash,
    this.fromDatabase = false,
    this.scannedRecipe,
    this.systemRecipes = const [],
  });

  @override
  State<ScanRecipeResultScreen> createState() => _ScanRecipeResultScreenState();
}

class _ScanRecipeResultScreenState extends State<ScanRecipeResultScreen> {
  late Map<String, dynamic> _recipe = Map<String, dynamic>.from(widget.recipe); // สูตรที่กำลังแสดง/แก้ไขอยู่ (ก๊อปมา ไม่แก้ของเดิม)

  /// สูตรในระบบทั้งหมดที่สลับไปใช้ได้ (ไม่ซ้ำ recipe_id)
  late final List<Map<String, dynamic>> _systemRecipes = () {
    final list = <Map<String, dynamic>>[if (widget.fromDatabase) widget.recipe]; // ถ้าสูตรหลักมาจากฐานข้อมูล ใส่ไว้ก่อน
    for (final r in widget.systemRecipes) {
      if (!list.any((x) => x['recipe_id'] == r['recipe_id'])) list.add(r); // เพิ่มสูตรอื่น (ไม่ซ้ำ id)
    }
    return list;
  }();

  /// สูตรจากรูป/AI (null = ยังไม่ได้ให้ AI อ่าน -> กดสร้างได้ครั้งเดียว)
  late Map<String, dynamic>? _aiRecipe = widget.fromDatabase
      ? widget.scannedRecipe
      : widget.recipe;

  /// สูตรในระบบที่เลือกใช้อยู่ (null = ใช้สูตรจากรูป/AI)
  late Map<String, dynamic>? _selectedSystem = widget.fromDatabase
      ? widget.recipe
      : null;

  /// ที่ผู้ใช้แก้ไขไว้ของแต่ละสูตร (key = recipe_id หรือ 'ai')
  /// สลับไปมาแล้วสิ่งที่แก้ไว้ไม่หาย
  final Map<Object?, Map<String, dynamic>> _drafts = {};

  /// id ของสูตรในฐานข้อมูลที่ใช้อยู่ (null = สูตรใหม่จาก AI)
  Object? get _existingRecipeId => _selectedSystem?['recipe_id'] as Object?; // ไม่ null = บันทึกแบบอ้างสูตรเดิม

  Object? get _draftKey => _selectedSystem?['recipe_id'] ?? 'ai'; // ชื่อช่องเก็บร่างของสูตรที่เลือกอยู่

  /// ที่มาของสูตรจาก AI สำหรับ recipes.source:
  /// AI แต่งขั้นตอนเองทั้งหมด (รูปมีแค่ชื่อเมนู/ไม่มีวิธีทำ) = 'ai_generated'
  /// อ่านสูตรจากรูปจริง (อาจมี AI เติมบางขั้นตอน) = 'scanned'
  String get _aiSource {
    final ai = _aiRecipe;
    if (ai == null) return 'scanned'; // ยังไม่มีสูตร AI
    final steps = RecipeRepository.stepTextsOf(ai).length;
    final aiSteps = RecipeRepository.aiStepIndexesOf(ai).length;
    return steps > 0 && aiSteps >= steps ? 'ai_generated' : 'scanned'; // ทุกขั้นตอน AI แต่งเอง = ai_generated
  }

  /// สลับไปใช้สูตรในระบบ ([system]) หรือสูตรจากรูป/AI (null)
  void _switchTo(Map<String, dynamic>? system) { // สลับสูตรที่แสดง
    setState(() {
      _drafts[_draftKey] = _recipe; // เก็บที่แก้ไว้ของสูตรปัจจุบันก่อน
      _selectedSystem = system; // เปลี่ยนสูตรที่เลือก
      _recipe =
          _drafts[_draftKey] ?? Map<String, dynamic>.from(system ?? _aiRecipe!); // เคยแก้ไว้ใช้ร่างเดิม ไม่งั้นก๊อปสูตรใหม่
    });
  }

  List<Map<String, dynamic>> _inventory = []; // ของในตู้เย็น
  bool _isLoadingInventory = true; // กำลังโหลดของในตู้ไหม

  /// สูตรในคลังของผู้ใช้ — ใช้เช็คว่าชื่อเมนูซ้ำกับสูตรที่บันทึกไว้แล้วไหม
  List<Map<String, dynamic>> _library = [];
  bool _isSaving = false; // กำลังบันทึกไหม

  @override
  void initState() {
    super.initState();
    _fetchInventory(); // โหลดของในตู้ (ไว้เช็คว่ามีวัตถุดิบไหม)
    _fetchLibrary(); // โหลดคลังสูตร (ไว้เช็คชื่อซ้ำ)
  }

  Future<void> _fetchLibrary() async {
    try {
      final library = await RecipeRepository.fetchSavedRecipes();
      if (mounted) setState(() => _library = library);
    } catch (e) {
      debugPrint('โหลดคลังสูตรไม่สำเร็จ: $e');
    }
  }

  /// มีสูตรอื่นในคลังที่ชื่อเดียวกันไหม (ไม่นับสูตรในระบบที่เลือกอยู่ ถ้าบันทึกไว้แล้ว)
  bool _nameTaken(String name) => _library.any(
    (r) =>
        r['recipe_id'] != _existingRecipeId &&
        RecipeRepository.isSameRecipeName(r['recipe_name'], name),
  );

  // กดชื่อเมนู -> เปลี่ยนชื่อ
  Future<void> _renameRecipe() async {
    final name = await showRenameRecipeDialog(
      context,
      currentName: (_recipe['recipe_name'] ?? '').toString(),
      isTaken: _nameTaken,
    );
    if (name == null || !mounted) return; // กดยกเลิก/ชื่อเดิม
    setState(() => _recipe = {..._recipe, 'recipe_name': name}); // อัปเดตชื่อ
  }

  Future<void> _fetchInventory() async {
    try {
      final inventory = await RecipeRepository.fetchInventory();
      if (mounted) setState(() => _inventory = inventory);
    } catch (e) {
      debugPrint('โหลดวัตถุดิบในตู้เย็นไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isLoadingInventory = false);
    }
  }

  // ข้อความปริมาณ เช่น "2 ฟอง" (ไม่มี = "ไม่ได้ระบุ")
  String _formatQty(Map<String, dynamic> ing) {
    final qty = RecipeRepository.formatNum(ing['use_quantity']).trim();
    final unit = (ing['unit'] ?? '').toString().trim();
    final combined = [qty, unit].where((s) => s.isNotEmpty).join(' ');
    return combined.isEmpty ? 'ไม่ได้ระบุ' : combined;
  }

  // กด "แก้ไข" -> เปิดฟอร์มแก้สูตร แล้วรับสูตรที่แก้กลับมา
  Future<void> _editRecipe() async {
    final edited = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualRecipeScreen(
          initialRecipe: _recipe,
          mode: RecipeFormMode.reviewDraft, // โหมดตรวจร่างก่อนบันทึก
          showAiDisclaimer: widget.isAiGenerated,
          referenceImage: widget.imageBytes, // แสดงรูปต้นฉบับไว้เทียบ
        ),
      ),
    );
    if (edited != null && mounted) setState(() => _recipe = edited); // แก้แล้ว -> ใช้สูตรใหม่
  }

  // กด "บันทึกสูตร"
  Future<void> _saveRecipe() async {
    setState(() => _isSaving = true);
    try {
      final existingId = _existingRecipeId;
      // ชื่อเมนูก่อนผู้ใช้เปลี่ยน -> ใช้เป็นชื่อในระบบ (ชื่อที่ตั้งเองอยู่แค่ในคลัง)
      final sharedName = ((_selectedSystem ?? _aiRecipe)?['recipe_name'] ?? '')
          .toString();
      final warnings = existingId != null
          // สูตรที่มีในฐานข้อมูลแล้ว -> แค่เพิ่มเข้าคลังของผู้ใช้
          ? await RecipeRepository.saveExistingRecipe( // บันทึกอ้างสูตรเดิมในฐานข้อมูล
              existingId,
              _recipe,
              original: _selectedSystem!,
              imageHash: widget.imageHash,
              sharedName: sharedName,
              scanImageBytes: widget.imageBytes,
            )
          : await RecipeRepository.saveRecipe( // บันทึกเป็นสูตรใหม่
              _recipe,
              source: _aiSource,
              imageHash: widget.imageHash,
              sharedName: sharedName,
              // สาธารณะได้เฉพาะสูตรที่ AI แต่งเองทั้งหมด (รูปมีแค่ชื่อเมนู) และไม่ได้แก้
              // สูตรที่อ่านจากตำรา/ลายมือของผู้ใช้ = ส่วนตัวเสมอ (ไม่เปิดให้คนอื่นเห็น
              // โดยไม่ได้ขออนุญาต ตามแนวทางของทีม) แก้อะไรก็ตาม = ส่วนตัว
              isPublic:
                  _aiSource == 'ai_generated' &&
                  _aiRecipe != null &&
                  RecipeRepository.isUneditedRecipe(_recipe, _aiRecipe!),
              scanImageBytes: widget.imageBytes,
            );
      if (!mounted) return;
      final duplicate = warnings.contains( // มีสูตรนี้ในคลังอยู่แล้วไหม
        RecipeRepository.alreadyInLibraryWarning,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            duplicate
                ? RecipeRepository.alreadyInLibraryWarning
                : warnings.isEmpty
                ? 'บันทึกสูตรอาหารเรียบร้อยแล้ว 📖'
                : 'บันทึกสูตรแล้ว แต่${warnings.join(' และ')}',
          ),
          backgroundColor: warnings.isEmpty ? Colors.green : Colors.orange, // [UI] ไม่มีคำเตือน = เขียว, มีคำเตือน = ส้ม
        ),
      );
      Navigator.pop(context, true); // ปิดหน้า ส่ง true = บันทึกแล้ว
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red, // [UI] แถบสีแดง = error
        ),
      );
    }
  }

  /// แจ้งว่าเจอสูตรนี้ในฐานข้อมูล + ปุ่มเปลี่ยนไปใช้สูตรที่ AI อ่านจากรูป
  /// ไม่อยากใช้สูตรในระบบ -> ให้ AI อ่าน/สร้างสูตรจากรูปนี้แทน (เรียก AI ขั้นที่ 2)
  Future<void> _createWithAi() async {
    final bytes = widget.imageBytes; // รูปที่สแกน
    if (bytes == null) return; // ไม่มีรูป ทำไม่ได้
    final closeLoader = showBlockingLoader( // แสดงป๊อปอัปกำลังโหลด (คืนฟังก์ชันไว้ปิด)
      context,
      'AI กำลังสร้างสูตรอาหาร...',
    );
    try {
      final recipe = await RecipeAiService.scanRecipeImage( // ให้ AI อ่าน/สร้างสูตรจากรูป
        bytes,
        imageHash: widget.imageHash,
      );
      RecipeRepository.cacheScanPrivately(recipe, widget.imageHash); // เก็บผลไว้แบบส่วนตัว (สแกนรูปเดิมซ้ำจะไม่เปลือง AI)
      closeLoader();
      if (!mounted) return;
      _aiRecipe = recipe;
      _switchTo(null); // บันทึกเป็นสูตรใหม่
    } catch (e) {
      closeLoader();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RecipeAiService.friendlyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ปุ่มในกล่องสีเขียว: มีกรอบ + พื้นขาว + กว้างเต็มกล่อง ให้เห็นชัดว่ากดได้
  Widget _bannerButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    const green = Color(0xFF2E7D32); // [UI] สีเขียวเข้มของปุ่ม
    return Padding(
      padding: const EdgeInsets.only(top: 10), // [UI] ระยะบนปุ่ม
      child: SizedBox(
        width: double.infinity, // [UI] ปุ่มกว้างเต็ม
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18), // [UI] ไอคอนขนาด 18
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: green, // [UI] สีตัวอักษร/ไอคอน
            backgroundColor: Colors.white, // [UI] พื้นขาว
            side: const BorderSide(color: green, width: 1.4), // [UI] ขอบเขียว หนา 1.4
            padding: const EdgeInsets.symmetric(vertical: 12), // [UI] ความสูงปุ่ม
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
            ),
            textStyle: const TextStyle(
              fontSize: 14, // [UI] ขนาดตัวอักษร
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// กล่องเลือกที่มาของสูตร: สูตรในระบบ / สูตรจากรูป (AI)
  /// สลับไปมาได้ตลอด ส่วนปุ่มให้ AI สร้างสูตรจะกดได้ครั้งเดียว
  Widget _recipeSourceBanner() {
    final usingSystem = _selectedSystem != null; // ใช้สูตรในระบบอยู่ไหม
    final message = usingSystem
        ? 'พบสูตรเมนูนี้ในฐานข้อมูลแล้ว จึงใช้สูตรที่มีอยู่แทนการสร้างใหม่'
        : 'กำลังใช้สูตรจากรูปของคุณ (AI) — กลับไปใช้สูตรในระบบได้';
    String nameOf(Map<String, dynamic> r) =>
        (r['recipe_name'] ?? '').toString().trim();
    final otherSystems = [ // สูตรในระบบอื่นๆ ที่ยังไม่ได้เลือก
      for (final r in _systemRecipes)
        if (r['recipe_id'] != _selectedSystem?['recipe_id']) r,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), // [UI] ระยะในกล่อง
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9), // [UI] พื้นเขียวอ่อน
        borderRadius: BorderRadius.circular(14), // [UI] มุมโค้ง 14
        border: Border.all(color: const Color(0xFFA5D6A7)), // [UI] ขอบเขียว
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                usingSystem
                    ? Icons.menu_book_rounded
                    : Icons.auto_awesome_outlined,
                color: const Color(0xFF2E7D32), // [UI] ไอคอนสีเขียว
                size: 20, // [UI] ขนาดไอคอน
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13, // [UI] ขนาดข้อความ
                    color: Color(0xFF1B5E20), // [UI] สีเขียวเข้ม
                    height: 1.4, // [UI] ระยะบรรทัด
                  ),
                ),
              ),
            ],
          ),
          // กลับไปใช้สูตรในระบบ (สูตรที่ไม่ได้เลือกอยู่)
          for (final r in otherSystems)
            _bannerButton(
              icon: Icons.menu_book_rounded,
              label: otherSystems.length == 1 && nameOf(r).isEmpty
                  ? 'ใช้สูตรในระบบ'
                  : 'ใช้สูตรในระบบ: ${nameOf(r)}',
              onPressed: () => _switchTo(r),
            ),
          if (usingSystem)
            // AI อ่านรูปไปแล้ว -> สลับไปใช้สูตรจากรูปได้ทันที (ไม่เสีย token เพิ่ม)
            if (_aiRecipe != null)
              _bannerButton(
                icon: Icons.photo_camera_outlined,
                label: 'ใช้สูตรจากรูป (AI)',
                onPressed: () => _switchTo(null),
              )
            // ยังไม่ได้ให้ AI อ่านรูป -> กดเรียกเองได้ครั้งเดียว
            // ได้สูตรแล้วปุ่มนี้จะกลายเป็นปุ่มสลับด้านบนแทน
            else if (widget.imageBytes != null)
              _bannerButton(
                icon: Icons.auto_awesome_outlined,
                label: 'ให้ AI สร้างสูตรใหม่จากรูปนี้ (ได้ครั้งเดียว)',
                onPressed: _createWithAi,
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = RecipeRepository.ingredientsOf(_recipe); // วัตถุดิบทั้งหมด
    final steps = RecipeRepository.stepTextsOf(_recipe); // ขั้นตอนทั้งหมด
    final aiSteps = RecipeRepository.aiStepIndexesOf(_recipe); // ตำแหน่งขั้นตอนที่ AI แต่ง
    // เครื่องปรุงพื้นฐาน (ซอส น้ำปลา น้ำตาล ฯลฯ) แยกไว้ ไม่นับในสถานะวัตถุดิบ
    final mainIngredients = [
      for (final ing in ingredients)
        if (!RecipeRepository.isStapleIngredient(ing)) ing,
    ];
    final stapleIngredients = [
      for (final ing in ingredients)
        if (RecipeRepository.isStapleIngredient(ing)) ing,
    ];
    final availability = [ // มีในตู้ไหม (ทีละวัตถุดิบหลัก)
      for (final ing in mainIngredients)
        RecipeRepository.isIngredientAvailable(ing, _inventory),
    ];
    final availableCount = availability.where((a) => a).length; // นับจำนวนที่มี
    final name = (_recipe['recipe_name'] ?? '').toString().trim();
    final servingsText = (_recipe['servings'] ?? '').toString().trim();
    final timeText = (_recipe['time'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: kRecipeBg, // [UI] สีพื้นหลัง
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: 'สูตรเมนูอาหาร'), // หัวหน้า
            const SizedBox(height: 15), // [UI] ระยะใต้หัว
            // รูปสูตรที่ผู้ใช้อัปโหลด ตรึงไว้ด้านบน ไม่เลื่อนตามรายละเอียด
            // (แบบเดียวกับหน้าผลสแกนวัตถุดิบ) แตะเพื่อขยาย/ซูมดูตัวหนังสือ
            if (widget.imageBytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), // [UI] ระยะรอบรูป
                child: ScannedImagePreview(
                  bytes: widget.imageBytes!,
                  height: 180, // [UI] ความสูงรูปตัวอย่าง
                ),
              ),
            Expanded(
              child: _isLoadingInventory
                  ? const Center(
                      child: CircularProgressIndicator(color: kRecipeBlue), // กำลังโหลด
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), // [UI] ระยะรอบรายการ
                      children: [
                        // ชื่อเมนู — แตะเพื่อเปลี่ยนชื่อ
                        RecipeNameBox(name: name, onRename: _renameRecipe), // ชื่อเมนู (แตะเพื่อเปลี่ยน)
                        if (_nameTaken(name)) ...[ // ชื่อซ้ำกับสูตรในคลัง -> เตือน
                          const SizedBox(height: 6),
                          Text(
                            'มีสูตรชื่อ "$name" ในคลังแล้ว แตะชื่อด้านบนเพื่อตั้งชื่อใหม่ เช่น "$name 2"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800, // [UI] ข้อความเตือนสีส้ม
                            ),
                          ),
                        ],
                        if (_systemRecipes.isNotEmpty) ...[ // มีสูตรในระบบ -> แสดงกล่องเลือกที่มา
                          const SizedBox(height: 12),
                          _recipeSourceBanner(),
                        ],
                        if (widget.isAiGenerated) ...[ // มาจาก AI -> แสดงคำเตือน
                          const SizedBox(height: 12),
                          const AiDisclaimerBanner(),
                        ],
                        const SizedBox(height: 12), // [UI] ระยะห่างระหว่างการ์ด

                        // สถานะวัตถุดิบ (ของจริงจากตู้เย็น)
                        RecipeSectionCard( // การ์ดสถานะวัตถุดิบ
                          child: RecipeStatusBar(
                            label: 'สถานะวัตถุดิบ',
                            have: availableCount,
                            total: mainIngredients.length,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // วัตถุดิบที่ต้องใช้
                        RecipeSectionCard( // การ์ดวัตถุดิบ
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('วัตถุดิบที่ต้องใช้'),
                              const SizedBox(height: 12),
                              if (servingsText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    bottom: 10,
                                  ),
                                  child: RecipeInfoLine(
                                    icon: Icons.restaurant_outlined,
                                    text: 'สำหรับ $servingsText',
                                    estimated:
                                        _recipe['servings_estimated'] == true,
                                  ),
                                ),
                              if (ingredients.isEmpty)
                                _emptyHint(
                                  'ไม่พบวัตถุดิบ กด "แก้ไข" เพื่อเพิ่ม',
                                ),
                              for (var i = 0; i < mainIngredients.length; i++) // แถววัตถุดิบหลัก
                                _ingredientRow(
                                  mainIngredients[i],
                                  availability[i],
                                ),
                              if (stapleIngredients.isNotEmpty) ...[ // เครื่องปรุงพื้นฐาน (แสดงสีเทา)
                                const SizedBox(height: 4),
                                const StapleIngredientsHeader(),
                                for (final ing in stapleIngredients)
                                  _ingredientRow(ing, false, staple: true),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ขั้นตอนการทำ
                        RecipeSectionCard( // การ์ดขั้นตอน
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('ขั้นตอนการทำ'),
                              const SizedBox(height: 12),
                              if (timeText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    bottom: 10,
                                  ),
                                  child: RecipeInfoLine(
                                    icon: Icons.timer_outlined,
                                    text: 'ใช้เวลาประมาณ $timeText',
                                    estimated:
                                        _recipe['time_estimated'] == true,
                                  ),
                                ),
                              if (steps.isEmpty)
                                _emptyHint(
                                  'ไม่พบขั้นตอน กด "แก้ไข" เพื่อเพิ่ม',
                                ),
                              RecipeStepsView( // รายการขั้นตอน (ขั้นที่ AI แต่งจะมีป้าย)
                                steps: steps,
                                aiIndexes: aiSteps,
                                fontSize: 15, // [UI] ขนาดตัวอักษรขั้นตอน
                                spacing: 12, // [UI] ระยะห่างระหว่างขั้นตอน
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            RecipeBottomActions( // ปุ่มด้านล่าง: ปุ่มรอง + บันทึก
              secondaryLabel: widget.retryLabel,
              onSecondary: () => Navigator.pop(context, false), // ปุ่มรอง -> ปิดหน้า ส่ง false
              primaryLabel: 'บันทึกสูตร',
              onPrimary: _saveRecipe,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  // หัวการ์ด: ป้ายชื่อส่วน + ปุ่มแก้ไข
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        SectionPill(title),
        const Spacer(),
        EditPill(onTap: _editRecipe),
      ],
    );
  }

  // ข้อความแจ้งเมื่อไม่มีข้อมูล
  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
  );

  /// แถววัตถุดิบในกรอบมุมโค้ง: ✓ (มีในตู้เย็นพอ) | ชื่อ | ปริมาณ
  Widget _ingredientRow(
    Map<String, dynamic> ing,
    bool available, {
    bool staple = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), // [UI] ระยะใต้แต่ละแถว
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // [UI] ระยะในแถว
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10), // [UI] มุมโค้ง 10
        border: Border.all(color: Colors.grey.shade300), // [UI] เส้นขอบเทาอ่อน
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22, // [UI] ช่องไอคอนกว้าง 22
            child: staple
                ? Icon( // ของพื้นฐาน -> ไอคอนครัวสีเทา
                    Icons.kitchen_outlined,
                    size: 16,
                    color: Colors.grey.shade500,
                  )
                : available // มีในตู้ -> ติ๊กถูก
                ? const CheckIcon(size: 16)
                : null, // ไม่มี -> ว่าง
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              (ing['name'] ?? '').toString(),
              style: TextStyle(
                fontSize: 14, // [UI] ขนาดชื่อวัตถุดิบ
                color: staple ? Colors.grey.shade600 : Colors.black87, // [UI] ของพื้นฐาน = สีเทา
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatQty(ing),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700), // [UI] ปริมาณ ขนาด 13 สีเทา
          ),
        ],
      ),
    );
  }
}
