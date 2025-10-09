import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:coaching_institute_app/common/continue_button.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool obscurePassword = true;
  AnimationController? _fadeController;
  AnimationController? _slideController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;
  
  // Validation variables
  String? emailError;
  String? passwordError;
  bool isEmailValid = false;
  bool isPasswordValid = false;
  
  // Email suggestions
  List<String> savedEmails = [];
  List<String> filteredEmails = [];
  bool showSuggestions = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadSavedEmails();
    emailController.addListener(_validateEmail);
    passwordController.addListener(_validatePassword);
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

  Future<void> _loadSavedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      savedEmails = prefs.getStringList('saved_emails') ?? [];
    });
  }

  Future<void> _saveEmail(String email) async {
    if (!savedEmails.contains(email)) {
      savedEmails.insert(0, email);
      if (savedEmails.length > 5) {
        savedEmails = savedEmails.sublist(0, 5); // Keep only last 5 emails
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_emails', savedEmails);
    }
  }

  void _filterEmails(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredEmails = [];
        showSuggestions = false;
      });
      _removeOverlay();
      return;
    }

    setState(() {
      filteredEmails = savedEmails
          .where((email) => email.toLowerCase().contains(query.toLowerCase()))
          .toList();
      showSuggestions = filteredEmails.isNotEmpty;
    });

    if (showSuggestions) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width - 80,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(40, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: filteredEmails.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      emailController.text = filteredEmails[index];
                      _removeOverlay();
                      setState(() {
                        showSuggestions = false;
                      });
                      _validateEmail();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[200]!,
                            width: index < filteredEmails.length - 1 ? 1 : 0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.email_outlined,
                            color: AppColors.primaryBlue,
                            size: 18,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              filteredEmails[index],
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.grey800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _fadeController?.dispose();
    _slideController?.dispose();
    _removeOverlay();
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

  void _validatePassword() {
    final password = passwordController.text;
    
    if (password.isEmpty) {
      setState(() {
        passwordError = null;
        isPasswordValid = false;
      });
      return;
    }
    
    // Changed minimum password length to 4
    if (password.length < 4) {
      setState(() {
        passwordError = 'Password must be at least 4 characters';
        isPasswordValid = false;
      });
      return;
    }
    
    setState(() {
      passwordError = null;
      isPasswordValid = true;
    });
  }

  Future<void> loginUser() async {
    _validateEmail();
    _validatePassword();
    
    if (!isEmailValid || !isPasswordValid) {
      if (emailController.text.trim().isEmpty) {
        _showSnackBar('Please enter your email', AppColors.errorRed);
      } else if (passwordController.text.isEmpty) {
        _showSnackBar('Please enter your password', AppColors.errorRed);
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    final username = emailController.text.trim();
    final password = passwordController.text;
    
    debugPrint('Login attempt with username: $username');

    try {
      final httpClient = ApiConfig.createHttpClient();
      
      // Updated API endpoint
      final request = await httpClient.postUrl(
        Uri.parse('${ApiConfig.baseUrl}/api/students/student_login/'),
      );
      
      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      // Updated request body with username instead of email
      final body = jsonEncode({
        'username': username,
        'password': password,
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
    // Save user data
    await _saveEmail(username);
    final prefs = await SharedPreferences.getInstance();
    
    // Store access token (changed to camelCase)
    await prefs.setString('accessToken', responseData['access'] ?? '');
    
    // Store student type (changed to camelCase)
    await prefs.setString('studentType', responseData['student_type'] ?? '');
    
    // Store phone number (changed to camelCase)
    await prefs.setString('phoneNumber', responseData['phone_number'] ?? '');
    
    // Store profile completion status (changed to camelCase)
    await prefs.setBool('profileCompleted', responseData['profile_completed'] ?? false);
    
    // Optional: Store username for future reference
    await prefs.setString('username', username);
    
    debugPrint('Verification - Stored accessToken: ${prefs.getString('accessToken')}');
    debugPrint('Verification - Stored studentType: ${prefs.getString('studentType')}');
    
    _showSnackBar('Login successful!', AppColors.successGreen);
    
    // Navigate based on profile completion status
    Future.delayed(const Duration(milliseconds: 800), () {
      if (responseData['profile_completed'] == false) {
        Navigator.pushReplacementNamed(
          context, 
          '/profile_completion_page',
          arguments: responseData,
        );
      } else {
        Navigator.pushReplacementNamed(
          context, 
          '/home',
          arguments: responseData,
        );
      }
    });
  } else {
    _showSnackBar(
      responseData['message'] ?? 'Invalid credentials',
      AppColors.errorRed,
    );
  }



      } else if (httpResponse.statusCode == 401) {
        _showSnackBar('Invalid email or password', AppColors.errorRed);
      } else if (httpResponse.statusCode == 404) {
        _showSnackBar('API endpoint not found', AppColors.errorRed);
      } else {
        _showSnackBar('Server error: ${httpResponse.statusCode}', AppColors.errorRed);
      }
      
      httpClient.close();
      
    } on TimeoutException catch (e) {
      _showSnackBar('Request timeout. Please check your connection.', AppColors.errorRed);
      debugPrint('Timeout Error: $e');
    } on FormatException catch (e) {
      _showSnackBar('Invalid response format from server.', AppColors.errorRed);
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

  void _navigateToSignup() {
    debugPrint('Navigating to signup screen...');
    _removeOverlay();
    
    try {
      Navigator.pushNamed(context, '/account_creation').then((result) {
        debugPrint('Signup navigation successful: $result');
      }).catchError((error) {
        debugPrint('Signup navigation failed: $error');
        _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
      });
    } catch (e) {
      debugPrint('Navigation error: $e');
      _showSnackBar('Navigation system error. Please restart the app.', AppColors.errorRed);
    }
  }

  void _navigateToForgotPassword() {
    debugPrint('Navigating to forgot password screen...');
    _removeOverlay();
    
    try {
      Navigator.pushNamed(context, '/forgot_password').then((result) {
        debugPrint('Forgot password navigation successful: $result');
      }).catchError((error) {
        debugPrint('Forgot password navigation failed: $error');
        _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
      });
    } catch (e) {
      debugPrint('Navigation error: $e');
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
          
          // Main content - Logo
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

  Widget _buildLoginContainer(double screenWidth) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
            // Email field
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
                    size: screenWidth * 0.038,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Email",
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
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
                      hintText: "Enter your email",
                      hintStyle: TextStyle(
                        color: AppColors.grey500,
                        fontSize: screenWidth * 0.037,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
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
                      _validateEmail();
                      _filterEmails(value);
                    },
                    onTap: () {
                      if (emailController.text.isNotEmpty) {
                        _filterEmails(emailController.text);
                      }
                    },
                  ),
                  
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
            
            const SizedBox(height: 18),
            
            // Password field
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: AppGradients.primaryYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    color: AppColors.white,
                    size: screenWidth * 0.038,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Password",
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
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
                  color: isPasswordValid 
                    ? AppColors.successGreen.withOpacity(0.6)
                    : passwordError != null
                      ? AppColors.errorRed.withOpacity(0.6)
                      : AppColors.grey300,
                  width: 1.5,
                ),
                boxShadow: isPasswordValid ? [
                  BoxShadow(
                    color: AppColors.successGreen.withOpacity(0.1),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ] : passwordError != null ? [
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
                    controller: passwordController,
                    obscureText: obscurePassword,
                    style: TextStyle(
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey800,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter your password",
                      hintStyle: TextStyle(
                        color: AppColors.grey500,
                        fontSize: screenWidth * 0.037,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword 
                            ? Icons.visibility_off_outlined 
                            : Icons.visibility_outlined,
                          color: AppColors.grey600,
                          size: screenWidth * 0.05,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      _validatePassword();
                    },
                  ),
                  
                  if (passwordError != null)
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
                              passwordError!,
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
            
            const SizedBox(height: 12),

            // Forgot Password Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _navigateToForgotPassword,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  "Forgot Password?",
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),

            // Login button
            _buildLoginButton(screenWidth),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupOption() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Don't have an account? ",
            style: TextStyle(
              fontSize: screenWidth * 0.037,
              color: AppColors.grey600,
              fontWeight: FontWeight.w400,
            ),
          ),
          GestureDetector(
            onTap: _navigateToSignup,
            child: Text(
              "Sign Up",
              style: TextStyle(
                fontSize: screenWidth * 0.037,
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(double screenWidth) {
    bool isEnabled = isEmailValid && isPasswordValid;
    
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
        onPressed: isEnabled && !isLoading ? loginUser : null,
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
            : Text(
                "Login",
                style: TextStyle(
                  fontSize: screenWidth * 0.042,
                  fontWeight: FontWeight.w700,
                  color: isEnabled ? AppColors.white : AppColors.grey600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _removeOverlay();
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 25),
              _buildLoginContainer(MediaQuery.of(context).size.width),
              _buildSignupOption(),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
            ],
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}