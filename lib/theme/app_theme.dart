import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF09090B),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF18181B),
      onPrimaryContainer: Colors.white,
      secondary: Color(0xFF27272A),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF4F4F5),
      onSecondaryContainer: Color(0xFF09090B),
      tertiary: Color(0xFF52525B),
      onTertiary: Colors.white,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF09090B),
      onSurfaceVariant: Color(0xFF71717A),
      outline: Color(0xFFE4E4E7),
      outlineVariant: Color(0xFFE5E5EA),
      surfaceContainerLow: Color(0xFFFAFAFA),
      surfaceContainer: Color(0xFFF4F4F5),
      surfaceContainerHigh: Color(0xFFE4E4E7),
      surfaceContainerHighest: Color(0xFFD4D4D8),
    );

    const textTheme = TextTheme(
      headlineLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleSmall: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFF18181B)),
      bodyMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF27272A)),
      bodySmall: TextStyle(fontFamily: 'Inter', color: Color(0xFF71717A)),
      labelLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFF09090B), fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF71717A), fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontFamily: 'Inter', color: Color(0xFF71717A), fontWeight: FontWeight.w500),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      textTheme: textTheme,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF09090B),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFF09090B),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Color(0xFF09090B), size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF09090B),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF09090B),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF09090B),
          side: const BorderSide(color: Color(0xFFE4E4E7), width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF09090B),
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5E5EA), width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFF09090B),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFF3F3F46),
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E5EA),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
