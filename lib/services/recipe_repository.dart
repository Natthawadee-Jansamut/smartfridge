import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_app/services/fridge_images.dart';

import 'package:test_app/services/fridge_stock.dart';
import 'package:test_app/services/global_recipe_service.dart';
import 'package:test_app/services/shopping_suggestion.dart';
import 'package:test_app/utils/fridge_age.dart';

/// งานฝั่ง Supabase ทั้งหมดของฟีเจอร์สูตรอาหาร รวมไว้ที่เดียว
/// (หน้าจอจะได้ไม่ต้องเขียน query / logic เทียบวัตถุดิบซ้ำกันหลายที่)
class RecipeRepository {
  RecipeRepository._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// bucket ใน Supabase Storage สำหรับรูปเมนูที่ผู้ใช้แนบ (หน้าเขียนสูตรเอง)
  static const imageBucket = 'recipe-images';

  // ---------------------------------------------------------------- Inventory

  static Future<List<Map<String, dynamic>>> fetchInventory() async {
    final res = await _db.from('fridge_items').select();
    return List<Map<String, dynamic>>.from(res);
  }

  // ------------------------------------------------------------- Number utils

  static num toNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// แปลงจำนวนที่ผู้ใช้พิมพ์ รองรับ "2", "0.5", "1/2", "1 1/2"
  /// คืน null ถ้าว่างหรืออ่านไม่ออก
  static num? parseQuantity(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    final direct = num.tryParse(s);
    if (direct != null) return direct;

    num total = 0;
    for (final part in s.split(RegExp(r'\s+'))) {
      if (part.contains('/')) {
        final f = part.split('/');
        if (f.length != 2) return null;
        final a = num.tryParse(f[0]);
        final b = num.tryParse(f[1]);
        if (a == null || b == null || b == 0) return null;
        total += a / b;
      } else {
        final n = num.tryParse(part);
        if (n == null) return null;
        total += n;
      }
    }
    return total;
  }

  /// ดึงตัวเลขตัวแรกจากข้อความ เช่น "2 ที่" -> 2, "1/2" -> 0.5 (ไม่มี -> null)
  static num? leadingNumber(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final text = v.toString();
    final frac = RegExp(
      r'(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)',
    ).firstMatch(text);
    if (frac != null) {
      final a = num.parse(frac.group(1)!);
      final b = num.parse(frac.group(2)!);
      return b == 0 ? null : a / b;
    }
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    return m == null ? null : num.parse(m.group(0)!);
  }

