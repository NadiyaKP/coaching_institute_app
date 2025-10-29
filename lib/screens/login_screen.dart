import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'dart:io';

// ============= PROVIDER CLASS =============
class LoginProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;
  
  // Email suggestions
  List<String> _savedEmails = [];
  List<String> _filteredEmails = [];
  bool _showSuggestions = false;

  bool get isLoading => _isLoading;
  bool get obscurePassword => _obscurePassword;
  String? get emailError => _emailError;
  String? get passwordError => _passwordError;
  bool get isEmailValid => _isEmailValid;
  bool get isPasswordValid => _isPasswordValid;
  List<String> get filteredEmails => _filteredEmails;
  bool get showSuggestions => _showSuggestions;

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  void setEmailError(String? error) {
    _emailError = error;
    notifyListeners();
  }

  void setPasswordError(String? error) {
    _passwordError = error;
    notifyListeners();
  }

  void setEmailValid(bool valid) {
    _isEmailValid = valid;
    notifyListeners();
  }

  void setPasswordValid(bool valid) {
    _isPasswordValid = valid;
    notifyListeners();
  }

  void setShowSuggestions(bool show) {
    _showSuggestions = show;
    notifyListeners();
  }

  void setFilteredEmails(List<String> emails) {
    _filteredEmails = emails;
    notifyListeners();
  }

  Future<void> loadSavedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    _savedEmails = prefs.getStringList('saved_emails') ?? [];
    notifyListeners();
  }

  Future<void> saveEmail(String email) async {
    if (!_savedEmails.contains(email)) {
      _savedEmails.insert(0, email);
      if (_savedEmails.length > 5) {
        _savedEmails = _savedEmails.sublist(0, 5);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_emails', _savedEmails);
    }
  }

  void filterEmails(String query) {
    if (query.isEmpty) {
      _filteredEmails = [];
      _showSuggestions = false;
    } else {
      _filteredEmails = _savedEmails
          .where((email) => email.toLowerCase().contains(query.toLowerCase()))
          .toList();
      _showSuggestions = _filteredEmails.isNotEmpty;
    }
    notifyListeners();
  }

  void validateEmail(String email) {
    final trimmedEmail = email.trim();
    
    if (trimmedEmail.isEmpty) {
      _emailError = null;
      _isEmailValid = false;
      notifyListeners();
      return;
    }
    
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    
    if (!emailRegex.hasMatch(trimmedEmail)) {
      _emailError = 'Enter a valid email address';
      _isEmailValid = false;
    } else {
      _emailError = null;
      _isEmailValid = true;
    }
    notifyListeners();
  }

  void validatePassword(String password) {
    if (password.isEmpty) {
      _passwordError = null;
      _isPasswordValid = false;
      notifyListeners();
      return;
    }
    
    if (password.length < 4) {
      _passwordError = 'Password must be at least 4 characters';
      _isPasswordValid = false;
    } else {
      _passwordError = null;
      _isPasswordValid = true;
    }
    notifyListeners();
  }

 Future<Map<String, dynamic>?> loginUser({
  required String email,
  required String password,
}) async {
  _isLoading = true;
  notifyListeners();

  final username = email.trim();
  
  debugPrint('Login attempt with username: $username');

  HttpClient? httpClient;

  try {
    httpClient = ApiConfig.createHttpClient();
    
    final request = await httpClient.postUrl(
      Uri.parse('${ApiConfig.baseUrl}/api/students/student_login/'),
    );
    
    ApiConfig.commonHeaders.forEach((key, value) {
      request.headers.set(key, value);
    });
    
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
        await saveEmail(username);
        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setString('accessToken', responseData['access'] ?? '');
        await prefs.setString('studentType', responseData['student_type'] ?? '');
        await prefs.setString('phoneNumber', responseData['phone_number'] ?? '');
        await prefs.setBool('profileCompleted', responseData['profile_completed'] ?? false);
        await prefs.setString('username', username);
        
        debugPrint('Verification - Stored accessToken: ${prefs.getString('accessToken')}');
        debugPrint('Verification - Stored studentType: ${prefs.getString('studentType')}');
        
        return {
          'success': true,
          'message': 'Login successful!',
          'profile_completed': responseData['profile_completed'] ?? false,
          'response_data': responseData,
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Invalid credentials',
        };
      }
    } else if (httpResponse.statusCode == 401) {
      return {
        'success': false,
        'message': 'Invalid email or password',
      };
    } else if (httpResponse.statusCode == 404) {
      return {
        'success': false,
        'message': 'API endpoint not found',
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
    String errorMessage = 'Network error: ${e.toString()}';
    if (e.toString().contains('SocketException')) {
      errorMessage = 'No internet connection. Please check your network.';
    }
    debugPrint('API Error: $e');
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
}
// ============= SCREEN CLASS =============
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  
  // Create the provider instance here
  late final LoginProvider _loginProvider;
  
  AnimationController? _fadeController;
  AnimationController? _slideController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;
  
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    
    // Initialize provider
    _loginProvider = LoginProvider();
    
    _initializeAnimations();
    
    // Load saved emails
    _loginProvider.loadSavedEmails();
    
    emailController.addListener(_onEmailChanged);
    passwordController.addListener(_onPasswordChanged);
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

  void _onEmailChanged() {
    _loginProvider.validateEmail(emailController.text);
    _loginProvider.filterEmails(emailController.text);
  }

  void _onPasswordChanged() {
    _loginProvider.validatePassword(passwordController.text);
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
          offset: const Offset(40, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _loginProvider.filteredEmails.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      emailController.text = _loginProvider.filteredEmails[index];
                      _removeOverlay();
                      _loginProvider.setShowSuggestions(false);
                      _loginProvider.validateEmail(emailController.text);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[200]!,
                            width: index < _loginProvider.filteredEmails.length - 1 ? 1 : 0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            color: AppColors.primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _loginProvider.filteredEmails[index],
                              style: const TextStyle(
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
    _loginProvider.dispose(); 
    super.dispose();
  }

  Future<void> _loginUser() async {
    debugPrint('=== _loginUser CALLED ===');
    
    _loginProvider.validateEmail(emailController.text);
    _loginProvider.validatePassword(passwordController.text);
    
    debugPrint('Email valid: ${_loginProvider.isEmailValid}');
    debugPrint('Password valid: ${_loginProvider.isPasswordValid}');
    
    if (!_loginProvider.isEmailValid || !_loginProvider.isPasswordValid) {
      debugPrint('Validation failed - showing error');
      if (emailController.text.trim().isEmpty) {
        _showSnackBar('Please enter your email', AppColors.errorRed);
      } else if (passwordController.text.isEmpty) {
        _showSnackBar('Please enter your password', AppColors.errorRed);
      }
      return;
    }

    debugPrint('Calling provider.loginUser...');
    
    final result = await _loginProvider.loginUser(
      email: emailController.text,
      password: passwordController.text,
    );

    debugPrint('Result received: $result');

    if (!mounted) {
      debugPrint('Widget not mounted, returning');
      return;
    }

    if (result != null && result['success'] == true) {
      debugPrint('Login SUCCESS - showing snackbar');
      _showSnackBar(result['message'] ?? 'Login successful!', AppColors.successGreen);
      
      debugPrint('Scheduling navigation after 800ms delay...');
      debugPrint('Profile completed: ${result['profile_completed']}');
      
      // Navigate based on profile completion status
      Future.delayed(const Duration(milliseconds: 800), () {
        debugPrint('Delay completed, checking mounted state...');
        if (!mounted) {
          debugPrint('Widget not mounted after delay, returning');
          return;
        }
        
        debugPrint('Attempting navigation...');
        
        if (result['profile_completed'] == false) {
          debugPrint('Navigating to /profile_completion_page');
          Navigator.pushReplacementNamed(
            context, 
            '/profile_completion_page',
            arguments: result['response_data'],
          );
        } else {
          debugPrint('Navigating to /home');
          Navigator.pushReplacementNamed(
            context, 
            '/home',
            arguments: result['response_data'],
          );
        }
      });
    } else {
      debugPrint('Login FAILED');
      _showSnackBar(
        result?['message'] ?? 'Login failed',
        AppColors.errorRed,
      );
    }
    
    debugPrint('=== _loginUser COMPLETED ===');
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
      child: ListenableBuilder(
        listenable: _loginProvider,
        builder: (context, child) {
          // Show overlay when suggestions are available
          if (_loginProvider.showSuggestions && _overlayEntry == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
          } else if (!_loginProvider.showSuggestions && _overlayEntry != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _removeOverlay());
          }

          return Container(
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
                      color: _loginProvider.isEmailValid 
                        ? AppColors.successGreen.withOpacity(0.6)
                        : _loginProvider.emailError != null
                          ? AppColors.errorRed.withOpacity(0.6)
                          : AppColors.grey300,
                      width: 1.5,
                    ),
                    boxShadow: _loginProvider.isEmailValid ? [
                      BoxShadow(
                        color: AppColors.successGreen.withOpacity(0.1),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ] : _loginProvider.emailError != null ? [
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
                          suffixIcon: _loginProvider.isEmailValid
                            ? Icon(
                                Icons.check_circle,
                                color: AppColors.successGreen,
                                size: screenWidth * 0.05,
                              )
                            : _loginProvider.emailError != null
                              ? Icon(
                                  Icons.error,
                                  color: AppColors.errorRed,
                                  size: screenWidth * 0.05,
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          _loginProvider.validateEmail(value);
                          _loginProvider.filterEmails(value);
                        },
                        onTap: () {
                          if (emailController.text.isNotEmpty) {
                            _loginProvider.filterEmails(emailController.text);
                          }
                        },
                      ),
                      
                      if (_loginProvider.emailError != null)
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
                                  _loginProvider.emailError!,
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
                      color: _loginProvider.isPasswordValid 
                        ? AppColors.successGreen.withOpacity(0.6)
                        : _loginProvider.passwordError != null
                          ? AppColors.errorRed.withOpacity(0.6)
                          : AppColors.grey300,
                      width: 1.5,
                    ),
                    boxShadow: _loginProvider.isPasswordValid ? [
                      BoxShadow(
                        color: AppColors.successGreen.withOpacity(0.1),
                        spreadRadius: 0,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ] : _loginProvider.passwordError != null ? [
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
                        obscureText: _loginProvider.obscurePassword,
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
                              _loginProvider.obscurePassword 
                                ? Icons.visibility_off_outlined 
                                : Icons.visibility_outlined,
                              color: AppColors.grey600,
                              size: screenWidth * 0.05,
                            ),
                            onPressed: _loginProvider.togglePasswordVisibility,
                          ),
                        ),
                        onChanged: (value) {
                          _loginProvider.validatePassword(value);
                        },
                      ),
                      
                      if (_loginProvider.passwordError != null)
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
                                  _loginProvider.passwordError!,
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
                    onPressed: _loginProvider.isLoading ? null : _navigateToForgotPassword,
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
          );
        },
      ),
    );
  }

  Widget _buildSignupOption() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return ListenableBuilder(
      listenable: _loginProvider,
      builder: (context, child) {
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
                onTap: _loginProvider.isLoading ? null : _navigateToSignup,
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
      },
    );
  }

  Widget _buildLoginButton(double screenWidth) {
    bool isEnabled = _loginProvider.isEmailValid && _loginProvider.isPasswordValid;
    
    debugPrint('Login button build - isEnabled: $isEnabled, isLoading: ${_loginProvider.isLoading}');
    
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
        onPressed: isEnabled && !_loginProvider.isLoading 
          ? () {
              debugPrint('LOGIN BUTTON PRESSED!');
              _loginUser();
            }
          : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: _loginProvider.isLoading
            ? const SizedBox(
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