import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final supabase = Supabase.instance.client;

  final firstNameController = TextEditingController();

  final lastNameController = TextEditingController();

  final phoneController = TextEditingController();

  bool loading = false;

  @override
  void initState() {
    super.initState();

    loadData();
  }

  void loadData() {
    final user = supabase.auth.currentUser;

    firstNameController.text = user?.userMetadata?['first_name'] ?? "";

    lastNameController.text = user?.userMetadata?['last_name'] ?? "";

    phoneController.text = user?.userMetadata?['phone'] ?? "";
  }

  Future<void> saveProfile() async {
    setState(() {
      loading = true;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            "first_name": firstNameController.text.trim(),

            "last_name": lastNameController.text.trim(),

            "phone": phoneController.text.trim(),
          },
        ),
      );

      await supabase.auth.refreshSession();

      await supabase.auth.getUser();

      // เพิ่มบรรทัดนี้
      await supabase.auth.refreshSession();
      if (mounted) {
        final user = await supabase.auth.getUser();

        Navigator.pop(context, user.user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 30),

                onPressed: () {
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  "แก้ไขข้อมูลส่วนตัว",

                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 35),

              buildField(
                "First Name",

                firstNameController,

                Icons.person_outline,
              ),

              const SizedBox(height: 18),

              buildField("Last Name", lastNameController, Icons.person_outline),

              const SizedBox(height: 18),

              buildField("Phone", phoneController, Icons.phone_outlined),

              const Spacer(),

              SizedBox(
                width: double.infinity,

                height: 55,

                child: ElevatedButton(
                  onPressed: loading ? null : saveProfile,

                  style: ElevatedButton.styleFrom(
                    // ปุ่มสีฟ้าทุกปุ่มในแอปต้องใช้รหัสสี #D7EDFF ตามที่กำหนด
                    backgroundColor: const Color(0xffD7EDFF),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.black87)
                      : const Text(
                          "บันทึก",

                          style: TextStyle(
                            fontSize: 18,

                            color: Colors.black87,

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

  Widget buildField(
    String label,

    TextEditingController controller,

    IconData icon,
  ) {
    return TextField(
      controller: controller,

      decoration: InputDecoration(
        labelText: label,

        prefixIcon: Icon(icon),

        filled: true,

        fillColor: Colors.white,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),

          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
