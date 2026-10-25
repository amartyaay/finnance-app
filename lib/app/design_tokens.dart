import 'package:flutter/material.dart';

/// One palette per brightness. Screens read it through [T.of] so light and dark
/// are designed together instead of inverted.
@immutable
class FinanceColors {
  const FinanceColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.inkOnPrimary,
    required this.heroInk,
    required this.heroMuted,
    required this.primary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.positive,
    required this.positiveSoft,
    required this.caution,
    required this.cautionSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.outline,
    required this.outlineVariant,
    required this.chart,
    required this.ramp,
    required this.heroGradient,
    required this.tintGradient,
    required this.shadowSoft,
    required this.shadowCard,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSunken;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;

  /// Ink for filled buttons sitting on [primary].
  final Color inkOnPrimary;

  /// Ink for text sitting on [heroGradient] and card faces. Always near-white.
  final Color heroInk;

  /// Secondary ink on the hero. Solid, not translucent, so it clears 4.5:1 on
  /// every stop of the gradient.
  final Color heroMuted;

  final Color primary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color accent;
  final Color accentSoft;
  final Color positive;
  final Color positiveSoft;
  final Color caution;
  final Color cautionSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color outline;
  final Color outlineVariant;

  /// Categorical hues, used only for identity icons (which also carry a shape
  /// and a name). Quantitative charts use [ramp].
  final List<Color> chart;

  /// Ranked single-hue ramp: darkest = biggest share. Colour communicates rank,
  /// never identity, so a red-green colour-blind reader loses nothing.
  final List<Color> ramp;

  final LinearGradient heroGradient;

  /// Soft tinted canvas for the one section that should not be a white box.
  final LinearGradient tintGradient;

  final List<BoxShadow> shadowSoft;
  final List<BoxShadow> shadowCard;

  bool get isDark => brightness == Brightness.dark;

  FinanceColors copyWith() => this;

  /// A soft background for [strong] that works on either canvas.
  Color soft(Color strong, {double light = 0.10, double dark = 0.16}) =>
      strong.withValues(alpha: isDark ? dark : light);

  /// A lighter/stronger tint for hovered or selected states.
  Color strongTint(Color strong) =>
      strong.withValues(alpha: isDark ? 0.26 : 0.16);

