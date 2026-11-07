/// เป้าหมายของแพลนอาหาร (ลดน้ำหนัก / รักษาน้ำหนัก / เพิ่มกล้ามเนื้อ)
///
/// ใช้ 3 ที่:
/// 1. ค่าเริ่มต้นของแคลอรี/โปรตีนต่อวัน เมื่อผู้ใช้ไม่ได้กรอกเอง
///    — กรอกน้ำหนักตัว: คำนวณต่อ กก. ตามเป้าหมาย / ไม่กรอก: ใช้ค่ากลาง
///    (อิงผู้ใหญ่หนักประมาณ 60 กก.)
/// 2. ลำดับเมนูที่หยิบจากแพลนเก่า/คลังสูตรกลาง (ในช่วงเป้าต่อมื้อเหมือนกัน
///    เลือกเมนูที่เหมาะกับเป้าหมายก่อน)
/// 3. กติกาใน prompt ของ Gemini (สร้างแพลน / เปลี่ยนเมนู)
///
/// ค่าเริ่มต้นเป็นค่าประมาณทั่วไป ไม่ได้คิดเพศ อายุ ส่วนสูง หรือกิจกรรม
/// ผู้ใช้ควรกรอกเป้าของตัวเองถ้ารู้ (เช่น จากนักโภชนาการ)
class PlanGoal {
  static const loseWeight = 'ลดน้ำหนัก';
  static const maintain = 'รักษาน้ำหนัก';
  static const gainMuscle = 'เพิ่มกล้ามเนื้อ';

  /// น้ำหนักตัวที่รับได้ (กก.) — นอกช่วงนี้ถือว่ากรอกผิด ใช้ค่ากลางแทน
  static const minWeightKg = 30;
  static const maxWeightKg = 200;

  /// โปรตีน (g ต่อน้ำหนักตัว 1 กก. ต่อวัน) ตามเป้าหมาย
  /// คนทั่วไป ~0.8–1.0, ลดน้ำหนัก ~1.2–1.6 (ช่วยรักษากล้ามเนื้อ),
  /// เพิ่มกล้ามเนื้อ ~1.6–2.2 (ควบคู่การออกกำลังกาย) — ใช้ค่ากลางของแต่ละช่วง
  static double proteinPerKg(String? goal) => switch (goal) {
    loseWeight => 1.4,
    gainMuscle => 1.8,
    _ => 1.0,
  };

  /// พลังงาน (kcal ต่อน้ำหนักตัว 1 กก. ต่อวัน) สำหรับรักษาน้ำหนัก (กิจกรรมเบา-ปานกลาง)
  static const maintainKcalPerKg = 32;

  /// ลดน้ำหนัก: กินน้อยกว่าที่ใช้วันละ ~400 kcal / เพิ่มกล้ามเนื้อ: มากกว่า ~300 kcal
  static int _calorieShift(String? goal) => switch (goal) {
    loseWeight => -400,
    gainMuscle => 300,
    _ => 0,
  };

  /// แคลอรีต่ำสุดที่ยอมให้เป็นค่าเริ่มต้น (กันค่าต่ำเกินไปสำหรับคนตัวเล็ก)
  static const minCalories = 1200;

  /// น้ำหนักตัวที่ใช้ได้ หรือ null ถ้าไม่ได้กรอก/อยู่นอกช่วง
  static double? validWeight(Object? v) {
    final w = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
    if (w == null || w < minWeightKg || w > maxWeightKg) return null;
    return w;
  }

  /// ค่าเริ่มต้น (kcal, g โปรตีน) ต่อวัน เมื่อผู้ใช้ไม่ได้กรอกเป้า
  /// [weightKg] = น้ำหนักตัว (null = ไม่รู้ ใช้ค่ากลาง)
  static ({int calories, int protein}) defaultTargets(
    String? goal, {
    double? weightKg,
  }) {
    final w = validWeight(weightKg);
    if (w == null) {
      // ค่ากลาง ≈ ผู้ใหญ่หนัก 60 กก.
      return switch (goal) {
        loseWeight => (calories: 1600, protein: 80),
        gainMuscle => (calories: 2300, protein: 110),
        _ => (calories: 2000, protein: 60),
      };
    }
    int roundTo(num v, int step) => (v / step).round() * step;
    final cal = w * maintainKcalPerKg + _calorieShift(goal);
    return (
      calories: roundTo(cal < minCalories ? minCalories : cal, 50),
      protein: roundTo(w * proteinPerKg(goal), 5),
    );
  }

  /// กติกาเพิ่มเติมสำหรับ prompt ของ Gemini ตามเป้าหมาย
  static String promptRule(String? goal) => switch (goal) {
    loseWeight =>
      'เน้นเมนูอิ่มนานแต่พลังงานไม่สูง: โปรตีนไม่ติดมัน ผักเยอะ '
          'เลี่ยงของทอด กะทิ และน้ำตาลเยอะ ใช้วิธีต้ม นึ่ง ย่าง ผัดน้ำมันน้อย',
    gainMuscle =>
      'เน้นโปรตีนสูงทุกมื้อ (เนื้อสัตว์ ไข่ เต้าหู้ ถั่ว) '
          'คู่กับคาร์โบไฮเดรตพอเหมาะ เช่น ข้าว เส้น เพื่อให้พลังงานพอ',
    _ => 'เน้นเมนูสมดุล มีทั้งโปรตีน คาร์โบไฮเดรต และผัก ในสัดส่วนพอดี',
  };

  /// คะแนนความเหมาะกับเป้าหมาย (มากกว่า = เลือกก่อน) ใช้เรียงเมนูที่อยู่ในช่วง
  /// เป้าต่อมื้ออยู่แล้ว — ลดน้ำหนัก: โปรตีนต่อแคลอรีสูง, เพิ่มกล้ามเนื้อ:
  /// โปรตีนสูง, รักษาน้ำหนัก: เท่ากันหมด (คงลำดับเดิม)
  static double score(String? goal, num calories, num protein) =>
      switch (goal) {
        loseWeight => calories > 0 ? protein / calories : 0,
        gainMuscle => protein.toDouble(),
        _ => 0,
      };
}
