import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("ไม่สามารถลบบัญชีได้ : $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  void confirmDelete() {
    showDialog(
      context: context,

      builder: (context) {
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

          content: const Text(
            "คุณต้องการลบบัญชีใช่หรือไม่?\n\n"
            "ข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้",
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },

              child: const Text("ยกเลิก"),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

              onPressed: () {
                Navigator.pop(context);

                deleteAccount();
              },

              child: const Text(
                "ลบบัญชี",

                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
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
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20),
                ),

                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      "เมื่อคุณลบบัญชี:",

                      style: TextStyle(
                        fontSize: 18,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 10),

                    Text("• ข้อมูลผู้ใช้จะถูกลบ"),

                    Text("• วัตถุดิบในตู้เย็นจะถูกลบ"),

                    Text("• สูตรอาหารจะไม่สามารถกู้คืนได้"),
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
