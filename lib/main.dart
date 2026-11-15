import 'package:flutter/material.dart'; // Flutter framework for building UI
import 'package:supabase_flutter/supabase_flutter.dart'; // Supabase client for Flutter
import 'package:app_links/app_links.dart'; // For handling deep links in the app

import 'package:test_app/config/supabase_config.dart'; // Configuration for Supabase (URL and anon key)
import 'package:test_app/screens/auth/login_screen.dart';
import 'package:test_app/screens/home/main_menu_screen.dart';
import 'package:test_app/screens/auth/reset_password_screen.dart';
import 'package:test_app/screens/notification/expiration_alert_screen.dart';
import 'package:test_app/services/notification_service.dart';
import 'package:test_app/services/remember_me.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(); // ใช้สำหรับการนำทางระหว่างหน้าจอโดยไม่ต้องมี context

// กดลิงก์รีเซ็ตรหัสผ่านตอนแอปปิดอยู่ แล้วแลก session เสร็จก่อนหน้าจอพร้อม
bool passwordRecoveryPending = false; // ใช้เพื่อตรวจสอบว่ามีการรีเซ็ตรหัสผ่านที่รอดำเนินการอยู่หรือไม่

Future<void> main() async { // รอให้ Flutter framework พร้อมก่อนทำงาน
  WidgetsFlutterBinding.ensureInitialized(); // ให้แน่ใจว่า Flutter framework พร้อมก่อนทำงาน

  await Supabase.initialize( //เปิดระบบหลังบ้าน Supabase และ 'รอ' (await) จนกว่ามันจะเตรียมตัวเสร็จ
    url: SupabaseConfig.url, // URL ของ Supabase ที่เก็บไว้ในไฟล์ config/supabase_config.dart

    publishableKey: SupabaseConfig.anonKey, // คีย์อนุญาตสำหรับการเข้าถึง Supabase ที่เก็บไว้ในไฟล์ config/supabase_config.dart
  );

  // ฟังตั้งแต่ตรงนี้ เพื่อไม่ให้พลาดกรณีเปิดแอปจากลิงก์รีเซ็ตรหัสผ่าน
  Supabase.instance.client.auth.onAuthStateChange.listen((state) { //สั่งให้ฟังการเปลี่ยนแปลงสถานะการเข้าสู่ระบบของผู้ใช้ (เช่น การเข้าสู่ระบบ การออกจากระบบ การรีเซ็ตรหัสผ่าน)
    if (state.event != AuthChangeEvent.passwordRecovery) return;   // ถ้าเหตุการณ์ไม่ใช่การรีเซ็ตรหัสผ่าน ให้ข้ามไป

    final navigator = navigatorKey.currentState; //เช็คว่ามี navigator อยู่หรือไม่ (เพื่อให้สามารถนำทางไปยังหน้าจอรีเซ็ตรหัสผ่านได้)

    if (navigator == null) {
      passwordRecoveryPending = true;   // ถ้า navigator ยังไม่พร้อม ให้ตั้งค่า passwordRecoveryPending เป็น true เพื่อรอให้ navigator พร้อมก่อนนำทางไปยังหน้าจอรีเซ็ตรหัสผ่าน

      return; 
    }

    navigator.pushAndRemoveUntil( // นำทางไปยังหน้าจอรีเซ็ตรหัสผ่านและลบหน้าจออื่น ๆ ออกจาก stack
      MaterialPageRoute(builder: (_) => const ResetPasswordScreen()), // สร้าง route ใหม่ไปยังหน้าจอ ResetPasswordScreen  

      (route) => false, // ลบหน้าจออื่น ๆ ออกจาก stack (ไม่ให้ผู้ใช้ย้อนกลับไปยังหน้าจอก่อนหน้า)
    );
  }, onError: (_) {}); // ถ้ามีข้อผิดพลาดเกิดขึ้นระหว่างการฟังเหตุการณ์ ให้ทำอะไรบางอย่าง (ในที่นี้คือไม่ทำอะไรเลย)

  // กดแจ้งเตือนตอนแอปเปิดอยู่/อยู่เบื้องหลัง -> เปิดหน้าแจ้งเตือน (ต้องล็อกอินอยู่)
  NotificationService.onOpenAlerts = () {
    if (Supabase.instance.client.auth.currentSession == null) return; // ถ้าไม่มี session ของผู้ใช้ (ยังไม่ได้ล็อกอิน) ให้ข้ามไป
    navigatorKey.currentState?.push( // ถ้าล็อคอิน นำทางไปยังหน้าจอแจ้งเตือนหมดอายุ
      MaterialPageRoute(builder: (_) => const ExpirationAlertScreen()), // สร้าง route ใหม่ไปยังหน้าจอ ExpirationAlertScreen
    );
  };
  await NotificationService.init(); //สั่งเปิดระบบแจ้งเตือน (NotificationService) และรอให้มันพร้อมก่อนทำงานต่อ



  // ไม่ได้ติ๊ก Remember me ตอน login ครั้งก่อน ให้ล้างเซสชันที่ค้างอยู่
  // session หายทันทีตอนเรียก ส่วนการแจ้งเซิร์ฟเวอร์ไม่ต้องรอ (ออฟไลน์ก็เปิดแอปได้)
  if (Supabase.instance.client.auth.currentSession != null &&
      !await RememberMe.isEnabled()) { //เช็คว่าไม่ได้ล็อคอินค้างไว้และไม่ได้ติ๊ก Remember me ตอน login ครั้งก่อน
    Supabase.instance.client.auth.signOut().catchError((_) {}); // ถ้าเซิร์ฟเวอร์ไม่ตอบกลับก็ไม่ต้องสนใจ (ออฟไลน์ก็เปิดแอปได้)11
  }



  // ถ้ามีเซสชันผู้ใช้ค้างอยู่แล้ว (เปิดแอปโดยไม่ต้อง login ใหม่) ให้ซิงก์
  // แจ้งเตือนของที่อยู่ในตู้เย็นนานทันทีตั้งแต่แอปเปิด ไม่ต้องรอให้ไปเปิดหน้าคลังก่อน
  // (fire-and-forget ไม่ให้บล็อกการเปิดแอป)
  NotificationService.scheduleExpiryReminders().catchError((_) {});

  await Future.delayed(
    const Duration(seconds: 3),
  ); // หน่วง 3 วิ ให่หน้าโลโก้แสดงค้่าง ให้เบื้องหลังทำงาน

  runApp(const MyApp()); // เริ่มต้นแอป
}
//*****จบเตรียมงานหลังบ้าน********





