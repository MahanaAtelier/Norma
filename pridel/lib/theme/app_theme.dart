import 'package:flutter/material.dart';

class AppTheme {
  static const ink = Color(0xFF1E1E1C);
  static const muted = Color(0xFF74716B);
  static const champagne = Color(0xFFB89A63);
  static const canvas = Color(0xFFF8F7F4);
  static const line = Color(0xFFE8E4DD);
  static const soft = Color(0xFFF1EDE5);
  static const success = Color(0xFF3F6E50);
  static const warning = Color(0xFF9A672F);
  static const danger = Color(0xFF8B3D3D);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: champagne,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme.copyWith(
        primary: ink,
        secondary: champagne,
        surface: Colors.white,
        outline: line,
        error: danger,
      ),
      scaffoldBackgroundColor: canvas,
      fontFamily: 'sans-serif',
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: champagne, width: 1.4),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: soft,
        labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w600)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: soft,
        selectedIconTheme: IconThemeData(color: ink),
        selectedLabelTextStyle:
            TextStyle(color: ink, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: soft,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          minimumSize: const Size(0, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: ink)),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.8,
            height: 1.05),
        headlineMedium: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.5),
        headlineSmall: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.3),
        titleLarge:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
        titleMedium:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
        bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.35),
        labelLarge:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    );
  }
}
