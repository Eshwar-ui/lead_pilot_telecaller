import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.springWood,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blueRibbon,
        primary: AppColors.blueRibbon,
        secondary: AppColors.electricViolet,
        surface: AppColors.white,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme.apply(
        bodyColor: AppColors.merlin,
        displayColor: AppColors.zeus,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.zeus,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: AppColors.westar,
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.westar),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.blueRibbon,
      ),
    );
  }
}

abstract final class AppText {
  static TextStyle get display24 => GoogleFonts.dmSans(
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.48,
    color: AppColors.zeus,
  );

  static TextStyle get display16 => GoogleFonts.dmSans(
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.32,
    color: AppColors.zeus,
  );

  static TextStyle get display20 => GoogleFonts.dmSans(
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.zeus,
  );

  static TextStyle get body14 => GoogleFonts.plusJakartaSans(
    fontSize: 14,
    height: 20.25 / 14,
    fontWeight: FontWeight.w400,
    color: AppColors.merlin,
  );

  static TextStyle get body13 => GoogleFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.merlin,
  );

  static TextStyle get label11 => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.88,
    color: AppColors.schooner,
  );

  static TextStyle get caption11 => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.tide,
  );

  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.schooner,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
}

abstract final class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 3),
  ];

  static const blueAction = [
    BoxShadow(color: Color(0x402E4AFF), offset: Offset(0, 4), blurRadius: 7),
  ];
}
