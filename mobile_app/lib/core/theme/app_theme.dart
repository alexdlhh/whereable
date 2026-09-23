import 'package:flutter/material.dart';

/// Paleta de campo: alto contraste, lectura en taller y de noche.
class AppColors {
  static const Color bg = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF121821);
  static const Color surfaceAlt = Color(0xFF1A222D);
  static const Color elevated = Color(0xFF222C38);
  static const Color border = Color(0xFF2A3441);
  static const Color accent = Color(0xFF2EE6C7);
  static const Color accentDim = Color(0xFF163F3A);
  static const Color warning = Color(0xFFF5C542);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color success = Color(0xFF4ADE80);
  static const Color text = Color(0xFFE8EEF4);
  static const Color muted = Color(0xFF8B97A6);
  static const Color info = Color(0xFF7DD3FC);
}

class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.warning,
      surface: AppColors.surface,
      error: AppColors.danger,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: AppColors.text,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.elevated,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.accentDim,
        labelStyle: const TextStyle(color: AppColors.text, fontSize: 12),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.elevated,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      dividerColor: AppColors.border,
    );
  }
}
