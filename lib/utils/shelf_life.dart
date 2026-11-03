/// ตารางอายุการเก็บรักษาวัตถุดิบ (ค่ากลางมาตรฐาน / Default Expiration)
/// อ้างอิงจากข้อมูลที่รวบรวมไว้ (ที่มา: springnews, The Beefchelor, SUPALAI,
/// Maeban) — ใช้เป็นค่าเริ่มต้นตอนสแกนวัตถุดิบเข้าตู้เย็น ถ้าวัตถุดิบไม่ตรงกับ
/// ประเภทไหนในตารางนี้ จะใช้จำนวนวันที่ Gemini ประเมินให้แทน และผู้ใช้ยังแก้
/// วันหมดอายุเองได้เสมอ

/// ช่องที่เก็บในตู้เย็น
const String storageFridge = 'fridge';
const String storageFreezer = 'freezer';

String storageLabel(String? storage) =>
    storage == storageFreezer ? 'ช่องแช่แข็ง' : 'ช่องปกติ';

String storageEmoji(String? storage) => storage == storageFreezer ? '❄️' : '🧊';

/// อายุการเก็บรักษาของวัตถุดิบหนึ่งสถานะ (หน่วยเป็นวัน)
/// - fridgeMin/fridgeMax: ช่องปกติ (ถ้าเป็นช่วง เช่น 3-5 วัน ให้ Gemini เลือก
///   ค่าในช่วงนี้ตามชนิดจริงของวัตถุดิบ)
/// - freezer: ช่องแช่แข็ง (null = ไม่มีข้อมูลช่องแช่แข็ง → ไม่มีตัวเลือกช่องแช่แข็ง)
class ShelfLife {
  final int? fridgeMin;
  final int? fridgeMax;
  final int? freezer;

  const ShelfLife({this.fridgeMin, int? fridgeMax, this.freezer})
    : fridgeMax = fridgeMax ?? fridgeMin;
}

/// ประเภทวัตถุดิบในตาราง
class ShelfType {
  final String key;
  final String label;

  /// สถานะที่ให้ผู้ใช้เลือก (เช่น ดิบ/สุก, เปิดซองแล้ว/ยังไม่เปิดซอง) ตัวแรก
  /// คือค่าเริ่มต้น — ถ้าไม่มีสถานะให้เลือกจะใช้คีย์ว่าง ''
  final Map<String, ShelfLife> states;

  /// true = ไม่ควรเก็บในช่องแช่แข็ง (เช่น ไข่) ผู้ใช้จะเลือกช่องแช่แข็งไม่ได้
  final bool noFreeze;

  /// แหล่งอ้างอิงของข้อมูลประเภทนี้ (แสดงให้ผู้ใช้เห็นว่าตัวเลขมาจากไหน)
  final String source;

  const ShelfType({
    required this.key,
    required this.label,
    required this.states,
    this.noFreeze = false,
    this.source = _srcMeat,
  });

  List<String> get stateNames =>
      states.keys.where((s) => s.isNotEmpty).toList();
}

const String _srcMeat = 'springnews, The Beefchelor';
const String _srcProcessed = 'springnews, The Beefchelor, SUPALAI';
const String _srcProduce = 'Maeban, SUPALAI';

/// หน่วยสำหรับ "นับเป็นชิ้น" (ของที่นับได้ ไม่ต้องชั่ง) — "แบ่งเป็นส่วน" ใช้
/// หน่วย "ส่วน" ใช้ร่วมกันทั้งหน้าผลสแกนและหน้ารายละเอียด
const List<String> pieceUnits = [
  "ชิ้น",
  "ฟอง",
  "ผล",
  "ลูก",
  "หัว",
  "ต้น",
  "กำ",
  "แพ็ค",
  "ขวด",
  "กล่อง",
];

const String portionUnit = 'ส่วน';

/// shelf_type ที่บันทึกเมื่อผู้ใช้แก้ระยะที่เก็บได้เอง — เก็บเป็น
/// "custom:<ประเภทเดิม>:<จำนวนวันเดิม>" เช่น "custom:egg:21" เพื่อจำที่มาเดิม
/// ไว้ ถ้าผู้ใช้แก้กลับเป็นค่าเดิม จะได้คืนที่มาเดิมได้ (ค่าเก่าที่เป็นแค่
/// "custom" เฉยๆ ถือว่าไม่รู้ที่มาเดิม)
const String shelfTypeCustom = 'custom';

