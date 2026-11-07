import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/services/notification_service.dart';
import 'package:test_app/services/reauth.dart';
import 'package:test_app/screens/auth/login_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final supabase = Supabase.instance.client;

  bool loading = false;

  Future<void> deleteAccount() async {
    setState(() {
      loading = true;
    });

    try {
      // เรียก Supabase Edge Function

      final response = await supabase.functions.invoke('delete-user');

      if (response.status != 200) {
        throw Exception("Delete account failed");
      }

      // Logout หลังลบสำเร็จ

      await supabase.auth.signOut();

      // ยกเลิกแจ้งเตือนวัตถุดิบที่ตั้งล่วงหน้าไว้ของบัญชีที่ลบไปแล้ว

      await NotificationService.notifications.cancelAll();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
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
    final passwordController = TextEditingController();
    String? error;
    bool hide = true;
    bool checking = false;
    const red = Color(0xffD93025);

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            final password = passwordController.text.trim();
            if (password.isEmpty) {
              setDialogState(() => error = "กรุณากรอกรหัสผ่านเพื่อยืนยัน");
              return;
            }
            setDialogState(() {
              checking = true;
              error = null;
            });
            try {
              final ok = await verifyCurrentPassword(password);
              if (!dialogContext.mounted) return;
              if (ok) {
                Navigator.pop(dialogContext, true);
                return;
              }
              setDialogState(() => error = "รหัสผ่านไม่ถูกต้อง");
            } catch (e) {
              if (!dialogContext.mounted) return;
              setDialogState(
                () => error = e is AuthException
                    ? e.message
                    : "ตรวจสอบรหัสผ่านไม่สำเร็จ กรุณาลองใหม่",
              );
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => checking = false);
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),

            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.red),

                SizedBox(width: 10),

                Text("ยืนยันการลบ"),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text(
                  "คุณต้องการลบบัญชีใช่หรือไม่?\n\n"
                  "ข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้\n\n"
                  "กรอกรหัสผ่านเพื่อยืนยัน",
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: passwordController,

                  obscureText: hide,

                  enabled: !checking,

                  onChanged: (_) {
                    if (error != null) setDialogState(() => error = null);
                  },

                  onSubmitted: (_) => submit(),

                  decoration: InputDecoration(
                    labelText: "รหัสผ่าน",

                    errorText: error,

                    errorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: red, width: 1.5),
                    ),

                    focusedErrorBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: red, width: 1.5),
                    ),

                    border: const OutlineInputBorder(),

                    suffixIcon: IconButton(
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
                    : () => Navigator.pop(dialogContext, false),

                child: const Text("ยกเลิก"),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

                onPressed: checking ? null : submit,

                child: checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
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

    if (confirmed == true && mounted) deleteAccount();
  }

  Widget consequenceRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Icon(Icons.cancel, size: 20, color: Colors.red),

        const SizedBox(width: 10),

        Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
      ],
    );
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
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 30),

                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 30),

              Center(
                child: Container(
                  width: 100,

                  height: 100,

                  decoration: const BoxDecoration(
                    color: Color(0xffffdddd),

                    shape: BoxShape.circle,
                  ),

                  child: const Icon(
                    Icons.delete_forever,

                    size: 60,

                    color: Colors.red,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              const Center(
                child: Text(
                  "ลบบัญชี",

                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 25),

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20),
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

              const Spacer(),

              SizedBox(
                width: double.infinity,

                height: 55,

                child: ElevatedButton(
                  onPressed: loading ? null : confirmDelete,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,

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
