import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.blue,
    required this.tint,
    required this.line,
    required this.warm,
    required this.warning,
  });
  final Color canvas, surface, ink, muted, blue, tint, line, warm, warning;
  static const light = AppColors(
    canvas: Color(0xFFF7F8FC),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF17243B),
    muted: Color(0xFF647188),
    blue: Color(0xFF1765E8),
    tint: Color(0xFFEAF1FF),
    line: Color(0xFFE7EBF2),
    warm: Color(0xFFFFF3E5),
    warning: Color(0xFF925012),
  );
  static const dark = AppColors(
    canvas: Color(0xFF101723),
    surface: Color(0xFF1A2434),
    ink: Color(0xFFF3F6FC),
    muted: Color(0xFFA8B5CC),
    blue: Color(0xFF79AAFF),
    tint: Color(0xFF1B3359),
    line: Color(0xFF2D3A4E),
    warm: Color(0xFF3B2B1C),
    warning: Color(0xFFFFBF77),
  );
  @override
  AppColors copyWith() => this;
  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      canvas: blend(canvas, other.canvas),
      surface: blend(surface, other.surface),
      ink: blend(ink, other.ink),
      muted: blend(muted, other.muted),
      blue: blend(blue, other.blue),
      tint: blend(tint, other.tint),
      line: blend(line, other.line),
      warm: blend(warm, other.warm),
      warning: blend(warning, other.warning),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData appTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final fontFamily = defaultTargetPlatform == TargetPlatform.iOS
      ? '.SF UI Text'
      : 'Inter';
  final base = ThemeData(
    fontFamily: fontFamily,
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.blue,
      brightness: brightness,
      surface: c.surface,
      primary: c.blue,
      onSurface: c.ink,
    ),
    scaffoldBackgroundColor: c.canvas,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: c.blue,
    ),
    extensions: [c],
  );
  final typography = base.textTheme
      .apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: fontFamily)
      .copyWith(
        displaySmall: TextStyle(
          fontSize: 36,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
          color: c.ink,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.1,
          color: c.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          color: c.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
          color: c.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -.2,
          color: c.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: c.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
      );
  final resolvedTypography = typography.apply(fontFamily: fontFamily);
  return base.copyWith(
    textTheme: resolvedTypography,
    dividerColor: c.line,
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: resolvedTypography.titleMedium,
    ),
    iconTheme: IconThemeData(color: c.ink, size: 24),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.blue,
        minimumSize: const Size(44, 44),
        textStyle: resolvedTypography.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      labelStyle: TextStyle(color: c.muted),
      hintStyle: TextStyle(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.blue, width: 1.5),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.canvas,
      dragHandleColor: c.muted.withValues(alpha: .35),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.surface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.surface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.blue : c.line,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
