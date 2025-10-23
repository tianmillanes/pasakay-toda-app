import 'package:flutter/material.dart';

class AppTheme {
  // Minimal theme - Grayscale with green accent
  static const Color primaryColor = Color(0xFF2D2D2D);      // Dark gray/black
  static const Color accentGreen = Color(0xFF4CAF50);       // Green accent
  static const Color backgroundGray = Color(0xFFF5F5F5);    // Light gray background
  
  // Grayscale palette
  static const Color darkGray = Color(0xFF2D2D2D);          // Primary dark
  static const Color mediumGray = Color(0xFF757575);        // Secondary text
  static const Color lightGray = Color(0xFFE0E0E0);         // Borders/dividers
  static const Color veryLightGray = Color(0xFFF5F5F5);     // Background
  
  // Accent colors (minimal use)
  static const Color accentBlue = Color(0xFF0D7CFF);        // Sharp vibrant blue accent
  static const Color accentBlueDark = Color(0xFF0052CC);    // Darker blue for gradient
  static const Color successGreen = Color(0xFF4CAF50);      // Success/active
  static const Color warningOrange = Color(0xFFFF9800);     // Warning
  static const Color errorRed = Color(0xFFF44336);          // Error
  
  // Legacy color names for compatibility
  static const Color primaryBlue = Color(0xFF2D2D2D);       // Now dark gray
  static const Color primaryBlueDark = Color(0xFF1A1A1A);   // Darker gray
  static const Color vibrantGreen = Color(0xFF4CAF50);      // Green accent
  static const Color vibrantOrange = Color(0xFFFF9800);     // Orange
  static const Color vibrantPurple = Color(0xFF9C27B0);     // Purple
  static const Color vibrantRed = Color(0xFFF44336);        // Red
  
  // Gradient colors (now grayscale)
  static const Color gradientStart = Color(0xFF2D2D2D);
  static const Color gradientEnd = Color(0xFF424242);
  
  // Surface colors
  static const Color surfaceLight = Color(0xFFF5F5F5);
  static const Color surfaceDark = Color(0xFF2D2D2D);
  static const Color cardBackground = Color(0xFFFFFFFF);
  
  // Text colors - minimal theme
  static const Color textPrimary = Color(0xFF2D2D2D);       // Dark gray
  static const Color textSecondary = Color(0xFF757575);     // Medium gray
  static const Color textHint = Color(0xFFBDBDBD);          // Light gray

  // Status colors - minimal theme
  static const Color successColor = Color(0xFF4CAF50);      // Green
  static const Color warningColor = Color(0xFFFF9800);      // Orange
  static const Color errorColor = Color(0xFFF44336);        // Red
  static const Color infoColor = Color(0xFF757575);         // Gray

  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      // Color Scheme
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: vibrantGreen,
        surface: cardBackground,
        background: surfaceLight,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: Colors.white,
      ),

      // App Bar Theme - Minimal white with dark text
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: darkGray,
        elevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkGray,
        ),
        iconTheme: IconThemeData(color: darkGray),
      ),

      // Elevated Button Theme - Dark gray
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkGray,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Outlined Button Theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          side: const BorderSide(color: primaryBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Button Theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textHint),
      ),

      // Card Theme - Minimal flat cards
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        color: cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: lightGray, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // Floating Action Button Theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 6,
      ),

      // Bottom Navigation Bar Theme - Minimal with light blue accent
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: accentBlue,
        unselectedItemColor: darkGray,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      // SnackBar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      // Dialog Theme
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        elevation: 8,
        backgroundColor: Colors.white,
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: Colors.grey[300],
        thickness: 1,
        space: 16,
      ),

      // Text Theme with better accessibility
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: textHint,
        ),
      ),
    );
  }

  // Helper methods for common color schemes - ALL ROLES SAME COLOR
  static Color getRoleColor(String role) {
    // ALL ROLES USE THE SAME PRIMARY BLUE - NO DIFFERENT COLORS
    return primaryBlue;
  }

  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'available':
      case 'completed':
        return successColor;
      case 'pending':
      case 'waiting':
        return warningColor;
      case 'cancelled':
      case 'error':
      case 'offline':
        return errorColor;
      case 'in_progress':
      case 'on_trip':
        return infoColor;
      default:
        return textSecondary;
    }
  }

  // JoyRide-style helpers
  static BoxShadow getSoftShadow({Color? color}) {
    return BoxShadow(
      color: (color ?? Colors.black).withOpacity(0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    );
  }

  static BorderRadius getStandardBorderRadius() {
    return BorderRadius.circular(12);
  }

  static EdgeInsets getStandardPadding() {
    return const EdgeInsets.all(16);
  }

  // Minimal gradient (grayscale)
  static LinearGradient getPrimaryGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [gradientStart, gradientEnd],
    );
  }

  // Service type colors (like JoyRide's colorful icons)
  static Color getServiceColor(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'tricycle':
      case 'motorcycle':
        return vibrantBlue;
      case 'car':
      case 'sedan':
        return vibrantGreen;
      case 'suv':
      case 'van':
        return vibrantOrange;
      case 'premium':
      case 'luxury':
        return vibrantPurple;
      default:
        return primaryBlue;
    }
  }

  // Add vibrant blue for service colors
  static const Color vibrantBlue = Color(0xFF007AFF);
}