class MyApp extends StatefulWidget { // แอปหลักของ SmartFridge.AI
  const MyApp({super.key}); // สร้าง instance ของ MyApp

  @override 
  State<MyApp> createState() => _MyAppState(); // ผูกกับคลาส _MyAppState ด้านล่างที่เก็บสถานะ/โค้ดจริง
}

class _MyAppState extends State<MyApp> { // ตัวเก็บสถานะและการทำงานของแอปหลัก
  final appLinks = AppLinks(); // สำหรับจัดการลิ้งภายนอกที่กดมาจากgmail

  Uri? lastResetLink; // เก็บลิงก์รีเซ็ตรหัสผ่านล่าสุดที่กดมา เพื่อไม่ให้แจ้งเตือนซ้ำ

  @override
  void initState() { // ทำงานครั้งเดียวตอนแอปเริ่มสร้างหน้าจอ
    super.initState(); // เรียกของเดิมของ Flutter ก่อนเสมอ

    initDeepLink(); // เปิดการจัดการลิงก์รีเซ็ตรหัสผ่าน (deep link) ตอนแอปเปิดอยู่

    listenForExpiredSession(); //เปิดการตรวจจับการออกจากระบบ
  }



  // เซสชันที่จำไว้ใช้ต่อไม่ได้แล้ว (เช่น token หมดอายุ) ให้กลับไปหน้า Login
  // ส่วนการออกจากระบบเองแต่ละหน้าพาไปหน้า Login อยู่แล้ว จึงไม่ต้องจัดการที่นี่

  void listenForExpiredSession() {
    // ฟังทุกครั้งที่สถานะล็อกอินเปลี่ยน (ล็อกอิน/ออก/token หมดอายุ ฯลฯ)
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut && // ถ้าเซสชันหมดอายุ (ไม่ได้ออกจากระบบเอง) ให้กลับไปหน้า Login
          state.signOutReason != SignOutReason.userInitiated) {
        navigatorKey.currentState?.pushAndRemoveUntil( // เด้งไปหน้า Login
          MaterialPageRoute(builder: (_) => const LoginScreen()), // หน้าที่จะไป = หน้า Login

          (route) => false, // ล้างหน้าเก่าทิ้งหมด กดย้อนกลับไม่ได้
        );
      }
    }, onError: (_) {}); // ถ้าตัวฟังมี error ก็เงียบไว้ ไม่ให้แอปพัง
  }


