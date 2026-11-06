import 'package:supabase_flutter/supabase_flutter.dart';

/// นับว่าวัตถุดิบอยู่ในตู้เย็นมาแล้วกี่วัน ตามวันในปฏิทิน (ใส่วันนี้ = 0,
/// ใส่เมื่อวาน = 1) — นับแบบเดียวกับวันหมดอายุ (daysUntilExpiry) เพื่อให้
/// "อยู่มาแล้ว + เก็บได้อีก" เท่ากับ "เก็บได้" เสมอ ผู้ใช้ไม่งง
int daysInFridge(dynamic createdAt) {
  final added = parseCreatedAt(createdAt);
  if (added == null) return 0;
  final diff = _today().difference(_dayOf(added)).inDays;
  return diff < 0 ? 0 : diff;
}

/// แปลงเวลาที่ฐานข้อมูลสร้างให้เอง (created_at) เป็นเวลาเครื่อง — Supabase
/// เก็บ created_at เป็นเวลา UTC แต่ส่งกลับมาโดยไม่มีตัวบอก timezone (ไม่มี Z
/// หรือ +00:00) ถ้า parse ตรงๆ Dart จะเข้าใจว่าเป็นเวลาไทย ทำให้นับเกินไป
/// 7 ชั่วโมง จึงต้องบอกให้ชัดว่าเป็น UTC ก่อนแปลงเป็นเวลาเครื่อง
DateTime? parseCreatedAt(dynamic raw) {
  if (raw == null) return null;
  var text = raw.toString().trim();
  if (text.isEmpty) return null;
  final hasTimezone = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$').hasMatch(text);
  if (!hasTimezone && text.contains(RegExp(r'[T ]\d{2}:'))) text = '${text}Z';
  try {
    return DateTime.parse(text).toLocal();
  } catch (_) {
    return null;
  }
}

/// เวลาที่เอาเข้าตู้เย็น เช่น "23:00 น." — "" ถ้าไม่มีข้อมูล
String addedTimeText(dynamic createdAt) {
  final d = parseCreatedAt(createdAt);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)} น.';
}

/// เข้าตู้เย็นมาแล้วกี่ชั่วโมง
int hoursInFridge(dynamic createdAt) {
  final added = parseCreatedAt(createdAt);
  if (added == null) return 0;
  final diff = DateTime.now().difference(added).inHours;
  return diff < 0 ? 0 : diff;
}

/// อยู่ในตู้เย็นมาแล้วนานเท่าไหร่ แบบสั้น เช่น "อยู่มา 3 วัน" — ถ้าใส่วันนี้
/// บอกเป็นชั่วโมงแทน เช่น "ใส่วันนี้ (5 ชั่วโมงที่แล้ว)" (แสดงชั่วโมงเฉพาะวัน
/// เดียวกัน จึงไม่ขัดกับการนับวันตามปฏิทิน)
String fridgeAgeShort(dynamic createdAt) {
  final days = daysInFridge(createdAt);
  final yesterday = _yesterdayHours(createdAt, days);
  if (yesterday != null) return 'ใส่เมื่อวาน ($yesterday ชั่วโมงที่แล้ว)';
  if (days > 0) return 'อยู่มา $days วัน';
  final hours = hoursInFridge(createdAt);
  if (hours < 1) return 'ใส่วันนี้ (เพิ่งใส่)';
  return 'ใส่วันนี้ ($hours ชั่วโมงที่แล้ว)';
}

/// ใส่เมื่อวานแต่ยังไม่ครบ 24 ชั่วโมง (เช่น ใส่ 18:00 ดูตอนเที่ยงคืน) — คืน
/// จำนวนชั่วโมง ไม่งั้น null การนับวันยังเป็นตามปฏิทิน (= 1 วัน) เหมือนเดิม
/// แค่เปลี่ยนคำให้ไม่ดูเหมือนอยู่มานานเกินจริง
int? _yesterdayHours(dynamic createdAt, int days) {
  if (days != 1) return null;
  final hours = hoursInFridge(createdAt);
  return hours < 24 ? hours : null;
}

