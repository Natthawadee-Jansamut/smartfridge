import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();

    // ตั้งค่าสำหรับ Android
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ตั้งค่าสำหรับ iOS
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await notifications.initialize(settings);
  }

  // ฟังก์ชันสั่งแสดงแจ้งเตือน
  static Future<void> showExpiryAlert({required String message}) async {
    const androidDetails = AndroidNotificationDetails(
      'smart_fridge_channel',
      'Expiry Alerts',
      channelDescription: 'Notifications for expiring food items',
      importance: Importance.max,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await notifications.show(1, "SmartFridge.AI", message, notificationDetails);
  }
}
