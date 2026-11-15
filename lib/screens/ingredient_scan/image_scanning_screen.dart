import 'dart:convert'; // jsonDecode

import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:image_picker/image_picker.dart'; // เปิดกล้อง/คลังรูป
import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารี Gemini
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล

import 'package:test_app/utils/category_icons.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/widgets/app_bottom_nav.dart';
import 'package:test_app/widgets/app_icons.dart';
import 'package:test_app/widgets/recipe_flow_widgets.dart';
import 'package:test_app/screens/ingredient_scan/result_screen.dart'; // หน้าผลสแกน (ไปต่อหลังวิเคราะห์)
import 'package:test_app/config/api_keys.dart';
import 'package:test_app/services/ai_request_log.dart';
import 'package:test_app/services/gemini_retry.dart';

/// หน้าถ่ายภาพวัตถุดิบเพื่อสแกนเข้าตู้เย็น (ตามดีไซน์ใน Figma: "SCAN")
/// รายการ "วัตถุดิบที่เพิ่มล่าสุด" ดึงจาก Supabase จริงเสมอ (ไม่ใช้ตัวเลข mock ของ Figma)
class ImageScanning extends StatefulWidget {
  const ImageScanning({super.key});

  @override
  State<ImageScanning> createState() => _ImageScanningState();
}

class _ImageScanningState extends State<ImageScanning> {
  // แบบฟอร์มคำตอบของ Gemini (structured output) — ใช้ enum บังคับค่าให้อยู่ใน
  // ชุดที่แอปรู้จักเสมอ
  static final Schema _scanSchema = Schema.array( // รูปแบบคำตอบที่บังคับให้ AI ตอบ (ลิสต์ของวัตถุดิบ)
    items: Schema.object(
      properties: {
        'name': Schema.string(description: 'ชื่อวัตถุดิบภาษาไทย'),
        'category': Schema.enumString(enumValues: fixedCategories), // หมวดหมู่ต้องเป็นหนึ่งในชุดที่กำหนด
        'quantity': Schema.number(), // ปริมาณที่เห็น
        'unit': Schema.string(), // หน่วย
        'count_mode': Schema.enumString(enumValues: ['piece', 'portion']), // นับเป็นชิ้น หรือแบ่งเป็นส่วน
        'count': Schema.integer(), // จำนวนสำหรับหักใช้
        'count_unit': Schema.string(), // หน่วยของจำนวนนั้น
        'shelf_type': Schema.enumString( // ประเภทอายุการเก็บ (ต้องอยู่ในตาราง หรือ other)
          enumValues: [...shelfTypes.map((t) => t.key), 'other'],
        ),
        'fridge_days': Schema.integer(), // ช่องปกติเก็บได้กี่วัน
        // ตอบจำนวนวันช่องแช่แข็งเสมอ (เป็นหน้าที่ของ AI เมื่อไม่มีข้อมูลในระบบ)
        'freezer_days': Schema.integer(),
      },
      requiredProperties: [ // ช่องที่ต้องตอบทุกครั้ง
        'name',
        'category',
        'quantity',
        'unit',
        'count_mode',
        'count',
        'count_unit',
        'shelf_type',
        'fridge_days',
        'freezer_days',
      ],
    ),
  );

  final ImagePicker _picker = ImagePicker(); // ตัวเปิดกล้อง/คลังรูป
  final String _apiKey = ApiKeys.imageScanning; // คีย์ AI ของหน้านี้

  List<Map<String, dynamic>> _recentItems = []; // วัตถุดิบที่เพิ่มล่าสุด
  bool _isLoadingRecent = true; // กำลังโหลดรายการล่าสุดไหม

  @override
  void initState() {
    super.initState();
    _fetchRecentItems(); // เปิดหน้ามาโหลดรายการล่าสุด
  }

  // ดึงวัตถุดิบที่เพิ่มล่าสุด 3 รายการจาก Supabase (ของจริง ไม่ใช่ mock)
  Future<void> _fetchRecentItems() async {
    try {
      final response = await Supabase.instance.client
          .from('fridge_items')
          .select()
          .order('created_at', ascending: false) // ใหม่สุดก่อน
          .limit(3); // เอาแค่ 3 รายการ (แก้เลขเพื่อแสดงมาก/น้อยลง)

      if (mounted) {
        setState(() {
          _recentItems = List<Map<String, dynamic>>.from(response);
          _isLoadingRecent = false;
        });
      }
    } catch (e) {
      debugPrint('โหลดวัตถุดิบล่าสุดไม่สำเร็จ: $e');
      if (mounted) {
        setState(() => _isLoadingRecent = false);
      }
    }
  }

