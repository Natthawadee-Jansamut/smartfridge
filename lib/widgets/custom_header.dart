import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอของ Flutter

// แถบหัวสีฟ้าด้านบนของหน้า (มีชื่อหน้า + คำอธิบายใต้ชื่อ + ปุ่มย้อนกลับถ้าต้องการ)
class CustomHeader extends StatelessWidget {
  final String title; // ข้อความหัวเรื่องตัวใหญ่
  final String subtitle; // ข้อความเล็กใต้หัวเรื่อง
  final bool showBack; // true = แสดงปุ่มลูกศรย้อนกลับ

  const CustomHeader({
    super.key,
    required this.title, // ต้องส่งหัวเรื่องมาเสมอ
    required this.subtitle, // ต้องส่งคำอธิบายมาเสมอ
    this.showBack = false, // ถ้าไม่ส่งมา จะไม่มีปุ่มย้อนกลับ
  });

  @override
  Widget build(BuildContext context) {
    return Container( // กล่องพื้นหลังของแถบหัว
      width: double.infinity, // [UI] กว้างเต็มจอ
      padding: EdgeInsets.only( // [UI] ระยะห่างด้านในกล่อง (ยิ่งมากเนื้อหายิ่งห่างจากขอบ)
        top: MediaQuery.of(context).padding.top + 10, // [UI] บน = ความสูงแถบสถานะ (นาฬิกา/แบต) + 10 กันโดนบัง
        left: 20, // [UI] ซ้าย 20
        right: 20, // [UI] ขวา 20
        bottom: 25, // [UI] ล่าง 25 (ความสูงส่วนล่างของแถบ)
      ),
      decoration: const BoxDecoration( // การตกแต่งกล่อง
        gradient: LinearGradient( // [UI] สีไล่เฉด
          begin: Alignment.topCenter, // [UI] เริ่มไล่จากด้านบน
          end: Alignment.bottomCenter, // [UI] ไปจบด้านล่าง
          colors: [const Color(0xff5189C9), Color.fromARGB(255, 37, 113, 237)], // [UI] สีบน (ฟ้าอมเทา) -> สีล่าง (ฟ้าสด) เปลี่ยนเลขสีเพื่อเปลี่ยนธีมแถบหัว
        ),
        borderRadius: BorderRadius.only( // [UI] ความโค้งของมุม
          bottomLeft: Radius.circular(30), // [UI] มุมล่างซ้ายโค้ง 30 (0 = เหลี่ยม)
          bottomRight: Radius.circular(30), // [UI] มุมล่างขวาโค้ง 30
        ),
      ),
      child: Column( // จัดของในแถบหัวเรียงจากบนลงล่าง
        crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดซ้าย
        children: [
          if (showBack) // ถ้าต้องการปุ่มย้อนกลับ
            InkWell( // ทำให้กดได้
              onTap: () {
                if (Navigator.canPop(context)) { // มีหน้าก่อนหน้าให้ย้อนไหม
                  Navigator.pop(context); // ย้อนกลับหน้าเดิม
                }
              },
              child: const Icon(Icons.arrow_back, color: Colors.white), // [UI] ไอคอนลูกศรสีขาว
            )
          else
            const SizedBox(height: 24), // [UI] ไม่มีปุ่ม ก็เว้นที่ว่างสูง 24 ให้ความสูงเท่าเดิม

          const SizedBox(height: 15), // [UI] ระยะห่างระหว่างปุ่มย้อนกลับกับหัวเรื่อง
          Text(
            title, // หัวเรื่อง
            style: const TextStyle(
              color: Colors.white, // [UI] สีตัวอักษรขาว
              fontSize: 24, // [UI] ขนาดตัวอักษรหัวเรื่อง
              fontWeight: FontWeight.bold, // [UI] ตัวหนา
            ),
          ),
          const SizedBox(height: 5), // [UI] ระยะห่างระหว่างหัวเรื่องกับคำอธิบาย
          Text(
            subtitle, // คำอธิบาย
            style: const TextStyle(color: Colors.white70, fontSize: 14), // [UI] ขาวจาง 70% ขนาด 14
          ),
        ],
      ),
    );
  }
}
