import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ
import 'package:supabase_flutter/supabase_flutter.dart'; // ระบบผู้ใช้ของ Supabase

// หน้าแก้ไขข้อมูลส่วนตัว (ชื่อ นามสกุล เบอร์โทร)
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final supabase = Supabase.instance.client; // ตัวเชื่อมต่อ Supabase

  final firstNameController = TextEditingController(); // ข้อความในช่องชื่อ

  final lastNameController = TextEditingController(); // ข้อความในช่องนามสกุล

  final phoneController = TextEditingController(); // ข้อความในช่องเบอร์โทร

  bool loading = false; // true = กำลังบันทึก

  @override
  void initState() { // ทำครั้งเดียวตอนเปิดหน้า
    super.initState();

    loadData(); // ดึงข้อมูลเดิมมาใส่ช่องกรอก
  }

  // ดึงข้อมูลผู้ใช้ปัจจุบันมาใส่ในช่องกรอก
  void loadData() {
    final user = supabase.auth.currentUser; // ผู้ใช้ที่ล็อกอินอยู่

    firstNameController.text = user?.userMetadata?['first_name'] ?? ""; // ชื่อ (ไม่มีก็ว่าง)

    lastNameController.text = user?.userMetadata?['last_name'] ?? ""; // นามสกุล

    phoneController.text = user?.userMetadata?['phone'] ?? ""; // เบอร์โทร
  }

  // กดบันทึก -> อัปเดตข้อมูลผู้ใช้บน Supabase
  Future<void> saveProfile() async {
    setState(() {
      loading = true; // เริ่มโหลด (ปุ่มหมุน)
    });

    try {
      await supabase.auth.updateUser( // อัปเดตข้อมูลผู้ใช้
        UserAttributes(
          data: { // ข้อมูลเพิ่มเติมของผู้ใช้ (metadata)
            "first_name": firstNameController.text.trim(),

            "last_name": lastNameController.text.trim(),

            "phone": phoneController.text.trim(),
          },
        ),
      );

      await supabase.auth.refreshSession(); // รีเฟรช session ให้ได้ข้อมูลใหม่

      await supabase.auth.getUser(); // ดึงข้อมูลผู้ใช้ล่าสุดจากเซิร์ฟเวอร์

      // เพิ่มบรรทัดนี้
      await supabase.auth.refreshSession();
      if (mounted) { // หน้ายังเปิดอยู่
        final user = await supabase.auth.getUser(); // ดึงข้อมูลผู้ใช้ใหม่อีกครั้ง

        Navigator.pop(context, user.user); // ปิดหน้านี้ แล้วส่งข้อมูลผู้ใช้ใหม่กลับไปหน้าโปรไฟล์
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString()))); // แสดง error
      }
    } finally {
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

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20), // [UI] ระยะจากขอบจอ 20

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดซ้าย

            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 30), // [UI] ลูกศรย้อนกลับ ขนาด 30

                onPressed: () {
                  Navigator.pop(context); // กลับโดยไม่บันทึก
                },
              ),

              const SizedBox(height: 20), // [UI] ระยะห่าง

              const Center(
                child: Text(
                  "แก้ไขข้อมูลส่วนตัว", // หัวข้อหน้า

                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold), // [UI] ขนาด 26 ตัวหนา
                ),
              ),

              const SizedBox(height: 35), // [UI] ระยะหัวข้อกับช่องแรก

              buildField(
                "First Name", // ป้ายช่อง

                firstNameController,

                Icons.person_outline, // [UI] ไอคอนคน
              ),

              const SizedBox(height: 18), // [UI] ระยะระหว่างช่องกรอก

              buildField("Last Name", lastNameController, Icons.person_outline),

              const SizedBox(height: 18),

              buildField("Phone", phoneController, Icons.phone_outlined), // [UI] ไอคอนโทรศัพท์

              const Spacer(), // ดันปุ่มบันทึกลงไปล่างสุดของจอ

              SizedBox(
                width: double.infinity, // [UI] ปุ่มกว้างเต็มจอ

                height: 55, // [UI] ความสูงปุ่ม

                child: ElevatedButton(
                  onPressed: loading ? null : saveProfile, // กำลังโหลด = กดไม่ได้

                  style: ElevatedButton.styleFrom(
                    // หน้านี้พื้นหลังเป็นฟ้า ถ้าใช้ปุ่มฟ้า #D7EDFF จะกลืนกับพื้น จึงใช้เหลืองอ่อนแทน
                    backgroundColor: const Color(0xFFFFF7D0), // [UI] สีปุ่ม

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20), // [UI] มุมปุ่มโค้ง 20
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.black87) // วงหมุนตอนบันทึก
                      : const Text(
                          "บันทึก",

                          style: TextStyle(
                            fontSize: 18, // [UI] ขนาดตัวอักษรปุ่ม

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

  // สร้างช่องกรอกข้อความ 1 ช่อง (ใช้ซ้ำกับ ชื่อ/นามสกุล/เบอร์)
  Widget buildField(
    String label, // ป้ายกำกับในช่อง

    TextEditingController controller, // ตัวเก็บข้อความ

    IconData icon, // ไอคอนหน้าช่อง
  ) {
    return TextField(
      controller: controller,

      decoration: InputDecoration(
        labelText: label,

        prefixIcon: Icon(icon), // [UI] ไอคอนด้านหน้าในช่อง

        filled: true, // [UI] เปิดใช้สีพื้นช่อง

        fillColor: Colors.white, // [UI] สีพื้นช่องสีขาว

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20), // [UI] มุมช่องโค้ง 20

          borderSide: BorderSide.none, // [UI] ไม่มีเส้นขอบ
        ),
      ),
    );
  }
}
