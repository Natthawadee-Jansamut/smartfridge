import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_goal.dart';

void main() {
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

  test('รักษาน้ำหนัก / ไม่รู้เป้าหมาย: ไม่เปลี่ยนลำดับเดิม', () {
    expect(
      PlanGoal.score(PlanGoal.maintain, 400, 40),
      PlanGoal.score(PlanGoal.maintain, 700, 10),
    );
    expect(PlanGoal.score(null, 400, 40), PlanGoal.score(null, 700, 10));
  });
}
