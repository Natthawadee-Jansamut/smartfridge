import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/non_food_check.dart';

void main() {
  test('บุหรี่ / สุราสำหรับดื่ม: ไม่ใช่วัตถุดิบทำอาหาร', () {
    for (final n in ['บุหรี่', 'เบียร์ช้าง', 'เหล้าขาว', 'ไวน์แดง', 'สุรา', 'Vodka']) {
      expect(NonFoodCheck.isNotForCooking(n), isTrue, reason: n);
    }
  });

  test('ยา / สารเคมี / ของใช้: ไม่ใช่วัตถุดิบทำอาหาร', () {
    for (final n in [
      'ยาพารา',
      'ยาแก้ไอ',
      'ยาหยอดตา',
      'อินซูลิน',
      'วิตามินซีแคปซูล',
      'น้ำยาล้างจาน',
      'ผงซักฟอก',
      'สบู่',
      'ครีมกันแดด',
      'แบตเตอรี่',
      'อาหารแมว',
      'ฟิล์มถนอมอาหาร',
    ]) {
      expect(NonFoodCheck.isNotForCooking(n), isTrue, reason: n);
    }
  });

  test('สุราปรุงอาหารและวัตถุดิบที่ชื่อคล้าย: ใช้ทำอาหารได้', () {
    for (final n in [
      'เหล้าจีน',
      'ไวน์ปรุงอาหาร',
      'มิริน',
      'สาเกปรุงอาหาร',
      'น้ำส้มสายชูไวน์แดง',
      'อุด้ง',
      'ginger',
      'หอยนางรมสุราษฎร์',
      'ซอสหอยนางรม',
      'หมูสามชั้น',
      'ใบยานาง',
      'ยำวุ้นเส้น',
      'วิปปิ้งครีม',
      'ปลาทราย',
    ]) {
      expect(NonFoodCheck.isNotForCooking(n), isFalse, reason: n);
    }
  });

  test('แมลง: ไม่แนะนำให้ซื้อเพิ่ม แต่น้ำพริกแมงดาซื้อได้', () {
    for (final n in ['จิ้งหรีดทอด', 'ไข่มดแดง', 'หนอนไม้', 'ดักแด้']) {
      expect(NonFoodCheck.isUncommonToBuy(n), isTrue, reason: n);
    }
    for (final n in ['น้ำพริกแมงดา', 'หมูสับ', 'ปลาร้า']) {
      expect(NonFoodCheck.isUncommonToBuy(n), isFalse, reason: n);
    }
  });
}
