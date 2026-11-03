import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:test_app/screens/auth/login_screen.dart';
import 'package:test_app/screens/home/main_menu_screen.dart';
import 'package:test_app/screens/auth/reset_password_screen.dart';
import 'package:test_app/services/notification_service.dart';
import 'package:test_app/services/remember_me.dart';


final GlobalKey<NavigatorState> navigatorKey =
GlobalKey<NavigatorState>();

// กดลิงก์รีเซ็ตรหัสผ่านตอนแอปปิดอยู่ แล้วแลก session เสร็จก่อนหน้าจอพร้อม
bool passwordRecoveryPending = false;





Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();


  await Supabase.initialize(

    url: 'https://qwxjxtzyowhhkhkjtjhj.supabase.co',

    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF3eGp4dHp5b3doaGtoa2p0amhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjE5OTQsImV4cCI6MjA5ODM5Nzk5NH0.Xvl_9Rf40Ge1hIL7u5MRREPbctNKJyOJJt_AuckeR1A',

  );


  // ฟังตั้งแต่ตรงนี้ เพื่อไม่ให้พลาดกรณีเปิดแอปจากลิงก์รีเซ็ตรหัสผ่าน
  Supabase.instance.client.auth.onAuthStateChange.listen(

    (state){

      if(state.event != AuthChangeEvent.passwordRecovery) return;

      final navigator = navigatorKey.currentState;

      if(navigator == null){

        passwordRecoveryPending = true;

        return;

      }

      navigator.pushAndRemoveUntil(

        MaterialPageRoute(

          builder:(_)=>

          const ResetPasswordScreen(),

        ),

        (route)=>false,

      );

    },

    onError:(_){},

  );


  await NotificationService.init();

  // ไม่ได้ติ๊ก Remember me ตอน login ครั้งก่อน ให้ล้างเซสชันที่ค้างอยู่
  // session หายทันทีตอนเรียก ส่วนการแจ้งเซิร์ฟเวอร์ไม่ต้องรอ (ออฟไลน์ก็เปิดแอปได้)
  if (Supabase.instance.client.auth.currentSession != null &&
      !await RememberMe.isEnabled()) {
    Supabase.instance.client.auth.signOut().catchError((_) {});
  }

  // ถ้ามีเซสชันผู้ใช้ค้างอยู่แล้ว (เปิดแอปโดยไม่ต้อง login ใหม่) ให้ซิงก์
  // แจ้งเตือนของที่อยู่ในตู้เย็นนานทันทีตั้งแต่แอปเปิด ไม่ต้องรอให้ไปเปิดหน้าคลังก่อน
  // (fire-and-forget ไม่ให้บล็อกการเปิดแอป)
  NotificationService.scheduleExpiryReminders().catchError((_) {});


await Future.delayed(
  const Duration(seconds: 3)
);







  runApp(
    const MyApp(),
  );

}








class MyApp extends StatefulWidget {


  const MyApp({super.key});


  @override
  State<MyApp> createState() =>
      _MyAppState();


}








class _MyAppState extends State<MyApp> {



  final appLinks = AppLinks();

  Uri? lastResetLink;





  @override
  void initState(){


    super.initState();


    initDeepLink();

    listenForExpiredSession();


  }




  // เซสชันที่จำไว้ใช้ต่อไม่ได้แล้ว (เช่น token หมดอายุ) ให้กลับไปหน้า Login
  // ส่วนการออกจากระบบเองแต่ละหน้าพาไปหน้า Login อยู่แล้ว จึงไม่ต้องจัดการที่นี่
  void listenForExpiredSession(){


    Supabase.instance.client.auth.onAuthStateChange.listen(

      (state){


        if(state.event == AuthChangeEvent.signedOut &&

            state.signOutReason != SignOutReason.userInitiated){


          navigatorKey.currentState?.pushAndRemoveUntil(

            MaterialPageRoute(

              builder:(_)=>

              const LoginScreen(),

            ),

            (route)=>false,

          );


        }


      },

      onError:(_){},

    );


  }








  Future<void> initDeepLink() async {



    // กรณีกดลิงก์ตอน App ปิดอยู่

    final initialUri =
    await appLinks.getInitialLink();



    if(initialUri != null){

      handleDeepLink(initialUri);

    }






    // กรณีกดลิงก์ตอน App เปิดอยู่

    appLinks.uriLinkStream.listen((uri){


      handleDeepLink(uri);


    });



  }









  Future<void> handleDeepLink(Uri uri) async {



    // การแลก code เป็น session supabase_flutter ทำให้เองอยู่แล้ว (ห้ามเรียกซ้ำ
    // เพราะ code ใช้ได้ครั้งเดียว) แล้วจะแจ้ง passwordRecovery มาให้ listener ใน main()
    // ตรงนี้จึงเหลือแค่แจ้งเตือนกรณีลิงก์ใช้ไม่ได้ เช่น หมดอายุหรือเคยกดไปแล้ว
    if(uri.scheme == "smartfridge" &&

        uri.host == "reset-password" &&

        uri != lastResetLink &&

        (uri.queryParameters.containsKey("error") ||

            Uri.splitQueryString(uri.fragment).containsKey("error"))){


      lastResetLink = uri;


      WidgetsBinding.instance.addPostFrameCallback((_){


        final context = navigatorKey.currentContext;


        if(context == null) return;


        ScaffoldMessenger.of(context).showSnackBar(

          const SnackBar(

            content:
            Text("ลิงก์รีเซ็ตรหัสผ่านหมดอายุหรือถูกใช้ไปแล้ว กรุณาขอลิงก์ใหม่"),

          ),

        );


      });


    }



  }









  @override
  Widget build(BuildContext context) {


    return MaterialApp(


      debugShowCheckedModeBanner:false,



      navigatorKey:
      navigatorKey,



      theme:
      ThemeData(



        primarySwatch:
        Colors.orange,



        // ฟอนต์ตรงตามดีไซน์ Figma (Inter) แทนของเดิมที่พิมพ์ชื่อฟอนต์ผิด
        // จน Flutter มองไม่เห็นและใช้ฟอนต์ default ของเครื่องแทนมาตลอด
        // ใช้ไฟล์ฟอนต์ที่แนบมากับแอปเอง (ประกาศไว้ใน pubspec.yaml) แทนการให้
        // google_fonts โหลดจากเน็ตตอนเปิดแอป เพื่อไม่ให้พลาดกรณีไม่มีอินเทอร์เน็ต
        fontFamily:
        'Inter',



        scaffoldBackgroundColor:
        const Color(0xFFFFF9E6),




        appBarTheme:
        const AppBarTheme(



          backgroundColor:
          Colors.transparent,



          elevation:
          0,



          iconTheme:
          IconThemeData(

            color:
            Colors.black,

          ),



        ),






        elevatedButtonTheme:
        ElevatedButtonThemeData(



          style:
          ElevatedButton.styleFrom(



            backgroundColor:
            const Color(0xffffd84d),



            foregroundColor:
            const Color(0xff5189C9),



            shape:
            RoundedRectangleBorder(



              borderRadius:
              BorderRadius.circular(25),



            ),



          ),



        ),



      ),






      home:
      passwordRecoveryPending
          ? const ResetPasswordScreen()
          : Supabase.instance.client.auth.currentSession != null
          ? const MainMenuScreen()
          : const LoginScreen(),



    );


  }


}