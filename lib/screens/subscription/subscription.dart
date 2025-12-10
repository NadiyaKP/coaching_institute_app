import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../service/notification_service.dart';
import '../../common/theme_color.dart';
import '../subscription/subscription_detail.dart';
import '../../common/bottom_navbar.dart';
import '../view_profile.dart';
import '../settings/settings.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final AuthService _authService = AuthService();
  bool isLoading = true;
  List<SubscriptionPlan> plans = [];
  List<StudentSubscription> activeSubscriptions = [];
  String? errorMessage;
  int? selectedPlanIndex;
  
  // Bottom Navigation Bar
  int _currentIndex = 1; // Subscription tab is selected
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _studentType = '';
  
  // Profile data for drawer
  String _userName = '';
  String _userEmail = '';
  bool _profileCompleted = false;
  String _courseName = '';
  String _subcourseName = '';
  
  String? courseId;
  
  // New state variables for active plan popup and expansion
  bool _showActivePlanPopup = false;
  bool _isActivePlanExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadStudentType();
    _loadProfileData();
    _loadCourseId();
    _fetchStudentSubscriptions().then((_) {
      // Show popup if there's an active subscription
      if (activeSubscriptions.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _showActivePlanPopup = true;
          });
        });
      }
    });
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('profile_name') ?? 'User Name';
        _userEmail = prefs.getString('profile_email') ?? '';
        _profileCompleted = prefs.getBool('profile_completed') ?? false;
        _courseName = prefs.getString('profile_course') ?? 'Course';
        _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
      });
    } catch (e) {
      debugPrint('Error loading profile data for drawer: $e');
    }
  }

  Future<void> _loadStudentType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentType = prefs.getString('profile_student_type') ?? '';
    });
  }

  Future<void> _loadCourseId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      courseId = prefs.getString('course_id') ?? 'aNYuWH6tZ2ShfSZZ0-4-zg'; 
    });
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _fetchStudentSubscriptions() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        debugPrint('No access token found');
        _navigateToLogin();
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        Future<http.Response> makeRequest(String token) {
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/subscriptions/list_student_subscriptions/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Student Subscriptions response status: ${response.statusCode}');
        debugPrint('Student Subscriptions response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');

          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            debugPrint('❌ Token refresh failed');
            await _authService.logout();
            _navigateToLogin();
            return;
          }
        }

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          
          setState(() {
            activeSubscriptions = responseData
                .map((sub) => StudentSubscription.fromJson(sub))
                .toList();
          });

          debugPrint('✅ Successfully loaded ${activeSubscriptions.length} active subscriptions');
          
          // After loading subscriptions, fetch the plans
          _fetchSubscriptionPlans();
        } else {
          setState(() {
            errorMessage = 'Failed to load subscriptions';
            isLoading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load subscriptions: ${response.statusCode}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() {
        errorMessage = 'SSL certificate issue';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SSL certificate issue - this is normal in development'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() {
        errorMessage = 'No network connection';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching subscriptions: $e');
      setState(() {
        errorMessage = 'Error loading subscriptions: ${e.toString()}';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchSubscriptionPlans() async {
    try {
      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        debugPrint('No access token found');
        _navigateToLogin();
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        Future<http.Response> makeRequest(String token) {
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/subscriptions/plans/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Subscription Plans response status: ${response.statusCode}');
        debugPrint('Subscription Plans response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');

          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            debugPrint('❌ Token refresh failed');
            await _authService.logout();
            _navigateToLogin();
            return;
          }
        }

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          
          setState(() {
            plans = responseData
                .map((plan) => SubscriptionPlan.fromJson(plan))
                .toList();
            isLoading = false;
          });

          debugPrint('✅ Successfully loaded ${plans.length} subscription plans');
        } else {
          setState(() {
            errorMessage = 'Failed to load subscription plans';
            isLoading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load plans: ${response.statusCode}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() {
        errorMessage = 'SSL certificate issue';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SSL certificate issue - this is normal in development'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() {
        errorMessage = 'No network connection';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching subscription plans: $e');
      setState(() {
        errorMessage = 'Error loading plans: ${e.toString()}';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  // Navigate to View Profile
  void _navigateToViewProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(
          onProfileUpdated: (Map<String, String> updatedData) {
            // Refresh profile data when returning from view profile
            _loadProfileData();
            
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

  void _handleSubscribe(SubscriptionPlan plan) async {
    if (courseId == null || courseId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Course information not found'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Check if user already has an active subscription for this course
    if (activeSubscriptions.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active subscription for this course.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Navigate to subscription detail page
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SubscriptionDetailPage(
          plan: plan,
          courseId: courseId!,
        ),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully subscribed to ${plan.name}'),
          backgroundColor: AppColors.successGreen,
        ),
      );
      
      // Refresh the subscriptions list
      _fetchStudentSubscriptions();
    }
  }

  // Calculate days left until subscription expires
  int _calculateDaysLeft(String endDate) {
    try {
      final end = DateTime.parse(endDate);
      final now = DateTime.now();
      final difference = end.difference(now).inDays;
      return difference >= 0 ? difference : 0;
    } catch (e) {
      return 0;
    }
  }

  // Check if subscription is active (not expired)
  bool _isSubscriptionActive(StudentSubscription subscription) {
    return _calculateDaysLeft(subscription.endDate) > 0;
  }

  // Check subscription status and return appropriate message
  String _getSubscriptionStatusMessage(StudentSubscription subscription) {
    final daysLeft = _calculateDaysLeft(subscription.endDate);
    
    if (daysLeft == 0) {
      return 'Plan Expired. Subscribe Now!';
    } else if (daysLeft <= 3) {
      return 'Only $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left to expire your plan';
    }
    
    return ''; // No special message needed
  }

  // Get status color based on days left
  Color _getStatusColor(StudentSubscription subscription) {
    final daysLeft = _calculateDaysLeft(subscription.endDate);
    
    if (daysLeft == 0) {
      return AppColors.errorRed; // Red for expired
    } else if (daysLeft <= 3) {
      return AppColors.warningOrange; // Orange for warning
    }
    
    return AppColors.successGreen; // Green for active
  }

  // Get status text based on days left
  String _getStatusText(StudentSubscription subscription) {
    final daysLeft = _calculateDaysLeft(subscription.endDate);
    return daysLeft == 0 ? 'Inactive' : 'Active';
  }

  // Get current active subscription (only one should be active at a time)
  StudentSubscription? get _currentActiveSubscription {
    if (activeSubscriptions.isEmpty) return null;
    
    // Return the first subscription (assuming only one active subscription)
    return activeSubscriptions.first;
  }

  // Check if device is in landscape mode
  bool get _isLandscape {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.orientation == Orientation.landscape;
  }

  // Get popup width based on orientation
  double get _popupWidth {
    if (_isLandscape) {
      final mediaQuery = MediaQuery.of(context);
      // For landscape mode, use a smaller percentage of screen width
      // and set a maximum width to prevent it from being too wide
      return mediaQuery.size.width * 0.6 > 500 ? 500 : mediaQuery.size.width * 0.6;
    }
    // For portrait mode, maintain original behavior
    return MediaQuery.of(context).size.width * 0.85;
  }

  // Mark subscription notifications as read
  Future<void> _markSubscriptionNotificationsAsRead() async {
    debugPrint('🔍 _markSubscriptionNotificationsAsRead() called');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Debug: Check all keys in SharedPreferences
      final allKeys = prefs.getKeys();
      debugPrint('🔑 All SharedPreferences keys: $allKeys');
      
      final String? notificationsData = prefs.getString('unread_notifications');
      debugPrint('📝 Raw notifications data from SharedPreferences: $notificationsData');
      
      if (notificationsData == null || notificationsData.isEmpty) {
        debugPrint('📭 No notifications to mark as read');
        return;
      }
      
      // Parse the notifications list
      List<dynamic> notificationsList;
      try {
        notificationsList = json.decode(notificationsData);
        debugPrint('✅ Successfully parsed notifications list: ${notificationsList.length} items');
      } catch (e) {
        debugPrint('❌ Failed to parse notifications JSON: $e');
        return;
      }
      
      if (notificationsList.isEmpty) {
        debugPrint('📭 Notifications list is empty after parsing');
        return;
      }
      
      // Filter notifications for subscription types
      List<String> subscriptionNotificationIds = [];
      
      for (var notification in notificationsList) {
        if (notification['data'] != null) {
          final String type = notification['data']['type']?.toString().toLowerCase() ?? '';
          final String id = notification['id']?.toString() ?? '';
          
          if (type == 'subscription_expired' || type == 'subscription_warning') {
            if (id.isNotEmpty) {
              subscriptionNotificationIds.add(id);
            }
          }
        }
      }
      
      if (subscriptionNotificationIds.isEmpty) {
        debugPrint('📭 No subscription notifications found to mark as read');
        return;
      }
      
      debugPrint('📤 Marking ${subscriptionNotificationIds.length} subscription notifications as read - IDs: $subscriptionNotificationIds');
      
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
        'ids': subscriptionNotificationIds,
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
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✅ Subscription notifications marked as read successfully!');
          
          // Update notification badges
          NotificationService.updateBadges(
            hasUnreadAssignments: NotificationService.badgeNotifier.value['hasUnreadAssignments'] ?? false,
            hasUnreadSubscription: false, // Mark subscription as read
          );
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
          debugPrint('⚠️ Failed to mark subscription notifications as read');
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
      debugPrint('❌ Error marking subscription notifications as read: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
    
    debugPrint('🏁 _markSubscriptionNotificationsAsRead() completed');
  }

  // Bottom Navigation Bar methods
  void _onTabTapped(int index) async {
    // Check for subscription notifications before navigation
    await _markSubscriptionNotificationsAsRead();
    
    if (index == 3) {
      // Profile tab - open drawer
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }
    
    setState(() {
      _currentIndex = index;
    });

    // Use the common helper for navigation logic
    BottomNavBarHelper.handleTabSelection(
      index, 
      context, 
      _studentType,
      _scaffoldKey,
    );
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    // Check for subscription notifications before navigation
    await _markSubscriptionNotificationsAsRead();
    
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (Route<dynamic> route) => false,
    );
    return false; 
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

// Active Plan Popup Widget
Widget _buildActivePlanPopup() {
  final currentSubscription = _currentActiveSubscription;
  if (currentSubscription == null) return const SizedBox.shrink();
  
  final daysLeft = _calculateDaysLeft(currentSubscription.endDate);
  final statusMessage = _getSubscriptionStatusMessage(currentSubscription);
  final statusColor = _getStatusColor(currentSubscription);
  
  return Dialog(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    child: Container(
      width: _popupWidth, // Use responsive width
      constraints: BoxConstraints(
        maxWidth: _isLandscape ? 500 : double.infinity, // Limit max width in landscape
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with close button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isSubscriptionActive(currentSubscription) 
                        ? Icons.verified_rounded 
                        : Icons.error_outline_rounded,
                    color: _isSubscriptionActive(currentSubscription) 
                        ? AppColors.primaryYellow 
                        : AppColors.errorRed,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Current Plan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showActivePlanPopup = false;
                    });
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textGrey,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Course Name
            Text(
              currentSubscription.course,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Plan Details
            _buildPlanDetailRow('Plan', currentSubscription.plan),
            _buildPlanDetailRow('Price', '₹${currentSubscription.planAmount.toStringAsFixed(0)}'),
            _buildPlanDetailRow('Valid Until', _formatDate(currentSubscription.endDate)),
            _buildDaysLeftRow(daysLeft),
            _buildPlanDetailRow('Status', _getStatusText(currentSubscription)),
            
            const SizedBox(height: 16),
            
            // Status Alert
            if (statusMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      daysLeft == 0 ? Icons.error_rounded : Icons.warning_rounded,
                      color: statusColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Explore Plans Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showActivePlanPopup = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Explore Plans',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// New method for Days Left row with conditional color
Widget _buildDaysLeftRow(int daysLeft) {
  Color daysLeftColor = daysLeft > 3 ? AppColors.successGreen : AppColors.errorRed;
  
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Days Left',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textGrey,
          ),
        ),
        Text(
          '$daysLeft days',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: daysLeftColor,
          ),
        ),
      ],
    ),
  );
}

Widget _buildPlanDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textGrey,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundLight,
      endDrawer: CommonProfileDrawer(
        name: _userName,
        email: _userEmail,
        course: _courseName,
        subcourse: _subcourseName,
        studentType: _studentType,
        profileCompleted: _profileCompleted,
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
        child: Stack(
          children: [
            // Main Content
            errorMessage != null
                ? _buildErrorState()
                : isLoading
                    ? _buildSkeletonLoading()
                    : plans.isEmpty
                        ? _buildEmptyState()
                        : _buildPlansContent(),
            
            // Active Plan Popup - Show as overlay
            if (_showActivePlanPopup && _currentActiveSubscription != null)
              const ModalBarrier(
                color: Colors.black54,
                dismissible: false,
              ),
            
            if (_showActivePlanPopup && _currentActiveSubscription != null)
              Center(
                child: SingleChildScrollView( // Added to prevent overflow
                  child: _buildActivePlanPopup(),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: CommonBottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _onTabTapped,
        studentType: _studentType,
        scaffoldKey: _scaffoldKey,
      ),
    );
  }

  // Skeleton Loading Widget
  Widget _buildSkeletonLoading() {
    return Column(
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await _handleDeviceBackButton();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Skeleton Content
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16, 
                  20, 
                  16, 
                  _isLandscape ? 100 : 20, // Extra bottom padding in landscape
                ),
                child: Column(
                  children: [
                    // Skeleton Active Plan Section
                    _buildSkeletonActivePlanSection(),
                    const SizedBox(height: 16),
                    
                    // Skeleton Plan Cards
                    _buildSkeletonPlanCard(),
                    const SizedBox(height: 12),
                    _buildSkeletonPlanCard(),
                    const SizedBox(height: 12),
                    _buildSkeletonPlanCard(),
                    const SizedBox(height: 16),
                    
                    // Skeleton Features Section
                    _buildSkeletonFeaturesSection(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonActivePlanSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildShimmerBox(width: 3, height: 20, radius: 2),
                const SizedBox(width: 10),
                _buildShimmerBox(width: 140, height: 20, radius: 4),
              ],
            ),
            const SizedBox(height: 12),
            _buildSkeletonActivePlanItem(),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonActivePlanItem() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildShimmerBox(width: 40, height: 40, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(width: 120, height: 16, radius: 4),
                const SizedBox(height: 6),
                _buildShimmerBox(width: 180, height: 12, radius: 4),
                const SizedBox(height: 4),
                _buildShimmerBox(width: 150, height: 12, radius: 4),
              ],
            ),
          ),
          _buildShimmerBox(width: 60, height: 24, radius: 6),
        ],
      ),
    );
  }

  Widget _buildSkeletonPlanCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Plan name skeleton
                _buildShimmerBox(width: 100, height: 24, radius: 5),
                // Radio skeleton
                _buildShimmerBox(width: 24, height: 24, radius: 12),
              ],
            ),
            const SizedBox(height: 8),
            // Duration skeleton
            _buildShimmerBox(width: 120, height: 14, radius: 4),
            const SizedBox(height: 16),
            // Price skeleton
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildShimmerBox(width: 30, height: 30, radius: 4),
                const SizedBox(width: 4),
                _buildShimmerBox(width: 80, height: 40, radius: 4),
                const SizedBox(width: 6),
                _buildShimmerBox(width: 60, height: 14, radius: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonFeaturesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildShimmerBox(width: 3, height: 20, radius: 2),
              const SizedBox(width: 10),
              _buildShimmerBox(width: 140, height: 20, radius: 4),
            ],
          ),
          const SizedBox(height: 14),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(isLast: true),
        ],
      ),
    );
  }

  Widget _buildSkeletonFeatureItem({bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          _buildShimmerBox(width: 32, height: 32, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(width: 100, height: 14, radius: 4),
                const SizedBox(height: 4),
                _buildShimmerBox(width: 180, height: 10, radius: 4),
              ],
            ),
          ),
          _buildShimmerBox(width: 16, height: 16, radius: 8),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.grey200,
            AppColors.grey200.withOpacity(0.5),
            AppColors.grey200,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: _ShimmerAnimation(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        // Header Section
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await _handleDeviceBackButton();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.errorRed.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Oops! Something went wrong',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _fetchStudentSubscriptions,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Retry',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        // Header Section
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await _handleDeviceBackButton();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 64,
                    color: AppColors.grey400,
                  ),
                   SizedBox(height: 12),
                   Text(
                    'No Plans Available',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                   SizedBox(height: 6),
                   Text(
                    'There are no subscription plans available at the moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlansContent() {
    return RefreshIndicator(
      onRefresh: _fetchStudentSubscriptions,
      color: AppColors.primaryYellow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
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
                  padding: EdgeInsets.fromLTRB(
                    20, 
                    60, 
                    20, 
                    _isLandscape ? 20 : 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              await _handleDeviceBackButton();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Subscription Plans',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Choose the plan that works best for you',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16, 
                    20, 
                    16, 
                    _isLandscape ? 100 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Subscriptions Section - Collapsible (Show only current active plan)
                      if (_currentActiveSubscription != null) ...[
                        _buildCollapsibleActivePlanSection(),
                        const SizedBox(height: 20),
                      ],

                      // Plans List - Always use list view (no grid)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: plans.length,
                        itemBuilder: (context, index) {
                          final plan = plans[index];
                          final bool isSelected = selectedPlanIndex == index;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildPlanCard(plan, index, isSelected),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Features Section
                      _buildFeaturesSection(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCollapsibleActivePlanSection() {
    final currentSubscription = _currentActiveSubscription;
    if (currentSubscription == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header - Always visible
          GestureDetector(
            onTap: () {
              setState(() {
                _isActivePlanExpanded = !_isActivePlanExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _getStatusColor(currentSubscription),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'My Active Plan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    _isActivePlanExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textGrey,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Content - Only visible when expanded
          if (_isActivePlanExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildActiveSubscriptionCard(currentSubscription),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveSubscriptionCard(StudentSubscription subscription) {
    final daysLeft = _calculateDaysLeft(subscription.endDate);
    final statusMessage = _getSubscriptionStatusMessage(subscription);
    final statusColor = _getStatusColor(subscription);
    final statusText = _getStatusText(subscription);
    final isActive = _isSubscriptionActive(subscription);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isActive ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.course,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${subscription.plan} • ₹${subscription.planAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Valid until: ${_formatDate(subscription.endDate)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          // Status Alert
          if (statusMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    daysLeft == 0 ? Icons.error_rounded : Icons.warning_rounded,
                    color: statusColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusMessage,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPlanIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected 
                ? AppColors.primaryYellow 
                : AppColors.grey200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected 
                  ? AppColors.primaryYellow.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isSelected ? 10 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Plan Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryYellow.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                plan.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryYellow,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${plan.durationInMonths} ${plan.durationInMonths == 1 ? "Month" : "Months"} Access',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Selection Radio
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected 
                                ? AppColors.primaryYellow 
                                : AppColors.grey300,
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: isSelected 
                              ? AppColors.primaryYellow 
                              : Colors.transparent,
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        plan.amount.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '/ ${plan.durationInMonths} ${plan.durationInMonths == 1 ? "month" : "months"}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Only show per month rate for plans with more than 2 months
                  if (plan.durationInMonths > 2) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.trending_down_rounded,
                            size: 13,
                            color: AppColors.successGreen,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '₹${(plan.amount / plan.durationInMonths).toStringAsFixed(0)} per month',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.successGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Subscribe Button
            if (isSelected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ElevatedButton(
                  onPressed: () => _handleSubscribe(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Subscribe Now',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
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
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'All Plans Include',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildFeatureItem(
            icon: Icons.video_library_rounded,
            title: 'Video Classes',
            description: 'Access to all video lectures',
          ),
          _buildFeatureItem(
            icon: Icons.description_rounded,
            title: 'Notes',
            description: 'Comprehensive study notes',
          ),
          _buildFeatureItem(
            icon: Icons.quiz_rounded,
            title: 'Question Papers',
            description: 'Previous year question papers',
          ),
          _buildFeatureItem(
            icon: Icons.assignment_rounded,
            title: 'Mock Tests',
            description: 'Practice with unlimited tests',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryYellow,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.successGreen,
            size: 16,
          ),
        ],
      ),
    );
  }
}

// Custom Clipper for curved header (same as home page)
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 30,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}

// Model class for Subscription Plan
class SubscriptionPlan {
  final String id;
  final String name;
  final int durationInMonths;
  final double amount;
  final String razorpayPlanId;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.durationInMonths,
    required this.amount,
    required this.razorpayPlanId,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      durationInMonths: json['duration_in_months'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      razorpayPlanId: json['razorpay_plan_id'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'duration_in_months': durationInMonths,
      'amount': amount,
      'razorpay_plan_id': razorpayPlanId,
    };
  }
}

// Model class for Student Subscription
class StudentSubscription {
  final String course;
  final String plan;
  final String startDate;
  final String endDate;
  final double planAmount;

  StudentSubscription({
    required this.course,
    required this.plan,
    required this.startDate,
    required this.endDate,
    required this.planAmount,
  });

  factory StudentSubscription.fromJson(Map<String, dynamic> json) {
    return StudentSubscription(
      course: json['course'] ?? '',
      plan: json['plan'] ?? '',
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
      planAmount: (json['plan_amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course': course,
      'plan': plan,
      'start_date': startDate,
      'end_date': endDate,
      'plan_amount': planAmount,
    };
  }
}

// Model class for Subscription Response
class SubscriptionResponse {
  final bool success;
  final int subscriptionId;
  final String razorpaySubscriptionId;
  final String status;
  final String startDate;
  final String endDate;

  SubscriptionResponse({
    required this.success,
    required this.subscriptionId,
    required this.razorpaySubscriptionId,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  factory SubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionResponse(
      success: json['success'] ?? false,
      subscriptionId: json['subscription_id'] ?? 0,
      razorpaySubscriptionId: json['razorpay_subscription_id'] ?? '',
      status: json['status'] ?? '',
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
    );
  }
}

// Shimmer Animation Widget for skeleton loading
class _ShimmerAnimation extends StatefulWidget {
  final Widget child;

  const _ShimmerAnimation({required this.child});

  @override
  __ShimmerAnimationState createState() => __ShimmerAnimationState();
}

class __ShimmerAnimationState extends State<_ShimmerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.7),
                Colors.white.withOpacity(0.3),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * slidePercent - bounds.width,
      0.0,
      0.0,
    );
  }
}

