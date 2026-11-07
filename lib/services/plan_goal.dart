/// เป้าหมายของแพลนอาหาร (ลดน้ำหนัก / รักษาน้ำหนัก / เพิ่มกล้ามเนื้อ)
///
/// ใช้ 3 ที่:
/// 1. ค่าเริ่มต้นของแคลอรี/โปรตีนต่อวัน เมื่อผู้ใช้ไม่ได้กรอกเอง
///    (แหล่งอ้างอิงของแต่ละตัวเลขอยู่ที่ค่าคงที่ด้านล่าง)
/// 2. ลำดับเมนูที่หยิบจากแพลนเก่า/คลังสูตรกลาง (ในช่วงเป้าต่อมื้อเหมือนกัน
///    เลือกเมนูที่เหมาะกับเป้าหมายก่อน)
/// 3. กติกาใน prompt ของ Gemini (สร้างแพลน / เปลี่ยนเมนู)
///
/// ค่าเริ่มต้นเป็นค่าแนะนำทั่วไปสำหรับผู้ใหญ่สุขภาพดี ไม่ได้คิดเพศ อายุ ส่วนสูง
/// หรือโรคประจำตัว ผู้ใช้ควรกรอกเป้าของตัวเองถ้ารู้ (เช่น จากแพทย์/นักโภชนาการ)
class PlanGoal {
  static const loseWeight = 'ลดน้ำหนัก';
  static const maintain = 'รักษาน้ำหนัก';
  static const gainMuscle = 'เพิ่มกล้ามเนื้อ';

  /// น้ำหนักตัวที่รับได้ (กก.) — นอกช่วงนี้ถือว่ากรอกผิด ใช้ค่ากลางแทน
  static const minWeightKg = 30;
  static const maxWeightKg = 200;

  /// น้ำหนักตัวที่ใช้แทนเมื่อผู้ใช้ไม่ได้กรอก (ประมาณผู้ใหญ่ไทย)
  static const referenceWeightKg = 60;

  /// โปรตีน (g ต่อน้ำหนักตัว 1 กก. ต่อวัน) ตามเป้าหมาย
  /// - รักษาน้ำหนัก 0.8: ค่าแนะนำพื้นฐานสำหรับผู้ใหญ่ (RDA)
  /// - ลดน้ำหนัก 1.4: meta-analysis 2024 (PMID 39002131) พบว่าโปรตีน
  ///   มากกว่า 1.3 g/กก. ช่วยรักษากล้ามเนื้อระหว่างลดน้ำหนัก (ต่ำกว่า 1.0 เสี่ยงเสีย)
  /// - เพิ่มกล้ามเนื้อ 1.8: ISSN Position Stand 2017 (PMID 28642676) แนะนำ
  ///   1.4–2.0 g/กก. สำหรับคนออกกำลังกาย และ Iraki et al. 2019
  ///   (PMID 31247944) แนะนำ 1.6–2.2 g/กก. ช่วงเพิ่มกล้ามเนื้อ
  static double proteinPerKg(String? goal) => switch (goal) {
    loseWeight => 1.4,
    gainMuscle => 1.8,
    _ => 0.8,
  };

  /// พลังงานพื้นฐานต่อวัน: 2,000 kcal ตามธงโภชนาการของกรมอนามัย (ระดับ
  /// วัยรุ่นและชายวัยทำงาน; ระดับ 1,600 สำหรับหญิงวัยทำงานและผู้สูงอายุ)
  /// ไม่คิดจากน้ำหนักตัว เพราะพลังงานที่ใช้จริงขึ้นกับเพศ อายุ ส่วนสูง และ
  /// กิจกรรมด้วย การคูณน้ำหนักอย่างเดียวไม่มีแหล่งอ้างอิงสำหรับคนทั่วไป
  static const baseCalories = 2000;

  /// ลดน้ำหนัก: ลด 500 kcal/วัน (ค่าต่ำสุดของช่วง 500–750 ใน 2013
  /// AHA/ACC/TOS Guideline for the Management of Overweight and Obesity)
  static const loseDeficit = 500;

  /// เพิ่มกล้ามเนื้อ: มากกว่าพลังงานพื้นฐาน 15% (ค่ากลางของ 10–20% ใน
  /// Iraki et al. 2019)
  static const gainSurplusRatio = 0.15;

  /// น้ำหนักตัวที่ใช้ได้ หรือ null ถ้าไม่ได้กรอก/อยู่นอกช่วง
  static double? validWeight(Object? v) {
    final w = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
    if (w == null || w < minWeightKg || w > maxWeightKg) return null;
    return w;
  }

  /// ค่าเริ่มต้น (kcal, g โปรตีน) ต่อวัน เมื่อผู้ใช้ไม่ได้กรอกเป้า
  /// - แคลอรี: ตามเป้าหมาย (ไม่ขึ้นกับน้ำหนัก)
  /// - โปรตีน: น้ำหนักตัว × g ต่อ กก. ตามเป้าหมาย ปัดทีละ 5 g
  ///   ([weightKg] = null -> ใช้ [referenceWeightKg])
  static ({int calories, int protein}) defaultTargets(
    String? goal, {
    double? weightKg,
  }) {
    final w = validWeight(weightKg) ?? referenceWeightKg;
    final calories = switch (goal) {
      loseWeight => baseCalories - loseDeficit,
      gainMuscle => (baseCalories * (1 + gainSurplusRatio)).round(),
      _ => baseCalories,
    };
    return (
      calories: calories,
      protein: ((w * proteinPerKg(goal)) / 5).round() * 5,
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
