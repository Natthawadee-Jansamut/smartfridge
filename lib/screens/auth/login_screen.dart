import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบล็อกอิน

import 'package:test_app/services/remember_me.dart'; // เก็บค่า "Remember me"
import 'package:test_app/screens/auth/register_screen.dart'; // หน้าสมัครสมาชิก
import 'package:test_app/screens/home/main_menu_screen.dart'; // หน้าหลัก (ไปต่อหลังล็อกอินสำเร็จ)
import 'package:test_app/screens/auth/forgot_password_screen.dart'; // หน้าลืมรหัสผ่าน

// หน้าเข้าสู่ระบบ (อีเมล + รหัสผ่าน)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>(); // กุญแจของฟอร์ม ใช้สั่งตรวจความถูกต้องของทุกช่อง

  final supabase = Supabase.instance.client;

  final emailController = TextEditingController(); // ช่องอีเมล

  final passwordController = TextEditingController(); // ช่องรหัสผ่าน

  bool obscurePassword = true; // true = ซ่อนรหัส

  bool isLoading = false; // กำลังล็อกอินอยู่ไหม

  bool rememberMe = false; // ติ๊ก Remember me ไหม

  @override
  void initState() {
    super.initState();

    // อ่านค่า Remember me ที่เคยติ๊กไว้ มาแสดงในช่องติ๊ก
    RememberMe.isEnabled().then((value) {
      if (mounted) {
        setState(() {
          rememberMe = value;
        });
      }
    });
  }

  @override
  void dispose() { // ปิดหน้า คืนหน่วยความจำ
    emailController.dispose();

    passwordController.dispose();

    super.dispose();
  }

  // กดปุ่ม Login
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return; // ตรวจทุกช่อง ถ้ามีช่องผิดให้หยุด (ข้อความแดงจะขึ้นใต้ช่อง)

    setState(() {
      isLoading = true;
    });

    try {
      await RememberMe.setEnabled(rememberMe); // จำค่าติ๊ก Remember me

      final response = await supabase.auth.signInWithPassword( // ล็อกอินด้วยอีเมล+รหัส
        email: emailController.text.trim(),

        password: passwordController.text.trim(),
      );

      if (response.user != null && mounted) { // ล็อกอินสำเร็จ
        Navigator.pushReplacement( // ไปหน้าหลัก แบบแทนที่หน้า Login (กดย้อนกลับไม่กลับมาหน้านี้)
          context,

          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      }
    } on AuthException catch (e) { // อีเมล/รหัสผิด ฯลฯ
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) { // error อื่น
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Login failed")));
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container( // พื้นหลังเต็มจอ
        width: double.infinity, // [UI] กว้างเต็มจอ

        height: double.infinity, // [UI] สูงเต็มจอ

        decoration: const BoxDecoration(
          gradient: LinearGradient( // [UI] พื้นหลังไล่สี
            colors: [Color(0xffD8EEFF), Colors.white], // [UI] ฟ้าอ่อน (บน) -> ขาว (ล่าง)

            begin: Alignment.topCenter,

            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: Center(
            child: SingleChildScrollView( // เลื่อนได้ กันคีย์บอร์ดบัง
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32), // [UI] ระยะ ซ้ายขวา 24 บนล่าง 32

              child: Form( // ฟอร์มที่ตรวจความถูกต้องได้
                key: _formKey,

                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_open, // [UI] ไอคอนแม่กุญแจเปิด

                      size: 80, // [UI] ขนาด

                      color: Color(0xff5189C9),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Welcome Back", // หัวข้อ

                      style: TextStyle(
                        fontSize: 28, // [UI] ขนาดหัวข้อ

                        fontWeight: FontWeight.bold,

                        color: Color(0xff5189C9),
                      ),
                    ),

                    const SizedBox(height: 40), // [UI] ระยะหัวข้อกับช่องกรอก
                    TextFormField( // ช่องอีเมล
                      controller: emailController,

                      keyboardType: TextInputType.emailAddress, // [UI] คีย์บอร์ดแบบอีเมล (มี @)

                      validator: (value) { // ตรวจรูปแบบอีเมล
                        if (value == null ||
                            !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) { // ต้องเป็น xxx@xxx.xxx
                          return "Enter valid email"; // ข้อความแดงใต้ช่อง
                        }

                        return null; // ผ่าน
                      },

                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.email, // [UI] ไอคอนซองจดหมาย

                          color: Color(0xff5189C9),
                        ),

                        labelText: "Email",

                        filled: true,

                        fillColor: Colors.white, // [UI] พื้นช่องขาว

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

                          borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
                        ),
                      ),
                    ),

                    const SizedBox(height: 16), // [UI] ระยะระหว่างช่อง

                    TextFormField( // ช่องรหัสผ่าน
                      controller: passwordController,

                      obscureText: obscurePassword, // ซ่อน/แสดงรหัส

                      validator: (value) {
                        if (value == null || value.isEmpty) { // ยังไม่กรอก
                          return "Enter password";
                        }

                        return null;
                      },

                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.lock, // [UI] ไอคอนแม่กุญแจ

                          color: Color(0xff5189C9),
                        ),

                        labelText: "Password",

                        suffixIcon: IconButton( // ปุ่มรูปตา สลับซ่อน/แสดง
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

                        filled: true,

                        fillColor: Colors.white,

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),

                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    CheckboxListTile( // ช่องติ๊ก Remember me
                      value: rememberMe,

                      onChanged: (value) {
                        setState(() {
                          rememberMe = value ?? false;
                        });
                      },

                      title: const Text(
                        "Remember me",

                        style: TextStyle(color: Color(0xff5189C9)), // [UI] สีข้อความ
                      ),

                      activeColor: const Color(0xff5189C9), // [UI] สีช่องติ๊กตอนติ๊กแล้ว

                      controlAffinity: ListTileControlAffinity.leading, // [UI] ช่องติ๊กอยู่ซ้ายของข้อความ

                      contentPadding: EdgeInsets.zero, // [UI] ไม่มีระยะขอบใน

                      dense: true, // [UI] แบบกระชับ (เตี้ยลง)
                    ),

                    const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity, // [UI] ปุ่มกว้างเต็ม

                      height: 55, // [UI] ความสูงปุ่ม

                      child: ElevatedButton(
                        onPressed: isLoading ? null : _login,

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
                                "Login",

                                style: TextStyle(
                                  fontSize: 18,

                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Forgot Password
                    TextButton(
                      onPressed: () {
                        Navigator.push( // ไปหน้าลืมรหัสผ่าน
                          context,

                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },

                      child: const Text(
                        "Forgot Password?",

                        style: TextStyle(
                          color: Color(0xff5189C9),

                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextButton(
                      onPressed: () {
                        Navigator.push( // ไปหน้าสมัครสมาชิก
                          context,

                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },

                      child: const Text(
                        "Don't have an account? Register",

                        style: TextStyle(color: Color(0xff5189C9)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
