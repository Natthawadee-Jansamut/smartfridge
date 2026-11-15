import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบผู้ใช้

// หน้าที่ไปต่อได้จากหน้าโปรไฟล์
import 'package:test_app/screens/profile/edit_profile_screen.dart';
import 'package:test_app/screens/profile/change_password_screen.dart';
import 'package:test_app/screens/profile/delete_account_screen.dart';
import 'package:test_app/screens/auth/login_screen.dart';

// หน้าโปรไฟล์: แสดงชื่อผู้ใช้ + เมนูตั้งค่าบัญชี
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;

  String userName = "User"; // ชื่อที่แสดง (ค่าเริ่มต้นก่อนโหลดเสร็จ)

  @override
  void initState() {
    super.initState();

    loadUser(); // โหลดชื่อผู้ใช้
  }

  // ดึงข้อมูลผู้ใช้จากเซิร์ฟเวอร์ แล้วเลือกชื่อที่จะแสดง
  Future<void> loadUser() async {
    final response = await supabase.auth.getUser(); // ขอข้อมูลผู้ใช้ล่าสุด

    final user = response.user;

    if (user != null) {
      final firstName = user.userMetadata?['first_name'] ?? ""; // ชื่อ

      final lastName = user.userMetadata?['last_name'] ?? ""; // นามสกุล

      if (mounted) {
        setState(() {
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            userName = "$firstName $lastName"; // มีครบ -> "ชื่อ นามสกุล"
          } else if (firstName.isNotEmpty) {
            userName = firstName; // มีแค่ชื่อ
          } else {
            userName = user.email ?? "User"; // ไม่มีชื่อเลย -> ใช้อีเมลแทน
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง (ฟ้าอ่อน)

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ

          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft, // [UI] ปุ่มย้อนกลับมุมซ้ายบน

                child: CircleAvatar( // วงกลมรองปุ่ม
                  backgroundColor: const Color(0xfffff38a), // [UI] สีวงกลม (เหลือง)

                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),

                    onPressed: () {
                      Navigator.pop(context); // กลับหน้าก่อน
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25), // [UI] ระยะห่าง

              CircleAvatar( // รูปโปรไฟล์ (วงกลม + ไอคอนคน)
                radius: 65, // [UI] รัศมีวงกลมโปรไฟล์ (ใหญ่ขึ้น = เพิ่มเลข)

                backgroundColor: const Color(0xff5189C9), // [UI] สีวงกลม (ฟ้า)

                child: const Icon(Icons.person, size: 85, color: Colors.white), // [UI] ไอคอนคนสีขาว ขนาด 85
              ),

              const SizedBox(height: 20),

              Text(
                userName, // ชื่อผู้ใช้

                textAlign: TextAlign.center, // [UI] จัดกึ่งกลาง

                style: const TextStyle(
                  fontSize: 30, // [UI] ขนาดชื่อ

                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 35), // [UI] ระยะชื่อกับเมนู

              // เมนู: แก้ไขข้อมูล -> ถ้ากลับมาพร้อมข้อมูลใหม่ ให้โหลดชื่อใหม่
              settingCard("แก้ไขข้อมูลส่วนตัว", () async {
                final result = await Navigator.push(
                  context,

                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );

                if (result != null) { // บันทึกแล้ว (ไม่ได้กดย้อนกลับเฉยๆ)
                  await loadUser();
                }
              }),

              // เมนู: เปลี่ยนรหัสผ่าน
              settingCard("เปลี่ยนรหัสผ่าน", () {
                Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              }),

              // เมนู: ออกจากระบบ -> ถามยืนยันก่อน
              settingCard("ออกจากระบบ", () {
                logoutDialog();
              }),

              // เมนู: ลบบัญชี (danger = ตัวอักษรสีแดง)
              settingCard("ลบบัญชี", () {
                Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (_) => const DeleteAccountScreen(),
                  ),
                );
              }, danger: true),
            ],
          ),
        ),
      ),
    );
  }

  // สร้างการ์ดเมนูตั้งค่า 1 อัน (ข้อความ + ลูกศรขวา)
  Widget settingCard(String title, VoidCallback onTap, {bool danger = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22), // [UI] ระยะห่างใต้การ์ดแต่ละอัน

      height: 60, // [UI] ความสูงการ์ด

      decoration: BoxDecoration(
        color: Colors.white, // [UI] พื้นการ์ด

        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

        border: Border.all(color: const Color(0xff5189C9)), // [UI] เส้นขอบสีฟ้า
      ),

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(20),

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30), // [UI] ระยะในซ้าย-ขวา

          child: Row(
            children: [
              Text(
                title,

                style: TextStyle(
                  fontSize: 18, // [UI] ขนาดตัวอักษร

                  color: danger ? Colors.red : Colors.black, // [UI] เมนูอันตรายเป็นสีแดง ปกติสีดำ
                ),
              ),

              const Spacer(), // ดันลูกศรไปชิดขวา

              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey), // [UI] ลูกศรขวาสีเทา
            ],
          ),
        ),
      ),
    );
  }

  // ป๊อปอัปยืนยันการออกจากระบบ
  void logoutDialog() {
    showDialog(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), // [UI] มุมป๊อปอัปโค้ง 20
          ),

          title: const Text("ออกจากระบบ"),

          content: const Text("คุณต้องการออกจากระบบใช่หรือไม่?"),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // ปิดป๊อปอัป ไม่ทำอะไร
              },

              child: const Text("ยกเลิก"),
            ),

            TextButton(
              onPressed: () async {
                // ปิด Dialog ก่อน

                Navigator.pop(dialogContext);

                // Logout Supabase

                await supabase.auth.signOut();

                if (!mounted) return;

                // ไปหน้า Login และล้าง Stack ทั้งหมด

                Navigator.pushAndRemoveUntil(
                  context,

                  MaterialPageRoute(builder: (context) => const LoginScreen()),

                  (route) => false,
                );
              },

              child: const Text(
                "ออกจากระบบ",

                style: TextStyle(color: Colors.red), // [UI] ปุ่มยืนยันสีแดง
              ),
            ),
          ],
        );
      },
    );
  }
}
