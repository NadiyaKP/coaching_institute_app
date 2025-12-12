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
import '../service/timer_service.dart'; 
import '../../service/websocket_manager.dart'; 

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
  bool _isInitialLoadComplete = false;
  bool _isFetchingProfile = false;
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
  final TimerService _timerService = TimerService(); 
  bool _isFocusModeActive = false;
  
  // 🆕 Timetable data
  List<dynamic> _timetableDays = [];
  int _currentTimetableIndex = 1; // Default to today (middle index)
  bool _isLoadingTimetable = false;
  
  // 🆕 NEW: Timetable cache keys
  static const String _keyTimetableData = 'timetable_data';
  static const String _keyTimetableLastFetchDate = 'timetable_last_fetch_date';
  static const String _keyTimetableCache = 'timetable_cache';

  // 🆕 REMOVED: All UI timers - using ValueNotifier listeners instead

  // 🆕 WillPopScope handling
  DateTime? _currentBackPressTime;

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
  static const String _keyFirstLoginSubjectsFetched = 'first_login_subjects_fetched';

  // 🆕 Flag to prevent duplicate notification API calls
  bool _isFetchingNotifications = false;

@override
void initState() {
  super.initState();
  
  _pageController = PageController(viewportFraction: 0.75);
  _startAutoScroll();
  
  // Initialize focus mode
  _initializeFocusMode();
  
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver(
    onResumed: () async {
      debugPrint('📱 App resumed - syncing focus mode state');
      await _syncFocusModeState();
    },
  ));
}
  

Future<void> _initializeFocusMode() async {
  // Initialize timer service
  await _timerService.initialize();
  
  // Check focus mode status
  final prefs = await SharedPreferences.getInstance();
  final isFocusActiveInPrefs = prefs.getBool(TimerService.isFocusModeKey) ?? false;
  final today = DateTime.now().toIso8601String().split('T')[0];
  final lastDate = prefs.getString(TimerService.lastDateKey);
  
  // Check and restore focus time if same day
  if (lastDate == today) {
    final savedSeconds = prefs.getInt(TimerService.focusKey) ?? 0;
    final lastStoredSeconds = prefs.getInt(TimerService.lastStoredFocusTimeKey) ?? 0;
    
    // Use the greater value
    final focusSeconds = savedSeconds > lastStoredSeconds ? savedSeconds : lastStoredSeconds;
    
    if (focusSeconds > 0) {
      _timerService.focusTimeToday.value = Duration(seconds: focusSeconds);
      debugPrint('🔄 Initialized focus time: ${focusSeconds}s');
    }
  }
  
  _isFocusModeActive = isFocusActiveInPrefs;
  
  if (mounted) setState(() {});
}

@override
void dispose() {
  _autoScrollTimer?.cancel();
  _autoScrollTimer = null;
  
  _pageController.dispose();
  _scrollController.dispose();
  
  super.dispose();
}

  // 🆕 Format duration for display
  String _formatTimerDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

// 🆕 FIXED: Stop Focus Mode
Future<void> _stopFocusMode() async {
  debugPrint('🛑 Stopping focus mode');
  
  try {
    // Send WebSocket event for focus end
    _sendFocusEndEvent();
    
    // Stop the timer service
    await _timerService.stopFocusMode();
    
    // Update local state
    setState(() {
      _isFocusModeActive = false;
    });
    
    // Navigate back to focus mode entry screen
    if (mounted) {
      await Navigator.of(context).pushReplacementNamed('/focus_mode');
    }
    
  } catch (e) {
    debugPrint('❌ Error stopping focus mode: $e');
  }
}

 Future<void> stopFocusModeForLogout() async {
  debugPrint('⏱️ Focus mode stopped for logout');
  
  // Send WebSocket event for focus end
  _sendFocusEndEvent();
  
  // Stop the timer service
  await _timerService.stopFocusMode();
  
  // Update local state
  _isFocusModeActive = false;
}

  // Method to send focus_end event via WebSocket
  void _sendFocusEndEvent() {
    try {
      // Always try to send the event directly
      WebSocketManager.send({"event": "focus_end"});
      debugPrint('📤 WebSocket event sent: {"event": "focus_end"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_end event: $e');
    }
  }

  Future<bool> _onWillPop() async {
  // Check if student type is Online or Offline
  final isEligibleStudent = studentType.toUpperCase() == 'ONLINE' || 
                             studentType.toUpperCase() == 'OFFLINE';
  
  // Check if focus mode is active
  if (isEligibleStudent && _isFocusModeActive) {
    return await _showExitConfirmationDialog();
  }
  
  // For other cases, allow normal back press behavior
  return true;
}
 
