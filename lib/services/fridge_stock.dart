import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/utils/fridge_age.dart';
import 'package:test_app/utils/shelf_life.dart';
import 'package:test_app/services/non_food_check.dart';

/// ผลการหักวัตถุดิบ 1 รายการ
class DeductResult {
  /// เจอวัตถุดิบที่ชื่อตรงกันในตู้เย็นอย่างน้อย 1 ลอตหรือไม่
  final bool found;

  /// error จริงตอนอัปเดตฐานข้อมูล (เช่นโดนบล็อกสิทธิ์) — null ถ้าสำเร็จ
  final String? error;

  const DeductResult({required this.found, this.error});
}

num _toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

/// เทียบชื่อแบบยืดหยุ่น (ตัดช่องว่าง/ตัวพิมพ์เล็กใหญ่ และยอมให้ชื่อฝั่งหนึ่ง
/// เป็นส่วนหนึ่งของอีกฝั่ง) เพราะชื่อที่ AI ตอบกลับมาอาจไม่ตรงเป๊ะกับในคลัง
bool ingredientNameMatches(dynamic inventoryName, String neededName) {
  final invName = (inventoryName ?? '').toString().trim().toLowerCase();
  final name = neededName.trim().toLowerCase();
  if (invName.isEmpty || name.isEmpty) return false;
  return invName == name || invName.contains(name) || name.contains(invName);
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
  required List<Map<String, dynamic>> inventory,
  required String name,
  required num amount,
}) async {
  final lots =
      inventory
          .where(
            (lot) =>
                ingredientNameMatches(lot['name'], name) &&
                _toNum(lot['quantity']) > 0,
          )
          .toList()
        ..sort(compareFifo);

  if (lots.isEmpty) return const DeductResult(found: false);
  if (amount <= 0) return const DeductResult(found: true);

  num remaining = amount;
  try {
    for (final lot in lots) {
      if (remaining <= 0) break;
      final current = _toNum(lot['quantity']);
      final take = current < remaining ? current : remaining;
      final left = current - take;
      remaining -= take;

      if (left <= 0) {
        await supabase
            .from('fridge_items')
            .delete()
            .eq('item_id', lot['item_id']);
        inventory.remove(lot);
      } else {
        await supabase
            .from('fridge_items')
            .update({'quantity': left})
            .eq('item_id', lot['item_id']);
        lot['quantity'] = left;
      }
    }
  } catch (e) {
    return DeductResult(found: true, error: e.toString());
  }

  return const DeductResult(found: true);
}

/// ปริมาณคงเหลือรวมของวัตถุดิบชื่อนี้จากทุกลอตในตู้เย็น (ซื้อซ้ำจะถูกแยกเป็น
/// คนละลอต ต้องรวมทุกลอตก่อนเช็คว่ามีพอใช้ไหม)
num availableQuantity(List<Map<String, dynamic>> inventory, String name) {
  return inventory
      .where((lot) => ingredientNameMatches(lot['name'], name))
      .fold<num>(0, (sum, lot) => sum + _toNum(lot['quantity']));
}

/// รายการวัตถุดิบสำหรับใส่ใน prompt ของ Gemini — รวมลอตที่ชื่อและหน่วยเดียวกัน
/// เป็นรายการเดียว และไม่เอาของที่ใช้หมดแล้วมาเสนอให้ AI ใช้
/// [withPerCook] = ใส่ "ใช้ครั้งละ" ของวัตถุดิบที่นับเป็นชิ้นด้วย (ใช้กับหน้าแนะนำเมนู
/// ส่วนแผนอาหารไม่ใส่ เพราะ AI ต้องกำหนดสัดส่วนเองตามโภชนาการที่ผู้ใช้ตั้ง)
String inventoryPromptList(
  List<Map<String, dynamic>> inventory, {
  bool withPerCook = false,
}) {
  final totals = <String, num>{};
  // นับเป็นชิ้น: ผู้ใช้ตั้งไว้ว่าทำอาหาร 1 ครั้งใช้กี่ชิ้น ("ใช้ครั้งละ")
  final perCook = <String, num>{};
  for (final lot in inventory) {
    if (isUsedUp(lot)) continue;
    // บุหรี่ / สุราสำหรับดื่ม ไม่ส่งให้ AI เอาไปทำเมนู (ตรวจจากชื่อปัจจุบัน)
    if (NonFoodCheck.isNotForCooking(lot['name'])) continue;
    final key = "${lot['name']}|${lot['unit'] ?? ''}";
    totals[key] = (totals[key] ?? 0) + _toNum(lot['quantity']);
    final per = _toNum(lot['use_per_cook']);
    if (per > 0 && !perCook.containsKey(key)) perCook[key] = per;
  }
  return totals.entries
      .map((e) {
        final parts = e.key.split('|');
        final qty = e.value == e.value.roundToDouble()
            ? e.value.toInt().toString()
            : e.value.toStringAsFixed(1);
        final per = perCook[e.key];
        // เช่น "ไข่ไก่ (10 ฟอง, ใช้ครั้งละ 2 ฟอง)"
        final perText = !withPerCook || per == null || parts[1] == 'ส่วน'
            ? ''
            : ", ใช้ครั้งละ ${per == per.roundToDouble() ? per.toInt() : per} ${parts[1]}";
        return "${parts[0]} ($qty ${parts[1]}$perText)";
      })
      .join(", ");
}

/// ผู้ใช้ตรวจแล้วว่ายังใช้ได้ ต่อเวลาให้ "เก็บได้อีก [moreDays] วัน" นับจากวันนี้
/// — ปรับระยะที่เก็บได้ของช่องที่เก็บอยู่ = จำนวนวันที่อยู่มาแล้ว + [moreDays]
/// วันหมดอายุเลื่อนตาม และบันทึกที่มาเป็น "คุณกำหนดเอง" (จำค่าแนะนำเดิมไว้)
/// ของเก่าที่ไม่มีข้อมูลระยะที่เก็บได้ เลื่อนแค่วันหมดอายุ
Future<void> extendShelfLife({
  required SupabaseClient supabase,
  required Map<String, dynamic> item,
  required int moreDays,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final fields = <String, dynamic>{
    'expiry_date': today
        .add(Duration(days: moreDays, hours: 12))
        .toUtc()
        .toIso8601String(),
  };

  final current = shelfDaysOf(item);
  if (current != null && storageStartOf(item) != null) {
    final newDays = daysInFridge(storageStartOf(item)) + moreDays;
    final original = originalShelfSource(
      item['shelf_type']?.toString(),
      current,
    );
    fields[item['storage'] == storageFreezer ? 'freezer_days' : 'fridge_days'] =
        newDays;
    // ผู้ใช้ต่อเวลาเอง ค่าที่กำหนดนี้แทนจำนวนวันที่จำไว้ตอนแช่แข็ง
    fields['days_left_at_freeze'] = null;
    fields['shelf_type'] = (original.days != null && newDays == original.days)
        ? original.key
        : customShelfType(original.key, original.days);
  }

  await supabase
      .from('fridge_items')
      .update(fields)
      .eq('item_id', item['item_id']);
}
