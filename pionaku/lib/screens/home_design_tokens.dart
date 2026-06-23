import 'package:flutter/material.dart';

/// Visual tokens for the Home dashboard (accent palette, panel chrome).
class HomeDesignTokens {
  HomeDesignTokens._();

  static const Color accentBlue = Color(0xFF3D7FFF);
  static const Color accentCyan = Color(0xFF00C8E8);
  static const Color accentAmber = Color(0xFFFFB830);
  static const Color accentPink = Color(0xFFFF5FA0);
  static const Color accentGreen = Color(0xFF00D68F);
  static const Color accentPurple = Color(0xFFAB6FFF);

  static const Color surfaceDark = Color(0xFF0D1B33);

  static Color borderDark(double a) => Colors.white.withOpacity(a);
  static Color borderLight(double a) => const Color(0xFF3D7FFF).withOpacity(a);

  static List<BoxShadow> panelShadowDark = [
    BoxShadow(
        color: Colors.black.withOpacity(0.45),
        blurRadius: 28,
        offset: const Offset(0, 10)),
    BoxShadow(
        color: const Color(0xFF3D7FFF).withOpacity(0.05),
        blurRadius: 20,
        spreadRadius: -4),
  ];
  static List<BoxShadow> panelShadowLight = [
    BoxShadow(
        color: const Color(0xFF3D7FFF).withOpacity(0.08),
        blurRadius: 24,
        offset: const Offset(0, 8)),
    BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 8,
        offset: const Offset(0, 2)),
  ];
}
