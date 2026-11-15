import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ไลบรารีแจ้งเตือนในเครื่อง
import 'package:permission_handler/permission_handler.dart'; // ขอสิทธิ์แจ้งเตือน
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz; // ข้อมูลเขตเวลา (ใช้ตั้งเวลาแจ้งเตือน)
import 'package:timezone/timezone.dart' as tz;

import 'package:test_app/utils/fridge_age.dart';

/// บริการแจ้งเตือนวัตถุดิบที่ใกล้ครบอายุการเก็บรักษา — อ่านค่า "แจ้งเตือน
/// ล่วงหน้ากี่วันก่อนครบอายุการเก็บรักษา" (notify_days) ที่ผู้ใช้ตั้งไว้ในหน้า
/// notification_settings_screen.dart (เก็บใน user_metadata ของ Supabase Auth)
/// แล้วนับถอยหลังจากอายุการเก็บรักษาของวัตถุดิบแต่ละชิ้น (ดู daysLeft
/// ใน fridge_age.dart) ข้อความแจ้งเตือนบอกว่าอยู่ในตู้เย็นมาแล้วกี่วัน
///
/// ใช้ 2 กลไกร่วมกันเพราะแอปนี้เป็น client-only (ไม่มีเซิร์ฟเวอร์/ฟังก์ชัน
/// แบ็กเอนด์คอยรันตอนแอปปิดอยู่):
/// 1. scheduleExpiryReminders() — ตั้งแจ้งเตือนล่วงหน้าไว้ให้ระบบปฏิบัติการ
///    ยิงเองตอน 09:00 ของวันที่เหลือ notify_days วันก่อนครบอายุการเก็บรักษา
///    ผ่าน flutter_local_notifications ซึ่งทำงานแม้แอปถูกปิดอยู่
/// 2. checkAndShowDueReminders() — เช็กซ้ำทุกครั้งที่เปิดแอป/หน้าคลัง ว่ามี
///    วัตถุดิบที่ถึงช่วงต้องเตือนแล้ว และวันนี้ยังไม่เคยเตือน ถ้ายัง จะยิง
///    แจ้งเตือนทันที (รวมทุกรายการเป็นข้อความเดียว)
///
/// ข้อจำกัดที่ควรรู้: บน iOS ระบบปฏิบัติการจำกัดจำนวนแจ้งเตือนที่ "ตั้งรอไว้ล่วงหน้า"
/// (pending) ได้สูงสุด 64 รายการต่อแอป ถ้ามีวัตถุดิบเยอะมากพร้อมกัน อาจมีบาง
/// รายการที่ตั้งล่วงหน้าไม่ติด แต่กลไกข้อ 2 (เช็กตอนเปิดแอป) จะช่วยชดเชยได้เสมอ
class NotificationService {
  static final notifications = FlutterLocalNotificationsPlugin(); // ตัวสั่งแจ้งเตือน

  static bool _initialized = false; // เตรียมระบบแจ้งเตือนไปแล้วหรือยัง (ทำครั้งเดียวพอ)

  /// เรียกเมื่อผู้ใช้กดแจ้งเตือนตอนแอปเปิดอยู่/อยู่เบื้องหลัง — main.dart ตั้งให้
  /// เปิดหน้าแจ้งเตือน (ExpirationAlertScreen)
  static VoidCallback? onOpenAlerts;

  /// แอปถูกเปิดขึ้นมาจากการกดแจ้งเตือน (ตอนแอปปิดอยู่) — หน้าเมนูหลักจะเช็ก
  /// แล้วพาไปหน้าแจ้งเตือนครั้งเดียว ผ่าน takeOpenAlertsOnLaunch()
  static bool _openAlertsOnLaunch = false;

