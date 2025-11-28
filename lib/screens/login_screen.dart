import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'dart:io';
import '../screens/explore_student/explore.dart';
import '../../../service/http_interceptor.dart';

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
      return height * 0.25; 
    }
    return height * 0.35; 
  }

 static double getLogoSize(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;
  final isTabletDevice = isTablet(context);
  final isLandscapeMode = isLandscape(context);
  
  
  if (!isLandscapeMode) {
    if (isTabletDevice) {
      return screenWidth * 0.25;
    } else {
      return screenWidth * 0.22; 
    }
  }
  
  
  if (isTabletDevice) {
    
    return screenHeight * 0.15; 
  } else {
    
    return screenHeight * 0.12;
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
class LoginProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;
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

  void setShowSuggestions(bool show) {
    _showSuggestions = show;
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
  
  debugPrint('=== LOGIN REQUEST ===');
  debugPrint('Login attempt with username: $username');

  try {
    
    final apiUrl = '${ApiConfig.baseUrl}/api/students/student_login/';
    
    debugPrint('URL: $apiUrl');
    debugPrint('Method: POST');
    
    final response = await globalHttpClient.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        ...ApiConfig.commonHeaders,
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    ).timeout(
      ApiConfig.requestTimeout,
      onTimeout: () {
        throw TimeoutException('Request timeout');
      },
    );
    
    debugPrint('=== LOGIN RESPONSE ===');
    debugPrint('Response status: ${response.statusCode}');
    debugPrint('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      
      if (responseData['success'] == true) {
        await saveEmail(username);
        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setString('accessToken', responseData['access'] ?? '');
        await prefs.setString('studentType', responseData['student_type'] ?? '');
        await prefs.setString('phoneNumber', responseData['phone_number'] ?? '');
        await prefs.setBool('profileCompleted', responseData['profile_completed'] ?? false);
        await prefs.setString('username', username);
        
        debugPrint('=== STORED IN SHARED PREFERENCES ===');
        debugPrint('Stored accessToken: ${prefs.getString('accessToken')}');
        debugPrint('Stored studentType: ${prefs.getString('studentType')}');
        debugPrint('Stored phoneNumber: ${prefs.getString('phoneNumber')}');
        debugPrint('Stored profileCompleted: ${prefs.getBool('profileCompleted')}');
        debugPrint('Stored username: ${prefs.getString('username')}');
        
        return {
          'success': true,
          'message': 'Login successful!',
          'profile_completed': responseData['profile_completed'] ?? false,
          'response_data': responseData,
        };
      } else {
        debugPrint('Login failed: ${responseData['message']}');
        return {
          'success': false,
          'message': responseData['message'] ?? 'Invalid credentials',
        };
      }
    } else if (response.statusCode == 401) {
      debugPrint('Authentication failed: 401 Unauthorized');
      return {
        'success': false,
        'message': 'Invalid email or password',
      };
    } else if (response.statusCode == 404) {
      debugPrint('API endpoint not found: 404');
      return {
        'success': false,
        'message': 'API endpoint not found',
      };
    } else {
      debugPrint('Server error: ${response.statusCode}');
      return {
        'success': false,
        'message': 'Server error: ${response.statusCode}',
      };
    }
    
  } on TimeoutException catch (e) {
    debugPrint('Timeout Error: $e');
    return {
      'success': false,
      'message': 'Request timeout. Please check your connection.',
    };
  } on http.ClientException catch (e) {
    debugPrint('ClientException: $e');
    
    return {
      'success': false,
      'message': e.message,
    };
  } on SocketException catch (e) {
    debugPrint('SocketException: $e');
    return {
      'success': false,
      'message': 'No internet connection. Please check your network.',
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
    debugPrint('Error Stack Trace: ${StackTrace.current}');
    return {
      'success': false,
      'message': errorMessage,
    };
  } finally {
    _isLoading = false;
    notifyListeners();
    debugPrint('=== LOGIN REQUEST COMPLETED ===');
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
    _loginProvider = LoginProvider();
    _initializeAnimations();
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
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final overlayWidth = maxWidth == double.infinity 
        ? size.width - 80 
        : maxWidth - 40;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: overlayWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(
            ResponsiveUtils.isTablet(context) || ResponsiveUtils.isLandscape(context) 
                ? 20 
                : 40, 
            60
          ),
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
                              style: TextStyle(
                                fontSize: ResponsiveUtils.getFontSize(context, 14),
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
    _loginProvider.validateEmail(emailController.text);
    _loginProvider.validatePassword(passwordController.text);
    
    if (!_loginProvider.isEmailValid || !_loginProvider.isPasswordValid) {
      if (emailController.text.trim().isEmpty) {
        _showSnackBar('Please enter your email', AppColors.errorRed);
      } else if (passwordController.text.isEmpty) {
        _showSnackBar('Please enter your password', AppColors.errorRed);
      }
      return;
    }

    final result = await _loginProvider.loginUser(
      email: emailController.text,
      password: passwordController.text,
    );

    if (!mounted) return;

    if (result != null && result['success'] == true) {
      _showSnackBar(result['message'] ?? 'Login successful!', AppColors.successGreen);
      
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        
        if (result['profile_completed'] == false) {
          Navigator.pushReplacementNamed(
            context,
            '/profile_completion_page',
            arguments: result['response_data'],
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            '/home',
            arguments: result['response_data'],
          );
        }
      });
    } else {
      // Check if the error is "Server error: 400"
      final errorMessage = result?['message'] ?? 'Login failed';
      
      if (errorMessage == 'Server error: 400') {
        _showSnackBar(
          'Make sure your location is turned on and also allow location access to the app.',
          AppColors.errorRed,
        );
      } else {
        _showSnackBar(
          errorMessage,
          AppColors.errorRed,
        );
      }
    }
  }

  void _navigateToSignup() {
    _removeOverlay();
    Navigator.pushNamed(context, '/account_creation').catchError((error) {
      _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
    });
  }

  void _navigateToForgotPassword() {
    _removeOverlay();
    Navigator.pushNamed(context, '/forgot_password').catchError((error) {
      _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
    });
  }

 void _navigateToExplore() {
  _removeOverlay();
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const ExploreScreen()),
  ).catchError((error) {
    _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
  });
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
  final isLandscape = ResponsiveUtils.isLandscape(context);
  final isTabletDevice = ResponsiveUtils.isTablet(context);
  
  final headerHeight = isLandscape ? screenHeight * 0.25 : screenHeight * 0.35;
  
  double logoSize;
  if (!isLandscape) {
    if (isTabletDevice) {
      logoSize = screenWidth * 0.25; 
    } else {
      logoSize = screenWidth * 0.22; 
    }
  } else {
    if (isTabletDevice) {
      logoSize = screenWidth * 0.06; 
    } else {
      logoSize = screenWidth * 0.08; 
    }
  }
  
  double logoBottomPosition;
  if (isLandscape) {
    logoBottomPosition = headerHeight * 0.20;
  } else {
    logoBottomPosition = screenHeight * 0.08; 
  }
  
  return Container(
    width: double.infinity,
    height: headerHeight,
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
        
        // Explore Button 
        if (!isLandscape)
          Positioned(
            top: 16,
            right: 16,
            child: _fadeAnimation != null
                ? FadeTransition(
                    opacity: _fadeAnimation!,
                    child: _buildExploreButton(),
                  )
                : _buildExploreButton(),
          ),
        
        // Logo
        Positioned(
          left: 0,
          right: 0,
          bottom: logoBottomPosition, 
          child: _fadeAnimation != null
              ? FadeTransition(
                  opacity: _fadeAnimation!,
                  child: Image.asset(
                    "assets/images/signature_logo.png",
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  "assets/images/signature_logo.png",
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
        ),
      ],
    ),
  );
}

