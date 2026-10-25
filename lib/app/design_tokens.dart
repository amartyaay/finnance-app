import 'package:flutter/material.dart';

/// Design tokens. One place for colour, spacing, radius, type and motion so
/// every screen feels like the same product.
///
/// Palette rationale: a warm off-white canvas (not pure white, which is harsh on
/// OLED-less LCDs and in Indian daylight), one deep emerald primary, and a
/// single clay accent. Status colours always travel with a word — colour alone
/// must never carry meaning (CVD + Indian red/green cultural baggage).
class T {
  const T._();

  // ---- Surfaces -----------------------------------------------------------
  static const bg = Color(0xFFF6F7F4);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEFF2EC);
  static const surfaceSunken = Color(0xFFE7EBE3);

  // ---- Ink ----------------------------------------------------------------
  static const ink = Color(0xFF121A15);
  static const inkSecondary = Color(0xFF4A5A50);
  static const inkMuted = Color(0xFF78877D);
  static const inkOnPrimary = Color(0xFFF7FBF8);

  // ---- Brand --------------------------------------------------------------
  static const primary = Color(0xFF0E7A5F);
  static const primaryPressed = Color(0xFF0A5E49);
  static const primarySoft = Color(0xFFE0F1E9);
  static const accent = Color(0xFFB4690E);
  static const accentSoft = Color(0xFFFBEDD9);

  // ---- Status (always paired with a label) --------------------------------
  static const positive = Color(0xFF16754A);
  static const positiveSoft = Color(0xFFE1F2E7);
  static const caution = Color(0xFF8A5A00);
  static const cautionSoft = Color(0xFFFFF1D6);
  static const danger = Color(0xFFAE2A21);
  static const dangerSoft = Color(0xFFFBE6E3);
  static const info = Color(0xFF1F5F8B);
  static const infoSoft = Color(0xFFE4EEF6);

  // ---- Data visualisation (checked against white for CVD separation) ------
  static const chart = <Color>[
    Color(0xFF0E7A5F), // emerald
    Color(0xFF2E7FB8), // blue
    Color(0xFFB4690E), // clay
    Color(0xFF6C5CE0), // violet
    Color(0xFF3C8C8C), // teal
    Color(0xFFA8447A), // plum
    Color(0xFF7A8B3A), // olive
    Color(0xFF8A6A4F), // umber
  ];

  // ---- Spacing scale (4pt) -----------------------------------------------
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s7 = 32.0;
  static const s8 = 40.0;
  static const s9 = 56.0;

  // ---- Radii --------------------------------------------------------------
  static const r1 = 8.0;
  static const r2 = 12.0;
  static const r3 = 16.0;
  static const r4 = 20.0;
  static const r5 = 28.0;

  // ---- Motion -------------------------------------------------------------
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const curve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const curveOut = Curves.easeOutCubic;

  // ---- Elevation (very soft; flat design with one raised surface) ---------
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(color: Color(0x0A0F1A12), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x14101A15), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E7A5F), Color(0xFF0B6A73)],
  );
  static const warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFF6EA), Color(0xFFFDF0E1)],
  );

  // ---- Type ---------------------------------------------------------------
  // System font (Roboto on Android, SF on iOS) keeps the build free of bundled
  // binaries while still looking native. Numerals are tabular everywhere money
  // is displayed so digits do not jump as values change.
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get display => const TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.05,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle get heroNumber => const TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    height: 1.1,
    color: inkOnPrimary,
    fontFeatures: _tabular,
  );

  static TextStyle get title => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
    color: ink,
  );

  static TextStyle get cardTitle => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: ink,
  );

  static TextStyle get body => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: inkSecondary,
  );

  static TextStyle get bodySmall => const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: inkMuted,
  );

  static TextStyle get label => const TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.2,
    color: inkMuted,
  );

  static TextStyle get money => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle moneyLarge([Color color = ink]) => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.5,
    color: color,
    fontFeatures: _tabular,
  );
}
