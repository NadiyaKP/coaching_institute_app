import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/auth_service.dart';
import '../service/api_config.dart';
import 'view_profile.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String phoneNumber = '';
  String countryCode = '+91';
  String name = '';
  String email = '';
  
  // Profile data from API
  String course = '';
  String subcourse = '';
  String subcourseId = '';
  String enrollmentStatus = '';
  String subscriptionType = '';
  String subscriptionEndDate = '';
  bool isSubscriptionActive = false;
  bool profileCompleted = false;
  bool isLoading = true;

  final AuthService _authService = AuthService();

  // SharedPreferences keys
  static const String _keyName = 'profile_name';
  static const String _keyEmail = 'profile_email';
  static const String _keyPhoneNumber = 'profile_phone_number';
  static const String _keyProfileCompleted = 'profile_completed';
  static const String _keyCourse = 'profile_course';
  static const String _keySubcourse = 'profile_subcourse';
  static const String _keySubcourseId = 'profile_subcourse_id';
  static const String _keyEnrollmentStatus = 'profile_enrollment_status';
  static const String _keySubscriptionType = 'profile_subscription_type';
  static const String _keySubscriptionEndDate = 'profile_subscription_end_date';
  static const String _keyIsSubscriptionActive = 'profile_is_subscription_active';



  @override
  void initState() {
    super.initState();
    _storeStartTime(); // Add this line
  }

  // Add this method
  Future<void> _storeStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('start_time') == null) {
      String startTime = DateTime.now().toIso8601String();
      await prefs.setString('start_time', startTime);
      debugPrint('✅ Start timestamp stored on home page: $startTime');
    } else {
      debugPrint('ℹ️ Start timestamp already exists: ${prefs.getString('start_time')}');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      phoneNumber = args['phone_number'] ?? '';
      countryCode = args['country_code'] ?? '+91';
      name = args['name'] ?? '';
      email = args['email'] ?? '';
      
      debugPrint('HomeScreen - Received phone_number: $phoneNumber');
      debugPrint('HomeScreen - Received country_code: $countryCode');
      debugPrint('HomeScreen - Received name: $name');
      debugPrint('HomeScreen - Received email: $email');
    }
    
    // First load cached data, then fetch fresh data
    _loadCachedProfileData();
    _fetchProfileData();
  }

  // Load cached profile data from SharedPreferences
  Future<void> _loadCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        name = prefs.getString(_keyName) ?? name;
        email = prefs.getString(_keyEmail) ?? email;
        phoneNumber = prefs.getString(_keyPhoneNumber) ?? phoneNumber;
        profileCompleted = prefs.getBool(_keyProfileCompleted) ?? false;
        course = prefs.getString(_keyCourse) ?? '';
        subcourse = prefs.getString(_keySubcourse) ?? '';
        subcourseId = prefs.getString(_keySubcourseId) ?? '';
        enrollmentStatus = prefs.getString(_keyEnrollmentStatus) ?? '';
        subscriptionType = prefs.getString(_keySubscriptionType) ?? '';
        subscriptionEndDate = prefs.getString(_keySubscriptionEndDate) ?? '';
        isSubscriptionActive = prefs.getBool(_keyIsSubscriptionActive) ?? false;
      });
      
      // Print cached data to console
      debugPrint('========== CACHED PROFILE DATA ==========');
      debugPrint('Name: ${prefs.getString(_keyName) ?? "N/A"}');
      debugPrint('Email: ${prefs.getString(_keyEmail) ?? "N/A"}');
      debugPrint('Phone Number: ${prefs.getString(_keyPhoneNumber) ?? "N/A"}');
      debugPrint('Profile Completed: ${prefs.getBool(_keyProfileCompleted) ?? false}');
      debugPrint('Course: ${prefs.getString(_keyCourse) ?? "N/A"}');
      debugPrint('Subcourse: ${prefs.getString(_keySubcourse) ?? "N/A"}');
      debugPrint('Subcourse ID: ${prefs.getString(_keySubcourseId) ?? "N/A"}');
      debugPrint('Enrollment Status: ${prefs.getString(_keyEnrollmentStatus) ?? "N/A"}');
      debugPrint('Subscription Type: ${prefs.getString(_keySubscriptionType) ?? "N/A"}');
      debugPrint('Subscription End Date: ${prefs.getString(_keySubscriptionEndDate) ?? "N/A"}');
      debugPrint('Is Subscription Active: ${prefs.getBool(_keyIsSubscriptionActive) ?? false}');
      debugPrint('=========================================');
    } catch (e) {
      debugPrint('Error loading cached profile data: $e');
    }
  }

  // Save profile data to SharedPreferences
  Future<void> _saveProfileDataToCache(Map<String, dynamic> profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString(_keyName, profile['name'] ?? '');
      await prefs.setString(_keyEmail, profile['email'] ?? '');
      await prefs.setString(_keyPhoneNumber, profile['phone_number'] ?? '');
      await prefs.setBool(_keyProfileCompleted, profile['profile_completed'] ?? false);
      
      // Save enrollment data
      if (profile['enrollments'] != null) {
        final enrollments = profile['enrollments'];
        await prefs.setString(_keyCourse, enrollments['course'] ?? '');
        await prefs.setString(_keySubcourse, enrollments['subcourse'] ?? '');
        
        // Handle subcourse_id - it can be String or int
        String subcourseIdValue = '';
        if (enrollments['subcourse_id'] != null) {
          subcourseIdValue = enrollments['subcourse_id'].toString();
        }
        await prefs.setString(_keySubcourseId, subcourseIdValue);
        
        await prefs.setString(_keyEnrollmentStatus, enrollments['status'] ?? '');
        
        debugPrint('Saving Subcourse ID to SharedPreferences: $subcourseIdValue');
      }
      
      // Save subscription data
      if (profile['subscription'] != null) {
        await prefs.setString(_keySubscriptionType, profile['subscription']['type'] ?? '');
        await prefs.setString(_keySubscriptionEndDate, profile['subscription']['end_date'] ?? '');
        await prefs.setBool(_keyIsSubscriptionActive, profile['subscription']['is_active'] ?? false);
      }
      
      debugPrint('Profile data saved to SharedPreferences successfully');
    } catch (e) {
      debugPrint('Error saving profile data to SharedPreferences: $e');
    }
  }

  // Clear cached profile data
  Future<void> _clearCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_keyName);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyPhoneNumber);
      await prefs.remove(_keyProfileCompleted);
      await prefs.remove(_keyCourse);
      await prefs.remove(_keySubcourse);
      await prefs.remove(_keySubcourseId);
      await prefs.remove(_keyEnrollmentStatus);
      await prefs.remove(_keySubscriptionType);
      await prefs.remove(_keySubscriptionEndDate);
      await prefs.remove(_keyIsSubscriptionActive);
      
      debugPrint('Cached profile data cleared');
    } catch (e) {
      debugPrint('Error clearing cached profile data: $e');
    }
  }

  // Create HTTP client with custom certificate handling for development
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // Fetch profile data from API
  Future<void> _fetchProfileData() async {
  try {
    setState(() {
      isLoading = true;
    });

    // Get access token from SharedPreferences
    String accessToken = await _authService.getAccessToken();

    if (accessToken.isEmpty) {
      debugPrint('No access token found');
      _navigateToLogin();
      return;
    }

    // Create HTTP client with custom certificate handling
    final client = _createHttpClientWithCustomCert();

    try {
      // -----------------------------
      // 🔹 Function to make profile API call
      // -----------------------------
      Future<http.Response> makeProfileRequest(String token) {
        return client.get(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/students/get_profile/'),
          headers: {
            ...ApiConfig.commonHeaders,
            'Authorization': 'Bearer $token',
          },
        ).timeout(ApiConfig.requestTimeout);
      }

      // 🟢 Step 1: Try API call with current access token
      var response = await makeProfileRequest(accessToken);

      debugPrint('Get Profile response status: ${response.statusCode}');
      debugPrint('Get Profile response body: ${response.body}');

      // 🟢 Step 2: If token expired (401), try refreshing it
      if (response.statusCode == 401) {
        debugPrint('⚠️ Access token expired, trying refresh...');

        final newAccessToken = await _authService.refreshAccessToken();

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          // Retry the request with the new token
          response = await makeProfileRequest(newAccessToken);
          debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
        } else {
          // Refresh failed — log out user
          debugPrint('❌ Token refresh failed');
          await _authService.logout();
          await _clearCachedProfileData();
          _navigateToLogin();
          return;
        }
      }

      // 🟢 Step 3: Handle API response
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['profile'] != null) {
          final profile = responseData['profile'];

          // Save profile locally
          await _saveProfileDataToCache(profile);

          setState(() {
            name = profile['name'] ?? '';
            email = profile['email'] ?? '';
            phoneNumber = profile['phone_number'] ?? '';
            profileCompleted = profile['profile_completed'] ?? false;

            // Enrollment details
            if (profile['enrollments'] != null) {
              final enrollments = profile['enrollments'];
              course = enrollments['course'] ?? '';
              subcourse = enrollments['subcourse'] ?? '';

              if (enrollments['subcourse_id'] != null) {
                subcourseId = enrollments['subcourse_id'].toString();
              }

              enrollmentStatus = enrollments['status'] ?? '';
              debugPrint('Extracted Subcourse ID from API: $subcourseId');
            }

            // Subscription details
            if (profile['subscription'] != null) {
              subscriptionType = profile['subscription']['type'] ?? '';
              subscriptionEndDate = profile['subscription']['end_date'] ?? '';
              isSubscriptionActive = profile['subscription']['is_active'] ?? false;
            }

            isLoading = false;
          });
        } else {
          debugPrint('Profile data not found in response');
          setState(() => isLoading = false);
        }
      } else {
        debugPrint('Failed to fetch profile: ${response.statusCode}');
        setState(() => isLoading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load profile data: ${response.statusCode}'),
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
    setState(() => isLoading = false);

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
    setState(() => isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No network connection - showing cached data'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } catch (e) {
    debugPrint('Error fetching profile: $e');
    setState(() => isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading profile: ${e.toString()}'),
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

  // Logout API call method with SSL handling
 Future<void> _performLogout() async {
  String? accessToken;
  
  try {
    // Show loading dialog
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

    // Get access token from shared preferences
    accessToken = await _authService.getAccessToken();
    
    // Capture the logout time (end time)
    String endTime = DateTime.now().toIso8601String();
    
    // STEP 1: Send attendance data FIRST (while session is still active)
    await _sendAttendanceData(accessToken, endTime);
    
    // STEP 2: Make logout API call after attendance is recorded
    final client = _createHttpClientWithCustomCert();
    
    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/students/student_logout/'),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Logout response status: ${response.statusCode}');
      debugPrint('Logout response body: ${response.body}');
    } finally {
      client.close();
    }
    
    // Close loading dialog
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    // STEP 3: Clear local data after everything is done
    await _clearLogoutData();
    
  } on HandshakeException catch (e) {
    debugPrint('SSL Handshake error: $e');
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    // Still send attendance data before clearing
    String endTime = DateTime.now().toIso8601String();
    await _sendAttendanceData(accessToken, endTime);
    await _clearLogoutData();
    
  } on SocketException catch (e) {
    debugPrint('Network error: $e');
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    // Still send attendance data before clearing
    String endTime = DateTime.now().toIso8601String();
    await _sendAttendanceData(accessToken, endTime);
    await _clearLogoutData();
    
  } catch (e) {
    debugPrint('Logout error: $e');
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    // Still send attendance data before clearing
    String endTime = DateTime.now().toIso8601String();
    await _sendAttendanceData(accessToken, endTime);
    await _clearLogoutData();
  }
}

// Helper method to send attendance data only
Future<void> _sendAttendanceData(String? accessToken, String endTime) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    String? startTime = prefs.getString('start_time');

    if (startTime != null && accessToken != null && accessToken.isNotEmpty) {
      debugPrint('📤 Preparing API request with timestamps:');
      debugPrint('Start: $startTime, End: $endTime');

      // Remove milliseconds from timestamps to match backend format
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

// Helper method to clear all logout data
Future<void> _clearLogoutData() async {
  try {
    // Clear auth data
    await _authService.logout();
    await _clearCachedProfileData();
    
    // Remove timestamps from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('start_time');
    await prefs.remove('end_time');
    await prefs.remove('last_active_time');
    debugPrint('🗑️ SharedPreferences timestamps cleared');

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate to signup screen and clear all routes
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

// Helper method to send attendance data and perform logout
Future<void> _sendAttendanceAndLogout(String? accessToken, String endTime) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    String? startTime = prefs.getString('start_time');

    if (startTime != null) {
      debugPrint('📤 Preparing API request with timestamps:');
      debugPrint('Start: $startTime, End: $endTime');

      // Remove milliseconds from timestamps to match backend format
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
      debugPrint('⚠️ No start_time found in SharedPreferences');
    }

    // Clear local data
    await _authService.logout();
    await _clearCachedProfileData();
    
    // Remove timestamps from SharedPreferences
    await prefs.remove('start_time');
    await prefs.remove('end_time');
    await prefs.remove('last_active_time');
    debugPrint('🗑️ SharedPreferences timestamps cleared');

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate to signup screen and clear all routes
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  } catch (e) {
    debugPrint('❌ Error in _sendAttendanceAndLogout: $e');
    
    // Still clear local data even if attendance sending fails
    await _authService.logout();
    await _clearCachedProfileData();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout completed (Error: ${e.toString()})'),
          backgroundColor: Colors.red,
        ),
      );
      
      // Navigate to signup screen anyway
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }
}
  // Show logout confirmation dialog
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
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                _performLogout(); // Perform logout
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

  // Navigate to Study Materials screen
  void _navigateToStudyMaterials() {
    Navigator.pushNamed(context, '/study_materials');
  }

  // Navigate to Mock Test screen
  void _navigateToMockTest() {
    Navigator.pushNamed(context, '/mock_test');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Home',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFFF4B400),
        automaticallyImplyLeading: false,
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(
                Icons.account_circle,
                color: Colors.white,
                size: 24,
              ),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildProfileDrawer(context),
      body: SafeArea(
        child: isLoading 
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF4B400)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading profile...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // Welcome message with name from API
                  Text(
                    'Welcome${name.isNotEmpty ? ', $name' : ''}!',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // My Course section (only course and subcourse)
                  if (course.isNotEmpty || subcourse.isNotEmpty) ...[
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.school,
                                  color: Color(0xFFF4B400),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'My Course',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            if (course.isNotEmpty) ...[
                              _buildCourseInfoRow('Course', course),
                              const SizedBox(height: 12),
                            ],
                            
                            if (subcourse.isNotEmpty) ...[
                              _buildCourseInfoRow('Subcourse', subcourse),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],
                  
                  // Study Materials Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToStudyMaterials,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4B400),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 4,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.library_books,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Study Materials',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Mock Test Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _navigateToMockTest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4B400),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 4,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.quiz,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Mock Test',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Profile completion reminder (if profile is not completed)
                  if (!profileCompleted) ...[
                    Card(
                      elevation: 2,
                      color: Colors.orange.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.orange.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Complete your profile to access all features',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildCourseInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

 Widget _buildProfileDrawer(BuildContext context) {
  return Drawer(
    width: MediaQuery.of(context).size.width * 0.65,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4B400), Color(0xFFF39C12)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 48,
                      color: Color(0xFFF4B400),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name.isNotEmpty ? name : 'User Name',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // View Profile Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _navigateToViewProfile();
                },
                icon: const Icon(Icons.person, color: Color(0xFFF4B400), size: 20),
                label: const Text(
                  'View Profile',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF4B400),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Settings Button (NEW)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings, color: Color(0xFFF4B400), size: 20),
                label: const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF4B400),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.white, size: 20),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showLogoutDialog();
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  void _navigateToViewProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(
          onProfileUpdated: (Map<String, String> updatedData) {
            // Handle the updated profile data and refresh from API
            _fetchProfileData(); // Refresh data from API
            
            // Optionally show a success message
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
}