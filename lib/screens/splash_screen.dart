import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../service/auth_service.dart';
import 'home.dart';
import 'getin_screen.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

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
    // Start auth check
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      // Add a small delay for the splash screen to be visible
      await Future.delayed(const Duration(seconds: 3));

      print('=== SPLASH SCREEN: Checking Authentication ===');
      
      // Get SharedPreferences instance
      final prefs = await SharedPreferences.getInstance();
      
      // Check if accessToken exists in SharedPreferences
      final String? accessToken = prefs.getString('accessToken');
      
      // Check student_type from SharedPreferences
      final String? studentType = prefs.getString('profile_student_type');
      
      print('Access Token Present: ${accessToken != null && accessToken.isNotEmpty}');
      print('Student Type: ${studentType ?? "N/A"}');
      
      // Ensure widget is still mounted before navigation
      if (!mounted) return;

      // Navigate based on access token presence and student type
      if (accessToken != null && accessToken.isNotEmpty) {
        // Check if student type is 'ONLINE'
        if (studentType != null && studentType.toUpperCase() == 'ONLINE') {
          print('✅ Access token found + Student Type is ONLINE - Navigating to GetInScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const GetInScreen()),
          );
        } else {
          print('✅ Access token found + Student Type is NOT ONLINE - Navigating to HomeScreen');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        print('❌ No access token found - Navigating to LoginScreen');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
      
      print('===============================');
      
    } catch (e) {
      print('=== ERROR IN SPLASH SCREEN ===');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $e');
      print('Falling back to LoginScreen');
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
    final isLandscape = screenWidth > screenHeight;
    
    // Responsive sizing based on orientation
    final logoSize = isLandscape 
        ? screenHeight * 0.55  // Use height for landscape - increased size
        : screenWidth * 0.7;    // Use width for portrait
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppGradients.background,
        ),
        child: Stack(
          children: [
            // Background decorative circles
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
            
            // Main content - centered for both orientations
            Center(
              child: isLandscape
                  ? // Landscape: Just show logo centered
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/signature_logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: logoSize,
                              height: logoSize,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.image_not_supported,
                                size: logoSize * 0.4,
                                color: AppColors.white.withOpacity(0.5),
                              ),
                            );
                          },
                        ),
                      ],
                    )
                  : // Portrait: Show logo centered
                    SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.05,
                          horizontal: 20,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo with responsive sizing
                            Image.asset(
                              'assets/images/signature_logo.png',
                              width: logoSize,
                              height: logoSize,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: logoSize,
                                  height: logoSize,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: logoSize * 0.4,
                                    color: AppColors.white.withOpacity(0.5),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}