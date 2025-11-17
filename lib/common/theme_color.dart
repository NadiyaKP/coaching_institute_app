// theme_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primaryYellow = Color(0xFFFF8C00);
  static const Color primaryYellowLight = Color(0xFFFFD54F);
  static const Color primaryYellowDark = Color(0xFFE6A200);
  
  // Blue Colors
  static const Color primaryBlue = Color(0xFF09376B);
  static const Color primaryBlueDark = Color(0xFF073162);
  static const Color primaryBlueLight = Color(0xFF1565C0);
  
  // Background Colors
  static const Color backgroundGrey = Color(0xFFF5F5F5);
  static const Color backgroundLight = Color(0xFFF8F5E9);
  static const Color backgroundMedium = Color(0xFFF9F2DC);
  static const Color backgroundDark = Color(0xFFF4F0E3);
  
  // Text Colors
  static const Color textDark = Color(0xFF09376B);
  static const Color textGrey = Color(0xFF666666);
  static const Color textLightGrey = Color(0xFF888888);
  
  // Status Colors
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color errorRed = Color(0xFFF44336);
  static const Color warningOrange = Color(0xFFFF9800);
  
  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color black = Color(0xFF000000);
  
  // Gradient Colors
  static List<Color> get yellowGradient => [primaryYellow, primaryYellowLight, primaryYellowDark];
  static List<Color> get backgroundGradient => [backgroundLight, backgroundMedium, backgroundDark];
  static List<Color> get blueGradient => [primaryBlue, primaryBlueLight];
  
  // Shadow Colors
  static Color shadowYellow = primaryYellow.withOpacity(0.3);
  static Color shadowGrey = black.withOpacity(0.08);
  static Color shadowBlue = primaryBlue.withOpacity(0.1);
}

class AppGradients {
  static Gradient get primaryYellow => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: AppColors.yellowGradient,
    stops: const [0.0, 0.5, 1.0],
  );
  
  static Gradient get background => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: AppColors.backgroundGradient,
    stops: const [0.0, 0.5, 1.0],
  );
  
  static Gradient get blue => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: AppColors.blueGradient,
  );
}