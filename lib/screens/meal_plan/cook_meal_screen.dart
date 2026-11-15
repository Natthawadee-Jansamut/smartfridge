import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/services/fridge_stock.dart'; // หักวัตถุดิบ FIFO
import 'package:test_app/services/gemini_retry.dart'; // ข้อความ error ของ AI
import 'package:test_app/services/meal_nutrition.dart'; // คำนวณโภชนาการใหม่
import 'package:test_app/services/plan_allocation.dart'; // จองของให้มื้อในแพลน
import 'package:test_app/services/shopping_suggestion.dart'; // ของพื้นฐาน
import 'package:test_app/widgets/deduct_confirm_sheet.dart'; // แผ่นยืนยันหักวัตถุดิบ
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';

/// หน้า "ทำอาหาร" ของมื้ออาหารหนึ่งมื้อ (ตามดีไซน์ Figma กลุ่ม PLANNING)
/// ใช้ลวดลายการ์ดเดียวกับหน้า "สูตรอาหารที่บันทึกไว้" (recipe_detail_screen.dart)
/// เพื่อให้ UI ตรงกัน — ต่างกันแค่ข้อความ/แหล่งข้อมูล (มาจาก weekly_meals แทน
/// recipes / user_saved_recipes) แสดง/แก้ไขวัตถุดิบและขั้นตอนการทำจากของจริงใน Supabase
/// เท่านั้น (ไม่มีข้อมูล mock) และเมื่อกด "ทำแล้ว" จะหักวัตถุดิบที่ใช้ออกจาก
/// ตู้เย็นจริงด้วย
class CookMealScreen extends StatefulWidget {
  final String mealId; // id ของมื้อที่จะแสดง

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

  Map<String, dynamic>? meal; // ข้อมูลมื้อ
  bool loading = true; // กำลังโหลดไหม
  bool saving = false; // กำลังบันทึก "ทำแล้ว" ไหม

  /// มื้อนี้กด "ทำแล้ว" (หักวัตถุดิบ) ไปแล้ว -> ห้ามกดซ้ำ
  bool get _cooked => meal?['is_cooked'] == true;
  bool recalculating = false; // กำลังคำนวณโภชนาการใหม่ไหม

  final Map<String, String> _dayThai = const { // [UI] ชื่อวันภาษาไทย
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
    _loadMeal(); // เปิดหน้ามาโหลดข้อมูลมื้อ
  }

