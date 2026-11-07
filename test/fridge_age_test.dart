import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/utils/fridge_age.dart';

String _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();

Map<String, dynamic> _chicken({
  required String storage,
  required int addedDaysAgo,
}) => {
  'storage': storage,
  'fridge_days': 2,
  'freezer_days': 120,
  'created_at': _daysAgo(addedDaysAgo),
};

Map<String, dynamic> _move(Map<String, dynamic> item, String target) => {
  ...item,
  ...storageMoveFields(item, target),
};

void main() {
  test('ของที่ไม่เคยย้ายช่องนับจากวันเข้าตู้เย็นเหมือนเดิม', () {
    expect(daysLeft(_chicken(storage: 'fridge', addedDaysAgo: 1)), 1);
    expect(daysLeft(_chicken(storage: 'freezer', addedDaysAgo: 100)), 20);
  });

  test('แช่แข็งมานานแล้วย้ายออก ไม่ขึ้นเกินกำหนดและเก็บได้ตามช่องปกติ', () {
    final moved = _move(
      _chicken(storage: 'freezer', addedDaysAgo: 100),
      'fridge',
    );
    expect(daysLeft(moved), 2);
    expect(isOverdue(moved), isFalse);
    expect(moved['thawed_at'], isNotNull);
  });

  test('ย้ายเข้าช่องแช่แข็งเริ่มนับวันของช่องแช่แข็งจากวันที่ย้าย', () {
    final moved = _move(
      _chicken(storage: 'fridge', addedDaysAgo: 1),
      'freezer',
    );
    expect(moved['days_left_at_freeze'], 1);
    expect(daysLeft(moved), 120);
  });

  test('ย้ายกลับออกมา เก็บได้ไม่เกินจำนวนวันที่เหลือตอนแช่', () {
    final frozen = _move(
      _chicken(storage: 'fridge', addedDaysAgo: 1),
      'freezer',
    );
    expect(daysLeft(_move(frozen, 'fridge')), 1);
  });

  test(
    'ของที่เกินกำหนดก่อนแช่ ยังเกินกำหนดทั้งในช่องแช่แข็งและหลังย้ายออก',
    () {
      final frozen = _move(
        _chicken(storage: 'fridge', addedDaysAgo: 5),
        'freezer',
      );
      expect(daysLeft(frozen), -3);
      expect(isOverdue(frozen), isTrue);
      expect(daysLeft(_move(frozen, 'fridge')), -3);
    },
  );

  test('ของที่เหลือ 0 วันตอนแช่ ย้ายออกมาแล้วต้องใช้ภายในวันนี้', () {
    final frozen = _move(
      _chicken(storage: 'fridge', addedDaysAgo: 2),
      'freezer',
    );
    expect(daysLeft(_move(frozen, 'fridge')), 0);
  });

  test('ของที่ไม่มีข้อมูลระยะเก็บยังใช้วันหมดอายุเดิม', () {
    // เที่ยงวันของอีก 4 วันข้างหน้า — เดิมใช้ now + 4 วัน 1 ชั่วโมง ถ้ารันเทสต์
    // หลัง 23:00 จะข้ามเที่ยงคืนเป็น 5 วัน (นับวันตามปฏิทิน) เทสต์เลยพังตามเวลา
    final now = DateTime.now();
    final expiry = DateTime(now.year, now.month, now.day + 4, 12);
    final item = <String, dynamic>{
      'storage': 'fridge',
      'created_at': _daysAgo(1),
      'expiry_date': expiry.toUtc().toIso8601String(),
    };
    final moved = _move(item, 'freezer');
    expect(moved['expiry_date'], item['expiry_date']);
    expect(daysLeft(moved), 4);
  });

  test(
    'ของที่ไม่มีข้อมูลช่องแช่แข็ง เอาเข้าช่องแช่แข็งได้ แต่ไม่ต่อเวลาให้',
    () {
      // ผลไม้เก็บช่องปกติได้ 7 วัน เข้าตู้มา 2 วัน เหลือ 5 วัน
      final fruit = {
        'storage': 'fridge',
        'fridge_days': 7,
        'freezer_days': null,
        'created_at': _daysAgo(2),
      };
      final moved = _move(fruit, 'freezer');
      expect(moved['freezer_days'], 5);
      expect(daysLeft(moved), 5);
    },
  );
}
