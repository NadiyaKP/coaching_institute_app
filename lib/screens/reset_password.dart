import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
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

  static double getButtonHeight(BuildContext context) {
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    if (isLandscapeMode) {
      return 42.0;
    } else if (isTabletDevice) {
      return 60.0;
    }
    return 56.0;
  }
}

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

  Widget _buildHeader(BuildContext context) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
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

          // Title and Icon - Centered content
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
                      Icons.lock_reset,
                      color: AppColors.white,
                      size: iconSize * (isLandscape ? 0.8 : 1),
                    ),
                  ),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 12)),
                  Text(
                    "Reset Password",
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
                    child: Text(
                      "Create a strong password for your account",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleFontSize * 0.95,
                        fontWeight: FontWeight.w400,
                        color: AppColors.primaryBlue,
                        height: 1.3,
                      ),
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

  Widget _buildPasswordCard(BuildContext context) {
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final horizontalPadding = ResponsiveUtils.getHorizontalPadding(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    final containerPadding = EdgeInsets.symmetric(
      horizontal: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 12 : 20),
      vertical: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 12 : 20),
    );
    
    return ScaleTransition(
      scale: _scaleAnimation!,
      child: FadeTransition(
        opacity: _fadeAnimation!,
        child: Center(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPasswordField(
                    context,
                    title: "New Password",
                    controller: newPasswordController,
                    obscureText: obscureNewPassword,
                    isValid: isNewPasswordValid,
                    errorText: newPasswordError,
                    hintText: "Enter new password",
                    onToggleVisibility: () {
                      setState(() {
                        obscureNewPassword = !obscureNewPassword;
                      });
                    },
                    onChanged: (_) => _validateNewPassword(),
                  ),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                  _buildPasswordField(
                    context,
                    title: "Confirm Password",
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmPassword,
                    isValid: isConfirmPasswordValid,
                    errorText: confirmPasswordError,
                    hintText: "Re-enter new password",
                    onToggleVisibility: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                    onChanged: (_) => _validateConfirmPassword(),
                  ),
                  SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                  _buildContinueButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    BuildContext context, {
    required String title,
    required TextEditingController controller,
    required bool obscureText,
    required bool isValid,
    required String? errorText,
    required String hintText,
    required VoidCallback onToggleVisibility,
    required ValueChanged<String> onChanged,
  }) {
    final iconSize = ResponsiveUtils.getFontSize(context, 18);
    final titleFontSize = ResponsiveUtils.getFontSize(context, 16);
    final inputFontSize = ResponsiveUtils.getFontSize(context, 15);
    final hintFontSize = ResponsiveUtils.getFontSize(context, 14);
    final errorFontSize = ResponsiveUtils.getFontSize(context, 12.5);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                size: iconSize,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 12)),
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
              color: isValid 
                ? AppColors.successGreen.withOpacity(0.6)
                : errorText != null
                  ? AppColors.errorRed.withOpacity(0.6)
                  : AppColors.grey300,
              width: 1.5,
            ),
            boxShadow: isValid ? [
              BoxShadow(
                color: AppColors.successGreen.withOpacity(0.1),
                spreadRadius: 0,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : errorText != null ? [
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
                controller: controller,
                obscureText: obscureText,
                style: TextStyle(
                  fontSize: inputFontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey800,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: AppColors.grey500,
                    fontSize: hintFontSize,
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
                      if (isValid)
                        Icon(
                          Icons.check_circle,
                          color: AppColors.successGreen,
                          size: iconSize * 1.1,
                        )
                      else if (errorText != null)
                        Icon(
                          Icons.error,
                          color: AppColors.errorRed,
                          size: iconSize * 1.1,
                        ),
                      IconButton(
                        icon: Icon(
                          obscureText
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.grey500,
                          size: iconSize * 1.1,
                        ),
                        onPressed: onToggleVisibility,
                      ),
                    ],
                  ),
                ),
                onChanged: onChanged,
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.errorRed,
                        size: errorFontSize * 1.2,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorText,
                          style: TextStyle(
                            color: AppColors.errorRed,
                            fontSize: errorFontSize,
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
      ],
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    final fontSize = ResponsiveUtils.getFontSize(context, 16);
    final iconSize = ResponsiveUtils.getFontSize(context, 18);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final buttonHeight = ResponsiveUtils.getButtonHeight(context);
    
    bool isEnabled = isNewPasswordValid && isConfirmPasswordValid;

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
          onPressed: isEnabled && !isLoading ? _resetPassword : null,
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
          child: isLoading
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
                      "Continue",
                      style: TextStyle(
                        fontSize: isLandscape ? fontSize * 0.85 : fontSize * 0.9,
                        fontWeight: FontWeight.w700,
                        color: isEnabled ? AppColors.white : AppColors.grey600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: isLandscape ? 4 : 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: isEnabled ? AppColors.white : AppColors.grey600,
                      size: isLandscape ? iconSize * 0.9 : iconSize,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final verticalSpacing = ResponsiveUtils.getVerticalSpacing(context, 40);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isLandscape) {
                // Landscape layout - side by side with proper flex
                return Row(
                  children: [
                    // Header section - takes less space
                    Flexible(
                      flex: 2,
                      child: _buildHeader(context),
                    ),
                    // Content section - takes more space
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
                            child: _buildPasswordCard(context),
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
                    _buildPasswordCard(context),
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
    );
  }
}