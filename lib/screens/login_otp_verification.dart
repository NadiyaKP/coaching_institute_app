import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'home.dart';
import 'profile_completion_page.dart'; // Import the profile completion page
import '../service/api_config.dart'; // Import the API configuration
import '../service/auth_service.dart'; // Import the AuthService
import '../common/theme_color.dart'; // Import the theme colors
import '../common/continue_button.dart'; // Import the ContinueButton

class LoginOtpVerificationScreen extends StatefulWidget {
  const LoginOtpVerificationScreen({super.key});

  @override
  State<LoginOtpVerificationScreen> createState() => _LoginOtpVerificationScreenState();
}

class _LoginOtpVerificationScreenState extends State<LoginOtpVerificationScreen> {
  final List<TextEditingController> otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(6, (index) => FocusNode());
  bool isLoading = false;
  Timer? _timer;
  int _countdown = 59;
  bool _canResend = false;
  
  // Variables to store data from route arguments
  String phoneNumber = '';
  String countryCode = '+91';
  String mobileNumber = '';

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Extract arguments passed from previous screen
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      phoneNumber = args['phone_number'] ?? '';
      countryCode = args['country_code'] ?? '+91';
      mobileNumber = args['mobile_number'] ?? '';
      
      // Debug prints to verify data
      _debugLog('LOGIN OTP - ROUTE ARGUMENTS RECEIVED', {
        'phone_number': phoneNumber,
        'country_code': countryCode,
        'mobile_number': mobileNumber,
        'display_phone': getDisplayPhoneNumber(),
        'formatted_phone': getFormattedPhoneNumber(),
      });
    } else {
      debugPrint('WARNING: No route arguments received for login OTP');
    }
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

  // Start the countdown timer
  void _startTimer() {
    setState(() {
      _countdown = 59;
      _canResend = false;
    });
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  // Helper method for detailed debug logging
  void _debugLog(String title, dynamic content) {
    debugPrint('\n==================== $title ====================');
    if (content is Map || content is List) {
      debugPrint(const JsonEncoder.withIndent('  ').convert(content));
    } else {
      debugPrint(content.toString());
    }
    debugPrint('=' * (42 + title.length));
  }

  // Create HTTP client using ApiConfig
  static http.Client createHttpClient() {
    return IOClient(ApiConfig.createHttpClient());
  }

  // Helper method to get display phone number
  String getDisplayPhoneNumber() {
    if (phoneNumber.isEmpty) return '';
    
    // If phone number already contains country code, return as is
    if (phoneNumber.startsWith(countryCode)) {
      return phoneNumber;
    }
    
    // Otherwise, combine country code with phone number
    return '$countryCode $phoneNumber';
  }

  // Helper method to get formatted phone number for API call
  String getFormattedPhoneNumber() {
    if (phoneNumber.isEmpty) return '';
    
    // If phone number already contains country code, return as is
    if (phoneNumber.startsWith(countryCode)) {
      return phoneNumber;
    }
    
    // Otherwise, combine country code with phone number
    return '$countryCode$phoneNumber';
  }

  // Save login authentication data using AuthService
  Future<void> _saveLoginAuthData(Map<String, dynamic> responseData) async {
    try {
      final authService = AuthService();
      
      // Save authentication data using AuthService
      await authService.saveAuthData(responseData);
      
      debugPrint('✅ Login authentication data saved using AuthService');
      _debugLog('LOGIN_AUTH_SERVICE_DATA', {
        'isLoggedIn': true,
        'phoneNumber': responseData['phone_number'] ?? phoneNumber,
        'accessToken': responseData['access'] != null ? '***TOKEN_SAVED***' : 'NOT_FOUND',
        'studentType': responseData['student_type'] ?? '',
        'profileCompleted': responseData['profile_completed'] ?? false,
        'authSuccess': responseData.containsKey('success') ? responseData['success'] : 'NOT_FOUND',
      });
      
      // Optional: Debug print all auth data
      await authService.debugPrintAllData();
    } catch (e) {
      debugPrint('❌ Error saving login auth data using AuthService: $e');
    }
  }

  // Helper method to determine navigation based on profile completion
  void _navigateAfterLogin(Map<String, dynamic> responseData) {
    // Extract profile completion status
    bool profileCompleted = false;
    
    // Handle different possible formats for profile_completed
    if (responseData['profile_completed'] is bool) {
      profileCompleted = responseData['profile_completed'];
    } else if (responseData['profile_completed'] is String) {
      final profileCompletedString = responseData['profile_completed'].toString().toLowerCase();
      profileCompleted = profileCompletedString == 'true';
    } else {
      // Default to false if not provided or in unexpected format
      profileCompleted = false;
    }

    debugPrint('📊 Profile completion status: $profileCompleted');
    _debugLog('🧭 NAVIGATION DECISION', {
      'profile_completed_raw': responseData['profile_completed'],
      'profile_completed_processed': profileCompleted,
      'navigation_target': profileCompleted ? 'HOME' : 'PROFILE_COMPLETION',
    });

    // Prepare navigation arguments
    final navigationArgs = {
      'phone_number': responseData['phone_number'] ?? phoneNumber,
      'country_code': countryCode,
      'mobile_number': mobileNumber,
      'verified': true,
      'login_success': true,
      'student_type': responseData['student_type'] ?? '',
      'profile_completed': profileCompleted,
      // Include any user data from response if available
      if (responseData['access'] != null) 'access_token': responseData['access'],
    };

    _debugLog('🧭 NAVIGATION ARGUMENTS', navigationArgs);

    if (profileCompleted) {
      // Profile is completed - navigate to home screen
      debugPrint('🏠 Navigating to HOME screen (profile completed)');
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home',
        (route) => false,
        arguments: navigationArgs,
      );
    } else {
      // Profile is not completed - navigate to profile completion page
      debugPrint('📝 Navigating to PROFILE COMPLETION screen (profile incomplete)');
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/profile_completion_page', 
        (route) => false,
        arguments: navigationArgs,
      );
    }
  }

  void _onOtpDigitChanged(String value, int index) {
    debugPrint('Login OTP Digit Changed - Index: $index, Value: "$value"');
    
    if (value.isNotEmpty && index < 5) {
      focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }

    // Auto-verify when all 6 digits are entered
    if (value.isNotEmpty && index == 5) {
      String otp = otpControllers.map((controller) => controller.text).join();
      debugPrint('Login Auto-verify triggered - Complete OTP: "$otp"');
      if (otp.length == 6) {
        _verifyLoginOtp();
      }
    }
  }

  Future<void> _verifyLoginOtp() async {
    String otp = otpControllers.map((controller) => controller.text).join();
    debugPrint('\n🔍 LOGIN OTP VERIFICATION INITIATED');
    debugPrint('Current OTP: "$otp"');
    debugPrint('OTP Length: ${otp.length}');
    
    if (otp.length != 6) {
      debugPrint('❌ Login OTP validation failed - incomplete OTP');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter complete OTP'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    // Create HTTP client using ApiConfig
    final client = createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      // Use ApiConfig for the login OTP verification URL
      final requestUrl = ApiConfig.loginOtpVerificationUrl;
      
      // Prepare the request data
      final requestData = {
        'identifier': getFormattedPhoneNumber(),
        'otp': otp,
      };

      // Use ApiConfig for common headers
      final requestHeaders = ApiConfig.commonHeaders;

      // Log complete request details
      _debugLog('🚀 LOGIN OTP API REQUEST', {
        'method': 'POST',
        'url': requestUrl,
        'headers': requestHeaders,
        'body': requestData,
        'base_url': ApiConfig.currentBaseUrl,
        'is_development': ApiConfig.isDevelopment,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Make the API call with ApiConfig timeout
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

      // Log complete response details
      _debugLog('📥 LOGIN OTP API RESPONSE', {
        'status_code': response.statusCode,
        'status_message': response.reasonPhrase,
        'headers': response.headers,
        'body_raw': response.body,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Try to parse response body as JSON
      dynamic responseData;
      try {
        responseData = json.decode(response.body);
        _debugLog('📋 PARSED LOGIN RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse login response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Check if success is true (handle both boolean and string responses)
        bool isSuccess = false;
        if (responseData['success'] is bool) {
          isSuccess = responseData['success'];
        } else if (responseData['success'] is String) {
          isSuccess = responseData['success'].toString().toLowerCase() == 'true';
        }
        
        debugPrint('✅ Login success status determined: $isSuccess (HTTP ${response.statusCode})');
        
        setState(() {
          isLoading = false;
        });

        if (isSuccess) {
          // Save login authentication data to SharedPreferences
          await _saveLoginAuthData(responseData);
          
          if (mounted) {
            // Show success message
            final successMessage = responseData['message'] ?? 'Login successful';
            debugPrint('🎉 Login OTP verification successful: $successMessage');
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage),
                backgroundColor: AppColors.successGreen,
              ),
            );

            // Navigate based on profile completion status
            _navigateAfterLogin(responseData);
          }
        } else {
          // Handle unsuccessful login verification
          final errorMessage = responseData['message'] ?? 'Invalid OTP. Please try again.';
          debugPrint('❌ Login OTP verification failed: $errorMessage');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: AppColors.errorRed,
              ),
            );
            
            // Clear OTP fields for retry
            _clearOtpFields();
          }
        }
      } else if (response.statusCode == 400) {
        // Handle bad request (invalid OTP, expired, etc.)
        setState(() {
          isLoading = false;
        });
        
        final errorMessage = responseData['message'] ?? 'Invalid OTP. Please try again.';
        debugPrint('❌ Login Bad Request (400): $errorMessage');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.errorRed,
            ),
          );
          
          // Clear OTP fields for retry
          _clearOtpFields();
        }
      } else if (response.statusCode == 401) {
        // Handle unauthorized (user not found, account blocked, etc.)
        setState(() {
          isLoading = false;
        });
        
        final errorMessage = responseData['message'] ?? 'Account not found or blocked.';
        debugPrint('❌ Login Unauthorized (401): $errorMessage');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.errorRed,
            ),
          );
          
          // Navigate back to login screen
          Navigator.pop(context);
        }
      } else {
        // Handle other HTTP errors
        setState(() {
          isLoading = false;
        });
        
        debugPrint('❌ Login HTTP Error ${response.statusCode}: ${response.reasonPhrase}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network error. Please try again.'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('⏰ LOGIN REQUEST TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request timeout. Please check your connection and try again.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('🌐 LOGIN NETWORK ERROR', {
        'error': e.toString(),
        'message': e.message,
        'os_error': e.osError?.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Please check your network.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('💥 LOGIN UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login verification failed: ${e.toString()}'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } finally {
      client.close();
      debugPrint('🔒 Login HTTP client closed');
    }
  }

  void _clearOtpFields() {
    debugPrint('🧹 Clearing login OTP fields');
    for (var controller in otpControllers) {
      controller.clear();
    }
    if (focusNodes.isNotEmpty) {
      focusNodes[0].requestFocus();
      debugPrint('🎯 Focus set to first login OTP field');
    }
  }

  Future<void> _resendLoginOtp() async {
    debugPrint('\n🔄 RESEND LOGIN OTP INITIATED');
    
    setState(() {
      isLoading = true;
    });

    // Create HTTP client using ApiConfig
    final client = createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      // Build the resend OTP URL using ApiConfig - using student_login endpoint as requested
      final requestUrl = ApiConfig.currentStudentLoginUrl;
      
      // Prepare the request data with identifier as requested
      final requestData = {
        'identifier': getFormattedPhoneNumber(),
      };

      // Use ApiConfig for common headers
      final requestHeaders = ApiConfig.commonHeaders;

      // Log complete request details
      _debugLog('🚀 RESEND LOGIN OTP API REQUEST', {
        'method': 'POST',
        'url': requestUrl,
        'headers': requestHeaders,
        'body': requestData,
        'base_url': ApiConfig.currentBaseUrl,
        'is_development': ApiConfig.isDevelopment,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Make the API call with ApiConfig timeout
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

      // Log complete response details
      _debugLog('📥 RESEND LOGIN OTP API RESPONSE', {
        'status_code': response.statusCode,
        'status_message': response.reasonPhrase,
        'headers': response.headers,
        'body_raw': response.body,
        'response_time_ms': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      });

      setState(() {
        isLoading = false;
      });

      // Try to parse response body as JSON
      dynamic responseData;
      try {
        responseData = json.decode(response.body);
        _debugLog('📋 PARSED RESEND LOGIN RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse resend login response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final successMessage = responseData['message'] ?? 'Login OTP resent to ${getDisplayPhoneNumber()}';
        debugPrint('✅ Login OTP resend successful: $successMessage (HTTP ${response.statusCode})');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              backgroundColor: AppColors.successGreen,
            ),
          );
        }

        // Clear all OTP fields and restart timer
        _clearOtpFields();
        _startTimer();
      } else {
        debugPrint('❌ Resend login OTP failed with status: ${response.statusCode}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to resend OTP. Please try again.'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('⏰ RESEND LOGIN TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request timeout. Please try again.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('🌐 RESEND LOGIN NETWORK ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Please check your network.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('💥 RESEND LOGIN UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login OTP resent to ${getDisplayPhoneNumber()}'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        
        // Clear all OTP fields and restart timer
        _clearOtpFields();
        _startTimer();
      }
    } finally {
      client.close();
      debugPrint('🔒 Resend login HTTP client closed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.textDark, size: screenWidth * 0.05),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - 
                MediaQuery.of(context).padding.top - 
                kToolbarHeight,
            ),
            child: Column(
              children: [
                SizedBox(height: screenHeight * 0.03),
                
                // Header Section with Icon - Reduced size
                Container(
                  width: screenWidth * 0.15,
                  height: screenWidth * 0.15,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primaryYellow,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowYellow,
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.white,
                    size: screenWidth * 0.07,
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.025),
                
                // Title - Reduced font size
                Text(
                  'Login Verification',
                  style: TextStyle(
                    fontSize: screenWidth * 0.06,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.5,
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.012),
                
                // Description - Reduced font size
                Text(
                  phoneNumber.isNotEmpty 
                    ? 'Enter the 6-digit code sent to'
                    : 'Enter the 6-digit verification code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.006),
                
                // Phone Number Display - Reduced font size
                if (phoneNumber.isNotEmpty)
                  Text(
                    getDisplayPhoneNumber(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                
                SizedBox(height: screenHeight * 0.035),
                
                // Timer Display with Progress Indicator - Reduced font size
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        size: 16,
                      ),
                      SizedBox(width: 5),
                      Text(
                        '$_countdown seconds',
                        style: TextStyle(
                          fontSize: screenWidth * 0.03,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.04),
                
                // OTP Input Fields with Reduced Size
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (index) {
                      return Container(
                        width: screenWidth * 0.11,
                        height: screenWidth * 0.11,
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
                          controller: otpControllers[index],
                          focusNode: focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          enabled: !isLoading,
                          style: TextStyle(
                            fontSize: screenWidth * 0.05,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: isLoading ? AppColors.grey200 : AppColors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.primaryYellow,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.grey300,
                                width: 1,
                              ),
                            ),
                          ),
                          onChanged: (value) => _onOtpDigitChanged(value, index),
                        ),
                      );
                    }),
                  ),
                ),
                
                SizedBox(height: screenHeight * 0.05),
                
                // Verify Button using ContinueButton class
                ContinueButton(
                  isEnabled: !isLoading,
                  isLoading: isLoading,
                  onPressed: _verifyLoginOtp,
                  screenWidth: screenWidth,
                ),
                
                SizedBox(height: screenHeight * 0.025),
                
                // Resend OTP Section - Reduced font sizes
                Column(
                  children: [
                    Text(
                      "Didn't receive the code?",
                      style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: AppColors.textLightGrey,
                      ),
                    ),
                    SizedBox(height: 6),
                    TextButton(
                      onPressed: _canResend && !isLoading ? _resendLoginOtp : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      ),
                      child: Text(
                        _canResend ? 'Resend OTP' : 'Resend OTP in $_countdown seconds',
                        style: TextStyle(
                          fontSize: screenWidth * 0.034,
                          fontWeight: FontWeight.w600,
                          color: _canResend && !isLoading 
                              ? AppColors.primaryBlue 
                              : AppColors.grey500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Add extra space when keyboard is visible
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 
                    ? MediaQuery.of(context).viewInsets.bottom + 16 
                    : screenHeight * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }
}