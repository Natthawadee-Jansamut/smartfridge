import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบผู้ใช้
import 'package:test_app/services/reauth.dart'; // ตรวจรหัสผ่านปัจจุบัน

// หน้าเปลี่ยนรหัสผ่าน (ต้องกรอกรหัสปัจจุบันก่อน)
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final supabase = Supabase.instance.client;

  /// รหัสผ่านปัจจุบัน — ต้องถูกก่อนถึงเปลี่ยนได้ (กันคนหยิบโทรศัพท์ที่ล็อกอินค้างไว้)
  final currentPasswordController = TextEditingController();

  bool hideCurrent = true; // ซ่อนรหัสปัจจุบันไหม

  /// ข้อความเตือนสีแดงใต้ช่องรหัสผ่านปัจจุบัน (null = ไม่มี)
  String? currentError;

  final passwordController = TextEditingController(); // ช่องรหัสใหม่

  final confirmPasswordController = TextEditingController(); // ช่องยืนยันรหัสใหม่

  bool hidePassword = true; // ซ่อนรหัสใหม่ไหม

  bool hideConfirm = true; // ซ่อนรหัสยืนยันไหม

  bool loading = false; // กำลังบันทึกอยู่ไหม

  @override
  void dispose() { // ปิดหน้า คืนหน่วยความจำ
    currentPasswordController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();
  }

  // =========================
  // Password Requirement
  // =========================

  bool get hasMinLength => passwordController.text.length >= 8; // ยาว 8 ตัวขึ้นไป

  bool get hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text); // มีตัวพิมพ์ใหญ่

  bool get hasLowercase => RegExp(r'[a-z]').hasMatch(passwordController.text); // มีตัวพิมพ์เล็ก

  bool get hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text); // มีตัวเลข

  bool get hasSpecial =>
      RegExp(r'[!@#$%^&*]').hasMatch(passwordController.text); // มีอักขระพิเศษ

  bool get passwordValid =>
      hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecial; // ผ่านทุกข้อ

  // กดบันทึก -> ตรวจทุกอย่างแล้วเปลี่ยนรหัส
  Future<void> changePassword() async {
    final current = currentPasswordController.text.trim();

    final password = passwordController.text.trim();

    final confirm = confirmPasswordController.text.trim();

    if (current.isEmpty) { // ไม่กรอกรหัสปัจจุบัน
      setState(() => currentError = "กรุณากรอกรหัสผ่านปัจจุบัน");

      return;
    }

    if (!passwordValid) { // รหัสใหม่ไม่ผ่านกฎ
      showMessage("รหัสผ่านไม่ตรงตามเงื่อนไข");

      return;
    }

    if (password != confirm) { // รหัสใหม่กับยืนยันไม่ตรงกัน
      showMessage("รหัสผ่านไม่ตรงกัน");

      return;
    }

    if (password == current) { // รหัสใหม่ซ้ำรหัสเดิม
      showMessage("รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน");

      return;
    }

    setState(() {
      loading = true;
    });

    try {
      // ยืนยันตัวตนด้วยรหัสผ่านปัจจุบันก่อน
      if (!await verifyCurrentPassword(current)) {
        if (mounted) {
          setState(() => currentError = "รหัสผ่านปัจจุบันไม่ถูกต้อง");
        }

        return;
      }

      await supabase.auth.updateUser(UserAttributes(password: password)); // บันทึกรหัสใหม่

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("เปลี่ยนรหัสผ่านเรียบร้อย")),
        );

        Navigator.pop(context); // กลับหน้าโปรไฟล์
      }
    } on AuthException catch (e) {
      showMessage(e.message);
    } catch (e) {
      showMessage("เกิดข้อผิดพลาด กรุณาลองใหม่");
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // แถบข้อความด้านล่างจอ
  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // แถวกฎรหัสผ่าน 1 ข้อ (ผ่าน = ติ๊กฟ้า)
  Widget passwordCheck(String text, bool status) {
    return Row(
      children: [
        Icon(
          status ? Icons.check_circle : Icons.radio_button_unchecked,

          size: 16, // [UI] ขนาดไอคอน

          color: status ? const Color(0xff5189C9) : Colors.grey, // [UI] ผ่าน = ฟ้า ไม่ผ่าน = เทา
        ),

        const SizedBox(width: 8),

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

  // สร้างช่องกรอกรหัสผ่าน 1 ช่อง (ใช้ซ้ำ 3 ช่อง)
  Widget buildPasswordField(
    String label, // ป้ายในช่อง

    TextEditingController controller,

    bool hide, // ซ่อนรหัสไหม

    VoidCallback toggle, // กดปุ่มตา

    Function(String) onChanged, { // พิมพ์แล้วทำอะไร
    String? errorText, // ข้อความแดงใต้ช่อง
  }) {
    return TextField(
      controller: controller,

      obscureText: hide,

      onChanged: onChanged,

      decoration: InputDecoration(
        labelText: label,

        // เตือนสีแดงใต้ช่อง (ขอบแดง + ข้อความ) แบบเดียวกับหน้าสร้างแพลน
        errorText: errorText,

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: const BorderSide(color: Color(0xffD93025), width: 1.5), // [UI] ขอบแดงตอน error
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: const BorderSide(color: Color(0xffD93025), width: 1.5),
        ),

        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xff5189C9)), // [UI] ไอคอนแม่กุญแจ

        suffixIcon: IconButton(
          icon: Icon(hide ? Icons.visibility : Icons.visibility_off), // [UI] ไอคอนตา

          onPressed: toggle,
        ),

        filled: true,

        fillColor: Colors.white, // [UI] พื้นช่องขาว

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

          borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบปกติ
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง

      body: SafeArea(
        child: SingleChildScrollView( // เลื่อนได้
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,

                  size: 30,

                  color: Color(0xff5189C9),
                ),

                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  "เปลี่ยนรหัสผ่าน",

                  style: TextStyle(
                    fontSize: 26, // [UI] ขนาดหัวข้อ

                    fontWeight: FontWeight.bold,

                    color: Color(0xff5189C9),
                  ),
                ),
              ),

              const SizedBox(height: 35),

              // ช่องที่ 1: รหัสปัจจุบัน
              buildPasswordField(
                "รหัสผ่านปัจจุบัน",

                currentPasswordController,

                hideCurrent,

                () {
                  setState(() {
                    hideCurrent = !hideCurrent;
                  });
                },

                (value) {
                  // เริ่มพิมพ์ใหม่ -> ซ่อนข้อความเตือนเดิม
                  if (currentError != null) {
                    setState(() => currentError = null);
                  }
                },

                errorText: currentError,
              ),

              const SizedBox(height: 20),

              // ช่องที่ 2: รหัสใหม่
              buildPasswordField(
                "รหัสผ่านใหม่",

                passwordController,

                hidePassword,

                () {
                  setState(() {
                    hidePassword = !hidePassword;
                  });
                },

                (value) {
                  setState(() {}); // วาดใหม่ให้รายการกฎอัปเดต
                },
              ),

              const SizedBox(height: 12),

              passwordCheck("อย่างน้อย 8 ตัวอักษร", hasMinLength),

              passwordCheck("ตัวพิมพ์ใหญ่ A-Z", hasUppercase),

              passwordCheck("ตัวพิมพ์เล็ก a-z", hasLowercase),

              passwordCheck("ตัวเลข 0-9", hasNumber),

              passwordCheck("อักขระพิเศษ !@#\$%^&*", hasSpecial),

              const SizedBox(height: 20),

              // ช่องที่ 3: ยืนยันรหัสใหม่
              buildPasswordField(
                "ยืนยันรหัสผ่าน",

                confirmPasswordController,

                hideConfirm,

                () {
                  setState(() {
                    hideConfirm = !hideConfirm;
                  });
                },

                (value) {
                  setState(() {});
                },
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,

                height: 55, // [UI] ความสูงปุ่ม

                child: ElevatedButton(
                  onPressed: loading || !passwordValid ? null : changePassword, // รหัสยังไม่ผ่าน = ปุ่มกดไม่ได้

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffffd84d), // [UI] สีปุ่มเหลือง

                    disabledBackgroundColor: Colors.grey.shade300, // [UI] สีตอนกดไม่ได้

                    foregroundColor: const Color(0xff5189C9),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(
                          color: Color(0xff5189C9),
                        )
                      : const Text(
                          "บันทึกรหัสผ่านใหม่",

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
