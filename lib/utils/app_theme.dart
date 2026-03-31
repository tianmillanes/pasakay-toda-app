import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Midnight Indigo Theme (Unique Hailing App)
  static const Color primaryGreen = Color(0xFF304FFE);       // Deep Indigo (Primary)
  static const Color primaryGreenLight = Color(0xFFE8EAF6);  // Light Indigo Backgrounds
  static const Color accentGreen = Color(0xFFFFD600);        // Amber Accent (Secondary)
  
  // Neutral Colors
  static const Color backgroundLight = Color(0xFFF8F9FD);    // Premium light gray background
  static const Color backgroundWhite = Color(0xFFFFFFFF);    // Pure white surface
  static const Color textPrimary = Color(0xFF1A1A1A);       // Near black for readability
  static const Color textSecondary = Color(0xFF757575);     // Medium gray for subtitles
  static const Color textHint = Color(0xFFBDBDBD);          // Light gray for hints
  static const Color borderLight = Color(0xFFEEEEEE);       // Subtle borders
  
  // Status Colors
  static const Color successGreen = Color(0xFF1AB65C);
  static const Color warningOrange = Color(0xFFFF9800);
  static const Color vibrantOrange = warningOrange;
  static const Color errorRed = Color(0xFFF44336);
  static const Color infoBlue = Color(0xFF2196F3);
  
  // Legacy color names for compatibility (mapping to new theme)
  static const Color primaryBlue = primaryGreen;            // Replaced Blue with Green
  static const Color accentBlue = primaryGreen;             // Replaced Blue with Green
  static const Color primaryColor = primaryGreen;           // Legacy
  static const Color mediumGray = textSecondary;            // Legacy
  static const Color veryLightGray = backgroundLight;       // Legacy
  static const Color darkGray = Color(0xFF1A1A1A);
  static const Color lightGray = Color(0xFFE0E0E0);
  static const Color successColor = successGreen;
  static const Color warningColor = warningOrange;
  static const Color errorColor = errorRed;
  static const Color infoColor = infoBlue;

  static ThemeData get lightTheme {
    final base = ThemeData.light();
    final manropeTextTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      primaryTextTheme: manropeTextTheme,
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: accentGreen,
        surface: backgroundWhite,
        background: backgroundLight,
        error: errorRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: Colors.white,
      ),

      // App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 24),
      ),

      // Elevated Button Theme (Highly rounded corners as per GoRide)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryGreen.withOpacity(0.3),
          shape: const StadiumBorder(), // Stadium shape like the screenshot
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFF1F1F1), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: errorRed, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textHint, fontWeight: FontWeight.normal),
        labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.normal),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.05),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryGreen,
        unselectedItemColor: Color(0xFF9E9E9E),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 20,
      ),

      // Text Theme is already set via primaryTextTheme
    );
  }

  // Visual Helpers
  static BoxShadow getSoftShadow({Color? color}) {
    return BoxShadow(
      color: (color ?? Colors.black).withOpacity(0.04),
      blurRadius: 24,
      offset: const Offset(0, 12),
    );
  }

  static LinearGradient getPrimaryGradient() {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [primaryGreen, Color(0xFF536DFE)], // Indigo Gradient
    );
  }

  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'available':
      case 'completed':
        return successGreen;
      case 'pending':
      case 'waiting':
        return warningOrange;
      default:
        return textSecondary;
    }
  }

  // Legacy Helpers
  static BorderRadius getStandardBorderRadius() => BorderRadius.circular(24);
  static EdgeInsets getStandardPadding() => const EdgeInsets.all(24);
}
