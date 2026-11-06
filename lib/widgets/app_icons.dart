import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ไอคอน SVG ที่ดึงเส้นพาธจริงจากไฟล์ Figma ต้นฉบับ (ไม่ใช่ไอคอนประมาณจาก Material Icons)
/// เก็บรวมไว้ที่นี่เพื่อใช้ซ้ำได้หลายหน้า/หลายจุดในแอป

/// ไอคอนกรอบมุมแบบ viewfinder เฉยๆ (ไม่มีรูปข้างใน)
/// ใช้กับ: แท็บ "สแกน" ในแถบเมนูด้านล่าง, ไอคอนหัวข้อหน้าสแกนต่างๆ
class ViewfinderIcon extends StatelessWidget {
  final double size;
  final Color color;

  const ViewfinderIcon({
    super.key,
    this.size = 24,
    this.color = Colors.black87,
  });

  static const String _svg = '''
<svg width="64" height="64" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M6.66669 21.8321C6.94402 16.2321 7.77335 12.7387 10.2587 10.2587C12.7387 7.77341 16.232 6.94408 21.832 6.66675M57.3334 21.8321C57.056 16.2321 56.2267 12.7387 53.7414 10.2587C51.2614 7.77341 47.768 6.94408 42.168 6.66675M42.168 57.3334C47.768 57.0561 51.2614 56.2267 53.7414 53.7414C56.2267 51.2614 57.056 47.7681 57.3334 42.1681M21.832 57.3334C16.232 57.0561 12.7387 56.2267 10.2587 53.7414C7.77335 51.2614 6.94402 47.7681 6.66669 42.1681" stroke="black" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// ไอคอน "ถ่ายภาพวัตถุดิบ" (กรอบมุม viewfinder + รูปแอปเปิ้ล) ตรงตัวจาก Figma
/// (ต้นฉบับชื่อ hugeicons:meal-scan) — วางไว้ในหน้าเลือกสแกน
class MealScanIcon extends StatelessWidget {
  final double size;
  final Color color;

  const MealScanIcon({super.key, this.size = 64, this.color = Colors.black87});

  static const String _svg = '''
<svg width="64" height="64" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M6.66669 21.8321C6.94402 16.2321 7.77335 12.7387 10.2587 10.2587C12.7387 7.77341 16.232 6.94408 21.832 6.66675M57.3334 21.8321C57.056 16.2321 56.2267 12.7387 53.7414 10.2587C51.2614 7.77341 47.768 6.94408 42.168 6.66675M42.168 57.3334C47.768 57.0561 51.2614 56.2267 53.7414 53.7414C56.2267 51.2614 57.056 47.7681 57.3334 42.1681M21.832 57.3334C16.232 57.0561 12.7387 56.2267 10.2587 53.7414C7.77335 51.2614 6.94402 47.7681 6.66669 42.1681M37.9254 22.6667C41.1867 22.6667 45.3334 25.3334 45.3334 30.2321C45.3334 34.6427 44.592 37.7947 41.6294 41.5787C39.3787 44.1334 36.3707 44.7734 33.1654 42.9841L32 42.3894L30.8347 42.9841C27.6294 44.7734 24.6214 44.1334 22.3707 41.5787C19.408 37.7947 18.6667 34.6454 18.6667 30.2321C18.6667 25.3334 22.816 22.6667 26.0747 22.6667C29.3334 22.6667 30.6667 24.0001 32 25.3334C33.3334 24.0001 34.6667 22.6667 37.9254 22.6667Z" stroke="black" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M34.6667 17.3335C33.3333 18.6668 32 21.3335 32 25.3335" stroke="black" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// ไอคอน "สแกนสูตรอาหาร" (เอกสาร + แว่นขยาย) ตรงตัวจาก Figma
/// (ต้นฉบับชื่อ material-symbols-light:document-scanner-outline) — ใช้แทน
/// Icons.document_scanner_outlined ตัวประมาณเดิม เพื่อความเป๊ะกับดีไซน์
class DocumentScannerRawIcon extends StatelessWidget {
  final double size;
  final Color color;

  const DocumentScannerRawIcon({
    super.key,
    this.size = 60,
    this.color = Colors.black87,
  });

