import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/notification_service.dart';
import '../../screens/Academics/academics.dart';
import '../screens/mock_test/mock_test.dart';
import '../screens/subscription/subscription.dart';
import '../screens/my_documents/my_documents.dart';
import '../screens/allow_apps/allow_apps.dart'; 
import '../common/theme_color.dart';
import 'package:device_apps/device_apps.dart';


class CommonBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabSelected;
  final String studentType;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const CommonBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.studentType,
    this.scaffoldKey,
  }) : super(key: key);

  @override
  State<CommonBottomNavBar> createState() => _CommonBottomNavBarState();
}

class _CommonBottomNavBarState extends State<CommonBottomNavBar> {
  String _getSecondTabLabel() {
    final String studentTypeUpper = widget.studentType.toUpperCase();
    if (studentTypeUpper == 'ONLINE') {
      return 'Academics';
    } else if (studentTypeUpper == 'PUBLIC') {
      return 'Subscription';
    } else {
      return 'Academics';
    }
  }

  IconData _getSecondTabIcon() {
    final String studentTypeUpper = widget.studentType.toUpperCase();
    if (studentTypeUpper == 'ONLINE') {
      return Icons.school_rounded;
    } else if (studentTypeUpper == 'PUBLIC') {
      return Icons.card_membership_rounded;
    } else {
      return Icons.school_rounded;
    }
  }

  void _openProfileDrawer() {
    if (widget.scaffoldKey?.currentState != null) {
      widget.scaffoldKey!.currentState!.openEndDrawer();
    }
  }

  void _handleTabSelection(int index) {
    widget.onTabSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        child: ValueListenableBuilder<Map<String, bool>>(
          valueListenable: NotificationService.badgeNotifier,
          builder: (context, badges, child) {
            final bool showAcademicsBadge = badges['hasUnreadAssignments'] ?? false;
            final bool showSubscriptionBadge = badges['hasUnreadSubscription'] ?? false;
            
            return BottomNavigationBar(
              currentIndex: widget.currentIndex,
              onTap: (index) {
                if (index == 3) {
                  _openProfileDrawer();
                } else {
                  _handleTabSelection(index);
                }
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.white,
              selectedItemColor: AppColors.primaryYellow,
              unselectedItemColor: AppColors.grey500,
              selectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: _buildIconWithBadge(
                    icon: Icon(_getSecondTabIcon()),
                    showBadge: _getSecondTabLabel() == 'Academics' 
                        ? showAcademicsBadge 
                        : showSubscriptionBadge,
                  ),
                  label: _getSecondTabLabel(),
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_turned_in_rounded),
                  label: 'Practice',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIconWithBadge({
    required Widget icon,
    required bool showBadge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (showBadge)
          Positioned(
            top: -2,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.errorRed,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
            ),
          ),
      ],
    );
  }
}

class BottomNavBarHelper {
  static void handleTabSelection(
    int index, 
    BuildContext context, 
    String studentType,
    GlobalKey<ScaffoldState>? scaffoldKey,
  ) {
    switch (index) {
      case 0:
        _navigateToHome(context);
        break;
      case 1:
        _handleSecondTab(context, studentType);
        break;
      case 2:
        _navigateToMockTest(context);
        break;
      case 3:
        if (scaffoldKey?.currentState != null) {
          scaffoldKey!.currentState!.openEndDrawer();
        }
        break;
    }
  }

  static void _handleSecondTab(BuildContext context, String studentType) {
    final String studentTypeUpper = studentType.toUpperCase();
    if (studentTypeUpper == 'PUBLIC') {
      _navigateToSubscription(context);
    } else {
      _navigateToAcademics(context);
    }
  }

  static void _navigateToHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (Route<dynamic> route) => false,
    );
  }

  static void _navigateToSubscription(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SubscriptionScreen(),
        settings: const RouteSettings(name: '/subscription'),
      ),
    );
  }

  static void _navigateToAcademics(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AcademicsScreen(),
        settings: const RouteSettings(name: '/academics'),
      ),
    );
  }

  static void _navigateToMockTest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MockTestScreen(),
        settings: const RouteSettings(name: '/mock_test'),
      ),
    );
  }
}

// App Permission Service
class AppPermissionService {
  static const String _permissionKey = 'app_permission_granted';

