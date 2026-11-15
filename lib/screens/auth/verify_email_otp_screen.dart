import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบล็อกอิน/ยืนยัน OTP

// หน้ากรอกรหัส OTP 6 หลักที่ส่งไปทางอีเมล เพื่อยืนยันอีเมลหลังสมัครสมาชิก
class VerifyEmailOtpScreen extends StatefulWidget {
  final String email; // อีเมลที่สมัครไว้ (รับมาจากหน้าสมัคร)

  const VerifyEmailOtpScreen({super.key, required this.email});

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final supabase = Supabase.instance.client;

  final otpController = TextEditingController(); // ข้อความในช่องกรอก OTP

  bool isLoading = false; // กำลังยืนยัน OTP อยู่ไหม

  bool isResending = false; // กำลังขอรหัสใหม่อยู่ไหม

  @override
  void dispose() { // ตอนปิดหน้า
    otpController.dispose(); // คืนหน่วยความจำ

    super.dispose();
  }

  // กดปุ่มยืนยัน -> ส่ง OTP ไปตรวจกับ Supabase
  Future<void> verifyOtp() async {
    final otp = otpController.text.trim(); // รหัสที่กรอก

    if (otp.length != 6) { // ไม่ครบ 6 หลัก
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("กรุณากรอกรหัส OTP 6 หลัก")));

      return; // หยุด ไม่ส่งไปตรวจ
    }

    setState(() {
      isLoading = true; // เริ่มโหลด
    });

    try {
      await supabase.auth.verifyOTP( // ส่งรหัสไปตรวจ
        email: widget.email,

        token: otp,

        type: OtpType.email, // ชนิดรหัส = OTP ทางอีเมล
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("ยืนยันอีเมลสำเร็จ ✅")));

      Navigator.popUntil(context, (route) => route.isFirst); // ย้อนกลับจนถึงหน้าแรกสุด (หน้า Login)
    } on AuthException catch (e) { // error จากระบบล็อกอิน (เช่น รหัสผิด/หมดอายุ)
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message))); // แสดงข้อความจาก Supabase
    } catch (e) { // error อื่น
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ยืนยันไม่สำเร็จ กรุณาลองใหม่")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false; // หยุดโหลด
        });
      }
    }
  }

  // กด "Resend OTP" -> ขอให้ส่งรหัสใหม่ไปที่อีเมล
  Future<void> resendOtp() async {
    setState(() {
      isResending = true;
    });

    try {
      await supabase.auth.resend(type: OtpType.signup, email: widget.email); // ส่งรหัสสมัครสมาชิกใหม่

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
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง (ฟ้าอ่อน)

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24), // [UI] ระยะจากขอบจอ 24

          child: Center( // จัดเนื้อหาไว้กลางจอ
            child: SingleChildScrollView( // เลื่อนได้ (กันคีย์บอร์ดบังแล้วล้นจอ)
              child: Column(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined, // [UI] ไอคอนซองจดหมาย

                    size: 80, // [UI] ขนาดไอคอน

                    color: Color(0xff5189C9), // [UI] สีฟ้า
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "Verify your email", // หัวข้อ

                    style: TextStyle(
                      fontSize: 26, // [UI] ขนาดหัวข้อ

                      fontWeight: FontWeight.bold,

                      color: Color(0xff5189C9),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    "เราได้ส่งรหัส OTP 6 หลักไปที่\n${widget.email}", // บอกว่าส่งไปที่อีเมลไหน

                    textAlign: TextAlign.center, // [UI] จัดกึ่งกลาง

                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),

                  const SizedBox(height: 30),

                  TextField( // ช่องกรอก OTP
                    controller: otpController,

                    keyboardType: TextInputType.number, // [UI] เปิดแป้นตัวเลข

                    maxLength: 6, // กรอกได้สูงสุด 6 ตัว

                    textAlign: TextAlign.center, // [UI] ตัวเลขอยู่กลางช่อง

                    style: const TextStyle(
                      fontSize: 28, // [UI] ขนาดตัวเลข OTP

                      letterSpacing: 8, // [UI] ระยะห่างระหว่างตัวเลข (ให้อ่านง่าย)

                      fontWeight: FontWeight.bold,

                      color: Color(0xff5189C9),
                    ),

                    decoration: InputDecoration(
                      counterText: "", // [UI] ซ่อนตัวนับ "0/6" ใต้ช่อง

                      hintText: "------", // [UI] ขีดจางๆ ตอนช่องว่าง

                      filled: true,

                      fillColor: Colors.white, // [UI] พื้นช่องขาว

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง

                        borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity, // [UI] ปุ่มกว้างเต็ม

                    height: 55, // [UI] ความสูงปุ่ม

                    child: ElevatedButton(
                      onPressed: isLoading ? null : verifyOtp, // กำลังโหลด = กดไม่ได้

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xffffd84d), // [UI] สีปุ่มเหลือง

                        foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษรฟ้า

                        elevation: 6, // [UI] เงาปุ่ม

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25), // [UI] มุมปุ่มโค้ง
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

                  TextButton( // ปุ่มข้อความ "ส่งรหัสใหม่"
                    onPressed: isResending ? null : resendOtp,

                    child: Text(
                      isResending ? "Sending..." : "Resend OTP", // ระหว่างส่งเปลี่ยนข้อความ

                      style: const TextStyle(color: Color(0xff5189C9)), // [UI] สีฟ้า
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
