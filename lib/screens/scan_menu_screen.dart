import 'package:flutter/material.dart';

import 'ImageScanning.dart';
import 'saved_recipes_screen.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';

/// หน้าเลือกว่าจะ "สแกน" อะไร (ตามดีไซน์ใน Figma: เฟรม "SCAN" ตัวบนสุด)
/// เข้าถึงได้จากแท็บ "สแกน" ที่แถบเมนูด้านล่าง
/// - ถ่ายรูปวัตถุดิบ  -> ไปหน้าสแกนวัตถุดิบเข้าตู้เย็น (ImageScanning)
/// - สแกนสูตรอาหาร   -> ไปหน้าคลังสูตรอาหารที่สแกนไว้ (SavedRecipesScreen)
///
/// หมายเหตุ: ทางลัดจากหน้าหลัก (เมนูตะแกรง) ยังคงพาเข้า ImageScanning ตรงๆ
/// เหมือนเดิม ไม่ต้องผ่านหน้าเลือกนี้
class ScanMenuScreen extends StatelessWidget {
  const ScanMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8EEFF),
      bottomNavigationBar: const AppBottomNav(current: AppTab.scan),
      body: SafeArea(
        child: Column(
          children: [
            // แถบบนสุด: ป้ายกำกับ "สแกน" ทรงแคปซูลสีเหลือง + ปุ่มตัวกรองวงกลม (ตามดีไซน์)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D0),
                        borderRadius: BorderRadius.circular(27),
                      ),
                      child: const Row(
                        children: [
                          ScannerIcon(size: 20),
                          SizedBox(width: 15),
                          Text(
                            "สแกน",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      child: const Center(child: FilterIcon(size: 20)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  children: [
                    _ScanOptionCard(
                      // ตรงกับไอคอน "hugeicons:meal-scan" ใน Figma แบบเป๊ะๆ
                      // (ใช้เส้นพาธ SVG จริงจากไฟล์ Figma ไม่ใช่ไอคอนประมาณ)
                      iconWidget: const MealScanIcon(size: 64),
                      title: "ถ่ายรูปวัตถุดิบ",
                      subtitle: "นำวัตถุดิบเข้าตู้เย็น โดยการถ่ายรูป\nหรือเลือกรูปจากคลัง",
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ImageScanning(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ScanOptionCard(
                      // ตรงกับไอคอน "material-symbols-light:document-scanner-outline" ใน Figma
                      // (ใช้เส้นพาธ SVG จริงจากไฟล์ Figma ไม่ใช่ไอคอนประมาณ)
                      iconWidget: const SizedBox(
                        width: 64,
                        height: 64,
                        child: DocumentScannerRawIcon(size: 60),
                      ),
                      title: "สแกนสูตรอาหาร",
                      subtitle: "นำเข้าสูตรอาหารโดยการถ่ายรูป\nหรือเลือกรูปจากคลัง",
                      onTap: () => Navigator.push(
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

class _ScanOptionCard extends StatelessWidget {
  final Widget iconWidget;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScanOptionCard({
    required this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.blue.withOpacity(0.15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconWidget,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        height: 1.4,
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
