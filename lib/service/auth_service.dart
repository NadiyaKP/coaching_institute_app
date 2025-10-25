
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // 🔑 Keys for SharedPreferences
  static const String _isLoggedInKey = 'isLoggedIn';
  static const String _phoneNumberKey = 'phoneNumber';
  static const String _accessTokenKey = 'accessToken';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _studentTypeKey = 'studentType';
  static const String _authSuccessKey = 'authSuccess';
  static const String _countryCodeKey = 'countryCode';
  static const String _emailKey = 'email';
  static const String _nameKey = 'name';

  // 🌐 Refresh token endpoint using ApiConfig
  static String get _refreshTokenUrl => 
      ApiConfig.buildUrl('/api/admin/refresh-token/');

  // ----------------------------
  // 🔹 TOKEN MANAGEMENT SECTION
  // ----------------------------

  // ✅ Get access token for API calls
  Future<String> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey) ?? '';
  }

  // ✅ Get refresh token
  Future<String> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey) ?? '';
  }

  // ✅ Save new tokens (after refresh or login)
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  // 🚀 Refresh the access token when expired
  Future<String?> refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);

    if (refreshToken == null || refreshToken.isEmpty) {
      print("⚠️ No refresh token available");
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(_refreshTokenUrl),
        headers: ApiConfig.commonHeaders, // Use common headers from ApiConfig
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(ApiConfig.requestTimeout); // Use timeout from ApiConfig

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'] ?? data['access'] ?? '';
        if (newAccessToken.isNotEmpty) {
          await prefs.setString(_accessTokenKey, newAccessToken);
          print("✅ Access token refreshed successfully");
          return newAccessToken;
        } else {
          print("⚠️ Refresh token response did not contain access token");
          return null;
        }
      } else {
        print("❌ Refresh failed (status: ${response.statusCode})");
        await logout(); // clear tokens
        return null;
      }
    } catch (e) {
      print("❌ Error refreshing access token: $e");
      return null;
    }
  }

  // ✅ Check if we have valid tokens
  Future<bool> hasValidTokens() async {
    final accessToken = await getAccessToken();
    final refreshToken = await getRefreshToken();
    return accessToken.isNotEmpty && refreshToken.isNotEmpty;
  }

  // ----------------------------
  // 🔹 AUTHENTICATION DATA SECTION
  // ----------------------------

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  // Save authentication data after login
  Future<void> saveAuthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_phoneNumberKey, data['phone_number'] ?? '');
    await prefs.setString(_accessTokenKey, data['access'] ?? '');
    await prefs.setString(_refreshTokenKey, data['refresh'] ?? '');
    await prefs.setString(_studentTypeKey, data['student_type'] ?? '');

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

  // ----------------------------
  // 🔹 LOGOUT SECTION
  // ----------------------------

  // Partial logout - keeps some details
  Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_phoneNumberKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_studentTypeKey);
    await prefs.remove(_authSuccessKey);
  }

  // Complete logout - clears everything
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

  // ----------------------------
  // 🔹 DEBUG SECTION
  // ----------------------------
  Future<void> debugPrintAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    print('=== AUTH SERVICE DEBUG DATA ===');
    for (var key in keys) {
      final value = prefs.get(key);
      print('$key: $value');
    }
    print('===============================');
  }
}