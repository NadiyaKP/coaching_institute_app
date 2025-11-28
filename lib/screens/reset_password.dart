import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
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

// ==================== PROVIDER CLASS ====================
class ResetPasswordProvider extends ChangeNotifier {
  // Controllers
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  
  // State variables
  bool _isLoading = false;
  
  // Validation variables
  String? _newPasswordError;
  String? _confirmPasswordError;
  bool _isNewPasswordValid = false;
  bool _isConfirmPasswordValid = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  
  // Variables to store data from route arguments
  String _email = '';
  String _resetToken = '';
  bool _isInitialized = false;

  // Getters
  bool get isLoading => _isLoading;
  String? get newPasswordError => _newPasswordError;
  String? get confirmPasswordError => _confirmPasswordError;
  bool get isNewPasswordValid => _isNewPasswordValid;
  bool get isConfirmPasswordValid => _isConfirmPasswordValid;
  bool get obscureNewPassword => _obscureNewPassword;
  bool get obscureConfirmPassword => _obscureConfirmPassword;
  String get email => _email;
  String get resetToken => _resetToken;
  bool get isInitialized => _isInitialized;

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // Initialize with route arguments
  void initialize(Map<String, dynamic>? args) {
    if (_isInitialized) return;
    
    if (args != null) {
      _email = args['email'] ?? '';
      _resetToken = args['reset_token'] ?? '';
      
      _debugLog('RESET PASSWORD - ROUTE ARGUMENTS RECEIVED', {
        'email': _email,
        'reset_token_received': _resetToken.isNotEmpty ? '***TOKEN_RECEIVED***' : 'NOT_FOUND',
        'verified': args['verified'] ?? false,
      });
    } else {
      debugPrint('WARNING: No route arguments received for Reset Password');
    }
    
    _isInitialized = true;
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

  // Password validation methods
  void validateNewPassword() {
    final password = newPasswordController.text;
    
    if (password.isEmpty) {
      _newPasswordError = null;
      _isNewPasswordValid = false;
      notifyListeners();
      return;
    }
    
    // Password validation: minimum 4 characters
    if (password.length < 4) {
      _newPasswordError = 'Password must be at least 4 characters';
      _isNewPasswordValid = false;
      notifyListeners();
      return;
    }
    
    _newPasswordError = null;
    _isNewPasswordValid = true;
    notifyListeners();
    
    // Re-validate confirm password if it has content
    if (confirmPasswordController.text.isNotEmpty) {
      validateConfirmPassword();
    }
  }

  void validateConfirmPassword() {
    final confirmPassword = confirmPasswordController.text;
    final newPassword = newPasswordController.text;
    
    if (confirmPassword.isEmpty) {
      _confirmPasswordError = null;
      _isConfirmPasswordValid = false;
      notifyListeners();
      return;
    }
    
    if (confirmPassword != newPassword) {
      _confirmPasswordError = 'Passwords do not match';
      _isConfirmPasswordValid = false;
      notifyListeners();
      return;
    }
    
    _confirmPasswordError = null;
    _isConfirmPasswordValid = true;
    notifyListeners();
  }

  // Toggle password visibility
  void toggleNewPasswordVisibility() {
    _obscureNewPassword = !_obscureNewPassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _obscureConfirmPassword = !_obscureConfirmPassword;
    notifyListeners();
  }

  // Reset password API call
  Future<Map<String, dynamic>> resetPassword() async {
    validateNewPassword();
    validateConfirmPassword();
    
    if (!_isNewPasswordValid) {
      if (newPasswordController.text.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Please enter your new password',
        };
      }
      return {
        'success': false,
        'message': _newPasswordError ?? 'Invalid password',
      };
    }
    
    if (!_isConfirmPasswordValid) {
      if (confirmPasswordController.text.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Please confirm your password',
        };
      }
      return {
        'success': false,
        'message': _confirmPasswordError ?? 'Passwords do not match',
      };
    }

    if (_resetToken.isEmpty) {
      return {
        'success': false,
        'message': 'Invalid reset token. Please try again.',
        'navigate_back': true,
      };
    }

    _isLoading = true;
    notifyListeners();

    final newPassword = newPasswordController.text.trim();
    
    debugPrint('\n🔒 RESET PASSWORD INITIATED');
    debugPrint('Email: $_email');
    debugPrint('New Password Length: ${newPassword.length}');

    final client = _createHttpClient();
    final stopwatch = Stopwatch()..start();

