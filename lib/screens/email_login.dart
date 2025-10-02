import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:coaching_institute_app/common/continue_button.dart';
import 'email_login_otp.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();
  bool isLoading = false;
  bool isEmailValid = false;
  String? emailError;
  AnimationController? _fadeController;
  AnimationController? _slideController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    emailController.addListener(_validateEmail);
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController!, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController!, curve: Curves.easeOutCubic));
    
    _fadeController?.forward();
    _slideController?.forward();
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
    
    // Email validation regex
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        emailError = 'Enter a valid email address';
        isEmailValid = false;
      });
      return;
    }
    
    // If all validations pass
    setState(() {
      emailError = null;
      isEmailValid = true;
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    emailFocusNode.dispose();
    _fadeController?.dispose();
    _slideController?.dispose();
    super.dispose();
  }

  // Create HTTP client that bypasses SSL verification for ngrok
  http.Client _createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Allow all certificates for development with ngrok
        // WARNING: Only use this for development with ngrok URLs
        return ApiConfig.isDevelopment;
      };
    
    return IOClient(httpClient);
  }

  Future<void> _handleEmailLogin() async {
    // Validate email before proceeding
    _validateEmail();
    
    if (!isEmailValid) {
      if (emailController.text.trim().isEmpty) {
        _showSnackBar('Please enter your email address', AppColors.errorRed);
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    String email = emailController.text.trim();
    
    debugPrint('Starting email login process');
    debugPrint('Email: $email');

    try {
      debugPrint('Making API call for email login');
      debugPrint('Email: $email');
      debugPrint('Using API URL: ${ApiConfig.currentStudentLoginUrl}');
      
      // Create HTTP client using ApiConfig
      final httpClient = ApiConfig.createHttpClient();
      
      final request = await httpClient.postUrl(
        Uri.parse(ApiConfig.currentStudentLoginUrl),
      );
      
      // Set headers using ApiConfig
      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      // Set body with email using 'identifier' as requested
      final body = jsonEncode({
        'identifier': email,
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
        
        // Check for OTP in API response
        if (responseData.containsKey('otp')) {
          debugPrint('🔐 OTP RECEIVED FROM API: ${responseData['otp']}');
          debugPrint('📧 OTP sent to: $email');
          debugPrint('⏰ OTP received at: ${DateTime.now().toLocal()}');
        }
        
        // Check for other possible OTP field names
        if (responseData.containsKey('otp_code')) {
          debugPrint('🔐 OTP CODE RECEIVED: ${responseData['otp_code']}');
        }
        if (responseData.containsKey('verification_code')) {
          debugPrint('🔐 VERIFICATION CODE RECEIVED: ${responseData['verification_code']}');
        }
        
        // Handle different result codes based on your API response
        if (responseData['result'] == 1 || responseData['result'] == 2) {
          bool accountAvailable = responseData['account_available'] ?? false;
          
          debugPrint('Result code: ${responseData['result']}');
          debugPrint('Account available: $accountAvailable');
          
          if (accountAvailable) {
            debugPrint('Account exists - navigating to email OTP verification');
            debugPrint('API Message: ${responseData['message']}');
            
            // Extract OTP from response
            String? receivedOtp;
            if (responseData.containsKey('otp')) {
              receivedOtp = responseData['otp'].toString();
            } else if (responseData.containsKey('otp_code')) {
              receivedOtp = responseData['otp_code'].toString();
            } else if (responseData.containsKey('verification_code')) {
              receivedOtp = responseData['verification_code'].toString();
            }
            
            _navigateToEmailOtpVerification(email, otpFromApi: receivedOtp);
          } else {
            debugPrint('Account not found');
            _showSnackBar('No account is registered with this email address. Please register first.', AppColors.errorRed);
          }
        } else {
          _showSnackBar('Error: ${responseData['message'] ?? 'Unknown error'}', AppColors.errorRed);
        }
      } else if (httpResponse.statusCode == 404) {
        _showSnackBar('API endpoint not found. Please check the URL.', AppColors.errorRed);
      } else if (httpResponse.statusCode >= 500) {
        _showSnackBar('Server error. Please try again later.', AppColors.errorRed);
      } else {
        _showSnackBar('Server error: ${httpResponse.statusCode} - $responseBody', AppColors.errorRed);
      }
      
      httpClient.close();
      
    } on TimeoutException catch (e) {
      _showSnackBar('Request timeout. Please check your connection.', AppColors.errorRed);
      debugPrint('Timeout Error: $e');
    } on FormatException catch (e) {
      _showSnackBar('Invalid response format from server.', AppColors.errorRed);
      debugPrint('JSON Format Error: $e');
    } on Exception catch (e) {
      String errorMessage = 'Network error: ${e.toString()}';
      if (e.toString().contains('SocketException')) {
        errorMessage = 'No internet connection. Please check your network.';
      } else if (e.toString().contains('HandshakeException')) {
        errorMessage = 'SSL/TLS error. Trying alternative connection...';
        _tryHttpFallback(email);
        return;
      }
      _showSnackBar(errorMessage, AppColors.errorRed);
      debugPrint('API Error: $e');
    } catch (e) {
      _showSnackBar('Unexpected error: ${e.toString()}', AppColors.errorRed);
      debugPrint('Unexpected Error: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _tryHttpFallback(String email) async {
    try {
      debugPrint('Trying HTTP fallback for email login...');
      debugPrint('Using fallback API URL: ${ApiConfig.currentStudentLoginUrl}');
      debugPrint('HTTP Fallback - Email: $email');
      
      final response = await http.post(
        Uri.parse(ApiConfig.currentStudentLoginUrl),
        headers: ApiConfig.commonHeaders,
        body: jsonEncode({
          'identifier': email,
        }),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('HTTP Fallback Response status: ${response.statusCode}');
      debugPrint('HTTP Fallback Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        // Check for OTP in HTTP fallback response
        if (responseData.containsKey('otp')) {
          debugPrint('🔐 FALLBACK OTP RECEIVED: ${responseData['otp']}');
          debugPrint('📧 Fallback OTP sent to: $email');
        }
        
        // Handle different result codes based on your API response
        if (responseData['result'] == 1 || responseData['result'] == 2) {
          bool accountAvailable = responseData['account_available'] ?? false;
          
          debugPrint('HTTP Fallback - Result code: ${responseData['result']}');
          debugPrint('HTTP Fallback - Account available: $accountAvailable');
          
          if (accountAvailable) {
            debugPrint('HTTP Fallback - Account exists - navigating to email OTP verification');
            debugPrint('HTTP Fallback - API Message: ${responseData['message']}');
            
            // Extract OTP from fallback response
            String? receivedOtp;
            if (responseData.containsKey('otp')) {
              receivedOtp = responseData['otp'].toString();
            }
            
            _navigateToEmailOtpVerification(email, otpFromApi: receivedOtp);
          } else {
            debugPrint('HTTP Fallback - Account not found');
            _showSnackBar('No account is registered with this email address. Please register first.', AppColors.errorRed);
          }
        } else {
          _showSnackBar('Error: ${responseData['message'] ?? 'Unknown error'}', AppColors.errorRed);
        }
      } else {
        _showSnackBar('Server error: ${response.statusCode}', AppColors.errorRed);
      }
    } catch (e) {
      _showSnackBar('Both HTTPS and HTTP failed. Please check your server.', AppColors.errorRed);
      debugPrint('HTTP Fallback Error: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _navigateToEmailOtpVerification(String email, {String? otpFromApi}) {
    debugPrint('Navigating to email OTP verification screen...');
    debugPrint('Email: $email');
    
    if (otpFromApi != null) {
      debugPrint('🔐🔐🔐 FINAL OTP TO BE USED: $otpFromApi 🔐🔐🔐');
      debugPrint('📋 Copy this OTP for testing: $otpFromApi');
    }
    
    // Show success message
    _showSnackBar('OTP sent! Redirecting to verification...', AppColors.successGreen);
    
    // Add a small delay to let the user see the success message
    Future.delayed(const Duration(milliseconds: 800), () {
      // Try named route first
      try {
        Navigator.pushNamed(
          context, 
          '/email_login_otp',
          arguments: {
            'email': email,
            'identifier': email,
            'login_type': 'email',
            'otp_from_api': otpFromApi,
          },
        ).then((result) {
          debugPrint('Named route navigation successful: $result');
        }).catchError((error) {
          debugPrint('Named route navigation failed: $error');
          _tryDirectEmailOtpNavigation(email, otpFromApi: otpFromApi);
        });
      } catch (e) {
        debugPrint('Named route error: $e');
        _tryDirectEmailOtpNavigation(email, otpFromApi: otpFromApi);
      }
    });
  }

  void _tryDirectEmailOtpNavigation(String email, {String? otpFromApi}) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmailLoginOtpScreen(),
          settings: RouteSettings(
            arguments: {
              'email': email,
              'identifier': email,
              'login_type': 'email',
              'otp_from_api': otpFromApi,
            },
          ),
        ),
      ).then((result) {
        debugPrint('Direct navigation successful: $result');
      }).catchError((error) {
        debugPrint('Direct navigation also failed: $error');
        _showSnackBar('Unable to navigate to OTP screen. Please restart the app.', AppColors.errorRed);
      });
    } catch (e) {
      debugPrint('Direct navigation error: $e');
      _showSnackBar('Navigation system error. Please restart the app.', AppColors.errorRed);
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
          // Back button positioned at top left
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.05),
                    spreadRadius: 0,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  color: AppColors.grey700,
                  size: 20,
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
          
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
            left: 30,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white.withOpacity(0.06),
              ),
            ),
          ),
          
          // Main content - Logo positioned lower in the container
          Positioned(
            left: 0,
            right: 0,
            bottom: screenHeight * 0.08,
            child: _fadeAnimation != null 
              ? FadeTransition(
                  opacity: _fadeAnimation!,
                  child: Image.asset(
                    "assets/images/signature_logo.png",
                    width: screenWidth * 0.20,
                    height: screenWidth * 0.20,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  "assets/images/signature_logo.png",
                  width: screenWidth * 0.20,
                  height: screenWidth * 0.20,
                  fit: BoxFit.contain,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailContainer(double screenWidth) {
    return Container(
      padding: const EdgeInsets.all(20),
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
          // Enhanced section header with icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryYellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.email_outlined,
                  color: AppColors.white,
                  size: screenWidth * 0.040,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Email Address",
                style: TextStyle(
                  fontSize: screenWidth * 0.040,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Enhanced email input with better styling and proper validation display
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
                Row(
                  children: [
                    // Email icon section
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.7),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                        ),
                      ),
                      child: Icon(
                        Icons.email_outlined,
                        color: isEmailValid 
                          ? AppColors.successGreen
                          : emailError != null
                            ? AppColors.errorRed
                            : AppColors.grey500,
                        size: screenWidth * 0.045,
                      ),
                    ),
                    
                    // Divider with better visibility
                    Container(
                      width: 1.5,
                      height: 40,
                      color: AppColors.grey300,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    
                    // Expanded Email input
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        focusNode: emailFocusNode,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey800,
                          letterSpacing: 0.5,
                        ),
                        decoration: InputDecoration(
                          hintText: "Enter your email address",
                          hintStyle: TextStyle(
                            color: AppColors.grey500,
                            fontSize: screenWidth * 0.037,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          suffixIcon: isEmailValid
                            ? Icon(
                                Icons.check_circle,
                                color: AppColors.successGreen,
                                size: screenWidth * 0.05,
                              )
                            : emailError != null
                              ? Icon(
                                  Icons.error,
                                  color: AppColors.errorRed,
                                  size: screenWidth * 0.05,
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _validateEmail();
                          });
                          debugPrint("Email changed: $value");
                        },
                        onSubmitted: (_) => _handleEmailLogin(),
                      ),
                    ),
                  ],
                ),
                
                // Error message display
                if (emailError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.errorRed,
                          size: screenWidth * 0.035,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            emailError!,
                            style: TextStyle(
                              color: AppColors.errorRed,
                              fontSize: screenWidth * 0.032,
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

          // Continue button using the separate class
          ContinueButton(
            isEnabled: isEmailValid,
            isLoading: isLoading,
            onPressed: _handleEmailLogin,
            screenWidth: screenWidth,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginInfo() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.white,
              AppColors.grey50,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryBlue.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.1),
              spreadRadius: 0,
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withOpacity(0.1),
                    AppColors.primaryBlue.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.info_outline,
                color: AppColors.primaryBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Enter your registered email address to continue",
                style: TextStyle(
                  fontSize: screenWidth * 0.032,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      body: SingleChildScrollView(
        child: _slideAnimation != null 
          ? SlideTransition(
              position: _slideAnimation!,
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 25),
                  _buildEmailContainer(MediaQuery.of(context).size.width),
                  _buildLoginInfo(),
                  // Added extra padding at the bottom to prevent overflow
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
                ],
              ),
            )
          : Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 25),
                _buildEmailContainer(MediaQuery.of(context).size.width),
                _buildLoginInfo(),
                // Added extra padding at the bottom to prevent overflow
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
              ],
            ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}