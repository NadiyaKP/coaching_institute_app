import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../service/api_config.dart';
import '../service/auth_service.dart';
import '../common/theme_color.dart';

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
      return screenWidth * 0.20;
    }
    
    if (isTabletDevice) {
      return screenHeight * 0.30;
    } else {
      return screenHeight * 0.25;
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

// ============= GET IN SCREEN =============
class GetInScreen extends StatefulWidget {
  const GetInScreen({super.key});

  @override
  State<GetInScreen> createState() => _GetInScreenState();
}

class _GetInScreenState extends State<GetInScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String _userEmail = '';
  AnimationController? _fadeController;
  AnimationController? _slideController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadUserEmail();
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

  Future<void> _loadUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userEmail = prefs.getString('username') ?? 
                   prefs.getString('email') ?? 
                   'User';
    });
  }

  @override
  void dispose() {
    _fadeController?.dispose();
    _slideController?.dispose();
    super.dispose();
  }

  Future<void> _getInToAccount() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken');
      final profileCompleted = prefs.getBool('profileCompleted') ?? false;

      if (accessToken == null || accessToken.isEmpty) {
        _showSnackBar('Session expired. Please login again.', AppColors.errorRed);
        await _performLogout();
        return;
      }

      // Reset attendance tracking timestamps
      String startTime = DateTime.now().toIso8601String();
      await prefs.setString('start_time', startTime);
      await prefs.remove('end_time');
      await prefs.remove('last_active_time');

      if (!mounted) return;

      _showSnackBar('Welcome back!', AppColors.successGreen);
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        
        if (profileCompleted) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacementNamed(context, '/profile_completion_page');
        }
      });
    } catch (e) {
      debugPrint('Get In error: $e');
      _showSnackBar('Failed to access account. Please try again.', AppColors.errorRed);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performLogout() async {
    String? accessToken;
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Logging out...'),
              ],
            ),
          );
        },
      );

      accessToken = await _authService.getAccessToken();
      
      String endTime = DateTime.now().toIso8601String();
      
      await _sendAttendanceData(accessToken, endTime);
      
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/students/student_logout/'),
          headers: {
            ...ApiConfig.commonHeaders,
            'Authorization': 'Bearer $accessToken',
          },
        ).timeout(ApiConfig.requestTimeout);

        debugPrint('Logout response status: ${response.statusCode}');
        debugPrint('Logout response body: ${response.body}');
      } catch (e) {
        debugPrint('Logout API error: $e');
      }
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      await _clearLogoutData();
      
    } catch (e) {
      debugPrint('Logout error: $e');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      String endTime = DateTime.now().toIso8601String();
      await _sendAttendanceData(accessToken, endTime);
      await _clearLogoutData();
    }
  }

  Future<void> _sendAttendanceData(String? accessToken, String endTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final studentType = prefs.getString('profile_student_type') ?? 
                          prefs.getString('studentType') ?? '';
      final bool isOnlineStudent = studentType.toUpperCase() == 'ONLINE';
      
      if (!isOnlineStudent) {
        debugPrint('🎯 Skipping attendance data for non-online student during logout');
        return;
      }
      
      String? startTime = prefs.getString('start_time');

      if (startTime != null && accessToken != null && accessToken.isNotEmpty) {
        debugPrint('📤 Preparing API request with timestamps:');
        debugPrint('Start: $startTime, End: $endTime');

        String cleanStart = startTime.split('.')[0].replaceFirst('T', ' ');
        String cleanEnd = endTime.split('.')[0].replaceFirst('T', ' ');

        final body = {
          "records": [
            {"time_stamp": cleanStart, "is_checkin": 1},
            {"time_stamp": cleanEnd, "is_checkin": 0}
          ]
        };

        debugPrint('📦 API request payload: ${jsonEncode(body)}');

        try {
          final response = await http.post(
            Uri.parse(ApiConfig.buildUrl('/api/performance/add_onlineattendance/')),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 10));

          debugPrint('🌐 API response status: ${response.statusCode}');
          debugPrint('🌐 API response body: ${response.body}');

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('✅ Attendance sent successfully');
          } else {
            debugPrint('⚠️ Error sending attendance: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('❌ Exception while sending attendance: $e');
        }
      } else {
        debugPrint('⚠️ Missing data: startTime=$startTime, accessToken=$accessToken');
      }
    } catch (e) {
      debugPrint('❌ Error in _sendAttendanceData: $e');
    }
  }

  Future<void> _clearLogoutData() async {
    try {
      await _authService.logout();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('start_time');
      await prefs.remove('end_time');
      await prefs.remove('last_active_time');
      debugPrint('🗑️ SharedPreferences timestamps cleared');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Error in _clearLogoutData: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout completed (Error: ${e.toString()})'),
            backgroundColor: Colors.red,
          ),
        );
        
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4B400),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
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
    
    double logoSize = screenWidth * 0.20;
    if (isLandscape) {
      if (isTabletDevice) {
        logoSize = screenWidth * 0.15;
      } else {
        logoSize = screenWidth * 0.18;
      }
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
          
          // Logo
          Positioned(
            left: 0,
            right: 0,
            bottom: isLandscape ? headerHeight * 0.05 : screenHeight * 0.08,
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

  Widget _buildGetInContainer() {
    final maxWidth = ResponsiveUtils.getMaxContainerWidth(context);
    final horizontalPadding = ResponsiveUtils.getHorizontalPadding(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final isTabletDevice = ResponsiveUtils.isTablet(context);
    
    final containerPadding = EdgeInsets.symmetric(
      horizontal: (isTabletDevice && !isLandscape) ? 24 : (isLandscape ? 16 : 20),
      vertical: (isTabletDevice && !isLandscape) ? 20 : (isLandscape ? 12 : 16),
    );
    
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: horizontalPadding,
        child: Container(
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
              _buildWelcomeText(),
              SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 16)),
              _buildEmailDisplay(),
              SizedBox(height: ResponsiveUtils.getVerticalSpacing(context, 24)),
              _buildGetInButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeText() {
    final fontSize = ResponsiveUtils.getFontSize(context, 18);
    final iconSize = ResponsiveUtils.getFontSize(context, 20);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          "Return back to your account",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailDisplay() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    final iconSize = ResponsiveUtils.getFontSize(context, 16);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.grey50, AppColors.grey100],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppGradients.primaryYellow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.account_circle,
              color: AppColors.white,
              size: iconSize * 1.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Logged in as",
                  style: TextStyle(
                    fontSize: fontSize * 0.85,
                    color: AppColors.grey600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGetInButton() {
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
    
    return Container(
      width: double.infinity,
      height: buttonHeight,
      decoration: BoxDecoration(
        gradient: AppGradients.primaryYellow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowYellow,
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _getInToAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: _isLoading
            ? SizedBox(
                height: isLandscape ? 20 : 24,
                width: isLandscape ? 20 : 24,
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                "Get In",
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildLogoutOption() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    
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
              "Do you want to logout from your account? ",
              style: TextStyle(
                fontSize: fontSize,
                color: AppColors.grey600,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
          GestureDetector(
            onTap: _isLoading ? null : _showLogoutDialog,
            child: Text(
              "Logout",
              style: TextStyle(
                fontSize: fontSize,
                color: AppColors.errorRed,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final verticalSpacing = ResponsiveUtils.getVerticalSpacing(context, 25);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isLandscape) {
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
                              _buildGetInContainer(),
                              _buildLogoutOption(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            
            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeader(),
                  SizedBox(height: verticalSpacing),
                  _buildGetInContainer(),
                  _buildLogoutOption(),
                  SizedBox(
                    height: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}