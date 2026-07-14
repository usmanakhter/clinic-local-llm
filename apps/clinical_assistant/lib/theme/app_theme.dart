import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clinical reference tokens — medical teal / slate (no purple AI cliché).
class AppColors {
  static const Color teal = Color(0xFF0D7377);
  static const Color tealDark = Color(0xFF095456);
  static const Color tealSoft = Color(0xFFE6F3F3);
  static const Color slate900 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color warningStrip = Color(0xFFFEF3C7);
  static const Color warningText = Color(0xFF92400E);
  static const Color offlineStrip = Color(0xFF1E293B);
  static const Color offlineText = Color(0xFFE2E8F0);
  static const Color danger = Color(0xFFB91C1C);
  static const Color major = Color(0xFFC2410C);
  static const Color moderate = Color(0xFFB45309);
  static const Color minor = Color(0xFF486581);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        secondary: AppColors.slate700,
        surface: AppColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );

    final textTheme = GoogleFonts.notoSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.slate900,
      displayColor: AppColors.slate900,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSans(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.tealSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.notoSans(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.tealDark : AppColors.slate500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.tealDark : AppColors.slate500,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.slate200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.slate200),
    );
  }

  static Color severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'contraindicated':
        return AppColors.danger;
      case 'major':
        return AppColors.major;
      case 'moderate':
        return AppColors.moderate;
      case 'minor':
        return AppColors.minor;
      default:
        return AppColors.slate500;
    }
  }
}
