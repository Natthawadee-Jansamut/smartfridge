import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'recipe_detail_screen.dart'; // ✅ นำเข้าหน้าใหม่
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';
import '../config/api_keys.dart';
import '../services/fridge_stock.dart';
import '../services/gemini_retry.dart';
import '../utils/fridge_age.dart';

class AiRecipeScreen extends StatefulWidget {
  const AiRecipeScreen({super.key});

  @override
  State<AiRecipeScreen> createState() => _AiRecipeScreenState();
}

class _AiRecipeScreenState extends State<AiRecipeScreen> {
  bool _isLoadingData = true;
  bool _isGenerating = false;

  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _oldItems = [];

  // วัตถุดิบทุกชิ้นที่ยังเหลืออยู่ เรียงจากอยู่ในตู้เย็นนานที่สุด ใช้แสดงในการ์ด
  // "วัตถุดิบในตู้เย็น" (แสดงเสมอ ไม่ใช่เฉพาะของที่อยู่นานเกินกำหนด)
  List<Map<String, dynamic>> _fridgeByAge = [];
  int _aheadDays = defaultOldItemDays;
  List<dynamic> _generatedRecipes = []; // เก็บเมนูที่ AI สร้างให้

  // ตัวแปรสำหรับ Filter
  String _selectedCategory = 'ทั้งหมด';
  final List<String> _categories = ['ทั้งหมด', 'อาหารไทย', 'คลีน', 'คีโต'];

  String _selectedTime = 'ไม่จำกัด';
  final List<String> _times = [
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
    _fetchInventory();
  }

  // 1. ดึงข้อมูลวัตถุดิบจาก Supabase
  Future<void> _fetchInventory() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('fridge_items').select();
      final data = List<Map<String, dynamic>>.from(response);

      List<Map<String, dynamic>> oldItems = [];
      List<Map<String, dynamic>> byAge = [];
      final aheadDays = readOldItemDays(supabase.auth.currentUser);

      for (var item in data) {
        // ถ้าใช้วัตถุดิบชิ้นนี้หมดแล้ว (เช่น กดทำอาหารจนหักจำนวนเหลือ 0) ก็ไม่
        // ควรโผล่ในลิสต์ "อยู่ในตู้เย็นนาน" อีกต่อไป เพราะไม่มีของเหลือให้ต้องรีบ
        // ใช้แล้ว (ของที่ไม่มีระบุจำนวนไว้ ให้ถือว่ายังมีของอยู่ตามเดิม)
        if (isUsedUp(item)) continue;

        final days = daysInFridge(item['created_at']);
        item['days_in_fridge'] = days; // เก็บค่าไว้ใช้แสดงผล
        byAge.add(item);
        // ควรเอาไปทำอาหารก่อน: เก็บได้อีกไม่เกินจำนวนวันที่ตั้งไว้ในหน้าตั้งค่า
        // แจ้งเตือน (นับเป็นวัน ไม่ใช้เปอร์เซ็นต์) และยังไม่เกินกำหนด
        if (shouldUseFirst(item, aheadDays)) {
          oldItems.add(item);
        }
      }

      // เหลือวันน้อยที่สุดขึ้นก่อน ตรงกับ "เก็บได้อีก X วัน" ที่แสดงบนการ์ด
      // (เหมือนหน้าแจ้งเตือน) — ลำดับนี้ส่งให้ AI ใช้ของก่อนด้วย
      oldItems.sort(compareDaysLeft);
      byAge.sort(compareDaysLeft);

