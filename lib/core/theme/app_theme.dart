import 'package:flutter/material.dart';

/// Sumi & Washi Zen Editorial design system for Edge Translator.
class AppTheme {
  AppTheme._();

  // Warm Washi Paper Palette
  static const Color washi = Color(0xFFFAF7F2);
  static const Color washiSubtle = Color(0xFFF3EFE8);
  static const Color washiCard = Color(0xFFFFFFFF);
  static const Color recordingSurfaceHigh = Color(0xFFEAE5E1);

  // Sumi Ink Palette
  static const Color sumi = Color(0xFF1A1817);
  static const Color sumiMuted = Color(0xFF6E6862);
  static const Color outlineMuted = Color(0xFF8D706C);

  // Hanko Cinnabar Accents
  static const Color cinnabar = Color(0xFFC33A2B);
  static const Color cinnabarDeep = Color(0xFF981E11);
  static const Color cinnabarLight = Color(0xFFFAECE9);

  // Organic Secondary & Structural Hairlines
  static const Color bamboo = Color(0xFF2D6A4F);
  static const Color bambooLight = Color(0xFFE9F4EE);
  static const Color lineSubtle = Color(0xFFEBE5DC);
  static const Color outlineVariant = Color(0xFFE1BFB9);

  // Semantic aliases preserved for shared helpers
  static const Color background = washi;
  static const Color surface = washiCard;
  static const Color surfaceElevated = washiSubtle;
  static const Color cardBorder = lineSubtle;
  static const Color primaryNeon = cinnabar;
  static const Color primaryBlue = cinnabarDeep;
  static const Color successEmerald = bamboo;
  static const Color warningAmber = Color(0xFFB45309);
  static const Color errorRose = cinnabarDeep;
  static const Color textPrimary = sumi;
  static const Color textSecondary = sumiMuted;
  static const Color textMuted = sumiMuted;

  static const List<String> _minchoFallbacks = [
    'Noto Serif JP',
    'Noto Serif CJK JP',
    'Shippori Mincho',
    'Hiragino Mincho ProN',
    'Yu Mincho',
    'MS PMincho',
    'serif',
  ];

  static const List<String> _sansFallbacks = [
    'DM Sans',
    'Noto Sans',
    'Roboto',
    'Segoe UI',
    'sans-serif',
  ];

  /// Editorial Japanese serif style using bundled/system Mincho fallbacks (100% offline).
  static TextStyle minchoStyle({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w500,
    double? height,
    double? letterSpacing,
    Color color = sumi,
  }) {
    return TextStyle(
      fontFamily: 'Noto Serif JP',
      fontFamilyFallback: _minchoFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  /// Offline cursive brush-script style for the "IKHO" brand wordmark.
  static TextStyle cursiveBrandStyle({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 1.0,
    Color color = sumi,
  }) {
    return TextStyle(
      fontFamily: 'IKHOCursive',
      fontFamilyFallback: const ['cursive', 'serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      height: 1.1,
    );
  }

  /// Clean geometric sans style for UI chrome and English text.
  static TextStyle sansStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color color = sumi,
  }) {
    return TextStyle(
      fontFamilyFallback: _sansFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: washi,
      colorScheme: const ColorScheme.light(
        primary: cinnabar,
        secondary: bamboo,
        surface: washiCard,
        error: cinnabarDeep,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: sumi,
      ),
      dividerColor: lineSubtle,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: sumi,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: sumi,
        contentTextStyle: const TextStyle(color: washi, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: washiCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: lineSubtle, width: 1),
        ),
      ),
    );
  }
}
