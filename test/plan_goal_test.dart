import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_goal.dart';

void main() {
  test('แคลอรีตามเป้าหมาย ไม่ขึ้นกับน้ำหนัก', () {
    // ธงโภชนาการ 2000, ลด 500 (AHA/ACC/TOS), เพิ่ม 15% (Iraki 2019)
    for (final w in [null, 45.0, 90.0]) {
      expect(
        PlanGoal.defaultTargets(PlanGoal.maintain, weightKg: w).calories,
        2000,
      );
      expect(
        PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: w).calories,
        1500,
      );
      expect(
        PlanGoal.defaultTargets(PlanGoal.gainMuscle, weightKg: w).calories,
        2300,
      );
    }
  });

  test('โปรตีน: น้ำหนัก × 0.8 / 1.4 / 1.8 g ต่อ กก. ปัดทีละ 5', () {
    expect(PlanGoal.defaultTargets(PlanGoal.maintain, weightKg: 60).protein, 50);
    expect(
      PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: 60).protein,
      85,
    );
    expect(
      PlanGoal.defaultTargets(PlanGoal.gainMuscle, weightKg: 60).protein,
      110,
    );
    expect(
      PlanGoal.defaultTargets(PlanGoal.gainMuscle, weightKg: 80).protein,
      145,
    );
  });

  test('ไม่กรอกน้ำหนัก / กรอกผิด: ใช้น้ำหนักอ้างอิง 60 กก.', () {
    expect(PlanGoal.validWeight('abc'), isNull);
    expect(PlanGoal.validWeight('5'), isNull);
    expect(PlanGoal.validWeight('65'), 65);
    expect(
      PlanGoal.defaultTargets(PlanGoal.loseWeight),
      PlanGoal.defaultTargets(PlanGoal.loseWeight, weightKg: 60),
    );
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