/// สร้างค่า shelf_type สำหรับ "ผู้ใช้กำหนดเอง" โดยจำประเภทและจำนวนวันเดิมไว้
String customShelfType(String? originalKey, num? originalDays) =>
    '$shelfTypeCustom:${originalKey ?? ''}:${originalDays?.round() ?? ''}';

bool isCustomShelfType(String? value) =>
    value != null &&
    (value == shelfTypeCustom || value.startsWith('$shelfTypeCustom:'));

/// ที่มาเดิมก่อนผู้ใช้แก้ — key = ประเภทเดิม (null = AI ประเมิน), days =
/// จำนวนวันเดิม (null = ไม่รู้) — ถ้าไม่ใช่ค่า custom คืนตัวเดิมกลับไป
({String? key, int? days}) originalShelfSource(String? value, num? currentDays) {
  if (!isCustomShelfType(value)) {
    return (key: value, days: currentDays?.round());
  }
  final parts = value!.split(':');
  String? at(int i) => parts.length > i && parts[i].isNotEmpty ? parts[i] : null;
  return (key: at(1), days: int.tryParse(at(2) ?? ''));
}

const String stateRaw = 'ดิบ';
const String stateCooked = 'สุก';
const String stateOpened = 'เปิดซองแล้ว';
const String stateUnopened = 'ยังไม่เปิดซอง';

const List<ShelfType> shelfTypes = [
  ShelfType(
    key: 'chicken',
    label: 'เนื้อไก่',
    states: {
      stateRaw: ShelfLife(fridgeMin: 2, freezer: 120),
      stateCooked: ShelfLife(fridgeMin: 3),
    },
  ),
  ShelfType(
    key: 'beef_pork',
    label: 'เนื้อวัว, เนื้อหมู',
    states: {
      stateRaw: ShelfLife(fridgeMin: 3, freezer: 120),
      stateCooked: ShelfLife(fridgeMin: 3, freezer: 60),
    },
  ),
  ShelfType(
    key: 'ground_meat',
    label: 'เนื้อบด',
    states: {'': ShelfLife(fridgeMin: 1, freezer: 90)},
  ),
  ShelfType(
    key: 'offal',
    label: 'เครื่องในสัตว์',
    states: {'': ShelfLife(fridgeMin: 2, freezer: 90)},
  ),
  ShelfType(
    key: 'fish',
    label: 'ปลา',
    states: {'': ShelfLife(fridgeMin: 2, freezer: 180)},
  ),
  ShelfType(
    key: 'shellfish',
    label: 'หอย',
    states: {'': ShelfLife(fridgeMin: 2, freezer: 90)},
  ),
  ShelfType(
    key: 'processed_meat',
    label: 'ไส้กรอก แฮม เบคอน หรืออาหารแปรรูป',
    states: {
      stateUnopened: ShelfLife(fridgeMin: 14, freezer: 30),
      stateOpened: ShelfLife(fridgeMin: 7, freezer: 30),
    },
    source: _srcProcessed,
  ),
  ShelfType(
    key: 'egg',
    label: 'ไข่',
    states: {
      stateRaw: ShelfLife(fridgeMin: 21),
      stateCooked: ShelfLife(fridgeMin: 7),
    },
    noFreeze: true,
    source: _srcProcessed,
  ),
  ShelfType(
    key: 'leftover',
    label: 'อาหารกินเหลือ',
    states: {'': ShelfLife(fridgeMin: 2)},
    source: _srcProcessed,
  ),
  ShelfType(
    key: 'bread',
    label: 'ขนมปัง',
    states: {'': ShelfLife(fridgeMin: 3)},
    source: _srcProcessed,
  ),
  ShelfType(
    key: 'leafy_veg',
    label: 'ผักใบ',
    states: {'': ShelfLife(fridgeMin: 3, fridgeMax: 5)},
    source: _srcProduce,
  ),
  ShelfType(
    key: 'root_veg',
    label: 'ผักหัว',
    states: {'': ShelfLife(fridgeMin: 7, fridgeMax: 15)},
    source: _srcProduce,
  ),
  ShelfType(
    key: 'fruit',
    label: 'ผลไม้',
    states: {'': ShelfLife(fridgeMin: 3, fridgeMax: 15, freezer: 90)},
    source: _srcProduce,
  ),
  ShelfType(
    key: 'milk',
    label: 'นม',
    states: {'': ShelfLife(fridgeMin: 4)},
    source: _srcProduce,
  ),
  ShelfType(
    key: 'yogurt',
    label: 'โยเกิร์ต',
    states: {'': ShelfLife(fridgeMin: 3)},
    source: _srcProduce,
  ),
];

