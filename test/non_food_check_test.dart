import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/non_food_check.dart';

void main() {
  test('บุหรี่ / สุราสำหรับดื่ม: ไม่ใช่วัตถุดิบทำอาหาร', () {
    for (final n in ['บุหรี่', 'เบียร์ช้าง', 'เหล้าขาว', 'ไวน์แดง', 'สุรา', 'Vodka']) {
      expect(NonFoodCheck.isNotForCooking(n), isTrue, reason: n);
    }
  });

  test('สุราปรุงอาหารและวัตถุดิบที่ชื่อคล้าย: ใช้ทำอาหารได้', () {
    for (final n in [
      'เหล้าจีน',
      'ไวน์ปรุงอาหาร',
      'มิริน',
      'สาเกปรุงอาหาร',
      'น้ำส้มสายชูไวน์แดง',
      'อุด้ง',
      'ginger',
      'หอยนางรมสุราษฎร์',
      'ซอสหอยนางรม',
      'หมูสามชั้น',
    ]) {
      expect(NonFoodCheck.isNotForCooking(n), isFalse, reason: n);
    }
  });
}
