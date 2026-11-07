import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_goal.dart';

void main() {
  test('ค่าเริ่มต้นแคลอรี/โปรตีนต่างกันตามเป้าหมาย', () {
    expect(PlanGoal.defaultTargets(PlanGoal.loseWeight).calories, 1600);
    expect(PlanGoal.defaultTargets(PlanGoal.maintain).calories, 2000);
    expect(PlanGoal.defaultTargets(PlanGoal.gainMuscle).protein, 150);
    // ไม่รู้เป้าหมาย (แพลนเก่า) -> ใช้ค่าเดิม 2000 kcal / 100 g
    expect(PlanGoal.defaultTargets(null), (calories: 2000, protein: 100));
  });

  test('ลดน้ำหนัก: เลือกเมนูโปรตีนต่อแคลอรีสูงก่อน', () {
    final lean = PlanGoal.score(PlanGoal.loseWeight, 400, 40);
    final heavy = PlanGoal.score(PlanGoal.loseWeight, 600, 40);
    expect(lean, greaterThan(heavy));
  });

  test('เพิ่มกล้ามเนื้อ: เลือกเมนูโปรตีนสูงก่อน', () {
    final high = PlanGoal.score(PlanGoal.gainMuscle, 600, 50);
    final low = PlanGoal.score(PlanGoal.gainMuscle, 400, 30);
    expect(high, greaterThan(low));
  });

  test('รักษาน้ำหนัก: ไม่เปลี่ยนลำดับเดิม', () {
    expect(
      PlanGoal.score(PlanGoal.maintain, 400, 40),
      PlanGoal.score(PlanGoal.maintain, 700, 10),
    );
  });
}
