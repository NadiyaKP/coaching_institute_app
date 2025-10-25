import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../service/auth_service.dart';
import 'home.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      // Add a small delay for the splash screen to be visible
      await Future.delayed(const Duration(seconds: 3));

      // Print SharedPreferences data for debugging
      print('=== SPLASH SCREEN: Printing SharedPreferences data ===');
      await _authService.debugPrintAllData();

      // Check authentication status
      final isLoggedIn = await _authService.isLoggedIn();
      print('=== AUTHENTICATION STATUS ===');
      print('Is Logged In: $isLoggedIn');

      // Optional: Also check token validity if needed
      bool hasValidTokens = false;
      try {
        hasValidTokens = await _authService.hasValidTokens();
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
        // If you want to also check token validity, use:
        // if (isLoggedIn && hasValidTokens) {
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
      // Enhanced error logging
      print('=== ERROR IN SPLASH SCREEN ===');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $e');
      print('Stack Trace: ${StackTrace.current}');
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
            // Decorative circles - same as login screen
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
            
            // Main content - Centered with slight downward offset
            Align(
              alignment: const Alignment(0, 0.15), // Moved slightly down
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo - Increased size
                  Image.asset(
                    'assets/images/signature_logo.png',
                    width: screenWidth * 0.7,  // Increased from 60% to 70% of screen width
                    height: screenWidth * 0.7, // Keeping it square
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