  // Check if permission was already granted
  static Future<bool> isPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionKey) ?? false;
  }

  // Save permission status
  static Future<void> savePermissionStatus(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionKey, granted);
  }

  // Request permission from user
  static Future<bool> requestPermission(BuildContext context) async {
    // First check if already granted
    if (await isPermissionGranted()) {
      return true;
    }

    // Show permission dialog
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'App Access Permission',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We need to access your installed apps list to provide better educational recommendations.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.primaryYellow),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only app names and icons will be accessed. No personal data will be collected.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Deny',
              style: TextStyle(color: AppColors.grey500),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (granted == true) {
      await savePermissionStatus(true);
      return true;
    }
    
    return false;
  }
}

// REDESIGNED Common Profile Drawer - Beautiful Yellow Theme
class CommonProfileDrawer extends StatelessWidget {
  final String name;
  final String email;
  final String course;
  final String subcourse;
  final bool profileCompleted;
  final String studentType; // Added this parameter
  final VoidCallback onViewProfile;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  const CommonProfileDrawer({
    Key? key,
    required this.name,
    required this.email,
    required this.course,
    required this.subcourse,
    required this.profileCompleted,
    required this.studentType, // Added
    required this.onViewProfile,
    required this.onSettings,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final screenWidth = MediaQuery.of(context).size.width;
    final isOnlineOrOffline = studentType.toUpperCase() == 'ONLINE' || 
                              studentType.toUpperCase() == 'OFFLINE';
    
    // Adjust drawer width based on orientation
    final drawerWidth = orientation == Orientation.landscape
        ? screenWidth * 0.45
        : screenWidth * 0.75;
    
    return Drawer(
      width: drawerWidth,
      child: Container(
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
        child: SafeArea(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  // Profile Section
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: Column(
                      children: [
                        // Profile Avatar
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.black.withOpacity(0.12),
                                blurRadius: 16,
                                spreadRadius: 1,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const CircleAvatar(
                            radius: 38,
                            backgroundColor: AppColors.primaryBlue,
                            child: Icon(
                              Icons.person_rounded,
                              size: 42,
                              color: AppColors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // User Name
                        Text(
                          name.isNotEmpty ? name : 'User Name',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Email
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryBlueDark.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Course Information Card
                  if (course.isNotEmpty || subcourse.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.primaryBlue,
                                        AppColors.primaryBlueLight,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.school_rounded,
                                    color: AppColors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'My Course',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (course.isNotEmpty) 
                              _buildCourseInfo('Course', course),
                            if (subcourse.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildCourseInfo('Level', subcourse),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Menu Items
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          icon: Icons.person_outline_rounded,
                          label: 'View Profile',
                          onTap: onViewProfile,
                        ),
                        const SizedBox(height: 8),
                        _buildMenuItem(
                          icon: Icons.description_outlined,
                          label: 'My Documents',
                          onTap: () {
                            Navigator.of(context).pop();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyDocumentsScreen(),
                                settings: const RouteSettings(name: '/my_documents'),
                              ),
                            );
                          },
                        ),
                        
                        // Show "Allow Apps" button only for Online/Offline students
                       if (isOnlineOrOffline) ...[
                          const SizedBox(height: 8),
                          _buildMenuItem(
                            icon: Icons.apps_rounded,
                            label: 'Allow Apps',
                            onTap: () async {
                              // Close drawer first
                              Navigator.of(context).pop();
                              
                              // Check and request permission
                              final hasPermission = await AppPermissionService.requestPermission(context);
                              
                              if (hasPermission && context.mounted) {
                                // Navigate to Allow Apps screen only if permission is granted
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AllowAppsScreen(),
                                    settings: const RouteSettings(name: '/allow_apps'),
                                  ),
                                );
                              } else if (context.mounted) {
                                // Show message that permission is required
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Permission is required to view installed apps'),
                                    backgroundColor: AppColors.errorRed,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                                                
                        const SizedBox(height: 8),
                        _buildMenuItem(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          onTap: onSettings,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCourseInfo(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.white.withOpacity(0.3),
        highlightColor: AppColors.white.withOpacity(0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.primaryBlue,
                      AppColors.primaryBlueLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: AppColors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppColors.grey400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}