/// ข้อความเต็ม ใช้แสดงผลในหน้าคลังและหน้ารายละเอียด
String fridgeAgeText(dynamic createdAt) {
  final days = daysInFridge(createdAt);
  final yesterday = _yesterdayHours(createdAt, days);
  if (yesterday != null)
    return 'ใส่ตู้เย็นเมื่อวาน ($yesterday ชั่วโมงที่แล้ว)';
  if (days > 0) return 'อยู่ในตู้เย็นมาแล้ว $days วัน';
  final hours = hoursInFridge(createdAt);
  if (hours < 1) return 'ใส่ตู้เย็นวันนี้ (เพิ่งใส่)';
  return 'ใส่ตู้เย็นวันนี้ ($hours ชั่วโมงที่แล้ว)';
}

/// เหลืออีกกี่วันจะหมดอายุ นับเป็นวันตามปฏิทิน (หมดอายุวันนี้ = 0,
/// พรุ่งนี้ = 1, หมดอายุไปแล้ว = ติดลบ) — null ถ้าไม่มีวันหมดอายุ
int? daysUntilExpiry(dynamic expiryDate) {
  final expiry = _parseLocal(expiryDate);
  if (expiry == null) return null;
  return _dayOf(expiry).difference(_today()).inDays;
}

/// ข้อความป้ายบนการ์ด — ใช้คำเดียวกับทั้งแอป ("เก็บได้อีก X วัน" / "ครบกำหนด
/// วันนี้" / "เกินมาแล้ว X วัน") แทนคำว่า "หมดอายุ"
String expiryText(int days) => daysLeftText(days);

/// ของที่ใช้หมดแล้ว (เหลือ 0 ชิ้น) ไม่ต้องนับ/เตือน เพราะไม่มีของเหลือแล้ว
/// (ของที่ไม่มีระบุจำนวนไว้ ให้ถือว่ายังมีของอยู่ตามเดิม)
bool isUsedUp(Map<String, dynamic> item) {
  final qty = item['quantity'];
  if (qty == null) return false;
  final qtyNum = qty is num ? qty : num.tryParse(qty.toString());
  return qtyNum != null && qtyNum <= 0;
}

/// ลำดับแบบ FIFO: ลอตที่ใกล้หมดอายุที่สุดมาก่อน (ไม่มีวันหมดอายุไว้ท้ายสุด)
/// ถ้าหมดอายุวันเดียวกัน ลอตที่เข้าตู้เย็นก่อนมาก่อน — ใช้ทั้งตอนแสดงผลใน
/// หน้าเช็คตู้เย็นและตอนเลือกลอตที่จะหักตอนทำอาหาร
int compareFifo(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ea = daysLeft(a);
  final eb = daysLeft(b);
  if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
  if (ea == null && eb != null) return 1;
  if (ea != null && eb == null) return -1;
  return daysInFridge(b['created_at']).compareTo(daysInFridge(a['created_at']));
}

