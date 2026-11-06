import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/recipe_ai_service.dart';
import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/widgets/add_recipe_widgets.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/recipe_scan/saved_recipes_screen.dart';
import 'package:test_app/screens/recipe_scan/scan_recipe_result_screen.dart';

/// ทางลัด "สแกนสูตรอาหาร" จากเมนูหลัก -> เปิดหน้าคลังสูตรอาหารก่อน
/// (สแกนสูตรใหม่ได้จากปุ่ม + ในหน้าคลังสูตร)
class ScanRecipeScreen extends StatelessWidget {
  const ScanRecipeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SavedRecipesScreen();
}

/// หน้าสแกนสูตรอาหาร (ตามดีไซน์ใน Figma: "สแกนสูตรอาหาร")
/// ถ่ายภาพ/เลือกรูป -> Gemini อ่านสูตร -> หน้าผลลัพธ์ให้ตรวจสอบก่อนบันทึก
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
      final response = await RecipeRepository.fetchSavedRecipes(limit: 3);
      if (mounted) {
        setState(() {
          _recentRecipes = response;
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

      closeLoader = showBlockingLoader(context, 'กำลังค้นหาสูตรอาหารจากรูป...');
      final bytes = await image.readAsBytes();
      final imageHash = RecipeRepository.imageHashOf(bytes);

      // 1) รูปนี้เคยสแกนแล้ว (image_hash ตรงกัน) -> ใช้สูตรเดิม ไม่ต้องเรียก Gemini
      Map<String, dynamic>? found;
      try {
        found = await RecipeRepository.findRecipeByImageHash(imageHash);
        if (found != null) {
          logAiRequest(
            event: AiEvent.scanRecipe,
            result: AiResult.cacheHit,
            recipeId: found['recipe_id'],
            imageHash: imageHash,
          );
        }
      } catch (e) {
        debugPrint('ค้นสูตรจาก image_hash ไม่สำเร็จ: $e');
      }

      // ขั้นตอนอ่านสูตรเต็ม (ขั้นที่ 2) — ใช้ token มากที่สุด เรียกเฉพาะตอนจำเป็น
      final mimeType = image.mimeType ?? 'image/jpeg';
      Future<Map<String, dynamic>> readFullRecipe(String message) {
        closeLoader?.call();
        closeLoader = showBlockingLoader(context, message);
        return RecipeAiService.scanRecipeImage(
          bytes,
          mimeType: mimeType,
          imageHash: imageHash,
        );
      }

      Map<String, dynamic>? scanned;
      // สูตรในระบบที่เจอ — ส่งไปหน้าผลลัพธ์ให้สลับกลับมาใช้ได้ แม้เลือก AI ไปแล้ว
      var systemOptions = <Map<String, dynamic>>[if (found != null) found];
      if (found == null) {
        // 2) ขั้นที่ 1 (ประหยัด token): ถาม AI สั้นๆ ว่าเมนูอะไร มีวัตถุดิบ/วิธีทำไหม
        final info = await RecipeAiService.identifyRecipeImage(
          bytes,
          mimeType: mimeType,
          imageHash: imageHash,
        );
        // 3) เอาชื่อไปค้นในระบบ: ชื่อตรงกันทั้งชื่อ / ชื่อคล้ายกัน
        final (exact, similar) = await _searchByName(info.name);
        found = exact;
        systemOptions = [if (exact != null) exact, ...similar];

        if (info.isNameOnly) {
          // รูปมีแค่ชื่อเมนู -> ถ้าให้ AI อ่านต่อ AI ต้องแต่งสูตรเองทั้งสูตร
          if (found != null) {
            // เจอชื่อตรงในระบบ -> ใช้สูตรในระบบเลย ไม่ต้องเรียก AI ขั้นที่ 2
          } else if (similar.isNotEmpty) {
            closeLoader?.call();
            closeLoader = null;
            if (!mounted) return;
            final choice = await _chooseRecipe(
              title: 'พบสูตรที่ชื่อคล้าย "${info.name}"',
              subtitle: 'เป็นเมนูเดียวกันไหม? เลือกสูตรที่ต้องการใช้',
              scanned: null,
              options: similar,
            );
            if (choice == null || !mounted) return; // ปิดหน้าต่างไป = ยกเลิก
            if (identical(choice, _useImage)) {
              scanned = await readFullRecipe('AI กำลังสร้างสูตรอาหาร...');
            } else {
              found = choice;
            }
          } else {
            scanned = await readFullRecipe('AI กำลังสร้างสูตรอาหาร...');
          }
        } else {
          // รูปมีสูตรจริง -> อ่านสูตรเต็มจากรูป แล้วเทียบกับสูตรในระบบ
          scanned = await readFullRecipe('AI กำลังอ่านสูตรอาหารจากรูป...');
          closeLoader?.call();
          closeLoader = null;
          if (!mounted) return;

          //    - ชื่อตรง + วัตถุดิบใกล้เคียงสูตรในระบบ -> ใช้สูตรในระบบ
          //    - ชื่อตรง แต่สูตรต่างกัน -> ถามผู้ใช้
          //    - ชื่อคล้ายกัน -> ถามผู้ใช้ทุกครั้ง
          List<Map<String, dynamic>>? options;
          String? title, subtitle;
          if (found != null) {
            final close =
                RecipeRepository.ingredientSimilarity(found, scanned) >= 0.7;
            if (!close) {
              options = [found];
              title = 'พบสูตร "${info.name}" ในระบบแล้ว';
              subtitle = 'แต่สูตรในรูปของคุณต่างออกไป ต้องการใช้สูตรไหน?';
            }
          } else if (similar.isNotEmpty) {
            options = similar;
            title = 'พบสูตรที่ชื่อคล้าย "${info.name}"';
            subtitle = 'เป็นเมนูเดียวกันไหม? เลือกสูตรที่ต้องการใช้';
          }
          if (options != null) {
            final choice = await _chooseRecipe(
              title: title!,
              subtitle: subtitle!,
              scanned: scanned,
              options: options,
            );
            if (choice == null || !mounted) return; // ปิดหน้าต่างไป = ยกเลิก
            found = identical(choice, _useImage) ? null : choice;
          }
        }
      }
      closeLoader?.call();
      closeLoader = null;
      final useDatabase = found != null;
      if (!mounted) return;

      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          // ส่งรูปที่อัปโหลดไปด้วย ให้ผู้ใช้เทียบว่า AI อ่านสูตรถูกไหม
          builder: (_) => ScanRecipeResultScreen(
            recipe: useDatabase ? found! : scanned!,
            imageBytes: bytes,
            imageHash: imageHash,
            fromDatabase: useDatabase,
            // ใช้สูตรในระบบ -> เก็บผลจาก AI ไว้ เผื่อผู้ใช้อยากใช้สูตรจากรูปแทน
            scannedRecipe: useDatabase ? scanned : null,
            systemRecipes: systemOptions,
          ),
        ),
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

  /// ค่าที่ _chooseRecipe คืนมาเมื่อผู้ใช้เลือก "ใช้สูตรจากรูป / ให้ AI สร้าง"
  static const Map<String, dynamic> _useImage = {};

  /// ค้นสูตรในระบบจากชื่อเมนู -> (สูตรที่ชื่อตรงกันทั้งชื่อ, สูตรที่ชื่อคล้ายกัน)
  /// ค้นไม่สำเร็จ (เช่น เน็ตหลุด) -> ถือว่าไม่เจอ แล้วใช้ AI ต่อตามปกติ
  Future<(Map<String, dynamic>?, List<Map<String, dynamic>>)> _searchByName(
    String name,
  ) async {
    try {
      final exact = await RecipeRepository.findRecipeByName(name);
      if (exact != null) return (exact, <Map<String, dynamic>>[]);
      final similar = await RecipeRepository.findSimilarRecipesByName(name);
      // ชื่อเดียวกันจริงๆ แค่พิมพ์วรรณยุกต์/สระสลับลำดับ -> ถือว่าตรงทั้งชื่อ
      final same = similar
          .where(
            (r) => RecipeRepository.isSameRecipeName(r['recipe_name'], name),
          )
          .firstOrNull;
      if (same != null) return (same, <Map<String, dynamic>>[]);
      return (null, similar);
    } catch (e) {
      debugPrint('ค้นสูตรในฐานข้อมูลไม่สำเร็จ (ใช้ AI แทน): $e');
      return (null, <Map<String, dynamic>>[]);
    }
  }

  /// ให้ผู้ใช้เลือกว่าจะใช้สูตรจากรูป หรือสูตรใดสูตรหนึ่งในระบบ
  /// [scanned] = สูตรที่ AI อ่านจากรูปแล้ว (null = ยังไม่ได้อ่าน -> ปุ่มให้ AI สร้าง)
  /// คืนสูตรที่เลือก ([_useImage] = ใช้สูตรจากรูป/ให้ AI สร้าง),
  /// null = ปิดหน้าต่าง (ยกเลิก)
  Future<Map<String, dynamic>?> _chooseRecipe({
    required String title,
    required String subtitle,
    required Map<String, dynamic>? scanned,
    required List<Map<String, dynamic>> options,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              _RecipeChoiceCard(
                icon: scanned == null
                    ? Icons.auto_awesome_outlined
                    : Icons.photo_camera_outlined,
                title: scanned == null
                    ? 'ให้ AI สร้างสูตรจากรูปของคุณ'
                    : 'สูตรจากรูปของคุณ',
                recipe: scanned,
                onTap: () => Navigator.pop(ctx, _useImage),
              ),
              for (final option in options) ...[
                const SizedBox(height: 10),
                _RecipeChoiceCard(
                  icon: Icons.menu_book_rounded,
                  title: 'สูตรในระบบ',
                  // แสดงชื่อเต็มของสูตรในระบบ (อาจต่างจากชื่อที่สแกนได้)
                  name: (option['recipe_name'] ?? '').toString(),
                  recipe: option,
                  onTap: () => Navigator.pop(ctx, option),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
                    title: 'ถ่ายภาพสูตรอาหาร',
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
                        _tip('ถ่ายภาพในที่ที่มีแสงสว่างเพียงพอ'),
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

/// การ์ดตัวเลือกสูตร: จำนวนวัตถุดิบ / ขั้นตอน / ขั้นตอนที่ AI คิดเพิ่ม
class _RecipeChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;

  /// ชื่อเมนู (แสดงใต้หัวข้อ) — ใช้กับสูตรในระบบที่ชื่ออาจต่างจากที่สแกนได้
  final String? name;

  /// null = ยังไม่ได้ให้ AI อ่านสูตร (ตัวเลือก "ให้ AI สร้างสูตร")
  final Map<String, dynamic>? recipe;
  final VoidCallback onTap;

  const _RecipeChoiceCard({
    required this.icon,
    required this.title,
    this.name,
    required this.recipe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final recipe = this.recipe ?? const <String, dynamic>{};
    final pending = this.recipe == null;
    final ingredients = RecipeRepository.ingredientsOf(recipe).length;
    final steps = RecipeRepository.stepTextsOf(recipe).length;
    final aiSteps = RecipeRepository.aiStepIndexesOf(
      recipe,
    ).where((i) => i < steps).length;
    final detail = pending
        ? 'AI จะเขียนวัตถุดิบและวิธีทำให้ใหม่'
        : 'วัตถุดิบ $ingredients อย่าง · $steps ขั้นตอน';
    final aiText = pending
        ? 'ใช้ AI เพิ่ม และอาจรอนานขึ้นเล็กน้อย'
        : steps > 0 && aiSteps == steps
        ? 'AI สร้างขั้นตอนทั้งหมด'
        : aiSteps > 0
        ? 'AI เติมให้ $aiSteps ขั้นตอน'
        : 'ไม่มีขั้นตอนที่ AI แต่งเพิ่ม';

    return Material(
      color: kRecipeBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 30, color: Colors.black87),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (name != null && name!.trim().isNotEmpty)
                      Text(
                        name!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(detail, style: const TextStyle(fontSize: 13)),
                    Text(
                      aiText,
                      style: TextStyle(
                        fontSize: 12,
                        color: pending || aiSteps > 0
                            ? const Color(0xFFD32F2F)
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
