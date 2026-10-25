import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? const Color(0xFF5FD3AC) : T.primary,
    onPrimary: dark ? const Color(0xFF00281C) : T.inkOnPrimary,
    primaryContainer: dark ? const Color(0xFF0B3B2E) : T.primarySoft,
    onPrimaryContainer: dark ? const Color(0xFFB8F0DC) : const Color(0xFF064434),
    secondary: T.accent,
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF3B2A12) : T.accentSoft,
    onSecondaryContainer: dark ? const Color(0xFFF3D8AF) : const Color(0xFF5C3607),
    tertiary: T.info,
    onTertiary: Colors.white,
    tertiaryContainer: dark ? const Color(0xFF17303F) : T.infoSoft,
    onTertiaryContainer: dark ? const Color(0xFFC7E2F5) : const Color(0xFF103B57),
    error: T.danger,
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF43120F) : T.dangerSoft,
    onErrorContainer: dark ? const Color(0xFFF9D6D2) : const Color(0xFF6E1710),
    surface: dark ? const Color(0xFF101412) : T.surface,
    onSurface: dark ? const Color(0xFFECF1ED) : T.ink,
    surfaceContainerLowest: dark ? const Color(0xFF0B0E0C) : const Color(0xFFFBFCFA),
    surfaceContainerLow: dark ? const Color(0xFF161B18) : T.surfaceMuted,
    surfaceContainer: dark ? const Color(0xFF1B211D) : const Color(0xFFF2F5EF),
    surfaceContainerHigh: dark ? const Color(0xFF232A25) : T.surfaceSunken,
    surfaceContainerHighest: dark ? const Color(0xFF2B332D) : const Color(0xFFE3E8DF),
    onSurfaceVariant: dark ? const Color(0xFFBFC9C2) : T.inkSecondary,
    outline: dark ? const Color(0xFF3B443E) : const Color(0xFFCBD4CB),
    outlineVariant: dark ? const Color(0xFF2A312C) : const Color(0xFFE1E7DD),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? const Color(0xFFECF1ED) : const Color(0xFF1C2420),
    onInverseSurface: dark ? const Color(0xFF101412) : const Color(0xFFF3F7F3),
    inversePrimary: dark ? T.primary : const Color(0xFF5FD3AC),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B0E0C) : T.bg,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          displaySmall: T.display.copyWith(color: scheme.onSurface),
          headlineSmall: T.title.copyWith(color: scheme.onSurface),
          titleMedium: T.cardTitle.copyWith(color: scheme.onSurface),
          bodyMedium: T.body.copyWith(color: scheme.onSurfaceVariant),
          bodySmall: T.bodySmall.copyWith(color: scheme.onSurfaceVariant),
          labelLarge: T.label.copyWith(color: scheme.onSurfaceVariant),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
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
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
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
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r1)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: T.s4,
        vertical: T.s3,
      ),
      hintStyle: T.body.copyWith(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.r2),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r5)),
      labelStyle: T.bodySmall.copyWith(color: scheme.onSurface, fontSize: 12.5),
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
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => T.label.copyWith(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          fontSize: 11,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(T.r4)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(T.r5)),
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
