import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import '../service/auth_service.dart';
import 'home.dart';

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
      await Future.delayed(const Duration(seconds: 2));

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Add error handling for the image
            Image.asset(
              'assets/images/signature_logo.png',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.image_not_supported,
                    size: 50,
                    color: Colors.grey,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text(
              'Loading...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}