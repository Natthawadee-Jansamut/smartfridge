import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบล็อกอิน

import 'package:test_app/screens/auth/login_screen.dart'; // หน้า Login (ไปต่อหลังตั้งรหัสใหม่เสร็จ)

// หน้าตั้งรหัสผ่านใหม่ (เปิดมาจากลิงก์รีเซ็ตรหัสในอีเมล)
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final supabase = Supabase.instance.client;

  final passwordController = TextEditingController(); // ช่องรหัสใหม่

  final confirmPasswordController = TextEditingController(); // ช่องยืนยันรหัส

  bool loading = false; // กำลังบันทึกอยู่ไหม

  bool obscurePassword = true; // true = ซ่อนรหัส (แสดงเป็นจุด)

  bool obscureConfirm = true; // ซ่อนรหัสในช่องยืนยัน

  @override
  void dispose() { // ตอนปิดหน้า คืนหน่วยความจำ
    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();
  }

  // ---- กฎความปลอดภัยของรหัสผ่าน (แต่ละข้อคืน true เมื่อผ่าน) ----
  bool get hasMinLength => passwordController.text.length >= 8; // ยาวอย่างน้อย 8 ตัว (แก้เลข 8 เพื่อเปลี่ยนความยาวขั้นต่ำ)

  bool get hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text); // มีตัวพิมพ์ใหญ่

  bool get hasLowercase => RegExp(r'[a-z]').hasMatch(passwordController.text); // มีตัวพิมพ์เล็ก

  bool get hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text); // มีตัวเลข

  bool get hasSpecial =>
      RegExp(r'[!@#$%^&*]').hasMatch(passwordController.text); // มีอักขระพิเศษ

  bool get passwordValid =>
      hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecial; // ผ่านครบทุกข้อ

  // กดบันทึก -> ตั้งรหัสใหม่
  Future<void> updatePassword() async {
    final password = passwordController.text.trim();

    final confirm = confirmPasswordController.text.trim();

    if (!passwordValid) { // รหัสไม่ผ่านกฎ
      showMessage("Password does not meet requirements");

      return;
    }

    if (password != confirm) { // สองช่องไม่ตรงกัน
      showMessage("Passwords do not match");

      return;
    }

    setState(() {
      loading = true;
    });

    try {
      await supabase.auth.updateUser(UserAttributes(password: password)); // บันทึกรหัสใหม่

      // session นี้มาจากลิงก์ในอีเมล ให้ login ใหม่ด้วยรหัสผ่านที่เพิ่งตั้ง

      await supabase.auth.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password updated successfully")),
        );

        Navigator.pushAndRemoveUntil( // ไปหน้า Login และล้างหน้าเก่าทั้งหมด
          context,

          MaterialPageRoute(builder: (_) => const LoginScreen()),

          (route) => false,
        );
      }
    } catch (e) {
      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // แสดงข้อความแถบด้านล่างจอ
  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // แถวแสดงกฎรหัสผ่าน 1 ข้อ (ผ่าน = ติ๊กฟ้า, ยังไม่ผ่าน = วงกลมเทา)
  Widget passwordCheck(String text, bool status) {
    return Row(
      children: [
        Icon(
          status ? Icons.check_circle : Icons.radio_button_unchecked, // [UI] ไอคอนตามสถานะ

          size: 16, // [UI] ขนาดไอคอน

          color: status ? const Color(0xff5189C9) : Colors.grey, // [UI] ผ่าน = ฟ้า ไม่ผ่าน = เทา
        ),

        const SizedBox(width: 8), // [UI] ระยะไอคอนกับข้อความ

        Text(
          text,

          style: TextStyle(
            fontSize: 13, // [UI] ขนาดตัวอักษร

            color: status ? const Color(0xff5189C9) : Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง (ฟ้าอ่อน)

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              IconButton( // ปุ่มย้อนกลับ
                padding: EdgeInsets.zero, // [UI] ไม่มีระยะในปุ่ม (ชิดขอบซ้าย)

                icon: const Icon(
                  Icons.arrow_back,

                  size: 30, // [UI] ขนาดลูกศร

                  color: Color(0xff5189C9), // [UI] สีฟ้า
                ),

                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 30),

              Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_reset, // [UI] ไอคอนแม่กุญแจ

                      size: 80,

                      color: Color(0xff5189C9),
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      "Reset Password", // หัวข้อหน้า

                      style: TextStyle(
                        fontSize: 26, // [UI] ขนาดหัวข้อ

                        fontWeight: FontWeight.bold,

                        color: Color(0xff5189C9),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 35),

              TextField( // ช่องรหัสใหม่
                controller: passwordController,

                obscureText: obscurePassword, // ซ่อน/แสดงรหัส

                onChanged: (value) {
                  setState(() {}); // พิมพ์ทุกตัว วาดใหม่ให้รายการกฎอัปเดตทันที
                },

                decoration: InputDecoration(
                  labelText: "New Password",

                  prefixIcon: const Icon(
                    Icons.lock_outline, // [UI] ไอคอนแม่กุญแจหน้าช่อง

                    color: Color(0xff5189C9),
                  ),

                  suffixIcon: IconButton( // ปุ่มรูปตา กดสลับซ่อน/แสดงรหัส
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),

                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword; // สลับค่า
                      });
                    },
                  ),

                  filled: true,

                  fillColor: Colors.white, // [UI] พื้นช่องขาว

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

                    borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // รายการกฎรหัสผ่าน (ติ๊กถูกทีละข้อเมื่อผ่าน)
              passwordCheck("At least 8 characters", hasMinLength),

              passwordCheck("At least 1 uppercase letter (A-Z)", hasUppercase),

              passwordCheck("At least 1 lowercase letter (a-z)", hasLowercase),

              passwordCheck("At least 1 number (0-9)", hasNumber),

              passwordCheck(
                "At least 1 special character (!@#\$%^&*)",
                hasSpecial,
              ),

              const SizedBox(height: 20),

              TextField( // ช่องยืนยันรหัส
                controller: confirmPasswordController,

                obscureText: obscureConfirm,

                decoration: InputDecoration(
                  labelText: "Confirm Password",

                  prefixIcon: const Icon(
                    Icons.lock_outline,

                    color: Color(0xff5189C9),
                  ),

                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility : Icons.visibility_off,
                    ),

                    onPressed: () {
                      setState(() {
                        obscureConfirm = !obscureConfirm;
                      });
                    },
                  ),

                  filled: true,

                  fillColor: Colors.white,

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),

                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const Spacer(), // ดันปุ่มลงล่างสุด

              SizedBox(
                width: double.infinity, // [UI] ปุ่มกว้างเต็ม

                height: 55, // [UI] ความสูงปุ่ม

                child: ElevatedButton(
                  onPressed: loading || !passwordValid ? null : updatePassword, // กำลังโหลดหรือรหัสยังไม่ผ่าน = กดไม่ได้

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffffd84d), // [UI] สีปุ่มปกติ (เหลือง)

                    disabledBackgroundColor: Colors.grey.shade300, // [UI] สีปุ่มตอนกดไม่ได้ (เทา)

                    foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษร

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25), // [UI] มุมโค้ง
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(
                          color: Color(0xff5189C9),
                        )
                      : const Text(
                          "Save Password",

                          style: TextStyle(
                            fontSize: 18,

                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
