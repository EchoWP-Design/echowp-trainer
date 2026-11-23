/// EchoWP Corporate Design: Gelb #FFD400 auf Schwarz #0A0A0A, Schrift Inter.
library;

import 'package:flutter/material.dart';

const echoYellow = Color(0xFFFFD400);
const echoBlack = Color(0xFF0A0A0A);
const echoSurface = Color(0xFF161616);
const echoSurface2 = Color(0xFF222222);
const echoMuted = Color(0xFF9A9A9A);

/// Ampelfarben nur für Funktion (Score-Stufen), Marke bleibt Schwarz-Gelb.
const levelColors = {
  'push': Color(0xFF3DDC84),
  'normal': echoYellow,
  'locker': Color(0xFFFF9F1C),
  'recovery': Color(0xFFFF5A5F),
  'unbekannt': echoMuted,
};

ThemeData echoTheme() {
  const scheme = ColorScheme.dark(
    primary: echoYellow,
    onPrimary: echoBlack,
    secondary: echoYellow,
    onSecondary: echoBlack,
    surface: echoSurface,
    onSurface: Colors.white,
    error: Color(0xFFFF5A5F),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Inter', brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: echoBlack,
    appBarTheme: const AppBarTheme(
      backgroundColor: echoBlack,
      foregroundColor: echoYellow,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: echoSurface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: echoBlack,
      indicatorColor: echoYellow,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? echoBlack : echoMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? echoYellow : echoMuted)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: echoYellow,
        foregroundColor: echoBlack,
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: echoYellow,
        side: const BorderSide(color: echoYellow),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: echoSurface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: echoYellow, width: 1.5)),
      labelStyle: const TextStyle(color: echoMuted),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: echoYellow, thumbColor: echoYellow),
    dividerTheme: const DividerThemeData(color: echoSurface2),
    snackBarTheme: const SnackBarThemeData(
        backgroundColor: echoYellow, contentTextStyle: TextStyle(color: echoBlack, fontFamily: 'Inter')),
  );
}