//เปิดช่องทางlink gmail
  Future<void> initDeepLink() async { 
    // กรณีกดลิงก์ตอน App ปิดอยู่

    final initialUri = await appLinks.getInitialLink(); //ดักกรณีแอพปิดสนิท หยิบลิ้งไปให้handleDeepLink() จัดการต่อ

    if (initialUri != null) {
      handleDeepLink(initialUri); //ตรวจสอบลิ้งว่าเสียหรือหมดอายุหรือเปล่า
    }

    // กรณีกดลิงก์ตอน App เปิดอยู่

    appLinks.uriLinkStream.listen((uri) { //ดักกรณีแอพเปิดอยู่แล้ว กดลิ้งไปให้handleDeepLink() จัดการต่อ
      handleDeepLink(uri); //ตรวจสอบลิ้งว่าเสียหรือหมดอายุหรือเปล่า
    });
  }

  // ตรวจลิงก์ที่กดเข้ามา ถ้าเป็นลิงก์รีเซ็ตรหัสที่เสีย/หมดอายุ ให้เด้งข้อความเตือน
  Future<void> handleDeepLink(Uri uri) async {
    // การแลก code เป็น session supabase_flutter ทำให้เองอยู่แล้ว (ห้ามเรียกซ้ำ
    // เพราะ code ใช้ได้ครั้งเดียว) แล้วจะแจ้ง passwordRecovery มาให้ listener ใน main()
    // ตรงนี้จึงเหลือแค่แจ้งเตือนกรณีลิงก์ใช้ไม่ได้ เช่น หมดอายุหรือเคยกดไปแล้ว
    if (uri.scheme == "smartfridge" && // ลิงก์ต้องขึ้นต้นด้วย smartfridge:// (ลิงก์ของแอปเรา)
        uri.host == "reset-password" && // และเป็นลิงก์สำหรับรีเซ็ตรหัสผ่าน
        uri != lastResetLink && //เช็คว่ายังไม่เคยแจ้งเตือนมาก่อน
        (uri.queryParameters.containsKey("error") || //เช็คว่าลิ้งเสียหรือหมดอายุหรือเปล่า
            Uri.splitQueryString(uri.fragment).containsKey("error"))) {
      lastResetLink = uri; // จำลิงก์นี้ไว้ ถ้ากดซ้ำจะไม่แจ้งซ้ำ

      WidgetsBinding.instance.addPostFrameCallback((_) { //รอให้หน้าจอวาดเสร็จก่อนแจ้งเตือน
        final context = navigatorKey.currentContext; // หยิบ context ของหน้าจอปัจจุบันมาใช้แสดงข้อความ

        if (context == null) return; // ยังไม่มีหน้าจอให้แสดง ก็ข้ามไป

        ScaffoldMessenger.of(context).showSnackBar( // แสดงแถบข้อความเด้งขึ้นจากด้านล่างจอ (SnackBar)
          const SnackBar(
            content: Text( // ข้อความที่จะแสดงในแถบ แก้ข้อความตรงนี้ได้เลย
              "ลิงก์รีเซ็ตรหัสผ่านหมดอายุหรือถูกใช้ไปแล้ว กรุณาขอลิงก์ใหม่",
            ),
          ),
        );
      });
    }
  }



//หน้าตาและโครงสร้างของแอปทั้งหมด (Theme, Font, Color, Home screen) ผ่าน MaterialApp
  @override
  Widget build(BuildContext context) {
    return MaterialApp( // กล่องใหญ่สุดของแอป ใส่ธีม สี ฟอนต์ และหน้าแรก
      title: 'SmartFridge.AI', // ชื่อแอปที่แสดงบน task switcher ของ Android และ iOS
      debugShowCheckedModeBanner: false, // ปิดแถบ debug banner ที่มุมขวาบนของแอป

      navigatorKey: navigatorKey, // ผูก navigatorKey globalเข้ากับ navigator ของ MaterialApp เพื่อให้สามารถนำทางไปยังหน้าจออื่น ๆ ได้จากที่ไหนก็ได้ในแอป

      theme: ThemeData(
        primarySwatch: Colors.orange, // สีหลักของแอป (สีวงโหลด, สีขอบช่องกรอกตอนเลือก ฯลฯ) เปลี่ยนเป็น Colors.green ฯลฯ ได้

        fontFamily: 'Inter', // กำหนด font ทั้งแอป (ต้องมีไฟล์ฟอนต์ประกาศใน pubspec.yaml) เปลี่ยนชื่อตรงนี้เพื่อเปลี่ยนฟอนต์ทั้งแอป

        scaffoldBackgroundColor: const Color(0xFFFFF9E6), // สีพื้นหลังทุกหน้า (ครีมอ่อน) รูปแบบ 0xFF + รหัสสี hex 6 หลัก

        appBarTheme: const AppBarTheme( // กำหนดธีมของ AppBar (แถบด้านบนของหน้าจอ) ของแอป
          backgroundColor: Colors.transparent, // ทำให้ AppBar เป็นโปร่งใส

          elevation: 0, // กำหนดความสูงของเงาใต้ AppBar เป็น 0 (ไม่มีเงา)

          iconTheme: IconThemeData(color: Colors.black), // กำหนดสีของไอคอนใน AppBar เป็นสีดำ
        ),

        elevatedButtonTheme: ElevatedButtonThemeData( // กำหนดธีมของ ElevatedButton (ปุ่มยกสูง) ของแอป
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xffffd84d), // สีพื้นหลังของปุ่ม

            foregroundColor: const Color(0xff5189C9), //สีอักษรของปุ่ม

            shape: RoundedRectangleBorder( // กำหนดรูปร่างของปุ่ม สี่เหลี่ยมโค้ง
              borderRadius: BorderRadius.circular(25), //โค้งรัศมี 25
            ),
          ),
        ),
      ),


//เลือกหน้าแรกของแอพ
      home: passwordRecoveryPending
          ? const ResetPasswordScreen() // หน้ารีเซ็ตรหัสผ่าน
          : Supabase.instance.client.auth.currentSession != null // ถ้ามี session ของผู้ใช้ (ล็อกอินอยู่) ให้ไปหน้า MainMenuScreen
          ? const MainMenuScreen()
          : const LoginScreen(),// ถ้าไม่มี session ของผู้ใช้ (ยังไม่ได้ล็อกอิน) ให้ไปหน้า LoginScreen
    );
  }
}
