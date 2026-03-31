import 'package:flutter/material.dart';

/// Responsive utilities for adaptive layouts across different screen sizes
class ResponsiveUtils {
  /// Screen size breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  /// Check if device is mobile (width < 600)
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  /// Check if device is tablet (600 <= width < 900)
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  /// Check if device is desktop (width >= 900)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
  }

  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Get responsive font size based on screen width
  /// Base size is for mobile (360px width)
  static double fontSize(BuildContext context, double baseSize) {
    final width = screenWidth(context);
    final scale = width / 360; // 360 is base mobile width
    return baseSize * scale.clamp(0.8, 1.3); // Limit scaling
  }

  /// Get responsive spacing
  static double spacing(BuildContext context, double baseSpacing) {
    final width = screenWidth(context);
    if (width < 360) {
      return baseSpacing * 0.8;
    } else if (width > 600) {
      return baseSpacing * 1.2;
    }
    return baseSpacing;
  }

  /// Get responsive padding
  static EdgeInsets padding(BuildContext context, {
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final width = screenWidth(context);
    final scale = width < 360 ? 0.8 : (width > 600 ? 1.2 : 1.0);
    
    return EdgeInsets.only(
      left: (left ?? horizontal ?? all ?? 0) * scale,
      top: (top ?? vertical ?? all ?? 0) * scale,
      right: (right ?? horizontal ?? all ?? 0) * scale,
      bottom: (bottom ?? vertical ?? all ?? 0) * scale,
    );
  }

  /// Get responsive icon size
  static double iconSize(BuildContext context, double baseSize) {
    final width = screenWidth(context);
    if (width < 360) {
      return baseSize * 0.9;
    } else if (width > 600) {
      return baseSize * 1.1;
    }
    return baseSize;
  }

  /// Get max content width for larger screens
  static double maxContentWidth(BuildContext context) {
    final width = screenWidth(context);
    if (width > desktopBreakpoint) {
      return 1200;
    } else if (width > tabletBreakpoint) {
      return 900;
    }
    return width;
  }

  /// Check if keyboard is visible
  static bool isKeyboardVisible(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom > 0;
  }

  /// Get safe area padding
  static EdgeInsets safeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }

  /// Responsive value based on screen size
  /// Returns mobile value for small screens, tablet for medium, desktop for large
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) {
      return desktop;
    } else if (isTablet(context) && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  /// Get responsive border radius
  static BorderRadius borderRadius(BuildContext context, double baseRadius) {
    final width = screenWidth(context);
    final scale = width < 360 ? 0.8 : 1.0;
    return BorderRadius.circular(baseRadius * scale);
  }

  /// Responsive sized box
  static Widget verticalSpace(BuildContext context, double height) {
    return SizedBox(height: spacing(context, height));
  }

  static Widget horizontalSpace(BuildContext context, double width) {
    return SizedBox(width: spacing(context, width));
  }

  /// Check if screen is small (width < 360px)
  static bool isSmallScreen(BuildContext context) {
    return screenWidth(context) < 360;
  }

  /// Check if screen is large (width > 600px)
  static bool isLargeScreen(BuildContext context) {
    return screenWidth(context) > 600;
  }

  /// Get responsive container constraints
  static BoxConstraints containerConstraints(BuildContext context) {
    final maxWidth = maxContentWidth(context);
    return BoxConstraints(maxWidth: maxWidth);
  }
}

/// Extension on BuildContext for easier access to responsive utilities
extension ResponsiveContext on BuildContext {
  bool get isMobile => ResponsiveUtils.isMobile(this);
  bool get isTablet => ResponsiveUtils.isTablet(this);
  bool get isDesktop => ResponsiveUtils.isDesktop(this);
  bool get isSmallScreen => ResponsiveUtils.isSmallScreen(this);
  bool get isLargeScreen => ResponsiveUtils.isLargeScreen(this);
  bool get isKeyboardVisible => ResponsiveUtils.isKeyboardVisible(this);
  
  double get screenWidth => ResponsiveUtils.screenWidth(this);
  double get screenHeight => ResponsiveUtils.screenHeight(this);
  
  double fontSize(double baseSize) => ResponsiveUtils.fontSize(this, baseSize);
  double spacing(double baseSpacing) => ResponsiveUtils.spacing(this, baseSpacing);
  double iconSize(double baseSize) => ResponsiveUtils.iconSize(this, baseSize);
  
  EdgeInsets get safeAreaPadding => ResponsiveUtils.safeAreaPadding(this);
}
