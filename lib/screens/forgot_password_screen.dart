import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();

  bool loading = false;

  Future<void> sendResetEmail() async {
    if (emailController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      await supabase.auth.resetPasswordForEmail(
        emailController.text.trim(),

        redirectTo: 'smartfridge://reset-password/',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ส่งลิงก์รีเซ็ตรหัสผ่านไปที่ Email แล้ว"),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
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
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // Back Button เหมือนหน้า Profile
              Align(
                alignment: Alignment.topLeft,

                child: CircleAvatar(
                  radius: 25,

                  backgroundColor: const Color(0xfffff38a),

                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back,

                      color: Color(0xff5189C9),
                    ),

                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 50),

              Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_reset,

                      size: 80,

                      color: Color(0xff5189C9),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "Forgot Password",

                      style: TextStyle(
                        fontSize: 30,

                        fontWeight: FontWeight.bold,

                        color: Color(0xff5189C9),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20),

                  border: Border.all(color: const Color(0xff5189C9)),
                ),

                child: TextField(
                  controller: emailController,

                  decoration: const InputDecoration(
                    labelText: "Email",

                    prefixIcon: Icon(Icons.email, color: Color(0xff5189C9)),

                    border: InputBorder.none,

                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,

                      vertical: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,

                height: 60,

                child: ElevatedButton(
                  onPressed: loading ? null : sendResetEmail,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffffd84d),

                    foregroundColor: const Color(0xff5189C9),

                    elevation: 4,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(
                          color: Color(0xff5189C9),
                        )
                      : const Text(
                          "Send Reset Link",

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
