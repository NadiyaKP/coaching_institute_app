import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> 
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  bool isLoading = false;
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  
  // Validation variables
  String? emailError;
  bool isEmailValid = false;

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

  void _validateEmail() {
    final email = emailController.text.trim();
    
    if (email.isEmpty) {
      setState(() {
        emailError = null;
        isEmailValid = false;
      });
      return;
    }
    
    // Basic email validation
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );
    
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        emailError = 'Enter a valid email address';
        isEmailValid = false;
      });
      return;
    }
    
    setState(() {
      emailError = null;
      isEmailValid = true;
    });
  }

  Future<void> _sendResetOTP() async {
    _validateEmail();
    
    if (!isEmailValid) {
      if (emailController.text.trim().isEmpty) {
        _showSnackBar('Please enter your email', AppColors.errorRed);
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    final email = emailController.text.trim();
    
    debugPrint('Sending OTP to email: $email');

    try {
      final httpClient = ApiConfig.createHttpClient();
      
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
          _showSnackBar(
            responseData['message'] ?? 'OTP sent successfully!',
            AppColors.successGreen,
          );
          
          // Navigate to OTP verification page
          Future.delayed(const Duration(milliseconds: 800), () {
            Navigator.pushReplacementNamed(
              context,
              '/forgot_otp_verification',
              arguments: {
                'email': email,
                'otp': responseData['OTP'],
              },
            );
          });
        } else {
          _showSnackBar(
            responseData['message'] ?? 'Failed to send OTP',
            AppColors.errorRed,
          );
        }
      } else if (httpResponse.statusCode == 404) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        _showSnackBar(
          responseData['message'] ?? 'Email not found',
          AppColors.errorRed,
        );
      } else {
        _showSnackBar(
          'Server error: ${httpResponse.statusCode}',
          AppColors.errorRed,
        );
      }
      
      httpClient.close();
      
    } on TimeoutException catch (e) {
      _showSnackBar(
        'Request timeout. Please check your connection.',
        AppColors.errorRed,
      );
      debugPrint('Timeout Error: $e');
    } on FormatException catch (e) {
      _showSnackBar(
        'Invalid response format from server.',
        AppColors.errorRed,
      );
      debugPrint('JSON Format Error: $e');
    } catch (e) {
      String errorMessage = 'Network error: ${e.toString()}';
      if (e.toString().contains('SocketException')) {
        errorMessage = 'No internet connection. Please check your network.';
      }
      _showSnackBar(errorMessage, AppColors.errorRed);
      debugPrint('API Error: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
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
          
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.white,
                size: 22,
              ),
              onPressed: () => Navigator.pop(context),
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
                  "Forgot Password?",
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
                    "Don't worry! Enter your email to reset",
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

  Widget _buildEmailCard() {
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
              // Email label
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryYellow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      color: AppColors.white,
                      size: screenWidth * 0.05,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Email Address",
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
              
              // Email input field
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.grey50,
                      AppColors.grey100,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEmailValid 
                      ? AppColors.successGreen.withOpacity(0.6)
                      : emailError != null
                        ? AppColors.errorRed.withOpacity(0.6)
                        : AppColors.grey300,
                    width: 1.5,
                  ),
                  boxShadow: isEmailValid ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : emailError != null ? [
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
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey800,
                      ),
                      decoration: InputDecoration(
                        hintText: "Enter your registered email",
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
                        suffixIcon: isEmailValid
                          ? Icon(
                              Icons.check_circle,
                              color: AppColors.successGreen,
                              size: screenWidth * 0.055,
                            )
                          : emailError != null
                            ? Icon(
                                Icons.error,
                                color: AppColors.errorRed,
                                size: screenWidth * 0.055,
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        _validateEmail();
                      },
                    ),
                    
                    if (emailError != null)
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
                                emailError!,
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
    bool isEnabled = isEmailValid;
    
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: isEnabled
            ? AppGradients.primaryYellow
            : LinearGradient(
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
        onPressed: isEnabled && !isLoading ? _sendResetOTP : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: isLoading
            ? SizedBox(
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
              _buildEmailCard(),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
            ],
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}