ShelfType? findShelfType(String? key) {
  if (key == null) return null;
  for (final t in shelfTypes) {
    if (t.key == key) return t;
  }
  return null;
}

/// รายการประเภทสำหรับใส่ใน prompt ของ Gemini ให้เลือกว่าวัตถุดิบตรงกับ
/// ประเภทไหน (หรือ "other" ถ้าไม่ตรงกับประเภทไหนเลย)
String shelfTypePromptList() =>
    shelfTypes.map((t) => '${t.key} = ${t.label}').join('\n');

/// จำนวนวันที่เก็บได้ในแต่ละช่อง (ผลลัพธ์หลังรวมตารางกับค่าที่ Gemini ประเมิน)
/// freezerDays = null แปลว่าไม่ควรเก็บในช่องแช่แข็ง
class ResolvedShelfLife {
  final int fridgeDays;
  final int? freezerDays;
  final bool fromTable;

  const ResolvedShelfLife({
    required this.fridgeDays,
    required this.freezerDays,
    required this.fromTable,
  });

  int? daysFor(String storage) =>
      storage == storageFreezer ? freezerDays : fridgeDays;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.round();
  return num.tryParse(v.toString())?.round();
}

/// รวมค่าจากตารางกับค่าที่ Gemini ประเมิน:
/// - ถ้าตารางมีค่าแบบตายตัว ใช้ค่าตาราง
/// - ถ้าตารางเป็นช่วง (เช่น ผักใบ 3-5 วัน) ใช้ค่าของ Gemini แต่บังคับให้อยู่
///   ในช่วงของตาราง (ถ้า Gemini ไม่ให้ค่ามา ใช้ค่าต่ำสุดของช่วงเพื่อความปลอดภัย)
/// - ช่องแช่แข็ง: ถ้าตรงประเภทในตารางแต่ไม่มีข้อมูลช่องแช่แข็ง (เช่น ผัก นม)
///   จะไม่มีตัวเลือกช่องแช่แข็งเลย (freezerDays = null) ไม่ใช้ค่าที่ Gemini เดา
/// - ถ้าไม่ตรงประเภทไหนในตารางเลย ใช้ค่าของ Gemini ทั้งสองช่อง
ResolvedShelfLife resolveShelfLife({
  required String? typeKey,
  required String? state,
  dynamic geminiFridgeDays,
  dynamic geminiFreezerDays,
}) {
  final gFridge = _toInt(geminiFridgeDays);
  final gFreezer = _toInt(geminiFreezerDays);
  final type = findShelfType(typeKey);

  if (type == null) {
    return ResolvedShelfLife(
      fridgeDays: (gFridge != null && gFridge > 0) ? gFridge : 3,
      freezerDays: (gFreezer != null && gFreezer > 0) ? gFreezer : null,
      fromTable: false,
    );
  }

  final rule = type.states[state] ?? type.states.values.first;

  int fridgeDays;
  if (rule.fridgeMin == null) {
    fridgeDays = (gFridge != null && gFridge > 0) ? gFridge : 3;
  } else if (rule.fridgeMax != rule.fridgeMin) {
    fridgeDays = (gFridge ?? rule.fridgeMin!).clamp(
      rule.fridgeMin!,
      rule.fridgeMax!,
    );
  } else {
    fridgeDays = rule.fridgeMin!;
  }

  final int? freezerDays = type.noFreeze ? null : rule.freezer;

  return ResolvedShelfLife(
    fridgeDays: fridgeDays,
    freezerDays: freezerDays,
    fromTable: true,
  );
}

