import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/recipe_flow_widgets.dart';
import 'recipe_detail_screen.dart';
import 'scan_recipe_screen.dart';

/// หน้าคลังสูตรอาหารที่สแกนไว้ (ตามดีไซน์ใน Figma: "Smart Recipe")
/// ทุกสูตร + ความครบของวัตถุดิบ (X/Y) ดึงมาจาก Supabase จริงเสมอ
/// (ไม่ใช้ตัวเลข mock ของ Figma เช่น "6/7")
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

      final inventoryRes = await Supabase.instance.client
          .from('fridge_items')
          .select();

      if (mounted) {
        setState(() {
          _recipes = List<Map<String, dynamic>>.from(recipesRes);
          _inventory = List<Map<String, dynamic>>.from(inventoryRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      // แสดง error จริงออกมาแทนที่จะกลืนเงียบๆ เพื่อให้ตรวจจับปัญหา เช่น
      // Row Level Security (RLS) บน Supabase บล็อกการอ่านได้ง่ายขึ้น
      debugPrint('โหลดสูตรอาหารที่บันทึกไว้ไม่สำเร็จ: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('โหลดสูตรอาหารไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  num _toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  // นับว่าสูตรนี้มีวัตถุดิบครบกี่ชนิดจากที่ต้องใช้ทั้งหมด (เทียบกับตู้เย็นจริง)
  (int, int) _completeness(Map<String, dynamic> recipe) {
    final List<dynamic> needed = recipe['detailed_ingredients'] ?? [];
    int have = 0;
    for (final item in needed) {
      final ing = Map<String, dynamic>.from(item);
      final neededName = (ing['name'] ?? '').toString().trim().toLowerCase();
      final neededQty = _toNum(ing['use_quantity']);
      // เทียบชื่อแบบยืดหยุ่นเหมือนตอนหักวัตถุดิบจริงใน RecipeDetailScreen
      // เพื่อให้ตัวเลข "มีของครบกี่ชนิด" ตรงกับที่กดทำอาหารจริงจะเจอ
      final match = _inventory.where((inv) {
        final invName = (inv['name'] ?? '').toString().trim().toLowerCase();
        return invName.isNotEmpty &&
            (invName == neededName ||
                invName.contains(neededName) ||
                neededName.contains(invName));
      }).toList();
      if (match.isNotEmpty && _toNum(match.first['quantity']) >= neededQty) {
        have++;
      }
    }
    return (have, needed.length);
  }

  Future<bool> _confirmDelete(String recipeName) async {
    final confirm = await showDialog<bool>(
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
    );
    return confirm ?? false;
  }

  // ลบสูตรอาหารออกจาก Supabase จริง (ของจริง ไม่ใช่แค่ซ่อนในหน้าจอ)
  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    try {
      await Supabase.instance.client
          .from('scanned_recipes')
          .delete()
          .eq('id', recipe['id']);
      if (mounted) {
        setState(() => _recipes.remove(recipe));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ลบสูตรอาหารเรียบร้อยแล้ว"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('ลบสูตรอาหารไม่สำเร็จ: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // ลบไม่สำเร็จจริง (เช่นโดน RLS บล็อก) ให้รีโหลดรายการกลับมาแสดงตามเดิม
        _fetchData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFF7D0),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScanRecipeCaptureScreen()),
          );
          _fetchData();
        },
        child: const Icon(Icons.add, color: Color(0xff5189C9)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: "สูตรอาหาร"),
            const SizedBox(height: 15),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xff5189C9),
                      ),
                    )
                  : _recipes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Text(
                          "ยังไม่มีสูตรอาหารที่สแกนไว้\nกดปุ่ม + เพื่อสแกนสูตรอาหารสูตรแรกของคุณ",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchData,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 5,
                        ),
                        itemCount: _recipes.length,
                        itemBuilder: (context, index) {
                          final recipe = _recipes[index];
                          final (have, total) = _completeness(recipe);
                          final recipeName =
                              recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู';
                          return Dismissible(
                            key: ValueKey(
                              recipe['id'] ?? recipeName + index.toString(),
                            ),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmDelete(recipeName),
                            onDismissed: (_) => _deleteRecipe(recipe),
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                              ),
                              alignment: Alignment.centerRight,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 15),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  splashColor: Colors.blue.withOpacity(0.15),
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
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
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
                                    child: RecipeStatusBar(
                                      label: recipeName,
                                      have: have,
                                      total: total,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
