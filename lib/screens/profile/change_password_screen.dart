import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ChangePasswordScreen extends StatefulWidget {

  const ChangePasswordScreen({super.key});


  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();

}




class _ChangePasswordScreenState
    extends State<ChangePasswordScreen> {


  final supabase =
  Supabase.instance.client;



  final passwordController =
  TextEditingController();


  final confirmPasswordController =
  TextEditingController();



  bool hidePassword = true;

  bool hideConfirm = true;

  bool loading = false;





  @override
  void dispose(){

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();

  }






  // =========================
  // Password Requirement
  // =========================


  bool get hasMinLength =>
      passwordController.text.length >= 8;


  bool get hasUppercase =>
      RegExp(r'[A-Z]')
          .hasMatch(passwordController.text);



  bool get hasLowercase =>
      RegExp(r'[a-z]')
          .hasMatch(passwordController.text);



  bool get hasNumber =>
      RegExp(r'[0-9]')
          .hasMatch(passwordController.text);



  bool get hasSpecial =>
      RegExp(r'[!@#$%^&*]')
          .hasMatch(passwordController.text);







  bool get passwordValid =>

      hasMinLength &&

      hasUppercase &&

      hasLowercase &&

      hasNumber &&

      hasSpecial;









  Future<void> changePassword() async {



    final password =
    passwordController.text.trim();


    final confirm =
    confirmPasswordController.text.trim();





    if(!passwordValid){


      showMessage(
          "รหัสผ่านไม่ตรงตามเงื่อนไข"
      );


      return;


    }




    if(password != confirm){


      showMessage(
          "รหัสผ่านไม่ตรงกัน"
      );


      return;


    }






    setState((){


      loading=true;


    });






    try{



      await supabase.auth.updateUser(



        UserAttributes(

          password:
          password,

        ),



      );






      if(mounted){



        ScaffoldMessenger.of(context)
            .showSnackBar(


          const SnackBar(

            content:
            Text(
                "เปลี่ยนรหัสผ่านเรียบร้อย"
            ),


          ),


        );



        Navigator.pop(context);



      }





    }

    on AuthException catch(e){



      showMessage(e.message);



    }


    catch(e){



      showMessage(
          "เกิดข้อผิดพลาด กรุณาลองใหม่"
      );



    }




    finally{


      if(mounted){


        setState((){


          loading=false;


        });


      }


    }



  }






  void showMessage(String message){


    ScaffoldMessenger.of(context)
        .showSnackBar(


      SnackBar(

        content:
        Text(message),

      ),


    );


  }
    Widget passwordCheck(
      String text,
      bool status,
      ) {


    return Row(

      children: [


        Icon(

          status
              ? Icons.check_circle
              : Icons.radio_button_unchecked,


          size:16,


          color:

          status

              ? const Color(0xff5189C9)

              : Colors.grey,


        ),



        const SizedBox(width:8),



        Text(

          text,


          style: TextStyle(


            fontSize:13,


            color:

            status

                ? const Color(0xff5189C9)

                : Colors.grey,


          ),


        ),


      ],


    );


  }








  Widget buildPasswordField(

      String label,

      TextEditingController controller,

      bool hide,

      VoidCallback toggle,

      Function(String) onChanged,

      ){



    return TextField(



      controller:
      controller,



      obscureText:
      hide,



      onChanged:
      onChanged,



      decoration:
      InputDecoration(



        labelText:
        label,



        prefixIcon:
        const Icon(

          Icons.lock_outline,

          color:
          Color(0xff5189C9),

        ),




        suffixIcon:
        IconButton(



          icon:
          Icon(


            hide

                ?

            Icons.visibility

                :

            Icons.visibility_off,


          ),



          onPressed:
          toggle,


        ),






        filled:
        true,



        fillColor:
        Colors.white,



        border:
        OutlineInputBorder(



          borderRadius:
          BorderRadius.circular(20),



          borderSide:
          BorderSide.none,


        ),



      ),


    );


  }









  @override
  Widget build(BuildContext context) {


    return Scaffold(



      backgroundColor:
      const Color(0xffD8EEFF),






      body:
      SafeArea(



        child:
        Padding(



          padding:
          const EdgeInsets.all(20),




          child:
          Column(



            crossAxisAlignment:
            CrossAxisAlignment.start,



            children:[




              IconButton(



                icon:
                const Icon(


                  Icons.arrow_back,


                  size:30,


                  color:
                  Color(0xff5189C9),


                ),




                onPressed:(){


                  Navigator.pop(context);


                },



              ),






              const SizedBox(height:20),






              const Center(



                child:
                Text(



                  "เปลี่ยนรหัสผ่าน",




                  style:
                  TextStyle(



                    fontSize:26,


                    fontWeight:
                    FontWeight.bold,


                    color:
                    Color(0xff5189C9),



                  ),



                ),



              ),





              const SizedBox(height:35),






              buildPasswordField(



                "รหัสผ่านใหม่",


                passwordController,


                hidePassword,



                    (){


                  setState((){


                    hidePassword =
                    !hidePassword;


                  });


                },



                    (value){


                  setState((){});


                },


              ),







              const SizedBox(height:12),






              passwordCheck(

                "อย่างน้อย 8 ตัวอักษร",

                hasMinLength,

              ),



              passwordCheck(

                "ตัวพิมพ์ใหญ่ A-Z",

                hasUppercase,

              ),



              passwordCheck(

                "ตัวพิมพ์เล็ก a-z",

                hasLowercase,

              ),



              passwordCheck(

                "ตัวเลข 0-9",

                hasNumber,

              ),



              passwordCheck(

                "อักขระพิเศษ !@#\$%^&*",

                hasSpecial,

              ),







              const SizedBox(height:20),






              buildPasswordField(



                "ยืนยันรหัสผ่าน",


                confirmPasswordController,


                hideConfirm,



                    (){


                  setState((){


                    hideConfirm =
                    !hideConfirm;


                  });


                },



                    (value){


                  setState((){});


                },


              ),







              const Spacer(),






              SizedBox(



                width:
                double.infinity,



                height:
                55,



                child:
                ElevatedButton(



                  onPressed:

                  loading || !passwordValid

                      ?

                  null

                      :

                  changePassword,





                  style:
                  ElevatedButton.styleFrom(



                    backgroundColor:
                    const Color(0xffffd84d),



                    disabledBackgroundColor:
                    Colors.grey.shade300,



                    foregroundColor:
                    const Color(0xff5189C9),




                    shape:
                    RoundedRectangleBorder(



                      borderRadius:
                      BorderRadius.circular(20),



                    ),



                  ),






                  child:

                  loading


                      ?

                  const CircularProgressIndicator(

                    color:
                    Color(0xff5189C9),

                  )


                      :



                  const Text(



                    "บันทึกรหัสผ่านใหม่",




                    style:
                    TextStyle(



                      fontSize:18,


                      fontWeight:
                      FontWeight.bold,



                    ),



                  ),



                ),



              ),





            ],



          ),



        ),



      ),



    );


  }

}