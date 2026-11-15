import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบสมัครสมาชิก/ล็อกอิน
import 'package:test_app/screens/auth/verify_email_otp_screen.dart'; // หน้ากรอก OTP (ไปต่อหลังสมัคร)

// หน้าสมัครสมาชิก
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>(); // กุญแจฟอร์ม ใช้สั่งตรวจทุกช่อง

  final supabase = Supabase.instance.client;

  final firstNameController = TextEditingController(); // ช่องชื่อ

  final lastNameController = TextEditingController(); // ช่องนามสกุล

  final emailController = TextEditingController(); // ช่องอีเมล

  final passwordController = TextEditingController(); // ช่องรหัสผ่าน

  final confirmPasswordController = TextEditingController(); // ช่องยืนยันรหัส

  final phoneController = TextEditingController(); // ช่องเบอร์โทร

  bool obscurePassword = true; // ซ่อนรหัสไหม

  bool obscureConfirm = true; // ซ่อนรหัสยืนยันไหม

  bool isLoading = false; // กำลังสมัครอยู่ไหม

  bool get _hasMinLength => passwordController.text.length >= 8; // กฎ: ยาว 8 ตัวขึ้นไป

  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text); // กฎ: มีตัวพิมพ์ใหญ่

  bool get _hasLowercase => RegExp(r'[a-z]').hasMatch(passwordController.text); // กฎ: มีตัวพิมพ์เล็ก

  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text); // กฎ: มีตัวเลข

  bool get _hasSpecialChar => // กฎ: มีอักขระพิเศษ
      RegExp(r'[!@#$%^&*]').hasMatch(passwordController.text);

  @override
  void dispose() { // ปิดหน้า คืนหน่วยความจำของทุกช่อง
    firstNameController.dispose();

    lastNameController.dispose();

    emailController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    phoneController.dispose();

    super.dispose();
  }

  // ตรวจรหัสผ่าน คืนข้อความ error ข้อแรกที่ไม่ผ่าน (null = ผ่าน)
  String? validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return "Required";
    }

    if (password.length < 8) {
      return "Minimum 8 characters";
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return "Add uppercase letter";
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return "Add lowercase letter";
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return "Add a number";
    }

    if (!RegExp(r'[!@#$%^&*]').hasMatch(password)) {
      return "Add special character !@#\$%^&*";
    }

    return null; // ผ่านทุกข้อ
  }

  // กดปุ่ม Register
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return; // ตรวจทุกช่อง มีช่องผิดก็หยุด

    setState(() {
      isLoading = true;
    });

    try {
      final response = await supabase.auth.signUp( // สมัครสมาชิกกับ Supabase
        email: emailController.text.trim(),

        password: passwordController.text.trim(),

        emailRedirectTo: 'smartfridge://login-callback/', // ลิงก์ยืนยันในอีเมลให้เด้งกลับเข้าแอป

        data: { // ข้อมูลเพิ่มเติมของผู้ใช้
          'first_name': firstNameController.text.trim(),

          'last_name': lastNameController.text.trim(),

          'phone': phoneController.text.trim(),
        },
      );

      if (!mounted) return;

      if (response.user != null) { // สมัครสำเร็จ -> ไปหน้ากรอก OTP
        Navigator.push(
          context,

          MaterialPageRoute(
            builder: (_) =>
                VerifyEmailOtpScreen(email: emailController.text.trim()),
          ),
        );
      }
    } on AuthException catch (e) { // error จากระบบ (เช่น อีเมลซ้ำ)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Something went wrong")));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // แถวกฎรหัสผ่าน 1 ข้อ (ผ่าน = ติ๊กฟ้า)
  Widget buildPasswordRequirement(String text, bool isPassed) {
    return Padding(
      padding: const EdgeInsets.only(top: 4), // [UI] ระยะห่างบนแต่ละแถว

      child: Row(
        children: [
          Icon(
            isPassed ? Icons.check_circle : Icons.radio_button_unchecked,

            size: 16, // [UI] ขนาดไอคอน

            color: isPassed ? const Color(0xff5189C9) : Colors.grey, // [UI] ผ่าน = ฟ้า ไม่ผ่าน = เทา
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              text,

              style: TextStyle(
                fontSize: 12, // [UI] ขนาดตัวอักษร

                color: isPassed
                    ? const Color(0xff5189C9)
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // รายการกฎรหัสผ่านทั้งหมด
  Widget buildPasswordRequirements() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          buildPasswordRequirement("At least 8 characters", _hasMinLength),

          buildPasswordRequirement(
            "At least 1 uppercase letter (A-Z)",
            _hasUppercase,
          ),

          buildPasswordRequirement(
            "At least 1 lowercase letter (a-z)",
            _hasLowercase,
          ),

          buildPasswordRequirement("At least 1 number (0-9)", _hasNumber),

          buildPasswordRequirement(
            "At least 1 special character (!@#\$%^&*)",
            _hasSpecialChar,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container( // [UI] พื้นหลังเต็มจอ
        width: double.infinity,

        height: double.infinity,

        decoration: const BoxDecoration(
          gradient: LinearGradient( // [UI] พื้นหลังไล่สี
            colors: [Color(0xffD8EEFF), Colors.white], // [UI] ฟ้าอ่อน (บน) -> ขาว (ล่าง)

            begin: Alignment.topCenter,

            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: LayoutBuilder( // รู้ขนาดจอ
            builder: (context, constraints) {
              return SingleChildScrollView( // เลื่อนได้ (ฟอร์มยาว)
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight), // [UI] สูงอย่างน้อยเท่าจอ

                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24, // [UI] ระยะซ้ายขวา

                      vertical: 32, // [UI] ระยะบนล่าง
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_add, // [UI] ไอคอนคน + บวก

                            size: 70, // [UI] ขนาดไอคอน

                            color: Color(0xff5189C9),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            "Create Account",

                            style: TextStyle(
                              fontSize: 26, // [UI] ขนาดหัวข้อ

                              fontWeight: FontWeight.bold,

                              color: Color(0xff5189C9),
                            ),
                          ),

                          const SizedBox(height: 30), // [UI] ระยะหัวข้อกับช่องแรก

                          Row( // ชื่อ + นามสกุล อยู่แถวเดียวกัน
                            children: [
                              Expanded(
                                child: buildTextField(
                                  controller: firstNameController,

                                  label: "First Name",

                                  icon: Icons.person_outline,

                                  validator: (value) {
                                    return value!.isEmpty ? "Required" : null; // ว่าง = ต้องกรอก
                                  },
                                ),
                              ),

                              const SizedBox(width: 12), // [UI] ระยะระหว่างช่องชื่อกับนามสกุล

                              Expanded(
                                child: buildTextField(
                                  controller: lastNameController,

                                  label: "Last Name",

                                  icon: Icons.person_outline,

                                  validator: (value) {
                                    return value!.isEmpty ? "Required" : null;
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16), // [UI] ระยะระหว่างแถวช่องกรอก

                          buildTextField(
                            controller: emailController,

                            label: "Email",

                            icon: Icons.email_outlined,

                            keyboardType: TextInputType.emailAddress, // [UI] คีย์บอร์ดแบบอีเมล

                            validator: (value) {
                              if (value == null ||
                                  !RegExp(
                                    r'^[^@]+@[^@]+\.[^@]+', // รูปแบบ xxx@xxx.xxx
                                  ).hasMatch(value)) {
                                return "Enter valid email";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          buildTextField(
                            controller: passwordController,

                            label: "Password",

                            icon: Icons.lock_outline,

                            obscureText: obscurePassword,

                            onChanged: (value) {
                              setState(() {}); // พิมพ์ทุกตัว วาดใหม่ให้รายการกฎอัปเดต
                            },

                            suffix: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),

                              onPressed: () {
                                setState(() {
                                  obscurePassword = !obscurePassword;
                                });
                              },
                            ),

                            validator: validatePassword, // ใช้ฟังก์ชันตรวจรหัสด้านบน
                          ),

                          buildPasswordRequirements(), // แสดงรายการกฎใต้ช่องรหัส

                          const SizedBox(height: 16),

                          buildTextField(
                            controller: confirmPasswordController,

                            label: "Confirm Password",

                            icon: Icons.lock_outline,

                            obscureText: obscureConfirm,

                            suffix: IconButton(
                              icon: Icon(
                                obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),

                              onPressed: () {
                                setState(() {
                                  obscureConfirm = !obscureConfirm;
                                });
                              },
                            ),

                            validator: (value) {
                              if (value != passwordController.text) { // ต้องตรงกับช่องรหัสผ่าน
                                return "Passwords do not match";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          buildTextField(
                            controller: phoneController,

                            label: "Phone (Optional)",

                            icon: Icons.phone_outlined,

                            keyboardType: TextInputType.phone, // [UI] คีย์บอร์ดแบบเบอร์โทร
                          ),

                          const SizedBox(height: 30),

                          SizedBox(
                            width: double.infinity, // [UI] ปุ่มกว้างเต็ม

                            height: 55, // [UI] ความสูงปุ่ม

                            child: ElevatedButton(
                              onPressed: isLoading ? null : _register, // กำลังสมัคร = กดไม่ได้

                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xffffd84d), // [UI] สีปุ่มเหลือง

                                foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษรฟ้า

                                elevation: 6, // [UI] เงาปุ่ม

                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25), // [UI] มุมโค้ง
                                ),
                              ),

                              child: isLoading
                                  ? const CircularProgressIndicator(
                                      color: Color(0xff5189C9),
                                    )
                                  : const Text(
                                      "Register",

                                      style: TextStyle(
                                        fontSize: 18,

                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          TextButton(
                            onPressed: () {
                              Navigator.pop(context); // กลับหน้า Login
                            },

                            child: const Text(
                              "Already have an account? Login",

                              style: TextStyle(color: Color(0xff5189C9)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // สร้างช่องกรอก 1 ช่อง (ใช้ซ้ำทุกช่องในหน้านี้)
  Widget buildTextField({
    required TextEditingController controller,

    required String label,

    required IconData icon,

    TextInputType keyboardType = TextInputType.text, // ชนิดคีย์บอร์ด (ค่าเริ่มต้น = ข้อความ)

    bool obscureText = false, // ซ่อนข้อความไหม (ใช้กับรหัส)

    Widget? suffix, // ปุ่มท้ายช่อง (เช่นปุ่มตา)

    String? Function(String?)? validator, // ฟังก์ชันตรวจความถูกต้อง

    void Function(String)? onChanged, // พิมพ์แล้วทำอะไร
  }) {
    return TextFormField(
      controller: controller,

      keyboardType: keyboardType,

      obscureText: obscureText,

      validator: validator,

      onChanged: onChanged,

      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xff5189C9)), // [UI] ไอคอนหน้าช่องสีฟ้า

        suffixIcon: suffix,

        labelText: label,

        filled: true,

        fillColor: Colors.white, // [UI] พื้นช่องขาว

        contentPadding: const EdgeInsets.symmetric(
          vertical: 18, // [UI] ระยะในบนล่าง (ความสูงช่อง)

          horizontal: 20, // [UI] ระยะในซ้ายขวา
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20

          borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
        ),
      ),
    );
  }
}
