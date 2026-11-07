/// ตรวจว่าวัตถุดิบของเมนูขัดกับข้อจำกัดอาหารหรือไม่ (ดูจากชื่อวัตถุดิบ)
///
/// ใช้กันเมนูผิดข้อจำกัดหลุดเข้าแพลน / ถูกติดป้ายผิดแล้วลามไปผู้ใช้คนอื่น:
/// - เมนูเก่าจากแพลนก่อนๆ ของผู้ใช้ (ไม่มีป้ายข้อจำกัดอาหาร)
/// - เมนูจากคลังสูตรกลาง (กันป้ายที่ติดผิดมาก่อน)
/// - เมนูที่ Gemini สร้าง (ก่อนติดป้ายและบันทึกลงคลังกลาง)
///
/// เป็นการเทียบคำในชื่อวัตถุดิบ ไม่ใช่ฐานข้อมูลส่วนประกอบ — จับของที่เห็นชัด
/// (เนื้อสัตว์ น้ำปลา ไข่ นม กระเทียม ฯลฯ) ได้ แต่ของแปรรูปที่ชื่อไม่บอก
/// ส่วนผสม (เช่น ซอสสำเร็จรูปบางยี่ห้อ) ตรวจไม่ได้
class DietCheck {
  DietCheck._();

  static const none = 'ไม่มี';
  static const vegetarian = 'มังสวิรัติ';
  static const jay = 'เจ';
  static const noDairy = 'ไม่ทานนม';

  /// คำที่บอกว่าเป็นของทำจากพืช/ของเจ — ตัดออกก่อนตรวจ
  /// เช่น "หมูเจ", "ไก่เทียม", "นมถั่วเหลือง", "เนยถั่ว"
  static const _plantBased = [
    'เจ',
    'มังสวิรัติ',
    'เทียม',
    'โปรตีนเกษตร',
    'วีแกน',
    'จากพืช',
  ];
  static const _plantMilks = [
    'นมถั่วเหลือง',
    'นมอัลมอนด์',
    'นมข้าวโอ๊ต',
    'นมโอ๊ต',
    'นมมะพร้าว',
    'นมพืช',
    'เนยถั่ว',
    'เนยเทียม',
  ];

  /// เนื้อสัตว์ อาหารทะเล และเครื่องปรุงจากสัตว์ (ห้ามทั้งมังสวิรัติและเจ)
  static const _animal = [
    'หมู',
    'ไก่',
    'เนื้อวัว',
    'เนื้อสัตว์',
    'เนื้อสับ',
    'เนื้อแดดเดียว',
    'สันใน',
    'สันนอก',
    'วัว',
    'เป็ด',
    'แพะ',
    'แกะ',
    'ปลา',
    'กุ้ง',
    'ปู',
    'หอย',
    'หมึก',
    'แฮม',
    'เบคอน',
    'ไส้กรอก',
    'กุนเชียง',
    'ลูกชิ้น',
    'แหนม',
    'หมูยอ',
    'ตับ',
    'เลือด',
    'กระดูก',
    'น้ำปลา',
    'กะปิ',
    'ซอสหอยนางรม',
    'น้ำมันหอย',
    'ซุปก้อน',
    'น้ำซุปไก่',
    'น้ำสต๊อก',
  ];

  /// ไข่ (มังสวิรัติทั่วไปกินได้ แต่เจกินไม่ได้)
  static const _egg = ['ไข่'];

  /// นมและผลิตภัณฑ์นม
  static const _dairy = [
    'นม',
    'เนย',
    'ชีส',
    'โยเกิร์ต',
    'ครีม',
    'วิปปิ้ง',
    'มอสซาเรลลา',
  ];

  /// ผักฉุน 5 ชนิดที่อาหารเจงดเว้น
  static const _pungent = [
    'กระเทียม',
    'หอมแดง',
    'หอมใหญ่',
    'หอมหัวใหญ่',
    'หัวหอม',
    'ต้นหอม',
    'กุยช่าย',
    'หลักเกียว',
  ];

  /// คำที่ขึ้นต้นด้วย "เนื้อ" แต่ไม่ใช่เนื้อสัตว์
  static const _notMeat = ['เนื้อมะพร้าว', 'เนื้อเห็ด', 'เนื้อฟักทอง'];

  /// คำที่เป็นไข่ — ตัดออกก่อนตรวจเนื้อสัตว์ ("ไข่ไก่" ไม่ใช่เนื้อไก่)
  /// เรียงยาวก่อน ("ไข่ไก่" ก่อน "ไข่") แต่ "ไข่ปลา" จะเหลือ "ปลา" ให้จับได้
  static const _eggWords = [
    'ไข่นกกระทา',
    'ไข่เยี่ยวม้า',
    'ไข่ไก่',
    'ไข่เป็ด',
    'ไข่เค็ม',
    'ไข่ขาว',
    'ไข่แดง',
    'ไข่',
  ];

  static String _strip(String text, List<String> words) {
    var n = text;
    for (final w in words) {
      n = n.replaceAll(w, '');
    }
    return n;
  }

  static bool _hasAny(String name, List<String> words) =>
      words.any((w) => name.contains(w));

  /// มีเนื้อสัตว์/อาหารทะเล/เครื่องปรุงจากสัตว์ไหม
  static bool _isAnimal(String n) {
    // ของเจ/ของทำจากพืช ("หมูเจ", "ไก่เทียม") ไม่นับเป็นเนื้อสัตว์
    if (_hasAny(n, _plantBased)) return false;
    final t = _strip(n, [..._eggWords, ..._notMeat, 'นมวัว']);
    return _hasAny(t, _animal) || t.startsWith('เนื้อ');
  }

  static bool _isDairy(String n) =>
      _hasAny(_strip(n, _plantMilks), _dairy);

  /// ชื่อวัตถุดิบที่ขัดกับข้อจำกัดอาหาร [diet] (ว่าง = ผ่าน)
  static List<String> violations(String? diet, Iterable<Object?> names) {
    if (diet == null || diet == none || diet.trim().isEmpty) return const [];
    final out = <String>[];
    for (final raw in names) {
      final name = (raw ?? '').toString().trim();
      final n = name.replaceAll(RegExp(r'\s+'), '');
      if (n.isEmpty) continue;
      final bad = switch (diet) {
        vegetarian => _isAnimal(n),
        jay =>
          _isAnimal(n) ||
              (!_hasAny(n, _plantBased) && _hasAny(n, _egg)) ||
              _isDairy(n) ||
              _hasAny(n, _pungent),
        noDairy => _isDairy(n),
        _ => false,
      };
      if (bad) out.add(name);
    }
    return out;
  }

  /// วัตถุดิบทุกอย่างผ่านข้อจำกัดอาหาร [diet]
  static bool fits(String? diet, Iterable<Object?> names) =>
      violations(diet, names).isEmpty;

  /// ชื่อวัตถุดิบจากรายการ ingredients (List ของ Map ที่มี 'name')
  static List<String> namesOf(Object? ingredients) => [
    if (ingredients is List)
      for (final i in ingredients)
        if (i is Map) (i['name'] ?? '').toString(),
  ];
}
