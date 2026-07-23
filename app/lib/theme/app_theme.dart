import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — 1:1 with design/mockups.html.
abstract final class Tokens {
  static const indigo = Color(0xFF6366F1);
  static const indigoSoft = Color(0xFF818CF8);
  static const violet = Color(0xFFA855F7);
  static const phone = Color(0xFF0B0E1A); // app background
  static const card = Color(0xFF131829);
  static const cardHi = Color(0xFF1A2036);
  static const line = Color(0x1794A3FF); // rgba(148,163,255,0.09)
  static const ink = Color(0xFFF4F6FF);
  static const muted = Color(0xFF8B92B4);
  static const faint = Color(0xFF5A6184);
  static const coral = Color(0xFFF8968A);
  static const coralDeep = Color(0xFFF2766B);
  static const mint = Color(0xFF34D399);
  static const rose = Color(0xFFF87171);
  static const amber = Color(0xFFFBBF24);

  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, Color(0xFF7C6AF2)],
  );
  static const ringGradient = LinearGradient(colors: [indigo, violet]);
  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coral, coralDeep],
  );
}

ThemeData buildFluenixTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Tokens.phone,
    colorScheme: const ColorScheme.dark(
      primary: Tokens.indigo,
      secondary: Tokens.violet,
      surface: Tokens.card,
      onSurface: Tokens.ink,
      error: Tokens.rose,
    ),
  );

  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: Tokens.ink,
    displayColor: Tokens.ink,
  );

  return base.copyWith(
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: Tokens.line,
    cardTheme: const CardThemeData(
      color: Tokens.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: Tokens.line),
      ),
    ),
  );
}