  // โหลดข้อมูลมื้อ แล้วตรวจว่ามีวัตถุดิบในตู้จริงไหม
  Future<void> _loadMeal() async {
    try {
      await ShoppingSuggestion.loadStaples(); // โหลดรายการของพื้นฐาน
      final data = await supabase
          .from('weekly_meals') // ดึงมื้อนี้
          .select()
          .eq('id', widget.mealId)
          .single(); // เอาแถวเดียว

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
            await supabase.from('fridge_items').select().eq('user_id', user.id), // ดึงของในตู้
          );
          // จองของในตู้ให้มื้อที่ใกล้ถึงก่อน (ทั้งแพลน) แล้วติ๊กตามผลของมื้อนี้
          // สถานะจะตรงกับหน้าแผนรายสัปดาห์ และไม่ติ๊กของที่จองให้มื้อก่อนหน้าไปแล้ว
          final planId = loadedMeal['plan_id'];
          Map<String, List<IngredientStatus>>? allocation;
          if (planId != null) {
            try {
              final planMeals = await supabase
                  .from('weekly_meals') // ดึงมื้อทั้งแพลน
                  .select()
                  .eq('plan_id', planId);
              final plan = await supabase
                  .from('meal_plans') // ดึงวันที่สร้างแพลน
                  .select('created_at')
                  .eq('id', planId)
                  .maybeSingle();
              allocation = PlanAllocation.allocate( // จองของให้ทุกมื้อในแพลน
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
          final statuses = allocation?[widget.mealId]; // ผลของมื้อนี้
          if (statuses != null) {
            ingredientsList = [ // มีผลจองทั้งแพลน -> ติ๊กตามผลนั้น
              for (final ing in ingredientsList)
                {
                  ...ing,
                  'checked': // มีพอ = ติ๊ก
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
            ingredientsList = _withRealAvailability( // จองทั้งแพลนไม่ได้ -> เช็คเฉพาะมื้อนี้
              ingredientsList,
              fridgeItems,
            );
          }
          loadedMeal['ingredients'] = ingredientsList;
        }
      }

      if (mounted) {
        setState(() { // อัปเดตหน้าจอ
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
      final needAmount = _parseQuantityAmount( // จำนวนที่ต้องใช้
        ing['quantity']?.toString() ?? '',
      );

      if (name.isEmpty) { // ไม่มีชื่อ = ไม่ติ๊ก
        return {...ing, 'checked': false};
      }

      // ของพื้นฐาน (ข้าว เครื่องปรุง ฯลฯ) ถือว่ามีในบ้านเสมอ
      if (ShoppingSuggestion.isStaple(name)) {
        return {...ing, 'checked': true};
      }

      final matches = fridgeItems.where((item) { // หาของในตู้ที่ชื่อตรง/คล้าย
        final itemName = (item['name']?.toString() ?? '').trim().toLowerCase();
        return itemName.isNotEmpty &&
            (itemName == name ||
                itemName.contains(name) ||
                name.contains(itemName));
      }).toList();

      bool isAvailable;
      if (matches.isEmpty) {
        isAvailable = false; // ไม่มีในตู้
      } else {
        final haveQty = matches.fold<num>(0, (sum, item) { // รวมจำนวนทุกลอต
          final q = item['quantity'];
          final qNum = q is num ? q : (num.tryParse(q?.toString() ?? '') ?? 0);
          return sum + qNum;
        });
        isAvailable = haveQty > 0 && (needAmount <= 0 || haveQty >= needAmount); // มีของ และพอ (ถ้าไม่รู้จำนวนที่ต้องใช้ แค่มีก็พอ)
      }

      return {...ing, 'checked': isAvailable};
    }).toList();
  }

  // รายการวัตถุดิบของมื้อ (ผิดรูปแบบ = ลิสต์ว่าง)
  List<Map<String, dynamic>> get _ingredients {
    final raw = meal?['ingredients'];
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  // บันทึกรายการวัตถุดิบ (อัปเดตจอก่อน แล้วบันทึกฐานข้อมูล)
  Future<void> _saveIngredients(List<Map<String, dynamic>> updated) async {
    setState(() {
      meal = {...?meal, 'ingredients': updated};
    });

    try {
      await supabase
          .from('weekly_meals')
          .update({'ingredients': updated}) // บันทึกลงฐานข้อมูล
          .eq('id', widget.mealId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกวัตถุดิบไม่สำเร็จ: $e")));
    }
  }

  // แตะแถววัตถุดิบ -> สลับติ๊ก
  void _toggleChecked(int index, bool value) {
    final updated = _ingredients;
    updated[index] = {...updated[index], 'checked': value};
    _saveIngredients(updated);
  }

  // ป๊อปอัปแก้รายการวัตถุดิบ (ชื่อ + ปริมาณ)
  Future<void> _editIngredientsDialog() async {
    final controllers = _ingredients // สร้างช่องกรอกให้ทุกวัตถุดิบเดิม
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
        return StatefulBuilder( // ให้ป๊อปอัปวาดใหม่ได้ตอนเพิ่ม/ลบแถว
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("แก้ไขวัตถุดิบที่ต้องใช้"),
              content: SizedBox(
                width: double.maxFinite, // [UI] กว้างเต็มป๊อปอัป
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(controllers.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10), // [UI] ระยะใต้แถว
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3, // [UI] ช่องชื่อกว้าง 3 ส่วน
                                child: TextField(
                                  controller:
                                      controllers[i]['name']
                                          as TextEditingController,
                                  decoration: const InputDecoration(
                                    labelText: "วัตถุดิบ",
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8), // [UI] ระยะระหว่างช่อง
                              Expanded(
                                flex: 2, // [UI] ช่องปริมาณกว้าง 2 ส่วน
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
                                  size: 18, // [UI] ไอคอน X ขนาด 18
                                  color: Colors.red, // [UI] สีแดง
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    controllers.removeAt(i); // ลบแถวนี้
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
                            controllers.add({ // เพิ่มแถวว่าง
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
                        .map((c) { // แปลงช่องกรอกเป็นวัตถุดิบ
                          final name = (c['name'] as TextEditingController).text
                              .trim();
                          final prev = existing.firstWhere( // หาข้อมูลเดิมของชื่อนี้
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
                            'checked': prev['checked'] == true, // คงสถานะติ๊กเดิม
                            if (toBuy) ShoppingSuggestion.toBuyKey: true,
                          };
                        })
                        .where((e) => (e['name'] as String).isNotEmpty) // ตัดแถวที่ไม่มีชื่อ
                        .toList();
                    // วัตถุดิบเปลี่ยนจริง (ชื่อ/ปริมาณ/จำนวนรายการ) -> แคลอรี/โปรตีน
                    // ไม่ตรงแล้ว ติดธงไว้ให้ผู้ใช้กด "คำนวณใหม่"
                    String key(Map e) =>
                        '${e['name']}|${(e['quantity'] ?? '').toString().trim()}';
                    final changed = // รายการเปลี่ยนจริงไหม
                        existing.map(key).join('\n') !=
                        updated.map(key).join('\n');
                    final wasStale = MealNutrition.isStale(meal); // เดิมติดธงอยู่แล้วไหม
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
                      for (final e in updated) { // ติดธง "ต้องคำนวณใหม่" ทุกแถว
                        e[MealNutrition.staleKey] = true;
                        if (base != null) e[MealNutrition.baseKey] = base;
                      }
                    }
                    Navigator.pop(context); // ปิดป๊อปอัป
                    _saveIngredients(updated); // บันทึก
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

  // ป๊อปอัปแก้ขั้นตอน (กล่องข้อความหลายบรรทัด)
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
            maxLines: 8, // [UI] สูง 8 บรรทัด
            decoration: const InputDecoration(
              hintText: "กรุณาเพิ่มขั้นตอนการทำอาหาร...",
              border: OutlineInputBorder(), // [UI] กรอบรอบช่อง
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
                  meal = {...?meal, 'steps': text}; // อัปเดตจอก่อน
                });

                try {
                  await supabase // บันทึกลงฐานข้อมูล
                      .from('weekly_meals')
                      .update({'steps': text})
                      .eq('id', widget.mealId);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar( // เตรียมแสดงแถบข้อความด้านล่างจอ
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
    final match = RegExp( // หาเศษส่วน
      r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)',
    ).firstMatch(qtyText);
    if (match != null) {
      final numerator = double.tryParse(match.group(1) ?? '') ?? 0;
      final denominator = double.tryParse(match.group(3) ?? '') ?? 1;
      return denominator == 0 ? 0 : numerator / denominator; // กันหารด้วย 0
    }
    final single = RegExp(r'\d+(\.\d+)?').firstMatch(qtyText); // ไม่มีเศษส่วน -> ตัวเลขแรก
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
    int deducted = 0; // นับที่หักสำเร็จ
    List<String> notFound = []; // ชื่อที่หาไม่เจอ
    List<String> errors = []; // error ตอนบันทึก

    // หักตามปริมาณที่ผู้ใช้ยืนยันแบบ FIFO: ลอตที่ใกล้หมดอายุ/เก่าที่สุดก่อน
    // ถ้าลอตนั้นไม่พอก็หักลอตถัดไปต่อจนครบ (ดู fridge_stock.dart) วัตถุดิบชิ้น
    // ไหนอัปเดตไม่ผ่าน ชิ้นอื่นยังหักต่อได้ตามปกติ
    for (final choice in choices) {
      if (choice.amount == null) {
        notFound.add(choice.name); // ไม่มีในตู้
        continue;
      }
      if (choice.amount! <= 0) continue; // ผู้ใช้เลือก "ไม่ได้ใช้"

      final result = await deductIngredientFifo( // หักแบบ FIFO
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
        deducted++; // สำเร็จ
      }
    }

    return (deducted: deducted, notFound: notFound, errors: errors);
  }

  // กด "ทำแล้ว": ยืนยันจำนวน -> จองสถานะ "ทำแล้ว" -> หักวัตถุดิบ
  Future<void> _markAsCooked() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // ให้ผู้ใช้ยืนยันก่อนว่าใช้ไปเท่าไหร่จริง (กดเลือกแบบกะด้วยตา ไม่ต้องชั่ง)
    // ค่าเริ่มต้นตามที่แผนบอก — กดยกเลิกก็ไม่บันทึก/ไม่หักอะไรเลย
    final List<Map<String, dynamic>> fridgeItems;
    try {
      fridgeItems = List<Map<String, dynamic>>.from( // ดึงของในตู้ล่าสุด
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

    final choices = await showDeductConfirmSheet( // เปิดแผ่นยืนยันจำนวนที่ใช้
      context,
      inventory: fridgeItems,
      requests: [
        for (final ing in _ingredients)
          if ((ing['name']?.toString() ?? '').trim().isNotEmpty)
            DeductRequest( // คำขอหักวัตถุดิบ 1 รายการ
              name: ing['name'].toString(),
              suggested: _parseQuantityAmount(
                ing['quantity']?.toString() ?? '',
              ),
              // "2 ฟอง" / "1/2 ส่วน" -> ตัดตัวเลขข้างหน้าออก เหลือหน่วย
              unit: (ing['quantity']?.toString() ?? '')
                  .replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '')
                  .trim(),
              isStaple: ShoppingSuggestion.isStaple(ing['name'].toString()),
            ),
      ],
    );
    if (choices == null || !mounted) return; // กดยกเลิก -> ไม่ทำอะไร

    setState(() => saving = true); // เริ่มบันทึก

    // จองสถานะ "ทำแล้ว" ก่อนหักของ — อัปเดตเฉพาะเมื่อยังไม่เคยทำ (เงื่อนไขอยู่ใน
    // คำสั่งเดียวกัน) ถ้าไม่มีแถวถูกอัปเดต แปลว่ามื้อนี้ทำไปแล้ว (เปิดหน้าค้างไว้,
    // กดซ้ำเร็วๆ หรือกดจากอีกเครื่อง) -> ไม่หักวัตถุดิบซ้ำ
    final List claimed;
    try {
      claimed = await supabase
          .from('weekly_meals')
          .update({'is_cooked': true}) // ตั้งเป็นทำแล้ว
          .eq('id', widget.mealId)
          .not('is_cooked', 'is', true) // เฉพาะที่ยังไม่เคยทำ
          .select('id'); // ขอ id กลับมาเช็คว่าอัปเดตจริง
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
      }
      return;
    }
    if (claimed.isEmpty) { // ไม่มีแถวถูกอัปเดต = ทำไปแล้ว
      if (!mounted) return;
      setState(() {
        saving = false;
        meal = {...?meal, 'is_cooked': true};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("มื้อนี้ทำไปแล้ว ไม่ได้หักวัตถุดิบซ้ำ"),
          backgroundColor: Colors.orange, // [UI] แถบส้ม
        ),
      );
      return;
    }

    try {
      final result = await _deductFridgeIngredients(fridgeItems, choices); // หักวัตถุดิบ

      if (!mounted) return;

      // โชว์ผลลัพธ์ตรงกับที่เกิดขึ้นจริงกับตู้เย็น ไม่ใช่ข้อความสำเร็จตายตัว
      String message;
      Color bgColor;
      if (result.errors.isNotEmpty) {
        message = "หักวัตถุดิบไม่สำเร็จบางรายการ: ${result.errors.join(' | ')}";
        bgColor = Colors.red; // [UI] แดง
      } else if (result.deducted == 0) {
        message = result.notFound.isEmpty
            ? "บันทึกว่าทำแล้ว ไม่ได้หักวัตถุดิบออกจากตู้เย็น"
            : "บันทึกว่าทำแล้ว แต่หาวัตถุดิบในคลังไม่เจอ: "
                  "${result.notFound.join(', ')}";
        bgColor = Colors.orange; // [UI] ส้ม
      } else if (result.notFound.isNotEmpty) {
        message =
            "หักวัตถุดิบไปแล้ว ${result.deducted} รายการ "
            "แต่หาไม่เจอในคลัง: ${result.notFound.join(', ')}";
        bgColor = Colors.orange; // [UI] ส้ม
      } else {
        message = "ทำอาหารเสร็จสิ้น! หักวัตถุดิบเรียบร้อยแล้ว 🍲";
        bgColor = Colors.green; // [UI] เขียว
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: bgColor),
      );
      Navigator.pop(context, true); // ปิดหน้า ส่ง true
    } catch (e) {
      // หักของล้มเหลวทั้งก้อน -> คืนสถานะ "ยังไม่ทำ" ให้กดใหม่ได้
      try {
        await supabase
            .from('weekly_meals')
            .update({'is_cooked': false}) // คืนสถานะยังไม่ทำ
            .eq('id', widget.mealId);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("บันทึกไม่สำเร็จ: $e")));
    } finally {
      if (mounted) setState(() => saving = false); // หยุดโหลด
    }
  }

  // กด "คำนวณใหม่" -> ให้ AI คำนวณแคลอรี/โปรตีนใหม่
  Future<void> _recalculateNutrition() async {
    final current = meal;
    if (current == null) return;
    setState(() => recalculating = true); // เริ่มโหลด
    try {
      final updated = await MealNutrition.recalculate(current); // ให้ AI คำนวณและบันทึก
      if (!mounted) return;
      setState(() => meal = {...?meal, ...updated}); // อัปเดตจอ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "คำนวณใหม่แล้ว ✅ ${updated['calories']} kcal · "
            "โปรตีน ${updated['protein']} g",
          ),
          backgroundColor: Colors.green, // [UI] แถบเขียว
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiErrorMessage(e, fallback: 'คำนวณค่าโภชนาการไม่สำเร็จ'),
          ),
          backgroundColor: Colors.red, // [UI] แถบแดง
        ),
      );
    } finally {
      if (mounted) setState(() => recalculating = false);
    }
  }

  /// การ์ดพลังงาน/โปรตีนของมื้อนี้ + เตือนเมื่อแก้วัตถุดิบแล้วค่ายังเป็นของเมนูเดิม
  Widget _nutritionCard() {
    final stale = MealNutrition.isStale(meal); // ค่าโภชนาการเก่าไหม
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14), // [UI] ระยะในการ์ด
      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นขาว
        borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง
        border: stale
            ? Border.all(color: const Color(0xffE67E22), width: 1.4) // [UI] ค่าเก่า = ขอบส้มหนา 1.4
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
                  color: Colors.orange, // [UI] แคลอรีสีส้ม
                  fontWeight: FontWeight.bold,
                  fontSize: 16, // [UI] ขนาด 16
                ),
              ),
              const SizedBox(width: 20), // [UI] ระยะระหว่างแคลอรีกับโปรตีน
              Text(
                "โปรตีน ${meal?['protein'] ?? 0} g",
                style: const TextStyle(
                  color: Colors.blue, // [UI] โปรตีนสีฟ้า
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(), // ดันปุ่มไปชิดขวา
              // ยังไม่ได้แก้วัตถุดิบก็คำนวณใหม่ได้ เผื่อตัวเลขจากตอนสร้างแพลนไม่สมจริง
              // (คำนวณจากวัตถุดิบจริงทั้งหมด) — มื้อที่แก้แล้วใช้ปุ่มใหญ่ด้านล่างแทน
              if (!stale)
                recalculating
                    ? const SizedBox(
                        width: 18, // [UI] ขนาดวงหมุน
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        onPressed: _recalculateNutrition,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact, // [UI] ปุ่มกระชับ
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          size: 18, // [UI] ไอคอนรีเฟรช ขนาด 18
                          color: Color(0xff5189C9),
                        ),
                        label: const Text(
                          "คำนวณใหม่",
                          style: TextStyle(
                            fontSize: 13, // [UI] ขนาด 13
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
              style: TextStyle(fontSize: 13, color: Color(0xffB85C00)), // [UI] ขนาด 13 สีส้มเข้ม
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity, // [UI] ปุ่มกว้างเต็ม
              child: OutlinedButton.icon(
                onPressed: recalculating ? null : _recalculateNutrition,
                icon: recalculating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18), // [UI] ไอคอนประกาย ขนาด 18
                label: Text(
                  recalculating ? "กำลังคำนวณ..." : "คำนวณแคลอรีและโปรตีนใหม่",
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffB85C00), // [UI] สีตัวอักษรส้มเข้ม
                  side: const BorderSide(color: Color(0xffE67E22), width: 1.4), // [UI] ขอบส้มหนา 1.4
                  padding: const EdgeInsets.symmetric(vertical: 12), // [UI] ความสูงปุ่ม
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
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
    final dayLabel = _dayThai[meal?['day']] ?? ''; // ชื่อวันภาษาไทย
    final mealType = meal?['meal_type']?.toString() ?? ''; // ชื่อมื้อ
    final foodName = meal?['food_name']?.toString() ?? ''; // ชื่อเมนู
    final ingredients = _ingredients; // วัตถุดิบ
    final checkedCount = ingredients.where((e) => e['checked'] == true).length; // จำนวนที่ติ๊กแล้ว
    final steps = meal?['steps']?.toString() ?? ''; // ขั้นตอน (ข้อความ)
    final stepLines = steps // แยกเป็นบรรทัด ตัดบรรทัดว่าง
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator()) // กำลังโหลด
            : Column(
                children: [
                  const SizedBox(height: 15), // [UI] ระยะจากขอบบน
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
                    child: Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(context), // ย้อนกลับ
                          child: Container(
                            height: 45, // [UI] ขนาดปุ่ม 45x45
                            width: 45,
                            decoration: BoxDecoration(
                              color: const Color(0xfffff7d0), // [UI] สีครีม
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(child: BackIcon(size: 20)), // [UI] ไอคอนย้อนกลับ
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 50, // [UI] ความสูงแคปซูล
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7D0), // [UI] สีครีม
                              borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                            ),
                            child: Row(
                              children: [
                                const CalendarIcon(size: 20), // [UI] ไอคอนปฏิทิน
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.previewOnly
                                        ? "ดูสูตร $mealType $dayLabel"
                                        : "ทำอาหาร $mealType $dayLabel",
                                    overflow: TextOverflow.ellipsis, // [UI] ยาวเกินตัดเป็น ...
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16, // [UI] ขนาดชื่อหน้า
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
                  const SizedBox(height: 20), // [UI] ระยะห่างหัวกับเนื้อหา
                  Expanded(
                    // ให้ดึงลงเพื่อรีเฟรชได้ทุกเมื่อ เผื่อของในคลังถูกแก้ไข
                    // จากหน้าจออื่นระหว่างที่ค้างอยู่หน้านี้ (เช่น หักสต็อก
                    // จากเมนูอื่น หรือเพิ่ม/ลบวัตถุดิบในคลัง) จะได้เห็นสถานะ
                    // "สถานะวัตถุดิบ" ที่ตรงกับของจริงเสมอ ไม่ใช่แค่ตอนเปิด
                    // หน้าครั้งแรกเท่านั้น
                    child: RefreshIndicator(
                      onRefresh: _loadMeal, // ดึงลงเพื่อโหลดใหม่
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะซ้ายขวา
                        children: [
                          // ชื่อเมนู — กล่องขาวตรงกลาง ตามดีไซน์เดียวกับหน้า
                          // สูตรอาหารที่บันทึกไว้ (recipe_detail_screen.dart)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14), // [UI] ระยะในบนล่าง
                            decoration: BoxDecoration(
                              color: Colors.white, // [UI] พื้นขาว
                              borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              foodName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16, // [UI] ขนาดชื่อเมนู
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _nutritionCard(), // การ์ดโภชนาการ
                          const SizedBox(height: 20),

                          // สถานะวัตถุดิบ (แถบความคืบหน้า ของจริงจากฐานข้อมูล)
                          RecipeStatusBar( // แถบสถานะวัตถุดิบ
                            label: "สถานะวัตถุดิบ",
                            have: checkedCount,
                            total: ingredients.length,
                          ),
                          const SizedBox(height: 20),

                          // วัตถุดิบที่ต้องใช้
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
                            decoration: BoxDecoration(
                              color: Colors.white, // [UI] พื้นขาว
                              borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 5, // [UI] ความฟุ้งเงา
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
                                        horizontal: 14, // [UI] ระยะในป้าย
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF7D0), // [UI] สีป้าย (ครีม)
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        "วัตถุดิบที่ต้องใช้",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14, // [UI] ขนาดป้าย
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    EditPillButton( // ปุ่มแก้ไขวัตถุดิบ
                                      onTap: _editIngredientsDialog,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (ingredients.isEmpty) // ไม่มีวัตถุดิบ
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      "ยังไม่มีวัตถุดิบ กด \"แก้ไข\" เพื่อเพิ่ม",
                                      style: TextStyle(
                                        color: Colors.grey.shade600, // [UI] สีเทา
                                      ),
                                    ),
                                  )
                                else
                                  ...List.generate(ingredients.length, (index) { // แถววัตถุดิบ
                                    final ing = ingredients[index];
                                    final checked = ing['checked'] == true;
                                    return InkWell(
                                      onTap: () => // แตะสลับติ๊ก
                                          _toggleChecked(index, !checked),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10.0, // [UI] ระยะใต้แถว
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                SizedBox(
                                                  width: 20, // [UI] ช่องไอคอนกว้าง 20
                                                  child: checked
                                                      ? const CheckIcon( // [UI] ติ๊กถูก ขนาด 18
                                                          size: 18,
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  ing['name']?.toString() ?? '',
                                                  style: const TextStyle(
                                                    fontSize: 15, // [UI] ขนาดชื่อ
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              ing['quantity']?.toString() ?? '',
                                              style: TextStyle(
                                                color: Colors.grey.shade700, // [UI] ปริมาณสีเทา
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
                            padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 5, // [UI] ความฟุ้งเงา
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
                                        color: const Color(0xFFFFF7D0), // [UI] สีป้าย
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        "ขั้นตอนการทำ",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14, // [UI] ขนาดป้าย
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    EditPillButton(onTap: _editStepsDialog), // ปุ่มแก้ไขขั้นตอน
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (stepLines.isEmpty) // ยังไม่มีขั้นตอน
                                  Text(
                                    "กรุณาเพิ่มขั้นตอนการทำอาหาร...",
                                    style: TextStyle(
                                      color: Colors.grey.shade500, // [UI] สีเทา
                                    ),
                                  )
                                else
                                  ...stepLines.map((step) { // แสดงขั้นตอนทีละบรรทัด
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12.0, // [UI] ระยะใต้แต่ละขั้น
                                      ),
                                      child: Text(
                                        step,
                                        style: const TextStyle(
                                          fontSize: 15, // [UI] ขนาดตัวอักษร
                                          height: 1.5, // [UI] ระยะบรรทัด 1.5
                                          color: Colors.black87,
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100), // [UI] ระยะว่างท้าย (กันโดนแถบปุ่มบัง)
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
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 20), // [UI] ระยะรอบกล่อง
                padding: const EdgeInsets.symmetric(vertical: 14), // [UI] ระยะในบนล่าง
                decoration: BoxDecoration(
                  color: Colors.white, // [UI] พื้นขาว
                  borderRadius: BorderRadius.circular(25), // [UI] มุมโค้ง
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xff3F9142)), // [UI] ไอคอนติ๊กสีเขียว
                    SizedBox(width: 8),
                    Text(
                      "ทำมื้อนี้แล้ว (หักวัตถุดิบไปแล้ว)",
                      style: TextStyle(fontWeight: FontWeight.bold), // [UI] ตัวหนา
                    ),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20), // [UI] ระยะรอบแถบปุ่ม
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48, // [UI] ความสูงปุ่ม
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E0E0), // [UI] ปุ่มยกเลิกสีเทา
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                          ),
                        ),
                        onPressed: () => Navigator.pop(context), // ยกเลิก = ออกจากหน้า
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
                      height: 48, // [UI] ความสูงปุ่ม
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7D0), // [UI] ปุ่ม "ทำแล้ว" สีครีม
                          foregroundColor: Colors.black87,
                          elevation: 0, // [UI] ไม่มีเงา
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        onPressed: saving ? null : _markAsCooked, // กำลังบันทึก = กดไม่ได้
                        icon: saving
                            ? const SizedBox(
                                width: 16, // [UI] ขนาดวงหมุน
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check, size: 18), // [UI] ไอคอนติ๊ก ขนาด 18
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
