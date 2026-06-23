import 'package:flutter/material.dart';

/// Tema korporat PIONA Mobile - biru & putih (InJourney Airports style).
class AppTheme {
  AppTheme._();

  /// Biru korporat mockup (#3F6ED2)
  static const Color primaryBlue = Color(0xFF3F6ED2);
  static const Color primaryBlueDark = Color(0xFF3359B0);
  static const Color accentBlue = Color(0xFF5B85E8);
  static const Color backgroundWhite = Color(0xFFFAFBFC);
  /// Page fill behind floating navbar (same as Scan tabs — light mode).
  static const Color shellScaffoldLight = Color(0xFFF4F6FB);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5C5C5C);
  static const Color validGreen = Color(0xFF2E7D32);
  static const Color validGreenLight = Color(0xFFE8F5E9);
  static const Color securityGreen = Color(0xFFE0F2E9);
  static const Color invalidRed = Color(0xFFC62828);
  static const Color invalidRedLight = Color(0xFFFFEBEE);

  /// Warna untuk dark mode (nuansa biru gelap, selaras tema utama).
  static const Color darkBackground = Color(0xFF0C1222);
  static const Color darkSurface = Color(0xFF141C2E);
  static const Color darkSurfaceElevated = Color(0xFF1A2440);
  static const Color darkTextPrimary = Color(0xFFE8EDF4);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF2D3A52);

  /// Mengembalikan warna background sesuai tema (light = tema utama, dark = varian gelap).
  static Color background(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackground
        : backgroundWhite;
  }

  /// Mengembalikan warna surface (kartu, container) sesuai tema.
  static Color surface(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurface
        : surfaceWhite;
  }

  /// Surface lebih terangkat (card hover/secondary).
  static Color surfaceElevated(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurfaceElevated
        : surfaceWhite;
  }

  /// Teks utama sesuai tema.
  static Color textPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextPrimary
        : textPrimary;
  }

  /// Teks sekunder sesuai tema.
  static Color textSecondaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : textSecondary;
  }

  /// Border sesuai tema.
  static Color borderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBorder
        : const Color(0xFFE0E0E0);
  }

  static const List<Color> headerGradient = [
    Color(0xFF3F6ED2),
    Color(0xFF3359B0),
  ];

  static const double cardElevation = 4;
  static const double radiusCard = 20;
  static const double radiusButton = 14;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentBlue,
        surface: surfaceWhite,
        error: invalidRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundWhite,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentBlue,
        surface: darkSurface,
        error: invalidRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onError: Colors.white,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: const TextStyle(color: darkTextSecondary),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
