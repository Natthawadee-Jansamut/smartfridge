import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ฐานข้อมูล/ผู้ใช้
// หน้าที่ไปต่อได้จากหน้าหลัก
import 'package:test_app/screens/profile/profile_screen.dart';
import 'package:test_app/screens/ingredient_scan/image_scanning_screen.dart';
import 'package:test_app/screens/fridge/inventory_screen.dart';
import 'package:test_app/screens/menu_generator/ai_recipe_screen.dart';
import 'package:test_app/screens/meal_plan/plan_menu_screen.dart';
import 'package:test_app/screens/notification/expiration_alert_screen.dart';
import 'package:test_app/screens/recipe_scan/scan_recipe_screen.dart';
import 'package:test_app/services/notification_service.dart'; // เช็คว่าแอปเปิดจากการกดแจ้งเตือนไหม
import 'package:test_app/utils/fridge_age.dart'; // นับวันที่เหลือ

// หน้าหลักของแอป: หัว (ชื่อผู้ใช้) + กล่องสรุปจำนวนของ + ตะแกรงเมนู 6 ปุ่ม
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // ดึงชื่อ User จาก Supabase
  final supabase = Supabase.instance.client;

  String userName = "User"; // ชื่อที่แสดงบนหัว
  int totalItems = 0; // จำนวนของทั้งหมดในตู้

  int nearExpiryItems = 0; // จำนวนของใกล้ครบกำหนด

  int expiredItems = 0; // จำนวนของเกินกำหนด

  @override
  void initState() {
    super.initState();

    loadUser(); // โหลดชื่อ
    loadExpiryStatus(); // โหลดตัวเลขสรุป

    // แอปถูกเปิดจากการกดแจ้งเตือน (ตอนแอปปิดอยู่) -> พาไปหน้าแจ้งเตือนเลย
    if (NotificationService.takeOpenAlertsOnLaunch()) {
      WidgetsBinding.instance.addPostFrameCallback((_) { // รอหน้าจอวาดเสร็จก่อน
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExpirationAlertScreen()),
        );
      });
    }
  }

  @override
  void didChangeDependencies() { // ทำงานเมื่อข้อมูลที่หน้านี้พึ่งพาเปลี่ยน
    super.didChangeDependencies();

    loadUser();
  }

  // โหลดชื่อ-นามสกุลของผู้ใช้
  Future<void> loadUser() async {
    final session = supabase.auth.currentSession;

    // ถ้า logout แล้ว ไม่มี session ให้หยุดเลย
    if (session == null) {
      return;
    }

    User? fetched; // ข้อมูลผู้ใช้ที่ได้มา
    try {
      final response = await supabase.auth.getUser(); // ขอข้อมูลผู้ใช้ล่าสุด
      fetched = response.user; // หยิบค่า response.user มาเก็บไว้
    } catch (e) {
      // token หมดอายุ / เน็ตหลุด -> ไม่ให้แอปขึ้น error ใช้ข้อมูลที่จำไว้ในเครื่องแทน
      debugPrint('loadUser: $e');
      fetched = supabase.auth.currentUser;
    }
    final user = fetched; // ใช้ตัวนี้แสดงชื่อ

    if (user != null) {
      final firstName = user.userMetadata?['first_name'] ?? "";

      final lastName = user.userMetadata?['last_name'] ?? "";

      if (mounted) {
        setState(() {
          userName = "$firstName $lastName";
        });
      }
    }
  }

  // ตัวเลขสรุปต้องนับแบบเดียวกับหน้าคลังเสมอ: วันหมดอายุนับตามวันในปฏิทิน
  // (daysLeft) และไม่นับของที่ใช้หมดแล้ว (เหลือ 0)
  Future<void> loadExpiryStatus() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return;
    }

    final response = await supabase
        .from('fridge_items') // ดึงของในตู้ทั้งหมด
        .select()
        .eq('user_id', user.id);

    int total = response.length; // นับทั้งหมด

    int near = 0;

    int expired = 0;

    for (var item in response) { // ไล่นับทีละชิ้น
      if (isUsedUp(item)) continue; // หมดแล้ว ไม่นับ

      final diff = daysLeft(item); // เหลืออีกกี่วัน
      if (diff == null) continue;

      if (diff < 0) {
        expired++; // ติดลบ = เกินกำหนด
      } else if (diff <= 3) {
        near++; // เหลือ 0-3 วัน = ใกล้ครบกำหนด (แก้เลข 3 เพื่อเปลี่ยนเกณฑ์)
      }
    }

    if (mounted) {
      setState(() {
        totalItems = total;

        nearExpiryItems = near;

        expiredItems = expired;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง (ฟ้าอ่อน)

      body: SafeArea(
        child: LayoutBuilder( // รู้ขนาดจอ เพื่อคำนวณขนาดของต่างๆ เป็นสัดส่วนของจอ (จอเล็ก/ใหญ่ดูเหมือนกัน)
          builder: (context, size) {
            final screenHeight = size.maxHeight; // ความสูงจอที่ใช้ได้

            final screenWidth = size.maxWidth; // ความกว้างจอ

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.07, // [UI] ระยะซ้ายขวา = 7% ของความกว้างจอ

                vertical: screenHeight * 0.03, // [UI] ระยะบนล่าง = 3% ของความสูงจอ
              ),

              child: Column(
                children: [
                  // ================= HEADER =================
                  SizedBox(
                    height: screenHeight * 0.12, // [UI] ความสูงส่วนหัว = 12% ของจอ

                    child: Row(
                      children: [
                        CircleAvatar( // รูปโปรไฟล์วงกลม
                          radius: screenWidth * 0.07, // [UI] รัศมี = 7% ของความกว้างจอ

                          backgroundColor: const Color(0xff5189C9), // [UI] สีวงกลม (ฟ้า)

                          child: Icon(
                            Icons.person,

                            size: screenWidth * 0.09, // [UI] ขนาดไอคอนคน

                            color: Colors.white,
                          ),
                        ),

                        SizedBox(width: screenWidth * 0.03), // [UI] ระยะรูปกับข้อความ

                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                "SmartFridge", // ชื่อแอป

                                style: TextStyle(
                                  fontSize: screenWidth * 0.065, // [UI] ขนาดชื่อแอป (6.5% ของความกว้างจอ)

                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              Text(
                                "ตู้เย็นอัจฉริยะของคุณ $userName",

                                style: TextStyle(fontSize: screenWidth * 0.035), // [UI] ขนาดข้อความรอง
                              ),
                            ],
                          ),
                        ),

                        IconButton( // ปุ่มฟันเฟือง -> หน้าโปรไฟล์
                          icon: Icon(Icons.settings, size: screenWidth * 0.08), // [UI] ขนาดไอคอนฟันเฟือง

                          onPressed: () async {
                            await Navigator.push(
                              context,

                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );

                            // โหลดชื่อใหม่หลังกลับจาก Profile

                            loadUser();
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.025), // [UI] ระยะหัวกับกล่องสรุป

                  // ================= SUMMARY =================
                  // กดแล้วไปหน้าคลัง (เช็คตู้เย็น) ที่มีป้ายวันหมดอายุบนการ์ดทุกใบ
                  // จะได้ดูได้ว่าชิ้นไหนใกล้หมดอายุ/หมดแล้ว กลับมาแล้วรีเฟรชตัวเลข
                  GestureDetector(
                    behavior: HitTestBehavior.opaque, // กดตรงไหนของกล่องก็ได้
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InventoryScreen(),
                        ),
                      ).then((_) => loadExpiryStatus()); // กลับมาแล้วนับใหม่
                    },
                    child: Container(
                      height: screenHeight * 0.09, // [UI] ความสูงกล่องสรุป (9% ของจอ)

                      decoration: BoxDecoration(
                        color: Colors.white, // [UI] พื้นขาว

                        borderRadius: BorderRadius.circular(25), // [UI] มุมโค้ง 25
                      ),

                      child: Row(
                        children: [
                          stat(totalItems.toString(), "รายการ", Colors.green), // [UI] ตัวเลขสีเขียว

                          divider(),

                          stat(
                            nearExpiryItems.toString(),
                            "ใกล้ครบกำหนด",
                            Colors.orange, // [UI] ตัวเลขสีส้ม
                          ),

                          divider(),

                          stat(
                            expiredItems.toString(),
                            "เกินกำหนด",
                            Colors.red, // [UI] ตัวเลขสีแดง
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.06), // [UI] ระยะกล่องสรุปกับตะแกรงเมนู

                  // ================= MENU =================
                  Expanded(
                    child: GridView.builder( // ตะแกรงปุ่มเมนู
                      physics: const NeverScrollableScrollPhysics(), // [UI] ห้ามเลื่อน (6 ปุ่มพอดีจอ)

                      itemCount: 6, // จำนวนปุ่ม

                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, // [UI] 2 คอลัมน์

                        crossAxisSpacing: screenWidth * 0.04, // [UI] ระยะห่างแนวนอนระหว่างปุ่ม

                        mainAxisSpacing: screenHeight * 0.025, // [UI] ระยะห่างแนวตั้งระหว่างปุ่ม

                        childAspectRatio: 1.15, // [UI] สัดส่วนกว้าง:สูงของปุ่ม (มากขึ้น = ปุ่มเตี้ยลง)
                      ),

                      itemBuilder: (context, index) {
                        // เรียงตามแถบเมนูด้านล่าง: สแกน (วัตถุดิบ, สูตร) → คลัง
                        // → เมนูอาหาร → แจ้งเตือน → แพลน
                        // ไอคอน/ชื่อ/หน้าที่เปิด อยู่ในรายการเดียวกัน จะได้ไม่สลับกัน
                        // [UI] แต่ละรายการ = (ไอคอน, ชื่อปุ่ม, คำอธิบาย, หน้าที่เปิด) แก้ได้ที่นี่
                        const menus = <(IconData, String, String, Widget)>[
                          (
                            Icons.camera_alt,
                            "ถ่ายภาพวัตถุดิบ",
                            "เพิ่มของในตู้เย็น",
                            ImageScanning(),
                          ),
                          (
                            Icons.document_scanner,
                            "สแกนสูตรอาหาร",
                            "บันทึกสูตรเข้าคลัง",
                            ScanRecipeScreen(),
                          ),
                          (
                            Icons.kitchen,
                            "เช็คตู้เย็น",
                            "ดูวัตถุดิบได้จากทุกที่",
                            InventoryScreen(),
                          ),
                          (
                            Icons.restaurant,
                            "สร้างเมนูอาหาร",
                            "จากของที่มีอยู่",
                            AiRecipeScreen(),
                          ),
                          (
                            Icons.notifications,
                            "แจ้งเตือน",
                            "ของที่อยู่ในตู้เย็นนาน",
                            ExpirationAlertScreen(),
                          ),
                          (
                            Icons.calendar_month,
                            "แพลนอาหาร",
                            "สร้างเมนูรายสัปดาห์",
                            PlanMenuScreen(),
                          ),
                        ];
                        final (icon, title, subtitle, page) = menus[index]; // หยิบข้อมูลปุ่มลำดับนี้

                        return menuCard(icon, title, subtitle, () {
                          // กลับมาหน้าหลักแล้วโหลดตัวเลขสรุปใหม่ทุกครั้ง (เช่น
                          // หลังสแกนเพิ่มของ ทำอาหาร หรือลบของ) ไม่งั้นตัวเลข
                          // จะค้างเป็นค่าตอนเปิดหน้าครั้งแรก
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => page),
                          ).then((_) => loadExpiryStatus());
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ช่องตัวเลขสรุป 1 ช่อง (ตัวเลขใหญ่ + ชื่อใต้)
  Widget stat(String number, String title, Color color) {
    return Expanded( // แบ่งความกว้างเท่ากันทั้ง 3 ช่อง
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Text(
            number,

            style: TextStyle(
              color: color, // [UI] สีตัวเลข (ส่งมาจากตอนเรียก)

              fontWeight: FontWeight.bold,

              fontSize: 28, // [UI] ขนาดตัวเลข
            ),
          ),

          const SizedBox(height: 3),

          Text(title, style: const TextStyle(color: Colors.blue, fontSize: 13)), // [UI] ชื่อช่อง สีฟ้า ขนาด 13
        ],
      ),
    );
  }

  // เส้นคั่นแนวตั้งระหว่างช่องตัวเลข
  Widget divider() {
    return Container(height: 45, width: 1, color: Colors.amber); // [UI] สูง 45 หนา 1 สีเหลืองอำพัน
  }

  // ปุ่มเมนู 1 ปุ่มในตะแกรง
  Widget menuCard(
    IconData icon,

    String title,

    String subtitle,

    VoidCallback tap,
  ) {
    return InkWell(
      onTap: tap,

      borderRadius: BorderRadius.circular(20),

      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // [UI] พื้นปุ่ม

          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

          border: Border.all(color: const Color(0xff4F8FE8)), // [UI] เส้นขอบสีฟ้า
        ),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // [UI] จัดกลางแนวตั้ง

          children: [
            Container( // วงกลมเหลืองรองไอคอน
              width: 55, // [UI] ขนาดวงกลม

              height: 55,

              decoration: const BoxDecoration(
                color: Color(0xfffff38a), // [UI] สีเหลือง

                shape: BoxShape.circle,
              ),

              child: Icon(icon, color: const Color(0xff5189C9), size: 32), // [UI] ไอคอนสีฟ้า ขนาด 32
            ),

            const SizedBox(height: 10),

            Text(
              title,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), // [UI] ชื่อปุ่ม ขนาด 15
            ),

            Text(
              subtitle,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 11), // [UI] คำอธิบาย ขนาด 11
            ),
          ],
        ),
      ),
    );
  }
}
