import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'login_screen.dart';
import '../service/auth_service.dart';
import 'home.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

// ============= PROVIDER CLASS =============
class SplashProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLoggedIn = false;
  bool _hasValidTokens = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _isLoggedIn;
  bool get hasValidTokens => _hasValidTokens;

  Future<void> checkAuthAndNavigate(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Add a small delay for the splash screen to be visible
      await Future.delayed(const Duration(seconds: 3));

      print('=== SPLASH SCREEN: Printing SharedPreferences data ===');
      await _authService.debugPrintAllData();

      // Check authentication status
      _isLoggedIn = await _authService.isLoggedIn();
      print('=== AUTHENTICATION STATUS ===');
      print('Is Logged In: $_isLoggedIn');

      // Optional: Also check token validity if needed
      try {
        _hasValidTokens = await _authService.hasValidTokens();
        print('Has Valid Tokens: $_hasValidTokens');
      } catch (e) {
        print('Error checking tokens: $e');
        _hasValidTokens = false;
      }
      
      print('===============================');

      _isLoading = false;
      notifyListeners();

      // Navigate based on authentication status
      if (_isLoggedIn) {
        print('✅ User is authenticated - Navigating to HomeScreen');
        _navigateToHome(context);
      } else {
        print('❌ User is not authenticated - Navigating to SignupScreen');
        _navigateToLogin(context);
      }
    } catch (e) {
      print('=== ERROR IN SPLASH SCREEN ===');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $e');
      print('Falling back to SignupScreen');
      print('===============================');
      
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();

      _navigateToLogin(context);
    }
  }

  void _navigateToHome(BuildContext context) {
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  void _navigateToLogin(BuildContext context) {
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}

// ============= SCREEN CLASS =============
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Start auth check directly without provider
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    final authService = AuthService();
    
    try {
      // Add a small delay for the splash screen to be visible
      await Future.delayed(const Duration(seconds: 3));

      print('=== SPLASH SCREEN: Printing SharedPreferences data ===');
      await authService.debugPrintAllData();

      // Check authentication status
      final isLoggedIn = await authService.isLoggedIn();
      print('=== AUTHENTICATION STATUS ===');
      print('Is Logged In: $isLoggedIn');

      // Optional: Also check token validity if needed
      bool hasValidTokens = false;
      try {
        hasValidTokens = await authService.hasValidTokens();
        print('Has Valid Tokens: $hasValidTokens');
      } catch (e) {
        print('Error checking tokens: $e');
        hasValidTokens = false;
      }
      
      print('===============================');

      // Ensure widget is still mounted before navigation
      if (!mounted) return;

      // Navigate based on authentication status
      if (isLoggedIn) {
        print('✅ User is authenticated - Navigating to HomeScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        print('❌ User is not authenticated - Navigating to SignupScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      print('=== ERROR IN SPLASH SCREEN ===');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $e');
      print('Falling back to SignupScreen');
      print('===============================');
      
      // Ensure widget is still mounted before navigation
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppGradients.background,
        ),
        child: Stack(
          children: [
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
              top: screenHeight * 0.1,
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
              bottom: screenHeight * 0.15,
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
            Positioned(
              bottom: screenHeight * 0.25,
              right: 40,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.grey300.withOpacity(0.08),
                ),
              ),
            ),
            
            Align(
              alignment: const Alignment(0, 0.15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/signature_logo.png',
                    width: screenWidth * 0.7,  
                    height: screenWidth * 0.7, 
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: screenWidth * 0.7,
                        height: screenWidth * 0.7,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.image_not_supported,
                          size: 80,
                          color: AppColors.white.withOpacity(0.5),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  
                  // Loading indicator
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 20),
                  
                  // Loading text
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: screenWidth * 0.045,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}