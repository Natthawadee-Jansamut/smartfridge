import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/services/meal_nutrition.dart';
import 'package:test_app/services/plan_allocation.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/widgets/deduct_confirm_sheet.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';

/// หน้า "ทำอาหาร" ของมื้ออาหารหนึ่งมื้อ (ตามดีไซน์ Figma กลุ่ม PLANNING)
/// ใช้ลวดลายการ์ดเดียวกับหน้า "สูตรอาหารที่บันทึกไว้" (recipe_detail_screen.dart)
/// เพื่อให้ UI ตรงกัน — ต่างกันแค่ข้อความ/แหล่งข้อมูล (มาจาก weekly_meals แทน
/// recipes / user_saved_recipes) แสดง/แก้ไขวัตถุดิบและขั้นตอนการทำจากของจริงใน Supabase
/// เท่านั้น (ไม่มีข้อมูล mock) และเมื่อกด "ทำแล้ว" จะหักวัตถุดิบที่ใช้ออกจาก
/// ตู้เย็นจริงด้วย
class CookMealScreen extends StatefulWidget {
  final String mealId;

  /// true = เปิดดูก่อนบันทึกแพลน: ดู/แก้สูตรได้ แต่ไม่มีปุ่ม "ทำแล้ว" (ยังไม่หักของ)
  final bool previewOnly;

  const CookMealScreen({
    super.key,
    required this.mealId,
    this.previewOnly = false,
  });

  @override
  State<CookMealScreen> createState() => _CookMealScreenState();
}