  static const light = FinanceColors(
    brightness: Brightness.light,
    bg: Color(0xFFF3F6F1),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDF1E9),
    surfaceSunken: Color(0xFFE4EADF),
    ink: Color(0xFF101A14),
    inkSecondary: Color(0xFF4B5B51),
    inkMuted: Color(0xFF5A6A60),
    inkOnPrimary: Color(0xFFF7FBF8),
    heroInk: Color(0xFFF4FBF7),
    heroMuted: Color(0xFFCBE5DB),
    primary: Color(0xFF0C7257),
    primaryPressed: Color(0xFF085642),
    primarySoft: Color(0xFFDFF1E8),
    accent: Color(0xFFB4690E),
    accentSoft: Color(0xFFFBEDD9),
    positive: Color(0xFF16754A),
    positiveSoft: Color(0xFFE1F2E7),
    caution: Color(0xFF8A5A00),
    cautionSoft: Color(0xFFFFF1D6),
    danger: Color(0xFFAE2A21),
    dangerSoft: Color(0xFFFBE6E3),
    info: Color(0xFF1F5F8B),
    infoSoft: Color(0xFFE4EEF6),
    outline: Color(0xFFD7DFD3),
    outlineVariant: Color(0xFFE6EBE1),
    chart: [
      Color(0xFF0E7A5F),
      Color(0xFF2E7FB8),
      Color(0xFFB4690E),
      Color(0xFF6C5CE0),
      Color(0xFF3C8C8C),
      Color(0xFFA8447A),
      Color(0xFF7A8B3A),
      Color(0xFF8A6A4F),
    ],
    ramp: [
      Color(0xFF0A5B47),
      Color(0xFF127A61),
      Color(0xFF1F967D),
      Color(0xFF3FAE99),
      Color(0xFF6AC7B4),
      Color(0xFF9BDCCB),
      Color(0xFFC7E5DA),
    ],
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B6650), Color(0xFF085862), Color(0xFF064450)],
      stops: [0.0, 0.52, 1.0],
    ),
    tintGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEAF4EC), Color(0xFFE1EFE9)],
    ),
    shadowSoft: [
      BoxShadow(color: Color(0x0D0F1A12), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowCard: [
      BoxShadow(color: Color(0x1A0E2419), blurRadius: 30, offset: Offset(0, 14)),
    ],
  );

  static const dark = FinanceColors(
    brightness: Brightness.dark,
    bg: Color(0xFF07110D),
    surface: Color(0xFF0D1A14),
    surfaceMuted: Color(0xFF12241B),
    surfaceSunken: Color(0xFF183024),
    ink: Color(0xFFEDF5EF),
    inkSecondary: Color(0xFFB3C6B9),
    inkMuted: Color(0xFF9AB0A2),
    inkOnPrimary: Color(0xFF04211A),
    heroInk: Color(0xFFF2FBF6),
    heroMuted: Color(0xFFBFE3D7),
    primary: Color(0xFF5FD3AC),
    primaryPressed: Color(0xFF7EE3C0),
    primarySoft: Color(0xFF113A2C),
    accent: Color(0xFFE8AE66),
    accentSoft: Color(0xFF3A2A14),
    positive: Color(0xFF62D6A3),
    positiveSoft: Color(0xFF10392A),
    caution: Color(0xFFF0C06A),
    cautionSoft: Color(0xFF392B12),
    danger: Color(0xFFF29388),
    dangerSoft: Color(0xFF3D1B17),
    info: Color(0xFF8CC6EC),
    infoSoft: Color(0xFF132F40),
    outline: Color(0xFF2A4034),
    outlineVariant: Color(0xFF203329),
    chart: [
      Color(0xFF5FD3AC),
      Color(0xFF7FB8E8),
      Color(0xFFE0A15A),
      Color(0xFFA99BF0),
      Color(0xFF58C8C8),
      Color(0xFFE48AB8),
      Color(0xFFB8C86A),
      Color(0xFFC9A78D),
    ],
    ramp: [
      Color(0xFF8FEBD0),
      Color(0xFF6FDCBC),
      Color(0xFF55C9AA),
      Color(0xFF45B395),
      Color(0xFF389A80),
      Color(0xFF2E7F6B),
      Color(0xFF286557),
    ],
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0C5C46), Color(0xFF094C57), Color(0xFF073C4A)],
      stops: [0.0, 0.52, 1.0],
    ),
    tintGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F2119), Color(0xFF0D2A22)],
    ),
    shadowSoft: [
      BoxShadow(color: Color(0x4D000000), blurRadius: 20, offset: Offset(0, 8)),
    ],
    shadowCard: [
      BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 16)),
    ],
  );
}

/// A card face palette. Cards keep their own visual identity in both themes,
/// the way the physical card does.
@immutable
class CardFaceStyle {
  const CardFaceStyle({
    required this.gradient,
    required this.glow,
    required this.ink,
    required this.mutedInk,
  });

  final LinearGradient gradient;
  final Color glow;
  final Color ink;
  final Color mutedInk;
}

/// Design tokens. One place for colour, spacing, radius, type and motion so
/// every screen feels like the same product.
class T {
  const T._();

  /// Palette for the current brightness.
  static FinanceColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FinanceColors.dark
      : FinanceColors.light;

