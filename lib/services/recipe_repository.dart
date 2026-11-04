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

  /// ดึงตัวเลขตัวแรกจากข้อความ เช่น "2 ที่" -> 2, "1/2" -> 0.5 (ไม่มี -> null)
  static num? leadingNumber(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final text = v.toString();
    final frac = RegExp(r'(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)').firstMatch(text);
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

  // ------------------------------------------------------------ Saved recipes
  //
  // สูตรที่ผู้ใช้บันทึกไว้อยู่ในคลังสูตรกลาง (recipes) + Bookmark ของผู้ใช้
  // (user_saved_recipes) — ดู supabase/migrations/20261104000000_global_recipes.sql
  // แผนที่ส่งให้หน้าจอยังเป็นรูปแบบเดิม โดย 'id' = id ของ Bookmark (ใช้แก้ไข/ลบ)

  /// สูตรที่ผู้ใช้บันทึกไว้ ใหม่สุดก่อน ([limit] = เอาแค่กี่รายการ)
  static Future<List<Map<String, dynamic>>> fetchSavedRecipes({
    int? limit,
  }) async {
    if (_db.auth.currentUser == null) return [];
    final rows = await _db.rpc('my_saved_recipes');
    final list = (rows as List).whereType<Map>().map((row) {
      final recipe = Map<String, dynamic>.from(row['recipe'] as Map);
      recipe['id'] = row['saved_id'];
      recipe['global_recipe_id'] = row['recipe_id'];
      recipe['is_favorite'] = row['is_favorite'];
      recipe['created_at'] = row['saved_at'];
      return recipe;
    }).toList();
    return limit == null ? list : list.take(limit).toList();
  }

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

  /// บันทึกสูตรใหม่ (เข้าคลังกลางแบบส่วนตัว + Bookmark ให้ผู้ใช้)
  /// คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  /// [source]: 'scanned' (สแกนจากรูป) | 'manual' (เขียนเอง)
  static Future<List<String>> saveRecipe(
    Map<String, dynamic> recipe, {
    Uint8List? imageBytes,
    String source = 'manual',
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';

    final warnings = <String>[];
    final row = _rowFrom(recipe);
    final minutes = minutesOf(row['time']);
    if (minutes != null) row['time_minutes'] = minutes;
    if (imageBytes != null) {
      final url = await _uploadImage(user.id, imageBytes);
      if (url == null) {
        warnings.add('อัปโหลดรูปไม่สำเร็จ');
      } else {
        row['image_url'] = url;
      }
    }

    // สูตรจากตำรา/ที่เขียนเองเป็นของผู้ใช้ -> ไม่เปิดให้คนอื่นเห็น (is_public: false)
    await _db.rpc(
      'save_recipe',
      params: {
        'p_recipe': row,
        'p_source': source,
        'p_is_public': false,
        'p_bookmark': true,
      },
    );
    return warnings;
  }

  /// แก้ไขสูตรที่บันทึกไว้แล้ว — เก็บเป็นส่วนที่แก้ของผู้ใช้คนนี้ (overrides)
  /// สูตรกลางไม่เปลี่ยน คืนรายการคำเตือน (ว่าง = สำเร็จครบ)
  /// [id] = id ของ Bookmark, [imageBytes] = รูปใหม่, [removeImage] = ลบรูปเดิมออก
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

    // รวมกับที่เคยแก้ไว้ (เช่น รูปที่เปลี่ยนไปก่อนหน้า) ไม่ให้หายเมื่อแก้รอบใหม่
    final current = await _db
        .from('user_saved_recipes')
        .select('overrides')
        .eq('id', id)
        .eq('user_id', user.id)
        .maybeSingle();
    if (current == null) {
      throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข';
    }
    final overrides = {
      ...Map<String, dynamic>.from((current['overrides'] as Map?) ?? const {}),
      ...row,
    };

    final updated = await _db
        .from('user_saved_recipes')
        .update({'overrides': overrides})
        .eq('id', id)
        .eq('user_id', user.id)
        .select('id');
    // RLS บล็อกการแก้ไขจะไม่ error แต่ได้แถวกลับมา 0 แถว
    if (updated.isEmpty) {
      throw 'ไม่พบสูตรนี้ หรือไม่มีสิทธิ์แก้ไข';
    }
    return warnings;
  }

  /// ลบสูตรออกจากรายการที่บันทึกไว้ของผู้ใช้ (สูตรในคลังกลางยังอยู่)
  static Future<void> deleteSavedRecipe(Object id) async {
    final user = _db.auth.currentUser;
    if (user == null) throw 'ไม่พบผู้ใช้งาน กรุณาเข้าสู่ระบบใหม่';
    await _db
        .from('user_saved_recipes')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);
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
