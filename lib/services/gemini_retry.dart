import 'dart:async'; // ใช้ TimeoutException (error ตอนรอนานเกินกำหนด)

import 'package:google_generative_ai/google_generative_ai.dart'; // ไลบรารีเรียก AI Gemini

import 'package:test_app/services/ai_request_log.dart'; // ฟังก์ชันบันทึกประวัติการใช้ AI

/// error ฝั่งเซิร์ฟเวอร์ของ Gemini ที่เกิดจากโมเดลมีคนใช้งานพร้อมกันเยอะชั่วคราว
/// (503 / UNAVAILABLE / high demand) — ไม่ใช่บั๊กของแอป รอแป๊บนึงแล้วลองใหม่
/// มักจะผ่าน
bool isGeminiOverloaded(Object e) {
  final message = e.toString(); // แปลง error เป็นข้อความ
  return message.contains('503') || // มีรหัส 503 (เซิร์ฟเวอร์ไม่ว่าง)
      message.contains('UNAVAILABLE') ||
      message.contains('high demand');
}

/// เรียก generateContent แล้วลองใหม่อัตโนมัติถ้า Gemini ตอบว่าคนใช้เยอะชั่วคราว
/// (รอ 2 วินาที แล้ว 4 วินาที) ก่อนจะโยน error ให้หน้าจอแสดงให้ผู้ใช้เห็นจริงๆ
///
/// [logEvent] = ประเภทงานใน AiEvent -> บันทึกผลลง ai_request_logs ให้อัตโนมัติ
/// (สำเร็จ = 'gemini', ไม่สำเร็จ = 'failed') ถ้าไม่ส่งมาจะไม่บันทึก
Future<GenerateContentResponse> generateContentWithRetry(
  GenerativeModel model, // โมเดลที่จะเรียก
  List<Content> content, { // สิ่งที่ส่งให้ AI (ข้อความ/รูป)
  int maxAttempts = 3, // ลองได้สูงสุด 3 ครั้ง (แก้เลขเพื่อลองมาก/น้อยลง)
  Duration timeout = const Duration(seconds: 30), // รอคำตอบนานสุด 30 วินาทีต่อครั้ง
  String? logEvent,
  String? logImageHash,
}) async {
  for (int attempt = 1; ; attempt++) { // วนลองไปเรื่อยๆ (นับครั้งที่ลอง)
    try {
      final res = await model.generateContent(content).timeout(timeout); // ส่งไปให้ AI และรอคำตอบ
      if (logEvent != null) { // ถ้าให้บันทึกประวัติ
        logAiRequest(
          event: logEvent,
          result: AiResult.gemini, // บันทึกว่าสำเร็จ
          model: geminiModel,
          usage: res.usageMetadata, // จำนวน token ที่ใช้
          imageHash: logImageHash,
        );
      }
      return res; // ส่งคำตอบกลับ
    } catch (e) {
      if (isGeminiOverloaded(e) && attempt < maxAttempts) { // AI ไม่ว่าง และยังลองได้อีก
        await Future.delayed(Duration(seconds: 2 * attempt)); // รอ 2 วิ, 4 วิ ... แล้วค่อยลองใหม่
        continue; // กลับไปลองรอบถัดไป
      }
      if (logEvent != null) {
        logAiRequest(
          event: logEvent,
          result: AiResult.failed, // บันทึกว่าล้มเหลว
          model: geminiModel,
          imageHash: logImageHash,
        );
      }
      rethrow; // โยน error ต่อให้หน้าจอแสดง
    }
  }
}

/// โมเดล Gemini ที่ทุกหน้าในแอปใช้ (แก้ที่นี่ที่เดียว)
const String geminiModel = 'gemini-3.6-flash';

/// เรียก Gemini ด้วย [geminiModel] — ลองใหม่อัตโนมัติเมื่อคนใช้เยอะชั่วคราว
/// (503) ตาม generateContentWithRetry
Future<GenerateContentResponse> generateGemini({
  required String apiKey, // คีย์ใช้งาน AI
  required List<Content> content, // สิ่งที่ส่งให้ AI
  GenerationConfig? generationConfig, // ตั้งค่าการตอบ (เช่น ให้ตอบเป็น JSON)
  Duration timeout = const Duration(seconds: 30),
  String? logEvent,
}) {
  final model = GenerativeModel( // สร้างตัวเรียกโมเดล
    model: geminiModel,
    apiKey: apiKey,
    generationConfig: generationConfig,
  );
  return generateContentWithRetry( // เรียกผ่านตัวที่ลองใหม่ได้
    model,
    content,
    timeout: timeout,
    logEvent: logEvent,
  );
}

/// ใช้ AI ครบโควตาแล้ว (429 / RESOURCE_EXHAUSTED / exceeded your current quota)
/// — โควตานับต่อ Google Cloud project ไม่ใช่ต่อคีย์ ลองใหม่ทันทีก็ไม่ผ่าน
/// จึงไม่ retry อัตโนมัติ (generateContentWithRetry ลองใหม่เฉพาะ 503)
bool isGeminiQuotaExceeded(Object e) {
  final message = e.toString();
  return message.contains('429') ||
      message.contains('RESOURCE_EXHAUSTED') ||
      message.contains('exceeded your current quota');
}

/// ดึงเวลาที่ต้องรอจากข้อความ error ("Please retry in 7h29m27.79s") มาบอก
/// ผู้ใช้เป็นภาษาไทย เช่น "7 ชั่วโมง 29 นาที" — null ถ้าไม่มีข้อมูล
String? _retryAfterText(Object e) {
  final m = RegExp(
    r'retry in (?:(\d+)h)?(?:(\d+)m)?(?:([\d.]+)s)?', // รูปแบบหาตัวเลข ชั่วโมง/นาที/วินาที
  ).firstMatch(e.toString());
  if (m == null) return null; // ไม่เจอข้อมูลเวลา
  final h = int.tryParse(m.group(1) ?? '') ?? 0; // ชั่วโมง
  final min = int.tryParse(m.group(2) ?? '') ?? 0; // นาที
  if (h > 0) return '$h ชั่วโมง${min > 0 ? ' $min นาที' : ''}';
  if (min > 0) return '$min นาที';
  return 'ไม่กี่วินาที';
}

/// ข้อความ error ภาษาไทยที่อ่านเข้าใจสำหรับแสดงผู้ใช้
String geminiErrorMessage(Object e, {String fallback = 'วิเคราะห์ไม่สำเร็จ'}) {
  if (e is TimeoutException) { // รอนานเกินกำหนด
    return 'AI ใช้เวลาวิเคราะห์นานเกินไป ลองใหม่อีกครั้ง '
        '(ถ้ารูปมีวัตถุดิบหลายชิ้น ลองถ่ายทีละน้อยชิ้นลง)';
  }
  if (isGeminiQuotaExceeded(e)) { // โควตาหมด
    final wait = _retryAfterText(e);
    return 'ใช้ AI ครบโควตาของวันนี้แล้ว'
        '${wait == null ? '' : ' ใช้ได้อีกครั้งในอีกประมาณ $wait'}';
  }
  if (isGeminiOverloaded(e)) { // AI ไม่ว่าง
    return 'ตอนนี้ AI มีคนใช้งานเยอะ ลองใหม่อีกครั้งอีกสักครู่นะครับ';
  }
  return '$fallback: $e'; // error อื่นๆ แสดงข้อความดิบต่อท้าย
}
