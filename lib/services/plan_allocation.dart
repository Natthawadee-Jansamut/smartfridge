import 'package:test_app/services/recipe_repository.dart'; // ตัวช่วยแปลงตัวเลข/ปริมาณ
import 'package:test_app/services/shopping_suggestion.dart'; // เช็คของพื้นฐาน (ข้าว น้ำมัน ฯลฯ)
import 'package:test_app/utils/fridge_age.dart'; // เช็คของหมด/เกินกำหนด

/// สถานะวัตถุดิบ 1 รายการของมื้อหนึ่ง หลังจองของในตู้เย็นแล้ว
class IngredientStatus {
  final String name; // ชื่อวัตถุดิบ

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
  PlanAllocation._(); // ห้ามสร้างตัวแปรจากคลาสนี้

  // ลำดับวันในสัปดาห์ (ชื่อตรงกับที่บันทึกในฐานข้อมูล)
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
    final i = _dayOrder.indexOf(day ?? ''); // วันนี้อยู่ลำดับที่เท่าไหร่ (จันทร์=0)
    if (i < 0) return 99; // ชื่อวันไม่รู้จัก ไว้ท้ายสุด
    final start = planStart == null ? 0 : planStart.weekday - 1; // แพลนเริ่มวันไหน
    return (i - start + 7) % 7; // นับระยะห่างจากวันเริ่ม (วนรอบสัปดาห์)
  }

  /// "มื้อที่ 2" -> 2, มื้ออื่น (เช่น มื้อเสริม) ไว้ท้ายวัน
  static int mealRank(String? type) {
    final m = RegExp(r'\d+').firstMatch(type ?? ''); // หาตัวเลขในชื่อมื้อ
    return m == null ? 99 : int.parse(m.group(0)!); // ไม่มีเลข = ไว้ท้าย
  }

  // ชื่อวัตถุดิบเหมือนกันไหม (ตรงกัน หรือชื่อหนึ่งอยู่ในอีกชื่อ)
  static bool _sameName(String a, String b) {
    final x = a.trim().toLowerCase(), y = b.trim().toLowerCase();
    return x.isNotEmpty &&
        y.isNotEmpty &&
        (x == y || x.contains(y) || y.contains(x));
  }

  // ดึงหน่วยออกจากข้อความปริมาณ เช่น "2 ฟอง" -> "ฟอง" (ตัดตัวเลขด้านหน้าออก)
  static String _unitOf(String quantityText) =>
      quantityText.replaceFirst(RegExp(r'^\s*[\d.,/\s]+'), '').trim();

  /// คืน { meal id: [สถานะวัตถุดิบตามลำดับในมื้อ] } ของทุกมื้อในแพลน
  /// [fridgeItems] ต้องมี name, quantity, unit, use_per_cook (+ คอลัมน์วันที่สำหรับเช็กเกินกำหนด)
  /// ปริมาณที่ต้องใช้ ในหน่วยของตู้เย็น — หน่วยไม่ตรง (เช่น เมนูบอก "1 ลูก" แต่ตู้
  /// เก็บเป็น "ส่วน") ใช้ "ใช้ครั้งละ" ที่ผู้ใช้ตั้งไว้ หรือ 1 (ของที่แบ่งเป็นส่วน)
  static num _needInFridgeUnit(
    String qtyText, // ข้อความปริมาณในเมนู
    String unit, // หน่วยในเมนู
    String fridgeUnit, // หน่วยของของในตู้
    num perCook, // "ใช้ครั้งละ" ที่ผู้ใช้ตั้ง
  ) {
    final parsed = RecipeRepository.parseQuantity( // แปลงตัวเลขด้านหน้าเป็นจำนวน (รองรับ 1/2)
      RecipeRepository.leadingNumber(qtyText),
    );
    final sameUnit = unit.isEmpty || fridgeUnit.isEmpty || unit == fridgeUnit; // หน่วยตรงกันไหม
    if (sameUnit && parsed != null && parsed > 0) return parsed; // หน่วยตรง -> ใช้ตัวเลขในเมนูได้เลย
    if (fridgeUnit != 'ส่วน' && perCook > 0) return perCook; // หน่วยไม่ตรง -> ใช้ "ใช้ครั้งละ"
    return 1; // ไม่มีข้อมูลอะไรเลย -> ถือว่าใช้ 1
  }

  /// ข้อความปริมาณของวัตถุดิบในเมนู แปลงเป็นหน่วยเดียวกับของในตู้ถ้าหน่วยไม่ตรง
  /// (เช่น AI/คลังสูตรบอก "เมลอน 1 ลูก" แต่ผู้ใช้แบ่งเมลอนเป็นส่วนไว้ -> "1 ส่วน")
  /// ไม่มีในตู้ / ของพื้นฐาน / หน่วยตรงอยู่แล้ว คืนข้อความเดิม
  static String quantityInFridgeUnit(
    String name,
    String qtyText,
    List<Map<String, dynamic>> fridgeItems,
  ) {
    if (ShoppingSuggestion.isStaple(name)) return qtyText; // ของพื้นฐาน ไม่ต้องแปลง
    final matches = [ // หาของในตู้ที่ชื่อตรงและยังไม่หมด
      for (final f in fridgeItems)
        if (!isUsedUp(f) && _sameName((f['name'] ?? '').toString(), name)) f,
    ];
    if (matches.isEmpty) return qtyText; // ไม่มีในตู้
    final fridgeUnit = (matches.first['unit'] ?? '').toString().trim(); // หน่วยของในตู้
    final unit = _unitOf(qtyText); // หน่วยในเมนู
    if (unit.isEmpty || fridgeUnit.isEmpty || unit == fridgeUnit) {
      return qtyText; // หน่วยตรงอยู่แล้ว
    }
    final need = _needInFridgeUnit( // คำนวณจำนวนในหน่วยของตู้
      qtyText,
      unit,
      fridgeUnit,
      RecipeRepository.toNum(matches.first['use_per_cook']),
    );
    return '${RecipeRepository.formatNum(need)} $fridgeUnit'; // เช่น "1 ส่วน"
  }

  // จองของให้ทุกมื้อ แล้วคืนสถานะวัตถุดิบของแต่ละมื้อ
  static Map<String, List<IngredientStatus>> allocate({
    required List<dynamic> meals,
    required List<Map<String, dynamic>> fridgeItems,
    DateTime? planStart,
  }) => _allocate(meals, fridgeItems, planStart, null);

  /// ของในตู้ที่เหลือหลังจองให้ [meals] แล้ว (รูปแบบเดียวกับ fridge_items แต่
  /// quantity = จำนวนที่ยังไม่ถูกจอง) — ใช้บอก AI ว่าเหลืออะไรให้ใช้กับมื้อที่เหลือ
  static List<Map<String, dynamic>> leftoverStock({
    required List<dynamic> meals,
    required List<Map<String, dynamic>> fridgeItems,
    DateTime? planStart,
  }) {
    final lots = <Map<String, dynamic>>[]; // ตัวรับผลลอตหลังจอง
    _allocate(meals, fridgeItems, planStart, lots); // จองแล้วเก็บลอตไว้ใน lots
    return [
      for (final l in lots)
        if ((l['left'] as num) > 0) // เอาเฉพาะลอตที่ยังเหลือ
          {...(l['src'] as Map<String, dynamic>), 'quantity': l['left']}, // ก๊อปข้อมูลเดิม เปลี่ยนจำนวนเป็นที่เหลือ
    ];
  }

  // ตัวทำงานหลักของการจอง
  static Map<String, List<IngredientStatus>> _allocate(
    List<dynamic> meals,
    List<Map<String, dynamic>> fridgeItems,
    DateTime? planStart,
    List<Map<String, dynamic>>? lotsOut, // ถ้าส่งมา จะใส่ลอตหลังจองคืนให้
  ) {
    // ของที่ยังใช้ได้ (ไม่หมด ไม่เกินกำหนด) — จำนวนคงเหลือหลังจองแต่ละลอต
    final lots = [
      for (final f in fridgeItems)
        if (!isUsedUp(f) &&
            !isOverdue(f) &&
            (f['name'] ?? '').toString().trim().isNotEmpty)
          <String, dynamic>{
            'src': f, // ข้อมูลต้นฉบับ
            'name': f['name'].toString(),
            'unit': (f['unit'] ?? '').toString().trim(),
            'left': RecipeRepository.toNum(f['quantity']), // จำนวนที่ยังไม่ถูกจอง
            'per_cook': RecipeRepository.toNum(f['use_per_cook']),
          },
    ];

    // เรียงมื้อ: ตามวัน (นับจากวันเริ่มแพลน) แล้วตามมื้อที่ 1, 2, 3
    final ordered =
        [
          for (final m in meals)
            if (m is Map) Map<String, dynamic>.from(m),
        ]..sort((a, b) {
          final byDay = _dayRank(
            a['day'],
            planStart,
          ).compareTo(_dayRank(b['day'], planStart));
          if (byDay != 0) return byDay; // คนละวัน เรียงตามวัน
          return mealRank(a['meal_type']).compareTo(mealRank(b['meal_type'])); // วันเดียวกัน เรียงตามมื้อ
        });

    final result = <String, List<IngredientStatus>>{};
    for (final meal in ordered) { // ไล่ทีละมื้อตามลำดับ
      final cooked = meal['is_cooked'] == true; // มื้อนี้ทำไปแล้วหรือยัง
      final statuses = <IngredientStatus>[];
      final raw = meal['ingredients'];
      for (final ing in raw is List ? raw.whereType<Map>() : const <Map>[]) { // ไล่วัตถุดิบในมื้อ
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
            .where((l) => _sameName(l['name'] as String, name)) // ลอตที่ชื่อตรง
            .toList();
        // ปริมาณที่มื้อนี้ต้องใช้ ในหน่วยของตู้เย็น
        final fridgeUnit = matches.isEmpty
            ? unit
            : matches.first['unit'] as String;
        final perCook = matches.isEmpty ? 0 : matches.first['per_cook'] as num;
        final need = _needInFridgeUnit(qtyText, unit, fridgeUnit, perCook);

        // จองจากลอตที่เหลือ (ตามลำดับที่ได้มา)
        var remaining = need; // ยังต้องการอีกเท่าไหร่
        for (final l in matches) {
          if (remaining <= 0) break; // จองครบแล้ว
          final left = l['left'] as num;
          if (left <= 0) continue; // ลอตนี้ถูกจองหมดแล้ว
          final take = left < remaining ? left : remaining; // เอาเท่าที่ลอตมีหรือเท่าที่ต้องการ
          l['left'] = left - take; // ลดจำนวนที่เหลือในลอต
          remaining -= take;
        }
        statuses.add(
          IngredientStatus(
            name: name,
            quantity: qtyText,
            have: remaining <= 0, // จองได้ครบ = มี
            short: remaining > 0 ? remaining : 0, // ยังขาดเท่าไหร่
            unit: fridgeUnit,
          ),
        );
      }
      final id = meal['id']?.toString();
      if (id != null) result[id] = statuses; // เก็บผลของมื้อนี้
    }
    lotsOut?.addAll(lots); // ส่งลอตหลังจองออกไป (ถ้าขอ)
    return result;
  }

  /// รายการซื้อของทั้งสัปดาห์ = รวมส่วนที่ขาดจริงของทุกมื้อ (ชื่อ + หน่วยเดียวกันบวกกัน)
  /// คืน [(ชื่อ, จำนวน, หน่วย, วันที่ใช้)] เรียงตามชื่อ
  static List<({String name, num amount, String unit, List<String> days})>
  shoppingList({
    required List<dynamic> meals,
    required Map<String, List<IngredientStatus>> allocation, // ผลจาก allocate()
    required String Function(String dayKey) dayLabel, // ฟังก์ชันแปลงชื่อวันเป็นภาษาไทย
  }) {
    final totals =
        <String, ({String name, num amount, String unit, List<String> days})>{};
    for (final m in meals) {
      if (m is! Map) continue;
      final statuses = allocation[m['id']?.toString()] ?? const [];
      for (final s in statuses) {
        if (s.have || s.short <= 0) continue; // มีพอแล้ว ไม่ต้องซื้อ
        final key = '${s.name.toLowerCase()}|${s.unit}'; // รวมกลุ่มด้วยชื่อ+หน่วย
        final prev = totals[key];
        final day = dayLabel((m['day'] ?? '').toString());
        totals[key] = (
          name: s.name,
          amount: (prev?.amount ?? 0) + s.short, // บวกจำนวนที่ขาดสะสม
          unit: s.unit,
          days: [...?prev?.days, if (!(prev?.days.contains(day) ?? false)) day], // เพิ่มวันที่ใช้ (ไม่ซ้ำ)
        );
      }
    }
    return totals.values.toList()..sort((a, b) => a.name.compareTo(b.name)); // เรียงตามชื่อ
  }
}
