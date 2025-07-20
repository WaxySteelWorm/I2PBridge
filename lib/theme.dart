// lib/theme.dart
// This version contains the definitive fix for the CardTheme build error.

import 'package:flutter/material.dart';

const Color primaryColor = Color(0xFF006BCC);
const Color accentColor = Color(0xFF2b93f4);
const Color backgroundColor = Color(0xFF0A0A0A);
const Color surfaceColor = Color(0xFF1A1A1A);
const Color textColor = Color(0xFFE0E0E0);
const Color appBarColor = Color(0xFF101010); 

final ThemeData appTheme = ThemeData(
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

  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: textColor),
    bodyMedium: TextStyle(color: textColor),
    titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    headlineSmall: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
  ),

  appBarTheme: const AppBarTheme(
    backgroundColor: appBarColor,
    elevation: 0,
    centerTitle: true,
    iconTheme: IconThemeData(color: primaryColor),
    titleTextStyle: TextStyle(
      color: textColor,
      fontSize: 20,
      fontWeight: FontWeight.w500,
    ),
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
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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

  // --- DEFINITIVE FIX ---
  // The correct type is CardThemeData.
  cardTheme: CardThemeData(
    color: surfaceColor,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
);
