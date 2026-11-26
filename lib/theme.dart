import 'package:flutter/material.dart';

// Màu sắc và kiểu dùng chung cho cả app.

const Color kBrand = Color(0xFF00796B);
const Color kBrandDark = Color(0xFF00564B);
const Color kBrandLight = Color(0xFF009F8B);

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: kBrand, brightness: brightness)
      .copyWith(
    primary: dark ? const Color(0xFF5FDBC6) : kBrand,
    surface: dark ? const Color(0xFF101413) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF101413) : const Color(0xFFF3F6F5),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

/// Màu "thành công", đủ tương phản ở cả nền sáng và tối.
Color okColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF66D17A)
        : const Color(0xFF2E7D32);

/// Khung thẻ trắng viền mảnh.
BoxDecoration boxDecoration(ColorScheme cs, {Color? color}) => BoxDecoration(
      color: color ?? cs.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cs.outlineVariant.withAlpha(130)),
    );

/// Nhãn nhỏ có nền màu nhạt.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}
