import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_goal.dart';

void main() {
  test('ไม่รู้น้ำหนักตัว: ใช้ค่ากลางตามเป้าหมาย (≈ ผู้ใหญ่ 60 กก.)', () {
    expect(PlanGoal.defaultTargets(PlanGoal.loseWeight), (
      calories: 1600,
      protein: 80,
    ));
    expect(PlanGoal.defaultTargets(PlanGoal.maintain), (
      calories: 2000,
      protein: 60,
    ));
    expect(PlanGoal.defaultTargets(PlanGoal.gainMuscle), (
      calories: 2300,
      protein: 110,
    ));
  });

  test('รู้น้ำหนักตัว: คิดโปรตีนต่อ กก. ตามเป้าหมาย', () {
    // 60 กก.: 1.0 / 1.4 / 1.8 g ต่อ กก. (ปัดทีละ 5 g)
    expect(PlanGoal.defaultTargets(PlanGoal.maintain, weightKg: 60).protein, 60);
    expect(
      PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: 60).protein,
      85,
    );
    expect(
      PlanGoal.defaultTargets(PlanGoal.gainMuscle, weightKg: 60).protein,
      110,
    );
    // แคลอรี: 32 kcal/กก. ± ตามเป้าหมาย (ปัดทีละ 50)
    expect(
      PlanGoal.defaultTargets(PlanGoal.maintain, weightKg: 60).calories,
      1900,
    );
    expect(
      PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: 60).calories,
      1500,
    );
    expect(
      PlanGoal.defaultTargets(PlanGoal.gainMuscle, weightKg: 80).protein,
      145,
    );
  });

  test('แคลอรีไม่ต่ำกว่า 1200 แม้ตัวเล็กและลดน้ำหนัก', () {
    expect(
      PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: 40).calories,
      1200,
    );
  });

  test('น้ำหนักที่กรอกผิด (นอก 30–200 กก.) ใช้ค่ากลาง', () {
    expect(PlanGoal.validWeight('abc'), isNull);
    expect(PlanGoal.validWeight('5'), isNull);
    expect(PlanGoal.validWeight('65'), 65);
    expect(
      PlanGoal.defaultTargets(PlanGoal.maintain, weightKg: 500),
      PlanGoal.defaultTargets(PlanGoal.maintain),
    );
  });

  test('ลดน้ำหนัก: เลือกเมนูโปรตีนต่อแคลอรีสูงก่อน', () {
    expect(
      PlanGoal.score(PlanGoal.loseWeight, 400, 40),
      greaterThan(PlanGoal.score(PlanGoal.loseWeight, 600, 40)),
    );
  });

  test('เพิ่มกล้ามเนื้อ: เลือกเมนูโปรตีนสูงก่อน', () {
    expect(
      PlanGoal.score(PlanGoal.gainMuscle, 600, 50),
      greaterThan(PlanGoal.score(PlanGoal.gainMuscle, 400, 30)),
    );
  });

  test('รักษาน้ำหนัก: ไม่เปลี่ยนลำดับเดิม', () {
    expect(
      PlanGoal.score(PlanGoal.maintain, 400, 40),
      PlanGoal.score(PlanGoal.maintain, 700, 10),
    );
  });
}
