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
import '../screens/video_stream/videos.dart';
import '../common/theme_color.dart';
import 'dart:async';
import '../screens/subscription/subscription.dart';
import 'streak_challenge_sheet.dart'; 
import '../common/bottom_navbar.dart'; 
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
  String studentType = ''; 
  bool isSubscriptionActive = false;
  bool profileCompleted = false;
  bool isLoading = true;
  bool _isCourseExpanded = false;
  String streakDays = '0';
  int currentStreak = 0;  
  int longestStreak = 0;

  // PageView and Auto-scroll variables
  PageController _pageController = PageController(viewportFraction: 0.75);
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  // Bottom Navigation Bar
  int _currentIndex = 0;

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
  static const String _keyStudentType = 'profile_student_type';
  static const String _keyCurrentStreak = 'profile_current_streak'; 
  static const String _keyLongestStreak = 'profile_longest_streak'; 

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _storeStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    
    final String currentStudentType = studentType.isNotEmpty 
        ? studentType 
        : (prefs.getString('profile_student_type') ?? '');
    
    final bool isOnlineStudent = currentStudentType.toUpperCase() == 'ONLINE';
    
    if (!isOnlineStudent) {
      debugPrint('🎯 Skipping start time storage for non-online student (Type: $currentStudentType)');
      return;
    }
    
    if (prefs.getString('start_time') == null) {
      String startTime = DateTime.now().toIso8601String();
      await prefs.setString('start_time', startTime);
      debugPrint('✅ Start timestamp stored on home page: $startTime');
      debugPrint('🎯 Student type confirmed: $currentStudentType');
    } else {
      debugPrint('ℹ️ Start timestamp already exists: ${prefs.getString('start_time')}');
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_pageController.hasClients) {
        int nextPage = _currentPage + 1;
        if (nextPage >= 4) {
          nextPage = 0;
        }
        _currentPage = nextPage;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
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
    
    _loadCachedProfileData().then((_) {
     
      _storeStartTime();
    
      _fetchProfileData();
    });
  }

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
      studentType = prefs.getString(_keyStudentType) ?? '';
      currentStreak = prefs.getInt(_keyCurrentStreak) ?? 0;  
      longestStreak = prefs.getInt(_keyLongestStreak) ?? 0;  
    });
    
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
    debugPrint('Student Type: ${prefs.getString(_keyStudentType) ?? "N/A"}');
    debugPrint('Current Streak: ${prefs.getInt(_keyCurrentStreak) ?? 0}');  
    debugPrint('Longest Streak: ${prefs.getInt(_keyLongestStreak) ?? 0}');  
    debugPrint('=========================================');
  } catch (e) {
    debugPrint('Error loading cached profile data: $e');
  }
}

 Future<void> _saveProfileDataToCache(Map<String, dynamic> profile) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString(_keyName, profile['name'] ?? '');
    await prefs.setString(_keyEmail, profile['email'] ?? '');
    await prefs.setString(_keyPhoneNumber, profile['phone_number'] ?? '');
    await prefs.setBool(_keyProfileCompleted, profile['profile_completed'] ?? false);
    
    // Save student type
    if (profile['student_type'] != null) {
      await prefs.setString(_keyStudentType, profile['student_type']);
      debugPrint('Saving Student Type to SharedPreferences: ${profile['student_type']}');
    }
    
    // Save streak data
    if (profile['streak'] != null) {
      final streak = profile['streak'];
      await prefs.setInt(_keyCurrentStreak, streak['current_streak'] ?? 0);
      await prefs.setInt(_keyLongestStreak, streak['longest_streak'] ?? 0);
      debugPrint('Saving Streak to SharedPreferences: Current=${streak['current_streak']}, Longest=${streak['longest_streak']}');
    }
    
    // Save enrollment data
    if (profile['enrollments'] != null) {
      final enrollments = profile['enrollments'];
      await prefs.setString(_keyCourse, enrollments['course'] ?? '');
      await prefs.setString(_keySubcourse, enrollments['subcourse'] ?? '');
      
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
      await prefs.remove(_keyStudentType);
      await prefs.remove(_keyCurrentStreak); 
      await prefs.remove(_keyLongestStreak);  
      
      debugPrint('Cached profile data cleared');
    } catch (e) {
      debugPrint('Error clearing cached profile data: $e');
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

 Future<void> _fetchProfileData() async {
  try {
    setState(() {
      isLoading = true;
    });

    String accessToken = await _authService.getAccessToken();

    if (accessToken.isEmpty) {
      debugPrint('No access token found');
      _navigateToLogin();
      return;
    }

    final client = _createHttpClientWithCustomCert();

    try {
      Future<http.Response> makeProfileRequest(String token) {
        return client.get(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/students/get_profile/'),
          headers: {
            ...ApiConfig.commonHeaders,
            'Authorization': 'Bearer $token',
          },
        ).timeout(ApiConfig.requestTimeout);
      }

      var response = await makeProfileRequest(accessToken);

      debugPrint('Get Profile response status: ${response.statusCode}');
      debugPrint('Get Profile response body: ${response.body}');

      if (response.statusCode == 401) {
        debugPrint('⚠️ Access token expired, trying refresh...');

        final newAccessToken = await _authService.refreshAccessToken();

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          response = await makeProfileRequest(newAccessToken);
          debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
        } else {
          debugPrint('❌ Token refresh failed');
          await _authService.logout();
          await _clearCachedProfileData();
          _navigateToLogin();
          return;
        }
      }

      if (response.statusCode == 200) {
  final responseData = json.decode(response.body);

  if (responseData['success'] == true && responseData['profile'] != null) {
    final profile = responseData['profile'];

    await _saveProfileDataToCache(profile);

    setState(() {
      name = profile['name'] ?? '';
      email = profile['email'] ?? '';
      phoneNumber = profile['phone_number'] ?? '';
      profileCompleted = profile['profile_completed'] ?? false;
      studentType = profile['student_type'] ?? '';

      // Streak data
      if (profile['streak'] != null) {
        currentStreak = profile['streak']['current_streak'] ?? 0;
        longestStreak = profile['streak']['longest_streak'] ?? 0;
      }

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

          // Store start time AFTER we have the student type from API
          _storeStartTime();

          // After fetching profile data, fetch subjects data
          if (subcourseId.isNotEmpty) {
            await _fetchAndStoreSubjects();
          }

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

  // Fetch subjects from API and store in SharedPreferences
  Future<void> _fetchAndStoreSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get subcourse_id and access_token from SharedPreferences
      final String? encryptedId = prefs.getString('profile_subcourse_id');
      final String? accessToken = prefs.getString('accessToken');
      
      if (encryptedId == null || encryptedId.isEmpty) {
        print('Error: profile_subcourse_id not found in SharedPreferences');
        print('Available keys: ${prefs.getKeys()}');
        return;
      }

      if (accessToken == null || accessToken.isEmpty) {
        print('Error: accessToken not found in SharedPreferences');
        print('Available keys: ${prefs.getKeys()}');
        return;
      }

      // Check if subjects data already exists in SharedPreferences for this subcourse_id
      final String? cachedSubjectsData = prefs.getString('subjects_data');
      final String? cachedSubcourseId = prefs.getString('cached_subcourse_id');
      
      if (cachedSubjectsData != null && 
          cachedSubjectsData.isNotEmpty && 
          cachedSubcourseId == encryptedId) {
        print('✅ Using cached subjects data from SharedPreferences');
        print('Cached subcourse_id matches current: $encryptedId');
        return;
      }

      // No cached data or subcourse_id changed, fetch from API
      print('📡 No cached data found or subcourse_id changed. Fetching from API...');
      
      // Encode the subcourse_id
      String encodedId = Uri.encodeComponent(encryptedId);
      
      // Build the API URL
      String apiUrl = '${ApiConfig.baseUrl}/api/course/all/?subcourse_id=$encodedId';
      
      print('Fetching subjects from: $apiUrl');
      
      // Make GET request with Bearer token
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      print('Response Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          // Store the entire subjects data as JSON string
          await prefs.setString('subjects_data', json.encode(responseData['subjects']));
          
          // Store the subcourse_id to track which data is cached
          await prefs.setString('cached_subcourse_id', encryptedId);
          
          // Also store individual subject details for easy access
          final List<dynamic> subjects = responseData['subjects'];
          await prefs.setInt('subjects_count', subjects.length);
          
          print('✅ Subjects data stored successfully!');
          print('Total subjects: ${subjects.length}');
          print('Cached for subcourse_id: $encryptedId');
        } else {
          print('Error: API returned success: false');
        }
      } else {
        print('Error: Failed to fetch subjects. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Exception occurred while fetching subjects: $e');
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
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      await _clearLogoutData();
      
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      String endTime = DateTime.now().toIso8601String();
      await _sendAttendanceData(accessToken, endTime);
      await _clearLogoutData();
      
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      String endTime = DateTime.now().toIso8601String();
      await _sendAttendanceData(accessToken, endTime);
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
    
    // Check student type dynamically
    final studentType = prefs.getString('profile_student_type') ?? '';
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
      await _clearCachedProfileData();
      
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

  // Navigation methods
  void _navigateToStudyMaterials() {
    Navigator.pushNamed(context, '/study_materials');
  }

  void _navigateToMockTest() {
    Navigator.pushNamed(context, '/mock_test');
  }

  void _navigateToSubscription() {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => const SubscriptionScreen(),
       ),
     );
   }

  void _navigateToVideoClasses() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VideosScreen(),
      ),
    );
  }

  void _navigateToNotes() {
    Navigator.pushNamed(context, '/notes');
  }

  void _navigateToQuestionPapers() {
    Navigator.pushNamed(context, '/question_papers');
  }

  void _navigateToReferenceVideos() {
    Navigator.pushNamed(context, '/video_classes');
  }

  void _navigateToPerformance() {
    Navigator.pushNamed(context, '/performance');
  }

  // Bottom Navigation Bar methods 
  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Use the common helper for navigation logic
    BottomNavBarHelper.handleTabSelection(
      index, 
      context, 
      studentType,
      _scaffoldKey, // Pass scaffold key instead of function
    );
  }

  void _navigateToExamSchedule() {
    Navigator.pushNamed(context, '/exam_schedule');
  }

  void _navigateToStudent() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Student dashboard coming soon!'),
        backgroundColor: Color(0xFF43E97B),
      ),
    );
  }

  void _navigateToViewProfile() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(
          onProfileUpdated: (Map<String, String> updatedData) {
            _fetchProfileData(); // Refresh data from API
            
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
        onViewProfile: _navigateToViewProfile,
        onSettings: () {
          Navigator.of(context).pop(); 
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SettingsScreen(),
            ),
          );
        },
        onLogout: () {
          Navigator.of(context).pop();
          _showLogoutDialog();
        },
        onClose: () {
          Navigator.of(context).pop(); 
        },
      ),
      body: Stack(
        children: [
          // Main scrollable content
          Column(
            children: [
              // Non-scrollable Header Section with Curved Bottom
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
                      const SizedBox(height: 0),
                      // Welcome Text with Streak
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Welcome, '),
                                      TextSpan(
                                        text: name.isNotEmpty 
                                          ? name.split(' ').first 
                                          : 'Student',
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Everything you need to learn in one place',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.88),
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Streak Display 
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => StreakChallengeSheet(
                                  currentStreak: currentStreak,
                                  longestStreak: longestStreak,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '🔥',
                                    style: TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$currentStreak',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Course and Subcourse Info 
                      if (course.isNotEmpty || subcourse.isNotEmpty)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    letterSpacing: -0.1,
                                  ),
                                  children: [
                                    if (course.isNotEmpty)
                                      TextSpan(
                                        text: course,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (course.isNotEmpty && subcourse.isNotEmpty)
                                      const TextSpan(
                                        text: ' • ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (subcourse.isNotEmpty)
                                      TextSpan(
                                        text: subcourse,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.85),
                                        ),
                                      ),
                                  ],
                                ),
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
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quick Access Section
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryYellow,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Quick Access',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Scrollable Quick Access Cards
                      SizedBox(
                        height: 150,
                        child: PageView(
                          controller: _pageController,
                          physics: const BouncingScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          children: [
                            _buildQuickAccessCard(
                              icon: Icons.description_rounded,
                              title: 'Study Notes',
                              subtitle: 'Comprehensive study materials',
                              color1: AppColors.primaryYellow,
                              color2: AppColors.primaryYellowLight,
                              imagePath: "assets/images/notes.png",
                              onTap: _navigateToNotes,
                            ),
                            _buildQuickAccessCard(
                              icon: Icons.quiz_rounded,
                              title: 'Question Papers',
                              subtitle: 'Previous year papers',
                              color1: AppColors.primaryBlue,
                              color2: AppColors.primaryBlueLight,
                              imagePath: "assets/images/question_papers.png",
                              onTap: _navigateToQuestionPapers,
                            ),
                            _buildQuickAccessCard(
                              icon: Icons.play_circle_filled_rounded,
                              title: 'Video Classes',
                              subtitle: 'Expert lectures and tutorials',
                              color1: AppColors.warningOrange,
                              color2: const Color(0xFFFFAB40),
                              imagePath: "assets/images/video_classes.png",
                              onTap: _navigateToVideoClasses,
                            ),
                            _buildQuickAccessCard(
                              icon: Icons.assignment_rounded,
                              title: 'Mock Tests',
                              subtitle: 'Assess your preparation',
                              color1: const Color(0xFFFFD54F),
                              color2: const Color(0xFFFFE082),
                              imagePath: "assets/images/mock_test.png",
                              onTap: _navigateToMockTest,
                            ),
                          ],
                        ),
                      ),

                      // Page Indicator Dots
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: _currentPage == index ? 10 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentPage == index
                                      ? AppColors.primaryYellow
                                      : AppColors.grey300,
                                ),
                              );
                            }),
                          ),
                        ),
                      ),

                      // Main Action Buttons Section )
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding:  EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Your Learning Tools',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            // First Row: Video Classes and Notes
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.play_circle_filled_rounded,
                                    label: 'Video\nClasses',
                                    color: AppColors.warningOrange,
                                    onTap: _navigateToVideoClasses,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.description_rounded,
                                    label: 'Notes',
                                    color: AppColors.primaryYellow,
                                    onTap: _navigateToNotes,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Second Row: Question Papers and Reference Videos
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.quiz_rounded,
                                    label: 'Question\nPapers',
                                    color: AppColors.primaryBlue,
                                    onTap: _navigateToQuestionPapers,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildActionButton(
                                    icon: Icons.video_library_rounded,
                                    label: 'Reference\nVideos',
                                    color: AppColors.successGreen,
                                    onTap: _navigateToReferenceVideos,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Profile Completion Reminder
                      if (!profileCompleted)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.warningOrange.withOpacity(0.08),
                                  AppColors.warningOrange.withOpacity(0.04),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.warningOrange.withOpacity(0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningOrange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.info_outline_rounded,
                                      color: AppColors.warningOrange,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Complete Your Profile',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.warningOrange,
                                          ),
                                        ),
                                         SizedBox(height: 4),
                                        Text(
                                          'Unlock all features by completing your profile information',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textGrey,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: CommonBottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _onTabTapped,
        studentType: studentType,
        scaffoldKey: _scaffoldKey, 
      ),
    );
  }

  // Quick Access Card Widget
  Widget _buildQuickAccessCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color1,
    required Color color2,
    required VoidCallback onTap,
    required String imagePath,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color1, color2],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: color1.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Row(
              children: [
                // Left side content
                Expanded(
                  flex: 55,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right side image
                Expanded(
                  flex: 45,
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Action Button Widget
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 115,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                height: 1.2,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    
    // Create a quadratic bezier curve for smooth bottom
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