Future<bool> _showExitConfirmationDialog() async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Focus Mode Active'),
      content: const Text('Your focus time will stop on going out of the app. Are you sure you want to exit?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'CANCEL',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop(true);
            await _navigateToFocusModeEntry();
          },
          child: const Text(
            'OK',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
  
  return result ?? false;
}

Future<void> _navigateToFocusModeEntry() async {
  debugPrint('📊 Navigating to focus mode entry');
  
  // Send WebSocket event for focus end
  _sendFocusEndEvent();
  
  // Stop the timer
  await _timerService.stopFocusMode();
  
  // Navigate to focus mode entry screen
  if (mounted) {
    await Navigator.of(context).pushReplacementNamed('/focus_mode');
  }
}

Future<void> _syncFocusModeState() async {
  try {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final isFocusActiveInPrefs = prefs.getBool(TimerService.isFocusModeKey) ?? false;
    
    if (_isFocusModeActive != isFocusActiveInPrefs) {
      debugPrint('🔄 Syncing focus mode state: $_isFocusModeActive -> $isFocusActiveInPrefs');
      
      setState(() {
        _isFocusModeActive = isFocusActiveInPrefs;
      });
    }
  } catch (e) {
    debugPrint('❌ Error syncing focus mode state: $e');
  }
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

  // 🆕 NEW: Check if timetable needs refresh
  Future<bool> _shouldFetchTimetable() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchDate = prefs.getString(_keyTimetableLastFetchDate);
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // If never fetched or fetched on a different day, fetch from API
    return lastFetchDate != today;
  }

  // 🆕 NEW: Load cached timetable data
  Future<void> _loadCachedTimetable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_keyTimetableCache);
      
      if (cachedData != null && cachedData.isNotEmpty) {
        final decodedData = json.decode(cachedData);
        if (decodedData['days'] != null && decodedData['days'] is List) {
          setState(() {
            _timetableDays = decodedData['days'];
            _currentTimetableIndex = 1;
          });
          debugPrint('📅 Loaded cached timetable data (${_timetableDays.length} days)');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading cached timetable: $e');
    }
  }

  // 🆕 NEW: Save timetable data to cache
  Future<void> _saveTimetableToCache(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      await prefs.setString(_keyTimetableCache, json.encode(data));
      await prefs.setString(_keyTimetableLastFetchDate, today);
      
      debugPrint('💾 Saved timetable data to cache for date: $today');
    } catch (e) {
      debugPrint('❌ Error saving timetable to cache: $e');
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
  
  // Only fetch data once during initial load
  if (!_isInitialLoadComplete) {
    _isInitialLoadComplete = true;
    
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
    
    _loadCachedProfileData().then((_) async {
      // 🆕 REMOVED: _storeStartTime() call
      await _fetchProfileData();
      
      // Register device token AFTER profile is fetched
      await _registerDeviceTokenOnce();
      
      // 🆕 NEW: Sync focus mode state after initial load
      await _syncFocusModeState();
      
      // 🆕 MODIFIED: Load timetable with caching logic
      await _loadTimetableWithCache();
    });
  }
}

  // 🆕 MODIFIED: Load timetable with caching logic
  Future<void> _loadTimetableWithCache() async {
    // First load cached data
    await _loadCachedTimetable();
    
    // Check if we need to fetch fresh data
    final shouldFetch = await _shouldFetchTimetable();
    
    if (shouldFetch) {
      debugPrint('📡 Fetching fresh timetable data from API');
      await _fetchTimetableData();
    } else {
      debugPrint('📅 Using cached timetable data');
    }
  }

  // 🆕 MODIFIED: Fetch timetable data with caching
  Future<void> _fetchTimetableData() async {
    if (_isLoadingTimetable) return;
    
    setState(() {
      _isLoadingTimetable = true;
    });
    
    try {
      String accessToken = await _authService.getAccessToken();
      
      if (accessToken.isEmpty) {
        debugPrint('No access token found for timetable');
        return;
      }
      
      final client = _createHttpClientWithCustomCert();
      
      final response = await client.get(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/attendance/time_table/list/?filter=three_day'),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        debugPrint('Timetable API response received');
        
        if (responseData['days'] != null && responseData['days'] is List) {
          // Save to cache
          await _saveTimetableToCache(responseData);
          
          setState(() {
            _timetableDays = responseData['days'];
            _currentTimetableIndex = 1; // Default to today (middle index)
          });
          debugPrint('✅ Loaded and cached ${_timetableDays.length} days of timetable');
        }
      } else {
        debugPrint('Failed to fetch timetable: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching timetable: $e');
    } finally {
      setState(() {
        _isLoadingTimetable = false;
      });
    }
  }

  // 🆕 MODIFIED: Get day label with smaller font
  String _getDayLabel(int index) {
    if (_timetableDays.isEmpty) return '';
    
    if (index == 0) return 'Yesterday';
    if (index == 1) return 'Today';
    if (index == 2) return 'Tomorrow';
    return 'Day ${index + 1}';
  }

  // 🆕 MODIFIED: Format date for display with smaller font
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _refreshData() async {
  debugPrint('🔄 Starting forced refresh...');
  
  // Prevent multiple simultaneous refreshes
  if (isRefreshing) {
    debugPrint('⏳ Refresh already in progress, skipping...');
    return;
  }
  
  setState(() {
    isRefreshing = true;
  });

  try {
    // 🆕 NEW: Sync focus mode state before refreshing
    await _syncFocusModeState();
    
    // Clear device registration flag to force re-registration
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDeviceRegistered);
    debugPrint('🧹 Cleared device registration flag for refresh');

    // Reset notification flag to allow fresh fetch
    _isFetchingNotifications = false;

    // Fetch profile data first
    await _fetchProfileData();
    
    // 🆕 MODIFIED: Force fetch fresh timetable data on refresh
    await _fetchTimetableData();

    // Force refresh subjects data only during manual refresh
    if (subcourseId.isNotEmpty) {
      debugPrint('📚 Force refreshing subjects data for subcourse: $subcourseId');
      await _fetchAndStoreSubjects(forceRefresh: true);
    } else {
      debugPrint('⚠️ No subcourseId available for subjects refresh');
    }
    
    // Fetch notifications with duplicate prevention
    await _fetchUnreadNotifications();
    
    // Register device token (will happen since we cleared the flag)
    await _registerDeviceTokenOnce();
    
    debugPrint('✅ All data refreshed successfully from API');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed successfully!'),
          backgroundColor: AppColors.successGreen,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    debugPrint('❌ Error during refresh: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refresh failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        isRefreshing = false;
      });
    }
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
      await prefs.remove(_keyFirstLoginSubjectsFetched);
      await prefs.remove(_keyTimetableCache);
      await prefs.remove(_keyTimetableLastFetchDate);
      
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
    // Prevent duplicate API calls
    if (_isFetchingProfile) {
      debugPrint('⏳ Profile fetch already in progress, skipping...');
      return;
    }
    
    _isFetchingProfile = true;
    
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

            // 🆕 REMOVED: _storeStartTime() call

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
    } finally {
      _isFetchingProfile = false; 
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
      
      // 🆕 Fetch notifications after device registration
      await _fetchUnreadNotifications();
      
    } catch (e) {
      debugPrint('❌ Error in _registerDeviceTokenOnce: $e');
    }
  }

  Future<void> _fetchAndStoreSubjects({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get subcourse_id and access_token from SharedPreferences
      final String? encryptedId = prefs.getString('profile_subcourse_id');
      final String? accessToken = prefs.getString('accessToken');
      
      if (encryptedId == null || encryptedId.isEmpty) {
        debugPrint('❌ Error: profile_subcourse_id not found in SharedPreferences');
        debugPrint('Available keys: ${prefs.getKeys()}');
        return;
      }

      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ Error: accessToken not found in SharedPreferences');
        debugPrint('Available keys: ${prefs.getKeys()}');
        return;
      }

      // Check if this is first login (flag not set)
      final bool firstLoginSubjectsFetched = prefs.getBool(_keyFirstLoginSubjectsFetched) ?? false;
      
      if (!forceRefresh && firstLoginSubjectsFetched) {
        // Not first login and not forced refresh - use cache if available
        final String? cachedSubjectsData = prefs.getString('subjects_data');
        final String? cachedSubcourseId = prefs.getString('cached_subcourse_id');
        
        if (cachedSubjectsData != null && 
            cachedSubjectsData.isNotEmpty && 
            cachedSubcourseId == encryptedId) {
          debugPrint('✅ Using cached subjects data from SharedPreferences');
          debugPrint('Cached subcourse_id matches current: $encryptedId');
          return;
        }
      }

      // ALWAYS fetch from API during:
      // 1. First login (flag not set)
      // 2. Force refresh (manual refresh)
      // 3. No cached data exists
      debugPrint('📡 ${forceRefresh ? 'FORCE REFRESHING' : firstLoginSubjectsFetched ? 'REFRESHING' : 'FIRST LOGIN - FETCHING'} subjects from API...');
      
      // Encode the subcourse_id
      String encodedId = Uri.encodeComponent(encryptedId);
      
      // Build the API URL
      String apiUrl = '${ApiConfig.baseUrl}/api/course/all/?subcourse_id=$encodedId';
      
      debugPrint('🌐 Fetching subjects from: $apiUrl');
      
      // Make GET request with Bearer token
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('📡 Response Status Code: ${response.statusCode}');
      debugPrint('📡 Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          // Store the complete API response as JSON string
          await prefs.setString('subjects_data', json.encode(responseData));
          
          // Store the subcourse_id to track which data is cached
          await prefs.setString('cached_subcourse_id', encryptedId);
          
          // SET THE FIRST LOGIN FLAG to indicate subjects have been fetched at least once
          await prefs.setBool(_keyFirstLoginSubjectsFetched, true);
          
          // Also store individual subject details for easy access
          final List<dynamic> subjects = responseData['subjects'] ?? [];
          await prefs.setInt('subjects_count', subjects.length);
          
          debugPrint('✅ Subjects data ${forceRefresh ? 'FORCE REFRESHED' : firstLoginSubjectsFetched ? 'REFRESHED' : 'FIRST LOGIN FETCHED'} successfully!');
          debugPrint('📦 Complete API response stored in SharedPreferences');
          debugPrint('📚 Total subjects: ${subjects.length}');
          debugPrint('🎯 Cached for subcourse_id: $encryptedId');
          
          // Print the stored data structure for verification
          final storedData = prefs.getString('subjects_data');
          if (storedData != null) {
            final parsedData = json.decode(storedData);
            debugPrint('📊 Stored data structure:');
            debugPrint('   - success: ${parsedData['success']}');
            debugPrint('   - subjects count: ${parsedData['subjects']?.length ?? 0}');
            if (parsedData['subjects'] != null && parsedData['subjects'].isNotEmpty) {
              debugPrint('   - first subject: ${parsedData['subjects'][0]['title']}');
            }
          }
        } else {
          debugPrint('❌ Error: API returned success: false');
        }
      } else {
        debugPrint('❌ Error: Failed to fetch subjects. Status code: ${response.statusCode}');
        debugPrint('📡 Response Body: ${response.body}');
      }
    } catch (e) {
      debugPrint('💥 Exception occurred while fetching subjects: $e');
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

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            debugPrint('✅ Device token registered successfully');
            
            // After successful device registration, fetch unread notifications
            await _fetchUnreadNotifications();
          } else {
            debugPrint('⚠️ Device registration API returned success: false');
          }
        } else if (response.statusCode == 401) {
          debugPrint('🔐 Unauthorized - token might be expired');
        } else {
          debugPrint('❌ Failed to register device token: ${response.statusCode}');
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

  // Fetch unread notifications with duplicate call prevention
  Future<void> _fetchUnreadNotifications() async {
    try {
      // Prevent duplicate API calls
      if (_isFetchingNotifications) {
        debugPrint('⏳ Notifications fetch already in progress, skipping...');
        return;
      }
      
      _isFetchingNotifications = true;
      debugPrint('📬 Fetching unread notifications...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Get access token for authorization
      String accessToken = await _authService.getAccessToken();
      if (accessToken.isEmpty) {
        debugPrint('❌ Access token not available for fetching notifications');
        _isFetchingNotifications = false;
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
        _isFetchingNotifications = false;
      }
    } catch (e) {
      debugPrint('💥 Error in _fetchUnreadNotifications method: $e');
      _isFetchingNotifications = false;
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

  // 🆕 MODIFIED: Show Focus Mode Dialog with new design
  void _showFocusModeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon and title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.timer,
                        color: AppColors.primaryYellow,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Focus Mode Active',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Timer is running',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // Timer display
                Center(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: _timerService.focusTimeToday,
                    builder: (context, focusTime, _) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primaryYellow.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _formatTimerDuration(focusTime),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryYellow,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Informational text about raise hand
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF43E97B).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF43E97B).withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: const Color(0xFF43E97B),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If you have any doubts during focus session, click "Raise Hand"',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Action buttons
                Row(
                  children: [
                    // Raise Hand Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _raiseHandForDoubt();
                        },
                        icon: const Text('✋', style: TextStyle(fontSize: 18)),
                        label: const Text(
                          'Raise Hand',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF43E97B),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: const Color(0xFF43E97B),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Stop Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _stopFocusMode,
                        icon: const Icon(Icons.stop, size: 20),
                        label: const Text(
                          'Stop',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.errorRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Close button
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

// Send Raise Hand Event via WebSocket
void _raiseHandForDoubt() {
  try {
    // Send the raise_hand event
    WebSocketManager.send({"event": "raise_hand"});
    debugPrint('📤 WebSocket event sent: {"event": "raise_hand"}');
    
    // Show success message with better text
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your doubt has been registered! Your teacher will assist you shortly.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF43E97B),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  } catch (e) {
    debugPrint('❌ Error sending raise_hand event: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to raise hand. Please check your connection.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
          ),
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // Responsive sizing calculations
    double getResponsiveSize(double portraitSize) {
      if (isLandscape) {
        return portraitSize * 0.7;
      }
      return portraitSize;
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.backgroundLight,
        endDrawer: CommonProfileDrawer(
          name: name,
          email: email,
          course: course,
          subcourse: subcourse,
          studentType: studentType,
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
        body: Column(
          children: [
            // 🆕 FIXED HEADER SECTION
            _buildHeaderSection(isLandscape, getResponsiveSize),
            
            // 🆕 SCROLLABLE CONTENT SECTION
            Expanded(
              child: RefreshIndicator(
                key: _refreshIndicatorKey,
                onRefresh: _refreshData,
                color: AppColors.primaryYellow,
                backgroundColor: AppColors.backgroundLight,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🆕 MODIFIED: Timetable Section - Compact and Scrollable
                          if (_timetableDays.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                getResponsiveSize(20),
                                getResponsiveSize(16),
                                getResponsiveSize(20),
                                getResponsiveSize(8),
                              ),
                              child: _buildCompactTimetableCard(getResponsiveSize),
                            ),
                          
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
            ),
          ],
        ),
        // 🆕 MODIFIED: Floating Action Button for Focus Mode with primary yellow color
        floatingActionButton: _isFocusModeActive
            ? FloatingActionButton.extended(
                onPressed: _showFocusModeDialog,
                backgroundColor: AppColors.primaryYellow, // Changed to primary yellow
                foregroundColor: Colors.white,
                elevation: 4,
                icon: ValueListenableBuilder<Duration>(
                  valueListenable: _timerService.focusTimeToday,
                  builder: (context, focusTime, _) {
                    return Stack(
                      children: [
                        const Icon(Icons.timer, size: 24),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.stop,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                label: ValueListenableBuilder<Duration>(
                  valueListenable: _timerService.focusTimeToday,
                  builder: (context, focusTime, _) {
                    return Text(
                      _formatTimerDuration(focusTime),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
        bottomNavigationBar: CommonBottomNavBar(
          currentIndex: _currentIndex,
          onTabSelected: _onTabTapped,
          studentType: studentType,
          scaffoldKey: _scaffoldKey, 
        ),
      ),
    );
  }

Widget _buildCompactTimetableCard(double Function(double) getResponsiveSize) {
  if (_timetableDays.isEmpty || _currentTimetableIndex >= _timetableDays.length) {
    return Container();
  }

  final dayData = _timetableDays[_currentTimetableIndex];
  final entries = dayData['entries'] as List<dynamic>? ?? [];
  final date = dayData['date'] as String? ?? '';
  final dayLabel = _getDayLabel(_currentTimetableIndex);
  
  // Create a PageController for horizontal swiping
  final PageController _subjectPageController = PageController(viewportFraction: 0.9);
  int _currentSubjectPage = 0;

  return Container(
    height: getResponsiveSize(140), // Back to original height
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(getResponsiveSize(12)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: getResponsiveSize(8),
          offset: Offset(0, getResponsiveSize(2)),
        ),
      ],
    ),
    child: Padding(
      padding: EdgeInsets.all(getResponsiveSize(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row - compact
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left arrow
              GestureDetector(
                onTap: _currentTimetableIndex > 0
                    ? () {
                        setState(() {
                          _currentTimetableIndex--;
                          _currentSubjectPage = 0;
                        });
                      }
                    : null,
                child: Container(
                  width: getResponsiveSize(24),
                  height: getResponsiveSize(24),
                  decoration: BoxDecoration(
                    color: _currentTimetableIndex > 0
                        ? AppColors.primaryBlue.withOpacity(0.1)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chevron_left,
                      size: getResponsiveSize(16),
                      color: _currentTimetableIndex > 0
                          ? AppColors.primaryBlue
                          : Colors.grey[300],
                    ),
                  ),
                ),
              ),
              
              // Day and date
              Expanded(
                child: Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '$dayLabel • ',
                          style: TextStyle(
                            fontSize: getResponsiveSize(13),
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        TextSpan(
                          text: _formatDate(date),
                          style: TextStyle(
                            fontSize: getResponsiveSize(11),
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Right arrow
              GestureDetector(
                onTap: _currentTimetableIndex < _timetableDays.length - 1
                    ? () {
                        setState(() {
                          _currentTimetableIndex++;
                          _currentSubjectPage = 0;
                        });
                      }
                    : null,
                child: Container(
                  width: getResponsiveSize(24),
                  height: getResponsiveSize(24),
                  decoration: BoxDecoration(
                    color: _currentTimetableIndex < _timetableDays.length - 1
                        ? AppColors.primaryBlue.withOpacity(0.1)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chevron_right,
                      size: getResponsiveSize(16),
                      color: _currentTimetableIndex < _timetableDays.length - 1
                          ? AppColors.primaryBlue
                          : Colors.grey[300],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: getResponsiveSize(6)),
          
          // Divider
          Container(height: 1, color: Colors.grey[200]),
          
          SizedBox(height: getResponsiveSize(6)),
          
          // Subject area - Takes remaining space
          Expanded(
            child: entries.isNotEmpty
                ? Column(
                    children: [
                      // Subject content area
                      Expanded(
                        child: PageView.builder(
                          controller: _subjectPageController,
                          itemCount: entries.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentSubjectPage = index;
                            });
                          },
                          itemBuilder: (context, subjectIndex) {
                            final entry = entries[subjectIndex];
                            final subjectTitle = entry['subject_title'] ?? '';
                            final topicTitles = (entry['topic_titles'] as List<dynamic>?)?.join(', ') ?? '';
                            
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: getResponsiveSize(2)),
                              child: Container(
                                padding: EdgeInsets.all(getResponsiveSize(8)),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(getResponsiveSize(8)),
                                  border: Border.all(
                                    color: AppColors.primaryBlue.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Subject title row
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(getResponsiveSize(3)),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryBlue.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.book_rounded,
                                            size: getResponsiveSize(10),
                                            color: AppColors.primaryBlue,
                                          ),
                                        ),
                                        SizedBox(width: getResponsiveSize(6)),
                                        Expanded(
                                          child: Text(
                                            subjectTitle,
                                            style: TextStyle(
                                              fontSize: getResponsiveSize(12),
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textDark,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    
                                    SizedBox(height: getResponsiveSize(4)),
                                    
                                    // Topics
                                    if (topicTitles.isNotEmpty && topicTitles.trim().isNotEmpty)
                                      Text(
                                        topicTitles,
                                        style: TextStyle(
                                          fontSize: getResponsiveSize(10),
                                          color: AppColors.textDark,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Dot indicators - only if multiple subjects
                      if (entries.length > 1)
                        SizedBox(
                          height: getResponsiveSize(12),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(entries.length, (index) {
                                return Container(
                                  margin: EdgeInsets.symmetric(horizontal: getResponsiveSize(2)),
                                  width: _currentSubjectPage == index ? getResponsiveSize(6) : getResponsiveSize(4),
                                  height: getResponsiveSize(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentSubjectPage == index
                                        ? AppColors.primaryBlue
                                        : AppColors.primaryBlue.withOpacity(0.3),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Text(
                      'No classes',
                      style: TextStyle(
                        fontSize: getResponsiveSize(11),
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
          ),
        ],
      ),
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
    return Column(
      children: [
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
        ),
      ],
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

  // Action Button Widget
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

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResumed;
  
  _AppLifecycleObserver({required this.onResumed});
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}