      setState(() {
        _inventory = data;
        _oldItems = oldItems;
        _fridgeByAge = byAge;
        _aheadDays = aheadDays;
        _isLoadingData = false;
      });
    } catch (e) {
      print("Error fetching inventory: $e");
      setState(() => _isLoadingData = false);
    }
  }

  // สีของ "เก็บได้อีก X วัน": ครบกำหนด/เกินแล้ว = แดง, เหลือไม่เกินจำนวนวันที่
  // ตั้งแจ้งเตือนไว้ = ส้ม, นอกนั้น = เขียว
  Color _daysLeftColor(int? left) {
    if (left == null) return Colors.black45;
    if (left <= 0) return Colors.red;
    if (left <= _aheadDays) return Colors.orange.shade800;
    return const Color(0xff3F9142);
  }

  // 2. ส่งข้อมูลให้ Gemini คิดเมนู
  Future<void> _generateRecipes() async {
    if (_inventory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีวัตถุดิบในตู้เย็น กรุณาเพิ่มวัตถุดิบก่อน'),
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedRecipes = []; // เคลียร์ของเก่า
    });

    try {
      // ⚠️ ใส่ API Key ของคุณที่นี่
      final String apiKey = ApiKeys.aiRecipeScreen;

      // เตรียมรายชื่อวัตถุดิบเป็น Text (ไม่เอาของที่หมดแล้ว/เหลือ 0 ชิ้น มา
      // เสนอให้ AI ใช้ เพราะจริงๆ ไม่มีของเหลือให้ทำอาหารแล้ว)
      // (ลอตที่ชื่อ/หน่วยเดียวกันจะถูกรวมเป็นรายการเดียว)
      // ของที่เกินระยะที่เก็บได้แล้วไม่ส่งให้ AI เอาไปทำเมนู (อาจไม่ปลอดภัย
      // ให้ผู้ใช้ตรวจเองก่อน)
      String allItems = inventoryPromptList(
        _inventory.where((e) => !isOverdue(e)).toList(),
      );
      final useFirst = _oldItems
          .map((e) => "${e['name']} (${daysLeftText(daysLeft(e)!)})")
          .join(", ");

      final prompt = TextPart("""
        คุณคือเชฟอัจฉริยะ ช่วยคิดเมนูอาหาร 3 เมนู ที่สามารถทำได้จากวัตถุดิบเหล่านี้เป็นหลัก
        วัตถุดิบที่มี: $allItems
        วัตถุดิบที่ควรใช้ก่อน เรียงจากเก็บได้อีกน้อยวันที่สุด: ${useFirst.isEmpty ? 'ไม่มี' : useFirst}
        ถ้ามีวัตถุดิบที่ควรใช้ก่อน ทุกเมนูต้องใช้วัตถุดิบกลุ่มนี้อย่างน้อย 1 อย่าง (ตัวแรกๆ ก่อน)

        เงื่อนไขเพิ่มเติม:
        - ประเภทอาหาร: ${_selectedCategory == 'ทั้งหมด' ? 'อะไรก็ได้' : _selectedCategory}
        - เวลาทำ: ${_timeConstraintForPrompt()}

        สำคัญเรื่องปริมาณใน detailed_ingredients: ผู้ใช้ไม่ได้ชั่งตวง ให้ใช้หน่วยเดียวกับ
        วัตถุดิบที่มีในวงเล็บเท่านั้น (เช่น ส่วน, ฟอง, ผล, หัว) ห้ามใช้กรัม/กก./มล./ช้อน
        และ use_quantity ห้ามเกินจำนวนที่มี (1 ส่วน ≈ ใช้ทำอาหาร 1 ครั้ง ใช้ 0.5 ได้)

        ตอบกลับมาเป็น JSON Array เท่านั้น ตามรูปแบบนี้เป๊ะๆ:
        [
          {
            "recipe_name": "ชื่อเมนู",
            "time": "เวลาทำ (เช่น 15 นาที)",
            "servings": "จำนวนที่ได้ (เช่น 2 ที่)",
            "ingredients_used": ["วัตถุดิบหลัก1", "วัตถุดิบหลัก2"],
            "detailed_ingredients": [
              {"name": "ชื่อวัตถุดิบให้ตรงกับที่มีเป๊ะๆ", "use_quantity": จำนวนเลข(ใส่แค่เลข), "unit": "หน่วยเดียวกับวัตถุดิบที่มี"}
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
      final response = await generateGemini(
        apiKey: apiKey,
        content: [
          Content.multi([prompt]),
        ],
        timeout: const Duration(seconds: 60),
      );

      if (response.text != null) {
        String cleanJson = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        dynamic decoded = jsonDecode(cleanJson);

        setState(() {
          if (decoded is List) {
            _generatedRecipes = decoded;
          } else if (decoded is Map) {
            _generatedRecipes = [decoded];
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(geminiErrorMessage(e, fallback: 'สร้างเมนูไม่สำเร็จ')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // ฟ้าอ่อนให้ตรงกับดีไซน์ใหม่ทั้งแอป
      bottomNavigationBar: const AppBottomNav(current: AppTab.menu),
      body: _isLoadingData
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xff5189C9)),
            )
          : CustomScrollView(
              slivers: [
                // 1. Header (ตรงกับหน้าอื่นๆ ที่เป็น root ของ bottom-nav — ไม่มีปุ่มย้อนกลับ)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 15,
                      left: 20,
                      right: 20,
                      bottom: 15,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7D0),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: const Row(
                              children: [
                                ChefIcon(size: 22),
                                SizedBox(width: 10),
                                Text(
                                  "สร้างเมนูอาหาร",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 5,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const InkWell(
                            customBorder: CircleBorder(),
                            child: Center(child: FilterIcon(size: 20)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      "สร้างเมนูจากวัตถุดิบที่มี โดยใช้ของที่เก็บได้อีกน้อยวันก่อน",
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),

                // 2. กล่องแจ้งเตือนของที่อยู่ในตู้เย็นนาน
                if (_fridgeByAge.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
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
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  "วัตถุดิบในตู้เย็น",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._fridgeByAge.map((item) {
                              final left = daysLeft(item);
                              final leftColor = _daysLeftColor(left);
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 6.0,
                                  left: 34,
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
                                            color: Color(0xff5189C9),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        // นับเป็นวัน: เก็บได้อีก X วัน → ครบ
                                        // กำหนดวันนี้ → เกินมาแล้ว X วัน
                                        if (left != null)
                                          Text(
                                            daysLeftText(left),
                                            style: TextStyle(
                                              color: leftColor,
                                              fontSize: 12,
                                              fontWeight: left <= _aheadDays
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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
                  const SliverToBoxAdapter(child: SizedBox(height: 15)),

                // 3. ตัวกรอง (Filter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // การ์ดหุ้ม "ประเภทอาหาร" ทั้งชุด (ป้ายหัวข้อ + แถวปุ่มเลือก)
                        // ตามดีไซน์ Figma แทนที่จะปล่อยลอยอยู่บนพื้นหลังตรงๆ
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
                              _buildSectionLabel("ประเภทอาหาร"),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _categories
                                      .map(
                                        (e) => _buildFilterChip(
                                          e,
                                          _selectedCategory,
                                          (v) => setState(
                                              () => _selectedCategory = v),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
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
                                          (v) => setState(
                                              () => _selectedTime = v),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ปุ่มสร้างเมนู
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isGenerating ? null : _generateRecipes,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFF7D0),
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 2,
                            ),
                            child: _isGenerating
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.black87,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    "สร้างเมนูอาหาร",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        const Text(
                          "เมนูแนะนำ",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // 4. รายการเมนูที่ AI สร้าง
                if (_generatedRecipes.isEmpty && !_isGenerating)
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

                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final recipe = _generatedRecipes[index];
                    return _buildRecipeCard(recipe);
                  }, childCount: _generatedRecipes.length),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
    );
  }

  // ป้ายหัวข้อเล็กๆ แบบแคปซูล ให้ตรงกับดีไซน์ Figma (ใช้กับ "ประเภทอาหาร"/"เวลาในการทำ")
  Widget _buildSectionLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  // Widget สำหรับปุ่ม Filter — ใช้สีชุดเดียวกันทั้งแถวประเภทอาหารและแถวเวลา ตรงตาม Figma
  Widget _buildFilterChip(
    String label,
    String selectedValue,
    Function(String) onSelected,
  ) {
    final isSelected = selectedValue == label;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(color: Colors.black87)),
        selected: isSelected,
        selectedColor: const Color(0xFFFFF7D0),
        backgroundColor: Colors.white,
        showCheckmark: false,
        onSelected: (bool selected) => onSelected(label),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected
                ? const Color(0xFFFFF7D0)
                : const Color(0xff5189C9),
          ),
        ),
      ),
    );
  }

  // Widget การ์ดเมนูอาหาร — ตรงกับดีไซน์ Figma (avatar กลม + tag แบบขอบ)
  Widget _buildRecipeCard(Map<String, dynamic> recipe) {
    List<dynamic> tags = recipe['ingredients_used'] ?? [];

    return GestureDetector(
      onTap: () async {
        // ✅ กดเพื่อไปหน้า RecipeDetailScreen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecipeDetailScreen(
              recipe: recipe,
              inventory: _inventory,
              headerTitle: "เมนูแนะนำ",
            ),
          ),
        );

        // ✅ ถ้ากดหักวัตถุดิบกลับมา ให้รีเฟรชหน้า AI ใหม่ (เพื่อดึงยอดคงเหลือใหม่)
        if (result == true) {
          _fetchInventory();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE3F2FD), // ฟ้าอ่อน
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restaurant,
                color: Color(0xff5189C9),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe['recipe_name'] ?? 'ไม่มีชื่อเมนู',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        recipe['time'] ?? '-',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Tags วัตถุดิบ
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xff5189C9),
                              ),
                            ),
                            child: Text(
                              tag.toString(),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 11,
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
