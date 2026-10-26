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
    bg: Color(0xFFF5F5FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEFF6),
    surfaceSunken: Color(0xFFE7E7F0),
    ink: Color(0xFF0E0E18),
    inkSecondary: Color(0xFF4B4B63),
    inkMuted: Color(0xFF666680),
    inkOnPrimary: Color(0xFFFFFFFF),
    heroInk: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFDCD6FF),
    primary: Color(0xFF5B45F0),
    primaryPressed: Color(0xFF4A35D6),
    primarySoft: Color(0xFFECE9FF),
    accent: Color(0xFF0891B2),
    accentSoft: Color(0xFFDDF4F9),
    positive: Color(0xFF047857),
    positiveSoft: Color(0xFFDDF5EC),
    caution: Color(0xFFB45309),
    cautionSoft: Color(0xFFFEF0D9),
    danger: Color(0xFFE11D48),
    dangerSoft: Color(0xFFFDE4EA),
    info: Color(0xFF2563EB),
    infoSoft: Color(0xFFE3ECFE),
    outline: Color(0xFFDCDCE8),
    outlineVariant: Color(0xFFEAEAF2),
    chart: [
      Color(0xFF5B45F0),
      Color(0xFF0891B2),
      Color(0xFFE11D48),
      Color(0xFFD97706),
      Color(0xFF059669),
      Color(0xFFDB2777),
      Color(0xFF65A30D),
      Color(0xFF64748B),
    ],
    ramp: [
      Color(0xFF3B2BB0),
      Color(0xFF4A35D6),
      Color(0xFF5B45F0),
      Color(0xFF7A68F5),
      Color(0xFF9A8CF8),
      Color(0xFFBDB3FB),
      Color(0xFFDCD6FD),
    ],
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6A4CFF), Color(0xFF4338CA), Color(0xFF1E3A8A)],
      stops: [0.0, 0.55, 1.0],
    ),
    tintGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFFFF), Color(0xFFF4F3FF)],
    ),
    shadowSoft: [
      BoxShadow(color: Color(0x0A12102E), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1412102E), blurRadius: 28, offset: Offset(0, 10)),
    ],
    shadowCard: [
      BoxShadow(color: Color(0x1A3B2BB0), blurRadius: 6, offset: Offset(0, 3)),
      BoxShadow(color: Color(0x404338CA), blurRadius: 44, offset: Offset(0, 20)),
    ],
  );

  static const dark = FinanceColors(
    brightness: Brightness.dark,
    bg: Color(0xFF09090F),
    surface: Color(0xFF13131C),
    surfaceMuted: Color(0xFF191925),
    surfaceSunken: Color(0xFF20202E),
    ink: Color(0xFFF4F4FA),
    inkSecondary: Color(0xFFB4B4C8),
    inkMuted: Color(0xFF8E8EA6),
    inkOnPrimary: Color(0xFF0B0820),
    heroInk: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFD3CCFF),
    primary: Color(0xFF8B7CFF),
    primaryPressed: Color(0xFFA79BFF),
    primarySoft: Color(0xFF231F4A),
    accent: Color(0xFF4CC9F0),
    accentSoft: Color(0xFF0F2E3A),
    positive: Color(0xFF34D399),
    positiveSoft: Color(0xFF0E2E24),
    caution: Color(0xFFFBBF24),
    cautionSoft: Color(0xFF33280C),
    danger: Color(0xFFFB7185),
    dangerSoft: Color(0xFF3A1520),
    info: Color(0xFF60A5FA),
    infoSoft: Color(0xFF132544),
    outline: Color(0xFF2A2A3D),
    outlineVariant: Color(0xFF20202F),
    chart: [
      Color(0xFF8B7CFF),
      Color(0xFF4CC9F0),
      Color(0xFFFB7185),
      Color(0xFFFBBF24),
      Color(0xFF34D399),
      Color(0xFFF472B6),
      Color(0xFFA3E635),
      Color(0xFF94A3B8),
    ],
    ramp: [
      Color(0xFFC4B5FD),
      Color(0xFFA78BFA),
      Color(0xFF8B7CFF),
      Color(0xFF7C6CF0),
      Color(0xFF6D5DE0),
      Color(0xFF5B4BC8),
      Color(0xFF4A3DA8),
    ],
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6A4CFF), Color(0xFF4338CA), Color(0xFF1E3A8A)],
      stops: [0.0, 0.55, 1.0],
    ),
    tintGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF16161F), Color(0xFF12121A)],
    ),
    shadowSoft: [
      BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
    ],
    shadowCard: [
      BoxShadow(color: Color(0x554338CA), blurRadius: 48, offset: Offset(0, 18)),
      BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 10)),
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
  static const bg = Color(0xFFF5F5FA);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0E0E18);
  static const inkSecondary = Color(0xFF4B4B63);
  static const inkMuted = Color(0xFF666680);
  static const inkOnPrimary = Color(0xFFFFFFFF);
  static const primary = Color(0xFF5B45F0);
  static const primaryPressed = Color(0xFF4A35D6);
  static const primarySoft = Color(0xFFECE9FF);
  static const accent = Color(0xFF0891B2);
  static const accentSoft = Color(0xFFDDF4F9);
  static const positive = Color(0xFF047857);
  static const positiveSoft = Color(0xFFDDF5EC);
  static const caution = Color(0xFFB45309);
  static const cautionSoft = Color(0xFFFEF0D9);
  static const danger = Color(0xFFE11D48);
  static const dangerSoft = Color(0xFFFDE4EA);
  static const info = Color(0xFF2563EB);
  static const infoSoft = Color(0xFFE3ECFE);
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A4CFF), Color(0xFF4338CA), Color(0xFF1E3A8A)],
    stops: [0.0, 0.55, 1.0],
  );

  /// The first-run surface is always midnight, in either theme.
  static const onboardingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B1452), Color(0xFF0E0C2A), Color(0xFF07070D)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Deep midnight used for ink on a light button.
  static const brandDeep = Color(0xFF0B0820);

  /// Cyan highlight used sparingly on brand surfaces (progress, glows).
  static const mintGlow = Color(0xFF67E8F9);

  /// Magenta bloom used on brand surfaces.
  static const magentaGlow = Color(0xFFFF5CC8);

  static const List<Color> chart = [
    Color(0xFF5B45F0),
    Color(0xFF0891B2),
    Color(0xFFE11D48),
    Color(0xFFD97706),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
    Color(0xFF64748B),
  ];

  // ---- Spacing scale (4pt) -----------------------------------------------
  /// The app's typeface: Inter 4.1, bundled under assets/fonts.
  static const String fontFamily = 'Inter';

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
    BoxShadow(color: Color(0x0A0F2018), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F0F2018), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x140B2A1E), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x290B2A3E), blurRadius: 40, offset: Offset(0, 18)),
  ];

  // ---- Type ---------------------------------------------------------------
  // Inter (bundled). Numerals are tabular everywhere money is displayed so
  // digits do not jump as values change.
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get display => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 42,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.4,
    height: 1.02,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle get heroNumber => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    height: 1.04,
    color: inkOnPrimary,
    fontFeatures: _tabular,
  );

  static TextStyle get title => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
    color: ink,
  );

  static TextStyle get sectionTitle => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.25,
    color: ink,
  );

  static TextStyle get cardTitle => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
    color: ink,
  );

  static TextStyle get body => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: inkSecondary,
  );

  static TextStyle get bodySmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: inkMuted,
  );

  static TextStyle get label => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.2,
    color: inkMuted,
  );

  static TextStyle get money => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: ink,
    fontFeatures: _tabular,
  );

  static TextStyle moneyLarge([Color color = ink]) => TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.12,
    letterSpacing: -0.7,
    color: color,
    fontFeatures: _tabular,
  );

  // ---- Card faces ---------------------------------------------------------
  // Dark metal finishes, each tinted with the issuer's hue: cards read as
  // premium objects on the midnight canvas.
  static const _faceInk = Color(0xFFF8F8FF);
  static const _faceMuted = Color(0xB3F8F8FF);

  static CardFaceStyle _face(List<Color> colors, Color glow) => CardFaceStyle(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    ),
    glow: glow,
    ink: _faceInk,
    mutedInk: _faceMuted,
  );

  static final CardFaceStyle _hdfcFace = _face(
    const [Color(0xFF243B8F), Color(0xFF15215A), Color(0xFF0A0F2C)],
    const Color(0xFF93B4FF),
  );
  static final CardFaceStyle _iciciFace = _face(
    const [Color(0xFF7A2638), Color(0xFF4A1522), Color(0xFF220A10)],
    const Color(0xFFFFA3B8),
  );
  static final CardFaceStyle _amexFace = _face(
    const [Color(0xFF5A606C), Color(0xFF30343D), Color(0xFF15171C)],
    const Color(0xFFE5E7EB),
  );
  static final CardFaceStyle _sbiFace = _face(
    const [Color(0xFF1366B3), Color(0xFF0B3F75), Color(0xFF071E3A)],
    const Color(0xFF7DD3FC),
  );
  static final CardFaceStyle _axisFace = _face(
    const [Color(0xFF8A2350), Color(0xFF52142F), Color(0xFF250915)],
    const Color(0xFFF9A8D4),
  );
  static final CardFaceStyle _kotakFace = _face(
    const [Color(0xFF9B2C2C), Color(0xFF5C1717), Color(0xFF2A0A0A)],
    const Color(0xFFFCA5A5),
  );
  static final CardFaceStyle _defaultFace = _face(
    const [Color(0xFF4C3BC4), Color(0xFF2A2170), Color(0xFF120E30)],
    const Color(0xFFC4B5FD),
  );

  /// Tonal identity per issuer. Unknown issuers get the house violet.
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