  // ---- Light aliases (used by the theme and by code that has no context) ---
  static const bg = Color(0xFFF3F6F1);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF101A14);
  static const inkSecondary = Color(0xFF4B5B51);
  static const inkMuted = Color(0xFF5A6A60);
  static const inkOnPrimary = Color(0xFFF7FBF8);
  static const primary = Color(0xFF0C7257);
  static const primaryPressed = Color(0xFF085642);
  static const primarySoft = Color(0xFFDFF1E8);
  static const accent = Color(0xFFB4690E);
  static const accentSoft = Color(0xFFFBEDD9);
  static const positive = Color(0xFF16754A);
  static const positiveSoft = Color(0xFFE1F2E7);
  static const caution = Color(0xFF8A5A00);
  static const cautionSoft = Color(0xFFFFF1D6);
  static const danger = Color(0xFFAE2A21);
  static const dangerSoft = Color(0xFFFBE6E3);
  static const info = Color(0xFF1F5F8B);
  static const infoSoft = Color(0xFFE4EEF6);
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B6650), Color(0xFF085862), Color(0xFF064450)],
    stops: [0.0, 0.52, 1.0],
  );

  /// The first-run surface is always deep brand green, in either theme.
  static const onboardingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A4A3C), Color(0xFF07363F), Color(0xFF04262E)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Deep green used for ink on a cream button.
  static const brandDeep = Color(0xFF06352B);

  /// Mint highlight used sparingly on brand surfaces.
  static const mintGlow = Color(0xFF6FE3C2);

  static const List<Color> chart = [
    Color(0xFF0E7A5F),
    Color(0xFF2E7FB8),
    Color(0xFFB4690E),
    Color(0xFF6C5CE0),
    Color(0xFF3C8C8C),
    Color(0xFFA8447A),
    Color(0xFF7A8B3A),
    Color(0xFF8A6A4F),
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
  static const chartDraw = Duration(milliseconds: 700);
  static const curve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const curveOut = Curves.easeOutCubic;
  static const curveInOut = Curves.easeInOutCubicEmphasized;

  // ---- Elevation (very soft; flat design with one raised surface) ---------
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(color: Color(0x0D0F1A12), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x1A0E2419), blurRadius: 30, offset: Offset(0, 14)),
  ];

  // ---- Type ---------------------------------------------------------------
  // System font (Roboto on Android, SF on iOS) keeps the build free of bundled
  // binaries while still looking native. Numerals are tabular everywhere money
  // is displayed so digits do not jump as values change.
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get display => const TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
    height: 1.02,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle get heroNumber => const TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    height: 1.04,
    color: inkOnPrimary,
    fontFeatures: _tabular,
  );

  static TextStyle get title => const TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
    color: ink,
  );

  static TextStyle get sectionTitle => const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.25,
    color: ink,
  );

  static TextStyle get cardTitle => const TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
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
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    height: 1.2,
    color: inkMuted,
  );

  static TextStyle get money => const TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle moneyLarge([Color color = ink]) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.12,
    letterSpacing: -0.7,
    color: color,
    fontFeatures: _tabular,
  );

  // ---- Card faces ---------------------------------------------------------
  static const _faceInk = Color(0xFFF7FCF9);
  static const _faceMuted = Color(0xB3F7FCF9);

  static const CardFaceStyle _hdfcFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F7459), Color(0xFF0A4C44), Color(0xFF07323A)],
    ),
    glow: Color(0xFF7FE7C8),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _iciciFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF31478A), Color(0xFF202C5C), Color(0xFF141B3A)],
    ),
    glow: Color(0xFFA9BEFF),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _amexFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF454B45), Color(0xFF252E29), Color(0xFF101815)],
    ),
    glow: Color(0xFFE7CB92),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _sbiFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1F5394), Color(0xFF143765), Color(0xFF0B1F3C)],
    ),
    glow: Color(0xFFA6CBFF),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _axisFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7A2442), Color(0xFF4A1528), Color(0xFF2A0D18)],
    ),
    glow: Color(0xFFF5AEC6),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _kotakFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8C3026), Color(0xFF571C18), Color(0xFF2D0E0C)],
    ),
    glow: Color(0xFFFFBAA8),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );
  static const CardFaceStyle _defaultFace = CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0C5F52), Color(0xFF084A4F), Color(0xFF06333D)],
    ),
    glow: Color(0xFF7FE7C8),
    ink: _faceInk,
    mutedInk: _faceMuted,
  );

  /// Tonal identity per issuer. Unknown issuers get the house emerald.
  static CardFaceStyle faceFor(String issuer) {
    final name = issuer.toLowerCase();
    if (name.contains('hdfc')) return _hdfcFace;
    if (name.contains('icici')) return _iciciFace;
    if (name.contains('amex') || name.contains('american express')) {
      return _amexFace;
    }
    if (name.contains('sbi') || name.contains('state bank')) return _sbiFace;
    if (name.contains('axis')) return _axisFace;
    if (name.contains('kotak')) return _kotakFace;
    return _defaultFace;
  }
}
