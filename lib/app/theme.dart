import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final p = dark ? FinanceColors.dark : FinanceColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: p.inkOnPrimary,
    primaryContainer: p.primarySoft,
    onPrimaryContainer: dark ? const Color(0xFFB8F0DC) : const Color(0xFF064434),
    secondary: p.accent,
    onSecondary: dark ? const Color(0xFF2B1904) : Colors.white,
    secondaryContainer: p.accentSoft,
    onSecondaryContainer: dark ? const Color(0xFFF3D8AF) : const Color(0xFF5C3607),
    tertiary: p.info,
    onTertiary: dark ? const Color(0xFF08202E) : Colors.white,
    tertiaryContainer: p.infoSoft,
    onTertiaryContainer: dark ? const Color(0xFFC7E2F5) : const Color(0xFF103B57),
    error: p.danger,
    onError: dark ? const Color(0xFF2B0906) : Colors.white,
    errorContainer: p.dangerSoft,
    onErrorContainer: dark ? const Color(0xFFF9D6D2) : const Color(0xFF6E1710),
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerLowest: dark ? const Color(0xFF050D0A) : const Color(0xFFFBFCFA),
    surfaceContainerLow: p.surfaceMuted,
    surfaceContainer: dark ? const Color(0xFF152A20) : const Color(0xFFF2F5EF),
    surfaceContainerHigh: p.surfaceSunken,
    surfaceContainerHighest: dark ? const Color(0xFF22392C) : const Color(0xFFE3E8DF),
    onSurfaceVariant: p.inkSecondary,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? const Color(0xFFECF1ED) : const Color(0xFF1C2420),
    onInverseSurface: dark ? const Color(0xFF101412) : const Color(0xFFF3F7F3),
    inversePrimary: dark ? T.primary : const Color(0xFF5FD3AC),
  );

  final base = ThemeData(
    useMaterial3: true,
    // Bundled (assets/fonts), so every phone renders the same type.
    fontFamily: T.fontFamily,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          displaySmall: T.display.copyWith(color: scheme.onSurface),
          headlineSmall: T.title.copyWith(color: scheme.onSurface),
          titleMedium: T.cardTitle.copyWith(color: scheme.onSurface),
          bodyMedium: T.body.copyWith(color: scheme.onSurfaceVariant),
          bodySmall: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          labelLarge: T.label.copyWith(color: scheme.onSurfaceVariant),
        ),
    iconTheme: IconThemeData(color: p.inkSecondary, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleSpacing: T.s5,
      titleTextStyle: T.title.copyWith(color: scheme.onSurface),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(T.r3),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: T.s5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r2)),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: T.s5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r2)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r1)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: T.s4,
        vertical: T.s3,
      ),
      hintStyle: T.body.copyWith(color: p.inkMuted),
      prefixIconColor: p.inkMuted,
      suffixIconColor: p.inkMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: p.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: p.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: p.primary, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceMuted,
      selectedColor: p.ink,
      side: BorderSide(color: p.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r5)),
      labelStyle: T.bodySmall.copyWith(color: p.ink, fontSize: 12.5),
      secondaryLabelStyle: T.bodySmall.copyWith(
        color: p.bg,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 2),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: T.body.copyWith(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r2)),
      insetPadding: const EdgeInsets.all(T.s4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primarySoft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(T.r2),
      ),
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => T.label.copyWith(
          color: states.contains(WidgetState.selected) ? p.primary : p.inkMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          fontSize: 12,
          letterSpacing: 0.1,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? p.primary : p.inkMuted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r4)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(T.r5)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.surfaceSunken,
      circularTrackColor: p.surfaceSunken,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.primary
            : p.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.primarySoft
            : p.surfaceSunken,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? p.primary.withValues(alpha: 0.35)
            : p.outline,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.inkOnPrimary
              : p.inkSecondary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary
              : p.surfaceMuted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.outlineVariant)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
