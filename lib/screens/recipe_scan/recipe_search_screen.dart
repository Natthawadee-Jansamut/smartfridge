import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/services/recipe_repository.dart'; // ดึงสูตร/ของในตู้จากฐานข้อมูล
import 'package:test_app/widgets/add_recipe_widgets.dart'; // สีและวิดเจ็ตของหน้าสูตร (kRecipeBg, kRecipeBlue)
import 'package:test_app/widgets/app_bottom_nav.dart'; // แถบเมนูล่าง
import 'package:test_app/widgets/recipe_flow_widgets.dart'; // แถบสถานะ "มีของกี่อย่าง"
import 'package:test_app/screens/shared/recipe_detail_screen.dart'; // หน้ารายละเอียดสูตร

/// หน้าค้นหาสูตรอาหาร (เปิดจากช่องค้นหาด้านบนของหน้าสูตรอาหาร)
/// ค้นได้เฉพาะสูตรในคลังของผู้ใช้เอง กดแล้วไปหน้ารายละเอียด (แก้ไข/ทำอาหารได้)
class RecipeSearchScreen extends StatefulWidget {
  const RecipeSearchScreen({super.key});

  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  final _controller = TextEditingController(); // ข้อความในช่องค้นหา

  List<Map<String, dynamic>> _library = []; // สูตรทั้งหมดในคลังของผู้ใช้
  List<Map<String, dynamic>> _inventory = []; // ของในตู้เย็น (ไว้เช็คว่ามีวัตถุดิบครบไหม)
  bool _loadingLibrary = true; // กำลังโหลดคลังสูตรอยู่ไหม
  String _query = ''; // คำค้นหาปัจจุบัน

  @override
  void initState() { // ตอนเปิดหน้า
    super.initState();
    _loadLibrary(); // โหลดคลังสูตร
  }

  @override
  void dispose() { // ตอนปิดหน้า
    _controller.dispose(); // คืนหน่วยความจำของช่องค้นหา
    super.dispose();
  }

