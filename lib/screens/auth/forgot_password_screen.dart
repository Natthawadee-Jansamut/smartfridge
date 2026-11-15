import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบล็อกอิน/ส่งอีเมลรีเซ็ตรหัส

// หน้า "ลืมรหัสผ่าน": กรอกอีเมล แล้วระบบส่งลิงก์รีเซ็ตรหัสไปให้
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final supabase = Supabase.instance.client; // ตัวเชื่อมต่อ Supabase

  final emailController = TextEditingController(); // ตัวเก็บข้อความในช่องอีเมล

  bool loading = false; // true = กำลังส่งอยู่ (ปุ่มจะหมุนและกดไม่ได้)

  // กดปุ่มส่ง -> ขอให้ Supabase ส่งอีเมลรีเซ็ตรหัส
  Future<void> sendResetEmail() async {
    if (emailController.text.trim().isEmpty) { // ยังไม่กรอกอีเมล
      return; // ไม่ทำอะไร
    }

    setState(() { // สั่งให้หน้าจอวาดใหม่
      loading = true; // เริ่มโหลด
    });

    try {
      await supabase.auth.resetPasswordForEmail( // สั่งส่งอีเมลรีเซ็ตรหัส
        emailController.text.trim(), // อีเมลที่กรอก

        redirectTo: 'smartfridge://reset-password/', // กดลิงก์ในอีเมลแล้วให้เด้งกลับเข้าแอปที่หน้านี้
      );

      if (mounted) { // หน้ายังเปิดอยู่
        ScaffoldMessenger.of(context).showSnackBar( // แถบข้อความด้านล่างจอ
          const SnackBar(
            content: Text("ส่งลิงก์รีเซ็ตรหัสผ่านไปที่ Email แล้ว"),
          ),
        );
      }
    } catch (e) { // ส่งไม่สำเร็จ
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString()))); // แสดง error
    } finally { // ไม่ว่าสำเร็จหรือไม่ ทำเสมอ
      if (mounted) {
        setState(() {
          loading = false; // หยุดโหลด
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold( // โครงหน้าจอ
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง (ฟ้าอ่อน)

      body: SafeArea( // กันเนื้อหาทับแถบสถานะ
        child: Padding(
          padding: const EdgeInsets.all(20), // [UI] ระยะห่างจากขอบจอทุกด้าน 20

          child: Column( // เรียงจากบนลงล่าง
            crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดซ้าย

            children: [
              // Back Button เหมือนหน้า Profile
              Align(
                alignment: Alignment.topLeft, // [UI] วางมุมซ้ายบน

                child: CircleAvatar( // วงกลมรองปุ่ม
                  radius: 25, // [UI] รัศมีวงกลม 25 (เส้นผ่านศูนย์กลาง 50)

                  backgroundColor: const Color(0xfffff38a), // [UI] สีวงกลม (เหลือง)

                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back, // [UI] ไอคอนลูกศรย้อนกลับ

                      color: Color(0xff5189C9), // [UI] สีลูกศร (ฟ้า)
                    ),

                    onPressed: () {
                      Navigator.pop(context); // กลับหน้าก่อนหน้า
                    },
                  ),
                ),
              ),

              const SizedBox(height: 50), // [UI] ระยะห่างจากปุ่มย้อนกลับถึงไอคอนใหญ่

              Center( // จัดกึ่งกลางแนวนอน
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_reset, // [UI] ไอคอนแม่กุญแจรีเซ็ต

                      size: 80, // [UI] ขนาดไอคอน

                      color: Color(0xff5189C9), // [UI] สีไอคอน
                    ),

                    const SizedBox(height: 20), // [UI] ระยะไอคอนกับหัวข้อ

                    const Text(
                      "Forgot Password", // หัวข้อหน้า

                      style: TextStyle(
                        fontSize: 30, // [UI] ขนาดหัวข้อ

                        fontWeight: FontWeight.bold,

                        color: Color(0xff5189C9), // [UI] สีหัวข้อ
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40), // [UI] ระยะหัวข้อกับช่องกรอก

              Container( // กรอบช่องกรอกอีเมล
                decoration: BoxDecoration(
                  color: Colors.white, // [UI] พื้นช่องสีขาว

                  borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง 20

                  border: Border.all(color: const Color(0xff5189C9)), // [UI] เส้นขอบสีฟ้า
                ),

                child: TextField( // ช่องกรอกอีเมล
                  controller: emailController,

                  decoration: const InputDecoration(
                    labelText: "Email", // ป้ายในช่อง

                    prefixIcon: Icon(Icons.email, color: Color(0xff5189C9)), // [UI] ไอคอนซองจดหมายด้านหน้า

                    border: InputBorder.none, // [UI] ไม่ใช้เส้นขอบของช่องเอง (ใช้ของกรอบด้านนอกแทน)

                    contentPadding: EdgeInsets.symmetric( // [UI] ระยะในช่อง
                      horizontal: 20, // ซ้าย-ขวา 20

                      vertical: 18, // บน-ล่าง 18 (ยิ่งมาก ช่องยิ่งสูง)
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30), // [UI] ระยะช่องกรอกกับปุ่ม

              SizedBox( // กำหนดขนาดปุ่ม
                width: double.infinity, // [UI] ปุ่มกว้างเต็มจอ

                height: 60, // [UI] ความสูงปุ่ม

                child: ElevatedButton(
                  onPressed: loading ? null : sendResetEmail, // กำลังโหลด = null (ปุ่มกดไม่ได้)

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xffffd84d), // [UI] สีพื้นปุ่ม (เหลือง)

                    foregroundColor: const Color(0xff5189C9), // [UI] สีตัวอักษร/ไอคอนในปุ่ม (ฟ้า)

                    elevation: 4, // [UI] ความลอยของปุ่ม (เงา) 0 = แบน

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25), // [UI] มุมปุ่มโค้ง 25
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator( // กำลังโหลด = แสดงวงหมุน
                          color: Color(0xff5189C9), // [UI] สีวงหมุน
                        )
                      : const Text(
                          "Send Reset Link", // ข้อความบนปุ่ม

                          style: TextStyle(
                            fontSize: 18, // [UI] ขนาดตัวอักษรปุ่ม

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
