import 'dart:convert'; // jsonDecode
import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล
import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini
import 'package:test_app/screens/shared/recipe_detail_screen.dart'; // ✅ นำเข้าหน้าใหม่
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';
import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/services/non_food_check.dart';

// หน้า "สร้างเมนูอาหาร" จากของในตู้เย็น (หาในคลังสูตรก่อน ไม่พอค่อยให้ AI คิด)
class AiRecipeScreen extends StatefulWidget {
  const AiRecipeScreen({super.key});

  @override
  State<AiRecipeScreen> createState() => _AiRecipeScreenState();
}

class _AiRecipeScreenState extends State<AiRecipeScreen> {
  bool _isLoadingData = true; // กำลังโหลดของในตู้ไหม
  bool _isGenerating = false; // AI กำลังคิดเมนูอยู่ไหม

  List<Map<String, dynamic>> _inventory = []; // ของในตู้ทั้งหมด
  List<Map<String, dynamic>> _oldItems = []; // ของที่ควรใช้ก่อน (ใกล้ครบกำหนด)

  // วัตถุดิบทุกชิ้นที่ยังเหลืออยู่ เรียงจากอยู่ในตู้เย็นนานที่สุด ใช้แสดงในการ์ด
  // "วัตถุดิบในตู้เย็น" (แสดงเสมอ ไม่ใช่เฉพาะของที่อยู่นานเกินกำหนด)
  List<Map<String, dynamic>> _fridgeByAge = [];
  int _aheadDays = defaultOldItemDays; // เตือนล่วงหน้ากี่วัน
  List<dynamic> _generatedRecipes = []; // เก็บเมนูที่ AI สร้างให้

  // ชื่อเมนูที่เคยแสดงไปแล้วในหน้านี้ — กด "สร้างเมนูอาหาร" ซ้ำจะได้เมนูใหม่
  // (ไม่งั้นคลังสูตรจะคืนเมนูชุดเดิมทุกครั้ง เพราะเรียงลำดับแบบเดิม)
  final Set<String> _shownNames = {};

  // ตัวแปรสำหรับ Filter
  String _selectedCategory = 'ทั้งหมด'; // ประเภทอาหารที่เลือก
  final List<String> _categories = ['ทั้งหมด', 'อาหารไทย', 'คลีน', 'คีโต']; // [UI] ตัวเลือกประเภทอาหาร (แก้/เพิ่มได้)

  String _selectedTime = 'ไม่จำกัด'; // เวลาทำที่เลือก
  final List<String> _times = [ // [UI] ตัวเลือกเวลาทำ
    'ไม่จำกัด',
    '< 15 นาที',
    '< 30 นาที',
    '< 1 ชั่วโมง',
  ];

