import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/auth_service.dart';
import '../service/api_config.dart';
import 'view_profile.dart';
import 'settings/settings.dart';
import '../screens/video_stream/videos.dart';
import '../common/theme_color.dart';
import 'dart:async';
import '../screens/subscription/subscription.dart';
import 'streak_challenge_sheet.dart'; 
import '../common/bottom_navbar.dart'; 
import '../service/notification_service.dart';
import '../../../service/http_interceptor.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final ScrollController _scrollController = ScrollController();
  
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
  bool isRefreshing = false;
  bool _isCourseExpanded = false;
  String streakDays = '0';
  int currentStreak = 0;  
  int longestStreak = 0;

  // PageView and Auto-scroll variables
  late PageController _pageController;
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
  static const String _keyUnreadNotifications = 'unread_notifications';
  static const String _keyDeviceRegistered = 'device_registered_for_session';

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Helper method to capitalize first letter of each word
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // Get first name with proper capitalization
  String _getFormattedFirstName() {
    if (name.isEmpty) return 'Student';
    final firstName = name.split(' ').first;
    return _capitalizeFirstLetter(firstName);
  }

  // 🆕 Manual refresh trigger
  void triggerRefresh() {
    _refreshIndicatorKey.currentState?.show();
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
    
    // Update page controller based on orientation
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final newViewportFraction = isLandscape ? 0.45 : 0.75;
    
    if (_pageController.viewportFraction != newViewportFraction) {
      _pageController.dispose();
      _pageController = PageController(viewportFraction: newViewportFraction);
      _startAutoScroll();
    }
    
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

  // 🆕 Main refresh method
  Future<void> _refreshData() async {
  setState(() {
    isRefreshing = true;
  });

  try {
    await _fetchProfileData();

    if (subcourseId.isNotEmpty) {
      await _fetchAndStoreSubjects(forceRefresh: true);
    }
    
    await _fetchUnreadNotifications();
    
    debugPrint('✅ All data refreshed successfully from API');
  } catch (e) {
    debugPrint('❌ Error during refresh: $e');
  } finally {
    setState(() {
      isRefreshing = false;
    });
  }
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
      await prefs.remove(_keyUnreadNotifications);
      await prefs.remove(_keyDeviceRegistered);
      
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
    if (!isRefreshing) {
      setState(() {
        isLoading = true;
      });
    }

    String accessToken = await _authService.getAccessToken();

    if (accessToken.isEmpty) {
      debugPrint('No access token found');
      _navigateToLogin();
      return;
    }

    final client = _createHttpClientWithCustomCert();

    try {
      Future<http.Response> makeProfileRequest(String token) {
        return globalHttpClient.get(
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
          // 🆕 During initial load, use cache if available, otherwise fetch from API
          if (subcourseId.isNotEmpty) {
            await _fetchAndStoreSubjects(forceRefresh: false);
          }

          // 🆕 MODIFIED: Register device token only once per session
          await _registerDeviceTokenOnce();

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

Future<void> _registerDeviceTokenOnce() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if device is already registered for this session
    final bool isDeviceRegistered = prefs.getBool(_keyDeviceRegistered) ?? false;
    
    if (isDeviceRegistered) {
      debugPrint('✅ Device already registered for this session, skipping registration');
      
      // Still fetch unread notifications even if device is registered
      await _fetchUnreadNotifications();
      return;
    }
    
    debugPrint('🆕 First time registration for this session, calling device registration API');
    
    // Call device registration API
    await _registerDeviceToken();
    
    // Mark device as registered for this session
    await prefs.setBool(_keyDeviceRegistered, true);
    debugPrint('✅ Device registration flag set for this session');
    
  } catch (e) {
    debugPrint('❌ Error in _registerDeviceTokenOnce: $e');
  }
}


  // 🆕 MODIFIED: Fetch subjects from API and store in SharedPreferences with forceRefresh option
  Future<void> _fetchAndStoreSubjects({bool forceRefresh = false}) async {
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

      // 🆕 Check if we should use cache (only for initial load, not during refresh)
      if (!forceRefresh) {
        final String? cachedSubjectsData = prefs.getString('subjects_data');
        final String? cachedSubcourseId = prefs.getString('cached_subcourse_id');
        
        if (cachedSubjectsData != null && 
            cachedSubjectsData.isNotEmpty && 
            cachedSubcourseId == encryptedId) {
          print('✅ Using cached subjects data from SharedPreferences');
          print('Cached subcourse_id matches current: $encryptedId');
          return;
        }
      }

      // 🆕 ALWAYS fetch from API during refresh OR if no cached data exists
      print('📡 ${forceRefresh ? 'Force refreshing' : 'Fetching'} subjects from API...');
      
      // Encode the subcourse_id
      String encodedId = Uri.encodeComponent(encryptedId);
      
      // Build the API URL
      String apiUrl = '${ApiConfig.baseUrl}/api/course/all/?subcourse_id=$encodedId';
      
      print('Fetching subjects from: $apiUrl');
      
      // Make GET request with Bearer token
      final response = await globalHttpClient.get(
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
          
          print('✅ Subjects data ${forceRefresh ? 'refreshed' : 'stored'} successfully!');
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

  // Register device token for notifications
  Future<void> _registerDeviceToken() async {
    try {
      debugPrint('🚀 Starting device token registration...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Get the device token from SharedPreferences (stored in main.dart)
      final String? deviceToken = prefs.getString('fcm_token');
      
      if (deviceToken == null || deviceToken.isEmpty) {
        debugPrint('❌ Device token not found in SharedPreferences');
        debugPrint('Available SharedPreferences keys: ${prefs.getKeys()}');
        return;
      }

      debugPrint('📱 Found device token in SharedPreferences: $deviceToken');

      // Get access token for authorization
      String accessToken = await _authService.getAccessToken();
      if (accessToken.isEmpty) {
        debugPrint('❌ Access token not available for device registration');
        return;
      }

      debugPrint('✅ Access token available for device registration');

      // Prepare request body
      final Map<String, dynamic> requestBody = {
        "token": deviceToken
      };

      debugPrint('📦 Request body: ${json.encode(requestBody)}');

      final client = _createHttpClientWithCustomCert();

      try {
        final url = Uri.parse('${ApiConfig.currentBaseUrl}/api/notifications/register_device/');
        debugPrint('🌐 Making POST request to: $url');

        // Make POST request to register device
        final response = await client.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: json.encode(requestBody),
        ).timeout(const Duration(seconds: 15));

        debugPrint('📱 Device registration response status: ${response.statusCode}');
        debugPrint('📱 Device registration response body: ${response.body}');
        debugPrint('📱 Device registration response headers: ${response.headers}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            debugPrint('✅ Device token registered successfully');
            
            // After successful device registration, fetch unread notifications
            await _fetchUnreadNotifications();
          } else {
            debugPrint('⚠️ Device registration API returned success: false');
            debugPrint('Response data: $responseData');
          }
        } else if (response.statusCode == 401) {
          debugPrint('🔐 Unauthorized - token might be expired');
          // Try to refresh token and retry
          final newAccessToken = await _authService.refreshAccessToken();
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            debugPrint('🔄 Retrying with refreshed token...');
            await _retryDeviceRegistration(deviceToken, newAccessToken);
          }
        } else {
          debugPrint('❌ Failed to register device token: ${response.statusCode}');
          debugPrint('Response body: ${response.body}');
        }
      } on TimeoutException {
        debugPrint('⏰ Device registration request timed out');
      } on SocketException catch (e) {
        debugPrint('🌐 Network error during device registration: $e');
      } on HandshakeException catch (e) {
        debugPrint('🔒 SSL Handshake error during device registration: $e');
      } catch (e) {
        debugPrint('❌ Unexpected error during device registration: $e');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('💥 Error in _registerDeviceToken method: $e');
    }
  }

  // Fetch unread notifications and store in SharedPreferences
  Future<void> _fetchUnreadNotifications() async {
    try {
      debugPrint('📬 Fetching unread notifications...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Get access token for authorization
      String accessToken = await _authService.getAccessToken();
      if (accessToken.isEmpty) {
        debugPrint('❌ Access token not available for fetching notifications');
        return;
      }

      debugPrint('✅ Access token available for fetching notifications');

      final client = _createHttpClientWithCustomCert();

      try {
        final url = Uri.parse('${ApiConfig.currentBaseUrl}/api/notifications/unread/');
        debugPrint('🌐 Making GET request to: $url');

        // Make GET request to fetch unread notifications
        final response = await client.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        ).timeout(const Duration(seconds: 15));

        debugPrint('📬 Unread notifications response status: ${response.statusCode}');
        debugPrint('📬 Unread notifications response body: ${response.body}');

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          
          // Store the complete response in SharedPreferences
          await prefs.setString(_keyUnreadNotifications, json.encode(responseData));
          
          debugPrint('✅ Unread notifications stored successfully');
          debugPrint('📬 Total unread notifications: ${responseData.length}');
          
          // Print the stored data for verification
          final storedData = prefs.getString(_keyUnreadNotifications);
          debugPrint('💾 Stored notifications data: $storedData');
          
          // Update the notification service with the new data
          _updateNotificationBadges(responseData);
          
        } else if (response.statusCode == 401) {
          debugPrint('🔐 Unauthorized - token might be expired for notifications');
        } else {
          debugPrint('❌ Failed to fetch unread notifications: ${response.statusCode}');
        }
      } on TimeoutException {
        debugPrint('⏰ Unread notifications request timed out');
      } on SocketException catch (e) {
        debugPrint('🌐 Network error during notifications fetch: $e');
      } on HandshakeException catch (e) {
        debugPrint('🔒 SSL Handshake error during notifications fetch: $e');
      } catch (e) {
        debugPrint('❌ Unexpected error during notifications fetch: $e');
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('💥 Error in _fetchUnreadNotifications method: $e');
    }
  }

  // Update notification badges based on the response data
  void _updateNotificationBadges(List<dynamic> notifications) {
    bool hasAssignment = false;
    bool hasExam = false;
    bool hasSubscription = false;
    bool hasVideoLecture = false;

    for (var notification in notifications) {
      if (notification['data'] != null) {
        final String type = notification['data']['type']?.toString().toLowerCase() ?? '';
        
        if (type == 'assignment') {
          hasAssignment = true;
        } else if (type == 'exam') {
          hasExam = true;
        } else if (type == 'subscription') {
          hasSubscription = true;
        } else if (type == 'video_lecture') {
          hasVideoLecture = true;
        }
      }
    }

    debugPrint('🎯 Notification analysis:');
    debugPrint('   - Assignment: $hasAssignment');
    debugPrint('   - Exam: $hasExam');
    debugPrint('   - Subscription: $hasSubscription');
    debugPrint('   - Video Lecture: $hasVideoLecture');

    // Update the notification service
    NotificationService.updateBadges(
      hasUnreadAssignments: hasAssignment || hasExam,
      hasUnreadSubscription: hasSubscription,
      hasUnreadVideoLectures: hasVideoLecture,
    );
  }

  // Retry device registration with new access token
  Future<void> _retryDeviceRegistration(String deviceToken, String newAccessToken) async {
    try {
      debugPrint('🔄 Retrying device registration with new token...');
      
      final Map<String, dynamic> requestBody = {
        "token": deviceToken
      };

      final client = _createHttpClientWithCustomCert();

      try {
        final response = await client.post(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/notifications/register_device/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $newAccessToken',
          },
          body: json.encode(requestBody),
        ).timeout(const Duration(seconds: 10));

        debugPrint('🔄 Retry response status: ${response.statusCode}');
        debugPrint('🔄 Retry response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✅ Device token registered successfully on retry');
          
          // After successful device registration, fetch unread notifications
          await _fetchUnreadNotifications();
        } else {
          debugPrint('❌ Device registration failed on retry: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('❌ Error in retry device registration: $e');
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
    // Clear video lecture badge when user navigates to video classes
    NotificationService.clearVideoLectureBadge();
    
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
      _scaffoldKey,
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
            _fetchProfileData();
            
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Responsive sizing calculations
    double getResponsiveSize(double portraitSize) {
      if (isLandscape) {
        return portraitSize * 0.7;
      }
      return portraitSize;
    }

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
        onClose: () {
          Navigator.of(context).pop(); 
        },
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _refreshData,
        color: AppColors.primaryYellow,
        backgroundColor: AppColors.backgroundLight,
        displacement: 40,
        strokeWidth: 2.5,
        triggerMode: RefreshIndicatorTriggerMode.onEdge,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Scrollable Header Section
            SliverToBoxAdapter(
              child: _buildHeaderSection(isLandscape, getResponsiveSize),
            ),
            
            // Scrollable Content
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Access Section
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      getResponsiveSize(20),
                      isLandscape ? getResponsiveSize(20) : getResponsiveSize(28),
                      getResponsiveSize(20),
                      getResponsiveSize(14),
                    ),
                    child: _buildSectionHeader('Quick Access', getResponsiveSize),
                  ),

                  // Quick Access Cards
                  SizedBox(
                    height: isLandscape ? getResponsiveSize(150) : 150,
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
                          getResponsiveSize: getResponsiveSize,
                          isLandscape: isLandscape,
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.quiz_rounded,
                          title: 'Question Papers',
                          subtitle: 'Previous year Question papers',
                          color1: AppColors.primaryBlue,
                          color2: AppColors.primaryBlueLight,
                          imagePath: "assets/images/question_papers.png",
                          onTap: _navigateToQuestionPapers,
                          getResponsiveSize: getResponsiveSize,
                          isLandscape: isLandscape,
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.play_circle_filled_rounded,
                          title: 'Video Classes',
                          subtitle: 'Expert lectures and tutorials',
                          color1: AppColors.warningOrange,
                          color2: const Color(0xFFFFAB40),
                          imagePath: "assets/images/video_classes.png",
                          onTap: _navigateToVideoClasses,
                          getResponsiveSize: getResponsiveSize,
                          isLandscape: isLandscape,
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.assignment_rounded,
                          title: 'Mock Tests',
                          subtitle: 'Evaluate your preparations',
                          color1: AppColors.primaryBlue,
                          color2: AppColors.primaryBlueLight,
                          imagePath: "assets/images/mock_test.png",
                          onTap: _navigateToMockTest,
                          getResponsiveSize: getResponsiveSize,
                          isLandscape: isLandscape,
                        ),
                      ],
                    ),
                  ),

                  // Page Indicator Dots
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: getResponsiveSize(16)),
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

                  // Main Action Buttons Section
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      getResponsiveSize(20),
                      getResponsiveSize(8),
                      getResponsiveSize(20),
                      getResponsiveSize(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: getResponsiveSize(16)),
                          child: Text(
                            'Your Learning Tools',
                            style: TextStyle(
                              fontSize: getResponsiveSize(18),
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        
                        // Action buttons in responsive grid
                        if (isLandscape)
                          // Landscape: 4 columns
                          Row(
                            children: [
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.play_circle_filled_rounded,
                                  label: 'Video\nClasses',
                                  color: AppColors.warningOrange,
                                  onTap: _navigateToVideoClasses,
                                  showBadge: true,
                                  getResponsiveSize: getResponsiveSize,
                                  isLandscape: isLandscape,
                                ),
                              ),
                              SizedBox(width: getResponsiveSize(12)),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.description_rounded,
                                  label: 'Notes',
                                  color: AppColors.primaryYellow,
                                  onTap: _navigateToNotes,
                                  getResponsiveSize: getResponsiveSize,
                                  isLandscape: isLandscape,
                                ),
                              ),
                              SizedBox(width: getResponsiveSize(12)),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.quiz_rounded,
                                  label: 'Question\nPapers',
                                  color: AppColors.primaryBlue,
                                  onTap: _navigateToQuestionPapers,
                                  getResponsiveSize: getResponsiveSize,
                                  isLandscape: isLandscape,
                                ),
                              ),
                              SizedBox(width: getResponsiveSize(12)),
                              Expanded(
                                child: _buildActionButton(
                                  icon: Icons.video_library_rounded,
                                  label: 'Reference\nVideos',
                                  color: AppColors.successGreen,
                                  onTap: _navigateToReferenceVideos,
                                  getResponsiveSize: getResponsiveSize,
                                  isLandscape: isLandscape,
                                ),
                              ),
                            ],
                          )
                        else
                          // Portrait: 2 columns
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildActionButton(
                                      icon: Icons.play_circle_filled_rounded,
                                      label: 'Video\nClasses',
                                      color: AppColors.warningOrange,
                                      onTap: _navigateToVideoClasses,
                                      showBadge: true,
                                      getResponsiveSize: getResponsiveSize,
                                      isLandscape: isLandscape,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildActionButton(
                                      icon: Icons.description_rounded,
                                      label: 'Notes',
                                      color: AppColors.primaryYellow,
                                      onTap: _navigateToNotes,
                                      getResponsiveSize: getResponsiveSize,
                                      isLandscape: isLandscape,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildActionButton(
                                      icon: Icons.quiz_rounded,
                                      label: 'Question\nPapers',
                                      color: AppColors.primaryBlue,
                                      onTap: _navigateToQuestionPapers,
                                      getResponsiveSize: getResponsiveSize,
                                      isLandscape: isLandscape,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildActionButton(
                                      icon: Icons.video_library_rounded,
                                      label: 'Reference\nVideos',
                                      color: AppColors.successGreen,
                                      onTap: _navigateToReferenceVideos,
                                      getResponsiveSize: getResponsiveSize,
                                      isLandscape: isLandscape,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Profile Completion Reminder
                  if (!profileCompleted && !isLoading)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        getResponsiveSize(20),
                        getResponsiveSize(10),
                        getResponsiveSize(20),
                        getResponsiveSize(30),
                      ),
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
                          borderRadius: BorderRadius.circular(getResponsiveSize(16)),
                          border: Border.all(
                            color: AppColors.warningOrange.withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(getResponsiveSize(16)),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(getResponsiveSize(10)),
                                decoration: BoxDecoration(
                                  color: AppColors.warningOrange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(getResponsiveSize(12)),
                                ),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  color: AppColors.warningOrange,
                                  size: getResponsiveSize(24),
                                ),
                              ),
                              SizedBox(width: getResponsiveSize(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Complete Your Profile',
                                      style: TextStyle(
                                        fontSize: getResponsiveSize(15),
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.warningOrange,
                                      ),
                                    ),
                                    SizedBox(height: getResponsiveSize(4)),
                                    Text(
                                      'Unlock all features by completing your profile information',
                                      style: TextStyle(
                                        fontSize: getResponsiveSize(12),
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

                  SizedBox(height: getResponsiveSize(20)),
                ],
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

  // Build Section Header
  Widget _buildSectionHeader(String title, double Function(double) getResponsiveSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: getResponsiveSize(26),
              decoration: BoxDecoration(
                color: AppColors.primaryYellow,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: getResponsiveSize(12)),
            Text(
              title,
              style: TextStyle(
                fontSize: getResponsiveSize(22),
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build Header Section
  Widget _buildHeaderSection(bool isLandscape, double Function(double) getResponsiveSize) {
    return ClipPath(
      clipper: isLandscape ? null : CurvedHeaderClipper(),
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
          getResponsiveSize(20),
          isLandscape ? getResponsiveSize(40) : getResponsiveSize(60),
          getResponsiveSize(20),
          getResponsiveSize(32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isLandscape) const SizedBox(height: 0),
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
                          style: TextStyle(
                            fontSize: getResponsiveSize(24),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                          children: [
                            const TextSpan(text: 'Welcome, '),
                            TextSpan(
                              text: _getFormattedFirstName(),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: getResponsiveSize(4)),
                      Text(
                        'Everything you need to learn in one place',
                        style: TextStyle(
                          fontSize: getResponsiveSize(13),
                          color: Colors.white.withOpacity(0.88),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: getResponsiveSize(16)),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: getResponsiveSize(12),
                      vertical: getResponsiveSize(8),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(getResponsiveSize(12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🔥',
                          style: TextStyle(fontSize: getResponsiveSize(20)),
                        ),
                        SizedBox(width: getResponsiveSize(6)),
                        Text(
                          '$currentStreak',
                          style: TextStyle(
                            fontSize: getResponsiveSize(16),
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

            SizedBox(height: getResponsiveSize(18)),

            // Course and Subcourse Info 
            if (course.isNotEmpty || subcourse.isNotEmpty)
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(getResponsiveSize(4)),
                    child: Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: getResponsiveSize(20),
                    ),
                  ),
                  SizedBox(width: getResponsiveSize(8)),
                  Expanded(
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: getResponsiveSize(18),
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
    required double Function(double) getResponsiveSize,
    required bool isLandscape,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: getResponsiveSize(8)),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color1, color2],
            ),
            borderRadius: BorderRadius.circular(getResponsiveSize(18)),
            boxShadow: [
              BoxShadow(
                color: color1.withOpacity(0.25),
                blurRadius: getResponsiveSize(12),
                offset: Offset(0, getResponsiveSize(6)),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(getResponsiveSize(18)),
            child: Row(
              children: [
                // Left side content
                Expanded(
                  flex: 55,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      getResponsiveSize(14),
                      getResponsiveSize(14),
                      getResponsiveSize(6),
                      getResponsiveSize(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(getResponsiveSize(6)),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(getResponsiveSize(8)),
                          ),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: getResponsiveSize(18),
                          ),
                        ),
                        SizedBox(height: getResponsiveSize(8)),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: getResponsiveSize(14),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: getResponsiveSize(4)),
                        Flexible(
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: getResponsiveSize(10),
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
                    padding: EdgeInsets.all(getResponsiveSize(6)),
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

  // Action Button Widget with Badge Support and Responsive Sizing
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool showBadge = false,
    required double Function(double) getResponsiveSize,
    required bool isLandscape,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isLandscape ? getResponsiveSize(115) : 115,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(getResponsiveSize(16)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: getResponsiveSize(14),
              offset: Offset(0, getResponsiveSize(4)),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Stack for icon with badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.all(getResponsiveSize(13)),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(getResponsiveSize(14)),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: getResponsiveSize(26),
                  ),
                ),
                // Conditional badge display
                if (showBadge)
                  ValueListenableBuilder<Map<String, bool>>(
                    valueListenable: NotificationService.badgeNotifier,
                    builder: (context, badges, child) {
                      final hasUnread = badges['hasUnreadVideoLectures'] ?? false;
                      if (!hasUnread) return const SizedBox.shrink();
                      
                      return Positioned(
                        right: getResponsiveSize(8),
                        top: getResponsiveSize(8),
                        child: Container(
                          width: getResponsiveSize(10),
                          height: getResponsiveSize(10),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            SizedBox(height: getResponsiveSize(10)),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: getResponsiveSize(12.5),
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