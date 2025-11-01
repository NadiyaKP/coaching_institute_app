import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../common/theme_color.dart';
import '../../common/bottom_navbar.dart';
import 'exam_schedule/exam_schedule.dart';
import '../view_profile.dart';
import '../settings/settings.dart';
import '../../service/auth_service.dart';
import '../Academics/results.dart';
import 'assignments/assignments.dart';
import '../../screens/performance.dart';
import '../../service/notification_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileData();
    _loadStudentType();
    _reloadBadgeState();
    _debugBadgeState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload badge state when app comes to foreground while on this screen
      _reloadBadgeState();
    }
  }

  Future<void> _reloadBadgeState() async {
    debugPrint('🔄 Reloading badge state in Academics screen');
    // Trigger UI rebuild to reflect latest badge state
    if (mounted) {
      setState(() {});
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

  Future<void> _debugBadgeState() async {
  final prefs = await SharedPreferences.getInstance();
  final hasUnread = prefs.getBool('has_unread_assignments') ?? false;
  debugPrint('🔍 DEBUG - SharedPreferences badge state: $hasUnread');
  debugPrint('🔍 DEBUG - ValueNotifier badge state: ${NotificationService.hasUnreadAssignments.value}');
}

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (Route<dynamic> route) => false,
    );
    return false; // Prevent default back behavior since we're handling navigation
  }

  // Navigation methods
  void _navigateToExamSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ExamScheduleScreen(),
        settings: const RouteSettings(name: '/exam_schedule'),
      ),
    );
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

  void _navigateToAssignments() {
    // Clear the badge when assignments screen is opened
    if (NotificationService.hasUnreadAssignments.value) {
      NotificationService.clearAssignmentBadge();
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AssignmentsScreen(),
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

  // Helper method to check if student is online
  bool get isOnlineStudent => studentType.toLowerCase() == 'online';

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
        profileCompleted: profileCompleted,
        onViewProfile: () {
          Navigator.of(context).pop(); 
          _navigateToViewProfile();
        },
        onSettings: () {
          Navigator.of(context).pop(); 
          _navigateToSettings();
        },
        onLogout: () {
          Navigator.of(context).pop(); 
          _showLogoutDialog();
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

                    // Conditional rendering based on student type
                    if (!isOnlineStudent) ...[
                      // Exam Schedule Card (Only for non-online students)
                      _buildAcademicCard(
                        icon: Icons.calendar_today_rounded,
                        title: 'Exam Schedule',
                        subtitle: 'View your upcoming exams',
                        color: AppColors.primaryBlue,
                        onTap: _navigateToExamSchedule,
                      ),

                      const SizedBox(height: 12),

                      // Results Card (Only for non-online students)
                      _buildAcademicCard(
                        icon: Icons.assessment_rounded,
                        title: 'Results',
                        subtitle: 'Check your exam results',
                        color: AppColors.primaryYellowLight,
                        onTap: _navigateToResults,
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

                    // Assignments Card (For all students) - With unread badge
                    // Using the same ValueNotifier that controls the bottom navbar badge
                    ValueListenableBuilder<bool>(
                      valueListenable: NotificationService.hasUnreadAssignments,
                      builder: (context, hasUnread, child) {
                        debugPrint('🎯 Academics Screen - Assignments badge state: $hasUnread');
                        return _buildAcademicCard(
                          icon: Icons.assignment_rounded,
                          title: 'Assignments',
                          subtitle: 'Submit and track assignments',
                          color: AppColors.warningOrange,
                          onTap: _navigateToAssignments,
                          showBadge: hasUnread, // Same condition as bottom navbar
                        );
                      },
                    ),

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
    bool showBadge = false, // New parameter for showing badge
  }) {
    debugPrint('🔄 Building Academic Card - $title, showBadge: $showBadge');
    
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  // Icon Container with potential badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
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
                      // Unread badge - synchronized with bottom navbar
                      if (showBadge)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
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
                  
                  // Arrow Icon
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: color.withOpacity(0.6),
                    size: 16,
                  ),
                ],
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