import 'package:flutter/material.dart';

/// Paleta y tema visual estilo Nike Run / Apple: limpio, moderno, tecnológico.
class AppColors {
  AppColors._();

  // ─── Neutros (base Apple / Nike) ───────────────────────────────────────
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFDDE1E4);
  static const Color surfaceVariant = Color(0xFFF2F2F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Texto (jerarquía clara)
  static const Color textPrimary = Color(0xFF09090B);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFFAEAEB2);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Marca y acento (uso puntual, tipo Nike)
  static const Color primary = Color(0xFF212738);
  static const Color primaryLight = Color(0xFF2C2C2E);
  static const Color accent = Color(0xFFFF3B30);
  static const Color accentSoft = Color(0xFFFF6961);

  // UI
  static const Color border = Color(0xFFE5E5EA);
  static const Color divider = Color(0xFFC6C6C8);

  // Estados
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);
}

/// Espaciado consistente (8px base).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Tipografía estilo SF Pro / Nike: títulos grandes, cuerpo legible.
class AppTextStyle {
  AppTextStyle._();

  static TextStyle get largeTitle => const TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    color: AppColors.textPrimary,
  );

  static TextStyle get title1 => const TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
    color: AppColors.textPrimary,
  );

  static TextStyle get title2 => const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.35,
    color: AppColors.textPrimary,
  );

  static TextStyle get title3 => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
    color: AppColors.textPrimary,
  );

  static TextStyle get headline => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    color: AppColors.textPrimary,
  );

  static TextStyle get body => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    color: AppColors.textPrimary,
  );

  static TextStyle get callout => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.32,
    color: AppColors.textSecondary,
  );

  static TextStyle get subheadline => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    color: AppColors.textSecondary,
  );

  static TextStyle get footnote => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: AppColors.textTertiary,
  );

  static TextStyle get caption => const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textTertiary,
  );
}

/// Tema global: claro, minimalista, tecnológico.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textOnPrimary,
        secondary: AppColors.textSecondary,
        onSecondary: AppColors.surface,
        tertiary: AppColors.accent,
        onTertiary: AppColors.textOnAccent,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.surfaceVariant,
        onSurfaceVariant: AppColors.textSecondary,
        error: AppColors.error,
        onError: AppColors.textOnPrimary,
        outline: AppColors.border,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.37,
          color: AppColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: AppTextStyle.subheadline,
        hintStyle: AppTextStyle.subheadline,
        prefixIconColor: AppColors.textTertiary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.41,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 1,
      ),
      textTheme: TextTheme(
        displayLarge: AppTextStyle.largeTitle,
        displayMedium: AppTextStyle.title1,
        displaySmall: AppTextStyle.title2,
        headlineLarge: AppTextStyle.title2,
        headlineMedium: AppTextStyle.headline,
        headlineSmall: AppTextStyle.title3,
        titleLarge: AppTextStyle.title3,
        titleMedium: AppTextStyle.headline,
        titleSmall: AppTextStyle.headline,
        bodyLarge: AppTextStyle.body,
        bodyMedium: AppTextStyle.callout,
        bodySmall: AppTextStyle.subheadline,
        labelLarge: AppTextStyle.headline,
        labelMedium: AppTextStyle.subheadline,
        labelSmall: AppTextStyle.caption,
      ),
    );
  }
}
