import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:coaching_institute_app/common/continue_button.dart';

class ForgotOtpVerificationScreen extends StatefulWidget {
  const ForgotOtpVerificationScreen({super.key});

  @override
  State<ForgotOtpVerificationScreen> createState() => _ForgotOtpVerificationScreenState();
}

class _ForgotOtpVerificationScreenState extends State<ForgotOtpVerificationScreen> {
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
  String email = '';
  String receivedOtp = '';
  
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Extract arguments passed from forgot password screen
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      email = args['email'] ?? '';
      receivedOtp = args['otp']?.toString() ?? '';
      
      // Debug prints to verify data
      _debugLog('FORGOT OTP VERIFICATION - ROUTE ARGUMENTS RECEIVED', {
        'email': email,
        'otp_received': receivedOtp.isNotEmpty ? '***OTP_RECEIVED***' : 'NOT_FOUND',
      });
    } else {
      debugPrint('WARNING: No route arguments received for Forgot OTP verification');
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

  void _onOtpDigitChanged(String value, int index) {
    debugPrint('OTP Digit Changed - Index: $index, Value: "$value"');
    
    if (value.isNotEmpty && index < 5) {
      focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      focusNodes[index - 1].requestFocus();
    }

    // Auto-verify when all 6 digits are entered
    if (value.isNotEmpty && index == 5) {
      String otp = otpControllers.map((controller) => controller.text).join();
      debugPrint('Auto-verify triggered - Complete OTP: "$otp"');
      if (otp.length == 6) {
        _verifyOtp();
      }
    }
  }

  Future<void> _verifyOtp() async {
    String otp = otpControllers.map((controller) => controller.text).join();
    debugPrint('\n🔍 FORGOT PASSWORD OTP VERIFICATION INITIATED');
    debugPrint('Current OTP: "$otp"');
    debugPrint('OTP Length: ${otp.length}');
    debugPrint('Email: $email');
    
    if (otp.length != 6) {
      debugPrint('❌ OTP validation failed - incomplete OTP');
      _showSnackBar('Please enter complete OTP', AppColors.errorRed);
      return;
    }

    setState(() {
      isLoading = true;
    });

    // Create HTTP client using ApiConfig
    final client = createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      // Use the verify OTP endpoint
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/verify-otp/';
      
      // Prepare the request data with email and OTP
      final requestData = {
        'email': email,
        'otp': otp,
      };

      // Use ApiConfig for common headers
      final requestHeaders = ApiConfig.commonHeaders;

      // Log complete request details
      _debugLog('🚀 FORGOT OTP VERIFICATION API REQUEST', {
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
      _debugLog('📥 FORGOT OTP VERIFICATION API RESPONSE', {
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
        _debugLog('📋 PARSED RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Check if success is true
        bool isSuccess = false;
        if (responseData['success'] is bool) {
          isSuccess = responseData['success'];
        } else if (responseData['success'] is String) {
          isSuccess = responseData['success'].toString().toLowerCase() == 'true';
        }
        
        debugPrint('✅ OTP verification success status determined: $isSuccess (HTTP ${response.statusCode})');
        
        setState(() {
          isLoading = false;
        });

        if (isSuccess) {
          // Extract reset token from response
          final resetToken = responseData['reset_token'] ?? '';
          
          if (resetToken.isEmpty) {
            debugPrint('⚠️ Warning: Reset token not found in response');
            _showSnackBar('Invalid response from server', AppColors.errorRed);
            return;
          }

          debugPrint('🎉 OTP verification successful - Reset token received');
          
          if (mounted) {
            // Show success message
            _showSnackBar('OTP verified successfully!', AppColors.successGreen);

            // Prepare navigation arguments for reset password page
            final navigationArgs = {
              'email': email,
              'reset_token': resetToken,
              'verified': true,
            };

            _debugLog('🧭 NAVIGATION ARGUMENTS FOR RESET PASSWORD', navigationArgs);

            // Navigate to reset password page
            Future.delayed(const Duration(milliseconds: 800), () {
              debugPrint('🧭 Navigating to: /reset_password');
              Navigator.pushReplacementNamed(
                context, 
                '/reset_password',
                arguments: navigationArgs,
              );
            });
          }
        } else {
          // Handle unsuccessful OTP verification
          final errorMessage = responseData['message'] ?? 'Invalid OTP. Please try again.';
          debugPrint('❌ OTP verification failed: $errorMessage');
          
          if (mounted) {
            _showSnackBar(errorMessage, AppColors.errorRed);
            
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
        debugPrint('❌ Bad Request (400): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
          
          // Clear OTP fields for retry
          _clearOtpFields();
        }
      } else if (response.statusCode == 404) {
        // Handle not found (email not found, etc.)
        setState(() {
          isLoading = false;
        });
        
        final errorMessage = responseData['message'] ?? 'Email not found.';
        debugPrint('❌ Not Found (404): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
          
          // Navigate back to forgot password screen
          Navigator.pop(context);
        }
      } else {
        // Handle other HTTP errors
        setState(() {
          isLoading = false;
        });
        
        debugPrint('❌ HTTP Error ${response.statusCode}: ${response.reasonPhrase}');
        
        if (mounted) {
          _showSnackBar('Network error. Please try again.', AppColors.errorRed);
        }
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('⏰ REQUEST TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      if (mounted) {
        _showSnackBar(
          'Request timeout. Please check your connection and try again.',
          AppColors.errorRed,
        );
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('🌐 NETWORK ERROR', {
        'error': e.toString(),
        'message': e.message,
        'os_error': e.osError?.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        _showSnackBar(
          'No internet connection. Please check your network.',
          AppColors.errorRed,
        );
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('💥 UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        _showSnackBar(
          'Verification failed: ${e.toString()}',
          AppColors.errorRed,
        );
      }
    } finally {
      client.close();
      debugPrint('🔒 HTTP client closed');
    }
  }

  void _clearOtpFields() {
    debugPrint('🧹 Clearing OTP fields');
    for (var controller in otpControllers) {
      controller.clear();
    }
    if (focusNodes.isNotEmpty) {
      focusNodes[0].requestFocus();
      debugPrint('🎯 Focus set to first OTP field');
    }
  }

  Future<void> _resendOtp() async {
    debugPrint('\n🔄 RESEND FORGOT PASSWORD OTP INITIATED');
    debugPrint('Email: $email');
    
    setState(() {
      isLoading = true;
    });

    // Create HTTP client using ApiConfig
    final client = createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      // Use the same forget password endpoint to resend OTP
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/forget-password/';
      
      final requestData = {
        'email': email,
      };

      // Use ApiConfig for common headers
      final requestHeaders = ApiConfig.commonHeaders;

      // Log complete request details
      _debugLog('🚀 RESEND FORGOT PASSWORD OTP API REQUEST', {
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
      _debugLog('📥 RESEND OTP API RESPONSE', {
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
        _debugLog('📋 PARSED RESEND RESPONSE DATA', responseData);
      } catch (e) {
        debugPrint('⚠️ Failed to parse resend response as JSON: $e');
        responseData = {'raw_body': response.body};
      }

      if (response.statusCode == 200) {
        // Check if success is true
        bool isSuccess = false;
        if (responseData['success'] is bool) {
          isSuccess = responseData['success'];
        } else if (responseData['success'] is String) {
          isSuccess = responseData['success'].toString().toLowerCase() == 'true';
        }

        if (isSuccess) {
          final successMessage = responseData['message'] ?? 'OTP resent successfully to $email';
          debugPrint('✅ OTP resend successful: $successMessage (HTTP ${response.statusCode})');
          
          if (mounted) {
            _showSnackBar(successMessage, AppColors.successGreen);
          }

          // Clear all OTP fields and restart timer
          _clearOtpFields();
          _startTimer();
        } else {
          final errorMessage = responseData['message'] ?? 'Failed to resend OTP';
          debugPrint('❌ Resend OTP failed: $errorMessage');
          
          if (mounted) {
            _showSnackBar(errorMessage, AppColors.errorRed);
          }
        }
      } else if (response.statusCode == 404) {
        final errorMessage = responseData['message'] ?? 'Email not found';
        debugPrint('❌ Email not found (404): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
        }
      } else {
        debugPrint('❌ Resend OTP failed with status: ${response.statusCode}');
        
        if (mounted) {
          _showSnackBar('Failed to resend OTP. Please try again.', AppColors.errorRed);
        }
      }
    } on TimeoutException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('⏰ RESEND TIMEOUT', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
        'timeout_duration': ApiConfig.requestTimeout.inSeconds.toString() + ' seconds',
      });
      
      if (mounted) {
        _showSnackBar('Request timeout. Please try again.', AppColors.errorRed);
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('🌐 RESEND NETWORK ERROR', {
        'error': e.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        _showSnackBar(
          'No internet connection. Please check your network.',
          AppColors.errorRed,
        );
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      setState(() {
        isLoading = false;
      });
      
      _debugLog('💥 RESEND UNEXPECTED ERROR', {
        'error': e.toString(),
        'stack_trace': stackTrace.toString(),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      
      if (mounted) {
        _showSnackBar('Failed to resend OTP. Please try again.', AppColors.errorRed);
      }
    } finally {
      client.close();
      debugPrint('🔒 Resend HTTP client closed');
    }
  }

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
                
                // Header Section with Icon
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
                  email.isNotEmpty 
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
                if (email.isNotEmpty)
                  Text(
                    email,
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
                
                // Verify Button
                ContinueButton(
                  isEnabled: !isLoading,
                  isLoading: isLoading,
                  onPressed: _verifyOtp,
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
                    SizedBox(height: 6),
                    TextButton(
                      onPressed: _canResend && !isLoading ? _resendOtp : null,
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