Widget _buildExploreButton() {
  final fontSize = ResponsiveUtils.getFontSize(context, 13);
  final isLandscape = ResponsiveUtils.isLandscape(context);
  final isTabletDevice = ResponsiveUtils.isTablet(context);
  
  double horizontalPadding;
  double verticalPadding;
  
  if (isLandscape) {
    horizontalPadding = 12;
    verticalPadding = 6;
  } else if (isTabletDevice) {
    horizontalPadding = 16;
    verticalPadding = 8;
  } else {
    horizontalPadding = 14;
    verticalPadding = 7;
  }
  
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _loginProvider.isLoading ? null : _navigateToExplore,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.3),
              spreadRadius: 0,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.explore_outlined,
              color: AppColors.white,
              size: fontSize * 1.1,
            ),
            const SizedBox(width: 6),
            Text(
              "Explore",
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  Widget _buildLoginContainer() {
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final horizontalPadding = ResponsiveUtils.getHorizontalPadding(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    // Adjust container padding based on orientation
    final containerPadding = EdgeInsets.symmetric(
      horizontal: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 16 : 20),
      vertical: (isTabletDevice && !isLandscape) ? 20 : (isLandscape ? 12 : 16),
    );
    
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: horizontalPadding,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: ListenableBuilder(
            listenable: _loginProvider,
            builder: (context, child) {
              if (_loginProvider.showSuggestions && _overlayEntry == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
              } else if (!_loginProvider.showSuggestions && _overlayEntry != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _removeOverlay());
              }

              return Container(
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
                    _buildEmailField(),
                    SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 18)),
                    _buildPasswordField(),
                    SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 12)),
                    _buildForgotPasswordButton(),
                    SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 12)),
                    _buildLoginButton(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    final iconSize = ResponsiveUtils.getFontSize(context, 16);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              "Email",
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
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.grey50, AppColors.grey100],
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
            boxShadow: _loginProvider.isEmailValid
                ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : _loginProvider.emailError != null
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
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey800,
                ),
                decoration: InputDecoration(
                  hintText: "Enter your email",
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
                  suffixIcon: _loginProvider.isEmailValid
                      ? Icon(
                          Icons.check_circle,
                          color: AppColors.successGreen,
                          size: iconSize * 1.2,
                        )
                      : _loginProvider.emailError != null
                          ? Icon(
                              Icons.error,
                              color: AppColors.errorRed,
                              size: iconSize * 1.2,
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
                        size: fontSize * 0.9,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _loginProvider.emailError!,
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

  Widget _buildPasswordField() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    final iconSize = ResponsiveUtils.getFontSize(context, 16);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                size: iconSize,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Password",
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
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.grey50, AppColors.grey100],
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
            boxShadow: _loginProvider.isPasswordValid
                ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : _loginProvider.passwordError != null
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
                controller: passwordController,
                obscureText: _loginProvider.obscurePassword,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey800,
                ),
                decoration: InputDecoration(
                  hintText: "Enter your password",
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
                  suffixIcon: IconButton(
                    icon: Icon(
                      _loginProvider.obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.grey600,
                      size: iconSize * 1.2,
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
                        size: fontSize * 0.9,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _loginProvider.passwordError!,
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

  Widget _buildForgotPasswordButton() {
    final fontSize = ResponsiveUtils.getFontSize(context, 13);
    
    return Align(
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
            fontSize: fontSize,
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    final fontSize = ResponsiveUtils.getFontSize(context, 16);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    double buttonHeight;
    if (isLandscape) {
      buttonHeight = 48.0; 
    } else if (isTabletDevice) {
      buttonHeight = 60.0;
    } else {
      buttonHeight = 56.0;
    }
    
    final isEnabled = _loginProvider.isEmailValid && _loginProvider.isPasswordValid;
    
    return Container(
      width: double.infinity,
      height: buttonHeight,
      decoration: BoxDecoration(
        gradient: isEnabled
            ? AppGradients.primaryYellow
            : const LinearGradient(
                colors: [AppColors.grey300, AppColors.grey400],
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
        onPressed: isEnabled && !_loginProvider.isLoading ? _loginUser : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: _loginProvider.isLoading
            ? SizedBox(
                height: isLandscape ? 20 : 24,
                width: isLandscape ? 20 : 24,
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                "Login",
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: isEnabled ? AppColors.white : AppColors.grey600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildSignupOption() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    
    return ListenableBuilder(
      listenable: _loginProvider,
      builder: (context, child) {
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: ResponsiveUtils.getVerticalSpacing(context, 20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  "Don't have an account? ",
                  style: TextStyle(
                    fontSize: fontSize,
                    color: AppColors.grey600,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _loginProvider.isLoading ? null : _navigateToSignup,
                child: Text(
                  "Sign Up",
                  style: TextStyle(
                    fontSize: fontSize,
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

  @override
  Widget build(BuildContext context) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final verticalSpacing = ResponsiveUtils.getVerticalSpacing(context, 25);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _removeOverlay();
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (isLandscape) {
                // Landscape layout - side by side
                return Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildHeader(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: ResponsiveUtils.getMaxContainerWidth(context),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLoginContainer(),
                                _buildSignupOption(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              
              // Portrait layout 
              return SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(),
                    SizedBox(height: verticalSpacing),
                    _buildLoginContainer(),
                    _buildSignupOption(),
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