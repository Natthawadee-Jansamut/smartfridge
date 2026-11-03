import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/recipe_scan/manual_recipe_screen.dart';
import 'package:test_app/screens/shared/recipe_detail_screen.dart';
import 'package:test_app/screens/recipe_scan/scan_recipe_screen.dart';

/// หน้าคลังสูตรอาหาร (ตามดีไซน์ใน Figma: "สูตรอาหาร")
/// ทุกสูตร + ความครบของวัตถุดิบ (X/Y) ดึงมาจาก Supabase จริงเสมอ
/// ปุ่ม + มุมขวาล่าง -> Bottom Sheet 2 ทางเลือก: สแกน / เขียนเอง
/// ปุ่ม "แก้ไข" บนการ์ด -> ฟอร์มแก้ไขสูตร, ปัดซ้าย -> ลบสูตร
class SavedRecipesScreen extends StatefulWidget {
  const SavedRecipesScreen({super.key});

  @override
  State<SavedRecipesScreen> createState() => _SavedRecipesScreenState();
}

class _SavedRecipesScreenState extends State<SavedRecipesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _inventory = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _recipes = [];
          _inventory = [];
          _isLoading = false;
        });
        return;
      }

      final recipesRes = await Supabase.instance.client
          .from('scanned_recipes')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final inventory = await RecipeRepository.fetchInventory();

      if (mounted) {
        setState(() {
          _recipes = List<Map<String, dynamic>>.from(recipesRes);
          _inventory = inventory;
          _isLoading = false;
        });
      }
    } catch (e) {
      // แสดง error จริง เพื่อให้จับปัญหาอย่าง RLS บน Supabase บล็อกการอ่านได้ง่าย
      debugPrint('โหลดสูตรอาหารที่บันทึกไว้ไม่สำเร็จ: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('โหลดสูตรอาหารไม่สำเร็จ: $e', Colors.red);
      }
    }
  }

  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // ------------------------------------------------------------ Add flows

  Future<void> _onAddPressed() async {
    final option = await showAddRecipeSheet(context);
    if (option != null && mounted) await _openAddFlow(option);
  }

  Future<void> _openAddFlow(AddRecipeOption option) async {
    Object? result;
    switch (option) {
      case AddRecipeOption.scan:
        result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScanRecipeCaptureScreen()),
        );
      case AddRecipeOption.manual:
        result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManualRecipeScreen()),
        );
    }
    if (!mounted) return;
    // หน้าเขียนสูตรเองกด "สแกนใหม่" -> ส่งต่อไปหน้าสแกน
    if (result is AddRecipeOption) {
      await _openAddFlow(result);
      return;
    }
    _fetchData();
  }

  // ---------------------------------------------------------------- Edit

  Future<void> _editRecipe(Map<String, dynamic> recipe) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualRecipeScreen(
          initialRecipe: recipe,
          mode: RecipeFormMode.editSaved,
        ),
      ),
    );
    if (saved == true && mounted) _fetchData();
  }

  // -------------------------------------------------------------- Delete

  Future<bool> _confirmDelete(String recipeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบสูตรอาหารนี้?'),
        content: Text('ต้องการลบ "$recipeName" ออกจากคลังสูตรอาหารใช่ไหม'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    try {
      await Supabase.instance.client
          .from('scanned_recipes')
          .delete()
          .eq('id', recipe['id']);
      if (mounted) {
        setState(() => _recipes.remove(recipe));
        _showSnack('ลบสูตรอาหารเรียบร้อยแล้ว', Colors.green);
      }
    } catch (e) {
      debugPrint('ลบสูตรอาหารไม่สำเร็จ: $e');
      if (mounted) {
        _showSnack('ลบไม่สำเร็จ: $e', Colors.red);
        _fetchData(); // ลบไม่สำเร็จจริง ให้รายการกลับมาตามเดิม
      }
    }
  }

  // --------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecipeBg,
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          heroTag: 'add_recipe_fab',
          tooltip: 'เพิ่มสูตรอาหาร',
          backgroundColor: kRecipeYellow,
          elevation: 3,
          shape: const CircleBorder(),
          onPressed: _onAddPressed,
          child: const Icon(Icons.add_rounded, color: Colors.black, size: 44),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: 'สูตรอาหาร'),
            const SizedBox(height: 15),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kRecipeBlue));
    }
    if (_recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            'ยังไม่มีสูตรอาหาร\nกดปุ่ม + เพื่อสแกนหรือเขียนสูตรแรกของคุณ',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView.builder(
        // เผื่อที่ด้านล่างไม่ให้ปุ่ม + บังการ์ดใบสุดท้าย
        padding: const EdgeInsets.fromLTRB(20, 5, 20, 96),
        itemCount: _recipes.length,
        itemBuilder: (context, index) {
          final recipe = _recipes[index];
          final (have, total) = RecipeRepository.completeness(
            recipe,
            _inventory,
          );
          final recipeName = (recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู')
              .toString();
          return Dismissible(
            key: ValueKey(recipe['id'] ?? '$recipeName$index'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(recipeName),
            onDismissed: (_) => _deleteRecipe(recipe),
            background: Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Material(
                color: Colors.white,
                elevation: 1,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  splashColor: kRecipeBlue.withOpacity(0.12),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailScreen(
                          recipe: recipe,
                          inventory: _inventory,
                        ),
                      ),
                    );
                    if (result == true) _fetchData();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: RecipeStatusBar(
                            label: recipeName,
                            have: have,
                            total: total,
                          ),
                        ),
                        if (recipe['id'] != null) ...[
                          const SizedBox(width: 10),
                          EditPill(onTap: () => _editRecipe(recipe)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
