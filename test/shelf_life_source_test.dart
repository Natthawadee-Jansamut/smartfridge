import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/utils/shelf_life.dart';

// ที่มาของตัวเลขตามสไลด์อายุการเก็บรักษา
// (S = springnews, B = The Beefchelor, SU = SUPALAI)
void main() {
  String src(String key, String state, String storage) =>
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

  test('ขนมปัง SU, ผัก ผลไม้ นม โยเกิร์ต Maeban, SUPALAI', () {
    expect(src('bread', '', storageFridge), 'SUPALAI');
    for (final key in ['leafy_veg', 'root_veg', 'fruit', 'milk', 'yogurt']) {
      expect(src(key, '', storageFridge), 'Maeban, SUPALAI', reason: key);
    }
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
