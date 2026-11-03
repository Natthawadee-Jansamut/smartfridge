import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';


class ResetPasswordScreen extends StatefulWidget {

  const ResetPasswordScreen({super.key});


  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();

}




class _ResetPasswordScreenState
    extends State<ResetPasswordScreen> {


  final supabase =
  Supabase.instance.client;


  final passwordController =
  TextEditingController();


  final confirmPasswordController =
  TextEditingController();



  bool loading = false;

  bool obscurePassword = true;

  bool obscureConfirm = true;





  @override
  void dispose(){

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();

  }







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









  Future<void> updatePassword() async {



    final password =
    passwordController.text.trim();


    final confirm =
    confirmPasswordController.text.trim();




    if(!passwordValid){


      showMessage(
          "Password does not meet requirements"
      );


      return;


    }





    if(password != confirm){


      showMessage(
          "Passwords do not match"
      );


      return;


    }





    setState((){

      loading = true;

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
                "Password updated successfully"
            ),

          ),

        );




        Navigator.pushAndRemoveUntil(


          context,


          MaterialPageRoute(


            builder:(_)=>
            const LoginScreen(),


          ),


              (route)=>false,


        );


      }




    }

    catch(e){



      showMessage(
          e.toString()
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







  void showMessage(String text){


    ScaffoldMessenger.of(context)
        .showSnackBar(

      SnackBar(

        content:
        Text(text),

      ),

    );


  }







  Widget passwordCheck(
      String text,
      bool status,
      ){

    return Row(

      children:[


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

          style:TextStyle(

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









  @override
  Widget build(BuildContext context){


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



                padding:
                EdgeInsets.zero,



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





              const SizedBox(height:30),






              Center(

                child:
                Column(

                  children:[


                    const Icon(

                      Icons.lock_reset,

                      size:80,

                      color:
                      Color(0xff5189C9),

                    ),



                    const SizedBox(height:15),



                    const Text(

                      "Reset Password",

                      style:
                      TextStyle(

                        fontSize:26,

                        fontWeight:
                        FontWeight.bold,

                        color:
                        Color(0xff5189C9),

                      ),

                    ),


                  ],

                ),

              ),





              const SizedBox(height:35),





              TextField(


                controller:
                passwordController,


                obscureText:
                obscurePassword,


                onChanged:(value){

                  setState((){});

                },



                decoration:
                InputDecoration(



                  labelText:
                  "New Password",



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

                      obscurePassword

                          ?

                      Icons.visibility

                          :

                      Icons.visibility_off,

                    ),



                    onPressed:(){

                      setState((){

                        obscurePassword =
                        !obscurePassword;

                      });

                    },


                  ),



                  filled:true,


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

              ),





              const SizedBox(height:10),





              passwordCheck(
                "At least 8 characters",
                hasMinLength,
              ),


              passwordCheck(
                "At least 1 uppercase letter (A-Z)",
                hasUppercase,
              ),


              passwordCheck(
                "At least 1 lowercase letter (a-z)",
                hasLowercase,
              ),


              passwordCheck(
                "At least 1 number (0-9)",
                hasNumber,
              ),


              passwordCheck(
                "At least 1 special character (!@#\$%^&*)",
                hasSpecial,
              ),






              const SizedBox(height:20),






              TextField(



                controller:
                confirmPasswordController,



                obscureText:
                obscureConfirm,



                decoration:
                InputDecoration(



                  labelText:
                  "Confirm Password",



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

                      obscureConfirm

                          ?

                      Icons.visibility

                          :

                      Icons.visibility_off,

                    ),




                    onPressed:(){


                      setState((){


                        obscureConfirm =
                        !obscureConfirm;


                      });


                    },

                  ),




                  filled:true,

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

                  updatePassword,




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
                      BorderRadius.circular(25),

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

                    "Save Password",

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