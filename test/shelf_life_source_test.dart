import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/utils/shelf_life.dart';

// ที่มาของตัวเลขตามสไลด์อายุการเก็บรักษา
// (S = springnews, B = The Beefchelor, SU = SUPALAI, M = Maeban)
void main() {
  String? src(String key, String state, String storage) =>
      findShelfType(key)!.sourceFor(state, storage);

  test('เนื้อไก่: ดิบ/สุก ช่องปกติ B, ดิบ ช่องแช่แข็ง S', () {
    expect(src('chicken', stateRaw, storageFridge), 'The Beefchelor');
    expect(src('chicken', stateRaw, storageFreezer), 'springnews');
    expect(src('chicken', stateCooked, storageFridge), 'The Beefchelor');
  });

  test('เนื้อวัว เนื้อหมู: ช่องปกติ S,B, ช่องแช่แข็ง S', () {
    for (final st in [stateRaw, stateCooked]) {
      expect(src('beef_pork', st, storageFridge), 'springnews, The Beefchelor');
      expect(src('beef_pork', st, storageFreezer), 'springnews');
    }
  });

  test('ประเภทที่มาจาก springnews อย่างเดียว', () {
    for (final key in [
      'ground_meat',
      'offal',
      'fish',
      'shellfish',
      'leftover',
    ]) {
      expect(src(key, '', storageFridge), 'springnews', reason: key);
    }
    for (final st in [stateOpened, stateUnopened]) {
      expect(src('processed_meat', st, storageFridge), 'springnews');
      expect(src('processed_meat', st, storageFreezer), 'springnews');
    }
    expect(src('egg', stateRaw, storageFridge), 'springnews');
    expect(src('egg', stateCooked, storageFridge), 'springnews');
  });

  test('ขนมปัง นม โยเกิร์ต SU, ผักใบ ผักหัว ผลไม้ M', () {
    for (final key in ['bread', 'milk', 'yogurt']) {
      expect(src(key, '', storageFridge), 'SUPALAI', reason: key);
    }
    for (final key in ['leafy_veg', 'root_veg', 'fruit']) {
      expect(src(key, '', storageFridge), 'Maeban', reason: key);
    }
  });

  test('ผลไม้ไม่มีตัวเลือกช่องแช่แข็ง (ไม่มีข้อมูลจากแหล่งอ้างอิง)', () {
    final r = resolveShelfLife(
      typeKey: 'fruit',
      state: '',
      geminiFridgeDays: 7,
    );
    expect(r.fridgeDays, 7);
    expect(r.freezerDays, isNull);
  });

  test('ช่องแช่แข็งที่ระบบไม่มีข้อมูล: ไม่บอกแหล่งที่มา ใช้ค่าจาก AI', () {
    for (final key in ['fruit', 'leafy_veg', 'milk', 'bread']) {
      expect(src(key, '', storageFreezer), isNull, reason: key);
    }
    expect(src('egg', stateRaw, storageFreezer), isNull);
    expect(src('chicken', stateCooked, storageFreezer), isNull);
    // สแกนเข้าช่องแช่แข็งตั้งแต่แรก: AI ประเมิน ไม่เตือน
    expect(
      shelfSourceShort({
        'shelf_type': 'fruit',
        'storage': storageFreezer,
        'freezer_days': 60,
      }),
      'AI ประเมินให้ ควรตรวจสอบอีกครั้ง',
    );
    // ย้ายเข้าช่องแช่แข็งทีหลัง: นับวันที่เหลือเดิมต่อ
    expect(
      shelfSourceShort({
        'shelf_type': 'fruit',
        'storage': storageFreezer,
        'freezer_days': 5,
        'storage_changed_at': '2026-11-07T00:00:00Z',
      }),
      'นับวันที่เหลือต่อจากช่องปกติ',
    );
  });

  test('เตือนว่าไม่แนะนำให้แช่แข็งเฉพาะไข่', () {
    expect(freezerNotRecommended({'shelf_type': 'egg'}), isTrue);
    for (final key in ['fruit', 'leafy_veg', 'milk', 'bread', 'chicken']) {
      expect(freezerNotRecommended({'shelf_type': key}), isFalse, reason: key);
    }
    expect(
      shelfSourceShort({
        'shelf_type': 'egg',
        'food_state': stateRaw,
        'storage': storageFreezer,
        'freezer_days': 30,
      }),
      'AI ประเมินให้ ควรตรวจสอบอีกครั้ง · $freezerNotRecommendedText',
    );
  });

  test('หน่วยนับมี แผ่น', () {
    expect(pieceUnits, contains('แผ่น'));
  });

  test('การ์ดในตู้เย็นใช้ที่มาตามสถานะและช่องที่เก็บ', () {
    expect(
      shelfSourceShort({
        'shelf_type': 'chicken',
        'food_state': stateRaw,
        'storage': storageFreezer,
      }),
      'ข้อมูลจาก springnews',
    );
    expect(
      shelfSourceShort({
        'shelf_type': 'chicken',
        'food_state': stateRaw,
        'storage': storageFridge,
      }),
      'ข้อมูลจาก The Beefchelor',
    );
  });
}
