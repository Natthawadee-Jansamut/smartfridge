import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/recipe_scan/manual_recipe_screen.dart';

/// หน้าตรวจสอบสูตรที่ AI สแกน/สร้างมา (ตามดีไซน์ใน Figma: "สูตรเมนูอาหาร")
/// - เทียบวัตถุดิบที่สูตรต้องใช้กับของจริงในตู้เย็น (Supabase) แบบสด
/// - ปุ่ม "แก้ไข" เปิดฟอร์มที่กรอกข้อมูลจาก AI ไว้ให้แล้ว
/// - แสดงคำเตือน AI ชัดเจนก่อนบันทึก
///
/// ผลลัพธ์ที่ pop กลับ: true = บันทึกแล้ว, false = กดสแกนใหม่/สร้างใหม่, null = ย้อนกลับ
class ScanRecipeResultScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final bool isAiGenerated;
  final String retryLabel;

  /// รูปสูตรที่ผู้ใช้อัปโหลด — แสดงด้านบนให้เทียบกับผลที่ AI อ่านได้
  final Uint8List? imageBytes;

  const ScanRecipeResultScreen({
    super.key,
    required this.recipe,
    this.isAiGenerated = true,
    this.retryLabel = 'สแกนใหม่',
    this.imageBytes,
  });

  @override
  State<ScanRecipeResultScreen> createState() => _ScanRecipeResultScreenState();
}

class _ScanRecipeResultScreenState extends State<ScanRecipeResultScreen> {
  late Map<String, dynamic> _recipe = Map<String, dynamic>.from(widget.recipe);
  List<Map<String, dynamic>> _inventory = [];
  bool _isLoadingInventory = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchInventory();
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

  String _formatQty(Map<String, dynamic> ing) {
    final qty = RecipeRepository.formatNum(ing['use_quantity']).trim();
    final unit = (ing['unit'] ?? '').toString().trim();
    final combined = [qty, unit].where((s) => s.isNotEmpty).join(' ');
    return combined.isEmpty ? 'ไม่ได้ระบุ' : combined;
  }

  Future<void> _editRecipe() async {
    final edited = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualRecipeScreen(
          initialRecipe: _recipe,
          mode: RecipeFormMode.reviewDraft,
          showAiDisclaimer: widget.isAiGenerated,
          referenceImage: widget.imageBytes,
        ),
      ),
    );
    if (edited != null && mounted) setState(() => _recipe = edited);
  }

  Future<void> _saveRecipe() async {
    setState(() => _isSaving = true);
    try {
      final warnings = await RecipeRepository.saveRecipe(_recipe);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            warnings.isEmpty
                ? 'บันทึกสูตรอาหารเรียบร้อยแล้ว 📖'
                : 'บันทึกสูตรแล้ว แต่${warnings.join(' และ')}',
          ),
          backgroundColor: warnings.isEmpty ? Colors.green : Colors.orange,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = RecipeRepository.ingredientsOf(_recipe);
    final steps = RecipeRepository.stepTextsOf(_recipe);
    final aiSteps = RecipeRepository.aiStepIndexesOf(_recipe);
    final availability = [
      for (final ing in ingredients)
        RecipeRepository.isIngredientAvailable(ing, _inventory),
    ];
    final availableCount = availability.where((a) => a).length;
    final name = (_recipe['recipe_name'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: kRecipeBg,
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: 'สูตรเมนูอาหาร'),
            const SizedBox(height: 15),
            Expanded(
              child: _isLoadingInventory
                  ? const Center(
                      child: CircularProgressIndicator(color: kRecipeBlue),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      children: [
                        // รูปสูตรที่ผู้ใช้อัปโหลด (แตะเพื่อขยาย/ซูมดูตัวหนังสือ)
                        if (widget.imageBytes != null) ...[
                          ScannedImagePreview(bytes: widget.imageBytes!),
                          const SizedBox(height: 16),
                        ],
                        // ชื่อเมนู
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            name.isEmpty ? 'ไม่มีชื่อเมนู' : name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (widget.isAiGenerated) ...[
                          const SizedBox(height: 12),
                          const AiDisclaimerBanner(),
                        ],
                        const SizedBox(height: 12),

                        // สถานะวัตถุดิบ (ของจริงจากตู้เย็น)
                        RecipeSectionCard(
                          child: RecipeStatusBar(
                            label: 'สถานะวัตถุดิบ',
                            have: availableCount,
                            total: ingredients.length,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // วัตถุดิบที่ต้องใช้
                        RecipeSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('วัตถุดิบที่ต้องใช้'),
                              const SizedBox(height: 12),
                              if (ingredients.isEmpty)
                                _emptyHint(
                                  'ไม่พบวัตถุดิบ กด "แก้ไข" เพื่อเพิ่ม',
                                ),
                              for (var i = 0; i < ingredients.length; i++)
                                _ingredientRow(ingredients[i], availability[i]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ขั้นตอนการทำ
                        RecipeSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('ขั้นตอนการทำ'),
                              const SizedBox(height: 12),
                              if (steps.isEmpty)
                                _emptyHint(
                                  'ไม่พบขั้นตอน กด "แก้ไข" เพื่อเพิ่ม',
                                ),
                              RecipeStepsView(
                                steps: steps,
                                aiIndexes: aiSteps,
                                fontSize: 15,
                                spacing: 12,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            RecipeBottomActions(
              secondaryLabel: widget.retryLabel,
              onSecondary: () => Navigator.pop(context, false),
              primaryLabel: 'บันทึกสูตร',
              onPrimary: _saveRecipe,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        SectionPill(title),
        const Spacer(),
        EditPill(onTap: _editRecipe),
      ],
    );
  }

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
  );

  /// แถววัตถุดิบในกรอบมุมโค้ง: ✓ (มีในตู้เย็นพอ) | ชื่อ | ปริมาณ
  Widget _ingredientRow(Map<String, dynamic> ing, bool available) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: available ? const CheckIcon(size: 16) : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              (ing['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatQty(ing),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
