import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/utils/shelf_life.dart';

void main() {
  test('เนื้อสัตว์ / อาหารเหลือ: ไม่มีปุ่มต่อเวลา และบอกให้ทิ้ง', () {
    for (final type in ['chicken', 'fish', 'leftover']) {
      final item = {'shelf_type': type};
      expect(canExtendOverdue(item), isFalse, reason: type);
      expect(overdueAdvice(item), contains('ควรทิ้ง'));
    }
  });

  test('แปรรูปเปิดซองแล้วไม่มีปุ่ม ยังไม่เปิดซองมีปุ่ม', () {
    expect(
      canExtendOverdue({
        'shelf_type': 'processed_meat',
        'food_state': stateOpened,
      }),
      isFalse,
    );
    expect(
      canExtendOverdue({
        'shelf_type': 'processed_meat',
        'food_state': stateUnopened,
      }),
      isTrue,
    );
  });

  test('ขนมปัง: ต่อเวลาได้ และเตือนเรื่องรา', () {
    final bread = {'shelf_type': 'bread'};
    expect(canExtendOverdue(bread), isTrue);
    expect(overdueAdvice(bread), contains('รา'));
  });

  test('ผักผลไม้: ต่อเวลาได้ ตรวจด้วยตา', () {
    final veg = {'shelf_type': 'leafy_veg'};
    expect(canExtendOverdue(veg), isTrue);
    expect(overdueAdvice(veg), contains('ไม่เน่า'));
  });
}
