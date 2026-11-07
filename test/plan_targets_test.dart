import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_targets.dart';

void main() {
  const t = PlanTargets(dayCal: 1500, dayProtein: 90, meals: 3);

  test('ช่วงต่อมื้อ: 1500 kcal / 90 g, 3 มื้อ', () {
    expect(t.mealCalMax, 500);
    expect(t.mealCalMin, closeTo(466.67, 0.01));
    expect(t.mealProteinMax, 30);
    expect(t.mealProteinMin, closeTo(26.67, 0.01));
    expect(t.mealFits(480, 28), isTrue);
    expect(t.mealFits(390, 19), isFalse, reason: 'เมนูเล็กเกิน');
    expect(t.mealFits(510, 28), isFalse, reason: 'แคลอรีเกิน');
    expect(t.mealFits(480, 32), isFalse, reason: 'โปรตีนเกิน');
  });

  test('ยอดรวมต่อวัน: ห้ามเกิน ขาดได้ไม่เกิน 100 kcal / 10 g', () {
    expect(t.dayFits(1465, 85), isTrue);
    expect(t.dayFits(1400, 80), isTrue);
    expect(t.dayFits(1375, 93), isFalse);
    expect(t.dayFits(1501, 85), isFalse);
    expect(t.dayFits(1450, 79), isFalse);
    expect(t.dayDistance(1450, 85), 0);
    expect(t.dayDistance(1510, 85), greaterThan(t.dayDistance(1390, 85)));
  });

  test('งบมื้อที่เหลือหลังหักมื้อที่คงไว้', () {
    // มื้อเดิม 1 มื้อ 480 kcal / 29 g -> อีก 2 มื้อต้องรวมกัน 920-1020 kcal, 51-61 g
    final b = t.slotBudget(fixedCal: 480, fixedProtein: 29, slots: 2);
    expect(b.calMax, 510);
    expect(b.calMin, 460);
    expect(b.proteinMax, 30.5);
    expect(b.proteinMin, 25.5);
  });
}
