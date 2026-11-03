import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_screen.dart';
import 'ImageScanning.dart';
import 'inventory_screen.dart';
import 'ai_recipe_screen.dart';
import 'scan_recipe_result_screen.dart';
import 'weekly_plan_screen.dart';
import 'meal_plan_screen.dart';
import 'plan_menu_screen.dart';
import 'expiration_alert_screen.dart';
import 'scan_recipe_screen.dart';
import '../utils/fridge_age.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // ดึงชื่อ User จาก Supabase
  final supabase = Supabase.instance.client;

  String userName = "User";
  int totalItems = 0;

  int nearExpiryItems = 0;

  int expiredItems = 0;

  @override
  void initState() {
    super.initState();

    loadUser();
    loadExpiryStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    loadUser();
  }

  Future<void> loadUser() async {
    final session = supabase.auth.currentSession;

    // ถ้า logout แล้ว ไม่มี session ให้หยุดเลย
    if (session == null) {
      return;
    }

    final response = await supabase.auth.getUser();

    final user = response.user;

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
        .from('fridge_items')
        .select()
        .eq('user_id', user.id);

    int total = response.length;

    int near = 0;

    int expired = 0;

    for (var item in response) {
      if (isUsedUp(item)) continue;

      final diff = daysLeft(item);
      if (diff == null) continue;

      if (diff < 0) {
        expired++;
      } else if (diff <= 3) {
        near++;
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
      backgroundColor: const Color(0xffD8EEFF),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, size) {
            final screenHeight = size.maxHeight;

            final screenWidth = size.maxWidth;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.07,

                vertical: screenHeight * 0.03,
              ),

              child: Column(
                children: [
                  // ================= HEADER =================
                  SizedBox(
                    height: screenHeight * 0.12,

                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: screenWidth * 0.07,

                          backgroundColor: const Color(0xff5189C9),

                          child: Icon(
                            Icons.person,

                            size: screenWidth * 0.09,

                            color: Colors.white,
                          ),
                        ),

                        SizedBox(width: screenWidth * 0.03),

                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,

                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              Text(
                                "SmartFridge",

                                style: TextStyle(
                                  fontSize: screenWidth * 0.065,

                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              Text(
                                "ตู้เย็นอัจฉริยะของคุณ $userName",

                                style: TextStyle(fontSize: screenWidth * 0.035),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: Icon(Icons.settings, size: screenWidth * 0.08),

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

                  SizedBox(height: screenHeight * 0.025),

                  // ================= SUMMARY =================
                  // กดแล้วไปหน้าคลัง (เช็คตู้เย็น) ที่มีป้ายวันหมดอายุบนการ์ดทุกใบ
                  // จะได้ดูได้ว่าชิ้นไหนใกล้หมดอายุ/หมดแล้ว กลับมาแล้วรีเฟรชตัวเลข
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InventoryScreen(),
                        ),
                      ).then((_) => loadExpiryStatus());
                    },
                    child: Container(
                      height: screenHeight * 0.09,

                      decoration: BoxDecoration(
                        color: Colors.white,

                        borderRadius: BorderRadius.circular(25),
                      ),

                      child: Row(
                        children: [
                          stat(totalItems.toString(), "รายการ", Colors.green),

                          divider(),

                          stat(
                            nearExpiryItems.toString(),
                            "ใกล้ครบกำหนด",
                            Colors.orange,
                          ),

                          divider(),

                          stat(expiredItems.toString(), "เกินกำหนด", Colors.red),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.06),

                  // ================= MENU =================
                  Expanded(
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),

                      itemCount: 6,

                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,

                        crossAxisSpacing: screenWidth * 0.04,

                        mainAxisSpacing: screenHeight * 0.025,

                        childAspectRatio: 1.15,
                      ),

                      itemBuilder: (context, index) {
                        final menus = [
                          [
                            Icons.camera_alt,
                            "ถ่ายภาพวัตถุดิบ",
                            "เพิ่มของในตู้เย็น",
                          ],

                          [
                            Icons.calendar_month,
                            "แพลนอาหาร",
                            "สร้างเมนูรายสัปดาห์",
                          ],

                          [
                            Icons.notifications,
                            "แจ้งเตือน",
                            "ของที่อยู่ในตู้เย็นนาน",
                          ],

                          [
                            Icons.kitchen,
                            "เช็คตู้เย็น",
                            "ดูวัตถุดิบได้จากทุกที่",
                          ],

                          [
                            Icons.document_scanner,
                            "สแกนสูตรอาหาร",
                            "บันทึกสูตรเข้าคลัง",
                          ],

                          [
                            Icons.restaurant,
                            "สร้างเมนูอาหาร",
                            "จากของที่มีอยู่",
                          ],
                        ];

                        return menuCard(
                          menus[index][0] as IconData,

                          menus[index][1] as String,

                          menus[index][2] as String,

                          () {
                            const pages = <Widget>[
                              ImageScanning(),
                              PlanMenuScreen(),
                              ExpirationAlertScreen(),
                              InventoryScreen(),
                              ScanRecipeScreen(),
                              AiRecipeScreen(),
                            ];

                            // กลับมาหน้าหลักแล้วโหลดตัวเลขสรุปใหม่ทุกครั้ง (เช่น
                            // หลังสแกนเพิ่มของ ทำอาหาร หรือลบของ) ไม่งั้นตัวเลข
                            // จะค้างเป็นค่าตอนเปิดหน้าครั้งแรก
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => pages[index]),
                            ).then((_) => loadExpiryStatus());
                          },
                        );
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

  Widget stat(String number, String title, Color color) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Text(
            number,

            style: TextStyle(
              color: color,

              fontWeight: FontWeight.bold,

              fontSize: 28,
            ),
          ),

          const SizedBox(height: 3),

          Text(title, style: const TextStyle(color: Colors.blue, fontSize: 13)),
        ],
      ),
    );
  }

  Widget divider() {
    return Container(height: 45, width: 1, color: Colors.amber);
  }

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
          color: Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(color: const Color(0xff4F8FE8)),
        ),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 55,

              height: 55,

              decoration: const BoxDecoration(
                color: Color(0xfffff38a),

                shape: BoxShape.circle,
              ),

              child: Icon(icon, color: const Color(0xff5189C9), size: 32),
            ),

            const SizedBox(height: 10),

            Text(
              title,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            Text(
              subtitle,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
