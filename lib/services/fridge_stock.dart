import 'package:supabase_flutter/supabase_flutter.dart'; // ใช้ฐานข้อมูล

import 'package:test_app/utils/fridge_age.dart'; // นับวันที่อยู่ในตู้ / เรียงลำดับ FIFO
import 'package:test_app/utils/shelf_life.dart'; // อายุการเก็บ
import 'package:test_app/services/non_food_check.dart'; // ตรวจของที่ไม่ใช่อาหาร

/// ผลการหักวัตถุดิบ 1 รายการ
class DeductResult {
  /// เจอวัตถุดิบที่ชื่อตรงกันในตู้เย็นอย่างน้อย 1 ลอตหรือไม่
  final bool found;

  /// error จริงตอนอัปเดตฐานข้อมูล (เช่นโดนบล็อกสิทธิ์) — null ถ้าสำเร็จ
  final String? error;

  const DeductResult({required this.found, this.error});
}

// ตัวช่วยแปลงค่าอะไรก็ได้ให้เป็นตัวเลข (แปลงไม่ได้ = 0)
num _toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

/// เทียบชื่อแบบยืดหยุ่น (ตัดช่องว่าง/ตัวพิมพ์เล็กใหญ่ และยอมให้ชื่อฝั่งหนึ่ง
/// เป็นส่วนหนึ่งของอีกฝั่ง) เพราะชื่อที่ AI ตอบกลับมาอาจไม่ตรงเป๊ะกับในคลัง
bool ingredientNameMatches(dynamic inventoryName, String neededName) {
  final invName = (inventoryName ?? '').toString().trim().toLowerCase(); // ชื่อในตู้
  final name = neededName.trim().toLowerCase(); // ชื่อที่ต้องการ
  if (invName.isEmpty || name.isEmpty) return false; // ชื่อว่าง = ไม่ตรง
  return invName == name || invName.contains(name) || name.contains(invName); // ตรงกัน หรือฝั่งหนึ่งอยู่ในอีกฝั่ง
}

/// หักวัตถุดิบตามสัดส่วน (Portion-based Deduction) แบบ FIFO: ดึงจากลอตที่ใกล้
/// หมดอายุที่สุด/เก่าที่สุดก่อน ถ้าลอตนั้นไม่พอก็หักลอตถัดไปต่อจนครบ ลอตที่
/// ใช้หมดแล้วจะถูกลบออกจากตู้เย็น
///
/// [inventory] จะถูกอัปเดตจำนวนตามไปด้วย (ลอตที่หมดจะถูกเอาออกจากลิสต์) เพื่อ
/// ให้การหักวัตถุดิบชื่อเดียวกันซ้ำในเมนูเดียวกันเห็นจำนวนล่าสุดเสมอ
///
/// หมายเหตุ: คอลัมน์ quantity ใน Supabase ต้องเป็นชนิด numeric/decimal ถึงจะ
/// รับค่าทศนิยมได้ (เช่นใช้ไป 0.5 หัว) — ถ้ายังเป็น integer อยู่ ต้องรัน
/// `alter table fridge_items alter column quantity type numeric;` ก่อน
Future<DeductResult> deductIngredientFifo({
  required SupabaseClient supabase,
  required List<Map<String, dynamic>> inventory, // ของทั้งหมดในตู้
  required String name, // ชื่อวัตถุดิบที่จะหัก
  required num amount, // จำนวนที่จะหัก
}) async {
  // หาลอตที่ชื่อตรงและยังเหลืออยู่ แล้วเรียงให้ลอตที่ควรใช้ก่อนอยู่หน้าสุด
  final lots =
      inventory
          .where(
            (lot) =>
                ingredientNameMatches(lot['name'], name) &&
                _toNum(lot['quantity']) > 0,
          )
          .toList()
        ..sort(compareFifo); // เรียงแบบ FIFO (ใกล้หมดอายุ/เก่าสุดก่อน)

  if (lots.isEmpty) return const DeductResult(found: false); // ไม่มีของชิ้นนี้ในตู้
  if (amount <= 0) return const DeductResult(found: true); // ไม่ต้องหักอะไร

  num remaining = amount; // จำนวนที่ยังต้องหักอีก
  try {
    for (final lot in lots) { // ไล่หักทีละลอต
      if (remaining <= 0) break; // หักครบแล้ว หยุด
      final current = _toNum(lot['quantity']); // ลอตนี้มีเท่าไหร่
      final take = current < remaining ? current : remaining; // หักได้เท่าที่ลอตมี หรือเท่าที่ต้องการ (อันที่น้อยกว่า)
      final left = current - take; // เหลือในลอตนี้
      remaining -= take; // ลดจำนวนที่ต้องหักลง

      if (left <= 0) { // ลอตนี้หมดแล้ว
        await supabase
            .from('fridge_items')
            .delete() // ลบออกจากฐานข้อมูล
            .eq('item_id', lot['item_id']);
        inventory.remove(lot); // เอาออกจากลิสต์ในเครื่องด้วย
      } else { // ยังเหลืออยู่
        await supabase
            .from('fridge_items')
            .update({'quantity': left}) // อัปเดตจำนวนคงเหลือ
            .eq('item_id', lot['item_id']);
        lot['quantity'] = left; // อัปเดตในลิสต์ในเครื่องด้วย
      }
    }
  } catch (e) {
    return DeductResult(found: true, error: e.toString()); // บันทึกไม่สำเร็จ ส่ง error กลับ
  }

  return const DeductResult(found: true); // สำเร็จ
}

