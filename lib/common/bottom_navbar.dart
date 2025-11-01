import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/notification_service.dart';
import '../../screens/Academics/academics.dart';
import '../screens/mock_test/mock_test.dart';
import '../screens/subscription/subscription.dart';

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

  // Handle tab selection WITHOUT clearing badge for Academics
  void _handleTabSelection(int index) {
    // DON'T clear badge when Academics tab is selected
    // The badge should only clear when Assignments screen is opened
    widget.onTabSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
        child: ValueListenableBuilder<bool>(
          valueListenable: NotificationService.hasUnreadAssignments,
          builder: (context, hasUnread, child) {
            return BottomNavigationBar(
              currentIndex: widget.currentIndex,
              onTap: (index) {
                if (index == 3) {
                  // Profile tab - open drawer
                  _openProfileDrawer();
                } else {
                  // Other tabs - normal navigation without badge clearing
                  _handleTabSelection(index);
                }
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: const Color(0xFFF4B400),
              unselectedItemColor: const Color(0xFF9E9E9E),
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
                    showBadge: hasUnread && _getSecondTabLabel() == 'Academics',
                  ),
                  label: _getSecondTabLabel(),
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.assignment_turned_in_rounded),
                  label: 'Mock Test',
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

  // Widget to show badge on icon
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
                color: Colors.red,
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

// Update the BottomNavBarHelper to NOT clear badge when navigating to Academics
class BottomNavBarHelper {
  static void handleTabSelection(
    int index, 
    BuildContext context, 
    String studentType,
    GlobalKey<ScaffoldState>? scaffoldKey,
  ) {
    switch (index) {
      case 0: // Home
        _navigateToHome(context);
        break;
      case 1: // Academics/Subscription based on student type
        _handleSecondTab(context, studentType);
        break;
      case 2: // Mock Test
        _navigateToMockTest(context);
        break;
      case 3: // Profile - open drawer if scaffoldKey is provided
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
      // For 'ONLINE' and all other student types, navigate to Academics
      // DON'T clear badge here - only clear when Assignments screen is opened
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
        builder: (context) => SubscriptionScreen(),
        settings: const RouteSettings(name: '/subscription'),
      ),
    );
  }

  static void _navigateToAcademics(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AcademicsScreen(),
        settings: const RouteSettings(name: '/academics'),
      ),
    );
  }

  static void _navigateToMockTest(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MockTestScreen(),
        settings: const RouteSettings(name: '/mock_test'),
      ),
    );
  }
}

// Common Profile Drawer Widget that can be used across screens
class CommonProfileDrawer extends StatelessWidget {
  final String name;
  final String email;
  final String course;
  final String subcourse;
  final bool profileCompleted;
  final VoidCallback onViewProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;
  final VoidCallback onClose;

  const CommonProfileDrawer({
    Key? key,
    required this.name,
    required this.email,
    required this.course,
    required this.subcourse,
    required this.profileCompleted,
    required this.onViewProfile,
    required this.onSettings,
    required this.onLogout,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF4B400),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Profile Header with smaller icon
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  children: [
                    // Smaller profile icon
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Color(0xFFF4B400),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Full Name
                    Text(
                      name.isNotEmpty ? name : 'User Name',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    // Email
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.88),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // My Course Card - showing course and subcourse
              if (course.isNotEmpty || subcourse.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'My Course',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Course information
                        if (course.isNotEmpty) 
                          _buildDrawerCourseInfo('Course', course),
                        if (subcourse.isNotEmpty) 
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              _buildDrawerCourseInfo('Subcourse', subcourse),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Menu Items
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildDrawerItem(
                      icon: Icons.person_outline_rounded,
                      label: 'View Profile',
                      onTap: onViewProfile,
                    ),
                    const Divider(height: 1, color: Colors.grey),
                    _buildDrawerItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: onSettings,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Logout Button
              Container(
                margin: const EdgeInsets.all(16),
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for course info in drawer
  Widget _buildDrawerCourseInfo(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Drawer Item Widget
  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: const Color(0xFFF4B400),
        size: 22,
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
          letterSpacing: -0.1,
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.grey,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    );
  }
}