import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';
import '../../common/theme_color.dart';
import '../../common/bottom_navbar.dart';
import 'exam_schedule/exam_schedule.dart';
import '../view_profile.dart';
import '../settings/settings.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../service/notification_service.dart';
import '../Academics/results.dart';
import 'assignments/assignments.dart';
import '../../screens/performance.dart';
import '../../screens/Academics/my_leave_application/my_leave_application.dart';
import '../Academics/time_table.dart';

class AcademicsScreen extends StatefulWidget {
  const AcademicsScreen({Key? key}) : super(key: key);

  @override
  State<AcademicsScreen> createState() => _AcademicsScreenState();
}

class _AcademicsScreenState extends State<AcademicsScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthService _authService = AuthService();
  
  // User profile data
  String name = '';
  String email = '';
  String course = '';
  String subcourse = '';
  String studentType = '';
  bool profileCompleted = false;
  
  // Bottom Navigation Bar
  int _currentIndex = 1;
  
  // Notification counts
  int unreadAssignmentsCount = 0;
  int unreadExamsCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileData();
    _loadStudentType();
    _loadUnreadNotificationCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload notification counts when app comes to foreground
      _loadUnreadNotificationCounts();
    }
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        name = prefs.getString('profile_name') ?? '';
        email = prefs.getString('profile_email') ?? '';
        course = prefs.getString('profile_course') ?? '';
        subcourse = prefs.getString('profile_subcourse') ?? '';
        profileCompleted = prefs.getBool('profile_completed') ?? false;
      });
    } catch (e) {
      debugPrint('Error loading profile data: $e');
    }
  }

  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        studentType = prefs.getString('profile_student_type') ?? '';
      });
    } catch (e) {
      debugPrint('Error loading student type: $e');
    }
  }

  // Check if student type is Online or Offline (not Public)
  bool get isRegularStudent {
    final type = studentType.toLowerCase();
    return type == 'online' || type == 'offline';
  }

  // Check if student is online specifically
  bool get isOnlineStudent => studentType.toLowerCase() == 'online';

  // Update the bottom navbar badge based on unread counts
  void _updateAcademicsBadge() {
    // Check if both counts are zero
    final bool hasUnread = (unreadAssignmentsCount > 0 || unreadExamsCount > 0);
    
    // Get current subscription badge state
    final bool hasUnreadSubscription = NotificationService.badgeNotifier.value['hasUnreadSubscription'] ?? false;
    
    // Update the notification service badges (keeping subscription badge unchanged)
    NotificationService.updateBadges(
      hasUnreadAssignments: hasUnread,
      hasUnreadSubscription: hasUnreadSubscription,
    );
    
    debugPrint('🔔 Updated academics badge - hasUnread: $hasUnread (Assignments: $unreadAssignmentsCount, Exams: $unreadExamsCount)');
  }

  // Load and count unread notifications from SharedPreferences
  Future<void> _loadUnreadNotificationCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? notificationsData = prefs.getString('unread_notifications');
      
      if (notificationsData != null && notificationsData.isNotEmpty) {
        debugPrint('📬 Stored notifications data: $notificationsData');
        
        final List<dynamic> notifications = json.decode(notificationsData);
        
        int assignmentCount = 0;
        int examCount = 0;
        
        for (var notification in notifications) {
          if (notification['data'] != null) {
            final String type = notification['data']['type']?.toString().toLowerCase() ?? '';
            
            if (type == 'assignment') {
              assignmentCount++;
            } else if (type == 'exam') {
              examCount++;
            }
          }
        }
        
        setState(() {
          unreadAssignmentsCount = assignmentCount;
          unreadExamsCount = examCount;
        });
        
        debugPrint('📊 Unread counts - Assignments: $assignmentCount, Exams: $examCount');
      } else {
        debugPrint('📭 No unread notifications found');
        setState(() {
          unreadAssignmentsCount = 0;
          unreadExamsCount = 0;
        });
      }
      
      // Update the bottom navbar badge after loading counts
      _updateAcademicsBadge();
    } catch (e) {
      debugPrint('❌ Error loading unread notification counts: $e');
      setState(() {
        unreadAssignmentsCount = 0;
        unreadExamsCount = 0;
      });
      
      // Clear badge on error
      _updateAcademicsBadge();
    }
  }

  // Mark notifications as read by sending IDs to API
  Future<void> _markNotificationsAsRead() async {
    debugPrint('🔍 _markNotificationsAsRead() called');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Debug: Check all keys in SharedPreferences
      final allKeys = prefs.getKeys();
      debugPrint('🔑 All SharedPreferences keys: $allKeys');
      
      final String? idsData = prefs.getString('ids');
      debugPrint('📝 Raw IDs data from SharedPreferences: $idsData');
      
      if (idsData == null || idsData.isEmpty) {
        debugPrint('📭 No IDs to mark as read');
        return;
      }
      
      // Parse the IDs list
      List<dynamic> idsList;
      try {
        idsList = json.decode(idsData);
        debugPrint('✅ Successfully parsed IDs list: $idsList (Type: ${idsList.runtimeType})');
      } catch (e) {
        debugPrint('❌ Failed to parse IDs JSON: $e');
        // Clear corrupted data
        await prefs.remove('ids');
        return;
      }
      
      if (idsList.isEmpty) {
        debugPrint('📭 IDs list is empty after parsing');
        await prefs.remove('ids');
        return;
      }
      
      debugPrint('📤 Marking ${idsList.length} notifications as read - IDs: $idsList');
      
      // Get fresh access token using AuthService (handles token refresh)
      final String? accessToken = await _authService.getAccessToken();
      debugPrint('🔐 Access token obtained from AuthService');
      
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ Access token not found or empty');
        return;
      }
      
      // Get base URL using ApiConfig.currentBaseUrl
      final String baseUrl = ApiConfig.currentBaseUrl;
      debugPrint('🌐 Base URL from ApiConfig: $baseUrl');
      
      if (baseUrl.isEmpty) {
        debugPrint('❌ Base URL is empty');
        return;
      }
      
      // Prepare API endpoint
      final String apiUrl = '$baseUrl/api/notifications/mark_read/';
      
      // Prepare request body
      final Map<String, dynamic> requestBody = {
        'ids': idsList,
      };
      
      debugPrint('🌐 Full API URL: $apiUrl');
      debugPrint('📦 Request Body: ${json.encode(requestBody)}');
      debugPrint('🔐 Authorization Header: Bearer ${accessToken.substring(0, 10)}...');
      
      // Create HTTP client with custom certificate handling
      final client = IOClient(ApiConfig.createHttpClient());
      
      try {
        // Make POST request with authorization headers
        debugPrint('📡 Sending POST request...');
        final response = await client.post(
          Uri.parse(apiUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            ...ApiConfig.commonHeaders,
          },
          body: json.encode(requestBody),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('⏱️ Request timed out after 10 seconds');
            throw Exception('Request timeout');
          },
        );
        
        debugPrint('📨 Response Status Code: ${response.statusCode}');
        debugPrint('📨 Response Body: ${response.body}');
        debugPrint('📨 Response Headers: ${response.headers}');
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          // Successfully marked as read, clear the IDs from SharedPreferences
          await prefs.remove('ids');
          debugPrint('✅ Notifications marked as read successfully!');
          debugPrint('🗑️ IDs list cleared from SharedPreferences');
        } else if (response.statusCode == 401) {
          debugPrint('⚠️ Token expired or invalid - User needs to login again');
          // Handle token expiration
          await _authService.logout();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/signup',
              (Route<dynamic> route) => false,
            );
          }
        } else {
          debugPrint('⚠️ Failed to mark notifications as read');
          debugPrint('⚠️ Status Code: ${response.statusCode}');
          debugPrint('⚠️ Response: ${response.body}');
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('❌ SSL Handshake error: $e');
      debugPrint('This is normal in development environments with self-signed certificates');
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      debugPrint('Please check your internet connection');
    } catch (e, stackTrace) {
      debugPrint('❌ Error marking notifications as read: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
    
    debugPrint('🏁 _markNotificationsAsRead() completed');
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (Route<dynamic> route) => false,
    );
    return false; // Prevent default back behavior since we're handling navigation
  }

  void _navigateToExamSchedule() async {
  // Clear exam badge immediately for instant feedback
  setState(() {
    unreadExamsCount = 0;
  });
  
  // Update bottom navbar badge immediately
  _updateAcademicsBadge();
  
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ExamScheduleScreen(
        studentType: studentType, // Pass student type
      ),
      settings: const RouteSettings(name: '/exam_schedule'),
    ),
  );
  
  // After returning from exam_schedule, wait for dispose to complete
  debugPrint('🔄 Returned from Exam Schedule');
  await Future.delayed(const Duration(milliseconds: 300));
  
  // Now reload counts - exam notifications should be removed
  debugPrint('🔄 Reloading notification counts');
  await _loadUnreadNotificationCounts();
  
  // Ensure exam count stays 0 even if there's a timing issue
  setState(() {
    if (unreadExamsCount > 0) {
      debugPrint('⚠️ Exam count still showing, forcing to 0');
      unreadExamsCount = 0;
    }
  });
  
  // Update badge again after return
  _updateAcademicsBadge();
}

  void _navigateToResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ResultsScreen(),
      ),
    );
  }

  void _navigateToPerformance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PerformanceScreen(),
      ),
    );
  }

  void _navigateToAssignments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AssignmentsScreen(),
      ),
    );
    
    // When returning from assignments:
    debugPrint('🔄 Returned from Assignments');
    
    // Wait a bit to ensure any dispose() has completed
    await Future.delayed(const Duration(milliseconds: 100));
    
    // First mark notifications as read (send to API)
    await _markNotificationsAsRead();
    
    // Then reload the counts
    debugPrint('🔄 Reloading notification counts after marking as read');
    await _loadUnreadNotificationCounts();
    
    // Update bottom navbar badge
    _updateAcademicsBadge();
    
    // Force UI update
    if (mounted) {
      setState(() {});
    }
  }

  // Navigate to Leave Application
  void _navigateToLeaveApplication() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MyLeaveApplicationScreen(),
      ),
    );
  }

  // Navigate to Time Table
  void _navigateToTimeTable() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TimeTableScreen(),
      ),
    );
  }

  // Navigate to View Profile
  void _navigateToViewProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(
          onProfileUpdated: (Map<String, String> updatedData) {
            _loadProfileData(); // Refresh data
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile updated successfully!'),
                backgroundColor: Color(0xFFF4B400),
              ),
            );
          },
        ),
      ),
    );
  }

  // Navigate to Settings
  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
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

  Future<void> _performLogout() async {
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

      await _authService.logout();
      
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
      if (mounted) {
        Navigator.of(context).pop();
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

  // Bottom Navigation Bar methods
  void _onTabTapped(int index) {
    if (index == 3) {
      // Profile tab - open drawer
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }
    
    setState(() {
      _currentIndex = index;
    });

    BottomNavBarHelper.handleTabSelection(
      index,
      context,
      studentType,
      _scaffoldKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundLight,
      endDrawer: CommonProfileDrawer(
        name: name,
        email: email,
        course: course,
        subcourse: subcourse,
        studentType: studentType,
        profileCompleted: profileCompleted,
        onViewProfile: () {
          Navigator.of(context).pop(); 
          _navigateToViewProfile();
        },
        onSettings: () {
          Navigator.of(context).pop(); 
          _navigateToSettings();
        },
        onClose: () {
          Navigator.of(context).pop(); 
        },
      ),
      body: PopScope(
        canPop: false,
        onPopInvoked: (bool didPop) async {
          if (didPop) {
            return;
          }
          
          await _handleDeviceBackButton();
        },
        child: Column(
          children: [
            // Header Section with Curved Bottom
            ClipPath(
              clipper: CurvedHeaderClipper(),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryYellow,
                      AppColors.primaryYellowDark,
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button and title
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () async {
                            await _handleDeviceBackButton();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Academics',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    
                    // Section Title
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Academic Resources',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 18),

                    if (isRegularStudent) ...[
  // Exam Schedule Card (For Online and Offline students) - With unread badge
                        _buildAcademicCard(
                          icon: Icons.calendar_today_rounded,
                          title: 'Exam Schedule',
                          subtitle: 'View your upcoming exams',
                          color: AppColors.primaryBlue,
                          onTap: _navigateToExamSchedule,
                          badgeCount: unreadExamsCount,
                        ),

                        const SizedBox(height: 12),
                      ],

                      if (isOnlineStudent) ...[
                        // Performance Card (Only for online students)
                        _buildAcademicCard(
                          icon: Icons.trending_up_rounded,
                          title: 'Performance',
                          subtitle: 'Track your learning progress',
                          color: AppColors.primaryBlue,
                          onTap: _navigateToPerformance,
                        ),

                        const SizedBox(height: 12),
                      ],

                    if (!isOnlineStudent) ...[
                      // Results Card (Only for offline students)
                      _buildAcademicCard(
                        icon: Icons.assessment_rounded,
                        title: 'Results',
                        subtitle: 'Check your exam results',
                        color: AppColors.primaryYellowLight,
                        onTap: _navigateToResults,
                      ),

                      const SizedBox(height: 12),
                    ],

                    // Time Table Card (For Online and Offline students, not Public)
                    if (isRegularStudent) ...[
                      _buildAcademicCard(
                        icon: Icons.schedule_rounded,
                        title: 'Time Table',
                        subtitle: 'View your class schedule',
                        color: AppColors.primaryBlue,
                        onTap: _navigateToTimeTable,
                      ),

                      const SizedBox(height: 12),
                    ],

                    // Assignments Card (For all students) - With unread badge
                    _buildAcademicCard(
                      icon: Icons.assignment_rounded,
                      title: 'Assignments',
                      subtitle: 'Submit and track assignments',
                      color: AppColors.warningOrange,
                      onTap: _navigateToAssignments,
                      badgeCount: unreadAssignmentsCount,
                    ),

                    // Leave Application Card (Only for offline students)
                    if (!isOnlineStudent) ...[
                      const SizedBox(height: 12),
                      
                      _buildAcademicCard(
                        icon: Icons.edit_note, 
                        title: 'Leave Application',
                        subtitle: 'Apply and track leave requests',
                        color: AppColors.primaryBlue, 
                        onTap: _navigateToLeaveApplication,
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CommonBottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _onTabTapped,
        studentType: studentType,
        scaffoldKey: _scaffoldKey,
      ),
    );
  }

  Widget _buildAcademicCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool comingSoon = false,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // Icon Container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 26,
                ),
              ),
              
              const SizedBox(width: 14),
              
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (comingSoon) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryYellow.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'Soon',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryYellowDark,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 6),
              
              // Badge Count (if > 0) positioned on the right side
              if (badgeCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  child: Center(
                    child: Text(
                      badgeCount > 99 ? '99+' : badgeCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              
              // Arrow Icon
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color.withOpacity(0.6),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAccessItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Curved Header Clipper
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 25);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 25,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}