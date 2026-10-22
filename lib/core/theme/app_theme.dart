import 'package:flutter/material.dart';

/// Premium dark-mode design system for Edge Translator.
class AppTheme {
  AppTheme._();

  // Color Tokens
  static const Color background = Color(0xFF0B0F17);
  static const Color surface = Color(0xFF131B2B);
  static const Color surfaceElevated = Color(0xFF1E293B);
  static const Color cardBorder = Color(0xFF2E3D56);

  static const Color primaryNeon = Color(0xFF00E5FF);
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color accentIndigo = Color(0xFF6366F1);

  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRose = Color(0xFFF43F5E);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primaryNeon,
        secondary: primaryBlue,
        surface: surface,
        error: errorRose,
        onPrimary: Color(0xFF001F29),
        onSecondary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
    );
  }
}
