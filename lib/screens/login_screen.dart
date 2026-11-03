import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'register.dart';
import 'main_menu_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();

  final passwordController = TextEditingController();

  bool obscurePassword = true;

  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();

    passwordController.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),

        password: passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        Navigator.pushReplacement(
          context,

          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
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
      body: Container(
        width: double.infinity,

        height: double.infinity,

        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffD8EEFF), Colors.white],

            begin: Alignment.topCenter,

            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),

              child: Form(
                key: _formKey,

                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_open,

                      size: 80,

                      color: Color(0xff5189C9),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      "Welcome Back",

                      style: TextStyle(
                        fontSize: 28,

                        fontWeight: FontWeight.bold,

                        color: Color(0xff5189C9),
                      ),
                    ),

                    const SizedBox(height: 40),
                    TextFormField(
                      controller: emailController,

                      keyboardType: TextInputType.emailAddress,

                      validator: (value) {
                        if (value == null ||
                            !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return "Enter valid email";
                        }

                        return null;
                      },

                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.email,

                          color: Color(0xff5189C9),
                        ),

                        labelText: "Email",

                        filled: true,

                        fillColor: Colors.white,

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),

                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: passwordController,

                      obscureText: obscurePassword,

                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Enter password";
                        }

                        return null;
                      },

                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.lock,

                          color: Color(0xff5189C9),
                        ),

                        labelText: "Password",

                        suffixIcon: IconButton(
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

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,

                      height: 55,

                      child: ElevatedButton(
                        onPressed: isLoading ? null : _login,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffffd84d),

                          foregroundColor: const Color(0xff5189C9),

                          elevation: 6,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
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
                        Navigator.push(
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
                        Navigator.push(
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
