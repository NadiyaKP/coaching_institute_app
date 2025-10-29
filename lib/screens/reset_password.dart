import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  
  bool isLoading = false;
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  
  // Validation variables
  String? newPasswordError;
  String? confirmPasswordError;
  bool isNewPasswordValid = false;
  bool isConfirmPasswordValid = false;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;
  
  // Variables to store data from route arguments
  String email = '';
  String resetToken = '';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Extract arguments passed from OTP verification screen
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      email = args['email'] ?? '';
      resetToken = args['reset_token'] ?? '';
      
      // Debug prints to verify data
      _debugLog('RESET PASSWORD - ROUTE ARGUMENTS RECEIVED', {
        'email': email,
        'reset_token_received': resetToken.isNotEmpty ? '***TOKEN_RECEIVED***' : 'NOT_FOUND',
        'verified': args['verified'] ?? false,
      });
    } else {
      debugPrint('WARNING: No route arguments received for Reset Password');
    }
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController!, 
        curve: Curves.easeOutBack,
      ),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController!, 
        curve: Curves.easeOut,
      ),
    );
    
    _animationController?.forward();
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    _animationController?.dispose();
    super.dispose();
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

  void _validateNewPassword() {
    final password = newPasswordController.text;
    
    if (password.isEmpty) {
      setState(() {
        newPasswordError = null;
        isNewPasswordValid = false;
      });
      return;
    }
    
    // Password validation: minimum 4 characters
    if (password.length < 4) {
      setState(() {
        newPasswordError = 'Password must be at least 4 characters';
        isNewPasswordValid = false;
      });
      return;
    }
    
    setState(() {
      newPasswordError = null;
      isNewPasswordValid = true;
    });
    
    // Re-validate confirm password if it has content
    if (confirmPasswordController.text.isNotEmpty) {
      _validateConfirmPassword();
    }
  }

  void _validateConfirmPassword() {
    final confirmPassword = confirmPasswordController.text;
    final newPassword = newPasswordController.text;
    
    if (confirmPassword.isEmpty) {
      setState(() {
        confirmPasswordError = null;
        isConfirmPasswordValid = false;
      });
      return;
    }
    
    if (confirmPassword != newPassword) {
      setState(() {
        confirmPasswordError = 'Passwords do not match';
        isConfirmPasswordValid = false;
      });
      return;
    }
    
    setState(() {
      confirmPasswordError = null;
      isConfirmPasswordValid = true;
    });
  }

  Future<void> _resetPassword() async {
    _validateNewPassword();
    _validateConfirmPassword();
    
    if (!isNewPasswordValid) {
      if (newPasswordController.text.trim().isEmpty) {
        _showSnackBar('Please enter your new password', AppColors.errorRed);
      }
      return;
    }
    
    if (!isConfirmPasswordValid) {
      if (confirmPasswordController.text.trim().isEmpty) {
        _showSnackBar('Please confirm your password', AppColors.errorRed);
      }
      return;
    }

    if (resetToken.isEmpty) {
      _showSnackBar('Invalid reset token. Please try again.', AppColors.errorRed);
      Navigator.pushReplacementNamed(context, '/forgot_password');
      return;
    }

    setState(() {
      isLoading = true;
    });

    final newPassword = newPasswordController.text.trim();
    
    debugPrint('\n🔒 RESET PASSWORD INITIATED');
    debugPrint('Email: $email');
    debugPrint('New Password Length: ${newPassword.length}');

    // Create HTTP client using ApiConfig
    final client = createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/reset-password/';
      
      final requestData = {
        'reset_token': resetToken,
        'new_password': newPassword,
      };

      // Use ApiConfig for common headers
      final requestHeaders = ApiConfig.commonHeaders;

      // Log complete request details
      _debugLog('🚀 RESET PASSWORD API REQUEST', {
        'method': 'POST',
        'url': requestUrl,
        'headers': requestHeaders,
        'body': {
          'reset_token': '***TOKEN***',
          'new_password': '***PASSWORD***',
        },
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
      _debugLog('📥 RESET PASSWORD API RESPONSE', {
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

      setState(() {
        isLoading = false;
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Check if success is true
        bool isSuccess = false;
        if (responseData['success'] is bool) {
          isSuccess = responseData['success'];
        } else if (responseData['success'] is String) {
          isSuccess = responseData['success'].toString().toLowerCase() == 'true';
        }
        
        debugPrint('✅ Password reset success status: $isSuccess (HTTP ${response.statusCode})');
        
        if (isSuccess) {
          final successMessage = responseData['message'] ?? 'Password reset successful!';
          debugPrint('🎉 Password reset successful: $successMessage');
          
          if (mounted) {
            _showSnackBar(successMessage, AppColors.successGreen);

            // Navigate to login screen after successful password reset
            Future.delayed(const Duration(milliseconds: 1500), () {
              debugPrint('🧭 Navigating to: /signup');
              Navigator.pushNamedAndRemoveUntil(
                context, 
                 '/signup',
                (route) => false,
              );
            });
          }
        } else {
          final errorMessage = responseData['message'] ?? 'Failed to reset password';
          debugPrint('❌ Password reset failed: $errorMessage');
          
          if (mounted) {
            _showSnackBar(errorMessage, AppColors.errorRed);
          }
        }
      } else if (response.statusCode == 400) {
        final errorMessage = responseData['message'] ?? 'Invalid request. Please try again.';
        debugPrint('❌ Bad Request (400): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
        }
      } else if (response.statusCode == 401) {
        final errorMessage = responseData['message'] ?? 'Reset token expired. Please request a new one.';
        debugPrint('❌ Unauthorized (401): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
          
          // Navigate back to forgot password screen
          Future.delayed(const Duration(milliseconds: 1500), () {
            Navigator.pushReplacementNamed(context, '/forgot_password');
          });
        }
      } else if (response.statusCode == 404) {
        final errorMessage = responseData['message'] ?? 'User not found.';
        debugPrint('❌ Not Found (404): $errorMessage');
        
        if (mounted) {
          _showSnackBar(errorMessage, AppColors.errorRed);
        }
      } else {
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
          'Password reset failed: ${e.toString()}',
          AppColors.errorRed,
        );
      }
    } finally {
      client.close();
      debugPrint('🔒 HTTP client closed');
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

  Widget _buildHeader() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      width: double.infinity,
      height: screenHeight * 0.35,
      decoration: BoxDecoration(
        gradient: AppGradients.background,
        borderRadius: const BorderRadius.only(
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
          
          // Title and Icon
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
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
                    Icons.lock_reset,
                    color: AppColors.white,
                    size: screenWidth * 0.12,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Reset Password",
                  style: TextStyle(
                    fontSize: screenWidth * 0.065,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "Create a strong password for your account",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.037,
                      fontWeight: FontWeight.w400,
                      color: AppColors.primaryBlue,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return ScaleTransition(
      scale: _scaleAnimation!,
      child: FadeTransition(
        opacity: _fadeAnimation!,
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // New Password Section
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryYellow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: AppColors.white,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "New Password",
                    style: TextStyle(
                      fontSize: screenWidth * 0.042,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // New Password input field
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.grey50,
                      AppColors.grey100,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isNewPasswordValid 
                      ? AppColors.successGreen.withOpacity(0.6)
                      : newPasswordError != null
                        ? AppColors.errorRed.withOpacity(0.6)
                        : AppColors.grey300,
                    width: 1.5,
                  ),
                  boxShadow: isNewPasswordValid ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : newPasswordError != null ? [
                    BoxShadow(
                      color: AppColors.errorRed.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : [],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNewPassword,
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey800,
                      ),
                      decoration: InputDecoration(
                        hintText: "Enter new password",
                        hintStyle: TextStyle(
                          color: AppColors.grey500,
                          fontSize: screenWidth * 0.037,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isNewPasswordValid)
                              Icon(
                                Icons.check_circle,
                                color: AppColors.successGreen,
                                size: screenWidth * 0.055,
                              )
                            else if (newPasswordError != null)
                              Icon(
                                Icons.error,
                                color: AppColors.errorRed,
                                size: screenWidth * 0.055,
                              ),
                            IconButton(
                              icon: Icon(
                                obscureNewPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.grey500,
                                size: screenWidth * 0.055,
                              ),
                              onPressed: () {
                                setState(() {
                                  obscureNewPassword = !obscureNewPassword;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      onChanged: (value) {
                        _validateNewPassword();
                      },
                    ),
                    
                    if (newPasswordError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.errorRed,
                              size: screenWidth * 0.04,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                newPasswordError!,
                                style: TextStyle(
                                  color: AppColors.errorRed,
                                  fontSize: screenWidth * 0.034,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Confirm Password Section
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryYellow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: AppColors.white,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Confirm Password",
                    style: TextStyle(
                      fontSize: screenWidth * 0.042,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Confirm Password input field
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.grey50,
                      AppColors.grey100,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConfirmPasswordValid 
                      ? AppColors.successGreen.withOpacity(0.6)
                      : confirmPasswordError != null
                        ? AppColors.errorRed.withOpacity(0.6)
                        : AppColors.grey300,
                    width: 1.5,
                  ),
                  boxShadow: isConfirmPasswordValid ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : confirmPasswordError != null ? [
                    BoxShadow(
                      color: AppColors.errorRed.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : [],
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirmPassword,
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey800,
                      ),
                      decoration: InputDecoration(
                        hintText: "Re-enter new password",
                        hintStyle: TextStyle(
                          color: AppColors.grey500,
                          fontSize: screenWidth * 0.037,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isConfirmPasswordValid)
                              Icon(
                                Icons.check_circle,
                                color: AppColors.successGreen,
                                size: screenWidth * 0.055,
                              )
                            else if (confirmPasswordError != null)
                              Icon(
                                Icons.error,
                                color: AppColors.errorRed,
                                size: screenWidth * 0.055,
                              ),
                            IconButton(
                              icon: Icon(
                                obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.grey500,
                                size: screenWidth * 0.055,
                              ),
                              onPressed: () {
                                setState(() {
                                  obscureConfirmPassword = !obscureConfirmPassword;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      onChanged: (value) {
                        _validateConfirmPassword();
                      },
                    ),
                    
                    if (confirmPasswordError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.errorRed,
                              size: screenWidth * 0.04,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                confirmPasswordError!,
                                style: TextStyle(
                                  color: AppColors.errorRed,
                                  fontSize: screenWidth * 0.034,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Continue button
              _buildContinueButton(screenWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton(double screenWidth) {
    bool isEnabled = isNewPasswordValid && isConfirmPasswordValid;
    
    return Container(
      width: double.infinity,
      height: 56,
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
        onPressed: isEnabled && !isLoading ? _resetPassword : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Continue",
                    style: TextStyle(
                      fontSize: screenWidth * 0.042,
                      fontWeight: FontWeight.w700,
                      color: isEnabled ? AppColors.white : AppColors.grey600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: isEnabled ? AppColors.white : AppColors.grey600,
                    size: screenWidth * 0.05,
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              _buildPasswordCard(),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
            ],
          ),
        ),
      ),
    );
  }
    }
