import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/screens/verify_email_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final supabase = Supabase.instance.client;

  final firstNameController = TextEditingController();

  final lastNameController = TextEditingController();

  final emailController = TextEditingController();

  final passwordController = TextEditingController();

  final confirmPasswordController = TextEditingController();

  final phoneController = TextEditingController();

  bool obscurePassword = true;

  bool obscureConfirm = true;

  bool isLoading = false;

  bool get _hasMinLength => passwordController.text.length >= 8;

  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text);

  bool get _hasLowercase => RegExp(r'[a-z]').hasMatch(passwordController.text);

  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text);

  bool get _hasSpecialChar =>
      RegExp(r'[!@#$%^&*]').hasMatch(passwordController.text);

  @override
  void dispose() {
    firstNameController.dispose();

    lastNameController.dispose();

    emailController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    phoneController.dispose();

    super.dispose();
  }

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

    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),

        password: passwordController.text.trim(),

        emailRedirectTo: 'smartfridge://login-callback/',

        data: {
          'first_name': firstNameController.text.trim(),

          'last_name': lastNameController.text.trim(),

          'phone': phoneController.text.trim(),
        },
      );

      if (!mounted) return;

      if (response.user != null) {
        Navigator.push(
          context,

          MaterialPageRoute(
            builder: (_) =>
                VerifyEmailOtpScreen(email: emailController.text.trim()),
          ),
        );
      }
    } on AuthException catch (e) {
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

  Widget buildPasswordRequirement(String text, bool isPassed) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),

      child: Row(
        children: [
          Icon(
            isPassed ? Icons.check_circle : Icons.radio_button_unchecked,

            size: 16,

            color: isPassed ? const Color(0xff5189C9) : Colors.grey,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              text,

              style: TextStyle(
                fontSize: 12,

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),

                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,

                      vertical: 32,
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_add,

                            size: 70,

                            color: Color(0xff5189C9),
                          ),

                          const SizedBox(height: 16),

                          const Text(
                            "Create Account",

                            style: TextStyle(
                              fontSize: 26,

                              fontWeight: FontWeight.bold,

                              color: Color(0xff5189C9),
                            ),
                          ),

                          const SizedBox(height: 30),

                          Row(
                            children: [
                              Expanded(
                                child: buildTextField(
                                  controller: firstNameController,

                                  label: "First Name",

                                  icon: Icons.person_outline,

                                  validator: (value) {
                                    return value!.isEmpty ? "Required" : null;
                                  },
                                ),
                              ),

                              const SizedBox(width: 12),

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

                          const SizedBox(height: 16),

                          buildTextField(
                            controller: emailController,

                            label: "Email",

                            icon: Icons.email_outlined,

                            keyboardType: TextInputType.emailAddress,

                            validator: (value) {
                              if (value == null ||
                                  !RegExp(
                                    r'^[^@]+@[^@]+\.[^@]+',
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
                              setState(() {});
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

                            validator: validatePassword,
                          ),

                          buildPasswordRequirements(),

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
                              if (value != passwordController.text) {
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

                            keyboardType: TextInputType.phone,
                          ),

                          const SizedBox(height: 30),

                          SizedBox(
                            width: double.infinity,

                            height: 55,

                            child: ElevatedButton(
                              onPressed: isLoading ? null : _register,

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
                              Navigator.pop(context);
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

  Widget buildTextField({
    required TextEditingController controller,

    required String label,

    required IconData icon,

    TextInputType keyboardType = TextInputType.text,

    bool obscureText = false,

    Widget? suffix,

    String? Function(String?)? validator,

    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,

      keyboardType: keyboardType,

      obscureText: obscureText,

      validator: validator,

      onChanged: onChanged,

      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xff5189C9)),

        suffixIcon: suffix,

        labelText: label,

        filled: true,

        fillColor: Colors.white,

        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,

          horizontal: 20,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
