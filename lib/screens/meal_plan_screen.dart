import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'weekly_plan_screen.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/app_icons.dart';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import '../config/api_keys.dart';
import '../services/fridge_stock.dart';
import '../services/gemini_retry.dart';
import '../utils/fridge_age.dart';



class MealPlanScreen extends StatefulWidget {

  const MealPlanScreen({super.key});


  @override
  State<MealPlanScreen> createState() =>
      _MealPlanScreenState();

}





class _MealPlanScreenState
    extends State<MealPlanScreen>{


  final supabase =
  Supabase.instance.client;



 
  final String apiKey = ApiKeys.mealPlanScreen;



  String goal = "ลดน้ำหนัก";

  int meals = 3;

  String diet = "ไม่มี";


  bool loading = false;



  final calorieController =
  TextEditingController();



  final proteinController =
  TextEditingController();









  Future<void> createMealPlan() async{


    final user =
    supabase.auth.currentUser;



    if(user == null) return;




    setState((){

      loading=true;

    });





    try{


      // ===============================
      // ดึงข้อมูลของในตู้เย็น
      // ===============================


      final fridgeItems = await supabase

          .from('fridge_items')

          .select()

          .eq(

          'user_id',

          user.id

      );





      // รวมลอตที่ชื่อ/หน่วยเดียวกันเป็นรายการเดียวก่อนส่งให้ Gemini
      // ของที่เกินระยะที่เก็บได้แล้วไม่ส่งให้ AI เอาไปวางแผน (อาจไม่ปลอดภัย)
      final fridgeList = inventoryPromptList(
        List<Map<String, dynamic>>.from(fridgeItems)
            .where((e) => !isOverdue(e))
            .toList(),
      );






      if(fridgeList.isEmpty){


        throw Exception(

            "ไม่มีวัตถุดิบในตู้เย็น"

        );


      }

      // ===============================
      // หาวัตถุดิบที่อยู่ในตู้เย็นนานแล้ว (เอาไว้ให้ Gemini เลือกใช้ก่อน)
      // อิงรูปแบบเดียวกับ ai_recipe_screen.dart
      // ===============================
      final expiringSoon = <Map<String, dynamic>>[];

      for (var item in fridgeItems) {
        // เฉพาะของที่เก็บได้อีกไม่เกินจำนวนวันที่ตั้งแจ้งเตือนไว้ (นับเป็นวัน) และ
        // ยังไม่ได้ใช้หมด
        if (!shouldUseFirst(item, readOldItemDays(user))) continue;

        expiringSoon.add({
          'name': item['name'],
          'days_in_fridge': daysInFridge(item['created_at']),
        });
      }

      // ของที่อยู่ในตู้เย็นนานที่สุดขึ้นก่อน
      expiringSoon.sort(
        (a, b) => (b['days_in_fridge'] as int)
            .compareTo(a['days_in_fridge'] as int),
      );

      final expiringList = expiringSoon.map((e) => e['name']).join(", ");

      // ===============================
      // คลังเมนูที่เคยสร้างไว้แล้ว (ประหยัด token ไม่ต้องยิง Gemini ใหม่
      // ถ้าเมนูเก่ามีวัตถุดิบพอกับของในตู้เย็นตอนนี้อยู่แล้ว)
      // ===============================
      final myPlans = await supabase
          .from('meal_plans')
          .select('id')
          .eq('user_id', user.id);

      final planIds = myPlans.map((p) => p['id']).toList();

      List<dynamic> pastMeals = [];
      if (planIds.isNotEmpty) {
        pastMeals = await supabase
            .from('weekly_meals')
            .select()
            .inFilter('plan_id', planIds);
      }

      // รวมเป็นคลังเมนู ตัดชื่อซ้ำออก (เก็บล่าสุดของแต่ละชื่อ) และข้ามเมนูที่
      // ข้อมูลไม่ครบ (เช่นของเก่าก่อนมีคอลัมน์ steps จึงยังไม่มีขั้นตอนการทำ)
      final Map<String, Map<String, dynamic>> libraryByName = {};
      for (final m in pastMeals) {
        final name = (m['food_name']?.toString() ?? '').trim();
        final ingredients = m['ingredients'];
        final steps = m['steps']?.toString().trim() ?? '';
        if (name.isEmpty ||
            ingredients is! List ||
            ingredients.isEmpty ||
            steps.isEmpty) {
          continue;
        }
        libraryByName[name] = Map<String, dynamic>.from(m);
      }
      final library = libraryByName.values.toList();

      // แยกตัวเลขปริมาณออกจากข้อความ เช่น "1 ชิ้น" -> 1, "1/2 หัว" -> 0.5
      double parseQtyAmount(String qtyText) {
        final fraction =
            RegExp(r'(\d+(\.\d+)?)\s*/\s*(\d+(\.\d+)?)').firstMatch(qtyText);
        if (fraction != null) {
          final numerator = double.tryParse(fraction.group(1) ?? '') ?? 0;
          final denominator = double.tryParse(fraction.group(3) ?? '') ?? 1;
          return denominator == 0 ? 0 : numerator / denominator;
        }
        final single = RegExp(r'\d+(\.\d+)?').firstMatch(qtyText);
        return double.tryParse(single?.group(0) ?? '') ?? 0;
      }

      // เช็คว่าวัตถุดิบทุกอย่างของเมนูนี้ มีพอในตู้เย็นตอนนี้จริงไหม
      bool allIngredientsAvailable(List ingredients) {
        for (final ing in ingredients) {
          final name = (ing['name']?.toString() ?? '').trim().toLowerCase();
          if (name.isEmpty) continue;

          final needAmount =
              parseQtyAmount(ing['quantity']?.toString() ?? '');
          if (needAmount <= 0) continue;

          final matches = fridgeItems.where((item) {
            final itemName =
                (item['name']?.toString() ?? '').trim().toLowerCase();
            return itemName.isNotEmpty &&
                (itemName == name ||
                    itemName.contains(name) ||
                    name.contains(itemName));
          });

          if (matches.isEmpty) return false;

          final haveQty = matches
              .map((m) => num.tryParse(m['quantity']?.toString() ?? '') ?? 0)
              .fold<num>(0, (a, b) => a + b);

          if (haveQty < needAmount.ceil()) return false;
        }
        return true;
      }

      final expiringNamesLower = expiringSoon
          .map((e) => (e['name']?.toString() ?? '').trim().toLowerCase())
          .toSet();

      bool usesExpiringIngredient(List ingredients) {
        return ingredients.any((ing) {
          final name = (ing['name']?.toString() ?? '').trim().toLowerCase();
          return expiringNamesLower.any(
            (e) => e == name || e.contains(name) || name.contains(e),
          );
        });
      }

      // เมนูเก่าที่วัตถุดิบครบพอใช้ได้เลยตอนนี้ — สุ่มลำดับก่อน แล้วเอาเมนูที่
      // ใช้ของที่อยู่ในตู้เย็นนานขึ้นก่อน เพื่อความหลากหลายและช่วยเคลียร์ของเก่า
      final matched = library
          .where((m) => allIngredientsAvailable(m['ingredients'] as List))
          .toList();
      matched.shuffle();
      matched.sort((a, b) {
        final aExp =
            usesExpiringIngredient(a['ingredients'] as List) ? 0 : 1;
        final bExp =
            usesExpiringIngredient(b['ingredients'] as List) ? 0 : 1;
        return aExp.compareTo(bExp);
      });

      // ช่องมื้ออาหารทั้งสัปดาห์ (วัน x จำนวนมื้อต่อวัน)
      final weekDaysEn = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ];
      final slotGrid = <Map<String, String>>[];
      for (final day in weekDaysEn) {
        for (var i = 1; i <= meals; i++) {
          slotGrid.add({'day': day, 'meal_type': 'มื้อที่ $i'});
        }
      }

      final reuseCount =
          matched.length < slotGrid.length ? matched.length : slotGrid.length;

      final reusedMeals = <Map<String, dynamic>>[];
      for (var i = 0; i < reuseCount; i++) {
        final slot = slotGrid[i];
        final source = matched[i];
        reusedMeals.add({
          'day': slot['day'],
          'meal_type': slot['meal_type'],
          'food_name': source['food_name'],
          'calories': source['calories'],
          'protein': source['protein'],
          'ingredients': source['ingredients'],
          'steps': source['steps'],
        });
      }

      // ช่องที่เหลือ (ถ้ามี) ค่อยให้ Gemini สร้างเสริมเฉพาะส่วนที่ขาด — ถ้า
      // เมนูเก่าครบพอทั้งสัปดาห์แล้ว ช่องนี้จะว่างและไม่ต้องเรียก Gemini เลย
      final remainingSlots = slotGrid.sublist(reuseCount);






      // ===============================
      // สร้างข้อมูล plan
      // ===============================


      final plan = await supabase

          .from('meal_plans')

          .insert({

        'user_id':
        user.id,


        'goal':
        goal,


        'meals_per_day':
        meals,


        'target_calories':
        int.tryParse(
            calorieController.text
        ) ?? 2000,


        'target_protein':
        int.tryParse(
            proteinController.text
        ) ?? 100,


        'diet_type':
        diet,


      })

          .select()

          .single();





      final planId =
      plan['id'];









      // ===============================
      // Gemini — เรียกเฉพาะตอนที่เมนูเก่าในคลังไม่พอเติมเต็มสัปดาห์เท่านั้น
      // ถ้า remainingSlots ว่าง (เมนูเก่าครบพอแล้ว) จะข้ามส่วนนี้ไปเลย
      // เพื่อประหยัด token/การเรียกใช้ API
      // ===============================

      List<dynamic> geminiMeals = [];

      if (remainingSlots.isNotEmpty) {








      final slotsJson = remainingSlots
          .map((s) => '{"day":"${s['day']}","meal_type":"${s['meal_type']}"}')
          .join(",\n");

      final usedNames = reusedMeals
          .map((m) => m['food_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(", ");

      final prompt = """

คุณเป็น AI Nutritionist


ใช้วัตถุดิบจากตู้เย็นของผู้ใช้เท่านั้น


วัตถุดิบที่มี:

$fridgeList



วัตถุดิบที่อยู่ในตู้เย็นมานานแล้ว (พยายามบังคับใช้ในเมนูก่อนวัตถุดิบอื่น):

${expiringList.isEmpty ? "ไม่มี" : expiringList}



เป้าหมาย:

$goal



Calories:

${calorieController.text} kcal



Protein:

${proteinController.text} g



ข้อจำกัดอาหาร:

$diet



สร้างเมนูเฉพาะสำหรับช่องต่อไปนี้เท่านั้น จำนวน ${remainingSlots.length} มื้อ
(ระบุ day และ meal_type ให้ตรงกับที่กำหนดมาเป๊ะๆ ห้ามเพิ่มหรือลดจำนวน):

[
$slotsJson
]

${usedNames.isEmpty ? "" : "ห้ามสร้างเมนูซ้ำกับเมนูต่อไปนี้ที่ใช้ไปแล้วในสัปดาห์นี้: $usedNames"}



กฎ:

- ห้ามสร้างวัตถุดิบที่ไม่มีในรายการ
- ใช้วัตถุดิบที่มีอยู่ให้คุ้มค่า
- ให้ความสำคัญกับวัตถุดิบที่อยู่ในตู้เย็นมานานก่อนเป็นอันดับแรก
- สามารถใช้วัตถุดิบเดิมซ้ำได้
- ระบุ ingredients ของแต่ละมื้อ โดยเลือกจากวัตถุดิบที่มีเท่านั้น พร้อมปริมาณที่ใช้
- ปริมาณที่ใช้ต้องเป็นหน่วยเดียวกับวัตถุดิบที่มี (เช่น ส่วน, ฟอง, ผล, หัว) ห้ามใช้กรัม/กก./มล./ช้อน
  เพราะผู้ใช้ไม่ได้ชั่งตวง (1 ส่วน ≈ ใช้ทำอาหาร 1 ครั้ง ใช้ "1/2 ส่วน" ได้)
- ระบุ steps เป็นขั้นตอนการทำอาหารแบบละเอียด เรียงเป็นข้อๆ (array ของ string ภาษาไทย)
- ส่งออก JSON เท่านั้น




รูปแบบ:

[
{
"day":"Monday",
"meal_type":"มื้อที่ 1",
"food_name":"ข้าวอกไก่ไข่ดาว",
"calories":450,
"protein":35,
"ingredients":[
{"name":"อกไก่","quantity":"1 ชิ้น"},
{"name":"ไข่ไก่","quantity":"1 ฟอง"}
],
"steps":[
"หั่นอกไก่เป็นชิ้นพอดีคำ",
"ทอดไข่ดาวจนสุกตามชอบ",
"นำอกไก่ไปย่างหรือผัดจนสุก จัดใส่จาน"
]
}
]


""";






      // Gemini ตอบ 503 "high demand" ได้เป็นพักๆ ลองใหม่อัตโนมัติก่อนแจ้ง error
      final result = await generateGemini(
        apiKey: apiKey,
        content: [Content.text(prompt)],
        timeout: const Duration(seconds: 90),
      );






      String json =

      result!.text!

          .replaceAll(

          "```json",

          ""

      )

          .replaceAll(

          "```",

          ""

      )

          .trim();







      geminiMeals = jsonDecode(json);
      }

      // รวมเมนูที่หยิบจากคลังเก่า (ประหยัด token) กับเมนูใหม่จาก Gemini
      // (ถ้ามี) เข้าด้วยกันเป็นแผนอาหารสัปดาห์เดียว
      final List mealsData = [...reusedMeals, ...geminiMeals];







      // ===============================
      // บันทึก weekly_meals
      // ===============================

      // ชื่อวัตถุดิบที่มีจริงในตู้เย็น (normalize ไว้เทียบแบบไม่สนตัวพิมพ์/ช่องว่าง)
      final fridgeNames = fridgeItems
          .map((item) => (item['name']?.toString() ?? '').trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .toList();

      bool inFridge(String ingredientName) {
        final normalized = ingredientName.trim().toLowerCase();
        if (normalized.isEmpty) return false;
        return fridgeNames.any(
          (n) => n.contains(normalized) || normalized.contains(n),
        );
      }

      for(var meal in mealsData){


        // วัตถุดิบของมื้อนี้ (มาจาก Gemini โดยอิงของจริงในตู้เย็นเท่านั้น)
        // checked สะท้อนของจริงในตู้เย็น ณ ตอนสร้างแผน ไม่ใช่ค่าคงที่
        final ingredientsList = (meal['ingredients'] as List? ?? [])
            .map((ing) {
              final name = ing['name']?.toString() ?? '';
              return {
                'name': name,
                'quantity': ing['quantity']?.toString() ?? '',
                'checked': inFridge(name),
              };
            })
            .toList();

        // ขั้นตอนการทำอาหารจาก Gemini (อาจส่งมาเป็น array หรือ string ก็ได้)
        final stepsRaw = meal['steps'];
        String stepsText;
        if (stepsRaw is List) {
          stepsText = stepsRaw
              .asMap()
              .entries
              .map((e) => "${e.key + 1}. ${e.value}")
              .join("\n");
        } else {
          stepsText = stepsRaw?.toString() ?? '';
        }


        await supabase

            .from('weekly_meals')

            .insert({

          'plan_id':

          planId,


          'day':

          meal['day'],



          'meal_type':

          meal['meal_type'],



          'food_name':

          meal['food_name'],



          'calories':

          meal['calories'],



          'protein':

          meal['protein'],


          'ingredients':

          ingredientsList,

          'steps':

          stepsText,


          'is_cooked':

          false,


        });


      }







      Navigator.push(

        context,

        MaterialPageRoute(

          builder:(_)=>

          WeeklyPlanScreen(

            planId:

            planId,

          ),

        ),

      );




    }

    catch(e){



      ScaffoldMessenger.of(context)

          .showSnackBar(

        SnackBar(

          content:

          Text(

              geminiErrorMessage(e, fallback: "สร้างแผนไม่สำเร็จ")

          ),

        ),

      );



    }



    finally{


      setState((){

        loading=false;

      });


    }


  }
  @override
  Widget build(BuildContext context){


    return Scaffold(


      backgroundColor:
      const Color(0xffD8EEFF),



      body:

      SafeArea(

        child:

        SingleChildScrollView(

          padding:
          const EdgeInsets.all(20),



          child:
          Column(

            crossAxisAlignment:
            CrossAxisAlignment.start,


            children:[



              _buildHeader(context),



              const SizedBox(height:20),




              buildTitle(
                  Icons.track_changes,
                  "เป้าหมาย"
              ),






              buildChoiceCard(

                  "ลดน้ำหนัก",

                  "ควบคุม Calories",

                  goal=="ลดน้ำหนัก",

                      (){


                    setState((){

                      goal="ลดน้ำหนัก";

                    });


                  }

              ),






              buildChoiceCard(

                  "รักษาน้ำหนัก",

                  "Balance สุขภาพ",

                  goal=="รักษาน้ำหนัก",

                      (){


                    setState((){

                      goal="รักษาน้ำหนัก";

                    });


                  }

              ),






              buildChoiceCard(

                  "เพิ่มกล้ามเนื้อ",

                  "High Protein",

                  goal=="เพิ่มกล้ามเนื้อ",

                      (){


                    setState((){

                      goal="เพิ่มกล้ามเนื้อ";

                    });


                  }

              ),





              const SizedBox(height:20),





              buildTitle(
                  Icons.brunch_dining,
                  "จำนวนมื้อต่อวัน"
              ),





              _buildMealCounter(),






              const SizedBox(height:20),





              buildTitle(
                  Icons.local_fire_department,
                  "เป้าหมายโภชนาการ"
              ),






              buildInput(

                  "Calories ต่อวัน",

                  calorieController,

                  "kcal"

              ),





              const SizedBox(height:15),





              buildInput(

                  "Protein ต่อวัน",

                  proteinController,

                  "g"

              ),






              const SizedBox(height:20),





              buildTitle(
                  Icons.block,
                  "ข้อจำกัดอาหาร"
              ),






              _buildDietDropdown(),






              const SizedBox(height:35),






              _buildCreateButton(),



            ],


          ),


        ),


      ),




      bottomNavigationBar:

      const AppBottomNav(current: AppTab.plan),



    );


  }









  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.pop(context);
          },
          child: Container(
            height: 45,
            width: 45,
            decoration: BoxDecoration(
              color: const Color(0xfffff7d0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: BackIcon(size: 20)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7D0),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Row(
              children: [
                CalendarIcon(size: 22),
                SizedBox(width: 10),
                Text(
                  "สร้างแพลนอาหาร",
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 50,
          width: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const InkWell(
            customBorder: CircleBorder(),
            child: Center(child: FilterIcon(size: 20)),
          ),
        ),
      ],
    );
  }









  Widget _buildMealCounter(){


    return Container(

      padding:
      const EdgeInsets.all(15),



      decoration:
      boxDecoration(),



      child:
      Row(

        mainAxisAlignment:
        MainAxisAlignment.spaceBetween,


        children:[



          IconButton(

            icon:
            const Icon(Icons.remove),



            onPressed:(){

              if(meals>1){


                setState((){

                  meals--;

                });


              }


            },


          ),






          Text(

            "$meals มื้อ",


            style:
            const TextStyle(

              fontSize:20,

              fontWeight:
              FontWeight.bold,

            ),


          ),






          IconButton(

            icon:
            const Icon(Icons.add),



            onPressed:(){

              setState((){

                meals++;

              });


            },


          ),



        ],


      ),


    );


  }









  Widget _buildDietDropdown(){


    return Container(

      padding:
      const EdgeInsets.symmetric(
          horizontal:15
      ),


      decoration:
      boxDecoration(),



      child:
      DropdownButtonHideUnderline(


        child:
        DropdownButton<String>(


          value:
          diet,


          isExpanded:
          true,


          items:[


            "ไม่มี",

            "มังสวิรัติ",

            "เจ",

            "ไม่ทานนม"


          ]

              .map(

                  (e)=>

                  DropdownMenuItem(

                    value:e,

                    child:
                    Text(e),

                  )

          )

              .toList(),




          onChanged:(value){


            setState((){


              diet=value!;


            });


          },


        ),


      ),


    );


  }









  Widget _buildCreateButton(){


    return SizedBox(


      width:
      double.infinity,



      height:
      55,



      child:
      ElevatedButton(



        style:
        ElevatedButton.styleFrom(



          backgroundColor:
          const Color(0xFFFFF7D0),



          foregroundColor:
          Colors.black87,



          shape:
          RoundedRectangleBorder(



            borderRadius:
            BorderRadius.circular(25),


          ),



        ),




        onPressed:

        loading

            ?

        null

            :

        createMealPlan,



        child:

        loading

            ?

        const CircularProgressIndicator()



            :


        const Text(



          "สร้างแผนอาหารจากของในตู้เย็น",



          style:
          TextStyle(

            fontSize:16,

            fontWeight:
            FontWeight.bold,

          ),



        ),


      ),



    );


  }
  Widget buildTitle(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black87),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }








  Widget buildChoiceCard(

      String title,

      String sub,

      bool selected,

      VoidCallback tap,

      ){


    return GestureDetector(


      onTap:
      tap,



      child:
      Container(


        margin:
        const EdgeInsets.only(bottom:10),



        padding:
        const EdgeInsets.all(15),



        decoration:
        BoxDecoration(



          color:

          selected

              ?

          const Color(0xfffff7d0)

              :

          Colors.white,



          borderRadius:
          BorderRadius.circular(20),



        ),




        child:
        Row(



          children:[



            Icon(



              selected

                  ?

              Icons.radio_button_checked

                  :

              Icons.radio_button_off,



            ),





            const SizedBox(width:15),






            Column(



              crossAxisAlignment:
              CrossAxisAlignment.start,



              children:[



                Text(



                  title,



                  style:
                  const TextStyle(



                    fontSize:16,

                    fontWeight:
                    FontWeight.bold,



                  ),



                ),




                Text(sub),



              ],



            )



          ],



        ),



      ),



    );



  }









  Widget buildInput(

      String label,

      TextEditingController controller,

      String suffix,


      ){



    return Container(



      decoration:
      boxDecoration(),




      child:
      TextField(



        controller:
        controller,



        keyboardType:
        TextInputType.number,




        decoration:
        InputDecoration(



          labelText:
          label,



          suffixText:
          suffix,



          border:
          InputBorder.none,



          contentPadding:
          const EdgeInsets.all(15),



        ),



      ),



    );



  }









  BoxDecoration boxDecoration(){



    return BoxDecoration(



      color:
      Colors.white,



      borderRadius:
      BorderRadius.circular(20),



    );



  }




}