  static const String _svg = '''
<svg width="60" height="60" viewBox="0 0 60 60" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M6.25 13.75V3.75H16.25V6.25H8.75V13.75H6.25ZM51.25 13.75V6.25H43.75V3.75H53.75V13.75H51.25ZM6.25 56.25V46.25H8.75V53.75H16.25V56.25H6.25ZM43.75 56.25V53.75H51.25V46.25H53.75V56.25H43.75ZM16.25 44.71C16.25 45.095 16.41 45.4483 16.73 45.77C17.05 46.0917 17.4025 46.2517 17.7875 46.25H42.2125C42.5958 46.25 42.9483 46.09 43.27 45.77C43.5917 45.45 43.7517 45.0967 43.75 44.71V15.29C43.75 14.905 43.59 14.5517 43.27 14.23C42.95 13.9083 42.5967 13.7483 42.21 13.75H17.79C17.405 13.75 17.0517 13.91 16.73 14.23C16.4083 14.55 16.2483 14.9033 16.25 15.29V44.71ZM17.79 48.75C16.6383 48.75 15.6775 48.365 14.9075 47.595C14.1375 46.825 13.7517 45.8633 13.75 44.71V15.29C13.75 14.1383 14.1358 13.1775 14.9075 12.4075C15.6792 11.6375 16.64 11.2517 17.79 11.25H42.2125C43.3625 11.25 44.3233 11.6358 45.095 12.4075C45.8667 13.1792 46.2517 14.14 46.25 15.29V44.7125C46.25 45.8625 45.865 46.8233 45.095 47.595C44.325 48.3667 43.3633 48.7517 42.21 48.75H17.79ZM23.75 23.75H36.25V21.25H23.75V23.75ZM23.75 31.25H36.25V28.75H23.75V31.25ZM23.75 38.75H36.25V36.25H23.75V38.75ZM16.25 44.71V13.75V46.25V44.71Z" fill="black"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// ==== ไอคอนที่พี่ export เป็น PNG จาก Figma มาให้โดยตรง (assets/icons/) ====
/// ไอคอนกลุ่มนี้เป็นรูปภาพที่ export มาแล้ว (ไม่ใช่เวกเตอร์เส้น) จึงไม่ใส่
/// colorFilter ทับ เพื่อให้แสดงผลตรงกับต้นฉบับจาก Figma เป๊ะๆ

/// ไอคอนตู้เย็น — ใช้กับแท็บ "หน้าหลัก" ในแถบเมนูด้านล่าง
class FridgeIcon extends StatelessWidget {
  final double size;
  const FridgeIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/fridge.png', width: size, height: size);
  }
}

/// ไอคอนสแกน (กรอบมุม viewfinder) — ใช้ทั้งที่ป้าย "สแกน" บนหัวหน้าสแกน
/// และแท็บ "สแกน" ในแถบเมนูด้านล่าง (เป็นไอคอนเดียวกันตามการทำงาน)
class ScannerIcon extends StatelessWidget {
  final double size;
  const ScannerIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/scan.png', width: size, height: size);
  }
}

/// ไอคอนรายการ (list) — ใช้กับแท็บ "คลัง" ในแถบเมนูด้านล่าง
class ListIcon extends StatelessWidget {
  final double size;
  const ListIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/list.png', width: size, height: size);
  }
}

/// ไอคอนหมวกเชฟ — ใช้กับแท็บ "เมนูอาหาร" ในแถบเมนูด้านล่าง
class ChefIcon extends StatelessWidget {
  final double size;
  const ChefIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/chef.png', width: size, height: size);
  }
}

/// ไอคอนกระดิ่งแจ้งเตือน — ใช้กับแท็บ "แจ้งเตือน" ในแถบเมนูด้านล่าง
class NotificationIcon extends StatelessWidget {
  final double size;
  const NotificationIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/notification.png',
      width: size,
      height: size,
    );
  }
}

/// ไอคอนปฏิทิน — ใช้กับแท็บ "แพลน" ในแถบเมนูด้านล่าง
class CalendarIcon extends StatelessWidget {
  final double size;
  const CalendarIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/calendar.png', width: size, height: size);
  }
}

/// ไอคอนตัวกรอง (เส้น 3 ขีดลดหลั่น) — ใช้กับปุ่มวงกลมมุมขวาบนของหน้าสแกน
class FilterIcon extends StatelessWidget {
  final double size;
  const FilterIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/filter.png', width: size, height: size);
  }
}

/// ไอคอนปุ่มย้อนกลับ (ลูกศรโค้งหัวม้วนแบบลายเส้นมือวาด) — ตรงจาก Figma
/// ใช้แทน Icons.undo / Icons.arrow_back เดิม เพื่อให้ตรงกับดีไซน์ทุกหน้า
/// (หน้าสแกนทั้งหมดและหน้าคลัง)
class BackIcon extends StatelessWidget {
  final double size;
  const BackIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/back.png', width: size, height: size);
  }
}

/// ไอคอนติ๊กถูก (เส้นหนาสไตล์ลายเส้นมือวาด) — ตรงจาก Figma
/// ใช้แทน Icons.check เดิมในหน้าสแกน/ผลลัพธ์สแกน เพื่อให้ตรงกับดีไซน์
class CheckIcon extends StatelessWidget {
  final double size;
  const CheckIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/check.png', width: size, height: size);
  }
}