/// ปริมาณคงเหลือรวมของวัตถุดิบชื่อนี้จากทุกลอตในตู้เย็น (ซื้อซ้ำจะถูกแยกเป็น
/// คนละลอต ต้องรวมทุกลอตก่อนเช็คว่ามีพอใช้ไหม)
num availableQuantity(List<Map<String, dynamic>> inventory, String name) {
  return inventory
      .where((lot) => ingredientNameMatches(lot['name'], name)) // เลือกลอตที่ชื่อตรง
      .fold<num>(0, (sum, lot) => sum + _toNum(lot['quantity'])); // บวกจำนวนรวมกัน
}

/// รายการวัตถุดิบสำหรับใส่ใน prompt ของ Gemini — รวมลอตที่ชื่อและหน่วยเดียวกัน
/// เป็นรายการเดียว และไม่เอาของที่ใช้หมดแล้วมาเสนอให้ AI ใช้
/// [withPerCook] = ใส่ "ใช้ครั้งละ" ของวัตถุดิบที่นับเป็นชิ้นด้วย (ใช้กับหน้าแนะนำเมนู
/// ส่วนแผนอาหารไม่ใส่ เพราะ AI ต้องกำหนดสัดส่วนเองตามโภชนาการที่ผู้ใช้ตั้ง)
String inventoryPromptList(
  List<Map<String, dynamic>> inventory, {
  bool withPerCook = false,
}) {
  final totals = <String, num>{}; // รวมจำนวน: key = "ชื่อ|หน่วย"
  // นับเป็นชิ้น: ผู้ใช้ตั้งไว้ว่าทำอาหาร 1 ครั้งใช้กี่ชิ้น ("ใช้ครั้งละ")
  final perCook = <String, num>{};
  for (final lot in inventory) { // ไล่ทุกลอต
    if (isUsedUp(lot)) continue; // ใช้หมดแล้ว ข้าม
    // บุหรี่ / สุราสำหรับดื่ม ไม่ส่งให้ AI เอาไปทำเมนู (ตรวจจากชื่อปัจจุบัน)
    if (NonFoodCheck.isNotForCooking(lot['name'])) continue;
    final key = "${lot['name']}|${lot['unit'] ?? ''}"; // จับกลุ่มด้วยชื่อ+หน่วย
    totals[key] = (totals[key] ?? 0) + _toNum(lot['quantity']); // บวกจำนวนเข้ากลุ่ม
    final per = _toNum(lot['use_per_cook']); // ใช้ครั้งละเท่าไหร่
    if (per > 0 && !perCook.containsKey(key)) perCook[key] = per; // จำค่าแรกที่เจอ
  }
  return totals.entries
      .map((e) {
        final parts = e.key.split('|'); // แยก [ชื่อ, หน่วย]
        final qty = e.value == e.value.roundToDouble()
            ? e.value.toInt().toString() // จำนวนเต็ม แสดงไม่มีทศนิยม
            : e.value.toStringAsFixed(1); // มีทศนิยม แสดง 1 ตำแหน่ง
        final per = perCook[e.key];
        // เช่น "ไข่ไก่ (10 ฟอง, ใช้ครั้งละ 2 ฟอง)"
        final perText = !withPerCook || per == null || parts[1] == 'ส่วน'
            ? ''
            : ", ใช้ครั้งละ ${per == per.roundToDouble() ? per.toInt() : per} ${parts[1]}";
        return "${parts[0]} ($qty ${parts[1]}$perText)"; // ประกอบเป็นข้อความ 1 รายการ
      })
      .join(", "); // ต่อทุกรายการคั่นด้วยจุลภาค
}

