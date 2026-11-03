import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;

  String userName = "User";

  @override
  void initState() {
    super.initState();

    loadUser();
  }

  Future<void> loadUser() async {
    final response = await supabase.auth.getUser();

    final user = response.user;

    if (user != null) {
      final firstName = user.userMetadata?['first_name'] ?? "";

      final lastName = user.userMetadata?['last_name'] ?? "";

      if (mounted) {
        setState(() {
          if (firstName.isNotEmpty && lastName.isNotEmpty) {
            userName = "$firstName $lastName";
          } else if (firstName.isNotEmpty) {
            userName = firstName;
          } else {
            userName = user.email ?? "User";
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),

          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,

                child: CircleAvatar(
                  backgroundColor: const Color(0xfffff38a),

                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),

                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25),

              CircleAvatar(
                radius: 65,

                backgroundColor: const Color(0xff5189C9),

                child: const Icon(Icons.person, size: 85, color: Colors.white),
              ),

              const SizedBox(height: 20),

              Text(
                userName,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontSize: 30,

                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 35),

              settingCard("แก้ไขข้อมูลส่วนตัว", () async {
                final result = await Navigator.push(
                  context,

                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );

                if (result != null) {
                  await loadUser();
                }
              }),

              settingCard("เปลี่ยนรหัสผ่าน", () {
                Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              }),

              settingCard("ออกจากระบบ", () {
                logoutDialog();
              }),

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

  Widget settingCard(String title, VoidCallback onTap, {bool danger = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),

      height: 60,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: const Color(0xff5189C9)),
      ),

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(20),

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),

          child: Row(
            children: [
              Text(
                title,

                style: TextStyle(
                  fontSize: 18,

                  color: danger ? Colors.red : Colors.black,
                ),
              ),

              const Spacer(),

              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void logoutDialog() {
    showDialog(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: const Text("ออกจากระบบ"),

          content: const Text("คุณต้องการออกจากระบบใช่หรือไม่?"),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
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

                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}