  // แปลงตัวเลือกเวลาที่เลือกไว้ให้เป็นข้อความบอก Gemini แบบชัดเจนเป็นตัวเลข
  // นาทีตรงๆ (ไม่ใช่ส่งข้อความดิบอย่าง "< 30 นาที" ไปตรงๆ) เพื่อให้โมเดล
  // เข้าใจเงื่อนไขแม่นยำขึ้นและเมนูที่ได้ใช้เวลาทำสอดคล้องกับที่ผู้ใช้เลือกจริง
  String _timeConstraintForPrompt() {
    switch (_selectedTime) {
      case '< 15 นาที':
        return 'ต้องทำเสร็จภายใน 15 นาที';
      case '< 30 นาที':
        return 'ต้องทำเสร็จภายใน 30 นาที';
      case '< 1 ชั่วโมง':
        return 'ต้องทำเสร็จภายใน 60 นาที';
      default:
        return 'เท่าไหร่ก็ได้';
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchInventory(); // เปิดหน้ามาโหลดของในตู้
  }

  // 1. ดึงข้อมูลวัตถุดิบจาก Supabase
  Future<void> _fetchInventory() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('fridge_items').select(); // ดึงของในตู้ทั้งหมด
      final data = List<Map<String, dynamic>>.from(response);

      List<Map<String, dynamic>> oldItems = []; // ของที่ควรใช้ก่อน
      List<Map<String, dynamic>> byAge = []; // ของทั้งหมดเรียงตามวันที่เหลือ
      final aheadDays = readOldItemDays(supabase.auth.currentUser); // อ่านค่าเตือนล่วงหน้า

      for (var item in data) { // ไล่ทีละชิ้น
        // ถ้าใช้วัตถุดิบชิ้นนี้หมดแล้ว (เช่น กดทำอาหารจนหักจำนวนเหลือ 0) ก็ไม่
        // ควรโผล่ในลิสต์ "อยู่ในตู้เย็นนาน" อีกต่อไป เพราะไม่มีของเหลือให้ต้องรีบ
        // ใช้แล้ว (ของที่ไม่มีระบุจำนวนไว้ ให้ถือว่ายังมีของอยู่ตามเดิม)
        if (isUsedUp(item)) continue;

        final days = daysInFridge(item['created_at']); // อยู่ในตู้มากี่วัน
        item['days_in_fridge'] = days; // เก็บค่าไว้ใช้แสดงผล
        byAge.add(item);
        // ควรเอาไปทำอาหารก่อน: เก็บได้อีกไม่เกินจำนวนวันที่ตั้งไว้ในหน้าตั้งค่า
        // แจ้งเตือน (นับเป็นวัน ไม่ใช้เปอร์เซ็นต์) และยังไม่เกินกำหนด
        if (shouldUseFirst(item, aheadDays) &&
            !NonFoodCheck.isNotForCooking(item['name'])) { // ไม่ใช่ของต้องห้าม (ยา/เหล้า ฯลฯ)
          oldItems.add(item);
        }
      }

      // เหลือวันน้อยที่สุดขึ้นก่อน ตรงกับ "เก็บได้อีก X วัน" ที่แสดงบนการ์ด
      // (เหมือนหน้าแจ้งเตือน) — ลำดับนี้ส่งให้ AI ใช้ของก่อนด้วย
      oldItems.sort(compareDaysLeft);
      byAge.sort(compareDaysLeft);

      setState(() { // อัปเดตหน้าจอ
        _inventory = data;
        _oldItems = oldItems;
        _fridgeByAge = byAge;
        _aheadDays = aheadDays;
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint("Error fetching inventory: $e"); // พิมพ์ข้อความไว้ดูตอนพัฒนา
      setState(() => _isLoadingData = false);
    }
  }

  // สีของ "เก็บได้อีก X วัน": ครบกำหนด/เกินแล้ว = แดง, เหลือไม่เกินจำนวนวันที่
  // ตั้งแจ้งเตือนไว้ = ส้ม, นอกนั้น = เขียว
  Color _daysLeftColor(int? left) {
    if (left == null) return Colors.black45; // ไม่มีข้อมูล = เทา
    if (left <= 0) return Colors.red; // [UI] ครบ/เกินกำหนด = แดง
    if (left <= _aheadDays) return Colors.orange.shade800; // [UI] ถึงช่วงเตือน = ส้ม
    return const Color(0xff3F9142); // [UI] ยังอีกนาน = เขียว
  }

  // จำชื่อเมนูที่แสดงแล้ว (กดสร้างรอบหน้าจะได้เมนูใหม่)
  void _rememberShown(List<Map<String, dynamic>> recipes) {
    for (final r in recipes) {
      final name = r['recipe_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) _shownNames.add(name);
    }
  }

  // 2. ส่งข้อมูลให้ Gemini คิดเมนู
  Future<void> _generateRecipes() async {
    if (_inventory.isEmpty) { // ตู้ว่าง -> แจ้งเตือน
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีวัตถุดิบในตู้เย็น กรุณาเพิ่มวัตถุดิบก่อน'),
        ),
      );
      return;
    }

    setState(() { // เริ่มโหลด
      _isGenerating = true;
      _generatedRecipes = []; // เคลียร์ของเก่า
    });

    try {
      // ===== 1) ค้นเมนูจากคลังสูตรกลาง (recipes) ก่อน — เจอครบไม่ต้องเรียก AI =====
      const wanted = 3; // ต้องการ 3 เมนู (แก้เลขเพื่อเปลี่ยนจำนวน)
      final usable = _inventory.where((e) => !isOverdue(e)).toList(); // ตัดของเกินกำหนดออก
      final maxMinutes = switch (_selectedTime) { // เวลาทำสูงสุดเป็นนาที
        '< 15 นาที' => 15,
        '< 30 นาที' => 30,
        '< 1 ชั่วโมง' => 60,
        _ => null,
      };
      List<Map<String, dynamic>> fromLibrary = [];
      try {
        final candidates = await RecipeRepository.findRecipesForFridge( // ค้นสูตรในคลังที่ทำได้จากของในตู้
          fridgeItems: usable,
          limit: 20, // ดูมา 20 สูตร
          useFirstNames: {for (final e in _oldItems) e['name'].toString()}, // ให้คะแนนสูตรที่ใช้ของควรใช้ก่อน
        );
        fromLibrary = candidates
            .where((r) { // กรองตามเงื่อนไข
              // เมนูที่เพิ่งแสดงไปแล้ว ข้ามไปเอาเมนูอื่น
              if (_shownNames.contains(r['recipe_name']?.toString().trim())) {
                return false;
              }
              // ประเภทอาหาร: ต้องมีแท็กตรงกับที่เลือก (ทั้งหมด = ไม่กรอง)
              if (_selectedCategory != 'ทั้งหมด' &&
                  !(r['diet_tags'] as List).contains(_selectedCategory)) {
                return false;
              }
              // เวลาทำ: ไม่รู้เวลา = ผ่านเฉพาะตอนไม่จำกัดเวลา
              final minutes = r['time_minutes'] as int?;
              if (maxMinutes != null &&
                  (minutes == null || minutes > maxMinutes)) {
                return false;
              }
              return true;
            })
            .take(wanted) // เอาแค่จำนวนที่ต้องการ
            .map((r) => {...r, 'from_library': true}) // ติดป้าย "จากคลังสูตร"
            .toList();
      } catch (e) {
        debugPrint('ค้นคลังสูตรไม่สำเร็จ (ใช้ AI แทน): $e');
      }

      if (fromLibrary.length >= wanted) { // ในคลังมีพอ -> ไม่ต้องเรียก AI
        for (final r in fromLibrary) {
          logAiRequest( // บันทึกว่าใช้คลัง (ไม่เปลือง AI)
            event: AiEvent.generateMenu,
            result: AiResult.cacheHit,
            recipeId: r['recipe_id'],
          );
        }
        setState(() => _generatedRecipes = fromLibrary);
        _rememberShown(fromLibrary);
        return;
      }
      final aiCount = wanted - fromLibrary.length; // ให้ AI คิดเฉพาะจำนวนที่ยังขาด
      // ห้าม AI ซ้ำทั้งเมนูจากคลังรอบนี้ และเมนูที่เคยแสดงไปแล้ว
      final libraryNames = { // ชื่อที่ห้ามซ้ำ
        ...fromLibrary.map((r) => r['recipe_name'].toString().trim()),
        ..._shownNames,
      }.join(', ');

      // ===== 2) ให้ AI คิดเฉพาะส่วนที่ยังขาด =====
      // ⚠️ ใส่ API Key ของคุณที่นี่
      final String apiKey = ApiKeys.aiRecipeScreen; // คีย์ AI ของหน้านี้

      // เตรียมรายชื่อวัตถุดิบเป็น Text (ไม่เอาของที่หมดแล้ว/เหลือ 0 ชิ้น มา
      // เสนอให้ AI ใช้ เพราะจริงๆ ไม่มีของเหลือให้ทำอาหารแล้ว)
      // (ลอตที่ชื่อ/หน่วยเดียวกันจะถูกรวมเป็นรายการเดียว)
      // ของที่เกินระยะที่เก็บได้แล้วไม่ส่งให้ AI เอาไปทำเมนู (อาจไม่ปลอดภัย
      // ให้ผู้ใช้ตรวจเองก่อน)
      String allItems = inventoryPromptList( // รายการของในตู้สำหรับ prompt
        _inventory.where((e) => !isOverdue(e)).toList(),
        withPerCook: true,
      );
      final useFirst = _oldItems // รายการของที่ควรใช้ก่อน
          .map((e) => "${e['name']} (${daysLeftText(daysLeft(e)!)})")
          .join(", ");

      // คำสั่งที่ส่งให้ AI (ข้อความในเครื่องหมาย """ คือสิ่งที่ AI อ่าน)
      final prompt = TextPart("""
        คุณคือเชฟอัจฉริยะ ช่วยคิดเมนูอาหาร $aiCount เมนู ที่สามารถทำได้จากวัตถุดิบเหล่านี้เป็นหลัก
        ${libraryNames.isEmpty ? '' : 'ห้ามซ้ำกับเมนูเหล่านี้: $libraryNames'}
        วัตถุดิบที่มี: $allItems
        วัตถุดิบที่ควรใช้ก่อน เรียงจากเก็บได้อีกน้อยวันที่สุด: ${useFirst.isEmpty ? 'ไม่มี' : useFirst}
        ถ้ามีวัตถุดิบที่ควรใช้ก่อน ทุกเมนูต้องใช้วัตถุดิบกลุ่มนี้อย่างน้อย 1 อย่าง (ตัวแรกๆ ก่อน)

        เงื่อนไขเพิ่มเติม:
        - ประเภทอาหาร: ${_selectedCategory == 'ทั้งหมด' ? 'อะไรก็ได้' : _selectedCategory}
        - เวลาทำ: ${_timeConstraintForPrompt()}

        สำคัญเรื่องปริมาณใน detailed_ingredients: ผู้ใช้ไม่ได้ชั่งตวง ให้ใช้หน่วยเดียวกับ
        วัตถุดิบที่มีในวงเล็บเท่านั้น (เช่น ส่วน, ฟอง, ผล, หัว) ห้ามใช้กรัม/กก./มล./ช้อน
        และ use_quantity ห้ามเกินจำนวนที่มี (1 ส่วน ≈ ใช้ทำอาหาร 1 ครั้ง ใช้ 0.5 ได้)
        ถ้าวัตถุดิบมี "ใช้ครั้งละ N" ในวงเล็บ (ผู้ใช้กำหนดเองว่าทำอาหาร 1 ครั้งใช้เท่านี้)
        ให้ use_quantity ของวัตถุดิบนั้น = N พอดี

        ถ้ารายการวัตถุดิบมีของที่ไม่ใช่อาหารหรือไม่ปลอดภัยต่อการบริโภค (เช่น ยา สารเคมี น้ำยาทำความสะอาด ของใช้) ห้ามนำมาใช้ในเมนูเด็ดขาด

        เครื่องปรุงพื้นฐานที่ทุกบ้านมีอยู่แล้ว (น้ำปลา ซีอิ๊ว ซอสหอยนางรม ซอสปรุงรส น้ำตาล เกลือ
        พริกไทย น้ำมันพืช ผงปรุงรส น้ำเปล่า) ใช้ได้เลยแม้ไม่อยู่ในรายการวัตถุดิบที่มี
        ให้ใส่ "is_staple": true และใช้หน่วยครัว เช่น ช้อนโต๊ะ ช้อนชา ได้
        (กติกาเรื่องหน่วยด้านบนใช้กับวัตถุดิบหลักเท่านั้น ไม่ใช้กับเครื่องปรุงพื้นฐาน)

        ตอบกลับมาเป็น JSON Array เท่านั้น ตามรูปแบบนี้เป๊ะๆ:
        [
          {
            "recipe_name": "ชื่อเมนู",
            "time": "เวลาทำ (เช่น 15 นาที)",
            "servings": "จำนวนที่ได้ (เช่น 2 ที่)",
            "ingredients_used": ["วัตถุดิบหลัก1", "วัตถุดิบหลัก2"],
            "detailed_ingredients": [
              {"name": "ชื่อวัตถุดิบให้ตรงกับที่มีเป๊ะๆ", "use_quantity": จำนวนเลข(ใส่แค่เลข), "unit": "หน่วยเดียวกับวัตถุดิบที่มี", "is_staple": false}
            ],
            "instructions": [
              "1. ขั้นตอนแรก...",
              "2. ขั้นตอนต่อไป..."
            ]
          }
        ]
        ห้ามใส่ Markdown ```json
      """);

      // Gemini ตอบ 503 "high demand" ได้เป็นพักๆ ลองใหม่อัตโนมัติก่อนแจ้ง error
      final response = await generateGemini( // ส่ง prompt ให้ Gemini
        apiKey: apiKey,
        logEvent: AiEvent.generateMenu, // บันทึกประวัติการใช้ AI
        content: [
          Content.multi([prompt]),
        ],
        timeout: const Duration(seconds: 60), // รอนานสุด 60 วินาที
      );

      if (response.text != null) {
        String cleanJson = response.text! // ล้างเครื่องหมาย ``` ออก
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        dynamic decoded = jsonDecode(cleanJson); // แปลงข้อความเป็นข้อมูล
        // เมนูที่ AI คิดให้ทั้งเมนู -> เวลาและจำนวนที่เป็นค่าที่ AI ประมาณเอง
        for (final r in decoded is List ? decoded : [decoded]) {
          if (r is Map) {
            r['time_estimated'] = true;
            r['servings_estimated'] = true;
          }
        }

        final aiRecipes = [ // ทำให้เป็นลิสต์ของ Map
          for (final r in decoded is List ? decoded : [decoded])
            if (r is Map) Map<String, dynamic>.from(r),
        ];
        // ===== 3) เก็บเมนูจาก AI ลงคลังสูตรกลาง ครั้งหน้าจะได้ไม่ต้องเรียก AI =====
        for (final r in aiRecipes) { // บันทึกเมนูจาก AI ลงคลังสูตรกลาง
          final id = await RecipeRepository.saveAiRecipe(
            r,
            dietTags: [if (_selectedCategory != 'ทั้งหมด') _selectedCategory],
          );
          if (id != null) r['recipe_id'] = id; // ได้ id ก็จำไว้
        }

        setState(() { // แสดงเมนูจากคลัง + จาก AI
          _generatedRecipes = [...fromLibrary, ...aiRecipes];
        });
        _rememberShown([...fromLibrary, ...aiRecipes]);
      }
    } catch (e) {
      if (!mounted) return; // หน้านี้ถูกปิดไปแล้ว ไม่ต้องแสดงข้อความ
      ScaffoldMessenger.of(context).showSnackBar( // แสดง error
        SnackBar(
          content: Text(geminiErrorMessage(e, fallback: 'สร้างเมนูไม่สำเร็จ')),
          backgroundColor: Colors.red, // [UI] แถบสีแดง
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false); // หยุดโหลด (ไม่ว่าสำเร็จหรือไม่)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFD8EEFF,
      ), // ฟ้าอ่อนให้ตรงกับดีไซน์ใหม่ทั้งแอป
      bottomNavigationBar: const AppBottomNav(current: AppTab.menu), // แถบเมนูล่าง ไฮไลต์ "เมนูอาหาร"
      body: _isLoadingData // กำลังโหลด -> วงหมุน
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xff5189C9)), // [UI] สีวงหมุน
            )
          : CustomScrollView( // รายการเลื่อนได้แบบประกอบหลายส่วน
              slivers: [
                // 1. Header (ตรงกับหน้าอื่นๆ ที่เป็น root ของ bottom-nav — ไม่มีปุ่มย้อนกลับ)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 15, // [UI] บน = แถบสถานะ + 15
                      left: 20, // [UI] ซ้าย 20
                      right: 20, // [UI] ขวา 20
                      bottom: 15, // [UI] ล่าง 15
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 50, // [UI] ความสูงแคปซูล
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7D0), // [UI] สีครีม
                              borderRadius: BorderRadius.circular(25), // [UI] ทรงแคปซูล
                            ),
                            child: const Row(
                              children: [
                                ChefIcon(size: 22), // [UI] ไอคอนหมวกเชฟ
                                SizedBox(width: 10),
                                Text(
                                  "สร้างเมนูอาหาร",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16, // [UI] ขนาดชื่อหน้า
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้ายขวา
                    child: Text(
                      "สร้างเมนูจากวัตถุดิบที่มี โดยใช้ของที่เก็บได้อีกน้อยวันก่อน",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13, // [UI] ขนาดคำอธิบาย
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)), // [UI] ระยะห่าง

                // 2. กล่องแจ้งเตือนของที่อยู่ในตู้เย็นนาน
                if (_fridgeByAge.isNotEmpty) // มีของในตู้ถึงแสดงกล่อง
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        padding: const EdgeInsets.all(16), // [UI] ระยะในกล่อง
                        decoration: BoxDecoration(
                          color: Colors.white, // [UI] พื้นขาว
                          borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง 12
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4, // [UI] ความฟุ้งเงา
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.black87,
                                  size: 20, // [UI] ไอคอนขนาด 20
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  "วัตถุดิบในตู้เย็น",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16, // [UI] ขนาดหัวข้อ
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._fridgeByAge.map((item) { // แถวของแต่ละชิ้น
                              final left = daysLeft(item); // เหลืออีกกี่วัน
                              final leftColor = _daysLeftColor(left); // สีตามจำนวนวัน
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 6.0, // [UI] ระยะใต้แถว
                                  left: 34, // [UI] เยื้องซ้าย 34 (ให้ตรงกับหัวข้อ)
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "${item['name']} (${item['quantity']} ${item['unit']})",
                                        style: const TextStyle(
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          fridgeAgeShort(item['created_at']),
                                          style: const TextStyle(
                                            color: Color(0xff5189C9), // [UI] สีฟ้า
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13, // [UI] ขนาด 13
                                          ),
                                        ),
                                        // นับเป็นวัน: เก็บได้อีก X วัน → ครบ
                                        // กำหนดวันนี้ → เกินมาแล้ว X วัน
                                        if (left != null)
                                          Text(
                                            daysLeftText(left),
                                            style: TextStyle(
                                              color: leftColor,
                                              fontSize: 12, // [UI] ขนาด 12
                                              fontWeight: left <= _aheadDays // [UI] ถึงช่วงเตือนเป็นตัวหนา
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ช่องว่างก่อนการ์ด "ประเภทอาหาร" — เดิมไม่มีช่องว่างตรงนี้เลย
                // ทำให้ระยะห่างระหว่างการ์ดแต่ละใบไม่เท่ากัน (การ์ดวัตถุดิบที่อยู่
                // นานติดกับการ์ดประเภทอาหารพอดี ในขณะที่การ์ดประเภทอาหารกับ
                // การ์ดเวลาห่างกัน 15) เพิ่มให้เท่ากับช่องว่างระหว่างการ์ดอื่นๆ
                // เพื่อให้จังหวะแนวตั้ง (Y) สม่ำเสมอตลอดทั้งหน้า
                if (_fridgeByAge.isNotEmpty)
                  const SliverToBoxAdapter(child: SizedBox(height: 15)), // [UI] ระยะห่างก่อนการ์ดตัวกรอง

                // 3. ตัวกรอง (Filter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0), // [UI] ระยะซ้ายขวา
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // การ์ดหุ้ม "ประเภทอาหาร" ทั้งชุด (ป้ายหัวข้อ + แถวปุ่มเลือก)
                        // ตามดีไซน์ Figma แทนที่จะปล่อยลอยอยู่บนพื้นหลังตรงๆ
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16), // [UI] ระยะในการ์ด
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20
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
                              _buildSectionLabel("ประเภทอาหาร"),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal, // [UI] เลื่อนแนวนอนได้
                                child: Row(
                                  children: _categories
                                      .map(
                                        (e) => _buildFilterChip(
                                          e,
                                          _selectedCategory,
                                          (v) => setState(
                                            () => _selectedCategory = v, // เลือกประเภท
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15), // [UI] ระยะห่างระหว่างการ์ด
                        // การ์ดหุ้ม "เวลาในการทำ" ทั้งชุด เหมือนกัน
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
                              _buildSectionLabel("เวลาในการทำ"),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _times
                                      .map(
                                        (e) => _buildFilterChip(
                                          e,
                                          _selectedTime,
                                          (v) =>
                                              setState(() => _selectedTime = v), // เลือกเวลา
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20), // [UI] ระยะก่อนปุ่ม

                        // ปุ่มสร้างเมนู
                        SizedBox(
                          width: double.infinity,
                          height: 50, // [UI] ความสูงปุ่ม
                          child: ElevatedButton(
                            onPressed: _isGenerating ? null : _generateRecipes, // กำลังสร้าง = กดไม่ได้
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFF7D0), // [UI] สีปุ่ม (ครีม)
                              foregroundColor: Colors.black87, // [UI] สีตัวอักษร
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15), // [UI] มุมโค้ง 15
                              ),
                              elevation: 2, // [UI] เงาปุ่ม
                            ),
                            child: _isGenerating
                                ? const SizedBox(
                                    height: 20, // [UI] ขนาดวงหมุนในปุ่ม
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.black87,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    "สร้างเมนูอาหาร",
                                    style: TextStyle(
                                      fontSize: 16, // [UI] ขนาดตัวอักษรปุ่ม
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 25), // [UI] ระยะก่อนหัวข้อ "เมนูแนะนำ"
                        const Text(
                          "เมนูแนะนำ",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18, // [UI] ขนาดหัวข้อ
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // 4. รายการเมนูที่ AI สร้าง
                if (_generatedRecipes.isEmpty && !_isGenerating) // ยังไม่มีเมนูและไม่ได้กำลังสร้าง -> ข้อความแนะนำ
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: Center(
                        child: Text(
                          "กดปุ่มเพื่อสร้างเมนูจากของในตู้เย็นเลย!",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ),

                SliverList( // รายการการ์ดเมนู
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final recipe = _generatedRecipes[index];
                    return _buildRecipeCard(recipe);
                  }, childCount: _generatedRecipes.length),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 30)), // [UI] ระยะว่างท้ายหน้า
              ],
            ),
    );
  }

  // ป้ายหัวข้อเล็กๆ แบบแคปซูล ให้ตรงกับดีไซน์ Figma (ใช้กับ "ประเภทอาหาร"/"เวลาในการทำ")
  Widget _buildSectionLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), // [UI] ระยะในป้าย
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D0), // [UI] สีครีม
        borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), // [UI] ขนาดตัวอักษรป้าย
      ),
    );
  }

  // Widget สำหรับปุ่ม Filter — ใช้สีชุดเดียวกันทั้งแถวประเภทอาหารและแถวเวลา ตรงตาม Figma
  Widget _buildFilterChip(
    String label,
    String selectedValue,
    Function(String) onSelected,
  ) {
    final isSelected = selectedValue == label; // ตัวเลือกนี้ถูกเลือกอยู่ไหม

    return Padding(
      padding: const EdgeInsets.only(right: 8.0), // [UI] ระยะขวาระหว่างชิป
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(color: Colors.black87)), // [UI] ตัวอักษรสีดำ
        selected: isSelected,
        selectedColor: const Color(0xFFFFF7D0), // [UI] เลือกอยู่ = พื้นครีม
        backgroundColor: Colors.white, // [UI] ไม่เลือก = พื้นขาว
        showCheckmark: false, // [UI] ไม่แสดงเครื่องหมายติ๊ก
        onSelected: (bool selected) => onSelected(label),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
          side: BorderSide(
            color: isSelected
                ? const Color(0xFFFFF7D0) // [UI] เลือกอยู่ = ขอบครีม, ไม่เลือก = ขอบฟ้า
                : const Color(0xff5189C9),
          ),
        ),
      ),
    );
  }

  // Widget การ์ดเมนูอาหาร — ตรงกับดีไซน์ Figma (avatar กลม + tag แบบขอบ)
  Widget _buildRecipeCard(Map<String, dynamic> recipe) {
    List<dynamic> tags = recipe['ingredients_used'] ?? []; // ชื่อวัตถุดิบหลักที่ใช้ (แสดงเป็นป้าย)

    return GestureDetector(
      onTap: () async { // กดการ์ด
        // ✅ กดเพื่อไปหน้า RecipeDetailScreen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecipeDetailScreen(
              recipe: recipe,
              inventory: _inventory,
              headerTitle: "เมนูแนะนำ",
              tab: AppTab.menu,
            ),
          ),
        );

        // ✅ ถ้ากดหักวัตถุดิบกลับมา ให้รีเฟรชหน้า AI ใหม่ (เพื่อดึงยอดคงเหลือใหม่)
        if (result == true) {
          _fetchInventory();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // [UI] ระยะรอบการ์ด
        padding: const EdgeInsets.all(14), // [UI] ระยะในการ์ด
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16), // [UI] มุมโค้ง 16
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4, // [UI] ความฟุ้งเงา
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44, // [UI] ขนาดวงกลมไอคอน
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE3F2FD), // ฟ้าอ่อน
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restaurant,
                color: Color(0xff5189C9),
                size: 22, // [UI] ไอคอนขนาด 22
              ),
            ),
            const SizedBox(width: 12), // [UI] ระยะไอคอนกับข้อความ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16, // [UI] ขนาดชื่อเมนู
                    ),
                    maxLines: 1, // [UI] บรรทัดเดียว
                    overflow: TextOverflow.ellipsis,
                  ),
                  // เมนูจากคลังสูตรกลาง (ไม่ได้เรียก AI)
                  if (recipe['from_library'] == true) ...[
                    const SizedBox(height: 4),
                    const Text(
                      "📖 จากคลังสูตร",
                      style: TextStyle(
                        fontSize: 12, // [UI] ขนาด 12
                        color: Color(0xff3F9142), // [UI] สีเขียว
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 14, // [UI] ไอคอนนาฬิกา ขนาด 14
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        recipe['time'] ?? '-',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey, // [UI] ขนาด 12 สีเทา
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tags วัตถุดิบ
                  Wrap(
                    spacing: 6, // [UI] ระยะห่างป้ายแนวนอน
                    runSpacing: 6, // [UI] ระยะห่างป้ายแนวตั้ง
                    children: tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, // [UI] ระยะในป้ายซ้ายขวา
                              vertical: 4, // [UI] ระยะในป้ายบนล่าง
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20), // [UI] ทรงแคปซูล
                              border: Border.all(
                                color: const Color(0xff5189C9), // [UI] ขอบฟ้า
                              ),
                            ),
                            child: Text(
                              tag.toString(),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 11, // [UI] ขนาดตัวอักษรป้าย
                              ),
                            ),
                          ),
                        )
                        .toList(),
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