  /// เวลาทำเป็นนาที รองรับ "45 นาที", "1 ชั่วโมง 30 นาที", "1.5 ชม."
  static int? minutesOf(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.round();
    final text = v.toString();
    final hour = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ชั่วโมง|ชม)').firstMatch(text);
    final minute = RegExp(r'(\d+)\s*(?:นาที|น\.)').firstMatch(text);
    if (hour == null && minute == null) return leadingNumber(text)?.round();
    final h = hour == null ? 0 : num.parse(hour.group(1)!);
    final m = minute == null ? 0 : int.parse(minute.group(1)!);
    return (h * 60 + m).round();
  }

  /// นาที -> ข้อความที่เก็บลงฐานข้อมูล (null/0 = ไม่ได้ระบุ)
  static String? minutesText(num? minutes) =>
      (minutes == null || minutes <= 0) ? null : '${minutes.round()} นาที';

  /// จำนวนที่ -> ข้อความที่เก็บลงฐานข้อมูล (null/0 = ไม่ได้ระบุ)
  static String? servingsText(num? servings) =>
      (servings == null || servings <= 0) ? null : '${formatNum(servings)} ที่';

  /// แสดงตัวเลขสวยๆ: 2.0 -> "2", 0.5 -> "0.5"
  static String formatNum(dynamic v) {
    if (v == null) return '';
    final n = v is num ? v : num.tryParse(v.toString());
    if (n == null) return v.toString();
    if (n == n.roundToDouble()) return n.toInt().toString();
    return double.parse(n.toStringAsFixed(2)).toString();
  }

  // ------------------------------------------------------ Ingredient matching

  /// วัตถุดิบนี้มีในตู้เย็นพอไหม — เทียบชื่อแบบยืดหยุ่น + รวมทุกลอต (FIFO)
  /// ใช้ตรรกะเดียวกับตอนหักวัตถุดิบจริงใน RecipeDetailScreen
  static bool isIngredientAvailable(
    Map<String, dynamic> ingredient,
    List<Map<String, dynamic>> inventory,
  ) {
    final neededName = (ingredient['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (neededName.isEmpty) return false;
    final neededQty = toNum(ingredient['use_quantity']);

    final hasMatch = inventory.any((inv) {
      final invName = (inv['name'] ?? '').toString().trim().toLowerCase();
      return invName.isNotEmpty &&
          (invName == neededName ||
              invName.contains(neededName) ||
              neededName.contains(invName));
    });
    return hasMatch && availableQuantity(inventory, neededName) >= neededQty;
  }

  // ------------------------------------------------- เครื่องปรุงพื้นฐาน

  /// คำที่บอกว่าเป็นเครื่องปรุงพื้นฐานที่ทุกบ้านน่าจะมีอยู่แล้ว (ชื่อมีคำนี้อยู่ = ใช่)
  static const _stapleKeywords = [
    'น้ำปลา',
    'ซีอิ๊ว',
    'ซอส',
    'น้ำตาล',
    'เกลือ',
    'พริกไทย',
    'น้ำมัน',
    'ผงชูรส',
    'ผงปรุง',
    'รสดี',
    'คนอร์',
    'น้ำส้มสายชู',
    'เต้าเจี้ยว',
    'ซุปก้อน',
  ];

  /// ชื่อที่ต้องตรงทั้งคำ (สั้นเกินกว่าจะใช้ "มีคำนี้อยู่" ได้)
  static const _stapleExactNames = {'น้ำ', 'น้ำเปล่า', 'น้ำสะอาด'};

  /// เป็นเครื่องปรุงพื้นฐาน (ซอส น้ำปลา น้ำตาล ฯลฯ) ไหม — ไม่นับในสถานะวัตถุดิบ
  /// ดูจาก "is_staple": true (พจนานุกรมกลาง ingredients.is_staple หรือ AI ระบุมา)
  /// ถ้าไม่มี ใช้รายการคำด้านบนเทียบกับชื่อ
  static bool isStapleIngredient(Map<String, dynamic> ingredient) {
    if (ingredient['is_staple'] == true) return true;
    final name = (ingredient['name'] ?? '').toString().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (name.isEmpty) return false;
    return _stapleExactNames.contains(name) ||
        _stapleKeywords.any(name.contains);
  }

  /// (มีครบกี่ชนิด, ต้องใช้ทั้งหมดกี่ชนิด) — ไม่นับเครื่องปรุงพื้นฐาน
  static (int, int) completeness(
    Map<String, dynamic> recipe,
    List<Map<String, dynamic>> inventory,
  ) {
    final list = ingredientsOf(
      recipe,
    ).where((i) => !isStapleIngredient(i)).toList();
    final have = list.where((i) => isIngredientAvailable(i, inventory)).length;
    return (have, list.length);
  }

  static List<Map<String, dynamic>> ingredientsOf(Map<String, dynamic> recipe) {
    final raw = recipe['detailed_ingredients'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ------------------------------------------------------------------- Steps

  static final _stepNumberPrefix = RegExp(r'^\s*\d+\s*[\.\)]\s*');

  /// ขั้นตอนการทำ (ข้อความล้วน ตัดเลขข้อ "1." ออกแล้ว)
  static List<String> stepTextsOf(Map<String, dynamic> recipe) {
    final raw = recipe['instructions'];
    if (raw is! List) return [];
    return raw
        .map((e) => e.toString().replaceFirst(_stepNumberPrefix, '').trim())
        .toList();
  }

  /// ตำแหน่ง (เริ่มที่ 0) ของขั้นตอนที่ AI คิดเพิ่มให้ — ใช้ทำตัวหนังสือสีแดง
  static Set<int> aiStepIndexesOf(Map<String, dynamic> recipe) {
    final raw = recipe['ai_step_indexes'];
    if (raw is! List) return {};
    return raw
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .toSet();
  }

  // ------------------------------------------------------------------- Fetch
  //
  // โครงสร้างฐานข้อมูลใหม่ (แทนตาราง scanned_recipes เดิม):
  //   recipes             = ตัวสูตร (ใช้ร่วมกันได้หลายคน)
  //   recipe_ingredients  = วัตถุดิบของสูตร ทีละแถว ผูกกับ ingredients.id
  //   user_saved_recipes  = ผู้ใช้คนไหนบันทึกสูตรไหน + overrides (ส่วนที่แก้เอง)
  //
  // หน้าจอยังใช้ Map รูปแบบเดิม (recipe_name, time, servings,
  // detailed_ingredients, instructions, ai_step_indexes, image_url) เหมือนเดิม
  // โดย 'id' = id ของแถวใน user_saved_recipes

  static const _recipeSelect =
      'id, name, time_text, servings_text, instructions, '
      'ai_step_indexes, image_url, source, '
      'recipe_ingredients(sort_order, ingredient_id, display_name, quantity, unit, is_main, ingredients(is_staple))';

  static const _savedSelect =
      'id, recipe_id, overrides, is_favorite, created_at, '
      'recipes($_recipeSelect)';

  /// คีย์ที่ผู้ใช้แก้ทับสูตรต้นฉบับได้ (เก็บใน user_saved_recipes.overrides)
  static const _overrideKeys = [
    'recipe_name',
    'time',
    'servings',
    'time_estimated',
    'servings_estimated',
    'ingredients_used',
    'detailed_ingredients',
    'instructions',
    'ai_step_indexes',
    'image_url',
    // รูปสูตรที่ผู้ใช้สแกน (ที่เก็บไฟล์ส่วนตัว recipe-scan-images)
    'scan_image_path',
  ];

  /// สูตรที่ผู้ใช้บันทึกไว้ ใหม่สุดก่อน
  static Future<List<Map<String, dynamic>>> fetchSavedRecipes({
    int? limit,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    var query = _db
        .from('user_saved_recipes')
        .select(_savedSelect)
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    final res = limit == null ? await query : await query.limit(limit);
    return List<Map<String, dynamic>>.from(res).map(_flatten).toList();
  }

  /// ลายนิ้วมือของไฟล์รูป (SHA-256 แบบ hex) — รูปไฟล์เดียวกันได้ค่าเดียวกันเสมอ
  /// ใช้เก็บใน recipes.image_hash เพื่อจำว่ารูปนี้เคยสแกนแล้ว
  static String imageHashOf(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  /// ค้นสูตรที่เคยสแกนจากรูปเดียวกัน (image_hash ตรงกัน) — เจอ = ไม่ต้องเรียก Gemini
  static Future<Map<String, dynamic>?> findRecipeByImageHash(
    String imageHash,
  ) async {
    final rows = await _db
        .from('recipes')
        .select(_recipeSelect)
        .eq('image_hash', imageHash)
        .limit(1);
    if (rows.isEmpty) return null;
    return _recipeToMap(Map<String, dynamic>.from(rows.first));
  }

  /// สัดส่วนขั้นตอนที่ AI คิดเพิ่มเอง (0.0 - 1.0) ไม่มีขั้นตอนเลย = 1.0
  /// ใช้แยกว่าสูตรมาจากรูปจริง หรือ AI แต่งขึ้นเกือบทั้งหมด
  static double aiStepRatio(Map<String, dynamic> recipe) {
    final steps = stepTextsOf(recipe).length;
    if (steps == 0) return 1;
    return aiStepIndexesOf(recipe).where((i) => i < steps).length / steps;
  }

  /// สองสูตรใช้วัตถุดิบเหมือนกันแค่ไหน (0.0 - 1.0) เทียบจากชื่อวัตถุดิบ
  /// ชื่อที่มีคำหนึ่งอยู่ในอีกคำ (เช่น "หมูสับ" กับ "เนื้อหมูสับ") นับว่าตรงกัน
  static double ingredientSimilarity(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    Set<String> names(Map<String, dynamic> r) => ingredientsOf(r)
        .map((i) => (i['name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    final na = names(a), nb = names(b);
    if (na.isEmpty && nb.isEmpty) return 1;
    if (na.isEmpty || nb.isEmpty) return 0;
    bool same(String x, String y) => x == y || x.contains(y) || y.contains(x);
    final matched = na.where((x) => nb.any((y) => same(x, y))).length;
    final union = na.length + nb.length - matched;
    return matched / union;
  }

  /// ค้นสูตรในฐานข้อมูลจากชื่อเมนู (ไม่สนตัวพิมพ์เล็ก/ใหญ่ และช่องว่างหัวท้าย)
  /// เจอหลายสูตร -> เลือกสูตรที่มาจากรูปจริง (AI แต่งน้อยสุด) ก่อน
  /// แล้วค่อยดูว่ามีคนใช้มากที่สุด, ไม่เจอ -> null
  /// Map ที่คืนมามี 'recipe_id' = id ของสูตรในตาราง recipes
  static Future<Map<String, dynamic>?> _findRecipeByNameDirect(
    String name,
  ) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    // escape ตัวอักษรพิเศษของ ILIKE ให้เป็นการเทียบชื่อตรงตัว
    final pattern = trimmed.replaceAllMapped(
      RegExp(r'[\\%_]'),
      (m) => '\\${m[0]}',
    );
    final rows = await _db
        .from('recipes')
        .select(_recipeSelect)
        .ilike('name', pattern)
        .order('use_count', ascending: false)
        .limit(10);
    if (rows.isEmpty) return null;
    final candidates = [
      for (final r in rows) _recipeToMap(Map<String, dynamic>.from(r)),
    ];
    // sort แบบคงลำดับเดิม (use_count มากก่อน) เมื่อสัดส่วน AI เท่ากัน
    final order = {
      for (var i = 0; i < candidates.length; i++) candidates[i]: i,
    };
    candidates.sort((a, b) {
      final byAi = aiStepRatio(a).compareTo(aiStepRatio(b));
      return byAi != 0 ? byAi : order[a]!.compareTo(order[b]!);
    });
    return candidates.first;
  }

  /// ชื่อเมนูสำหรับเทียบ: ตัวพิมพ์เล็ก + ตัดช่องว่างทั้งหมด
  /// สระบน/ล่าง และวรรณยุกต์ภาษาไทย (พิมพ์สลับลำดับกันได้ เช่น "เตี๋ยว"
  /// ใส่ ี ก่อนหรือหลัง ๋ ก็ได้ ตาเห็นเหมือนกัน แต่คอมพิวเตอร์มองเป็นคนละคำ)
  static final _thaiMarks = RegExp('[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]');

  /// ชื่อเมนูสำหรับเทียบ: ตัวพิมพ์เล็ก ตัดช่องว่าง และตัดสระบน/ล่าง+วรรณยุกต์
  /// ทำให้ชื่อที่พิมพ์ลำดับต่างกันเทียบกันได้
  static String _nameForMatch(Object? v) => (v ?? '')
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(_thaiMarks, '');

  /// ชื่อเมนูเดียวกันไหม (ไม่สนช่องว่าง ตัวพิมพ์ และลำดับวรรณยุกต์/สระบนล่าง)
  /// ชื่อเมนูมีคำค้นอยู่ข้างในไหม (ไม่สนช่องว่าง ตัวพิมพ์ และลำดับวรรณยุกต์)
  static bool nameMatchesQuery(Object? name, String query) {
    final q = _nameForMatch(query);
    return q.isEmpty || _nameForMatch(name).contains(q);
  }

  static bool isSameRecipeName(Object? a, Object? b) {
    final x = _nameForMatch(a);
    return x.isNotEmpty && x == _nameForMatch(b);
  }

  /// ค้นสูตรที่ชื่อคล้ายกัน (ชื่อหนึ่งอยู่ในอีกชื่อ) หรือชื่อเดียวกันแต่พิมพ์
  /// วรรณยุกต์/สระสลับลำดับ เช่น สแกนได้ "ก๋วยเตี๋ยวคั่วไก่"
  /// -> เจอ "ก๋วยเตี๋ยวคั่วไก่กระทะร้อน"
  /// เรียงจากชื่อที่ยาวใกล้เคียงที่สุด แล้วสูตรจากรูปจริงก่อนสูตรที่ AI แต่ง
  /// คืนไม่เกิน [limit] สูตร (ไม่มี = list ว่าง)
  static Future<List<Map<String, dynamic>>> _findSimilarRecipesDirect(
    String name, {
    int limit = 3,
  }) async {
    final key = _nameForMatch(name);
    if (key.length < 3) return [];

    // ค้นในฐานข้อมูลด้วยตัวอักษรหลักคั่นด้วย * (ไม่สนวรรณยุกต์/สระบนล่าง)
    // เช่น "ก*ว*ย*เ*ต*ย*ว*..." แล้วค่อยกรองให้แม่นในแอปอีกที
    // - แบบเต็มชื่อ: เจอสูตรที่ชื่อในระบบยาวกว่า/เท่ากัน
    // - แบบ 3 ตัวแรก: เผื่อชื่อในระบบสั้นกว่าชื่อที่สแกนได้
    final chars = key
        .replaceAll(RegExp(r'[\\%_,()"*.:]'), '')
        .runes
        .map(String.fromCharCode)
        .toList();
    if (chars.length < 3) return [];
    final fullPattern = '*${chars.join('*')}*';
    final headPattern = '${chars.take(3).join('*')}*';
    final rows = await _db
        .from('recipes')
        .select(_recipeSelect)
        .or('name.ilike.$fullPattern,name.ilike.$headPattern')
        .order('use_count', ascending: false)
        .limit(50);

    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final recipe = _recipeToMap(Map<String, dynamic>.from(row));
      final other = _nameForMatch(recipe['recipe_name']);
      if (other.isEmpty) continue;
      if (other.contains(key) || key.contains(other)) matches.add(recipe);
    }
    debugPrint(
      'ค้นสูตรชื่อคล้าย "$name": ฐานข้อมูลส่งมา ${rows.length} แถว, '
      'ตรงเงื่อนไข ${matches.length} สูตร '
      '${matches.map((m) => m['recipe_name']).toList()}',
    );

    final order = {for (var i = 0; i < matches.length; i++) matches[i]: i};
    int lengthGap(Map<String, dynamic> r) =>
        (_nameForMatch(r['recipe_name']).length - key.length).abs();
    matches.sort((a, b) {
      final byLength = lengthGap(a).compareTo(lengthGap(b));
      if (byLength != 0) return byLength;
      final byAi = aiStepRatio(a).compareTo(aiStepRatio(b));
      return byAi != 0 ? byAi : order[a]!.compareTo(order[b]!);
    });
    return matches.take(limit).toList();
  }

  /// เก็บผลสแกนเข้าคลังกลางแบบส่วนตัวทันที (ยังไม่เข้าคลังของผู้ใช้) พร้อม image_hash
  /// ตามแนวทางของทีม: สแกนรูปเดิมซ้ำจะเจอจาก hash ไม่ต้องเรียก Gemini อีก แม้ยัง
  /// ไม่ได้กดบันทึก — ทำเบื้องหลัง ไม่สำเร็จก็ไม่กระทบการสแกน
  static void cacheScanPrivately(
    Map<String, dynamic> recipe,
    String? imageHash,
  ) {
    if (imageHash == null || imageHash.isEmpty) return;
    final steps = stepTextsOf(recipe).length;
    final aiSteps = aiStepIndexesOf(recipe).length;
    // รูปมีแค่ชื่อเมนู (AI แต่งขั้นตอนเองทั้งหมด) = ai_generated, นอกนั้น = scanned
    final source = steps > 0 && aiSteps >= steps ? 'ai_generated' : 'scanned';
    GlobalRecipeService.cacheRecipe(
      recipe,
      source: source,
      imageHash: imageHash,
      isPublic: false,
    );
  }

  // --------------------------------------------- Name search (team function)
  //
  // ใช้ public.search_recipes_by_name() ของทีม: ชื่อตรง (score 1) -> ชื่อมีคำค้น
  // อยู่ข้างใน (>= 0.8) -> ชื่อสะกดคล้าย (trigram similarity) จึงเจอแม้สะกดต่าง
  // เช่น "กะเพรา" กับ "กระเพรา" ถ้าเรียกฟังก์ชันไม่ได้ จะใช้วิธีค้นเดิมในแอปแทน

  /// คืน [(score, สูตร)] เรียงคะแนนมากก่อน (สูตรมี 'recipe_id')
  static Future<List<(double, Map<String, dynamic>)>> _searchByNameRpc(
    String name, {
    int limit = 10,
  }) async {
    final rows = await _db.rpc(
      'search_recipes_by_name',
      params: {'p_query': name.trim(), 'p_limit': limit},
    );
    if (rows is! List) return [];
    return [
      for (final row in rows.whereType<Map>())
        if (row['recipe'] is Map)
          (
            toNum(row['score']).toDouble(),
            {
              ...Map<String, dynamic>.from(row['recipe'] as Map),
              'recipe_id': row['recipe_id'],
            },
          ),
    ];
  }

  /// ค้นสูตรที่ชื่อตรงกันทั้งชื่อ (ไม่สนช่องว่าง ตัวพิมพ์ ลำดับวรรณยุกต์)
  /// เจอหลายสูตร -> เลือกสูตรที่มาจากรูปจริง (AI แต่งน้อยสุด) ก่อน แล้วค่อยดูคนใช้เยอะ
  /// Map ที่คืนมามี 'recipe_id' = id ของสูตรในตาราง recipes, ไม่เจอ -> null
  static Future<Map<String, dynamic>?> findRecipeByName(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final exact = [
        for (final (score, r) in await _searchByNameRpc(name))
          if (score >= 0.999 || isSameRecipeName(r['recipe_name'], name)) r,
      ];
      if (exact.isEmpty) return null;
      final order = {for (var i = 0; i < exact.length; i++) exact[i]: i};
      exact.sort((a, b) {
        final byAi = aiStepRatio(a).compareTo(aiStepRatio(b));
        return byAi != 0 ? byAi : order[a]!.compareTo(order[b]!);
      });
      return exact.first;
    } catch (e) {
      debugPrint('search_recipes_by_name ใช้ไม่ได้ (ใช้วิธีค้นเดิม): $e');
      return _findRecipeByNameDirect(name);
    }
  }

  /// ค้นสูตรที่ชื่อคล้ายกัน: มีคำค้นอยู่ในชื่อ หรือสะกดคล้าย (ไม่รวมชื่อที่ตรงกันทั้งชื่อ)
  /// เช่น "ก๋วยเตี๋ยวคั่วไก่" -> "ก๋วยเตี๋ยวคั่วไก่กระทะร้อน", "กะเพราหมู" -> "กระเพราหมู"
  /// เรียงคะแนนความคล้ายมากก่อน คืนไม่เกิน [limit] สูตร
  static Future<List<Map<String, dynamic>>> findSimilarRecipesByName(
    String name, {
    int limit = 3,
  }) async {
    if (_nameForMatch(name).length < 3) return [];
    try {
      final results = await _searchByNameRpc(name, limit: limit + 5);
      return [
        for (final (score, r) in results)
          if (score < 0.999 && !isSameRecipeName(r['recipe_name'], name)) r,
      ].take(limit).toList();
    } catch (e) {
      debugPrint('search_recipes_by_name ใช้ไม่ได้ (ใช้วิธีค้นเดิม): $e');
      return _findSimilarRecipesDirect(name, limit: limit);
    }
  }

  // ---------------------------------------------------- Shared recipe library
  //
  // เมนูที่ AI สร้าง (หน้าเมนูอาหาร / แพลน / เปลี่ยนเมนู) เก็บลง recipes เป็นคลังกลาง
  // ครั้งหน้าค้นจากคลังนี้ก่อน เจอเมนูที่ทำได้จากของในตู้ -> ไม่ต้องเรียก AI

  /// เก็บเมนูที่ AI สร้างลงคลังกลาง (source = ai_generated, แชร์ให้ทุกคนใช้ซ้ำ)
  /// ผ่าน public.save_recipe() ของทีม (p_bookmark = false: ไม่เพิ่มเข้าคลังของผู้ใช้)
  /// ฐานข้อมูลจัดการเอง: เพิ่มวัตถุดิบใหม่, ลายเซ็นวัตถุดิบ, กันสูตรซ้ำ, นับ use_count
  /// คืน id ของสูตร (null = บันทึกไม่สำเร็จ ไม่ทำให้หน้าจอพัง)
  static Future<Object?> saveAiRecipe(
    Map<String, dynamic> recipe, {
    num? caloriesPerServing,
    num? proteinPerServing,
    List<String> dietTags = const [],
  }) async {
    try {
      if (_db.auth.currentUser == null) return null;
      if (ingredientsOf(recipe).isEmpty) return null;
      final id = await _db.rpc(
        'save_recipe',
        params: {
          'p_recipe': {
            ...recipe,
            'recipe_name': _nameOf(recipe),
            if (caloriesPerServing != null)
              'calories_per_serving': caloriesPerServing,
            if (proteinPerServing != null)
              'protein_per_serving': proteinPerServing,
            'diet_tags': dietTags,
          },
          'p_source': 'ai_generated',
          'p_is_public': true,
          'p_bookmark': false,
        },
      );
      return id as Object?;
    } catch (e) {
      debugPrint('เก็บเมนูจาก AI ลงคลังสูตรไม่สำเร็จ: $e');
      return null;
    }
  }

  /// ค้นเมนูในคลังกลาง (recipes) ที่ทำได้จากของในตู้เย็น
  /// - วัตถุดิบหลักต้องมีในตู้ (เทียบ id + ชื่อ) ยอมให้ขาดได้ไม่เกิน [maxMissing] อย่าง
  ///   (ของพื้นฐาน เช่น ข้าว เครื่องปรุง ถือว่ามี)
  /// - [excludeNames] = ชื่อเมนูที่ไม่เอา (เช่น ใช้ไปแล้วในแพลน)
  /// - [requireNutrition] = ต้องมีแคลอรี/โปรตีนต่อที่ (ใช้กับแพลน)
  /// เรียง: ขาดน้อยก่อน -> ใช้ของที่ควรใช้ก่อน ([useFirstNames]) -> มีคนใช้เยอะ
  /// คืน Map รูปแบบเดียวกับ _recipeToMap + 'missing' (ชื่อที่ต้องซื้อ),
  /// 'calories', 'protein'
  static Future<List<Map<String, dynamic>>> findRecipesForFridge({
    required List<Map<String, dynamic>> fridgeItems,
    int maxMissing = 0,
    int limit = 10,
    Set<String> excludeNames = const {},
    Set<String> useFirstNames = const {},
    bool requireNutrition = false,
  }) async {
    final fridgeNames = [
      for (final f in fridgeItems)
        if (!isUsedUp(f) && (f['name'] ?? '').toString().trim().isNotEmpty)
          f['name'].toString().trim(),
    ];
    if (fridgeNames.isEmpty) return [];

    // จับคู่ฝั่งฐานข้อมูลด้วย public.match_recipes_by_ingredients() ของทีม
    // (ชื่อตรง, ชื่อเรียกอื่น, ชื่อหนึ่งอยู่ในอีกชื่อ, สะกดคล้าย, ไม่นับ is_staple)
    // ขอเผื่อจำนวนที่ขาดไว้ แล้วกรองของพื้นฐานตามรายการในแอปซ้ำอีกรอบ
    final matches = await GlobalRecipeService.matchByIngredients(
      fridgeNames.toSet().toList(),
      maxMissing: maxMissing + 3,
      minMatchRatio: 0,
      limit: 50,
    );

    final exclude = {for (final n in excludeNames) _nameForMatch(n)};
    final useFirst = useFirstNames.map((e) => e.trim().toLowerCase()).toSet();
    final results = <Map<String, dynamic>>[];
    for (final m in matches) {
      if (exclude.contains(_nameForMatch(m['recipe_name']))) continue;
      final calories = m['calories_per_serving'];
      final protein = m['protein_per_serving'];
      if (requireNutrition && (calories == null || protein == null)) continue;
      final missing = [
        for (final n in (m['missing_ingredients'] as List? ?? const []))
          if (!ShoppingSuggestion.isStaple(n.toString())) n.toString(),
      ];
      if (missing.length > maxMissing) continue;
      final usesFirst = ingredientsOf(m).any((ing) {
        final n = (ing['name'] ?? '').toString().trim().toLowerCase();
        return useFirst.any((u) => u == n || u.contains(n) || n.contains(u));
      });
      results.add({
        ...m,
        'recipe_id': m['global_recipe_id'],
        'missing': missing,
        'uses_first': usesFirst,
        'calories': calories,
        'protein': protein,
        'diet_tags': m['diet_tags'] ?? const [],
        'time_minutes': m['time_minutes'] is num
            ? (m['time_minutes'] as num).toInt()
            : minutesOf(m['time']),
      });
    }
    // ผลจากฐานข้อมูลเรียงขาดน้อยก่อนอยู่แล้ว -> ดันสูตรที่ใช้ของที่ควรใช้ก่อนขึ้นมา
    final order = {for (var i = 0; i < results.length; i++) results[i]: i};
    results.sort((a, b) {
      final byMissing = (a['missing'] as List).length.compareTo(
        (b['missing'] as List).length,
      );
      if (byMissing != 0) return byMissing;
      final byFirst =
          (b['uses_first'] == true ? 1 : 0) - (a['uses_first'] == true ? 1 : 0);
      if (byFirst != 0) return byFirst;
      return order[a]!.compareTo(order[b]!);
    });
    return results.take(limit).toList();
  }

  /// แปลงแถว recipes (+ recipe_ingredients) ให้เป็น Map รูปแบบที่หน้าจอใช้
  static Map<String, dynamic> _recipeToMap(Map<String, dynamic> r) {
    final rawIngs =
        (r['recipe_ingredients'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..sort(
            (a, b) => toNum(a['sort_order']).compareTo(toNum(b['sort_order'])),
          );
    final ingredients = [
      for (final i in rawIngs)
        {
          'name': i['display_name'],
          'use_quantity': i['quantity'],
          'unit': i['unit'],
          'ingredient_id': i['ingredient_id'],
          'is_main': i['is_main'],
          // เครื่องปรุงพื้นฐานตามพจนานุกรมกลาง (ingredients.is_staple)
          if (i['ingredients'] is Map &&
              (i['ingredients'] as Map)['is_staple'] == true)
            'is_staple': true,
        },
    ];

    return {
      'recipe_id': r['id'],
      'source': r['source'],
      'recipe_name': r['name'],
      'time': r['time_text'],
      'servings': r['servings_text'],
      'ingredients_used': ingredients.map((e) => e['name']).toList(),
      'detailed_ingredients': ingredients,
      'instructions': r['instructions'] ?? [],
      'ai_step_indexes': r['ai_step_indexes'] ?? [],
      'image_url': r['image_url'],
    };
  }

  /// แปลงแถว user_saved_recipes + recipes ให้เป็น Map รูปแบบที่หน้าจอใช้
  static Map<String, dynamic> _flatten(Map<String, dynamic> saved) {
    final out = <String, dynamic>{
      ..._recipeToMap(
        Map<String, dynamic>.from(saved['recipes'] as Map? ?? {}),
      ),
      'id': saved['id'],
      'recipe_id': saved['recipe_id'],
      'is_favorite': saved['is_favorite'] == true,
      'created_at': saved['created_at'],
    };

    final overrides = saved['overrides'];
    if (overrides is Map) {
      for (final key in _overrideKeys) {
        if (overrides.containsKey(key)) out[key] = overrides[key];
      }
    }
    return out;
  }

  // -------------------------------------------------------------------- Save

  static String _nameOf(Map<String, dynamic> recipe) {
    final name = (recipe['recipe_name'] ?? '').toString().trim();
    return name.isEmpty ? 'ไม่มีชื่อเมนู' : name;
  }

  /// overrides ของสูตรที่เพิ่งสร้างใหม่ — ตาราง recipes ไม่มีช่องเก็บชื่อที่ผู้ใช้ตั้งเอง
  /// และป้าย "AI ประมาณ" ของเวลา/จำนวนที่ จึงเก็บไว้ในคลังของผู้ใช้แทน
  static Map<String, dynamic>? _newRecipeOverrides(
    Map<String, dynamic> recipe,
    String? customName, {
    String? scanImagePath,
  }) {
    final out = <String, dynamic>{
      if (customName != null) 'recipe_name': customName,
      if (scanImagePath != null) 'scan_image_path': scanImagePath,
      if (recipe['time_estimated'] == true) 'time_estimated': true,
      if (recipe['servings_estimated'] == true) 'servings_estimated': true,
    };
    return out.isEmpty ? null : out;
  }

  /// เนื้อหาสูตรในรูปแบบที่หน้าจอใช้ (เก็บใน overrides ตอนแก้ไข)
  static Map<String, dynamic> _contentOf(Map<String, dynamic> recipe) {
    final ingredients = [
      for (final i in ingredientsOf(recipe))
        {
          'name': i['name'],
          'use_quantity': i['use_quantity'],
          'unit': i['unit'],
        },
    ];
    return {
      'recipe_name': _nameOf(recipe),
      'time': recipe['time'],
      'servings': recipe['servings'],
      'time_estimated': recipe['time_estimated'] == true,
      'servings_estimated': recipe['servings_estimated'] == true,
      'ingredients_used': ingredients.map((e) => e['name']).toList(),
      'detailed_ingredients': ingredients,
      'instructions': recipe['instructions'] ?? [],
      'ai_step_indexes': aiStepIndexesOf(recipe).toList()..sort(),
    };
  }

  /// คำเตือนตอนบันทึกสูตรที่อยู่ในคลังแล้ว (ไม่บันทึกซ้ำ/ทับของเดิม)
  static const alreadyInLibraryWarning =
      'สูตรนี้อยู่ในคลังของคุณแล้ว จึงไม่บันทึกซ้ำ';

  /// วัตถุดิบ (ชื่อ จำนวน หน่วย) และวิธีทำเหมือนกันทุกอย่างไหม
  /// ไม่สนชื่อเมนู เวลา จำนวนที่ — ต่างกันแค่นั้นยังถือเป็นสูตรเดียวกัน
  static bool isSameRecipeBody(Map<String, dynamic> a, Map<String, dynamic> b) {
    String key(Map<String, dynamic> r) => jsonEncode({
      'ingredients': [
        for (final i in ingredientsOf(r))
          [
            _nameForMatch(i['name']),
            parseQuantity(i['use_quantity']) ??
                (i['use_quantity'] ?? '').toString().trim(),
            (i['unit'] ?? '').toString().trim(),
          ],
      ],
      'steps': [
        for (final t in stepTextsOf(r))
          t.trim().replaceAll(RegExp(r'\s+'), ' '),
      ],
    });
    return key(a) == key(b);
  }

  /// สูตรไม่ถูกแก้อะไรเลยไหม (ชื่อ เวลา จำนวนที่ วัตถุดิบ วิธีทำ ต้องเหมือนเดิมทั้งหมด)
  /// ใช้ตัดสินว่าสูตรจาก AI บันทึกลงห้องสมุดกลางได้ไหม
  static bool isUneditedRecipe(
    Map<String, dynamic> recipe,
    Map<String, dynamic> original,
  ) => jsonEncode(_contentOf(recipe)) == jsonEncode(_contentOf(original));

  /// โหลดสูตรจากตาราง recipes ตาม id (null = ไม่เจอ/ไม่มีสิทธิ์อ่าน)
  static Future<Map<String, dynamic>?> _fetchRecipe(Object id) async {
    final row = await _db
        .from('recipes')
        .select(_recipeSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : _recipeToMap(Map<String, dynamic>.from(row));
  }

  /// บันทึกสูตรที่มีอยู่แล้วในฐานข้อมูล (เจอจาก findRecipeByName) เข้าคลังของผู้ใช้
  /// - วัตถุดิบหรือวิธีทำถูกแก้ ([recipe] ต่างจาก [original]) -> แยกเป็นสูตรใหม่
  /// - แก้แค่ชื่อ/เวลา/จำนวนที่ -> ผูกสูตรเดิม แล้วเก็บส่วนที่แก้ไว้ใน overrides
  /// - อยู่ในคลังแล้ว -> ไม่บันทึกทับ (ส่วนที่เคยแก้ไว้จะได้ไม่หาย)
  static Future<List<String>> saveExistingRecipe(
    Object recipeId,
    Map<String, dynamic> recipe, {
    required Map<String, dynamic> original,
    String source = 'scanned',
    String? imageHash,
    String? sharedName,
    Uint8List? scanImageBytes,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    if (!isSameRecipeBody(recipe, original)) {
      return saveRecipe(
        recipe,
        source: source,
        imageHash: imageHash,
        // ชื่อในระบบใช้ชื่อสูตรต้นทาง ชื่อที่ผู้ใช้ตั้งเองเก็บแค่ในคลัง
        sharedName: sharedName ?? _nameOf(original),
        // แก้วัตถุดิบ/วิธีทำของสูตรในระบบ = สูตรของผู้ใช้เอง -> เก็บเป็นส่วนตัว
        isPublic: false,
        scanImageBytes: scanImageBytes,
      );
    }

    if (await _isInLibrary(user.id, recipeId)) {
      return [alreadyInLibraryWarning];
    }
    final content = _contentOf(recipe);
    final edited = jsonEncode(content) != jsonEncode(_contentOf(original));
    final scanPath = await _uploadScanImage(user.id, scanImageBytes);
    final overrides = <String, dynamic>{
      if (edited) ...content,
      if (scanPath != null) 'scan_image_path': scanPath,
    };
    await _db.from('user_saved_recipes').upsert({
      'user_id': user.id,
      'recipe_id': recipeId,
      'overrides': overrides.isEmpty ? null : overrides,
    }, onConflict: 'user_id,recipe_id');
    await _bumpUseCount(recipeId);
    return [];
  }

  /// ผู้ใช้บันทึกสูตรนี้ไว้ในคลังแล้วหรือยัง
  static Future<bool> _isInLibrary(String userId, Object recipeId) async {
    final row = await _db
        .from('user_saved_recipes')
        .select('id')
        .eq('user_id', userId)
        .eq('recipe_id', recipeId)
        .maybeSingle();
    return row != null;
  }

  /// +1 ที่ recipes.use_count (มีคนบันทึกสูตรนี้เพิ่มอีกคน) ผ่านฟังก์ชันในฐานข้อมูล
  /// (ดู supabase/sql/increment_recipe_use_count.sql) ไม่สำเร็จ -> แค่ debugPrint
  /// เพราะการนับไม่ควรทำให้การบันทึกสูตรล้มเหลว
  static Future<void> _bumpUseCount(Object recipeId) async {
    try {
      await _db.rpc(
        'increment_recipe_use_count',
        params: {'p_recipe_id': recipeId},
      );
    } catch (e) {
      debugPrint(
        'เพิ่ม use_count ไม่สำเร็จ (รัน increment_recipe_use_count.sql แล้วหรือยัง): $e',
      );
    }
  }

  /// ปักหมุด/เลิกปักหมุดสูตรโปรด ([id] = id ของแถวใน user_saved_recipes)
  static Future<void> setFavorite(Object id, bool isFavorite) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';
    final updated = await _db
        .from('user_saved_recipes')
        .update({'is_favorite': isFavorite})
        .eq('id', id)
        .eq('user_id', user.id)
        .select('id');
    if (updated.isEmpty) throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข';
  }

  /// เรียงคลังสูตร: สูตรโปรดอยู่บนสุด แล้วเรียงตามจำนวนวัตถุดิบที่มีในตู้เย็น
  /// มากไปน้อย (ทั้งกลุ่มโปรดและกลุ่มปกติ) เท่ากัน -> สูตรที่บันทึกล่าสุดก่อน
  static List<Map<String, dynamic>> sortForLibrary(
    List<Map<String, dynamic>> recipes,
    List<Map<String, dynamic>> inventory,
  ) {
    final have = {for (final r in recipes) r: completeness(r, inventory).$1};
    final order = {for (var i = 0; i < recipes.length; i++) recipes[i]: i};
    return [...recipes]..sort((a, b) {
      final fav =
          (b['is_favorite'] == true ? 1 : 0) -
          (a['is_favorite'] == true ? 1 : 0);
      if (fav != 0) return fav;
      final byHave = have[b]!.compareTo(have[a]!);
      if (byHave != 0) return byHave;
      return order[a]!.compareTo(order[b]!); // คงลำดับเดิม (ใหม่สุดก่อน)
    });
  }

  /// เพิ่มสูตรใหม่ (recipes + recipe_ingredients) แล้วบันทึกให้ผู้ใช้ (user_saved_recipes)
  /// [source] = 'scanned' | 'manual' | 'ai_generated'
  /// คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  static Future<List<String>> saveRecipe(
    Map<String, dynamic> recipe, {
    Uint8List? imageBytes,
    String source = 'manual',
    String? imageHash,
    String? sharedName,
    bool? isPublic,
    Uint8List? scanImageBytes,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    // ชื่อที่เก็บในตาราง recipes (ที่คนอื่นเห็น) = ชื่อเมนูก่อนผู้ใช้เปลี่ยน
    // ส่วนชื่อที่ผู้ใช้ตั้งเอง (เช่น "คั่วไก่ 2") เก็บไว้ใน overrides ของคลังตัวเอง
    final myName = _nameOf(recipe);
    final baseName = (sharedName ?? '').trim();
    final storedName = baseName.isEmpty ? myName : baseName;
    final renamed = storedName != myName;

    final warnings = <String>[];
    String? imageUrl;
    if (imageBytes != null) {
      imageUrl = await _uploadImage(user.id, imageBytes);
      if (imageUrl == null) warnings.add('อัปโหลดรูปไม่สำเร็จ');
    }

    // สูตรที่ AI สร้าง แชร์ให้คนอื่นใช้ซ้ำได้ ส่วนสูตรที่ผู้ใช้สแกนจากตำรา/ลายมือ
    // หรือเขียนเอง เก็บเป็นส่วนตัว (ไม่เปิดให้คนอื่นเห็นโดยไม่ได้ขออนุญาต —
    // ตามแนวทางของทีม) ส่ง [isPublic] มาเพื่อกำหนดเองได้
    final shared = isPublic ?? source == 'ai_generated';

    // บันทึกเข้าคลังกลางผ่าน public.save_recipe() ของทีม (p_bookmark = false ก่อน
    // เพื่อเช็กว่าอยู่ในคลังของผู้ใช้แล้วหรือยัง) — ฐานข้อมูลจัดการเพิ่มวัตถุดิบใหม่,
    // กันสูตรซ้ำ (ชื่อ + ชุดวัตถุดิบ หรือรูปเดียวกัน) และนับ use_count เอง
    final Object recipeId;
    try {
      recipeId =
          await _db.rpc(
                'save_recipe',
                params: {
                  'p_recipe': {
                    ...recipe,
                    'recipe_name': storedName,
                    if (imageUrl != null) 'image_url': imageUrl,
                  },
                  'p_source': source,
                  'p_image_hash': imageHash,
                  'p_is_public': shared,
                  'p_bookmark': false,
                },
              )
              as Object;
    } on PostgrestException catch (e) {
      if (e.code == '54000') {
        throw 'บันทึกสูตรใหม่ครบโควตาของวันนี้แล้ว ลองใหม่พรุ่งนี้';
      }
      rethrow;
    }

    if (await _isInLibrary(user.id, recipeId)) {
      // อยู่ในคลังแล้ว ไม่บันทึกทับ (ส่วนที่ผู้ใช้เคยแก้ไว้จะได้ไม่หาย)
      return [...warnings, alreadyInLibraryWarning];
    }

    // สูตรที่ได้ตรงกับที่ผู้ใช้บันทึกทุกอย่างไหม (ฐานข้อมูลอาจคืนสูตรเดิมที่ชื่อ +
    // ชุดวัตถุดิบตรงกัน แต่ปริมาณ/วิธีทำต่างกัน) — ต่างกัน = เก็บฉบับของผู้ใช้ใน overrides
    final stored = await _fetchRecipe(recipeId);
    final sameBody = stored != null && isSameRecipeBody(stored, recipe);

    // รูปที่ใช้สแกน -> เก็บในคลังของผู้ใช้ (ไม่ผูกกับสูตรกลาง)
    final scanPath = await _uploadScanImage(user.id, scanImageBytes);
    await _db.from('user_saved_recipes').upsert({
      'user_id': user.id,
      'recipe_id': recipeId,
      'overrides': sameBody
          ? _newRecipeOverrides(
              recipe,
              renamed ? myName : null,
              scanImagePath: scanPath,
            )
          : {
              ..._contentOf(recipe),
              if (imageUrl != null) 'image_url': imageUrl,
              if (scanPath != null) 'scan_image_path': scanPath,
            },
    }, onConflict: 'user_id,recipe_id');
    return warnings;
  }

  /// แก้ไขสูตรที่บันทึกไว้แล้ว — เก็บส่วนที่แก้ไว้ใน user_saved_recipes.overrides
  /// (ไม่แก้ตาราง recipes ตรงๆ เพราะสูตรอาจถูกใช้ร่วมกับผู้ใช้คนอื่น)
  /// [id] = id ของแถวใน user_saved_recipes
  /// [imageBytes] = รูปใหม่ที่จะแทนรูปเดิม, [removeImage] = ลบรูปเดิมออก
  static Future<List<String>> updateRecipe(
    Object id,
    Map<String, dynamic> recipe, {
    Uint8List? imageBytes,
    bool removeImage = false,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    final current = await _db
        .from('user_saved_recipes')
        .select('overrides')
        .eq('id', id)
        .eq('user_id', user.id)
        .maybeSingle();
    if (current == null) throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข';

    final overrides = <String, dynamic>{
      if (current['overrides'] is Map)
        ...Map<String, dynamic>.from(current['overrides'] as Map),
      ..._contentOf(recipe),
    };

    final warnings = <String>[];
    if (imageBytes != null) {
      final url = await _uploadImage(user.id, imageBytes);
      if (url == null) {
        warnings.add('อัปโหลดรูปใหม่ไม่สำเร็จ (ยังใช้รูปเดิม)');
      } else {
        overrides['image_url'] = url;
      }
    } else if (removeImage) {
      overrides['image_url'] = null;
    }

    final updated = await _db
        .from('user_saved_recipes')
        .update({'overrides': overrides})
        .eq('id', id)
        .eq('user_id', user.id)
        .select('id');
    // RLS บล็อกการแก้ไขจะไม่ error แต่ได้แถวกลับมา 0 แถว
    if (updated.isEmpty) {
      throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข (เช็ค RLS policy ของ UPDATE)';
    }
    return warnings;
  }

  /// เอาสูตรออกจากคลังของผู้ใช้ (ลบแถวใน user_saved_recipes
  /// ตัวสูตรใน recipes ยังอยู่ เผื่อผู้ใช้คนอื่นใช้ร่วมกัน)
  static Future<void> deleteSavedRecipe(Object id) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';
    final deleted = await _db
        .from('user_saved_recipes')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id)
        .select('id');
    if (deleted.isEmpty) {
      throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์ลบ (เช็ค RLS policy ของ DELETE)';
    }
  }

  /// อัปโหลดรูปสูตรที่สแกนไปที่เก็บไฟล์ส่วนตัว (ไม่มีรูป/ไม่สำเร็จ = null)
  static Future<String?> _uploadScanImage(String uid, Uint8List? bytes) =>
      bytes == null
      ? Future.value(null)
      : uploadPrivateImage(recipeScanImageBucket, uid, bytes);

  static Future<String?> _uploadImage(String uid, Uint8List bytes) async {
    try {
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage
          .from(imageBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return _db.storage.from(imageBucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('อัปโหลดรูปเมนูไม่สำเร็จ: $e');
      return null;
    }
  }
}
