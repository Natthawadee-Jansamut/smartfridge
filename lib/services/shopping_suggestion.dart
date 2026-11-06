import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ค่าที่ใช้ร่วมกันของ "รายการซื้อของ" ในแพลนอาหาร
///
/// ตอนสร้างแพลนแบบ "ซื้อเพิ่มได้" วัตถุดิบที่ไม่มีในตู้เย็นจะติดธง `to_buy: true`
/// ใน weekly_meals.ingredients (jsonb เดิม ไม่ต้องแก้ตาราง) แผนรายสัปดาห์จะรวม
/// รายการเหล่านี้เป็นรายการซื้อของทั้งสัปดาห์ และแสดงในการ์ดของแต่ละมื้อ
class ShoppingSuggestion {
  ShoppingSuggestion._();

  /// key ในวัตถุดิบของมื้อ = ต้องซื้อเพิ่ม (ไม่มีในตู้เย็นตอนสร้างแพลน)
  static const toBuyKey = 'to_buy';

  /// ถือว่า "ไม่ถึงเป้า" เมื่อต่ำกว่าเป้าเกิน 10% (ใช้กับหลอดเทียบเป้ารายวัน)
  static const shortfallRatio = 0.9;

  /// ของพื้นฐานจากตาราง ingredients (is_staple = true) — โหลดด้วย loadStaples()
  /// เก็บเป็นชื่อที่ตัดช่องว่างแล้ว
  static Set<String> _dbStaples = {};
  static DateTime? _loadedAt;

  /// โหลดรายการของพื้นฐานจาก ingredients.is_staple (แคชไว้ 10 นาที)
  /// โหลดไม่ได้ -> ใช้รายการสำรองในโค้ด (staples) ต่อไป ไม่ทำให้หน้าจอพัง
  static Future<void> loadStaples({bool force = false}) async {
    final fresh =
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10);
    if (fresh && !force) return;
    try {
      final rows = await Supabase.instance.client
          .from('ingredients')
          .select('name')
          .eq('is_staple', true);
      _dbStaples = {
        for (final r in rows)
          (r['name'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ''),
      }..remove('');
      _loadedAt = DateTime.now();
    } catch (e) {
      debugPrint('โหลดของพื้นฐาน (is_staple) ไม่สำเร็จ ใช้รายการในโค้ดแทน: $e');
    }
  }

  /// รายชื่อของพื้นฐานสำหรับใส่ใน prompt ของ AI (จากตาราง + รายการสำรองในโค้ด)
  static String stapleNamesForPrompt() {
    final names = {..._dbStaples, ...staples};
    return names.join(', ');
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
    final n = name.trim().replaceAll(RegExp(r'\s+'), '');
    if (n.isEmpty) return false;
    const notStaple = ['ข้าวโพด', 'ข้าวเกรียบ', 'ข้าวเหนียวมะม่วง'];
    if (notStaple.any(n.startsWith)) return false;
    // ตรงกับของพื้นฐานในตาราง (ชื่อตรง หรือขึ้นต้นด้วยชื่อนั้น) หรือรายการสำรองในโค้ด
    return _dbStaples.any((s) => n == s || n.startsWith(s)) ||
        staples.any(n.startsWith);
  }
}
