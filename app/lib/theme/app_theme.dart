import 'package:flutter/material.dart';

/// Design tokens — 1:1 with design/README.md (cream / clay / teal editorial).
abstract final class Tokens {
  // Core palette
  static const ink = Color(0xFF14110F);
  static const cream = Color(0xFFF6F1E8);
  static const white = Color(0xFFFFFFFF);
  static const clay = Color(0xFFC9502B);
  static const clayHover = Color(0xFFDD5C33);
  static const clayTint = Color(0xFFFBEDE7);
  static const claySoft = Color(0xFFEFD3C6);
  static const teal = Color(0xFF0F5951);
  static const tealTint = Color(0xFFE4EEEC);
  static const tealInk = Color(0xFF0B2F27); // text on mint badge
  static const mint = Color(0xFF7BC9A8);
  static const goldText = Color(0xFFA9761A);
  static const gold = Color(0xFFE9A227);
  static const goldTint = Color(0xFFFAF0D8);

  // Ink opacities (on light surfaces)
  static const hairline = Color(0x1414110F); // .08 — card borders, dividers
  static const ink72 = Color(0xB814110F);
  static const ink60 = Color(0x9914110F); // secondary text
  static const ink50 = Color(0x8014110F); // tertiary text
  static const ink45 = Color(0x7314110F); // struck-through "said" text
  static const ink35 = Color(0x5914110F); // inactive tab, placeholder
  static const track = Color(0x1214110F); // .07 — progress-bar track
  static const inkSoft = Color(0x0B14110F); // .045 — soft card bg

  // Cream opacities (on the dark call screen / ink cards)
  static const cream07 = Color(0x12F6F1E8);
  static const cream08 = Color(0x14F6F1E8);
  static const cream10 = Color(0x1AF6F1E8);
  static const cream12 = Color(0x1FF6F1E8);
  static const cream16 = Color(0x29F6F1E8);
  static const cream45 = Color(0x73F6F1E8);

  // ── Legacy aliases (older widgets; migrate to the names above) ──
  static const indigo = clay;
  static const indigoSoft = clay;
  static const violet = teal;
  static const phone = cream; // app background
  static const card = white;
  static const cardHi = track;
  static const line = hairline;
  static const muted = ink60;
  static const faint = ink50;
  static const rose = clay;
  static const amber = goldText;

  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [clay, clayHover],
  );
  static const ringGradient = LinearGradient(colors: [clay, clayHover]);
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [clay, clayHover],
  );
}

/// One family app-wide: Plus Jakarta Sans, bundled in assets/fonts so the
/// first offline launch never falls back to system fonts. Hierarchy comes
/// from weight, not from mixing families. The helper names are roles:
/// `display` = big headline/number, `mono` = small uppercase label
/// (tracked caps + tabular figures).
abstract final class Type {
  static const family = 'PlusJakartaSans';

  static TextStyle display(
    double size, {
    Color color = Tokens.ink,
    double height = 1.1,
    FontWeight weight = FontWeight.w800,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: height,
        color: color,
        fontWeight: weight,
      );

  static TextStyle mono(
    double size, {
    Color color = Tokens.ink50,
    FontWeight weight = FontWeight.w700,
    double ls = 1.2,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: ls,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildFluenixTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    fontFamily: Type.family,
    scaffoldBackgroundColor: Tokens.cream,
    colorScheme: const ColorScheme.light(
      primary: Tokens.clay,
      secondary: Tokens.teal,
      surface: Tokens.white,
      onSurface: Tokens.ink,
      error: Tokens.clay,
    ),
  );

  final text = base.textTheme.apply(
    bodyColor: Tokens.ink,
    displayColor: Tokens.ink,
  );

  return base.copyWith(
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: Tokens.hairline,
    cardTheme: const CardThemeData(
      color: Tokens.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        side: BorderSide(color: Tokens.hairline),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tokens.white,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.ink,
      contentTextStyle: const TextStyle(
        fontFamily: Type.family,
        color: Tokens.cream,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Tokens.white,
      surfaceTintColor: Colors.transparent,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: Tokens.white,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: Tokens.clay),
  );
}
