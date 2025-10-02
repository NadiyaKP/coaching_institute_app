// lib/service/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Keys for SharedPreferences
  static const String _isLoggedInKey = 'isLoggedIn';
  static const String _phoneNumberKey = 'phoneNumber';
  static const String _accessTokenKey = 'accessToken';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _studentTypeKey = 'studentType';
  static const String _authSuccessKey = 'authSuccess';
  static const String _countryCodeKey = 'countryCode';
  static const String _emailKey = 'email';
  static const String _nameKey = 'name';

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Get access token for API calls
  Future<String> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey) ?? '';
  }

  // Get refresh token
  Future<String> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey) ?? '';
  }

  // Get user phone number
  Future<String> getPhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneNumberKey) ?? '';
  }

  // Get student type
  Future<String> getStudentType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_studentTypeKey) ?? '';
  }

  // Get country code
  Future<String> getCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_countryCodeKey) ?? '+91';
  }

  // Get email
  Future<String> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey) ?? '';
  }

  // Get name
  Future<String> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey) ?? '';
  }

  // Get authentication success status
  Future<bool> getAuthSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_authSuccessKey) ?? false;
  }

  // Save authentication data
  Future<void> saveAuthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_phoneNumberKey, data['phone_number'] ?? '');
    await prefs.setString(_accessTokenKey, data['access'] ?? '');
    await prefs.setString(_refreshTokenKey, data['refresh'] ?? '');
    await prefs.setString(_studentTypeKey, data['student_type'] ?? '');
    
    // Store success status with proper type conversion
    if (data.containsKey('success')) {
      bool successValue;
      if (data['success'] is bool) {
        successValue = data['success'];
      } else if (data['success'] is String) {
        successValue = data['success'].toString().toLowerCase() == 'true';
      } else {
        successValue = false;
      }
      await prefs.setBool(_authSuccessKey, successValue);
    }
  }

  // Save additional user data
  Future<void> saveUserData({
    String? countryCode,
    String? email,
    String? name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (countryCode != null) {
      await prefs.setString(_countryCodeKey, countryCode);
    }
    if (email != null) {
      await prefs.setString(_emailKey, email);
    }
    if (name != null) {
      await prefs.setString(_nameKey, name);
    }
  }

  // Get all auth data as a map
  Future<Map<String, dynamic>> getAllAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'isLoggedIn': prefs.getBool(_isLoggedInKey) ?? false,
      'phoneNumber': prefs.getString(_phoneNumberKey) ?? '',
      'accessToken': prefs.getString(_accessTokenKey) ?? '',
      'refreshToken': prefs.getString(_refreshTokenKey) ?? '',
      'studentType': prefs.getString(_studentTypeKey) ?? '',
      'countryCode': prefs.getString(_countryCodeKey) ?? '+91',
      'email': prefs.getString(_emailKey) ?? '',
      'name': prefs.getString(_nameKey) ?? '',
      'authSuccess': prefs.getBool(_authSuccessKey) ?? false,
    };
  }

  // Clear all authentication data (logout)
  Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_phoneNumberKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_studentTypeKey);
    await prefs.remove(_authSuccessKey);
    // Note: We might want to keep countryCode, email, and name
    // for future registrations, but remove them on explicit logout
  }

  // Complete logout - clear everything
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_phoneNumberKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_studentTypeKey);
    await prefs.remove(_authSuccessKey);
    await prefs.remove(_countryCodeKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_nameKey);
  }

  // Check if we have valid tokens
  Future<bool> hasValidTokens() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken.isNotEmpty && refreshToken.isNotEmpty;
  }

  // Debug method to print all stored data
  Future<void> debugPrintAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await prefs.getKeys();
    
    print('=== AUTH SERVICE DEBUG DATA ===');
    for (var key in keys) {
      final value = prefs.get(key);
      print('$key: $value');
    }
    print('===============================');
  }
}