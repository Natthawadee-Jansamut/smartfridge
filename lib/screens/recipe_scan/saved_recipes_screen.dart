import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบผู้ใช้/ฐานข้อมูล

import 'package:test_app/services/recipe_repository.dart'; // ดึง/ลบ/ตั้งสูตรโปรด
import 'package:test_app/widgets/add_recipe_widgets.dart'; // สีของหน้าสูตร + ป๊อปอัปเลือกวิธีเพิ่มสูตร
import 'package:test_app/widgets/app_bottom_nav.dart'; // แถบเมนูล่าง
import 'package:test_app/widgets/recipe_flow_widgets.dart'; // หัวหน้า + แถบสถานะวัตถุดิบ
import 'package:test_app/screens/recipe_scan/manual_recipe_screen.dart'; // หน้าเขียนสูตรเอง
import 'package:test_app/screens/shared/recipe_detail_screen.dart'; // หน้ารายละเอียดสูตร
import 'package:test_app/screens/recipe_scan/scan_recipe_screen.dart'; // หน้าถ่ายรูปสแกนสูตร

/// หน้าคลังสูตรอาหาร (ตามดีไซน์ใน Figma: "สูตรอาหาร")
/// ทุกสูตร + ความครบของวัตถุดิบ (X/Y) ดึงมาจาก Supabase จริงเสมอ
/// ปุ่ม + มุมขวาล่าง -> Bottom Sheet 2 ทางเลือก: สแกน / เขียนเอง
/// กดการ์ด -> หน้ารายละเอียด (แก้ไขวัตถุดิบ/ขั้นตอนได้ในหน้านั้น), ปัดซ้าย -> ลบสูตร
class SavedRecipesScreen extends StatefulWidget {
  const SavedRecipesScreen({super.key});

  @override
  State<SavedRecipesScreen> createState() => _SavedRecipesScreenState();
}

class _SavedRecipesScreenState extends State<SavedRecipesScreen> {
  bool _isLoading = true; // กำลังโหลดอยู่ไหม
  List<Map<String, dynamic>> _recipes = []; // สูตรทั้งหมดของผู้ใช้
  List<Map<String, dynamic>> _inventory = []; // ของในตู้เย็น

  @override
  void initState() {
    super.initState();
    _fetchData(); // เปิดหน้ามาก็โหลดข้อมูล
  }

  // โหลดสูตรและของในตู้จากฐานข้อมูล
  Future<void> _fetchData() async {
    setState(() => _isLoading = true); // แสดงวงหมุน
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) { // ยังไม่ล็อกอิน -> ไม่มีข้อมูล
        setState(() {
          _recipes = [];
          _inventory = [];
          _isLoading = false;
        });
        return;
      }

      final recipes = await RecipeRepository.fetchSavedRecipes(); // สูตรที่บันทึก
      final inventory = await RecipeRepository.fetchInventory(); // ของในตู้

