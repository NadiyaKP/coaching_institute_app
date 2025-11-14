import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

// ============= RESPONSIVE UTILITY CLASS =============
class ResponsiveUtils {
  static bool isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double getResponsiveWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);

    if (isTabletDevice || isLandscapeMode) {
      return width * 0.5;
    }
    return width * 0.9;
  }

  static double getMaxContainerWidth(BuildContext context) {
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);

    if (isTabletDevice) {
      return 500.0;
    } else if (isLandscapeMode) {
      return 450.0;
    }
    return double.infinity;
  }

  static double getFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);
    
    if (isLandscapeMode) {
      return baseSize * 0.85;
    } else if (isTabletDevice) {
      return baseSize * 1.2;
    }
    return (baseSize / 375) * width;
  }

  static double getHeaderHeight(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final isLandscapeMode = isLandscape(context);
    
    if (isLandscapeMode) {
      return height * 0.85;
    }
    return height * 0.35;
  }

  static double getIconSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);
    
    if (!isLandscapeMode) {
      if (isTabletDevice) {
        return screenWidth * (baseSize / 375) * 1.2;
      } else {
        return screenWidth * (baseSize / 375);
      }
    }
    
    if (isTabletDevice) {
      return screenHeight * (baseSize / 667) * 0.8;
    } else {
      return screenHeight * (baseSize / 667) * 0.7;
    }
  }

  static EdgeInsets getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    
    if (isTabletDevice) {
      return EdgeInsets.symmetric(horizontal: width * 0.15);
    }
    return const EdgeInsets.symmetric(horizontal: 20);
  }

  static double getVerticalSpacing(BuildContext context, double baseSpacing) {
    final isLandscapeMode = isLandscape(context);
    
    if (isLandscapeMode) {
      return baseSpacing * 0.6;
    }
    return baseSpacing;
  }

  static double getOtpBoxSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);
    
    if (isTabletDevice && !isLandscapeMode) {
      return 60.0;
    } else if (isLandscapeMode) {
      final availableWidth = width * 0.4;
      final boxSize = (availableWidth / 6) - 8;
      return boxSize.clamp(45.0, 55.0);
    }
    return width * 0.11;
  }

  static double getOtpSpacing(BuildContext context) {
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    if (isLandscapeMode) {
      return 6.0;
    } else if (isTabletDevice) {
      return 12.0;
    }
    return 10.0;
  }
}

