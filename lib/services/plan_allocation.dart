import 'package:test_app/services/recipe_repository.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/utils/fridge_age.dart';

/// สถานะวัตถุดิบ 1 รายการของมื้อหนึ่ง หลังจองของในตู้เย็นแล้ว
class IngredientStatus {
  final String name;

  /// ข้อความปริมาณตามแพลน เช่น "1 ชิ้น"
  final String quantity;

  /// มีของในตู้พอสำหรับมื้อนี้ (หลังจองให้มื้อก่อนหน้าแล้ว) — ของพื้นฐานถือว่ามีเสมอ
  final bool have;

  /// ขาดอีกเท่าไหร่ (0 = ไม่ขาด) และหน่วยของส่วนที่ขาด
  final num short;
  final String unit;

  const IngredientStatus({
    required this.name,
    required this.quantity,
    required this.have,
    required this.short,
    required this.unit,
  });
}

/// จองวัตถุดิบในตู้เย็นให้มื้ออาหารในแพลน "มื้อที่ใกล้ถึงก่อนได้ก่อน"
///
/// ปัญหาเดิม: ทุกมื้อเทียบกับของทั้งหมดในตู้แยกกัน อกไก่ 1 ชิ้นจึงทำให้ทุกมื้อที่ใช้
/// อกไก่ขึ้นว่ามีของ พอทำมื้อแรกไปแล้ว มื้ออื่นกลายเป็นต้องซื้อ
///
/// วิธีนี้: เรียงมื้อตามวันและมื้อจริง ข้ามมื้อที่ทำแล้ว (หักของไปแล้ว) แล้วไล่จอง
/// ของที่เหลือทีละมื้อ — คำนวณใหม่ทุกครั้งที่เปิดหน้า (ไม่เก็บสถานะไว้ตายตัว)
class PlanAllocation {
  PlanAllocation._();

  static const _dayOrder = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// ลำดับวันนับจากวันที่สร้างแพลน (ตรงกับลำดับที่หน้าแผนรายสัปดาห์แสดง)
  static int _dayRank(String? day, DateTime? planStart) {
    final i = _dayOrder.indexOf(day ?? '');
    if (i < 0) return 99;
    final start = planStart == null ? 0 : planStart.weekday - 1;
    return (i - start + 7) % 7;
  }

  /// "มื้อที่ 2" -> 2, มื้ออื่น (เช่น มื้อเสริม) ไว้ท้ายวัน
  static int mealRank(String? type) {
    final m = RegExp(r'\d+').firstMatch(type ?? '');
    return m == null ? 99 : int.parse(m.group(0)!);
  }

  static bool _sameName(String a, String b) {
    final x = a.trim().toLowerCase(), y = b.trim().toLowerCase();
    return x.isNotEmpty &&
        y.isNotEmpty &&
        (x == y || x.contains(y) || y.contains(x));
  }