  // โหลดสูตรในคลังและของในตู้พร้อมกัน
  Future<void> _loadLibrary() async {
    try {
      final results = await Future.wait([ // รอทั้ง 2 อย่างพร้อมกัน (เร็วกว่ารอทีละอัน)
        RecipeRepository.fetchSavedRecipes(), // [0] สูตรที่บันทึก
        RecipeRepository.fetchInventory(), // [1] ของในตู้
      ]);
      if (!mounted) return; // หน้าปิดไปแล้ว ไม่ต้องทำต่อ
      setState(() {
        _inventory = results[1];
        _library = RecipeRepository.sortForLibrary(results[0], _inventory); // เรียงสูตร (ทำได้ก่อนขึ้นก่อน)
      });
    } catch (e) {
      debugPrint('โหลดคลังสูตรไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingLibrary = false); // โหลดเสร็จ (สำเร็จหรือไม่ก็ตาม)
    }
  }

  // ทุกครั้งที่พิมพ์ในช่องค้นหา -> เก็บคำค้นแล้ววาดหน้าใหม่
  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  // กดสูตร -> เปิดหน้ารายละเอียด พอกลับมาก็โหลดคลังใหม่ (เผื่อแก้ไข/ลบสูตร)
  Future<void> _openLibraryRecipe(Map<String, dynamic> recipe) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          inventory: _inventory,
          canEdit: true, // อนุญาตให้แก้สูตรได้ (เพราะเป็นสูตรของผู้ใช้เอง)
        ),
      ),
    );
    if (mounted) _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    // กรองเอาเฉพาะสูตรที่ชื่อตรงกับคำค้น
    final libraryMatches = _library
        .where(
          (r) => RecipeRepository.nameMatchesQuery(r['recipe_name'], _query),
        )
        .toList();

    return Scaffold(
      backgroundColor: kRecipeBg, // [UI] สีพื้นหลัง (กำหนดใน add_recipe_widgets.dart)
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan), // แถบเมนูล่าง ไฮไลต์ "สแกน"
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(), // แถบค้นหาด้านบน
            const SizedBox(height: 12), // [UI] ระยะห่างใต้แถบค้นหา
            Expanded(
              child: ListView( // รายการผลค้นหาที่เลื่อนได้
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), // [UI] ระยะ ซ้าย 20 บน 0 ขวา 20 ล่าง 24
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag, // [UI] เลื่อนรายการแล้วคีย์บอร์ดหุบลง
                children: [
                  // ยังไม่พิมพ์อะไร = หน้าเปล่า ยังไม่แสดงสูตร
                  if (_query.isNotEmpty) ...[
                    _sectionTitle('สูตรของฉัน'),
                    if (_loadingLibrary) // กำลังโหลด -> วงหมุน
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(color: kRecipeBlue), // [UI] สีวงหมุน
                        ),
                      )
                    else if (libraryMatches.isEmpty) // ไม่เจอ -> ข้อความแจ้ง
                      _emptyHint('ไม่พบสูตรในคลังที่ชื่อมี "$_query"')
                    else // เจอ -> แสดงการ์ดทีละสูตร
                      for (final r in libraryMatches)
                        _recipeCard(r, onTap: () => _openLibraryRecipe(r)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แถบค้นหา: ปุ่มย้อนกลับ + ช่องพิมพ์
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0), // [UI] ระยะรอบแถบค้นหา
      child: Row(
        children: [
          IconButton( // ปุ่มย้อนกลับ
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFFF7D0), // [UI] สีพื้นปุ่ม (ครีมเหลือง)
              fixedSize: const Size(50, 50), // [UI] ขนาดปุ่ม 50x50
            ),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          ),
          const SizedBox(width: 10), // [UI] ระยะปุ่มกับช่องค้นหา
          Expanded(
            child: TextField( // ช่องพิมพ์ค้นหา
              controller: _controller,
              autofocus: true, // [UI] เปิดหน้ามาคีย์บอร์ดขึ้นทันที
              textInputAction: TextInputAction.search, // [UI] ปุ่มบนคีย์บอร์ดเป็น "ค้นหา"
              onChanged: _onQueryChanged, // พิมพ์ทุกตัวอักษร ค้นใหม่ทันที
              decoration: InputDecoration(
                hintText: 'ค้นหาสูตรอาหาร เช่น กะเพรา', // ข้อความจางๆ ตอนช่องยังว่าง
                filled: true,
                fillColor: Colors.white, // [UI] พื้นช่องสีขาว
                prefixIcon: const Icon(Icons.search), // [UI] ไอคอนแว่นขยาย
                suffixIcon: _query.isEmpty
                    ? null // ยังไม่พิมพ์ ไม่ต้องมีปุ่มล้าง
                    : IconButton( // ปุ่ม X ล้างคำค้น
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear(); // ล้างข้อความในช่อง
                          _onQueryChanged(''); // ล้างคำค้น
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14), // [UI] ความสูงด้านในช่อง
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(27), // [UI] ช่องทรงแคปซูล
                  borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // หัวข้อของกลุ่มผลค้นหา
  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4), // [UI] ระยะรอบหัวข้อ
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15, // [UI] ขนาดหัวข้อ
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    ),
  );

  // ข้อความแจ้งเมื่อไม่เจอผล
  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Text(text, style: TextStyle(color: Colors.grey.shade600)), // [UI] สีเทา
  );

  // การ์ดสูตร 1 ใบ (ชื่อ + แถบบอกว่ามีวัตถุดิบกี่อย่างจากทั้งหมด)
  Widget _recipeCard(
    Map<String, dynamic> recipe, {
    required VoidCallback onTap,
  }) {
    final (have, total) = RecipeRepository.completeness(recipe, _inventory); // มีกี่อย่าง / ต้องใช้กี่อย่าง
    final name = (recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12), // [UI] ระยะห่างระหว่างการ์ด
      child: Material(
        color: Colors.white, // [UI] พื้นการ์ดสีขาว
        elevation: 1, // [UI] เงาบางๆ
        shadowColor: Colors.black26, // [UI] สีเงา
        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
            child: RecipeStatusBar(label: name, have: have, total: total),
          ),
        ),
      ),
    );
  }
}
