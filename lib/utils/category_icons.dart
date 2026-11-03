/// รายการหมวดหมู่ที่กำหนดตายตัวไว้ตั้งแต่แรก (Fixed Set) — เป็นต้นแบบเดียวที่
/// ทุกจุดในแอปต้องใช้ร่วมกัน ห้ามให้ AI (ตอนสแกน) หรือผู้ใช้ (ตอนแก้ไข) พิมพ์ชื่อ
/// หมวดหมู่เป็นข้อความอิสระได้อีก เพราะจะทำให้เกิดหมวดหมู่แปลกๆ ซ้ำซ้อนไม่มีที่สิ้นสุด
/// ในหน้าคลัง (ปัญหาที่เจอมาก่อนแก้ไขนี้)
const List<String> fixedCategories = [
  'ผัก',
  'ผลไม้',
  'เนื้อสัตว์',
  'แป้ง/ข้าว',
  'นม/เครื่องดื่ม',
  'ขนม',
  'อื่นๆ',
];

/// แปลงข้อความหมวดหมู่ที่อาจไม่ตรงเป๊ะ (เช่น AI ตอบมาไม่ตรงรูปแบบ หรือข้อมูลเก่า
/// ก่อนแก้ไขนี้ที่ยังเป็นข้อความอิสระ) ให้เข้าเซ็ตที่กำหนดไว้เสมอ เป็นตัวกันเหนียว
/// ชั้นสุดท้ายก่อนบันทึกลง Supabase หรือแสดงผล
String normalizeCategory(String raw) {
  final c = raw.trim();
  if (fixedCategories.contains(c)) return c;
  if (c.contains('ผลไม้')) return 'ผลไม้';
  if (c.contains('ผัก')) return 'ผัก';
  if (c.contains('เนื้อ') ||
      c.contains('หมู') ||
      c.contains('ไก่') ||
      c.contains('ปลา') ||
      c.contains('กุ้ง') ||
      c.contains('อาหารทะเล')) {
    return 'เนื้อสัตว์';
  }
  if (c.contains('แป้ง') || c.contains('ข้าว')) return 'แป้ง/ข้าว';
  if (c.contains('เครื่องดื่ม') || c.contains('น้ำ') || c.contains('นม')) {
    return 'นม/เครื่องดื่ม';
  }
  if (c.contains('ขนม')) return 'ขนม';
  return 'อื่นๆ';
}

/// อิโมจิของแต่ละหมวดหมู่วัตถุดิบ — ให้ตรงกันทุกหน้า (ตามหน้า "คลัง"/Inventory
/// ซึ่งเป็นต้นแบบ) ห้ามให้แต่ละหน้ามีชุด mapping ของตัวเองแยกกันอีก
/// ใช้: หน้าคลัง, หน้าผลลัพธ์หลังสแกน, หน้าถ่ายรูปวัตถุดิบ (วัตถุดิบที่เพิ่มล่าสุด)
String categoryEmoji(String category) {
  if (category.contains('ผลไม้')) return '🍎';
  if (category.contains('ผัก')) return '🥕';
  if (category.contains('เนื้อ') ||
      category.contains('หมู') ||
      category.contains('ไก่')) {
    return '🥩';
  }
  if (category.contains('แป้ง') || category.contains('ข้าว')) return '🍞';
  if (category.contains('เครื่องดื่ม') ||
      category.contains('น้ำ') ||
      category.contains('นม')) {
    return '🥛';
  }
  if (category.contains('ขนม')) return '🍬';
  return '📦';
}
