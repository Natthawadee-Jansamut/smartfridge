import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/plan_allocation.dart';

void main() {
  final now = DateTime.now().toUtc().toIso8601String();
  // อกไก่ 2 ส่วน (2 ลอต ลอตละ 1) + ไข่ 3 ฟอง
  final fridge = [
    {'name': 'อกไก่', 'quantity': 1, 'unit': 'ส่วน', 'created_at': now, 'fridge_days': 5, 'storage': 'fridge'},
    {'name': 'อกไก่', 'quantity': 1, 'unit': 'ส่วน', 'created_at': now, 'fridge_days': 5, 'storage': 'fridge'},
    {'name': 'ไข่ไก่', 'quantity': 3, 'unit': 'ฟอง', 'created_at': now, 'fridge_days': 20, 'storage': 'fridge'},
  ];
  Map<String, dynamic> meal(String id, String day, String type, List<List<String>> ings, {bool cooked = false}) => {
        'id': id,
        'day': day,
        'meal_type': type,
        'is_cooked': cooked,
        'ingredients': [for (final i in ings) {'name': i[0], 'quantity': i[1]}],
      };
  // แพลนเริ่มวันจันทร์
  final monday = DateTime(2026, 11, 2);

  test('จองอกไก่ให้มื้อที่ใกล้ถึงก่อน มื้อหลังขาดเฉพาะส่วนที่ไม่พอ', () {
    final meals = [
      meal('wed', 'Wednesday', 'มื้อที่ 1', [['อกไก่', '1 ส่วน']]),
      meal('mon', 'Monday', 'มื้อที่ 1', [['อกไก่', '1 ส่วน'], ['ข้าวสวย', '1 ถ้วย']]),
      meal('tue', 'Tuesday', 'มื้อที่ 2', [['อกไก่', '1 ส่วน'], ['ไข่ไก่', '2 ฟอง']]),
    ];
    final a = PlanAllocation.allocate(meals: meals, fridgeItems: fridge, planStart: monday);
    expect(a['mon']!.first.have, isTrue);
    expect(a['mon']![1].have, isTrue, reason: 'ข้าวสวยเป็นของพื้นฐาน');
    expect(a['tue']!.first.have, isTrue);
    expect(a['tue']![1].have, isTrue);
    expect(a['wed']!.first.have, isFalse);
    expect(a['wed']!.first.short, 1);

    final list = PlanAllocation.shoppingList(meals: meals, allocation: a, dayLabel: (d) => d);
    expect(list.length, 1);
    expect(list.first.name, 'อกไก่');
    expect(list.first.amount, 1);
    expect(list.first.unit, 'ส่วน');
  });

  test('มื้อที่ทำแล้วไม่จองของซ้ำ (หักไปแล้ว)', () {
    // หลังทำมื้อวันจันทร์ อกไก่เหลือ 1 ส่วนในตู้
    final afterCook = [fridge[1], fridge[2]];
    final meals = [
      meal('mon', 'Monday', 'มื้อที่ 1', [['อกไก่', '1 ส่วน']], cooked: true),
      meal('tue', 'Tuesday', 'มื้อที่ 2', [['อกไก่', '1 ส่วน']]),
      meal('wed', 'Wednesday', 'มื้อที่ 1', [['อกไก่', '1 ส่วน']]),
    ];
    final a = PlanAllocation.allocate(meals: meals, fridgeItems: afterCook, planStart: monday);
    expect(a['mon']!.first.have, isTrue);
    expect(a['tue']!.first.have, isTrue, reason: 'สถานะเดิมไม่เปลี่ยนหลังทำมื้อแรก');
    expect(a['wed']!.first.have, isFalse);
  });

  test('ลำดับวันเริ่มจากวันที่สร้างแพลน', () {
    final meals = [
      meal('mon', 'Monday', 'มื้อที่ 1', [['อกไก่', '2 ส่วน']]),
      meal('fri', 'Friday', 'มื้อที่ 1', [['อกไก่', '2 ส่วน']]),
    ];
    // แพลนเริ่มวันศุกร์ -> วันศุกร์มาก่อนวันจันทร์ถัดไป
    final a = PlanAllocation.allocate(meals: meals, fridgeItems: fridge, planStart: DateTime(2026, 11, 6));
    expect(a['fri']!.first.have, isTrue);
    expect(a['mon']!.first.have, isFalse);
  });
}