/// สถานะเริ่มต้นของประเภทนั้น ('' ถ้าไม่มีสถานะให้เลือก)
String defaultStateFor(String? typeKey) {
  final type = findShelfType(typeKey);
  if (type == null) return '';
  return type.states.keys.first;
}

/// แปลงจำนวนวันให้อ่านง่าย (เกิน 2 เดือนแสดงเป็นเดือน)
String formatShelfDays(int days) {
  if (days >= 60 && days % 30 == 0) return '${days ~/ 30} เดือน';
  return '$days วัน';
}

/// ที่มาของระยะที่เก็บได้แบบสั้น สำหรับแสดงบนการ์ดเลยโดยไม่ต้องกดดู
/// (ใช้คำที่ผู้ใช้เข้าใจ ไม่พูดถึง "ตาราง" ที่เป็นเรื่องภายในระบบ)
String shelfSourceShort(Map<String, dynamic> item) {
  final key = item['shelf_type']?.toString();
  if (isCustomShelfType(key)) {
    final original = originalShelfSource(key, null).days;
    return original == null
        ? 'คุณกำหนดเอง'
        : 'คุณกำหนดเอง (ค่าแนะนำ ${formatShelfDays(original)})';
  }
  final type = findShelfType(key);
  if (type != null) return 'ข้อมูลจาก ${type.source}';
  if (item['fridge_days'] != null) return 'AI ประเมินให้ ควรตรวจสอบอีกครั้ง';
  return 'ไม่มีข้อมูลระยะที่เก็บได้';
}

/// ชนิดของเมื่อเกินระยะที่เก็บได้แล้ว: ไม่ควรเสี่ยง (ทิ้ง) / ตรวจด้วยตาได้
enum OverdueKind { unsafe, produce, other }

OverdueKind overdueKind(Map<String, dynamic> item) {
  // ของที่ผู้ใช้แก้เอง ใช้ประเภทเดิมก่อนแก้
  final key = originalShelfSource(item['shelf_type']?.toString(), null).key;
  const unsafe = {
    'chicken',
    'beef_pork',
    'ground_meat',
    'offal',
    'fish',
    'shellfish',
    'leftover',
  };
  const produce = {'leafy_veg', 'root_veg', 'fruit'};

  if (findShelfType(key) != null) {
    if (unsafe.contains(key) ||
        (key == 'processed_meat' && item['food_state'] == stateOpened)) {
      return OverdueKind.unsafe;
    }
    if (produce.contains(key)) return OverdueKind.produce;
    return OverdueKind.other;
  }
  // ไม่รู้ประเภท (AI ประเมิน / ของเก่า) ดูจากหมวดหมู่แทน
  final category = item['category']?.toString() ?? '';
  if (category.contains('เนื้อ')) return OverdueKind.unsafe;
  if (category.contains('ผัก') || category.contains('ผลไม้')) {
    return OverdueKind.produce;
  }
  return OverdueKind.other;
}

/// คำแนะนำบนการ์ดเมื่อเกินระยะที่เก็บได้แล้ว แยกตามชนิดของ — เนื้อสัตว์/อาหาร
/// ทะเล/อาหารกินเหลือไม่ควรเสี่ยง ส่วนผักผลไม้ตรวจด้วยตาได้
String overdueAdvice(Map<String, dynamic> item) {
  switch (overdueKind(item)) {
    case OverdueKind.unsafe:
      return 'ไม่ควรกินแล้ว เพื่อความปลอดภัยควรทิ้ง';
    case OverdueKind.produce:
      return 'ลองดูก่อน ถ้าไม่เน่า ไม่เละ ไม่ขึ้นรา ยังใช้ได้';
    case OverdueKind.other:
      return 'ตรวจกลิ่นและสภาพก่อนใช้ ถ้าผิดปกติควรทิ้ง';
  }
}

/// ตรวจแล้วยังใช้ได้ ให้ต่อเวลาได้ไหม — ของที่ไม่ควรเสี่ยงไม่มีปุ่มนี้
bool canExtendOverdue(Map<String, dynamic> item) =>
    overdueKind(item) != OverdueKind.unsafe;
