import 'package:flutter/material.dart'; // ชุดเครื่องมือสร้างหน้าจอ

import 'package:test_app/screens/ingredient_scan/image_scanning_screen.dart'; // หน้าถ่ายภาพวัตถุดิบ
import 'package:test_app/screens/recipe_scan/saved_recipes_screen.dart'; // หน้าคลังสูตรที่สแกนไว้
import 'package:test_app/widgets/app_bottom_nav.dart'; // แถบเมนูล่าง
import 'package:test_app/widgets/app_icons.dart'; // ไอคอนที่วาดเอง

/// หน้าเลือกว่าจะ "สแกน" อะไร (ตามดีไซน์ใน Figma: เฟรม "SCAN" ตัวบนสุด)
/// เข้าถึงได้จากแท็บ "สแกน" ที่แถบเมนูด้านล่าง
/// - ถ่ายภาพวัตถุดิบ  -> ไปหน้าสแกนวัตถุดิบเข้าตู้เย็น (ImageScanning)
/// - สแกนสูตรอาหาร   -> ไปหน้าคลังสูตรอาหารที่สแกนไว้ (SavedRecipesScreen)
///
/// หมายเหตุ: ทางลัดจากหน้าหลัก (เมนูตะแกรง) ยังคงพาเข้า ImageScanning ตรงๆ
/// เหมือนเดิม ไม่ต้องผ่านหน้าเลือกนี้
class ScanMenuScreen extends StatelessWidget {
  const ScanMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold( // โครงหน้าจอ
      backgroundColor: const Color(0xFFD8EEFF), // [UI] สีพื้นหลังหน้า (ฟ้าอ่อน)
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan), // แถบเมนูล่าง ไฮไลต์แท็บ "สแกน"
      body: SafeArea( // กันเนื้อหาทับแถบสถานะ
        child: Column(
          children: [
            // แถบบนสุด: ป้ายกำกับ "สแกน" ทรงแคปซูลสีเหลือง + ปุ่มตัวกรองวงกลม (ตามดีไซน์)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 20), // [UI] ระยะ ซ้าย 20 บน 15 ขวา 20 ล่าง 20
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 54, // [UI] ความสูงแคปซูล
                      padding: const EdgeInsets.symmetric(horizontal: 20), // [UI] ระยะในซ้าย-ขวา
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0), // [UI] สีแคปซูล (ครีมเหลือง)
                        borderRadius: BorderRadius.circular(27), // [UI] โค้ง = ครึ่งความสูง -> ทรงแคปซูล
                      ),
                      child: const Row(
                        children: [
                          ScannerIcon(size: 20), // [UI] ไอคอนสแกน ขนาด 20
                          SizedBox(width: 15), // [UI] ระยะไอคอนกับข้อความ
                          Text(
                            "สแกน",
                            style: TextStyle(
                              fontWeight: FontWeight.w600, // [UI] กึ่งหนา
                              fontSize: 16, // [UI] ขนาดตัวอักษร
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded( // พื้นที่ที่เหลือ
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0), // [UI] ระยะซ้าย-ขวาของการ์ด
                child: Column(
                  children: [
                    // การ์ดที่ 1: ถ่ายภาพวัตถุดิบ
                    _ScanOptionCard(
                      // ตรงกับไอคอน "hugeicons:meal-scan" ใน Figma แบบเป๊ะๆ
                      // (ใช้เส้นพาธ SVG จริงจากไฟล์ Figma ไม่ใช่ไอคอนประมาณ)
                      iconWidget: const MealScanIcon(size: 64), // [UI] ไอคอนขนาด 64
                      title: "ถ่ายภาพวัตถุดิบ",
                      subtitle:
                          "นำวัตถุดิบเข้าตู้เย็น โดยการถ่ายภาพ\nหรือเลือกรูปจากคลัง", // \n = ขึ้นบรรทัดใหม่
                      onTap: () => Navigator.push( // กดแล้วเปิดหน้าถ่ายภาพวัตถุดิบ
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ImageScanning(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20), // [UI] ระยะห่างระหว่างการ์ด
                    // การ์ดที่ 2: สแกนสูตรอาหาร
                    _ScanOptionCard(
                      // ตรงกับไอคอน "material-symbols-light:document-scanner-outline" ใน Figma
                      // (ใช้เส้นพาธ SVG จริงจากไฟล์ Figma ไม่ใช่ไอคอนประมาณ)
                      iconWidget: const SizedBox( // กล่อง 64x64 ให้ขนาดเท่าไอคอนการ์ดแรก
                        width: 64,
                        height: 64,
                        child: DocumentScannerRawIcon(size: 60), // [UI] ไอคอนจริงขนาด 60
                      ),
                      title: "สแกนสูตรอาหาร",
                      subtitle:
                          "นำเข้าสูตรอาหารโดยการถ่ายภาพ\nหรือเลือกรูปจากคลัง",
                      onTap: () => Navigator.push( // กดแล้วเปิดหน้าคลังสูตร
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedRecipesScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// การ์ดตัวเลือกการสแกน 1 ใบ (ไอคอน + หัวข้อ + คำอธิบาย)
class _ScanOptionCard extends StatelessWidget {
  final Widget iconWidget; // ไอคอนด้านซ้าย
  final String title; // หัวข้อ
  final String subtitle; // คำอธิบาย
  final VoidCallback onTap; // ทำอะไรเมื่อกด

  const _ScanOptionCard({
    required this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white, // [UI] พื้นการ์ดสีขาว
      borderRadius: BorderRadius.circular(24), // [UI] มุมการ์ดโค้ง 24
      child: InkWell( // ทำให้กดได้
        borderRadius: BorderRadius.circular(24), // [UI] เอฟเฟกต์กดโค้งตามการ์ด
        splashColor: Colors.blue.withOpacity(0.15), // [UI] สีคลื่นตอนกด (ฟ้าจาง 15%)
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22), // [UI] ระยะในการ์ดทุกด้าน 22
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, // [UI] ชิดด้านบน
            children: [
              iconWidget,
              const SizedBox(width: 16), // [UI] ระยะไอคอนกับข้อความ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17, // [UI] ขนาดหัวข้อ
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6), // [UI] ระยะหัวข้อกับคำอธิบาย
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54, // [UI] สีเทา
                        fontSize: 13, // [UI] ขนาดคำอธิบาย
                        height: 1.4, // [UI] ระยะห่างบรรทัด (1.4 เท่าของขนาดตัวอักษร)
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
