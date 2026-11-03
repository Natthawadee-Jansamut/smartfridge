import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/recipe_ai_service.dart';
import '../widgets/add_recipe_widgets.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';
import '../widgets/recipe_flow_widgets.dart';
import 'saved_recipes_screen.dart';
import 'scan_recipe_result_screen.dart';

/// ทางลัด "สแกนสูตรอาหาร" จากเมนูหลัก -> เปิดหน้าคลังสูตรอาหารก่อน
/// (สแกนสูตรใหม่ได้จากปุ่ม + ในหน้าคลังสูตร)
class ScanRecipeScreen extends StatelessWidget {
  const ScanRecipeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SavedRecipesScreen();
}

/// หน้าสแกนสูตรอาหาร (ตามดีไซน์ใน Figma: "สแกนสูตรอาหาร")
/// ถ่ายรูป/เลือกรูป -> Gemini อ่านสูตร -> หน้าผลลัพธ์ให้ตรวจสอบก่อนบันทึก
/// pop(true) กลับไปหน้าคลังสูตรเมื่อบันทึกสำเร็จ
class ScanRecipeCaptureScreen extends StatefulWidget {
  const ScanRecipeCaptureScreen({super.key});

  @override
  State<ScanRecipeCaptureScreen> createState() =>
      _ScanRecipeCaptureScreenState();
}

class _ScanRecipeCaptureScreenState extends State<ScanRecipeCaptureScreen> {
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _recentRecipes = [];
  bool _isLoadingRecent = true;

  @override
  void initState() {
    super.initState();
    _fetchRecentRecipes();
  }

  // สูตรที่บันทึกล่าสุด 3 รายการจาก Supabase จริง
  Future<void> _fetchRecentRecipes() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingRecent = false);
        return;
      }
      final response = await Supabase.instance.client
          .from('scanned_recipes')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(3);
      if (mounted) {
        setState(() {
          _recentRecipes = List<Map<String, dynamic>>.from(response);
          _isLoadingRecent = false;
        });
      }
    } catch (e) {
      debugPrint('โหลดสูตรอาหารล่าสุดไม่สำเร็จ: $e');
      if (mounted) setState(() => _isLoadingRecent = false);
    }
  }

  Future<void> _pickAndAnalyzeImage(ImageSource source) async {
    VoidCallback? closeLoader;
    try {
      // ย่อรูปก่อนส่งให้ AI (รูปความละเอียดสูงอัปโหลดช้าจนเกิน timeout ได้)
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      closeLoader = showBlockingLoader(
        context,
        'AI กำลังอ่านสูตรอาหารจากรูป...',
      );
      final bytes = await image.readAsBytes();
      final recipe = await RecipeAiService.scanRecipeImage(
        bytes,
        mimeType: image.mimeType ?? 'image/jpeg',
      );
      closeLoader();
      if (!mounted) return;

      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ScanRecipeResultScreen(recipe: recipe)),
      );
      if (!mounted) return;
      if (saved == true) {
        Navigator.pop(context, true); // กลับไปหน้าคลังสูตร
      } else {
        _fetchRecentRecipes();
      }
    } catch (e) {
      closeLoader?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(RecipeAiService.friendlyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRecipeBg,
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: 'สแกนสูตรอาหาร'),
            const SizedBox(height: 15),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                children: [
                  _ScanOptionCard(
                    icon: Icons.camera_alt_outlined,
                    title: 'ถ่ายรูปสูตรอาหาร',
                    subtitle: 'เปิดกล้องเพื่อสแกน',
                    onTap: () => _pickAndAnalyzeImage(ImageSource.camera),
                  ),
                  const SizedBox(height: 14),
                  _ScanOptionCard(
                    icon: Icons.add_photo_alternate_outlined,
                    title: 'เลือกจากคลังรูปภาพ',
                    subtitle: 'อัพโหลดรูปภาพที่มีอยู่',
                    onTap: () => _pickAndAnalyzeImage(ImageSource.gallery),
                  ),
                  const SizedBox(height: 20),
                  RecipeSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'เคล็ดลับการสแกน',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _tip('ถ่ายรูปในที่ที่มีแสงสว่างเพียงพอ'),
                        _tip('จัดมุมมองให้อยู่ในแนวตรงและวางราบ'),
                        _tip('เน้นความคมชัดและโฟกัสที่ตัวหนังสือ'),
                        _tip('ครอบตัดเอาเฉพาะเนื้อหาที่สำคัญ'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  RecipeSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'สูตรอาหารที่สแกนล่าสุด',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildRecentList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentList() {
    if (_isLoadingRecent) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2, color: kRecipeBlue),
        ),
      );
    }
    if (_recentRecipes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'ยังไม่มีประวัติการสแกนสูตรอาหาร',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _recentRecipes.map((r) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (r['recipe_name'] ?? 'ไม่มีชื่อเมนู').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                relativeTimeThai(r['created_at']?.toString()),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const CheckIcon(size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดตัวเลือกแบบกลาง (ไอคอนในวงกลมฟ้า + หัวข้อ + คำอธิบาย) ตาม Figma
class _ScanOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScanOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: kRecipeBlue.withOpacity(0.12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
          child: Column(
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: const BoxDecoration(
                  color: kRecipeBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