// ==================== PROVIDER CLASS ====================
class OtpVerificationProvider extends ChangeNotifier {
  // Controllers and Focus Nodes
  final List<TextEditingController> otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());

  // State variables
  bool _isLoading = false;
  Timer? _timer;
  int _countdown = 59;
  bool _canResend = false;
  bool _isInitialized = false;

  // Route arguments data
  String _phoneNumber = '';
  String _countryCode = '+91';
  String _mobileNumber = '';
  String _email = '';
  String _name = '';
  String _password = '';
  bool _isLoginFlow = false;

  // Getters
  bool get isLoading => _isLoading;
  int get countdown => _countdown;
  bool get canResend => _canResend;
  bool get isInitialized => _isInitialized;
  String get phoneNumber => _phoneNumber;
  String get countryCode => _countryCode;
  String get mobileNumber => _mobileNumber;
  String get email => _email;
  String get name => _name;
  String get password => _password;
  bool get isLoginFlow => _isLoginFlow;

  // Initialize with route arguments
  void initialize(Map<String, dynamic>? args) {
    if (_isInitialized) return;
    
    if (args != null) {
      _phoneNumber = args['phone_number'] ?? '';
      _countryCode = args['country_code'] ?? '+91';
      _mobileNumber = args['mobile_number'] ?? '';
      _email = args['email'] ?? '';
      _name = args['name'] ?? '';
      _password = args['password'] ?? '';
      _isLoginFlow = args['is_login'] ?? false;
      
      _debugLog('OTP VERIFICATION - ROUTE ARGUMENTS RECEIVED', {
        'phone_number': _phoneNumber,
        'country_code': _countryCode,
        'mobile_number': _mobileNumber,
        'email': _email,
        'name': _name,
        'password': _password.isNotEmpty ? '***PASSWORD_RECEIVED***' : 'NOT_FOUND',
        'is_login': _isLoginFlow,
        'formatted_phone': getFormattedPhoneNumber(),
      });
    } else {
      debugPrint('WARNING: No route arguments received for OTP verification');
    }
    
    _isInitialized = true;
    startTimer();
  }

  // Start countdown timer
  void startTimer() {
    _countdown = 59;
    _canResend = false;
    notifyListeners();
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        _countdown--;
        notifyListeners();
      } else {
        _canResend = true;
        notifyListeners();
        timer.cancel();
      }
    });
  }

  // Handle OTP digit changes
  void onOtpDigitChanged(String value, int index) {
    debugPrint('OTP Digit Changed - Index: $index, Value: "$value"');
    
    if (value.isNotEmpty && index < 5) {
      focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }
  }

  // Get complete OTP
  String getOtp() {
    return otpControllers.map((controller) => controller.text).join();
  }

  // Clear OTP fields
  void clearOtpFields() {
    debugPrint('🧹 Clearing OTP fields');
    for (var controller in otpControllers) {
      controller.clear();
    }
    if (focusNodes.isNotEmpty) {
      focusNodes[0].requestFocus();
      debugPrint('🎯 Focus set to first OTP field');
    }
  }

  // Helper method to get formatted phone number
  String getFormattedPhoneNumber() {
    if (_phoneNumber.isEmpty) return '';
    
    if (_phoneNumber.startsWith(_countryCode)) {
      return _phoneNumber;
    }
    
    return '$_countryCode$_phoneNumber';
  }

  // Verify OTP
  Future<Map<String, dynamic>> verifyOtp() async {
    String otp = getOtp();
    debugPrint('\n🔍 OTP VERIFICATION INITIATED');
    debugPrint('Current OTP: "$otp"');
    debugPrint('OTP Length: ${otp.length}');
    debugPrint('Email: $_email');
    
    if (otp.length != 6) {
      debugPrint('❌ OTP validation failed - incomplete OTP');
      return {
        'success': false,
        'message': 'Please enter complete OTP',
      };
    }

    _isLoading = true;
    notifyListeners();

    final client = _createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      String requestUrl = '${ApiConfig.baseUrl}/api/students/verify_registration/';
      
      final requestData = {
        'email': _email,
        'otp': otp,
      };

      final requestHeaders = ApiConfig.commonHeaders;

      _debugLog('🚀 OTP VERIFICATION API REQUEST', {
        'method': 'POST',
        'url': requestUrl,
        'headers': requestHeaders,
        'body': requestData,
        'base_url': ApiConfig.currentBaseUrl,
        'is_development': ApiConfig.isDevelopment,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final response = await client.post(
        Uri.parse(requestUrl),
        headers: requestHeaders,
        body: json.encode(requestData),
      ).timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw TimeoutException('Request timeout', ApiConfig.requestTimeout);
        },
      );

      stopwatch.stop();

      _debugLog('📥 OTP VERIFICATION API RESPONSE', {
        'status_code': response.statusCode,
        'status_message': response.reasonPhrase,
        'headers': response.headers,
        'body_raw': response.body,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      });

      dynamic responseData;
      try {
        responseData = json.decode(response.body);
        _debugLog('📋 PARSED RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      _isLoading = false;
      notifyListeners();

      if (response.statusCode == 200 || response.statusCode == 201) {
        bool isSuccess = _parseSuccessFlag(responseData['success']);
        
        debugPrint('✅ OTP verification success status: $isSuccess (HTTP ${response.statusCode})');

        if (isSuccess) {
          // Save authentication data
          await _saveAuthData(responseData);

          final navigationArgs = {
            'phone_number': responseData['phone_number'] ?? _phoneNumber,
            'country_code': _countryCode,
            'mobile_number': _mobileNumber,
            'email': responseData['email'] ?? _email,
            'name': _name,
            'verified': true,
            'is_login': _isLoginFlow,
            'access_token': responseData['access'] ?? '',
            'refresh_token': responseData['refresh'] ?? '',
            'student_type': responseData['student_type'] ?? '',
          };

          debugPrint('🎉 OTP verification successful');
          
          return {
            'success': true,
            'message': responseData['message'] ?? 'OTP verified successfully',
            'navigation_args': navigationArgs,
          };
        } else {
          final errorMessage = responseData['message'] ?? 'Invalid OTP. Please try again.';
          debugPrint('❌ OTP verification failed: $errorMessage');
          clearOtpFields();
          
          return {
            'success': false,
            'message': errorMessage,
          };
        }
      } else if (response.statusCode == 400) {
        final errorMessage = responseData['message'] ?? 'Invalid OTP. Please try again.';
        debugPrint('❌ Bad Request (400): $errorMessage');
        clearOtpFields();
        
        return {
          'success': false,
          'message': errorMessage,
        };
      } else if (response.statusCode == 401) {
        final errorMessage = responseData['message'] ?? 'Account not found or blocked.';
        debugPrint('❌ Unauthorized (401): $errorMessage');
        
        return {
          'success': false,
          'message': errorMessage,
          'navigate_back': true,
        };
      } else {
        debugPrint('❌ HTTP Error ${response.statusCode}: ${response.reasonPhrase}');
        
        return {
          'success': false,
          'message': 'Network error. Please try again.',
        };
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('⏰ REQUEST TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      return {
        'success': false,
        'message': 'Request timeout. Please check your connection and try again.',
      };
    } on SocketException catch (e) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('🌐 NETWORK ERROR', {
        'error': e.toString(),
        'message': e.message,
        'os_error': e.osError?.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e, stackTrace) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('💥 UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      return {
        'success': false,
        'message': 'Verification failed: ${e.toString()}',
      };
    } finally {
      client.close();
      debugPrint('🔒 HTTP client closed');
    }
  }

  // Save authentication data to SharedPreferences
  Future<void> _saveAuthData(Map<String, dynamic> responseData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('accessToken', responseData['access'] ?? '');
      await prefs.setString('studentType', responseData['student_type'] ?? '');
      await prefs.setString('phoneNumber', responseData['phone_number'] ?? _phoneNumber);
      await prefs.setBool('profileCompleted', responseData['profile_completed'] ?? false);
      await prefs.setString('username', responseData['email'] ?? _email);
      
      debugPrint('✅ Authentication data saved to SharedPreferences');
      _debugLog('SHARED_PREFERENCES_DATA', {
        'phoneNumber': responseData['phone_number'] ?? _phoneNumber,
        'email': responseData['email'] ?? _email,
        'accessToken': responseData['access'] != null ? '***TOKEN_SAVED***' : 'NOT_FOUND',
        'studentType': responseData['student_type'] ?? '',
      });
    } catch (e) {
      debugPrint('❌ Error saving auth data to SharedPreferences: $e');
    }
  }

  // Resend OTP
  Future<Map<String, dynamic>> resendOtp() async {
    debugPrint('\n🔄 RESEND OTP INITIATED');
    debugPrint('Email: $_email');
    
    _isLoading = true;
    notifyListeners();

    final client = _createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      String requestUrl;
      Map<String, dynamic> requestData;
      
      if (_isLoginFlow) {
        requestUrl = '${ApiConfig.baseUrl}/api/students/resend_login_otp/';
        requestData = {
          'email': _email,
        };
      } else {
        requestUrl = '${ApiConfig.baseUrl}/api/students/register_student/';
        requestData = {
          'phone_number': getFormattedPhoneNumber(),
          'email': _email,
          'name': _name,
          'password': _password,
        };
      }

      final requestHeaders = ApiConfig.commonHeaders;

      _debugLog('🚀 RESEND OTP API REQUEST', {
        'method': 'POST',
        'url': requestUrl,
        'endpoint_type': _isLoginFlow ? 'LOGIN' : 'REGISTRATION',
        'headers': requestHeaders,
        'body': requestData,
        'base_url': ApiConfig.currentBaseUrl,
        'is_development': ApiConfig.isDevelopment,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final response = await client.post(
        Uri.parse(requestUrl),
        headers: requestHeaders,
        body: json.encode(requestData),
      ).timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw TimeoutException('Request timeout', ApiConfig.requestTimeout);
        },
      );

      stopwatch.stop();

      _debugLog('📥 RESEND OTP API RESPONSE', {
        'status_code': response.statusCode,
        'status_message': response.reasonPhrase,
        'headers': response.headers,
        'body_raw': response.body,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _isLoading = false;
      notifyListeners();

      dynamic responseData;
      try {
        responseData = json.decode(response.body);
        _debugLog('📋 PARSED RESEND RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse resend response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        bool isSuccess = _parseSuccessFlag(responseData['success']);

        if (isSuccess) {
          final successMessage = responseData['message'] ?? 'OTP resent successfully to $_email';
          debugPrint('✅ OTP resend successful: $successMessage (HTTP ${response.statusCode})');
          
          clearOtpFields();
          startTimer();
          
          return {
            'success': true,
            'message': successMessage,
          };
        } else {
          final errorMessage = responseData['message'] ?? 'Failed to resend OTP';
          debugPrint('❌ Resend OTP failed: $errorMessage');
          
          return {
            'success': false,
            'message': errorMessage,
          };
        }
      } else {
        debugPrint('❌ Resend OTP failed with status: ${response.statusCode}');
        
        return {
          'success': false,
          'message': 'Failed to resend OTP. Please try again.',
        };
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('⏰ RESEND TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      return {
        'success': false,
        'message': 'Request timeout. Please try again.',
      };
    } on SocketException catch (e) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('🌐 RESEND NETWORK ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e, stackTrace) {
      stopwatch.stop();
      _isLoading = false;
      notifyListeners();
      
      _debugLog('💥 RESEND UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      return {
        'success': false,
        'message': 'Failed to resend OTP. Please try again.',
      };
    } finally {
      client.close();
      debugPrint('🔒 Resend HTTP client closed');
    }
  }

  // Helper methods
  http.Client _createHttpClient() {
    return IOClient(ApiConfig.createHttpClient());
  }

  bool _parseSuccessFlag(dynamic success) {
    if (success is bool) {
      return success;
    } else if (success is String) {
      return success.toLowerCase() == 'true';
    }
    return false;
  }

  void _debugLog(String title, dynamic content) {
    debugPrint('\n==================== $title ====================');
    if (content is Map || content is List) {
      debugPrint(const JsonEncoder.withIndent('  ').convert(content));
    } else {
      debugPrint(content.toString());
    }
    debugPrint('=' * (42 + title.length));
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}

// ==================== SCREEN WIDGET ====================
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _handleVerifyOtp(BuildContext context) async {
    final provider = context.read<OtpVerificationProvider>();
    final result = await provider.verifyOtp();

    if (!mounted) return;

    if (result['success'] == true) {
      _showSnackBar(result['message'], AppColors.successGreen);

      final navigationArgs = result['navigation_args'];

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          debugPrint('🧭 Navigating to: /profile_completion_page');
          Navigator.pushReplacementNamed(
            context,
            '/profile_completion_page',
            arguments: navigationArgs,
          );
        }
      });
    } else {
      _showSnackBar(result['message'], AppColors.errorRed);

      if (result['navigate_back'] == true) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleResendOtp(BuildContext context) async {
    final provider = context.read<OtpVerificationProvider>();
    final result = await provider.resendOtp();

    if (!mounted) return;

    if (result['success'] == true) {
      _showSnackBar(result['message'], AppColors.successGreen);
    } else {
      _showSnackBar(result['message'], AppColors.errorRed);
    }
  }

  Widget _buildHeader(BuildContext context) {
    final provider = context.watch<OtpVerificationProvider>();
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final headerHeight = ResponsiveUtils.getHeaderHeight(context);
    
    final iconSize = ResponsiveUtils.getIconSize(context, 45);
    final titleFontSize = ResponsiveUtils.getFontSize(context, 24);
    final subtitleFontSize = ResponsiveUtils.getFontSize(context, 14);

    return Container(
      width: double.infinity,
      height: headerHeight,
      decoration: BoxDecoration(
        gradient: AppGradients.background,
        borderRadius: isLandscape 
            ? const BorderRadius.only(
                topRight: Radius.circular(35),
                bottomRight: Radius.circular(35),
              )
            : const BorderRadius.only(
                bottomLeft: Radius.circular(35),
                bottomRight: Radius.circular(35),
              ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowYellow,
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.grey300.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: -25,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.grey400.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            right: 40,
            child: Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white.withOpacity(0.06),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.primaryBlue,
                size: ResponsiveUtils.getFontSize(context, 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Title and Icon
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                vertical: isLandscape ? 16 : 20,
                horizontal: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(isLandscape ? 10 : 16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.primaryYellow,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryYellow.withOpacity(0.4),
                          spreadRadius: 5,
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.white,
                      size: iconSize * (isLandscape ? 0.8 : 1),
                    ),
                  ),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 12)),
                  Text(
                    provider.isLoginFlow ? "Login Verification" : "Email Verification",
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 6)),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 10 : 40,
                    ),
                    child: Column(
                      children: [
                        Text(
                          provider.email.isNotEmpty
                              ? 'Enter the 6-digit code sent to'
                              : 'Enter the 6-digit verification code',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: subtitleFontSize * 0.95,
                            fontWeight: FontWeight.w400,
                            color: AppColors.primaryBlue,
                            height: 1.3,
                          ),
                        ),
                        if (provider.email.isNotEmpty) ...[
                          SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 4)),
                          Text(
                            provider.email,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: subtitleFontSize * 0.95,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpCard(BuildContext context) {
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final horizontalPadding = ResponsiveUtils.getHorizontalPadding(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    final containerPadding = EdgeInsets.symmetric(
      horizontal: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 12 : 20),
      vertical: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 12 : 20),
    );
    
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: horizontalPadding,
        child: Container(
          padding: containerPadding,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowGrey,
                spreadRadius: 0,
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.shadowYellow,
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Consumer<OtpVerificationProvider>(
            builder: (context, provider, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimerDisplay(context, provider),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                  _buildOtpInputFields(context, provider),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                  _buildVerifyButton(context, provider),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 12 : 20)),
                  _buildResendSection(context, provider),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTimerDisplay(BuildContext context, OtpVerificationProvider provider) {
    final fontSize = ResponsiveUtils.getFontSize(context, 12);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            color: AppColors.primaryBlue,
            size: fontSize * 1.3,
          ),
          const SizedBox(width: 6),
          Text(
            '${provider.countdown} seconds',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInputFields(BuildContext context, OtpVerificationProvider provider) {
    final otpBoxSize = ResponsiveUtils.getOtpBoxSize(context);
    final otpSpacing = ResponsiveUtils.getOtpSpacing(context);
    final fontSize = ResponsiveUtils.getFontSize(context, 18);
    
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            return Padding(
              padding: EdgeInsets.only(
                right: index < 5 ? otpSpacing : 0,
              ),
              child: _buildOtpBox(context, provider, index, otpBoxSize, fontSize),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildOtpBox(BuildContext context, OtpVerificationProvider provider, int index, double size, double fontSize) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    
    final adjustedFontSize = isLandscape ? fontSize.clamp(14.0, 18.0) : fontSize;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: provider.otpControllers[index],
        focusNode: provider.focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        maxLength: 1,
        enabled: !provider.isLoading,
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
          height: 1.2,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: provider.isLoading
              ? AppColors.grey200
              : AppColors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AppColors.primaryYellow,
              width: 2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AppColors.grey300,
              width: 1,
            ),
          ),
        ),
        onChanged: (value) {
          provider.onOtpDigitChanged(value, index);
          // Auto-verify when all 6 digits are entered
          if (value.isNotEmpty && index == 5) {
            String otp = provider.getOtp();
            if (otp.length == 6) {
              _handleVerifyOtp(context);
            }
          }
        },
      ),
    );
  }

  Widget _buildVerifyButton(BuildContext context, OtpVerificationProvider provider) {
    final fontSize = ResponsiveUtils.getFontSize(context, 16);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    double buttonHeight;
    if (isLandscape) {
      buttonHeight = 42.0;
    } else if (isTabletDevice) {
      buttonHeight = 60.0;
    } else {
      buttonHeight = 56.0;
    }
    
    bool isEnabled = !provider.isLoading;

    return Center(
      child: Container(
        width: isLandscape ? 250.0 : double.infinity,
        height: buttonHeight,
        decoration: BoxDecoration(
          gradient: isEnabled
              ? AppGradients.primaryYellow
              : const LinearGradient(
                  colors: [
                    AppColors.grey300,
                    AppColors.grey400,
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: AppColors.shadowYellow,
                    spreadRadius: 0,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: ElevatedButton(
          onPressed: isEnabled ? () => _handleVerifyOtp(context) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: provider.isLoading
              ? SizedBox(
                  height: isLandscape ? 16 : 20,
                  width: isLandscape ? 16 : 20,
                  child: const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Verify OTP",
                      style: TextStyle(
                        fontSize: isLandscape ? fontSize * 0.85 : fontSize * 0.9,
                        fontWeight: FontWeight.w700,
                        color: isEnabled ? AppColors.white : AppColors.grey600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: isLandscape ? 4 : 6),
                    Icon(
                      Icons.check_circle_outline,
                      color: isEnabled ? AppColors.white : AppColors.grey600,
                      size: isLandscape ? fontSize * 0.9 : fontSize,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildResendSection(BuildContext context, OtpVerificationProvider provider) {
    final fontSize = ResponsiveUtils.getFontSize(context, 13);
    final smallFontSize = ResponsiveUtils.getFontSize(context, 12);
    
    return Column(
      children: [
        Text(
          "Didn't receive the code?",
          style: TextStyle(
            fontSize: smallFontSize,
            color: AppColors.textLightGrey,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: provider.canResend && !provider.isLoading
              ? () => _handleResendOtp(context)
              : null,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            provider.canResend
                ? 'Resend OTP'
                : 'Resend OTP in ${provider.countdown}s',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: provider.canResend && !provider.isLoading
                  ? AppColors.primaryBlue
                  : AppColors.grey500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final verticalSpacing = ResponsiveUtils.getVerticalSpacing(context, 40);

    return ChangeNotifierProvider(
      create: (_) => OtpVerificationProvider()..initialize(args),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (isLandscape) {
                    // Landscape layout - side by side
                    return Row(
                      children: [
                        // Header section
                        Flexible(
                          flex: 2,
                          child: _buildHeader(context),
                        ),
                        // Content section
                        Flexible(
                          flex: 3,
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: ResponsiveUtils.getMaxContainerWidth(context),
                                ),
                                child: _buildOtpCard(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  
                  // Portrait layout - stacked
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHeader(context),
                        SizedBox(height: verticalSpacing),
                        _buildOtpCard(context),
                        SizedBox(
                          height: MediaQuery.of(context).viewInsets.bottom + 20,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          resizeToAvoidBottomInset: true,
        ),
      ),
    );
  }
}