  // เปิดหน้ากรอกวัตถุดิบเอง (ไม่ใช้ AI)
  void _openManualEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultScreen(foundItems: [], manual: true), // ส่งลิสต์ว่าง + โหมดกรอกเอง
      ),
    ).then((_) {
      _fetchRecentItems(); // กลับมาแล้วโหลดรายการล่าสุดใหม่
    });
  }

  // ถ่ายรูป/เลือกรูป แล้วส่งให้ AI วิเคราะห์
  Future<void> _pickAndAnalyzeImage(ImageSource source) async {
    if (!mounted) return;
    // กล้องเปิดไม่ได้จะ error ก่อนแสดงไดอะล็อก ต้องไม่ pop หน้านี้ออกไปแทน
    bool dialogOpen = false; // ป๊อปอัปกำลังโหลดเปิดอยู่ไหม
    try {
      // จำกัดขนาดรูปก่อนส่งเข้า Gemini — กล้องมือถือสมัยนี้ถ่ายได้ไฟล์ใหญ่มาก
      // (10+ MB) ถ้าส่งเต็มขนาดจริงจะอัพโหลดช้าและโมเดลประมวลผลช้าตามไปด้วย
      // โดยไม่ได้ช่วยให้แม่นยำขึ้นเลย (โมเดล vision ย่อภาพลงประมวลผลอยู่แล้ว)
      // ย่อเหลือด้านยาวสุดไม่เกิน 768px คุณภาพ 70% (ไฟล์เล็กลงราวครึ่งจาก
      // 1024px/80%) อัปโหลดและประมวลผลเร็วขึ้น ยังเห็นวัตถุดิบชัดพอจำแนกได้
      final XFile? image = await _picker.pickImage( // เปิดกล้องหรือคลังรูป
        source: source,
        maxWidth: 768, // ย่อรูปให้กว้างไม่เกิน 768px
        maxHeight: 768,
        imageQuality: 70, // คุณภาพรูป 70% (ไฟล์เล็กลง ส่งเร็วขึ้น)
      );
      if (image == null) return; // ผู้ใช้กดยกเลิก ไม่ได้เลือกรูป

      if (!mounted) return;
      dialogOpen = true;
      showDialog( // แสดงป๊อปอัป "กำลังวิเคราะห์"
        context: context,
        barrierDismissible: false, // [UI] แตะข้างนอกแล้วไม่ปิด
        // จำกัดสเกลข้อความไว้ไม่ให้เกิน 1.3 เท่า เพราะถ้าเครื่องตั้งค่า
        // ขนาดตัวอักษรใหญ่พิเศษ (Accessibility > Larger Text) ไว้สูงมาก
        // ป้ายข้อความเล็กๆ ในไดอะล็อกนี้จะขยายจนล้นทับเนื้อหาข้างหลังได้
        // (การ์ดสีขาวช่วยให้ดูเป็นกล่องไดอะล็อกจริงๆ ไม่ใช่ตัวหนังสือลอย
        // ทับพื้นหลังตรงๆ ด้วย)
        builder: (ctx) => PopScope(
          canPop: false, // ห้ามกดย้อนกลับปิดป๊อปอัป
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3, // [UI] ตัวอักษรขยายได้สูงสุด 1.3 เท่า
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28, // [UI] ระยะในกล่องซ้ายขวา
                  vertical: 24, // [UI] ระยะในกล่องบนล่าง
                ),
                decoration: BoxDecoration(
                  color: Colors.white, // [UI] กล่องสีขาว
                  borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26, // [UI] สีเงา
                      blurRadius: 10, // [UI] ความฟุ้งเงา
                      offset: Offset(0, 4), // [UI] เงาเลื่อนลง 4
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blue), // [UI] วงหมุนสีฟ้า
                    SizedBox(height: 16),
                    Text(
                      "กำลังวิเคราะห์วัตถุดิบ...",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14, // [UI] ขนาดข้อความ
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none, // ไม่มีเส้นใต้ (ป๊อปอัปไม่มีธีมข้อความ)
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // ให้ Gemini ตอบตามแบบฟอร์ม (structured output) แทนการอธิบายรูปแบบ JSON
      // ยาวๆ ใน prompt: prompt สั้นลง ตอบเร็วขึ้น และค่าที่ได้อยู่ในชุดที่กำหนด
      // เสมอ (หมวดหมู่ / ประเภทอายุการเก็บรักษา / วิธีนับ) ไม่ต้องกลัว JSON เพี้ยน
      // — Gemini ยังดูรูปแล้วเลือกประเภทเอง ความแม่นเท่าเดิม
      final imageBytes = await image.readAsBytes(); // อ่านไฟล์รูปเป็นไบต์

      final prompt = TextPart("""
วิเคราะห์อาหารและวัตถุดิบสำหรับประกอบอาหารทุกชิ้นในรูป
- ตอบเฉพาะสิ่งที่คนรับประทานได้ตามปกติในประเทศไทย ปลอดภัยต่อการบริโภค และไม่ใช่สิ่งที่ผิดกฎหมาย
  รวมถึงอาหารพื้นบ้านไทย (เช่น แมลงที่กินได้ ไข่มดแดง ปลาร้า เลือดหมู) ให้นับเป็นวัตถุดิบตามปกติ
  ข้ามสิ่งที่ไม่ใช่อาหาร เช่น ยา อาหารเสริมชนิดเม็ด สารเคมี น้ำยาทำความสะอาด เครื่องสำอาง ของใช้ ภาชนะเปล่า
  อาหารสัตว์ (อาหารสุนัข อาหารแมว ฯลฯ) บุหรี่ ยาสูบ บุหรี่ไฟฟ้า สุราสำหรับดื่ม (เบียร์ เหล้า ไวน์ ฯลฯ)
  และสิ่งที่ผิดกฎหมาย
  ยกเว้นสุราสำหรับปรุงอาหาร (เช่น เหล้าจีน ไวน์ปรุงอาหาร มิริน) ให้นับเป็นเครื่องปรุง
  ถ้าในรูปไม่มีอาหารเลย ให้ตอบเป็น array ว่าง []
- quantity/unit: ปริมาณที่เห็นจริง เช่น 1 แพ็ค, 6 ฟอง, 500 กรัม
- count_mode: piece ถ้าเห็นเป็นลูก/ชิ้นแยกกันนับได้ชัดเจน (ไข่ มะเขือเทศ หัวหอม ผลไม้ ผักหัว ขวด กล่อง ขนมปังแผ่น ชีสแผ่น) ไม่งั้น portion (เนื้อสัตว์ ผักใบ ของลูกเล็กจำนวนมาก เช่น มะเขือเทศราชินีทั้งแพ็ค พริก อาหารเหลือ)
- count/count_unit: จำนวนสำหรับหักใช้ ห้ามเป็นกรัม/มล. (portion ใช้ count_unit "ส่วน", 1 ส่วน = ทำอาหาร 1 ครั้ง)
- shelf_type: ${shelfTypePromptList().replaceAll('\n', ', ')}, other = ไม่ตรงประเภทไหน
- fridge_days/freezer_days: จำนวนวันที่เก็บได้อย่างปลอดภัยในสภาพที่เห็น ในช่องปกติ/ช่องแช่แข็ง (ตอบ freezer_days เสมอ)
""");

      // Gemini ตอบ 503 "high demand" ได้เป็นพักๆ ลองใหม่อัตโนมัติก่อนแจ้ง error
      // และรอได้ถึง 60 วินาที (รูปที่มีหลายชิ้นอาจใช้เวลาเกิน 30 วินาที)
      final response = await generateGemini( // ส่งข้อความ + รูปให้ Gemini
        apiKey: _apiKey,
        logEvent: AiEvent.scanIngredient, // บันทึกประวัติการใช้ AI
        content: [
          Content.multi([prompt, DataPart('image/jpeg', imageBytes)]),
        ],
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json', // ตอบเป็น JSON
          responseSchema: _scanSchema, // ต้องตอบตามรูปแบบ _scanSchema
        ),
        timeout: const Duration(seconds: 60), // รอนานสุด 60 วินาที
      );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // ปิดป๊อปอัปกำลังโหลด
      }
      dialogOpen = false;

      if (response.text != null) {
        String cleanJson = response.text! // ล้างเครื่องหมาย ``` ออก
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        dynamic decoded = jsonDecode(cleanJson); // แปลงข้อความเป็นข้อมูล
        List<dynamic> itemsList = [];

        if (decoded is List) { // ได้เป็นลิสต์ -> ใช้ได้เลย
          itemsList = decoded;
        } else if (decoded is Map) { // ได้เป็นชิ้นเดียว -> ห่อเป็นลิสต์
          itemsList = [decoded];
        }

        // กันเหนียว: ถ้า AI ตอบหมวดหมู่ไม่ตรงเป๊ะกับที่กำหนดไว้ (fixedCategories)
        // ให้ map เข้าเซ็ตที่กำหนดไว้เสมอ ไม่ปล่อยให้หมวดหมู่แปลกๆ หลุดเข้าคลัง
        for (var item in itemsList) {
          if (item is Map) {
            item['category'] = normalizeCategory(
              (item['category'] ?? '').toString(),
            );
          }
        }

        // ไม่พบอาหาร/วัตถุดิบในรูป (AI ข้ามของที่ไม่ใช่อาหาร) -> แจ้งผู้ใช้
        // ไม่พาไปหน้าผลสแกนที่ว่างเปล่า
        if (itemsList.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text( // [UI] ข้อความแจ้งว่าไม่เจออาหาร
                  'ไม่พบอาหารหรือวัตถุดิบในรูป ลองถ่ายใหม่ให้เห็นวัตถุดิบชัดขึ้น',
                ),
                action: SnackBarAction( // ปุ่มทางลัดบนแถบข้อความ
                  label: 'นำเข้าเอง',
                  onPressed: _openManualEntry,
                ),
              ),
            );
          }
          return;
        }

        if (mounted) {
          Navigator.push( // เจอวัตถุดิบ -> ไปหน้าผลสแกน
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ResultScreen(foundItems: itemsList, imageBytes: imageBytes),
            ),
          ).then((_) {
            _fetchRecentItems(); // กลับมาแล้วโหลดรายการล่าสุดใหม่
          });
        }
      }
    } catch (e) {
      if (dialogOpen && mounted && Navigator.canPop(context)) { // เกิด error ขณะเปิดป๊อปอัปอยู่ -> ปิดก่อน
        Navigator.pop(context);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            geminiErrorMessage(e, fallback: 'วิเคราะห์วัตถุดิบไม่สำเร็จ'),
          ),
          backgroundColor: Colors.red, // [UI] แถบข้อความสีแดง
          action: SnackBarAction(
            label: 'นำเข้าเอง',
            textColor: Colors.white,
            onPressed: _openManualEntry,
          ),
        ),
      );
    }
  }

  // ใช้ mapping กลางเดียวกับหน้าคลัง (Inventory) เพื่อให้อิโมจิหมวดหมู่ตรงกันทุกหน้า
  String _getCategoryEmoji(String category) => categoryEmoji(category);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลัง
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan), // แถบเมนูล่าง ไฮไลต์ "สแกน"
      body: SafeArea(
        child: Column(
          children: [
            const IngredientFlowHeader(title: "ถ่ายภาพวัตถุดิบ"), // หัวหน้า
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้ายขวา
                child: Column(
                  children: [
                    const SizedBox(height: 15), // [UI] ระยะใต้หัว
                    _IngredientOptionCard( // การ์ด: ถ่ายรูปด้วยกล้อง
                      icon: Icons.camera_alt_outlined,
                      title: "ถ่ายภาพวัตถุดิบ",
                      subtitle: "เปิดกล้องเพื่อสแกน",
                      onTap: () => _pickAndAnalyzeImage(ImageSource.camera),
                    ),
                    const SizedBox(height: 15), // [UI] ระยะห่างระหว่างการ์ด
                    _IngredientOptionCard( // การ์ด: เลือกรูปจากคลัง
                      icon: Icons.image_outlined,
                      title: "เลือกจากคลังรูปภาพ",
                      subtitle: "อัพโหลดรูปภาพที่มีอยู่",
                      onTap: () => _pickAndAnalyzeImage(ImageSource.gallery),
                    ),
                    const SizedBox(height: 15),
                    _IngredientOptionCard( // การ์ด: กรอกเอง
                      icon: Icons.edit_note,
                      title: "นำเข้าวัตถุดิบด้วยตัวเอง",
                      subtitle: "กรอกชื่อและจำนวนวัตถุดิบ",
                      onTap: _openManualEntry,
                    ),
                    const SizedBox(height: 20),

                    // เคล็ดลับการสแกน
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16), // [UI] ระยะในกล่อง
                      decoration: BoxDecoration(
                        color: Colors.white, // [UI] พื้นขาว
                        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5, // [UI] ความฟุ้งเงา
                            offset: Offset(0, 2), // [UI] เงาเลื่อนลง 2
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "เคล็ดลับการสแกน",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16, // [UI] ขนาดหัวข้อกล่อง
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildTipItem("ถ่ายภาพในที่ที่มีแสงสว่างเพียงพอ"),
                          _buildTipItem("จัดวัตถุดิบให้อยู่ตรงกลางเฟรม"),
                          _buildTipItem("หลีกเลี่ยงเงาหรือแสงสะท้อนบนวัตถุ"),
                          _buildTipItem("ถ่ายทีละชิ้นเพื่อความแม่นยำสูงสุด"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // วัตถุดิบที่เพิ่มล่าสุด (ดึงจาก Supabase จริง)
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
                          const Text(
                            "วัตถุดิบที่เพิ่มล่าสุด",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _isLoadingRecent // กำลังโหลด / ไม่มีข้อมูล / มีรายการ
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, // [UI] ความหนาวงหมุน
                                  ),
                                )
                              : _recentItems.isEmpty
                              ? const Text(
                                  "ยังไม่มีประวัติการเพิ่มวัตถุดิบ",
                                  style: TextStyle(color: Colors.grey),
                                )
                              : Column(
                                  children: _recentItems.map((item) {
                                    final emoji = _getCategoryEmoji( // อิโมจิตามหมวดหมู่
                                      item['category'] ?? '',
                                    );
                                    final name = item['name'] ?? 'ไม่ระบุ';
                                    final time = relativeTimeThai( // ข้อความเวลาแบบ "5 นาทีที่แล้ว"
                                      item['created_at']?.toString(),
                                    );
                                    return _buildRecentItem(emoji, name, time);
                                  }).toList(),
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แถบหัวเรื่อง: ปุ่มย้อนกลับ + แคปซูลไอคอนสแกน/ชื่อหน้า + ปุ่มตัวกรองวงกลม
  // (สีครีมเหลืองอ่อนทั้งแถบ ตามดีไซน์ Figma "SCAN")
  // แถวเคล็ดลับ 1 ข้อ (ไอคอนติ๊ก + ข้อความ)
  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0), // [UI] ระยะใต้แต่ละแถว
      child: Row(
        children: [
          const CheckIcon(size: 18), // [UI] ไอคอนติ๊กถูก ขนาด 18
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.black87, fontSize: 13), // [UI] ขนาดข้อความ 13
            ),
          ),
        ],
      ),
    );
  }

  // แถววัตถุดิบล่าสุด 1 แถว (อิโมจิ + ชื่อ + เวลา)
  Widget _buildRecentItem(String iconEmoji, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0), // [UI] ระยะบนล่างของแถว
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10), // [UI] ระยะรอบอิโมจิ
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9), // [UI] สีกล่องรองอิโมจิ (เทา)
              borderRadius: BorderRadius.circular(12), // [UI] มุมโค้ง
            ),
            child: Text(iconEmoji, style: const TextStyle(fontSize: 24)), // [UI] ขนาดอิโมจิ
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 15, // [UI] ขนาดชื่อ
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 12), // [UI] ขนาดเวลา
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// การ์ดตัวเลือกสแกน (วงกลมไอคอนฟ้าอ่อน + ชื่อ + คำอธิบาย) ทรงเดียวกับ
/// _ScanOptionCard ในหน้าสแกนสูตรอาหาร เพื่อให้ดีไซน์ตรงกันทั้งแอป
class _IngredientOptionCard extends StatelessWidget {
  final IconData icon; // ไอคอน
  final String title; // หัวข้อ
  final String subtitle; // คำอธิบาย
  final VoidCallback onTap; // ทำอะไรเมื่อกด

  const _IngredientOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white, // [UI] พื้นการ์ด
      borderRadius: BorderRadius.circular(24), // [UI] มุมโค้ง 24
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.blue.withValues(alpha: 0.15), // [UI] สีคลื่นตอนกด
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20), // [UI] ระยะในการ์ด บนล่าง 28 ซ้ายขวา 20
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 5, // [UI] ความฟุ้งเงา
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: 70, // [UI] ขนาดวงกลมไอคอน
                width: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), // [UI] สีวงกลม (ฟ้าอ่อน)
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: const Color(0xff5189C9)), // [UI] ไอคอนขนาด 32 สีฟ้า
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17, // [UI] ขนาดหัวข้อ
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13), // [UI] ขนาดคำอธิบาย
              ),
            ],
          ),
        ),
      ),
    );
  }
}
