// lib/theme.dart
// This version contains the definitive fix for the CardTheme build error.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color primaryColor = Color(0xFF006BCC);
const Color accentColor = Color(0xFF2b93f4);
const Color backgroundColor = Color(0xFF0A0A0A);
const Color surfaceColor = Color(0xFF1A1A1A);
const Color textColor = Color(0xFFE0E0E0);
const Color appBarColor = Color(0xFF101010); 

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  primaryColor: primaryColor,
  scaffoldBackgroundColor: backgroundColor,
  colorScheme: const ColorScheme.dark(
    primary: primaryColor,
    secondary: accentColor,
    background: backgroundColor,
    surface: surfaceColor,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onBackground: textColor,
    onSurface: textColor,
  ),
  textTheme: GoogleFonts.interTextTheme(const TextTheme()).apply(
    bodyColor: textColor,
    displayColor: textColor,
  ).copyWith(
    titleLarge: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    headlineSmall: const TextStyle(color: primaryColor, fontWeight: FontWeight.w700),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: appBarColor,
    elevation: 0,
    centerTitle: true,
    iconTheme: IconThemeData(color: primaryColor),
    titleTextStyle: TextStyle(
      color: textColor,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: surfaceColor,
    indicatorColor: Color(0x332b93f4),
    labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
    elevation: 0,
    iconTheme: WidgetStatePropertyAll(IconThemeData(color: textColor)),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: surfaceColor,
    selectedItemColor: primaryColor,
    unselectedItemColor: Colors.grey,
    type: BottomNavigationBarType.fixed,
    showUnselectedLabels: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: surfaceColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: primaryColor, width: 1.5),
    ),
    labelStyle: const TextStyle(color: Colors.grey),
    hintStyle: TextStyle(color: Colors.grey.shade700),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryColor,
    ),
  ),
  iconTheme: const IconThemeData(
    color: textColor,
  ),
  cardTheme: CardThemeData(
    color: surfaceColor,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  ),
  searchBarTheme: SearchBarThemeData(
    backgroundColor: WidgetStatePropertyAll(surfaceColor),
    hintStyle: WidgetStatePropertyAll(TextStyle(color: Colors.grey.shade600)),
    textStyle: const WidgetStatePropertyAll(TextStyle(color: textColor)),
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
);
