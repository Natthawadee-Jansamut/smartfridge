import 'dart:async';

import 'package:google_generative_ai/google_generative_ai.dart';

/// error ฝั่งเซิร์ฟเวอร์ของ Gemini ที่เกิดจากโมเดลมีคนใช้งานพร้อมกันเยอะชั่วคราว
/// (503 / UNAVAILABLE / high demand) — ไม่ใช่บั๊กของแอป รอแป๊บนึงแล้วลองใหม่
/// มักจะผ่าน
bool isGeminiOverloaded(Object e) {
  final message = e.toString();
  return message.contains('503') ||
      message.contains('UNAVAILABLE') ||
      message.contains('high demand');
}

/// เรียก generateContent แล้วลองใหม่อัตโนมัติถ้า Gemini ตอบว่าคนใช้เยอะชั่วคราว
/// (รอ 2 วินาที แล้ว 4 วินาที) ก่อนจะโยน error ให้หน้าจอแสดงให้ผู้ใช้เห็นจริงๆ
Future<GenerateContentResponse> generateContentWithRetry(
  GenerativeModel model,
  List<Content> content, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 30),
}) async {
  for (int attempt = 1; ; attempt++) {
    try {
      return await model.generateContent(content).timeout(timeout);
    } catch (e) {
      if (!isGeminiOverloaded(e) || attempt >= maxAttempts) rethrow;
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
  }
}

/// โมเดล Gemini ที่ทุกหน้าในแอปใช้ (แก้ที่นี่ที่เดียว)
const String geminiModel = 'gemini-3.6-flash';

/// เรียก Gemini ด้วย [geminiModel] — ลองใหม่อัตโนมัติเมื่อคนใช้เยอะชั่วคราว
/// (503) ตาม generateContentWithRetry
Future<GenerateContentResponse> generateGemini({
  required String apiKey,
  required List<Content> content,
  GenerationConfig? generationConfig,
  Duration timeout = const Duration(seconds: 30),
}) {
  final model = GenerativeModel(
    model: geminiModel,
    apiKey: apiKey,
    generationConfig: generationConfig,
  );
  return generateContentWithRetry(model, content, timeout: timeout);
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
  final m = RegExp(r'retry in (?:(\d+)h)?(?:(\d+)m)?(?:([\d.]+)s)?')
      .firstMatch(e.toString());
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? '') ?? 0;
  final min = int.tryParse(m.group(2) ?? '') ?? 0;
  if (h > 0) return '$h ชั่วโมง${min > 0 ? ' $min นาที' : ''}';
  if (min > 0) return '$min นาที';
  return 'ไม่กี่วินาที';
}

/// ข้อความ error ภาษาไทยที่อ่านเข้าใจสำหรับแสดงผู้ใช้
String geminiErrorMessage(Object e, {String fallback = 'วิเคราะห์ไม่สำเร็จ'}) {
  if (e is TimeoutException) {
    return 'AI ใช้เวลาวิเคราะห์นานเกินไป ลองใหม่อีกครั้ง '
        '(ถ้ารูปมีวัตถุดิบหลายชิ้น ลองถ่ายทีละน้อยชิ้นลง)';
  }
  if (isGeminiQuotaExceeded(e)) {
    final wait = _retryAfterText(e);
    return 'ใช้ AI ครบโควตาของวันนี้แล้ว'
        '${wait == null ? '' : ' ใช้ได้อีกครั้งในอีกประมาณ $wait'}';
  }
  if (isGeminiOverloaded(e)) {
    return 'ตอนนี้ AI มีคนใช้งานเยอะ ลองใหม่อีกครั้งอีกสักครู่นะครับ';
  }
  return '$fallback: $e';
}
