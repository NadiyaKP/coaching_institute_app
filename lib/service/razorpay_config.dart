class RazorpayConfig {
  // Test key - replace with your actual Razorpay key
  static const String keyId = 'rzp_test_RWQcyvM0Uccu0J';
  static const String keySecret = 'I723bHyw6H41Zqr1wU0JWam0'; // For server-side use only
  
  // Payment options
  static const Map<String, dynamic> options = {
    'key': keyId,
    'amount': 100, // Will be set dynamically
    'name': 'EduApp',
    'description': 'Course Subscription',
    'prefill': {
      'contact': '',
      'email': '',
    },
    'theme': {'color': '#FFD700'}
  };
}