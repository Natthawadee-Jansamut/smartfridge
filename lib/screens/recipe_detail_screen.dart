import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';
import '../widgets/recipe_flow_widgets.dart';
import '../widgets/deduct_confirm_sheet.dart';
import '../services/fridge_stock.dart';
import '../services/recipe_repository.dart';
import '../widgets/add_recipe_widgets.dart';

/// หน้ารายละเอียดสูตรอาหารที่บันทึกไว้ (ตามดีไซน์ใน Figma: "Smart Recipe" หน้าเมนู)
/// เปิดจากการกดเลือกสูตรในหน้าคลังสูตรอาหาร
/// เทียบวัตถุดิบที่ต้องใช้กับของจริงในตู้เย็น (Supabase) แบบสดเสมอ
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final List<Map<String, dynamic>>
  inventory; // รับข้อมูลคลังเพื่อเอามาเทียบหักลบ
  // ข้อความบนแคปซูลหัวเรื่อง — ค่าเริ่มต้นใช้กับสูตรที่บันทึกไว้แล้ว
  // ส่วนตอนเปิดจากหน้า "สร้างเมนูอาหาร (AI)" จะส่ง "เมนูแนะนำ" มาแทน
  // ให้ตรงกับดีไซน์ Figma ของแต่ละที่มา
  final String headerTitle;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.inventory,
    this.headerTitle = "สูตรเมนูอาหาร",
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isCooking = false;
  bool _isDeleting = false;

  // แปลงค่าจำนวนให้เป็นตัวเลขแบบทนทาน เผื่อ AI ตอบ use_quantity มาเป็น
  // ข้อความปนหน่วย (เช่น "1 ลูก") หรือเป็นเศษส่วน (เช่น "1/2") แทนที่จะเป็น
  // ตัวเลขล้วนๆ ตามที่ขอไว้ในพรอมป์เป๊ะๆ เสมอไป ถ้าแปลงตรงๆ ไม่ได้เลยจะได้
  // ลองดึงแค่ตัวเลขนำหน้าออกมาก่อน แทนที่จะปัดเป็น 0 แล้วข้ามการหักไปเฉยๆ
  num _toNum(dynamic v) {
    if (v is num) return v;
    final text = v?.toString().trim() ?? '';
    if (text.isEmpty) return 0;

    final direct = num.tryParse(text);
    if (direct != null) return direct;

    final fraction = RegExp(r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)').firstMatch(text);
    if (fraction != null) {
      final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
      final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
      return denominator == 0 ? 0 : numerator / denominator;
    }

    final leadingNumber = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    return double.tryParse(leadingNumber?.group(0) ?? '') ?? 0;
  }

  // แสดง "ไม่ได้ระบุ" แทนที่จะปล่อยว่างเปล่า เมื่อ AI ไม่ได้ระบุปริมาณ/หน่วยของ
  // วัตถุดิบชิ้นนั้นมาให้ (เช่น รูปสูตรต้นฉบับไม่ได้เขียนปริมาณกำกับไว้)
  String _formatQty(Map<String, dynamic> ing) {
    final qty = ing['use_quantity'];
    final unit = (ing['unit'] ?? '').toString().trim();
    final qtyText = (qty == null || qty.toString().trim().isEmpty)
        ? ''
        : qty.toString().trim();
    final combined = [qtyText, unit].where((s) => s.isNotEmpty).join(' ');
    return combined.isEmpty ? 'ไม่ได้ระบุ' : combined;
  }

  // เช็คว่าวัตถุดิบที่สูตรต้องการ มีในตู้เย็นพอไหม (เทียบชื่อ + จำนวน)
  bool _isIngredientAvailable(Map<String, dynamic> needed) {
    final neededName = (needed['name'] ?? '').toString().trim().toLowerCase();
    final neededQty = _toNum(needed['use_quantity']);
    // รวมทุกลอตของวัตถุดิบชื่อนี้ (ซื้อซ้ำจะแยกเป็นคนละลอตตามหลัก FIFO)
    final match = widget.inventory
        .where((inv) => ingredientNameMatches(inv['name'], neededName))
        .toList();
    if (match.isEmpty) return false;
    final haveQty = availableQuantity(widget.inventory, neededName);
    return haveQty >= neededQty;
  }

  // ฟังก์ชันหักวัตถุดิบออกจาก Supabase
  Future<void> _startCooking() async {
    List<dynamic> detailedIngredients =
        widget.recipe['detailed_ingredients'] ?? [];

    // ให้ผู้ใช้ยืนยันก่อนว่าใช้ไปเท่าไหร่จริง (กดเลือกแบบกะด้วยตา ไม่ต้องชั่ง)
    // ค่าเริ่มต้นตามที่สูตรบอก — กดยกเลิกก็ไม่หักอะไรเลย
    final choices = await showDeductConfirmSheet(
      context,
      inventory: widget.inventory,
      requests: [
        for (final needed in detailedIngredients)
          if ((needed['name'] ?? '').toString().trim().isNotEmpty)
            DeductRequest(
              name: needed['name'].toString(),
              suggested: _toNum(needed['use_quantity']),
            ),
      ],
    );
    if (choices == null || !mounted) return;

    setState(() => _isCooking = true);

    try {
      final supabase = Supabase.instance.client;

      int deductedCount = 0;
      List<String> notFoundNames = [];
      // เก็บ error จริงตอนยิง update ไป Supabase แยกจากกรณี "หาไม่เจอในคลัง"
      // เพราะสาเหตุคนละแบบกัน (เช่น ฐานข้อมูลปฏิเสธสิทธิ์แก้ไข ไม่ใช่แค่หา
      // วัตถุดิบไม่เจอ) ผู้ใช้จะได้รู้ว่าจริงๆ แล้วเกิดอะไรขึ้นกันแน่
      List<String> updateErrors = [];

      // สำเนาคลังไว้หักในเครื่องด้วย จะได้เห็นจำนวนล่าสุดถ้าเมนูใช้วัตถุดิบ
      // ชื่อเดียวกันซ้ำ (ไม่แก้ลิสต์ของหน้าก่อนหน้าโดยตรง)
      final inventory = widget.inventory
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // หักตามปริมาณที่ผู้ใช้ยืนยันแบบ FIFO (ลอตที่ใกล้หมดอายุ/เก่าที่สุดก่อน
      // ถ้าไม่พอหักลอตถัดไปต่อ) ผ่าน fridge_stock.dart
      for (final choice in choices) {
        if (choice.amount == null) {
          notFoundNames.add(choice.name);
          continue;
        }
        if (choice.amount! <= 0) continue; // ผู้ใช้เลือก "ไม่ได้ใช้"

        final result = await deductIngredientFifo(
          supabase: supabase,
          inventory: inventory,
          name: choice.name,
          amount: choice.amount!,
        );

        if (!result.found) {
          notFoundNames.add(choice.name);
        } else if (result.error != null) {
          updateErrors.add("${choice.name}: ${result.error}");
        } else {
          deductedCount++;
        }
      }

      if (mounted) {
        final hasNotFound = notFoundNames.isNotEmpty;
        final hasUpdateError = updateErrors.isNotEmpty;
        String message;
        Color bgColor;

        if (hasUpdateError) {
          // ฐานข้อมูลปฏิเสธการอัปเดตจริงๆ (เช่นสิทธิ์ไม่พอ) ต้องโชว์ error ตรงๆ
          // ไม่งั้นจะดูเหมือนกดแล้วไม่มีอะไรเกิดขึ้นเลย ทั้งที่จริงๆ error
          message = "หักวัตถุดิบไม่สำเร็จบางรายการ: ${updateErrors.join(' | ')}";
          bgColor = Colors.red;
        } else if (deductedCount == 0 && !hasNotFound) {
          // ผู้ใช้เลือก "ไม่ได้ใช้" ทุกรายการในหน้ายืนยัน
          message = "ทำอาหารเสร็จสิ้น! ไม่ได้หักวัตถุดิบออกจากตู้เย็น";
          bgColor = Colors.green;
        } else if (deductedCount == 0) {
          // ไม่พบวัตถุดิบที่ตรงกันในคลังเลยสักชิ้น ไม่ควรบอกว่า "เรียบร้อยแล้ว"
          message = "ไม่พบวัตถุดิบที่ตรงกับในคลังเลย จึงยังไม่ได้หักอะไรออก "
              "(${notFoundNames.join(', ')})";
          bgColor = Colors.orange;
        } else if (hasNotFound) {
          message =
              "หักวัตถุดิบไปแล้ว $deductedCount รายการ แต่หาไม่เจอในคลัง: "
              "${notFoundNames.join(', ')}";
          bgColor = Colors.orange;
        } else {
          message = "ทำอาหารเสร็จสิ้น! หักวัตถุดิบเรียบร้อยแล้ว 🍲";
          bgColor = Colors.green;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: bgColor),
        );
        // ถ้ามีที่หักสำเร็จอย่างน้อย 1 ชิ้น ค่อยบอกหน้าเดิมให้รีเฟรชตู้เย็น
        Navigator.pop(context, deductedCount > 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("เกิดข้อผิดพลาด: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCooking = false);
    }
  }

  // ลบสูตรอาหารนี้ออกจาก Supabase จริง
  Future<void> _deleteRecipe() async {
    final recipeName = widget.recipe['recipe_name'] ?? 'สูตรนี้';
    final confirm =
        await showDialog<bool>(
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
        ) ??
        false;

    if (!confirm) return;

    setState(() => _isDeleting = true);
    try {
      await Supabase.instance.client
          .from('scanned_recipes')
          .delete()
          .eq('id', widget.recipe['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ลบสูตรอาหารเรียบร้อยแล้ว"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // กลับไปหน้ารายการแล้วรีเฟรช
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ลบไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    // ขั้นตอนการทำ + ตำแหน่งขั้นตอนที่ AI คิดเพิ่ม (แสดงเป็นสีแดง)
    final steps = RecipeRepository.stepTextsOf(recipe);
    final aiSteps = RecipeRepository.aiStepIndexesOf(recipe);
    List<dynamic> detailedIngredients = recipe['detailed_ingredients'] ?? [];

    final availableCount = detailedIngredients
        .where((e) => _isIngredientAvailable(Map<String, dynamic>.from(e)))
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            RecipeFlowHeader(title: widget.headerTitle),
            const SizedBox(height: 15),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ชื่อเมนู (กล่องขาวตรงกลาง ตามดีไซน์)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // สถานะวัตถุดิบ (ของจริงจากฐานข้อมูล ไม่ใช่ mock)
                    RecipeStatusBar(
                      label: "สถานะวัตถุดิบ",
                      have: availableCount,
                      total: detailedIngredients.length,
                    ),
                    const SizedBox(height: 20),

                    // วัตถุดิบที่ต้องใช้
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "วัตถุดิบที่ต้องใช้",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              const EditPillButton(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ...detailedIngredients.map((ing) {
                            final ingMap = Map<String, dynamic>.from(ing);
                            final available = _isIngredientAvailable(ingMap);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        child: available
                                            ? const CheckIcon(size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        ingMap['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _formatQty(ingMap),
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ขั้นตอนการทำ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "ขั้นตอนการทำ",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              const EditPillButton(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // ขั้นตอนที่ AI คิดเพิ่ม = ตัวหนังสือสีแดง + ป้าย "AI"
                          RecipeStepsView(
                            steps: steps,
                            aiIndexes: aiSteps,
                            fontSize: 15,
                            spacing: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ปุ่มด้านล่าง: ลบสูตรนี้ / เริ่มทำอาหาร (หักวัตถุดิบ)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    height: 55,
                    width: 55,
                    child: OutlinedButton(
                      onPressed: _isDeleting ? null : _deleteRecipe,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isDeleting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.redAccent,
                              ),
                            )
                          : const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isCooking ? null : _startCooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7D0),
                          foregroundColor: const Color(0xff5189C9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: _isCooking
                            ? const CircularProgressIndicator(
                                color: Color(0xff5189C9),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.soup_kitchen,
                                    size: 24,
                                    color: Color(0xff5189C9),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    "Cooking (หักวัตถุดิบ)",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xff5189C9),
                                    ),
                                  ),
                                ],
                              ),
                      ),
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
}
