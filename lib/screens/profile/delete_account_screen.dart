import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบผู้ใช้ / เรียก Edge Function

import 'package:test_app/services/notification_service.dart'; // ยกเลิกแจ้งเตือนหลังลบบัญชี
import 'package:test_app/services/reauth.dart'; // ตรวจรหัสผ่านซ้ำก่อนลบ
import 'package:test_app/screens/auth/login_screen.dart'; // กลับหน้า Login หลังลบ

// หน้าลบบัญชีผู้ใช้
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false; // กำลังลบอยู่ไหม

  // ลบบัญชีจริง (เรียกหลังยืนยันรหัสผ่านแล้ว)
  Future<void> deleteAccount() async {
    setState(() {
      loading = true;
    });

    try {
      // เรียก Supabase Edge Function

      final response = await supabase.functions.invoke('delete-user'); // ฟังก์ชันฝั่งเซิร์ฟเวอร์ที่ลบผู้ใช้และข้อมูลทั้งหมด

      if (response.status != 200) { // 200 = สำเร็จ, อย่างอื่น = ล้มเหลว
        throw Exception("Delete account failed");
      }

      // Logout หลังลบสำเร็จ

      await supabase.auth.signOut();

      // ยกเลิกแจ้งเตือนวัตถุดิบที่ตั้งล่วงหน้าไว้ของบัญชีที่ลบไปแล้ว

      await NotificationService.notifications.cancelAll();

      if (mounted) {
        Navigator.pushAndRemoveUntil( // ไปหน้า Login ล้างหน้าเก่าทั้งหมด
          context,

          MaterialPageRoute(builder: (context) => const LoginScreen()),

          (route) => false,
        );
      }
    } catch (e) {
      debugPrint("ลบบัญชีไม่สำเร็จ: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ไม่สามารถลบบัญชีได้ กรุณาลองใหม่อีกครั้ง"),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  /// ยืนยันการลบด้วยรหัสผ่านปัจจุบัน (กันคนหยิบโทรศัพท์ที่ล็อกอินค้างไว้ลบบัญชี)
  /// รหัสผ่านถูก -> ปิดหน้าต่างแล้วลบบัญชี, ผิด -> เตือนสีแดงใต้ช่อง
  Future<void> confirmDelete() async {
    final passwordController = TextEditingController(); // ช่องรหัสในป๊อปอัป
    String? error; // ข้อความ error ใต้ช่อง (null = ไม่มี)
    bool hide = true; // ซ่อนรหัสไหม
    bool checking = false; // กำลังตรวจรหัสอยู่ไหม
    const red = Color(0xffD93025); // [UI] สีแดงของเส้นขอบตอน error

    final confirmed = await showDialog<bool>( // เปิดป๊อปอัป รอผล true/false
      context: context,

      // StatefulBuilder = ทำให้ป๊อปอัปวาดใหม่เองได้ (เช่นตอนแสดง error / สลับซ่อนรหัส)
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // กดยืนยันในป๊อปอัป -> ตรวจรหัส
          Future<void> submit() async {
            final password = passwordController.text.trim();
            if (password.isEmpty) { // ยังไม่กรอก
              setDialogState(() => error = "กรุณากรอกรหัสผ่านเพื่อยืนยัน");
              return;
            }
            setDialogState(() {
              checking = true; // เริ่มตรวจ
              error = null;
            });
            try {
              final ok = await verifyCurrentPassword(password); // ตรวจรหัสกับเซิร์ฟเวอร์
              if (!dialogContext.mounted) return;
              if (ok) {
                Navigator.pop(dialogContext, true); // รหัสถูก ปิดป๊อปอัปพร้อมส่ง true
                return;
              }
              setDialogState(() => error = "รหัสผ่านไม่ถูกต้อง"); // รหัสผิด
            } catch (e) {
              if (!dialogContext.mounted) return;
              setDialogState(
                () => error = e is AuthException
                    ? e.message
                    : "ตรวจสอบรหัสผ่านไม่สำเร็จ กรุณาลองใหม่",
              );
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => checking = false); // ตรวจเสร็จ
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20), // [UI] มุมป๊อปอัปโค้ง
            ),

            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red), // [UI] ไอคอนเตือนสีแดง

                SizedBox(width: 10),

                Text("ยืนยันการลบ"),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min, // [UI] สูงเท่าเนื้อหา

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text(
                  "คุณต้องการลบบัญชีใช่หรือไม่?\n\n"
                  "ข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้\n\n"
                  "กรอกรหัสผ่านเพื่อยืนยัน",
                ),

                const SizedBox(height: 12),

                TextField( // ช่องกรอกรหัส
                  controller: passwordController,

                  obscureText: hide,

                  enabled: !checking, // ระหว่างตรวจ ห้ามแก้

                  onChanged: (_) {
                    if (error != null) setDialogState(() => error = null); // เริ่มพิมพ์ใหม่ ลบข้อความ error
                  },

                  onSubmitted: (_) => submit(), // กด Enter บนคีย์บอร์ด = ยืนยัน

                  decoration: InputDecoration(
                    labelText: "รหัสผ่าน",

                    errorText: error, // ข้อความแดงใต้ช่อง

                    errorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: red, width: 1.5), // [UI] ขอบแดงหนา 1.5 ตอน error
                    ),

                    focusedErrorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: red, width: 1.5), // [UI] ขอบแดงตอน error และกำลังพิมพ์
                    ),

                    border: const OutlineInputBorder(), // [UI] กรอบปกติ

                    suffixIcon: IconButton( // ปุ่มรูปตา
                      icon: Icon(
                        hide ? Icons.visibility : Icons.visibility_off,
                      ),

                      onPressed: () => setDialogState(() => hide = !hide),
                    ),
                  ),
                ),
              ],
            ),

            actions: [
              TextButton(
                onPressed: checking
                    ? null
                    : () => Navigator.pop(dialogContext, false), // ยกเลิก

                child: const Text("ยกเลิก"),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red), // [UI] ปุ่มสีแดง

                onPressed: checking ? null : submit,

                child: checking
                    ? const SizedBox( // กำลังตรวจ -> วงหมุนเล็ก
                        width: 18, // [UI] ขนาดวงหมุน
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, // [UI] ความหนาเส้นวงหมุน
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "ลบบัญชี",

                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );

    // ไม่ dispose ทันที: หน้าต่างยังใช้ controller ระหว่างแอนิเมชันปิด
    // (dispose ตอนนั้นจะ error "used after being disposed")
    Future.delayed(const Duration(seconds: 1), passwordController.dispose);

    if (confirmed == true && mounted) deleteAccount(); // ยืนยันแล้ว -> ลบจริง
  }

  // แถวบอกผลของการลบ 1 ข้อ (ไอคอน X แดง + ข้อความ)
  Widget consequenceRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Icon(Icons.cancel, size: 20, color: Colors.red), // [UI] ไอคอน X แดง ขนาด 20

        const SizedBox(width: 10),

        Expanded(child: Text(text, style: const TextStyle(fontSize: 15))), // [UI] ขนาดข้อความ 15
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffD8EEFF), // [UI] สีพื้นหลัง

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 30), // [UI] ปุ่มย้อนกลับ

                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 30),

              Center(
                child: Container( // วงกลมแดงอ่อนรองไอคอนถังขยะ
                  width: 100, // [UI] ขนาดวงกลม

                  height: 100,

                  decoration: const BoxDecoration(
                    color: Color(0xffffdddd), // [UI] สีชมพูอ่อน

                    shape: BoxShape.circle,
                  ),

                  child: const Icon(
                    Icons.delete_forever, // [UI] ไอคอนถังขยะ

                    size: 60,

                    color: Colors.red,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              const Center(
                child: Text(
                  "ลบบัญชี",

                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold), // [UI] หัวข้อขนาด 30
                ),
              ),

              const SizedBox(height: 25),

              Container( // กล่องขาวอธิบายผลของการลบ
                width: double.infinity,

                padding: const EdgeInsets.all(20), // [UI] ระยะในกล่อง

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20), // [UI] มุมโค้ง
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      "เมื่อคุณลบบัญชี:",

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 14),

                    consequenceRow("ข้อมูลผู้ใช้จะถูกลบ"),

                    const SizedBox(height: 10),

                    consequenceRow("วัตถุดิบในตู้เย็นจะถูกลบ"),

                    const SizedBox(height: 10),

                    consequenceRow("สูตรอาหารจะไม่สามารถกู้คืนได้"),
                  ],
                ),
              ),

              const Spacer(), // ดันปุ่มลงล่างสุด

              SizedBox(
                width: double.infinity,

                height: 55, // [UI] ความสูงปุ่ม

                child: ElevatedButton(
                  onPressed: loading ? null : confirmDelete, // กด -> เปิดป๊อปอัปยืนยันรหัส

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // [UI] ปุ่มสีแดง (สื่อว่าอันตราย)

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "ยืนยันลบบัญชี",

                          style: TextStyle(
                            color: Colors.white,

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
