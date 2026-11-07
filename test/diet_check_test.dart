import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/diet_check.dart';

void main() {
  test('ไม่มีข้อจำกัด: ผ่านทุกอย่าง', () {
    expect(DietCheck.fits('ไม่มี', ['หมูสับ', 'น้ำปลา']), isTrue);
    expect(DietCheck.fits(null, ['ไก่']), isTrue);
  });

  test('มังสวิรัติ: ห้ามเนื้อสัตว์และเครื่องปรุงจากสัตว์ แต่กินไข่/นมได้', () {
    expect(DietCheck.violations('มังสวิรัติ', ['หมูสับ', 'ผักบุ้ง']), [
      'หมูสับ',
    ]);
    expect(DietCheck.fits('มังสวิรัติ', ['น้ำปลา']), isFalse);
    expect(DietCheck.fits('มังสวิรัติ', ['ซอสหอยนางรม']), isFalse);
    expect(DietCheck.fits('มังสวิรัติ', ['เนื้อวัว']), isFalse);
    expect(DietCheck.fits('มังสวิรัติ', ['ไข่ไก่', 'นมวัว', 'เต้าหู้']), isTrue);
    expect(DietCheck.fits('มังสวิรัติ', ['ไข่ปลา']), isFalse);
    expect(DietCheck.fits('มังสวิรัติ', ['หมูเจ', 'ไก่เทียม']), isTrue);
    expect(DietCheck.fits('มังสวิรัติ', ['เนื้อมะพร้าว']), isTrue);
  });

  test('เจ: ห้ามเนื้อสัตว์ ไข่ นม และผักฉุน', () {
    expect(DietCheck.fits('เจ', ['ไข่ไก่']), isFalse);
    expect(DietCheck.fits('เจ', ['นมสด']), isFalse);
    expect(DietCheck.fits('เจ', ['กระเทียม']), isFalse);
    expect(DietCheck.fits('เจ', ['ต้นหอม']), isFalse);
    expect(DietCheck.fits('เจ', ['ข้าวหอมมะลิ', 'เต้าหู้', 'นมถั่วเหลือง']), isTrue);
    expect(DietCheck.fits('เจ', ['หมูเจ']), isTrue);
  });

  test('ไม่ทานนม: ห้ามนมและผลิตภัณฑ์นม แต่นมพืชได้', () {
    expect(DietCheck.fits('ไม่ทานนม', ['เนยจืด']), isFalse);
    expect(DietCheck.fits('ไม่ทานนม', ['ชีส']), isFalse);
    expect(DietCheck.fits('ไม่ทานนม', ['นมถั่วเหลือง', 'เนยถั่ว', 'หมู']), isTrue);
  });

  test('namesOf: ดึงชื่อจาก ingredients', () {
    expect(
      DietCheck.namesOf([
        {'name': 'หมู', 'quantity': '1 ส่วน'},
        'ข้อมูลผิดรูป',
      ]),
      ['หมู'],
    );
    expect(DietCheck.namesOf(null), isEmpty);
  });
}
