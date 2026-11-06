import 'package:flutter/material.dart';

import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/shared/recipe_detail_screen.dart';

/// หน้าค้นหาสูตรอาหาร (เปิดจากช่องค้นหาด้านบนของหน้าสูตรอาหาร)
/// ค้นได้เฉพาะสูตรในคลังของผู้ใช้เอง กดแล้วไปหน้ารายละเอียด (แก้ไข/ทำอาหารได้)
class RecipeSearchScreen extends StatefulWidget {
  const RecipeSearchScreen({super.key});

  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  final _controller = TextEditingController();

  List<Map<String, dynamic>> _library = [];
  List<Map<String, dynamic>> _inventory = [];
  bool _loadingLibrary = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    try {
      final results = await Future.wait([
        RecipeRepository.fetchSavedRecipes(),
        RecipeRepository.fetchInventory(),
      ]);
      if (!mounted) return;
      setState(() {
        _inventory = results[1];
        _library = RecipeRepository.sortForLibrary(results[0], _inventory);
      });
    } catch (e) {
      debugPrint('โหลดคลังสูตรไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingLibrary = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
  }

  Future<void> _openLibraryRecipe(Map<String, dynamic> recipe) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          inventory: _inventory,
          canEdit: true,
        ),
      ),
    );
    if (mounted) _loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final libraryMatches = _library
        .where(
          (r) => RecipeRepository.nameMatchesQuery(r['recipe_name'], _query),
        )
        .toList();

    return Scaffold(
      backgroundColor: kRecipeBg,
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  // ยังไม่พิมพ์อะไร = หน้าเปล่า ยังไม่แสดงสูตร
                  if (_query.isNotEmpty) ...[
                    _sectionTitle('สูตรของฉัน'),
                    if (_loadingLibrary)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(color: kRecipeBlue),
                        ),
                      )
                    else if (libraryMatches.isEmpty)
                      _emptyHint('ไม่พบสูตรในคลังที่ชื่อมี "$_query"')
                    else
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

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFFFF7D0),
              fixedSize: const Size(50, 50),
            ),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'ค้นหาสูตรอาหาร เช่น กะเพรา',
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(27),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    ),
  );

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
  );

  Widget _recipeCard(
    Map<String, dynamic> recipe, {
    required VoidCallback onTap,
  }) {
    final (have, total) = RecipeRepository.completeness(recipe, _inventory);
    final name = (recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RecipeStatusBar(label: name, have: have, total: total),
          ),
        ),
      ),
    );
  }
}
