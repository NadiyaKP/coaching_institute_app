import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'dart:io';
import '../screens/settings/ip_config.dart';

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
}

// ============= PROVIDER CLASS =============
class ForgotPasswordProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _emailError;
  bool _isEmailValid = false;

  bool get isLoading => _isLoading;
  String? get emailError => _emailError;
  bool get isEmailValid => _isEmailValid;

  void validateEmail(String email) {
    if (email.isEmpty) {
      _emailError = null;
      _isEmailValid = false;
      notifyListeners();
      return;
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );

    if (!emailRegex.hasMatch(email)) {
      _emailError = 'Enter a valid email address';
      _isEmailValid = false;
    } else {
      _emailError = null;
      _isEmailValid = true;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> sendResetOTP(String email) async {
    if (!_isEmailValid) {
      if (email.trim().isEmpty) {
        return {
          'success': false,
          'message': 'Please enter your email',
        };
      }
      return {
        'success': false,
        'message': _emailError ?? 'Invalid email',
      };
    }

    _isLoading = true;
    notifyListeners();

    debugPrint('Sending OTP to email: $email');

    HttpClient? httpClient;

    try {
      httpClient = ApiConfig.createHttpClient();

      final request = await httpClient.postUrl(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/forget-password/'),
      );

      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final body = jsonEncode({
        'email': email,
      });
      request.contentLength = body.length;
      request.write(body);

      final httpResponse = await request.close().timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      final responseBody = await httpResponse.transform(utf8.decoder).join();

      debugPrint('Response status: ${httpResponse.statusCode}');
      debugPrint('Response body: $responseBody');

      if (httpResponse.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);

        if (responseData['success'] == true) {
          return {
            'success': true,
            'message': responseData['message'] ?? 'OTP sent successfully!',
            'email': email,
            'otp': responseData['OTP'],
          };
        } else {
          return {
            'success': false,
            'message': responseData['message'] ?? 'Failed to send OTP',
          };
        }
      } else if (httpResponse.statusCode == 404) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        return {
          'success': false,
          'message': responseData['message'] ?? 'Email not found',
        };
      } else {
        return {
          'success': false,
          'message': 'Server error: ${httpResponse.statusCode}',
        };
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout Error: $e');
      return {
        'success': false,
        'message': 'Request timeout. Please check your connection.',
      };
    } on FormatException catch (e) {
      debugPrint('JSON Format Error: $e');
      return {
        'success': false,
        'message': 'Invalid response format from server.',
      };
    } catch (e) {
      debugPrint('API Error: $e');
      String errorMessage = 'Network error: ${e.toString()}';
      if (e.toString().contains('SocketException')) {
        errorMessage = 'No internet connection. Please check your network.';
      }
      return {
        'success': false,
        'message': errorMessage,
      };
    } finally {
      httpClient?.close();
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _isLoading = false;
    _emailError = null;
    _isEmailValid = false;
    notifyListeners();
  }
}

// ============= SCREEN CLASS =============
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;

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
    emailController.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _handleSendOTP(BuildContext context) async {
    final provider = Provider.of<ForgotPasswordProvider>(context, listen: false);
    final email = emailController.text.trim();

    final result = await provider.sendResetOTP(email);

    if (!mounted) return;

    if (result['success'] == true) {
      _showSnackBar(
        result['message'] ?? 'OTP sent successfully!',
        AppColors.successGreen,
      );

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/forgot_otp_verification',
            arguments: {
              'email': result['email'],
              'otp': result['otp'],
            },
          );
        }
      });
    } else {
      _showSnackBar(
        result['message'] ?? 'Failed to send OTP',
        AppColors.errorRed,
      );
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

        // Settings button (NEW)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 16,
          child: IconButton(
            icon: Icon(
              Icons.settings,
              color: AppColors.primaryBlue,
              size: ResponsiveUtils.getFontSize(context, 20),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const IpConfigPage(),
                ),
              );
            },
            tooltip: 'IP Configuration',
          ),
        ),

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
                  "Forgot Password?",
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
                    "Don't worry! Enter your email to reset",
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

  Widget _buildEmailCard(BuildContext context) {
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final horizontalPadding = ResponsiveUtils.getHorizontalPadding(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    final containerPadding = EdgeInsets.symmetric(
      horizontal: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 12 : 20),
      vertical: (isTabletDevice && !isLandscape) ? 20 : (isLandscape ? 12 : 16),
    );
    
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: horizontalPadding,
        child: ScaleTransition(
          scale: _scaleAnimation!,
          child: FadeTransition(
            opacity: _fadeAnimation!,
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
              child: Consumer<ForgotPasswordProvider>(
                builder: (context, provider, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEmailField(provider),
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

  Widget _buildEmailField(ForgotPasswordProvider provider) {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    final iconSize = ResponsiveUtils.getFontSize(context, 16);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Email label
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: AppGradients.primaryYellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.email_outlined,
                color: AppColors.white,
                size: iconSize,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Email Address",
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Email input field
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
              color: provider.isEmailValid
                  ? AppColors.successGreen.withOpacity(0.6)
                  : provider.emailError != null
                      ? AppColors.errorRed.withOpacity(0.6)
                      : AppColors.grey300,
              width: 1.5,
            ),
            boxShadow: provider.isEmailValid
                ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : provider.emailError != null
                    ? [
                        BoxShadow(
                          color: AppColors.errorRed.withOpacity(0.1),
                          spreadRadius: 0,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
          ),
          child: Column(
            children: [
              TextField(
                controller: emailController,
                enabled: !provider.isLoading,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey800,
                ),
                decoration: InputDecoration(
                  hintText: "Enter your registered email",
                  hintStyle: TextStyle(
                    color: AppColors.grey500,
                    fontSize: fontSize * 0.95,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: provider.isEmailValid
                      ? Icon(
                          Icons.check_circle,
                          color: AppColors.successGreen,
                          size: iconSize * 1.2,
                        )
                      : provider.emailError != null
                          ? Icon(
                              Icons.error,
                              color: AppColors.errorRed,
                              size: iconSize * 1.2,
                            )
                          : null,
                ),
                onChanged: (value) {
                  provider.validateEmail(value.trim());
                },
              ),

              if (provider.emailError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.errorRed,
                        size: fontSize * 0.9,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          provider.emailError!,
                          style: TextStyle(
                            color: AppColors.errorRed,
                            fontSize: fontSize * 0.85,
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

  Widget _buildContinueButton(BuildContext context, ForgotPasswordProvider provider) {
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
    
    bool isEnabled = provider.isEmailValid;

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
          onPressed: isEnabled && !provider.isLoading
              ? () => _handleSendOTP(context)
              : null,
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
                      size: isLandscape ? fontSize * 0.95 : fontSize * 1.1,
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
    
    return ChangeNotifierProvider(
      create: (_) => ForgotPasswordProvider(),
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
                                child: _buildEmailCard(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHeader(context),
                        SizedBox(height: verticalSpacing),
                        _buildEmailCard(context),
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