class _CookMealScreenState extends State<CookMealScreen> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? meal;
  bool loading = true;
  bool saving = false;

  /// มื้อนี้กด "ทำแล้ว" (หักวัตถุดิบ) ไปแล้ว -> ห้ามกดซ้ำ
  bool get _cooked => meal?['is_cooked'] == true;
  bool recalculating = false;

  final Map<String, String> _dayThai = const {
    "Monday": "วันจันทร์",
    "Tuesday": "วันอังคาร",
    "Wednesday": "วันพุธ",
    "Thursday": "วันพฤหัสบดี",
    "Friday": "วันศุกร์",
    "Saturday": "วันเสาร์",
    "Sunday": "วันอาทิตย์",
  };

  @override
  void initState() {
    super.initState();
    _loadMeal();
  }

  Future<void> _loadMeal() async {
    try {
      await ShoppingSuggestion.loadStaples();
      final data = await supabase
          .from('weekly_meals')
          .select()
          .eq('id', widget.mealId)
          .single();

      final loadedMeal = Map<String, dynamic>.from(data);

      // ตรวจสถานะวัตถุดิบจริงจากคลัง (fridge_items) ทุกครั้งที่เปิดหน้านี้
      // แทนที่จะเชื่อค่า checked เดิมที่บันทึกไว้ตอนสร้างแผน (ซึ่งจะติ๊กถูก
      // ไว้หมดโดยไม่ได้เทียบกับของจริงในตู้เย็นเลย) — ถ้าวัตถุดิบไม่มีในคลัง
      // หรือมีไม่พอตามจำนวนที่สูตรต้องใช้ ต้องไม่ติ๊กให้
      final rawIngredients = loadedMeal['ingredients'];
      List<Map<String, dynamic>> ingredientsList = rawIngredients is List
          ? rawIngredients.map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      if (ingredientsList.isNotEmpty) {
        final user = supabase.auth.currentUser;
        if (user != null) {
          final fridgeItems = List<Map<String, dynamic>>.from(
            await supabase.from('fridge_items').select().eq('user_id', user.id),
          );
          // จองของในตู้ให้มื้อที่ใกล้ถึงก่อน (ทั้งแพลน) แล้วติ๊กตามผลของมื้อนี้
          // สถานะจะตรงกับหน้าแผนรายสัปดาห์ และไม่ติ๊กของที่จองให้มื้อก่อนหน้าไปแล้ว
          final planId = loadedMeal['plan_id'];
          Map<String, List<IngredientStatus>>? allocation;
          if (planId != null) {
            try {
              final planMeals = await supabase
                  .from('weekly_meals')
                  .select()
                  .eq('plan_id', planId);
              final plan = await supabase
                  .from('meal_plans')
                  .select('created_at')
                  .eq('id', planId)
                  .maybeSingle();
              allocation = PlanAllocation.allocate(
                meals: planMeals,
                fridgeItems: fridgeItems,
                planStart: DateTime.tryParse(
                  plan?['created_at']?.toString() ?? '',
                )?.toLocal(),
              );
            } catch (e) {
              debugPrint('จองวัตถุดิบทั้งแพลนไม่สำเร็จ (เช็กเฉพาะมื้อนี้): $e');
            }
          }
          final statuses = allocation?[widget.mealId];
          if (statuses != null) {
            ingredientsList = [
              for (final ing in ingredientsList)
                {
                  ...ing,
                  'checked':
                      statuses
                          .where(
                            (st) =>
                                st.name ==
                                (ing['name'] ?? '').toString().trim(),
                          )
                          .firstOrNull
                          ?.have ??
                      false,
                },
            ];
          } else {
            ingredientsList = _withRealAvailability(
              ingredientsList,
              fridgeItems,
            );
          }
          loadedMeal['ingredients'] = ingredientsList;
        }
      }

      if (mounted) {
        setState(() {
          meal = loadedMeal;
          loading = false;
        });
      }
    } catch (e) {
      debugPrint('โหลดข้อมูลมื้ออาหารไม่สำเร็จ: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  // เทียบวัตถุดิบที่สูตรต้องใช้กับของจริงในคลัง (ชื่อเทียบแบบยืดหยุ่น
  // เหมือนตอนหักสต็อกจริง) แล้วคืนรายการวัตถุดิบพร้อมค่า checked ที่ตรงกับ
  // สถานะจริง: ติ๊กถูกก็ต่อเมื่อเจอวัตถุดิบชื่อตรงกัน "และ" มีจำนวนพอใช้
  // ตามที่สูตรต้องการ ถ้าไม่มีในคลังเลยหรือมีไม่พอ จะไม่ติ๊กให้
  List<Map<String, dynamic>> _withRealAvailability(
    List<Map<String, dynamic>> ingredients,
    List<Map<String, dynamic>> fridgeItems,
  ) {
    return ingredients.map((ing) {
      final nameRaw = ing['name']?.toString() ?? '';
      final name = nameRaw.trim().toLowerCase();
      final needAmount = _parseQuantityAmount(
        ing['quantity']?.toString() ?? '',
      );

      if (name.isEmpty) {
        return {...ing, 'checked': false};
      }

      // ของพื้นฐาน (ข้าว เครื่องปรุง ฯลฯ) ถือว่ามีในบ้านเสมอ
      if (ShoppingSuggestion.isStaple(name)) {
        return {...ing, 'checked': true};
      }

      final matches = fridgeItems.where((item) {
        final itemName = (item['name']?.toString() ?? '').trim().toLowerCase();
        return itemName.isNotEmpty &&
            (itemName == name ||
                itemName.contains(name) ||
                name.contains(itemName));
      }).toList();

      bool isAvailable;
      if (matches.isEmpty) {
        isAvailable = false;
      } else {
        final haveQty = matches.fold<num>(0, (sum, item) {
          final q = item['quantity'];
          final qNum = q is num ? q : (num.tryParse(q?.toString() ?? '') ?? 0);
          return sum + qNum;
        });
        isAvailable = haveQty > 0 && (needAmount <= 0 || haveQty >= needAmount);
      }

      return {...ing, 'checked': isAvailable};
    }).toList();
  }

  List<Map<String, dynamic>> get _ingredients {
    final raw = meal?['ingredients'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> _saveIngredients(List<Map<String, dynamic>> updated) async {
    setState(() {
      meal = {...?meal, 'ingredients': updated};
    });

    try {
      await supabase
          .from('weekly_meals')
          .update({'ingredients': updated})
          .eq('id', widget.mealId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกวัตถุดิบไม่สำเร็จ: $e")));
    }
  }

  void _toggleChecked(int index, bool value) {
    final updated = _ingredients;
    updated[index] = {...updated[index], 'checked': value};
    _saveIngredients(updated);
  }

  Future<void> _editIngredientsDialog() async {
    final controllers = _ingredients
        .map(
          (e) => {
            'name': TextEditingController(text: e['name']?.toString() ?? ''),
            'quantity': TextEditingController(
              text: e['quantity']?.toString() ?? '',
            ),
          },
        )
        .toList();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("แก้ไขวัตถุดิบที่ต้องใช้"),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(controllers.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller:
                                      controllers[i]['name']
                                          as TextEditingController,
                                  decoration: const InputDecoration(
                                    labelText: "วัตถุดิบ",
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller:
                                      controllers[i]['quantity']
                                          as TextEditingController,
                                  decoration: const InputDecoration(
                                    labelText: "ปริมาณ",
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    controllers.removeAt(i);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            controllers.add({
                              'name': TextEditingController(),
                              'quantity': TextEditingController(),
                            });
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("เพิ่มวัตถุดิบ"),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ยกเลิก"),
                ),
                TextButton(
                  onPressed: () {
                    // เก็บสถานะติ๊กเดิมไว้ถ้าชื่อวัตถุดิบไม่เปลี่ยน ไม่งั้นเริ่มใหม่
                    final existing = _ingredients;
                    final updated = controllers
                        .map((c) {
                          final name = (c['name'] as TextEditingController).text
                              .trim();
                          final prev = existing.firstWhere(
                            (e) => (e['name']?.toString() ?? '') == name,
                            orElse: () => {},
                          );
                          // ต้องซื้อ: รายการเดิมเก็บธงเดิมไว้ (แก้ปริมาณไม่ทำให้
                          // หายจากรายการซื้อของ) ส่วนรายการที่เพิ่มใหม่ถือว่าต้องซื้อ
                          // ยกเว้นของพื้นฐาน — ถ้ามีในตู้อยู่แล้ว แผนรายสัปดาห์จะไม่
                          // แสดงในรายการซื้อของเอง
                          final toBuy = prev.isEmpty
                              ? !ShoppingSuggestion.isStaple(name)
                              : prev[ShoppingSuggestion.toBuyKey] == true;
                          return <String, dynamic>{
                            'name': name,
                            'quantity': (c['quantity'] as TextEditingController)
                                .text
                                .trim(),
                            'checked': prev['checked'] == true,
                            if (toBuy) ShoppingSuggestion.toBuyKey: true,
                          };
                        })
                        .where((e) => (e['name'] as String).isNotEmpty)
                        .toList();
                    // วัตถุดิบเปลี่ยนจริง (ชื่อ/ปริมาณ/จำนวนรายการ) -> แคลอรี/โปรตีน
                    // ไม่ตรงแล้ว ติดธงไว้ให้ผู้ใช้กด "คำนวณใหม่"
                    String key(Map e) =>
                        '${e['name']}|${(e['quantity'] ?? '').toString().trim()}';
                    final changed =
                        existing.map(key).join('\n') !=
                        updated.map(key).join('\n');
                    final wasStale = MealNutrition.isStale(meal);
                    if (changed || wasStale) {
                      // จำ "ค่าเดิม" (วัตถุดิบ + แคลอรี/โปรตีนก่อนแก้ครั้งแรก) ไว้
                      // ให้ตอนคำนวณใหม่ ปรับจากค่าเดิมตามส่วนที่เปลี่ยน
                      // ถ้าแก้มาก่อนแล้วแต่ไม่มีค่าเดิม (แก้ก่อนมีฟีเจอร์นี้) ห้าม
                      // จำตอนนี้ เพราะตัวเลขเป็นของวัตถุดิบชุดที่เก่ากว่านี้
                      final base =
                          MealNutrition.baseOf(meal) ??
                          (wasStale
                              ? null
                              : MealNutrition.snapshot(meal, existing));
                      for (final e in updated) {
                        e[MealNutrition.staleKey] = true;
                        if (base != null) e[MealNutrition.baseKey] = base;
                      }
                    }
                    Navigator.pop(context);
                    _saveIngredients(updated);
                  },
                  child: const Text("บันทึก"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editStepsDialog() async {
    final controller = TextEditingController(
      text: meal?['steps']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("แก้ไขขั้นตอนการทำ"),
          content: TextField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: "กรุณาเพิ่มขั้นตอนการทำอาหาร...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ยกเลิก"),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                Navigator.pop(context);

                setState(() {
                  meal = {...?meal, 'steps': text};
                });

                try {
                  await supabase
                      .from('weekly_meals')
                      .update({'steps': text})
                      .eq('id', widget.mealId);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("บันทึกขั้นตอนไม่สำเร็จ: $e")),
                  );
                }
              },
              child: const Text("บันทึก"),
            ),
          ],
        );
      },
    );
  }

  // แยกตัวเลขปริมาณออกจากข้อความ เช่น "1 ชิ้น" -> 1, "1/2 หัว" -> 0.5
  // เพื่อเอาไปหักออกจากจำนวนจริงในตู้เย็น
  double _parseQuantityAmount(String qtyText) {
    final match = RegExp(
      r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)',
    ).firstMatch(qtyText);
    if (match != null) {
      final numerator = double.tryParse(match.group(1) ?? '') ?? 0;
      final denominator = double.tryParse(match.group(3) ?? '') ?? 1;
      return denominator == 0 ? 0 : numerator / denominator;
    }
    final single = RegExp(r'\d+(\.\d+)?').firstMatch(qtyText);
    return double.tryParse(single?.group(0) ?? '') ?? 0;
  }

  // หักวัตถุดิบที่ใช้ในมื้อนี้ออกจาก fridge_items จริง (เทียบชื่อแบบยืดหยุ่น
  // เหมือนตอนสร้างแผน) กดทำแล้วแล้วของในตู้เย็นต้องลดลงจริง ไม่ใช่แค่ติ๊กในแอป
  // คืนผลจริงว่าหักไปกี่ชิ้น / หาไม่เจอชื่ออะไรบ้าง / อัปเดตไม่ผ่านเพราะอะไร
  // เพื่อให้ _markAsCooked() โชว์ผลลัพธ์ตรงกับที่เกิดขึ้นจริง แทนที่จะขึ้นว่า
  // "หักวัตถุดิบเรียบร้อยแล้ว" ทั้งที่จริงๆ อาจไม่ได้หักอะไรออกไปเลยสักชิ้น
  Future<({int deducted, List<String> notFound, List<String> errors})>
  _deductFridgeIngredients(
    List<Map<String, dynamic>> fridgeItems,
    List<DeductChoice> choices,
  ) async {
    int deducted = 0;
    List<String> notFound = [];
    List<String> errors = [];

    // หักตามปริมาณที่ผู้ใช้ยืนยันแบบ FIFO: ลอตที่ใกล้หมดอายุ/เก่าที่สุดก่อน
    // ถ้าลอตนั้นไม่พอก็หักลอตถัดไปต่อจนครบ (ดู fridge_stock.dart) วัตถุดิบชิ้น
    // ไหนอัปเดตไม่ผ่าน ชิ้นอื่นยังหักต่อได้ตามปกติ
    for (final choice in choices) {
      if (choice.amount == null) {
        notFound.add(choice.name);
        continue;
      }
      if (choice.amount! <= 0) continue; // ผู้ใช้เลือก "ไม่ได้ใช้"

      final result = await deductIngredientFifo(
        supabase: supabase,
        inventory: fridgeItems,
        name: choice.name,
        amount: choice.amount!,
      );

      if (!result.found) {
        notFound.add(choice.name);
      } else if (result.error != null) {
        errors.add("${choice.name}: ${result.error}");
      } else {
        deducted++;
      }
    }

    return (deducted: deducted, notFound: notFound, errors: errors);
  }

  Future<void> _markAsCooked() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // ให้ผู้ใช้ยืนยันก่อนว่าใช้ไปเท่าไหร่จริง (กดเลือกแบบกะด้วยตา ไม่ต้องชั่ง)
    // ค่าเริ่มต้นตามที่แผนบอก — กดยกเลิกก็ไม่บันทึก/ไม่หักอะไรเลย
    final List<Map<String, dynamic>> fridgeItems;
    try {
      fridgeItems = List<Map<String, dynamic>>.from(
        await supabase.from('fridge_items').select().eq('user_id', user.id),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("โหลดวัตถุดิบไม่สำเร็จ: $e")));
      return;
    }
    if (!mounted) return;

    final choices = await showDeductConfirmSheet(
      context,
      inventory: fridgeItems,
      requests: [
        for (final ing in _ingredients)
          if ((ing['name']?.toString() ?? '').trim().isNotEmpty)
            DeductRequest(
              name: ing['name'].toString(),
              suggested: _parseQuantityAmount(
                ing['quantity']?.toString() ?? '',
              ),
              // "2 ฟอง" / "1/2 ส่วน" -> ตัดตัวเลขข้างหน้าออก เหลือหน่วย
              unit: (ing['quantity']?.toString() ?? '')
                  .replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '')
                  .trim(),
            ),
      ],
    );
    if (choices == null || !mounted) return;

    setState(() => saving = true);

    // จองสถานะ "ทำแล้ว" ก่อนหักของ — อัปเดตเฉพาะเมื่อยังไม่เคยทำ (เงื่อนไขอยู่ใน
    // คำสั่งเดียวกัน) ถ้าไม่มีแถวถูกอัปเดต แปลว่ามื้อนี้ทำไปแล้ว (เปิดหน้าค้างไว้,
    // กดซ้ำเร็วๆ หรือกดจากอีกเครื่อง) -> ไม่หักวัตถุดิบซ้ำ
    final List claimed;
    try {
      claimed = await supabase
          .from('weekly_meals')
          .update({'is_cooked': true})
          .eq('id', widget.mealId)
          .not('is_cooked', 'is', true)
          .select('id');
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
      }
      return;
    }
    if (claimed.isEmpty) {
      if (!mounted) return;
      setState(() {
        saving = false;
        meal = {...?meal, 'is_cooked': true};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("มื้อนี้ทำไปแล้ว ไม่ได้หักวัตถุดิบซ้ำ"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final result = await _deductFridgeIngredients(fridgeItems, choices);

      if (!mounted) return;

      // โชว์ผลลัพธ์ตรงกับที่เกิดขึ้นจริงกับตู้เย็น ไม่ใช่ข้อความสำเร็จตายตัว
      String message;
      Color bgColor;
      if (result.errors.isNotEmpty) {
        message = "หักวัตถุดิบไม่สำเร็จบางรายการ: ${result.errors.join(' | ')}";
        bgColor = Colors.red;
      } else if (result.deducted == 0) {
        message = result.notFound.isEmpty
            ? "บันทึกว่าทำแล้ว ไม่ได้หักวัตถุดิบออกจากตู้เย็น"
            : "บันทึกว่าทำแล้ว แต่หาวัตถุดิบในคลังไม่เจอ: "
                  "${result.notFound.join(', ')}";
        bgColor = Colors.orange;
      } else if (result.notFound.isNotEmpty) {
        message =
            "หักวัตถุดิบไปแล้ว ${result.deducted} รายการ "
            "แต่หาไม่เจอในคลัง: ${result.notFound.join(', ')}";
        bgColor = Colors.orange;
      } else {
        message = "ทำอาหารเสร็จสิ้น! หักวัตถุดิบเรียบร้อยแล้ว 🍲";
        bgColor = Colors.green;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: bgColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // หักของล้มเหลวทั้งก้อน -> คืนสถานะ "ยังไม่ทำ" ให้กดใหม่ได้
      try {
        await supabase
            .from('weekly_meals')
            .update({'is_cooked': false})
            .eq('id', widget.mealId);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _recalculateNutrition() async {
    final current = meal;
    if (current == null) return;
    setState(() => recalculating = true);
    try {
      final updated = await MealNutrition.recalculate(current);
      if (!mounted) return;
      setState(() => meal = {...?meal, ...updated});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "คำนวณใหม่แล้ว ✅ ${updated['calories']} kcal · "
            "โปรตีน ${updated['protein']} g",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiErrorMessage(e, fallback: 'คำนวณค่าโภชนาการไม่สำเร็จ'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => recalculating = false);
    }
  }

  /// การ์ดพลังงาน/โปรตีนของมื้อนี้ + เตือนเมื่อแก้วัตถุดิบแล้วค่ายังเป็นของเมนูเดิม
  Widget _nutritionCard() {
    final stale = MealNutrition.isStale(meal);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: stale
            ? Border.all(color: const Color(0xffE67E22), width: 1.4)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "${meal?['calories'] ?? 0} kcal",
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 20),
              Text(
                "โปรตีน ${meal?['protein'] ?? 0} g",
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              // ยังไม่ได้แก้วัตถุดิบก็คำนวณใหม่ได้ เผื่อตัวเลขจากตอนสร้างแพลนไม่สมจริง
              // (คำนวณจากวัตถุดิบจริงทั้งหมด) — มื้อที่แก้แล้วใช้ปุ่มใหญ่ด้านล่างแทน
              if (!stale)
                recalculating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        onPressed: _recalculateNutrition,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Color(0xff5189C9),
                        ),
                        label: const Text(
                          "คำนวณใหม่",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xff5189C9),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
            ],
          ),
          if (stale) ...[
            const SizedBox(height: 8),
            const Text(
              "⚠️ แก้วัตถุดิบแล้ว ค่าโภชนาการยังเป็นของเมนูเดิม",
              style: TextStyle(fontSize: 13, color: Color(0xffB85C00)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: recalculating ? null : _recalculateNutrition,
                icon: recalculating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(
                  recalculating ? "กำลังคำนวณ..." : "คำนวณแคลอรีและโปรตีนใหม่",
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffB85C00),
                  side: const BorderSide(color: Color(0xffE67E22), width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = _dayThai[meal?['day']] ?? '';
    final mealType = meal?['meal_type']?.toString() ?? '';
    final foodName = meal?['food_name']?.toString() ?? '';
    final ingredients = _ingredients;
    final checkedCount = ingredients.where((e) => e['checked'] == true).length;
    final steps = meal?['steps']?.toString() ?? '';
    final stepLines = steps
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const SizedBox(height: 15),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 45,
                            width: 45,
                            decoration: BoxDecoration(
                              color: const Color(0xfffff7d0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(child: BackIcon(size: 20)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7D0),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              children: [
                                const CalendarIcon(size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.previewOnly
                                        ? "ดูสูตร $mealType $dayLabel"
                                        : "ทำอาหาร $mealType $dayLabel",
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    // ให้ดึงลงเพื่อรีเฟรชได้ทุกเมื่อ เผื่อของในคลังถูกแก้ไข
                    // จากหน้าจออื่นระหว่างที่ค้างอยู่หน้านี้ (เช่น หักสต็อก
                    // จากเมนูอื่น หรือเพิ่ม/ลบวัตถุดิบในคลัง) จะได้เห็นสถานะ
                    // "สถานะวัตถุดิบ" ที่ตรงกับของจริงเสมอ ไม่ใช่แค่ตอนเปิด
                    // หน้าครั้งแรกเท่านั้น
                    child: RefreshIndicator(
                      onRefresh: _loadMeal,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          // ชื่อเมนู — กล่องขาวตรงกลาง ตามดีไซน์เดียวกับหน้า
                          // สูตรอาหารที่บันทึกไว้ (recipe_detail_screen.dart)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              foodName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _nutritionCard(),
                          const SizedBox(height: 20),

                          // สถานะวัตถุดิบ (แถบความคืบหน้า ของจริงจากฐานข้อมูล)
                          RecipeStatusBar(
                            label: "สถานะวัตถุดิบ",
                            have: checkedCount,
                            total: ingredients.length,
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                    EditPillButton(
                                      onTap: _editIngredientsDialog,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (ingredients.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      "ยังไม่มีวัตถุดิบ กด \"แก้ไข\" เพื่อเพิ่ม",
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  )
                                else
                                  ...List.generate(ingredients.length, (index) {
                                    final ing = ingredients[index];
                                    final checked = ing['checked'] == true;
                                    return InkWell(
                                      onTap: () =>
                                          _toggleChecked(index, !checked),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  child: checked
                                                      ? const CheckIcon(
                                                          size: 18,
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  ing['name']?.toString() ?? '',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              ing['quantity']?.toString() ?? '',
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                    EditPillButton(onTap: _editStepsDialog),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (stepLines.isEmpty)
                                  Text(
                                    "กรุณาเพิ่มขั้นตอนการทำอาหาร...",
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                    ),
                                  )
                                else
                                  ...stepLines.map((step) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12.0,
                                      ),
                                      child: Text(
                                        step,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.5,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      // ดูสูตรก่อนบันทึกแพลน -> ไม่มีปุ่ม "ทำแล้ว" (กลับด้วยปุ่มย้อนกลับด้านบน)
      bottomNavigationBar: loading || widget.previewOnly
          ? null
          : _cooked
          // ทำไปแล้ว -> ไม่มีปุ่ม "ทำแล้ว" ให้กดซ้ำ (กันหักวัตถุดิบซ้ำ)
          ? SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xff3F9142)),
                    SizedBox(width: 8),
                    Text(
                      "ทำมื้อนี้แล้ว (หักวัตถุดิบไปแล้ว)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E0E0),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "ยกเลิก",
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7D0),
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: saving ? null : _markAsCooked,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: const Text(
                          "ทำแล้ว",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
