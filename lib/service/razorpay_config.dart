// razorpay_config.dart
import 'package:flutter/material.dart';
import '../common/theme_color.dart';

class RazorpayConfig {
  // Test key - replace with your actual Razorpay key
  static const String keyId = 'rzp_test_RWQcyvM0Uccu0J';
  static const String keySecret = 'I723bHyw6H41Zqr1wU0JWam0'; // For server-side use only

  // Convert a Flutter Color to a hex string like "#RRGGBB"
  static String colorToHex(Color color) {
    // color.value is AARRGGBB in hex; we drop the AA (alpha) part
    final hex = color.value.toRadixString(16).padLeft(8, '0'); // ensures 8 chars
    return '#${hex.substring(2).toUpperCase()}';
  }

  // Payment options generator (use when opening Razorpay)
  static Map<String, dynamic> getOptions({
    required int amount, // in paise (e.g., 100 -> ₹1.00)
    required String contact,
    required String email,
  }) {
    return {
      'key': keyId,
      'amount': amount,
      'name': 'Signature Institute',
      'description': 'Course Subscription',
      'prefill': {
        'contact': contact,
        'email': email,
      },
      'theme': {
        'color': colorToHex(AppColors.primaryYellow), // uses your theme color
      },
    };
  }
}
