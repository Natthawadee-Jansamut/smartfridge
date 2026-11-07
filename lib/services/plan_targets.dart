/// ช่วงเป้าหมายโภชนาการของแพลน
///
/// เป้าต่อวันที่ผู้ใช้ตั้งเป็น "เพดาน": ยอดรวมทั้งวันห้ามเกิน และขาดได้ไม่เกิน
/// [calTolerance] kcal / [proteinTolerance] g (ทั้งแคลอรีและโปรตีน)
/// แบ่งช่วงเท่ากันทุกมื้อ — ทุกมื้ออยู่ในช่วงต่อมื้อ -> ยอดรวมทั้งวันอยู่ในช่วงแน่นอน
class PlanTargets {
  static const num calTolerance = 100;
  static const num proteinTolerance = 10;

  final num dayCal;
  final num dayProtein;
  final int meals;

  const PlanTargets({
    required this.dayCal,
    required this.dayProtein,
    required this.meals,
  });

  num get _n => meals > 0 ? meals : 1;

  num get mealCalMax => dayCal / _n;
  num get mealCalMin => (dayCal - calTolerance) / _n;
  num get mealProteinMax => dayProtein / _n;
  num get mealProteinMin => (dayProtein - proteinTolerance) / _n;

  /// มื้อเดียวอยู่ในช่วงต่อมื้อ (ใช้คัดเมนูเก่า/เมนูจากคลังสูตร)
  bool mealFits(num cal, num protein) =>
      cal >= mealCalMin &&
      cal <= mealCalMax &&
      protein >= mealProteinMin &&
      protein <= mealProteinMax;

  /// ยอดรวมทั้งวันอยู่ในช่วง (ไม่เกินเป้า และขาดไม่เกินที่ยอมให้)
  bool dayFits(num cal, num protein) =>
      cal <= dayCal &&
      cal >= dayCal - calTolerance &&
      protein <= dayProtein &&
      protein >= dayProtein - proteinTolerance;

  /// ช่วงต่อมื้อสำหรับ [slots] มื้อที่เหลือของวัน เมื่อมื้ออื่นในวันนั้นรวมกันได้
  /// [fixedCal] / [fixedProtein] แล้ว (มื้อที่ไม่ได้ให้ AI ทำใหม่)
  ({num calMin, num calMax, num proteinMin, num proteinMax}) slotBudget({
    required num fixedCal,
    required num fixedProtein,
    required int slots,
  }) {
    final n = slots > 0 ? slots : 1;
    final calLeft = dayCal - fixedCal;
    final proLeft = dayProtein - fixedProtein;
    num floor0(num v) => v < 0 ? 0 : v;
    return (
      calMin: floor0((calLeft - calTolerance) / n),
      calMax: floor0(calLeft / n),
      proteinMin: floor0((proLeft - proteinTolerance) / n),
      proteinMax: floor0(proLeft / n),
    );
  }

  /// ระยะห่างของยอดรวมทั้งวันจากช่วงเป้า (0 = อยู่ในช่วง)
  /// เกินเป้าถือว่าแย่กว่าขาด 3 เท่า, โปรตีน 1 g นับเท่ากับ 10 kcal
  num dayDistance(num cal, num protein) {
    num calGap = 0, proGap = 0;
    if (cal > dayCal) calGap = (cal - dayCal) * 3;
    if (cal < dayCal - calTolerance) calGap = dayCal - calTolerance - cal;
    if (protein > dayProtein) proGap = (protein - dayProtein) * 3;
    if (protein < dayProtein - proteinTolerance) {
      proGap = dayProtein - proteinTolerance - protein;
    }
    return calGap + proGap * 10;
  }
}