DateTime? _parseLocal(dynamic raw) {
  if (raw == null) return null;
  try {
    return DateTime.parse(raw.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _today() => _dayOf(DateTime.now());

/// ค่าเริ่มต้นของ "แจ้งเตือนล่วงหน้ากี่วันก่อนครบอายุการเก็บรักษา" ถ้าผู้ใช้
/// ยังไม่เคยตั้งค่าไว้ในหน้า notification_settings_screen.dart
const int defaultOldItemDays = 1;

/// อ่านค่า "แจ้งเตือนล่วงหน้ากี่วันก่อนครบอายุการเก็บรักษา" (notify_days) ที่
/// ผู้ใช้ตั้งไว้ใน user_metadata ของ Supabase Auth — ใช้กับการแจ้งเตือน push
int readOldItemDays(User? user) {
  final saved = user?.userMetadata?['notify_days'];
  if (saved is int) return saved;
  if (saved != null) {
    return int.tryParse(saved.toString()) ?? defaultOldItemDays;
  }
  return defaultOldItemDays;
}

/// เวลาเริ่มต้นที่จะแจ้งเตือนในแต่ละวัน ถ้าผู้ใช้ยังไม่ได้ตั้งเอง (09:00)
const int defaultNotifyHour = 9;
const int defaultNotifyMinute = 0;

/// อ่านเวลาที่ผู้ใช้อยากรับแจ้งเตือน (notify_time รูปแบบ "HH:mm") จาก
/// user_metadata ของ Supabase Auth — ยังไม่ได้ตั้ง/อ่านไม่ออก = 09:00
({int hour, int minute}) readNotifyTime(User? user) {
  final saved = user?.userMetadata?['notify_time']?.toString() ?? '';
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(saved.trim());
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h < 24 && min < 60) return (hour: h, minute: min);
  }
  return (hour: defaultNotifyHour, minute: defaultNotifyMinute);
}

/// "HH:mm" สำหรับเก็บลง user_metadata และแสดงผล
String notifyTimeText(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// อายุการเก็บรักษา (วัน) ของวัตถุดิบชิ้นนี้ตามช่องที่เก็บ — null ถ้าไม่มีข้อมูล
num? shelfDaysOf(Map<String, dynamic> item) {
  final raw = item['storage'] == 'freezer'
      ? item['freezer_days']
      : item['fridge_days'];
  final days = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  return (days == null || days <= 0) ? null : days;
}

/// เวลาที่เริ่มนับวันของช่องที่เก็บอยู่ตอนนี้ — ย้ายช่องแล้วนับจากวันที่ย้าย
dynamic storageStartOf(Map<String, dynamic> item) =>
    item['storage_changed_at'] ?? item['created_at'];

/// จำนวนวันที่เหลือตอนเอาเข้าช่องแช่แข็งครั้งล่าสุด (ติดลบ = เกินกำหนดก่อนแช่)
int? _daysLeftAtFreeze(Map<String, dynamic> item) {
  final raw = item['days_left_at_freeze'];
  return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
}

/// ระยะที่เก็บได้จริงในช่องปัจจุบัน — ของที่ย้ายออกจากช่องแช่แข็งเก็บได้ไม่เกิน
/// จำนวนวันที่เหลือตอนแช่ เพราะความเย็นแค่หยุดเวลา ไม่ได้ทำให้ของกลับมาสดใหม่
num? effectiveShelfDays(Map<String, dynamic> item) {
  final shelf = shelfDaysOf(item);
  if (shelf == null) return null;
  final atFreeze = _daysLeftAtFreeze(item);
  if (item['storage'] == 'freezer' || atFreeze == null) return shelf;
  return shelf < atFreeze ? shelf : atFreeze;
}

/// ระยะที่เก็บได้สำหรับแสดงผล — null ถ้าไม่มีข้อมูลหรือไม่เหลือวันแล้ว
num? displayShelfDays(Map<String, dynamic> item) {
  final days = effectiveShelfDays(item);
  return (days == null || days <= 0) ? null : days;
}

/// ค่าที่ต้องบันทึกเมื่อย้ายไปช่อง [target] ('fridge' หรือ 'freezer')
Map<String, dynamic> storageMoveFields(
  Map<String, dynamic> item,
  String target,
) {
  final now = DateTime.now();
  final fields = <String, dynamic>{
    'storage': target,
    'storage_changed_at': now.toUtc().toIso8601String(),
    if (target == 'freezer')
      'days_left_at_freeze': daysLeft(item)
    else
      'thawed_at': now.toUtc().toIso8601String(),
  };
  final moved = {...item, ...fields};
  if (shelfDaysOf(moved) != null) {
    fields['expiry_date'] = now
        .add(Duration(days: daysLeft(moved)!))
        .toUtc()
        .toIso8601String();
  }
  return fields;
}

/// เก็บได้อีกกี่วันถ้าย้ายไปช่อง [target] ตอนนี้ — ใช้แสดงก่อนผู้ใช้ตัดสินใจ
int? daysLeftAfterMove(Map<String, dynamic> item, String target) =>
    daysLeft({...item, ...storageMoveFields(item, target)});

// ---------------------------------------------------------------------------
// นับเป็นวันอย่างเดียว (ไม่ใช้เปอร์เซ็นต์): เก็บได้อีก X วัน → ครบกำหนดวันนี้ →
// เกินมาแล้ว X วัน ใช้เหมือนกันทุกหน้า (เมนูอาหาร แพลน แจ้งเตือน push)
// ---------------------------------------------------------------------------

/// เก็บได้อีกกี่วัน = ระยะที่เก็บได้ − จำนวนวันที่อยู่ในช่องปัจจุบันมาแล้ว (ตาม
/// วันในปฏิทิน) — คำนวณที่เดียวเสมอ ทุกหน้า (คลัง เมนูอาหาร แพลน แจ้งเตือน) จึง
/// ตรงกัน (1 = พรุ่งนี้, 0 = ครบกำหนดวันนี้, ติดลบ = เกินมาแล้ว)
/// ของที่เกินกำหนดก่อนแช่แข็งยังถือว่าเกินกำหนด การแช่แข็งไม่ทำให้กลับมาปลอดภัย
/// ของเก่าที่ไม่มีข้อมูลระยะที่เก็บได้ ใช้วันหมดอายุที่บันทึกไว้แทน
/// — null ถ้าไม่มีข้อมูลเลย
int? daysLeft(Map<String, dynamic> item) {
  final atFreeze = _daysLeftAtFreeze(item);
  if (item['storage'] == 'freezer' && atFreeze != null && atFreeze < 0) {
    return atFreeze;
  }
  final shelf = effectiveShelfDays(item);
  final start = storageStartOf(item);
  if (shelf != null && start != null) {
    return shelf.floor() - daysInFridge(start);
  }
  return daysUntilExpiry(item['expiry_date']);
}

/// วันหมดอายุ (วันในปฏิทิน) คิดแบบเดียวกับ daysLeft — ใช้แสดงวันที่ในหน้า
/// รายละเอียด จะได้ตรงกับ "เก็บได้อีก X วัน" เสมอ
DateTime? expiryDayOf(Map<String, dynamic> item) {
  final left = daysLeft(item);
  if (left == null) return null;
  return _today().add(Duration(days: left));
}

/// "เก็บได้อีก 3 วัน" / "ครบกำหนดวันนี้" / "เกินมาแล้ว 2 วัน"
String daysLeftText(int left) {
  if (left > 0) {
    if (left >= 60) return 'เก็บได้อีก ${left ~/ 30} เดือน';
    return 'เก็บได้อีก $left วัน';
  }
  if (left == 0) return 'ครบกำหนดวันนี้';
  return 'เกินมาแล้ว ${-left} วัน';
}

/// เกินระยะที่เก็บได้แล้ว — ไม่ควรเอาไปทำอาหาร (ไม่ส่งให้ AI ใช้)
bool isOverdue(Map<String, dynamic> item) {
  final left = daysLeft(item);
  return left != null && left < 0;
}

/// ควรเอาไปทำอาหารก่อน: เหลือไม่เกิน [aheadDays] วัน (ค่า "แจ้งเตือนล่วงหน้า"
/// ที่ผู้ใช้ตั้งไว้) และยังไม่เกินกำหนด
bool shouldUseFirst(Map<String, dynamic> item, int aheadDays) {
  if (item['created_at'] == null || isUsedUp(item)) return false;
  final left = daysLeft(item);
  return left != null && left >= 0 && left <= aheadDays;
}

/// ถึงเวลาแจ้งเตือนแล้วหรือยัง — เหลือไม่เกิน [aheadDays] วัน (รวมของที่เกิน
/// กำหนดแล้วด้วย ผู้ใช้จะได้รู้และจัดการ)
bool isDueForReminder(Map<String, dynamic> item, int aheadDays) {
  if (item['created_at'] == null || isUsedUp(item)) return false;
  final left = daysLeft(item);
  return left != null && left <= aheadDays;
}

/// ข้อความในการแจ้งเตือน เช่น "ควรใช้ภายในพรุ่งนี้"
String useWithinText(num remainingDays) {
  final d = remainingDays.floor();
  if (d <= 0) return 'ควรใช้วันนี้';
  if (d == 1) return 'ควรใช้ภายในพรุ่งนี้';
  return 'ควรใช้ภายใน $d วัน';
}

/// เรียงของที่เก็บได้อีกน้อยวันที่สุดขึ้นก่อน (เกินกำหนดมาก่อนสุด ไม่มีข้อมูล
/// ไว้ท้าย) ถ้าเท่ากัน ของที่อยู่ในตู้เย็นนานกว่าขึ้นก่อน
int compareDaysLeft(Map<String, dynamic> a, Map<String, dynamic> b) {
  final la = daysLeft(a);
  final lb = daysLeft(b);
  if (la != null && lb != null && la != lb) return la.compareTo(lb);
  if (la == null && lb != null) return 1;
  if (la != null && lb == null) return -1;
  return hoursInFridge(
    b['created_at'],
  ).compareTo(hoursInFridge(a['created_at']));
}
