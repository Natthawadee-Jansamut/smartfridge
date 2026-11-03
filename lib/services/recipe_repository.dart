import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:test_app/services/fridge_stock.dart';

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

  /// (มีครบกี่ชนิด, ต้องใช้ทั้งหมดกี่ชนิด)
  static (int, int) completeness(
    Map<String, dynamic> recipe,
    List<Map<String, dynamic>> inventory,
  ) {
    final list = ingredientsOf(recipe);
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

  // -------------------------------------------------------------------- Save

  /// คอลัมน์เสริมที่อาจยังไม่ได้สร้างใน Supabase -> ถ้าไม่มี จะบันทึกส่วนอื่นต่อได้
  /// พร้อมคำเตือนที่จะแสดงให้ผู้ใช้เห็น
  static const _optionalColumns = {
    'image_url': 'ยังไม่ได้เพิ่มคอลัมน์ image_url ใน Supabase จึงไม่ได้บันทึกรูป',
    'ai_step_indexes':
        'ยังไม่ได้เพิ่มคอลัมน์ ai_step_indexes ใน Supabase จึงไม่ได้จำว่าขั้นตอนไหน AI คิดเพิ่ม',
  };

  static Map<String, dynamic> _rowFrom(Map<String, dynamic> recipe) {
    final ingredients = ingredientsOf(recipe);
    final name = (recipe['recipe_name'] ?? '').toString().trim();
    return {
      'recipe_name': name.isEmpty ? 'ไม่มีชื่อเมนู' : name,
      'time': recipe['time'],
      'servings': recipe['servings'],
      'ingredients_used':
          recipe['ingredients_used'] ??
          ingredients.map((e) => e['name']).toList(),
      'detailed_ingredients': ingredients,
      'instructions': recipe['instructions'] ?? [],
      'ai_step_indexes': aiStepIndexesOf(recipe).toList()..sort(),
    };
  }

  /// เขียนลง Supabase ถ้าเจอ error "ไม่พบคอลัมน์" (PGRST204) ของคอลัมน์เสริม
  /// จะตัดคอลัมน์นั้นออกแล้วลองใหม่ คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  static Future<List<String>> _writeWithFallback(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic> data) write,
  ) async {
    final data = Map<String, dynamic>.from(row);
    final warnings = <String>[];
    while (true) {
      try {
        await write(data);
        return warnings;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST204') rethrow;
        final missing = _optionalColumns.keys
            .where((c) => data.containsKey(c) && e.message.contains("'$c'"))
            .firstOrNull;
        if (missing == null) rethrow;
        final value = data.remove(missing);
        final hadData = value != null && !(value is List && value.isEmpty);
        if (hadData) warnings.add(_optionalColumns[missing]!);
        debugPrint('ไม่พบคอลัมน์ $missing ใน scanned_recipes — บันทึกโดยไม่มีคอลัมน์นี้');
      }
    }
  }

  /// เพิ่มสูตรใหม่ลงตาราง scanned_recipes — คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  static Future<List<String>> saveRecipe(
    Map<String, dynamic> recipe, {
    Uint8List? imageBytes,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    final warnings = <String>[];
    final row = {'user_id': user.id, ..._rowFrom(recipe)};
    if (imageBytes != null) {
      final url = await _uploadImage(user.id, imageBytes);
      if (url == null) {
        warnings.add('อัปโหลดรูปไม่สำเร็จ');
      } else {
        row['image_url'] = url;
      }
    }

    warnings.addAll(
      await _writeWithFallback(
        row,
        (data) async {
          await _db.from('scanned_recipes').insert(data);
        },
      ),
    );
    return warnings;
  }

  /// แก้ไขสูตรที่บันทึกไว้แล้ว — คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  /// [imageBytes] = รูปใหม่ที่จะแทนรูปเดิม, [removeImage] = ลบรูปเดิมออก
  static Future<List<String>> updateRecipe(
    Object id,
    Map<String, dynamic> recipe, {
    Uint8List? imageBytes,
    bool removeImage = false,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    final warnings = <String>[];
    final row = _rowFrom(recipe);
    if (imageBytes != null) {
      final url = await _uploadImage(user.id, imageBytes);
      if (url == null) {
        warnings.add('อัปโหลดรูปใหม่ไม่สำเร็จ (ยังใช้รูปเดิม)');
      } else {
        row['image_url'] = url;
      }
    } else if (removeImage) {
      row['image_url'] = null;
    }

    warnings.addAll(
      await _writeWithFallback(row, (data) async {
        final updated = await _db
            .from('scanned_recipes')
            .update(data)
            .eq('id', id)
            .eq('user_id', user.id)
            .select('id');
        // RLS บล็อกการแก้ไขจะไม่ error แต่ได้แถวกลับมา 0 แถว
        if (updated.isEmpty) {
          throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข (เช็ค RLS policy ของ UPDATE)';
        }
      }),
    );
    return warnings;
  }

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
