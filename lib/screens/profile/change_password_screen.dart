import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/services/reauth.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final supabase = Supabase.instance.client;

  /// รหัสผ่านปัจจุบัน — ต้องถูกก่อนถึงเปลี่ยนได้ (กันคนหยิบโทรศัพท์ที่ล็อกอินค้างไว้)
  final currentPasswordController = TextEditingController();

  bool hideCurrent = true;

  /// ข้อความเตือนสีแดงใต้ช่องรหัสผ่านปัจจุบัน (null = ไม่มี)
  String? currentError;

  final passwordController = TextEditingController();

  final confirmPasswordController = TextEditingController();

  bool hidePassword = true;

  bool hideConfirm = true;

  bool loading = false;

  @override
  void dispose() {
    currentPasswordController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();
  }

  // =========================
  // Password Requirement
  // =========================

  bool get hasMinLength => passwordController.text.length >= 8;

  bool get hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text);

  bool get hasLowercase => RegExp(r'[a-z]').hasMatch(passwordController.text);

  bool get hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text);

  bool get hasSpecial =>
      RegExp(r'[!@#$%^&*]').hasMatch(passwordController.text);

  bool get passwordValid =>
      hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecial;

  Future<void> changePassword() async {
    final current = currentPasswordController.text.trim();

    final password = passwordController.text.trim();

    final confirm = confirmPasswordController.text.trim();

    if (current.isEmpty) {
      setState(() => currentError = "กรุณากรอกรหัสผ่านปัจจุบัน");

      return;
    }

    if (!passwordValid) {
      showMessage("รหัสผ่านไม่ตรงตามเงื่อนไข");

      return;
    }

    if (password != confirm) {
      showMessage("รหัสผ่านไม่ตรงกัน");

      return;
    }

    if (password == current) {
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

      await supabase.auth.updateUser(UserAttributes(password: password));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("เปลี่ยนรหัสผ่านเรียบร้อย")),
        );

        Navigator.pop(context);
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

  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget passwordCheck(String text, bool status) {
    return Row(
      children: [
        Icon(
          status ? Icons.check_circle : Icons.radio_button_unchecked,

          size: 16,

          color: status ? const Color(0xff5189C9) : Colors.grey,
        ),

        const SizedBox(width: 8),

        Text(
          text,

          style: TextStyle(
            fontSize: 13,

            color: status ? const Color(0xff5189C9) : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget buildPasswordField(
    String label,

    TextEditingController controller,

    bool hide,

    VoidCallback toggle,

    Function(String) onChanged, {
    String? errorText,
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

          borderSide: const BorderSide(color: Color(0xffD93025), width: 1.5),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: const BorderSide(color: Color(0xffD93025), width: 1.5),
        ),

        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xff5189C9)),

        suffixIcon: IconButton(
          icon: Icon(hide ? Icons.visibility : Icons.visibility_off),

          onPressed: toggle,
        ),

        filled: true,

        fillColor: Colors.white,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

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
                    fontSize: 26,

                    fontWeight: FontWeight.bold,

                    color: Color(0xff5189C9),
                  ),
                ),
              ),

              const SizedBox(height: 35),

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
                  setState(() {});
                },
              ),

              const SizedBox(height: 12),

              passwordCheck("อย่างน้อย 8 ตัวอักษร", hasMinLength),

              passwordCheck("ตัวพิมพ์ใหญ่ A-Z", hasUppercase),

              passwordCheck("ตัวพิมพ์เล็ก a-z", hasLowercase),

              passwordCheck("ตัวเลข 0-9", hasNumber),

              passwordCheck("อักขระพิเศษ !@#\$%^&*", hasSpecial),

              const SizedBox(height: 20),

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

                height: 55,

                child: ElevatedButton(
                  onPressed: loading || !passwordValid ? null : changePassword,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffffd84d),

                    disabledBackgroundColor: Colors.grey.shade300,

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
