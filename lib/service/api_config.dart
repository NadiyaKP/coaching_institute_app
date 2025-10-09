import 'dart:io';

class ApiConfig {
  // Base URL configuration
  static const String _baseUrl = 'http://192.168.20.8:8000/';
  
  // API endpoints
  static const String _studentsPath = '/api/students';
  static const String _studentLoginPath = '/student_login/';
  
  // Complete API URLs
  static String get baseUrl => _baseUrl;
  static String get studentLoginUrl => '$_baseUrl$_studentsPath$_studentLoginPath';
  
  // Add more endpoints as needed
  static String get studentRegistrationUrl => '$_baseUrl$_studentsPath/register_student/';
  static String get otpVerificationUrl => '$_baseUrl$_studentsPath/verify_registration/';
  static String get loginOtpVerificationUrl => '$_baseUrl$_studentsPath/verify_login/';
  static String get emailLoginScreenUrl => '$_baseUrl$_studentsPath/student_login/';
  
  
  
  static String get profileUrl => '$_baseUrl$_studentsPath/profile/';
  
  // HTTP Client configuration for ngrok
  static HttpClient createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Allow ngrok certificates - WARNING: Only for development!
        return host.contains('ngrok') || host.contains('ngrok-free.app');
      };
    return httpClient;
  }
  
  // Common headers for API requests
  static Map<String, String> get commonHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'ngrok-skip-browser-warning': 'true',
    'User-Agent': 'Flutter App',
  };
  
  // Timeout configuration
  static const Duration requestTimeout = Duration(seconds: 30);
  
  // Environment-based configuration (optional)
  static bool get isDevelopment => _baseUrl.contains('ngrok');
  static bool get isProduction => !isDevelopment;
  
  // Method to change base URL at runtime (for testing different environments)
  static String _currentBaseUrl = _baseUrl;
  
  static void setBaseUrl(String newBaseUrl) {
    _currentBaseUrl = newBaseUrl;
  }
  
  static String get currentBaseUrl => _currentBaseUrl;
  
  // Build URL with current base URL
  static String buildUrl(String endpoint) {
    return '$_currentBaseUrl$endpoint';
  }
  
  // Predefined endpoints with current base URL
  static String get currentStudentLoginUrl => buildUrl('$_studentsPath$_studentLoginPath');
  static String get currentStudentRegistrationUrl => buildUrl('$_studentsPath/register_student/');
  static String get currentOtpVerificationUrl => buildUrl('$_studentsPath/verify_registration/');
  static String get currentProfileUrl => buildUrl('$_studentsPath/profile/');
}