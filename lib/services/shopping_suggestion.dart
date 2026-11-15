import 'package:flutter/foundation.dart'; // ใช้ debugPrint
import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้ดึงข้อมูลจากฐานข้อมูล

/// ค่าที่ใช้ร่วมกันของ "รายการซื้อของ" ในแพลนอาหาร
///
/// ตอนสร้างแพลนแบบ "ซื้อเพิ่มได้" วัตถุดิบที่ไม่มีในตู้เย็นจะติดธง `to_buy: true`
/// ใน weekly_meals.ingredients (jsonb เดิม ไม่ต้องแก้ตาราง) แผนรายสัปดาห์จะรวม
/// รายการเหล่านี้เป็นรายการซื้อของทั้งสัปดาห์ และแสดงในการ์ดของแต่ละมื้อ
class ShoppingSuggestion {
  ShoppingSuggestion._(); // ห้ามสร้างตัวแปรจากคลาสนี้

  /// key ในวัตถุดิบของมื้อ = ต้องซื้อเพิ่ม (ไม่มีในตู้เย็นตอนสร้างแพลน)
  static const toBuyKey = 'to_buy';

  /// ของพื้นฐานจากตาราง ingredients (is_staple = true) — โหลดด้วย loadStaples()
  /// เก็บเป็นชื่อที่ตัดช่องว่างแล้ว
  static Set<String> _dbStaples = {};
  static DateTime? _loadedAt; // เวลาที่โหลดล่าสุด (ไว้เช็คว่าแคชยังสดอยู่ไหม)

  /// โหลดรายการของพื้นฐานจาก ingredients.is_staple (แคชไว้ 10 นาที)
  /// โหลดไม่ได้ -> ใช้รายการสำรองในโค้ด (staples) ต่อไป ไม่ทำให้หน้าจอพัง
  static Future<void> loadStaples({bool force = false}) async {
    final fresh =
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10); // โหลดไปไม่ถึง 10 นาที = ยังสด
    if (fresh && !force) return; // ยังสดและไม่ได้บังคับโหลดใหม่ ก็ไม่ต้องโหลด
    try {
      final rows = await Supabase.instance.client
          .from('ingredients') // ตารางวัตถุดิบ
          .select('name') // เอาแค่ชื่อ
          .eq('is_staple', true); // เฉพาะที่เป็นของพื้นฐาน
      _dbStaples = {
        for (final r in rows)
          (r['name'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ''), // ตัดช่องว่างทั้งหมดออกจากชื่อ
      }..remove(''); // ทิ้งชื่อว่าง
      _loadedAt = DateTime.now(); // จำเวลาที่โหลด
    } catch (e) {
      debugPrint('โหลดของพื้นฐาน (is_staple) ไม่สำเร็จ ใช้รายการในโค้ดแทน: $e');
    }
  }

  /// รายชื่อของพื้นฐานสำหรับใส่ใน prompt ของ AI (จากตาราง + รายการสำรองในโค้ด)
  static String stapleNamesForPrompt() {
    final names = {..._dbStaples, ...staples}; // รวมสองรายการ (Set ตัดชื่อซ้ำให้เอง)
    return names.join(', '); // ต่อเป็นข้อความเดียวคั่นด้วยจุลภาค
  }

  /// รายการสำรองในโค้ด: ของพื้นฐานที่บ้านส่วนใหญ่มีอยู่แล้ว แต่มักไม่ได้บันทึกเข้าตู้เย็น
  /// (ข้าว น้ำมัน และเครื่องปรุงหลัก) — ใช้ร่วมกับ ingredients.is_staple
  /// ไม่รวมของที่ไม่ใช่ทุกบ้านจะมี เช่น กระเทียม หอมแดง พริก มะนาว แป้ง เนย ซุปก้อน
  static const staples = [
    'ข้าวสวย',
    'ข้าวสาร',
    'ข้าวหอมมะลิ',
    'ข้าวกล้อง',
    'ข้าว',
    'น้ำมัน',
    'น้ำปลา',
    'ซีอิ๊ว',
    'ซอส',
    'เกลือ',
    'น้ำตาล',
    'พริกไทย',
    'ผงปรุงรส',
    'ผงชูรส',
    'น้ำเปล่า',
  ];

  /// ของพื้นฐานไหม (เทียบคำขึ้นต้น เช่น "น้ำมันพืช", "ซีอิ๊วขาว", "ข้าวสวยหุงสุก")
  /// ยกเว้นของสดที่ขึ้นต้นคล้ายกัน เช่น "ข้าวโพด", "น้ำมะพร้าว" (ไม่อยู่ในรายการ)
  static bool isStaple(String name) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ''); // ตัดช่องว่างออกให้หมด
    if (n.isEmpty) return false; // ชื่อว่าง ไม่ใช่ของพื้นฐาน
    const notStaple = ['ข้าวโพด', 'ข้าวเกรียบ', 'ข้าวเหนียวมะม่วง']; // คำที่ขึ้นต้นด้วย "ข้าว" แต่ไม่ใช่ของพื้นฐาน
    if (notStaple.any(n.startsWith)) return false;
    // ตรงกับของพื้นฐานในตาราง (ชื่อตรง หรือขึ้นต้นด้วยชื่อนั้น) หรือรายการสำรองในโค้ด
    return _dbStaples.any((s) => n == s || n.startsWith(s)) ||
        staples.any(n.startsWith);
  }
}