      if (mounted) {
        setState(() {
          // สูตรโปรดบนสุด แล้วเรียงตามวัตถุดิบที่มีในตู้เย็นมากไปน้อย
          _recipes = RecipeRepository.sortForLibrary(recipes, inventory);
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

  // แสดงแถบข้อความด้านล่างจอ พร้อมสีพื้น (แดง = error, เขียว = สำเร็จ)
  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // ------------------------------------------------------------ Add flows

  // กดปุ่ม + -> เปิดป๊อปอัปให้เลือก สแกน/เขียนเอง
  Future<void> _onAddPressed() async {
    final option = await showAddRecipeSheet(context);
    if (option != null && mounted) await _openAddFlow(option); // เลือกแล้วไปหน้านั้น
  }

  // เปิดหน้าเพิ่มสูตรตามที่เลือก
  Future<void> _openAddFlow(AddRecipeOption option) async {
    Object? result;
    switch (option) {
      case AddRecipeOption.scan: // เลือกสแกน
        result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScanRecipeCaptureScreen()),
        );
      case AddRecipeOption.manual: // เลือกเขียนเอง
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
    _fetchData(); // กลับมาแล้วโหลดรายการใหม่
  }

  // ------------------------------------------------------------ Favorite

  // กดหัวใจ -> สลับสถานะสูตรโปรด
  Future<void> _toggleFavorite(Map<String, dynamic> recipe) async {
    final next = recipe['is_favorite'] != true; // ค่าใหม่ = ตรงข้ามค่าเดิม
    // อัปเดตหน้าจอทันที แล้วค่อยบันทึก ถ้าไม่สำเร็จจะย้อนกลับ
    setState(() {
      recipe['is_favorite'] = next;
      _recipes = RecipeRepository.sortForLibrary(_recipes, _inventory); // เรียงใหม่ (สูตรโปรดขึ้นบน)
    });
    try {
      await RecipeRepository.setFavorite(recipe['id'] as Object, next); // บันทึกลงฐานข้อมูล
    } catch (e) {
      debugPrint('บันทึกสูตรโปรดไม่สำเร็จ: $e');
      if (!mounted) return;
      setState(() { // บันทึกไม่ได้ -> คืนค่าเดิม
        recipe['is_favorite'] = !next;
        _recipes = RecipeRepository.sortForLibrary(_recipes, _inventory);
      });
      _showSnack('บันทึกสูตรโปรดไม่สำเร็จ: $e', Colors.red);
    }
  }

  // -------------------------------------------------------------- Delete

  // ป๊อปอัปถามยืนยันก่อนลบ (คืน true = ยืนยันลบ)
  Future<bool> _confirmDelete(String recipeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบสูตรอาหารนี้?'),
        content: Text('ต้องการลบ "$recipeName" ออกจากคลังสูตรอาหารใช่ไหม'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // ยกเลิก
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), // ยืนยัน
            style: TextButton.styleFrom(foregroundColor: Colors.red), // [UI] ปุ่มลบสีแดง
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    return confirm ?? false; // ปิดป๊อปอัปโดยไม่กดอะไร = ไม่ลบ
  }

  // ลบสูตรออกจากฐานข้อมูล
  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    try {
      await RecipeRepository.deleteSavedRecipe(recipe['id'] as Object);
      if (mounted) {
        setState(() => _recipes.remove(recipe)); // เอาออกจากรายการบนจอ
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
      backgroundColor: kRecipeBg, // [UI] สีพื้นหลัง (กำหนดใน add_recipe_widgets.dart)
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan), // แถบเมนูล่าง
      floatingActionButton: SizedBox( // ปุ่มลอย + มุมขวาล่าง
        width: 64, // [UI] ขนาดปุ่มลอย
        height: 64,
        child: FloatingActionButton(
          heroTag: 'add_recipe_fab', // ชื่อเฉพาะของปุ่ม (กันชนกับปุ่มลอยหน้าอื่นตอนเปลี่ยนหน้า)
          tooltip: 'เพิ่มสูตรอาหาร', // ข้อความตอนกดค้าง
          backgroundColor: kRecipeYellow, // [UI] สีปุ่ม (เหลือง)
          elevation: 3, // [UI] เงาปุ่ม
          shape: const CircleBorder(), // [UI] ทรงกลม
          onPressed: _onAddPressed,
          child: const Icon(Icons.add_rounded, color: Colors.black, size: 44), // [UI] ไอคอน + ขนาด 44
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: 'สูตรอาหาร'), // หัวหน้า
            const SizedBox(height: 15), // [UI] ระยะใต้หัว
            Expanded(child: _buildBody()), // เนื้อหา
          ],
        ),
      ),
    );
  }

  // เนื้อหาหลัก: กำลังโหลด / ว่าง / รายการสูตร
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kRecipeBlue)); // วงหมุน
    }
    if (_recipes.isEmpty) { // ยังไม่มีสูตร
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            'ยังไม่มีสูตรอาหาร\nกดปุ่ม + เพื่อสแกนหรือเขียนสูตรแรกของคุณ',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5), // [UI] สีเทา ระยะบรรทัด 1.5
          ),
        ),
      );
    }
    return RefreshIndicator( // ดึงลงเพื่อรีเฟรช
      onRefresh: _fetchData,
      child: ListView.builder( // สร้างรายการทีละแถวเท่าที่เห็นบนจอ (ประหยัดเครื่อง)
        // เผื่อที่ด้านล่างไม่ให้ปุ่ม + บังการ์ดใบสุดท้าย
        padding: const EdgeInsets.fromLTRB(20, 5, 20, 96), // [UI] ล่าง 96 = เผื่อที่ให้ปุ่มลอย
        itemCount: _recipes.length,
        itemBuilder: (context, index) { // สร้างการ์ดสูตรลำดับที่ index
          final recipe = _recipes[index];
          final (have, total) = RecipeRepository.completeness( // มีวัตถุดิบกี่อย่าง/ทั้งหมดกี่อย่าง
            recipe,
            _inventory,
          );
          final recipeName = (recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู')
              .toString();
          final isFavorite = recipe['is_favorite'] == true;
          return Dismissible( // ปัดการ์ดเพื่อลบ
            key: ValueKey(recipe['id'] ?? '$recipeName$index'), // รหัสเฉพาะของการ์ด
            direction: DismissDirection.endToStart, // ปัดจากขวาไปซ้ายเท่านั้น
            confirmDismiss: (_) => _confirmDelete(recipeName), // ถามก่อนลบ
            onDismissed: (_) => _deleteRecipe(recipe), // ยืนยันแล้ว ลบจริง
            background: Container( // พื้นหลังสีแดงที่โผล่ตอนปัด
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.centerRight, // [UI] ไอคอนถังขยะชิดขวา
              decoration: BoxDecoration(
                color: Colors.red, // [UI] สีพื้นตอนปัดลบ
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white), // [UI] ไอคอนถังขยะ
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15), // [UI] ระยะห่างระหว่างการ์ด
              child: Material(
                color: Colors.white, // [UI] พื้นการ์ด
                elevation: 1, // [UI] เงาบางๆ
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  splashColor: kRecipeBlue.withValues(alpha: 0.12), // [UI] สีคลื่นตอนกด
                  onTap: () async { // กดการ์ด -> หน้ารายละเอียด
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetailScreen(
                          recipe: recipe,
                          inventory: _inventory,
                          // แก้ไขวัตถุดิบ/ขั้นตอนได้ในหน้ารายละเอียดของแต่ละเมนู
                          canEdit: true,
                        ),
                      ),
                    );
                    // รีเฟรชเสมอ: อาจแก้ไขสูตร ทำอาหาร(หักวัตถุดิบ) หรือลบสูตรมา
                    if (mounted) _fetchData();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 6, 16), // [UI] ขวาน้อยกว่าเพราะมีปุ่มหัวใจ
                    child: Row(
                      children: [
                        Expanded(
                          child: RecipeStatusBar( // ชื่อสูตร + แถบ X/Y
                            label: recipeName,
                            have: have,
                            total: total,
                          ),
                        ),
                        // ปุ่มสูตรโปรด: กดแล้วสูตรจะขึ้นไปอยู่บนสุด
                        IconButton(
                          tooltip: isFavorite
                              ? 'เลิกเป็นสูตรโปรด'
                              : 'เพิ่มเป็นสูตรโปรด',
                          onPressed: () => _toggleFavorite(recipe),
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded // [UI] หัวใจทึบ
                                : Icons.favorite_border_rounded, // [UI] หัวใจโปร่ง
                            color: isFavorite
                                ? const Color(0xFFE53935) // [UI] สีแดงเมื่อเป็นสูตรโปรด
                                : Colors.grey.shade400, // [UI] สีเทาเมื่อไม่ใช่
                          ),
                        ),
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
