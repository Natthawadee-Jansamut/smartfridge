/// ช่วงเป้าหมายโภชนาการของแพลน
///
/// เป้าต่อวันที่ผู้ใช้ตั้งเป็น "เพดาน": ยอดรวมทั้งวันห้ามเกิน และขาดได้ไม่เกิน
/// [calTolerance] kcal / [proteinTolerance] g (ทั้งแคลอรีและโปรตีน)
/// แบ่งช่วงเท่ากันทุกมื้อ — ทุกมื้ออยู่ในช่วงต่อมื้อ -> ยอดรวมทั้งวันอยู่ในช่วงแน่นอน
class PlanTargets {
  static const num calTolerance = 100; // ยอมให้แคลอรีทั้งวันขาดเป้าได้ไม่เกิน 100 kcal (แก้เลขเพื่อให้หลวม/เข้มขึ้น)
  static const num proteinTolerance = 10; // ยอมให้โปรตีนทั้งวันขาดเป้าได้ไม่เกิน 10 กรัม

  final num dayCal; // เป้าแคลอรีต่อวัน
  final num dayProtein; // เป้าโปรตีนต่อวัน (กรัม)
  final int meals; // จำนวนมื้อต่อวัน

  const PlanTargets({
    required this.dayCal,
    required this.dayProtein,
    required this.meals,
  });

  num get _n => meals > 0 ? meals : 1; // จำนวนมื้อที่ใช้หาร (กันหารด้วย 0)

  num get mealCalMax => dayCal / _n; // แคลอรีสูงสุดต่อมื้อ = เป้าทั้งวัน ÷ จำนวนมื้อ
  num get mealCalMin => (dayCal - calTolerance) / _n; // แคลอรีต่ำสุดต่อมื้อ
  num get mealProteinMax => dayProtein / _n; // โปรตีนสูงสุดต่อมื้อ
  num get mealProteinMin => (dayProtein - proteinTolerance) / _n; // โปรตีนต่ำสุดต่อมื้อ

  /// มื้อเดียวอยู่ในช่วงต่อมื้อ (ใช้คัดเมนูเก่า/เมนูจากคลังสูตร)
  bool mealFits(num cal, num protein) =>
      cal >= mealCalMin && // แคลอรีไม่ต่ำเกิน
      cal <= mealCalMax && // แคลอรีไม่สูงเกิน
      protein >= mealProteinMin && // โปรตีนไม่ต่ำเกิน
      protein <= mealProteinMax; // โปรตีนไม่สูงเกิน

  /// ยอดรวมทั้งวันอยู่ในช่วง (ไม่เกินเป้า และขาดไม่เกินที่ยอมให้)
  bool dayFits(num cal, num protein) =>
      cal <= dayCal &&
      cal >= dayCal - calTolerance &&
      protein <= dayProtein &&
      protein >= dayProtein - proteinTolerance;

  /// ช่วงต่อมื้อสำหรับ [slots] มื้อที่เหลือของวัน เมื่อมื้ออื่นในวันนั้นรวมกันได้
  /// [fixedCal] / [fixedProtein] แล้ว (มื้อที่ไม่ได้ให้ AI ทำใหม่)
  ({num calMin, num calMax, num proteinMin, num proteinMax}) slotBudget({
    required num fixedCal, // แคลอรีของมื้อที่ล็อกไว้แล้ว
    required num fixedProtein, // โปรตีนของมื้อที่ล็อกไว้แล้ว
    required int slots, // จำนวนมื้อที่ยังต้องหาเมนูใหม่
  }) {
    final n = slots > 0 ? slots : 1; // กันหารด้วย 0
    final calLeft = dayCal - fixedCal; // แคลอรีที่เหลือให้ใช้ได้
    final proLeft = dayProtein - fixedProtein; // โปรตีนที่เหลือให้ใช้ได้
    num floor0(num v) => v < 0 ? 0 : v; // ตัวช่วย: ถ้าติดลบให้เป็น 0
    return (
      calMin: floor0((calLeft - calTolerance) / n), // แคลอรีขั้นต่ำต่อมื้อที่เหลือ
      calMax: floor0(calLeft / n), // แคลอรีสูงสุดต่อมื้อที่เหลือ
      proteinMin: floor0((proLeft - proteinTolerance) / n),
      proteinMax: floor0(proLeft / n),
    );
  }

  /// ระยะห่างของยอดรวมทั้งวันจากช่วงเป้า (0 = อยู่ในช่วง)
  /// เกินเป้าถือว่าแย่กว่าขาด 3 เท่า, โปรตีน 1 g นับเท่ากับ 10 kcal
  num dayDistance(num cal, num protein) {
    num calGap = 0, proGap = 0; // เริ่มที่ห่าง 0
    if (cal > dayCal) calGap = (cal - dayCal) * 3; // แคลอรีเกินเป้า -> ห่าง x3 (ลงโทษหนัก)
    if (cal < dayCal - calTolerance) calGap = dayCal - calTolerance - cal; // แคลอรีขาดเกินที่ยอม
    if (protein > dayProtein) proGap = (protein - dayProtein) * 3; // โปรตีนเกินเป้า -> x3
    if (protein < dayProtein - proteinTolerance) {
      proGap = dayProtein - proteinTolerance - protein; // โปรตีนขาดเกินที่ยอม
    }
    return calGap + proGap * 10; // รวมเป็นคะแนนเดียว (โปรตีน x10 ให้น้ำหนักเทียบแคลอรี)
  }
}