  /// คืน true ครั้งเดียวถ้าแอปถูกเปิดจากการกดแจ้งเตือน (เรียกซ้ำได้ false)
  static bool takeOpenAlertsOnLaunch() {
    final value = _openAlertsOnLaunch; // อ่านค่า
    _openAlertsOnLaunch = false; // รีเซ็ต จะได้ไม่พาไปซ้ำ
    return value;
  }

  // เตรียมระบบแจ้งเตือน (เรียกตอนเปิดแอปใน main.dart)
  static Future<void> init() async {
    if (_initialized) return; // เตรียมไปแล้ว ไม่ต้องทำซ้ำ

    tz.initializeTimeZones(); // โหลดข้อมูลเขตเวลา

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'), // [UI] ไอคอนเล็กบนแจ้งเตือน Android (ใช้ไอคอนแอป)
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true, // ขอสิทธิ์แสดงป๊อปอัป
        requestBadgePermission: true, // ขอสิทธิ์ตัวเลขแดงบนไอคอนแอป
        requestSoundPermission: true, // ขอสิทธิ์เสียง
      ),
    );

    await notifications.initialize(
      settings,
      // กดแจ้งเตือนตอนแอปเปิดอยู่หรืออยู่เบื้องหลัง -> ไปหน้าแจ้งเตือน
      onDidReceiveNotificationResponse: (_) => onOpenAlerts?.call(),
    );

    // กดแจ้งเตือนตอนแอปปิดอยู่ -> จำไว้ ให้หน้าเมนูหลักพาไปหน้าแจ้งเตือน
    try {
      final launch = await notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _openAlertsOnLaunch = true;
      }
    } catch (e) {
      debugPrint(
        '[NotificationService] อ่านข้อมูลการเปิดแอปจากแจ้งเตือนไม่สำเร็จ: $e',
      );
    }

    // Android 13 (API 33) ขึ้นไปต้องขอสิทธิ์แจ้งเตือนแบบ runtime permission
    // เหมือนสิทธิ์อื่นๆ (กล้อง/แกลเลอรี) ไม่ได้ขอผ่าน manifest อย่างเดียวแล้ว
    try {
      await Permission.notification.request();
    } catch (_) {
      // เครื่อง/แพลตฟอร์มที่ไม่รองรับ permission_handler ตัวนี้ (เช่นเว็บ) ข้ามไป
    }

    _initialized = true; // จำว่าเตรียมเสร็จแล้ว
  }

  // ยิงแจ้งเตือนทันที 1 อัน
  static Future<void> showExpiryAlert({required String message}) async {
    debugPrint('[NotificationService] showExpiryAlert: $message');
    await notifications.show(
      1, // id ของแจ้งเตือน (ใช้ 1 เสมอ อันใหม่จะทับอันเก่า)
      "🔔 SmartFridge", // [UI] หัวข้อแจ้งเตือน
      message, // ข้อความแจ้งเตือน
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_channel', // รหัสช่องแจ้งเตือนของ Android
          'แจ้งเตือนวัตถุดิบในตู้เย็น', // [UI] ชื่อช่องที่ผู้ใช้เห็นในตั้งค่าเครื่อง
          channelDescription: 'แจ้งเตือนเมื่อวัตถุดิบอยู่ในตู้เย็นนานแล้ว', // [UI] คำอธิบายช่อง
          importance: Importance.high, // [UI] ความสำคัญสูง = เด้งขึ้นบนจอ
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true, // [UI] แสดงป๊อปอัป
          presentBadge: true, // [UI] แสดงตัวเลขบนไอคอนแอป
          presentSound: true, // [UI] มีเสียง
          presentBanner: true, // [UI] แสดงแบนเนอร์ด้านบน (แม้แอปเปิดอยู่)
          presentList: true, // [UI] แสดงในศูนย์แจ้งเตือน
        ),
      ),
    );
  }

  // แปลง DateTime แบบ local ของเครื่อง ให้เป็น TZDateTime ที่ปลอดภัยสำหรับ
  // zonedSchedule โดยไม่ต้องพึ่งแพ็กเกจตรวจจับ timezone ของเครื่องเพิ่ม —
  // แปลงเป็น UTC ก่อนแล้วค่อยห่อด้วย tz.UTC ผลลัพธ์คือเวลาจริงตรงกับที่ตั้งไว้
  // ตามเวลาเครื่อง (Dart's DateTime() ที่ไม่ใส่ .utc คือเวลา local ของเครื่องอยู่แล้ว)
  static tz.TZDateTime _toTz(DateTime local) {
    return tz.TZDateTime.from(local.toUtc(), tz.UTC);
  }

  // แปลงข้อความเป็นเลข id ที่คงที่และไม่ติดลบ (ของชิ้นเดียวกันได้ id เดิมเสมอ)
  static int _stableId(String key) => key.hashCode & 0x7fffffff;

  /// ตั้งแจ้งเตือนล่วงหน้าให้ระบบปฏิบัติการยิงเองตามเวลาที่กำหนด สำหรับ
  /// วัตถุดิบทุกชิ้นในคลังของผู้ใช้ปัจจุบัน โดยอิงจากค่า "แจ้งเตือนเมื่ออยู่
  /// ในตู้เย็นครบกี่วัน" (notify_days) ที่ตั้งไว้ในหน้าตั้งค่า
  ///
  /// ล้างของเดิมแล้วตั้งใหม่ทั้งหมดทุกครั้ง เพื่อไม่ให้มีแจ้งเตือนค้างของ
  /// วัตถุดิบที่ถูกลบ/ทำอาหารไปแล้ว หรือวันที่เข้าตู้เย็นที่ถูกแก้ไขใหม่
  static Future<void> scheduleExpiryReminders() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return; // ยังไม่ล็อกอิน

    await init(); // เตรียมระบบแจ้งเตือนก่อน

    final notifyDays = readOldItemDays(user); // เตือนล่วงหน้ากี่วัน
    final notifyTime = readNotifyTime(user); // เตือนกี่โมง

    List<Map<String, dynamic>> items;
    try {
      final response = await supabase
          .from('fridge_items') // ดึงของในตู้ทั้งหมดของผู้ใช้
          .select()
          .eq('user_id', user.id);
      items = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[NotificationService] ดึงข้อมูล fridge_items ไม่สำเร็จ: $e');
      return; // ดึงข้อมูลไม่ได้ (ออฟไลน์ ฯลฯ) ข้ามรอบนี้ไป ไม่ทำให้แอปพัง
    }

    // ล้างแจ้งเตือนที่ตั้งไว้ล่วงหน้าของรอบก่อนหน้าทั้งหมดก่อน แล้วค่อยตั้งใหม่
    // จากข้อมูลคลังปัจจุบันจริงๆ
    await notifications.cancelAll();

    final now = DateTime.now();

    for (final item in items) { // ไล่ตั้งแจ้งเตือนทีละชิ้น
      final createdRaw = item['created_at'];
      if (createdRaw == null) continue; // ไม่รู้วันใส่ตู้ ข้าม
      if (isUsedUp(item)) continue; // ใช้หมดแล้ว ไม่ต้องเตือน

      final addedDate = parseCreatedAt(createdRaw);
      if (addedDate == null) continue;
      final addedDay = DateTime(addedDate.year, addedDate.month, addedDate.day); // วันที่ใส่ตู้ (ตัดเวลาออก)

      final name = item['name']?.toString() ?? 'วัตถุดิบ';
      final itemId = item['item_id']?.toString() ?? name;

      // นับถอยหลัง: เตือนล่วงหน้า notifyDays วันก่อนครบอายุการเก็บรักษาของชิ้นนั้น
      final remaining = daysLeft(item);
      if (remaining == null) continue; // ไม่มีข้อมูลอายุการเก็บรักษา
      final shelfEndDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: remaining.floor()));
      final triggerDay = shelfEndDay.subtract(Duration(days: notifyDays)); // วันที่จะเตือน = วันครบกำหนด - เตือนล่วงหน้า
      final ageAtTrigger = triggerDay.difference(addedDay).inDays; // วันนั้นจะอยู่ในตู้มากี่วัน (ใส่ในข้อความ)
      final triggerTime = DateTime(
        triggerDay.year,
        triggerDay.month,
        triggerDay.day,
        // เวลาที่ผู้ใช้ตั้งไว้ในหน้าตั้งค่าแจ้งเตือน (ค่าเริ่มต้น 09:00)
        notifyTime.hour,
        notifyTime.minute,
      );

      // ตั้งล่วงหน้าได้เฉพาะเวลาที่ยังไม่ผ่านไปเท่านั้น (ตั้งเวลาย้อนอดีตไม่ได้)
      // ถ้าช่วงที่ควรเตือนผ่านไปแล้ว (เช่นเพิ่งเปลี่ยนค่าวันแจ้งเตือน หรือเพิ่ง
      // มีของที่อยู่นานเกินกำหนดอยู่แล้ว) checkAndShowDueReminders() จะช่วยจับแทน
      if (triggerTime.isAfter(now)) {
        try {
          await notifications.zonedSchedule( // ตั้งแจ้งเตือนล่วงหน้าให้ระบบยิงเอง
            _stableId(itemId), // id ของแจ้งเตือน
            "🔔 SmartFridge", // [UI] หัวข้อ
            "$name อยู่ในตู้เย็นมาแล้ว ${ageAtTrigger < 0 ? 0 : ageAtTrigger} วัน — ${useWithinText(notifyDays)}",
            _toTz(triggerTime), // เวลาที่จะยิง
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'expiry_channel',
                'แจ้งเตือนวัตถุดิบในตู้เย็น',
                channelDescription:
                    'แจ้งเตือนเมื่อวัตถุดิบอยู่ในตู้เย็นนานแล้ว',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                presentBanner: true,
                presentList: true,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // ยิงได้แม้เครื่องพักหน้าจอ (เวลาอาจคลาดนิดหน่อย ประหยัดแบต)
          );
        } catch (e) {
          debugPrint(
            '[NotificationService] ตั้งแจ้งเตือนของ "$name" ไม่สำเร็จ: $e',
          );
          // ข้ามรายการนี้ไปถ้าตั้งไม่สำเร็จ (เช่น iOS เต็มโควตา 64 รายการ)
          // ไม่ให้กระทบรายการอื่น
        }
      }
    }

    // ถือโอกาสเช็กด้วยเลยว่ามีของที่อยู่นานเกินกำหนด "อยู่แล้วตอนนี้"
    // ที่พลาดช่วงเวลาที่ควรตั้งแจ้งเตือนไปแล้วหรือเปล่า จะได้ไม่พลาดแจ้งเตือน
    unawaited(checkAndShowDueReminders(items: items, notifyDays: notifyDays));
  }

  /// เช็กว่ามีวัตถุดิบที่ตอนนี้อยู่ในตู้เย็นมาแล้วตั้งแต่ notify_days วันขึ้นไป
  /// หรือไม่ ถ้ามีและยังไม่เคยแจ้งเตือนวันนี้ ให้ยิงแจ้งเตือนทันทีหนึ่งครั้ง
  /// (รวมทุกรายการเป็นข้อความเดียว) แล้วจำวันที่แจ้งเตือนล่าสุดไว้ใน
  /// user_metadata (แนวทางเดียวกับ notify_days) เพื่อไม่ให้เตือนซ้ำหลายครั้ง
  /// ในวันเดียวกันตอนเปิดแอปซ้ำๆ — เรียกซ้ำได้ทุกครั้งที่เปิดแอป/หน้าคลัง
  /// อย่างปลอดภัย
  static Future<void> checkAndShowDueReminders({
    List<Map<String, dynamic>>? items,
    int? notifyDays,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final days = notifyDays ?? readOldItemDays(user); // ใช้ค่าที่ส่งมา หรืออ่านจากตั้งค่าผู้ใช้

    List<Map<String, dynamic>> fridgeItems;
    if (items != null) {
      fridgeItems = items; // มีข้อมูลส่งมาแล้ว ไม่ต้องดึงใหม่
    } else { // ไม่มี -> ดึงจากฐานข้อมูล
      try {
        final response = await supabase
            .from('fridge_items')
            .select()
            .eq('user_id', user.id);
        fridgeItems = List<Map<String, dynamic>>.from(response);
      } catch (e) {
        debugPrint(
          '[NotificationService] ดึงข้อมูล fridge_items ไม่สำเร็จ: $e',
        );
        return;
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ยังไม่ถึงเวลาที่ผู้ใช้ตั้งไว้ของวันนี้ -> ยังไม่เตือน (แจ้งเตือนที่ตั้งเวลา
    // ล่วงหน้าไว้จะเด้งเองตอนถึงเวลา หรือเปิดแอปหลังเวลานั้นค่อยเช็กอีกรอบ)
    final notifyTime = readNotifyTime(user);
    final notifyAt = DateTime(
      today.year,
      today.month,
      today.day,
      notifyTime.hour,
      notifyTime.minute,
    );
    if (now.isBefore(notifyAt)) return;

    final List<String> oldItemNames = []; // รายชื่อของที่ถึงเวลาเตือน
    for (final item in fridgeItems) {
      if (isDueForReminder(item, days)) { // ถึงช่วงต้องเตือนแล้ว
        oldItemNames.add(item['name']?.toString() ?? 'วัตถุดิบ');
      }
    }

    if (oldItemNames.isEmpty) return; // ไม่มีของต้องเตือน

    // วันนี้ในรูปแบบ "ปปปป-ดด-วว" ไว้เทียบว่าเตือนไปแล้วหรือยัง
    final todayKey =
        "${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final lastNotified = user.userMetadata?['last_expiry_notify_date']
        ?.toString();
    if (lastNotified == todayKey) return; // วันนี้เตือนไปแล้ว ไม่เตือนซ้ำ

    // [UI] ข้อความแจ้งเตือน: ชิ้นเดียวบอกชื่อ, หลายชิ้นบอกจำนวน + ชื่อ 5 ชิ้นแรก
    final String message = oldItemNames.length == 1
        ? "${oldItemNames.first} ใกล้ครบอายุการเก็บรักษาแล้ว รีบเอาไปทำอาหารนะ!"
        : "มีวัตถุดิบใกล้ครบอายุการเก็บรักษา ${oldItemNames.length} รายการ: "
              "${oldItemNames.take(5).join(', ')}"
              "${oldItemNames.length > 5 ? ' และอื่นๆ' : ''}";

    await init();
    await showExpiryAlert(message: message); // ยิงแจ้งเตือน

    try {
      await supabase.auth.updateUser( // จำว่าวันนี้เตือนแล้ว
        UserAttributes(data: {"last_expiry_notify_date": todayKey}),
      );
    } catch (e) {
      debugPrint(
        '[NotificationService] บันทึกวันที่แจ้งเตือนล่าสุดไม่สำเร็จ: $e',
      );
      // อัปเดตวันที่แจ้งเตือนล่าสุดไม่สำเร็จ (เช่นออฟไลน์) ไม่เป็นไร รอบหน้า
      // จะลองใหม่ — อย่างมากคือแจ้งเตือนซ้ำอีกครั้งถ้าเปิดแอปวันเดียวกัน
    }
  }
}

// ช่วยให้เรียก Future แบบไม่ต้อง await ตรงๆ โดยไม่ขึ้น warning "unawaited_futures"
// (เทียบเท่า package:pedantic/unawaited แต่เขียนเองสั้นๆ พอ ไม่ต้องเพิ่ม dependency)
void unawaited(Future<void> future) {}