    try {
      String requestUrl = '${ApiConfig.baseUrl}/api/admin/reset-password/';
      
      final requestData = {
        'reset_token': _resetToken,
        'new_password': newPassword,
      };

      final requestHeaders = ApiConfig.commonHeaders;

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

      _debugLog('📥 RESET PASSWORD API RESPONSE', {
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
        
        debugPrint('✅ Password reset success status: $isSuccess (HTTP ${response.statusCode})');
        
        if (isSuccess) {
          final successMessage = responseData['message'] ?? 'Password reset successful!';
          debugPrint('🎉 Password reset successful: $successMessage');
          
          return {
            'success': true,
            'message': successMessage,
          };
        } else {
          final errorMessage = responseData['message'] ?? 'Failed to reset password';
          debugPrint('❌ Password reset failed: $errorMessage');
          
          return {
            'success': false,
            'message': errorMessage,
          };
        }
      } else if (response.statusCode == 400) {
        final errorMessage = responseData['message'] ?? 'Invalid request. Please try again.';
        debugPrint('❌ Bad Request (400): $errorMessage');
        
        return {
          'success': false,
          'message': errorMessage,
        };
      } else if (response.statusCode == 401) {
        final errorMessage = responseData['message'] ?? 'Reset token expired. Please request a new one.';
        debugPrint('❌ Unauthorized (401): $errorMessage');
        
        return {
          'success': false,
          'message': errorMessage,
          'navigate_back': true,
        };
      } else if (response.statusCode == 404) {
        final errorMessage = responseData['message'] ?? 'User not found.';
        debugPrint('❌ Not Found (404): $errorMessage');
        
        return {
          'success': false,
          'message': errorMessage,
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
        'message': 'Password reset failed: ${e.toString()}',
      };
    } finally {
      client.close();
      debugPrint('🔒 HTTP client closed');
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
}

// ==================== SCREEN WIDGET ====================
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController, 
        curve: Curves.easeOutBack,
      ),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController, 
        curve: Curves.easeOut,
      ),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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

  Future<void> _handleResetPassword(BuildContext context) async {
    final provider = context.read<ResetPasswordProvider>();
    final result = await provider.resetPassword();

    if (!mounted) return;

    if (result['success'] == true) {
      _showSnackBar(result['message'], AppColors.successGreen);

      // Navigate to login screen after successful password reset
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          debugPrint('🧭 Navigating to: /signup');
          Navigator.pushNamedAndRemoveUntil(
            context, 
            '/signup',
            (route) => false,
          );
        }
      });
    } else {
      _showSnackBar(result['message'], AppColors.errorRed);

      if (result['navigate_back'] == true) {
        // Navigate back to forgot password screen
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/forgot_password');
          }
        });
      }
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
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
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
              child: Consumer<ResetPasswordProvider>(
                builder: (context, provider, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPasswordField(
                        context,
                        title: "New Password",
                        controller: provider.newPasswordController,
                        obscureText: provider.obscureNewPassword,
                        isValid: provider.isNewPasswordValid,
                        errorText: provider.newPasswordError,
                        hintText: "Enter new password",
                        onToggleVisibility: provider.toggleNewPasswordVisibility,
                        onChanged: (_) => provider.validateNewPassword(),
                      ),
                      SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                      _buildPasswordField(
                        context,
                        title: "Confirm Password",
                        controller: provider.confirmPasswordController,
                        obscureText: provider.obscureConfirmPassword,
                        isValid: provider.isConfirmPasswordValid,
                        errorText: provider.confirmPasswordError,
                        hintText: "Re-enter new password",
                        onToggleVisibility: provider.toggleConfirmPasswordVisibility,
                        onChanged: (_) => provider.validateConfirmPassword(),
                      ),
                      SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, isLandscape ? 16 : 24)),
                      _buildContinueButton(context, provider),
                    ],
                  );
                },
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

  Widget _buildContinueButton(BuildContext context, ResetPasswordProvider provider) {
    final fontSize = ResponsiveUtils.getFontSize(context, 16);
    final iconSize = ResponsiveUtils.getFontSize(context, 18);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final buttonHeight = ResponsiveUtils.getButtonHeight(context);
    
    bool isEnabled = provider.isNewPasswordValid && provider.isConfirmPasswordValid;

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
          onPressed: isEnabled && !provider.isLoading ? () => _handleResetPassword(context) : null,
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
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final verticalSpacing = ResponsiveUtils.getVerticalSpacing(context, 40);

    return ChangeNotifierProvider(
      create: (_) => ResetPasswordProvider()..initialize(args),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (isLandscape) {
                    return Row(
                      children: [
                        Flexible(
                          flex: 2,
                          child: _buildHeader(context),
                        ),
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
        ),
      ),
    );
  }
}