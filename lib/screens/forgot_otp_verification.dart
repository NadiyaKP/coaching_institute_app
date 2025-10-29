import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:coaching_institute_app/common/continue_button.dart';

// ==================== PROVIDER CLASS ====================
class ForgotOtpProvider extends ChangeNotifier {
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
  String _email = '';
  String _receivedOtp = '';
  bool _isInitialized = false;

  // Getters
  bool get isLoading => _isLoading;
  int get countdown => _countdown;
  bool get canResend => _canResend;
  String get email => _email;
  String get receivedOtp => _receivedOtp;
  bool get isInitialized => _isInitialized;

  // Initialize with route arguments
  void initialize(Map<String, dynamic>? args) {
    if (_isInitialized) return; // Prevent re-initialization
    
    if (args != null) {
      _email = args['email'] ?? '';
      _receivedOtp = args['otp']?.toString() ?? '';
      
      _debugLog('FORGOT OTP VERIFICATION - ROUTE ARGUMENTS RECEIVED', {
        'email': _email,
        'otp_received': _receivedOtp.isNotEmpty ? '***OTP_RECEIVED***' : 'NOT_FOUND',
      });
    } else {
      debugPrint('WARNING: No route arguments received for Forgot OTP verification');
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

  // Verify OTP
  Future<Map<String, dynamic>> verifyOtp() async {
    String otp = getOtp();
    debugPrint('\n🔍 FORGOT PASSWORD OTP VERIFICATION INITIATED');
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
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/verify-otp/';
      
      final requestData = {
        'email': _email,
        'otp': otp,
      };

      final requestHeaders = ApiConfig.commonHeaders;

      _debugLog('🚀 FORGOT OTP VERIFICATION API REQUEST', {
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

      _debugLog('📥 FORGOT OTP VERIFICATION API RESPONSE', {
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
          final resetToken = responseData['reset_token'] ?? '';
          
          if (resetToken.isEmpty) {
            debugPrint('⚠️ Warning: Reset token not found in response');
            return {
              'success': false,
              'message': 'Invalid response from server',
            };
          }

          debugPrint('🎉 OTP verification successful - Reset token received');
          
          return {
            'success': true,
            'message': 'OTP verified successfully!',
            'reset_token': resetToken,
            'email': _email,
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
      } else if (response.statusCode == 404) {
        final errorMessage = responseData['message'] ?? 'Email not found.';
        debugPrint('❌ Not Found (404): $errorMessage');
        
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

  // Resend OTP
  Future<Map<String, dynamic>> resendOtp() async {
    debugPrint('\n🔄 RESEND FORGOT PASSWORD OTP INITIATED');
    debugPrint('Email: $_email');
    
    _isLoading = true;
    notifyListeners();

    final client = _createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/forget-password/';
      
      final requestData = {
        'email': _email,
      };

      final requestHeaders = ApiConfig.commonHeaders;

      _debugLog('🚀 RESEND FORGOT PASSWORD OTP API REQUEST', {
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

      if (response.statusCode == 200) {
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
      } else if (response.statusCode == 404) {
        final errorMessage = responseData['message'] ?? 'Email not found';
        debugPrint('❌ Email not found (404): $errorMessage');
        
        return {
          'success': false,
          'message': errorMessage,
        };
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
class ForgotOtpVerificationScreen extends StatelessWidget {
  const ForgotOtpVerificationScreen({super.key});

  void _showSnackBar(BuildContext context, String message, Color color) {
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

  Future<void> _handleVerifyOtp(BuildContext context) async {
    final provider = context.read<ForgotOtpProvider>();
    final result = await provider.verifyOtp();

    if (!context.mounted) return;

    if (result['success'] == true) {
      _showSnackBar(context, result['message'], AppColors.successGreen);

      final navigationArgs = {
        'email': result['email'],
        'reset_token': result['reset_token'],
        'verified': true,
      };

      Future.delayed(const Duration(milliseconds: 800), () {
        if (context.mounted) {
          debugPrint('🧭 Navigating to: /reset_password');
          Navigator.pushReplacementNamed(
            context,
            '/reset_password',
            arguments: navigationArgs,
          );
        }
      });
    } else {
      _showSnackBar(context, result['message'], AppColors.errorRed);

      if (result['navigate_back'] == true) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleResendOtp(BuildContext context) async {
    final provider = context.read<ForgotOtpProvider>();
    final result = await provider.resendOtp();

    if (!context.mounted) return;

    if (result['success'] == true) {
      _showSnackBar(context, result['message'], AppColors.successGreen);
    } else {
      _showSnackBar(context, result['message'], AppColors.errorRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Get route arguments
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    return ChangeNotifierProvider(
      create: (_) => ForgotOtpProvider()..initialize(args),
      child: Scaffold(
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
          child: Consumer<ForgotOtpProvider>(
            builder: (context, provider, child) {
              return SingleChildScrollView(
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

                      // Header Icon
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
                          Icons.lock_reset,
                          color: AppColors.white,
                          size: screenWidth * 0.07,
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.025),

                      // Title
                      Text(
                        'Email Verification',
                        style: TextStyle(
                          fontSize: screenWidth * 0.06,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          letterSpacing: 0.5,
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.012),

                      // Description
                      Text(
                        provider.email.isNotEmpty
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

                      // Email Display
                      if (provider.email.isNotEmpty)
                        Text(
                          provider.email,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.038,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),

                      SizedBox(height: screenHeight * 0.035),

                      // Timer Display
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: AppColors.primaryBlue,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${provider.countdown} seconds',
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

                      // OTP Input Fields
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
                                controller: provider.otpControllers[index],
                                focusNode: provider.focusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                enabled: !provider.isLoading,
                                style: TextStyle(
                                  fontSize: screenWidth * 0.05,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  filled: true,
                                  fillColor: provider.isLoading
                                      ? AppColors.grey200
                                      : AppColors.white,
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
                          }),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.05),

                      // Verify Button
                      ContinueButton(
                        isEnabled: !provider.isLoading,
                        isLoading: provider.isLoading,
                        onPressed: () => _handleVerifyOtp(context),
                        screenWidth: screenWidth,
                      ),

                      SizedBox(height: screenHeight * 0.025),

                      // Resend OTP Section
                      Column(
                        children: [
                          Text(
                            "Didn't receive the code?",
                            style: TextStyle(
                              fontSize: screenWidth * 0.032,
                              color: AppColors.textLightGrey,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: provider.canResend && !provider.isLoading
                                ? () => _handleResendOtp(context)
                                : null,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                            ),
                            child: Text(
                              provider.canResend
                                  ? 'Resend OTP'
                                  : 'Resend OTP in ${provider.countdown} seconds',
                              style: TextStyle(
                                fontSize: screenWidth * 0.034,
                                fontWeight: FontWeight.w600,
                                color: provider.canResend && !provider.isLoading
                                    ? AppColors.primaryBlue
                                    : AppColors.grey500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Extra space for keyboard
                      SizedBox(
                        height: MediaQuery.of(context).viewInsets.bottom > 0
                            ? MediaQuery.of(context).viewInsets.bottom + 16
                            : screenHeight * 0.04,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}