import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../service/auth_service.dart';
import 'home.dart';
import '../screens/focus_mode/focus_mode_entry.dart';
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
      await Future.delayed(const Duration(seconds: 3));
      final prefs = await SharedPreferences.getInstance();
      final String? accessToken = prefs.getString('accessToken');
      final String? studentType = prefs.getString('profile_student_type');
      
      if (!mounted) return;
      
      if (accessToken != null && accessToken.isNotEmpty) {
        // Check student type and navigate accordingly
        if (studentType != null) {
          final String studentTypeUpper = studentType.toUpperCase();
          
          if (studentTypeUpper == 'ONLINE' || studentTypeUpper == 'OFFLINE') {
            // Navigate to focus mode entry for Online/Offline students
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const FocusModeEntryScreen()),
            );
          } else if (studentTypeUpper == 'PUBLIC') {
            // Navigate to home for Public students
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          } else {
            // Default case: Navigate to home
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        } else {
          // No student type found: Navigate to home
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      } else {
        // No access token: Navigate to login
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
      
    } catch (e) {
      // Error handling: Navigate to login
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
        ? screenHeight * 0.55  
        : screenWidth * 0.7;    
    
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