  static String _unitOf(String quantityText) =>
      quantityText.replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '').trim();

  /// คืน { meal id: [สถานะวัตถุดิบตามลำดับในมื้อ] } ของทุกมื้อในแพลน
  /// [fridgeItems] ต้องมี name, quantity, unit, use_per_cook (+ คอลัมน์วันที่สำหรับเช็กเกินกำหนด)
  static Map<String, List<IngredientStatus>> allocate({
    required List<dynamic> meals,
    required List<Map<String, dynamic>> fridgeItems,
    DateTime? planStart,
  }) {
    // ของที่ยังใช้ได้ (ไม่หมด ไม่เกินกำหนด) — จำนวนคงเหลือหลังจองแต่ละลอต
    final lots = [
      for (final f in fridgeItems)
        if (!isUsedUp(f) &&
            !isOverdue(f) &&
            (f['name'] ?? '').toString().trim().isNotEmpty)
          {
            'name': f['name'].toString(),
            'unit': (f['unit'] ?? '').toString().trim(),
            'left': RecipeRepository.toNum(f['quantity']),
            'per_cook': RecipeRepository.toNum(f['use_per_cook']),
          },
    ];

    final ordered =
        [
          for (final m in meals)
            if (m is Map) Map<String, dynamic>.from(m),
        ]..sort((a, b) {
          final byDay = _dayRank(
            a['day'],
            planStart,
          ).compareTo(_dayRank(b['day'], planStart));
          if (byDay != 0) return byDay;
          return mealRank(a['meal_type']).compareTo(mealRank(b['meal_type']));
        });

    final result = <String, List<IngredientStatus>>{};
    for (final meal in ordered) {
      final cooked = meal['is_cooked'] == true;
      final statuses = <IngredientStatus>[];
      final raw = meal['ingredients'];
      for (final ing in raw is List ? raw.whereType<Map>() : const <Map>[]) {
        final name = (ing['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final qtyText = (ing['quantity'] ?? '').toString().trim();
        final unit = _unitOf(qtyText);
        // ทำแล้ว (หักของไปแล้ว) หรือของพื้นฐาน -> ถือว่ามี ไม่จองของในตู้
        if (cooked || ShoppingSuggestion.isStaple(name)) {
          statuses.add(
            IngredientStatus(
              name: name,
              quantity: qtyText,
              have: true,
              short: 0,
              unit: unit,
            ),
          );
          continue;
        }

        final matches = lots
            .where((l) => _sameName(l['name'] as String, name))
            .toList();
        // ปริมาณที่มื้อนี้ต้องใช้ ในหน่วยของตู้เย็น
        final fridgeUnit = matches.isEmpty
            ? unit
            : matches.first['unit'] as String;
        final parsed = RecipeRepository.parseQuantity(
          RecipeRepository.leadingNumber(qtyText),
        );
        final perCook = matches.isEmpty ? 0 : matches.first['per_cook'] as num;
        final sameUnit =
            unit.isEmpty || fridgeUnit.isEmpty || unit == fridgeUnit;
        num need;
        if (sameUnit && parsed != null && parsed > 0) {
          need = parsed;
        } else if (fridgeUnit != 'ส่วน' && perCook > 0) {
          need = perCook; // หน่วยไม่ตรง -> ใช้ "ใช้ครั้งละ" ที่ผู้ใช้ตั้งไว้
        } else {
          need = 1;
        }

        // จองจากลอตที่เหลือ (ตามลำดับที่ได้มา)
        var remaining = need;
        for (final l in matches) {
          if (remaining <= 0) break;
          final left = l['left'] as num;
          if (left <= 0) continue;
          final take = left < remaining ? left : remaining;
          l['left'] = left - take;
          remaining -= take;
        }
        statuses.add(
          IngredientStatus(
            name: name,
            quantity: qtyText,
            have: remaining <= 0,
            short: remaining > 0 ? remaining : 0,
            unit: fridgeUnit,
          ),
        );
      }
      final id = meal['id']?.toString();
      if (id != null) result[id] = statuses;
    }
    return result;
  }

  /// รายการซื้อของทั้งสัปดาห์ = รวมส่วนที่ขาดจริงของทุกมื้อ (ชื่อ + หน่วยเดียวกันบวกกัน)
  /// คืน [(ชื่อ, จำนวน, หน่วย, วันที่ใช้)] เรียงตามชื่อ
  static List<({String name, num amount, String unit, List<String> days})>
  shoppingList({
    required List<dynamic> meals,
    required Map<String, List<IngredientStatus>> allocation,
    required String Function(String dayKey) dayLabel,
  }) {
    final totals =
        <String, ({String name, num amount, String unit, List<String> days})>{};
    for (final m in meals) {
      if (m is! Map) continue;
      final statuses = allocation[m['id']?.toString()] ?? const [];
      for (final s in statuses) {
        if (s.have || s.short <= 0) continue;
        final key = '${s.name.toLowerCase()}|${s.unit}';
        final prev = totals[key];
        final day = dayLabel((m['day'] ?? '').toString());
        totals[key] = (
          name: s.name,
          amount: (prev?.amount ?? 0) + s.short,
          unit: s.unit,
          days: [...?prev?.days, if (!(prev?.days.contains(day) ?? false)) day],
        );
      }
    }
    return totals.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
