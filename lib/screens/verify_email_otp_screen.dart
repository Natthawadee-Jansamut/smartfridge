import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerifyEmailOtpScreen extends StatefulWidget {
  final String email;

  const VerifyEmailOtpScreen({super.key, required this.email});

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final supabase = Supabase.instance.client;

  final otpController = TextEditingController();

  bool isLoading = false;

  bool isResending = false;

  @override
  void dispose() {
    otpController.dispose();

    super.dispose();
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("กรุณากรอกรหัส OTP 6 หลัก")));

      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await supabase.auth.verifyOTP(
        email: widget.email,

        token: otp,

        type: OtpType.email,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("ยืนยันอีเมลสำเร็จ ✅")));

      Navigator.popUntil(context, (route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ยืนยันไม่สำเร็จ กรุณาลองใหม่")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> resendOtp() async {
    setState(() {
      isResending = true;
    });

    try {
      await supabase.auth.resend(type: OtpType.signup, email: widget.email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ส่งรหัสใหม่แล้ว กรุณาเช็กอีเมล")),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          isResending = false;
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
          padding: const EdgeInsets.all(24),

          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,

                    size: 80,

                    color: Color(0xff5189C9),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "Verify your email",

                    style: TextStyle(
                      fontSize: 26,

                      fontWeight: FontWeight.bold,

                      color: Color(0xff5189C9),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "เราได้ส่งรหัส OTP 6 หลักไปที่\n${widget.email}",

                    textAlign: TextAlign.center,

                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),

                  const SizedBox(height: 30),

                  TextField(
                    controller: otpController,

                    keyboardType: TextInputType.number,

                    maxLength: 6,

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      fontSize: 28,

                      letterSpacing: 8,

                      fontWeight: FontWeight.bold,

                      color: Color(0xff5189C9),
                    ),

                    decoration: InputDecoration(
                      counterText: "",

                      hintText: "------",

                      filled: true,

                      fillColor: Colors.white,

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),

                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,

                    height: 55,

                    child: ElevatedButton(
                      onPressed: isLoading ? null : verifyOtp,

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
                              "Verify Email",

                              style: TextStyle(
                                fontSize: 18,

                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: isResending ? null : resendOtp,

                    child: Text(
                      isResending ? "Sending..." : "Resend OTP",

                      style: const TextStyle(color: Color(0xff5189C9)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