/// ผู้ใช้ตรวจแล้วว่ายังใช้ได้ ต่อเวลาให้ "เก็บได้อีก [moreDays] วัน" นับจากวันนี้
/// — ปรับระยะที่เก็บได้ของช่องที่เก็บอยู่ = จำนวนวันที่อยู่มาแล้ว + [moreDays]
/// วันหมดอายุเลื่อนตาม และบันทึกที่มาเป็น "คุณกำหนดเอง" (จำค่าแนะนำเดิมไว้)
/// ของเก่าที่ไม่มีข้อมูลระยะที่เก็บได้ เลื่อนแค่วันหมดอายุ
Future<void> extendShelfLife({
  required SupabaseClient supabase,
  required Map<String, dynamic> item, // วัตถุดิบที่จะต่อเวลา
  required int moreDays, // ต่ออีกกี่วัน
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day); // วันนี้ตอนเที่ยงคืน (ตัดเวลาออก)
  final fields = <String, dynamic>{ // ค่าที่จะอัปเดต
    'expiry_date': today
        .add(Duration(days: moreDays, hours: 12)) // วันหมดใหม่ = วันนี้ + N วัน (บวก 12 ชม. กันปัญหาเขตเวลา)
        .toUtc()
        .toIso8601String(),
  };

  final current = shelfDaysOf(item); // ระยะเก็บได้ปัจจุบัน
  if (current != null && storageStartOf(item) != null) { // มีข้อมูลครบถึงจะปรับระยะเก็บได้
    final newDays = daysInFridge(storageStartOf(item)) + moreDays; // ระยะใหม่ = อยู่มาแล้ว + ต่อเพิ่ม
    final newShelfType = shelfTypeForDays(item, newDays); // ที่มาของค่าใหม่
    fields[item['storage'] == storageFreezer ? 'freezer_days' : 'fridge_days'] =
        newDays; // บันทึกลงช่องที่เก็บอยู่ (แช่แข็ง/ช่องเย็น)
    // ผู้ใช้ต่อเวลาเอง ค่าที่กำหนดนี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
    fields['days_left_at_freeze'] = null;
    fields['shelf_type'] = newShelfType; // เท่าค่าแนะนำ = ที่มาเดิม, ไม่งั้นติดป้าย "กำหนดเอง"
  }

  await supabase
      .from('fridge_items')
      .update(fields) // บันทึกลงฐานข้อมูล
      .eq('item_id', item['item_id']);
}
