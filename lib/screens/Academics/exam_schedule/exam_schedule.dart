import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../service/auth_service.dart';
import '../../../service/api_config.dart';
import '../../../common/theme_color.dart';
import 'package:intl/intl.dart';
import '../exam_schedule/exam_instruction.dart';
import '../../mock_test/mock_test.dart';
import 'dart:ui' show FontFeature;
import 'dart:async';

class ExamScheduleScreen extends StatefulWidget {
  final String studentType;
  
  const ExamScheduleScreen({
    super.key,
    this.studentType = '', 
  });

  @override
  State<ExamScheduleScreen> createState() => _ExamScheduleScreenState();
}

class _ExamScheduleScreenState extends State<ExamScheduleScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _allExams = [];
  bool _isLoading = true;
  String _errorMessage = '';
  int _currentIndex = 1;
  
  // Tab and filter related variables
  late TabController _tabController;
  String _selectedFilter = 'All';
  
  // Separate filtered lists for each tab
  List<Map<String, dynamic>> _dailyExams = [];
  List<Map<String, dynamic>> _mockExams = [];
  
  // Store filtered versions for each filter type
  Map<String, List<Map<String, dynamic>>> _dailyFilteredCache = {};
  Map<String, List<Map<String, dynamic>>> _mockFilteredCache = {};
  
  // Notification-related variables
  Set<String> _notificationExamIds = {}; // IDs from notifications
  List<Map<String, dynamic>> _unreadNotifications = []; // Complete notification data
  List<int> _examNotificationIds = []; // Store notification IDs for API call
  
  // Timer-related variables
  Timer? _countdownTimer;
  Map<String, Duration> _examCountdowns = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUnreadNotifications(); // Load unread notifications first
    _fetchExamSchedule();
    _setupExamStatusRefresh();
    _setupCountdownTimer(); 
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countdownTimer?.cancel();
    
    // Mark all exams as viewed synchronously before dispose completes
    if (_examNotificationIds.isNotEmpty) {
      _markAllExamsAsViewedSync();
    }
    
    super.dispose();
  }

  void _markAllExamsAsViewedSync() {
    SharedPreferences.getInstance().then((prefs) {
      debugPrint('=== MARKING ALL EXAMS AS VIEWED (SYNC) ===');
      debugPrint('Notification IDs to mark: $_examNotificationIds');
      
      // Remove exam notifications from unread_notifications
      _unreadNotifications.removeWhere((notification) => 
          notification['data'] != null && 
          notification['data']['type'] == 'exam');
      
      // Save updated unread notifications (without exam notifications)
      prefs.setString('unread_notifications', jsonEncode(_unreadNotifications));
      debugPrint('Updated unread notifications saved (exams removed)');
      
      // Send mark_read API request in background
      _sendMarkReadAPI(_examNotificationIds);
      
      debugPrint('=== ALL EXAMS MARKED AS VIEWED ===\n');
    });
  }

  // Load unread notifications from shared preferences
  Future<void> _loadUnreadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? unreadNotificationsJson = prefs.getString('unread_notifications');
      
      if (unreadNotificationsJson != null && unreadNotificationsJson.isNotEmpty) {
        final List<dynamic> notifications = jsonDecode(unreadNotificationsJson);
        debugPrint('Stored unread notifications data: $notifications');
        
        setState(() {
          _unreadNotifications = notifications.cast<Map<String, dynamic>>();
          
          // Extract exam IDs and notification IDs from notifications where type is 'exam'
          _notificationExamIds = _unreadNotifications
              .where((notification) => 
                  notification['data'] != null && 
                  notification['data']['type'] == 'exam' &&
                  notification['data']['exam_id'] != null)
              .map((notification) => notification['data']['exam_id'] as String)
              .toSet();
          
          // Store notification IDs for API call
          _examNotificationIds = _unreadNotifications
              .where((notification) => 
                  notification['data'] != null && 
                  notification['data']['type'] == 'exam' &&
                  notification['data']['exam_id'] != null)
              .map((notification) => notification['id'] as int)
              .toList();
        });
        
        debugPrint('Loaded notification exam IDs: $_notificationExamIds');
        debugPrint('Loaded exam notification IDs for API: $_examNotificationIds');
      } else {
        debugPrint('No unread notifications data found in SharedPreferences');
      }
    } catch (e) {
      debugPrint('Error loading unread notifications: $e');
    }
  }

  // Send mark_read API request
  Future<void> _sendMarkReadAPI(List<int> notificationIds) async {
    debugPrint('🔍 _sendMarkReadAPI() called with IDs: $notificationIds');
    
    try {
      if (notificationIds.isEmpty) {
        debugPrint('📭 No notification IDs to send');
        return;
      }
      
      // Get fresh access token
      final String? accessToken = await _authService.getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ Access token not found');
        return;
      }
      
      // Get base URL
      final String baseUrl = ApiConfig.currentBaseUrl;
      
      if (baseUrl.isEmpty) {
        debugPrint('❌ Base URL is empty');
        return;
      }
      
      // Prepare API endpoint
      final String apiUrl = '$baseUrl/api/notifications/mark_read/';
      
      // Prepare request body
      final Map<String, dynamic> requestBody = {
        'ids': notificationIds,
      };
      
      debugPrint('🌐 Full API URL: $apiUrl');
      debugPrint('📦 Request Body: ${json.encode(requestBody)}');
      
      // Create HTTP client
      final client = IOClient(ApiConfig.createHttpClient());
      
      try {
        debugPrint('📡 Sending POST request to mark exams as read...');
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
          debugPrint('✅ Exam notifications marked as read successfully via API!');
        } else if (response.statusCode == 401) {
          debugPrint('⚠️ Token expired or invalid');
          // Token refresh would be handled by AuthService if needed
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
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
    } catch (e, stackTrace) {
      debugPrint('❌ Error in mark_read API call: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
    
    debugPrint('🏁 _sendMarkReadAPI() completed');
  }

  void _setupCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateExamCountdowns();
        });
      }
    });
  }

  void _updateExamCountdowns() {
    final now = DateTime.now();
    _examCountdowns.clear();
    
    // Update countdowns for all exams
    for (var exam in _allExams) {
      final examStartTime = _getExamStartDateTime(exam);
      if (examStartTime != null) {
        final difference = examStartTime.difference(now);
        
        // Show countdown if exam starts within 1 hour (and hasn't started yet)
        if (difference.isNegative == false && difference.inMinutes <= 60) {
          _examCountdowns[exam['id'] ?? ''] = difference;
        }
      }
    }
  }

  DateTime? _getExamStartDateTime(Map<String, dynamic> exam) {
    try {
      DateTime examDate = DateTime.parse(exam['date']);
      String? startTime = exam['start_time'];
      
      if (startTime != null && startTime != 'None') {
        List<String> startParts = startTime.split(':');
        return DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
          startParts.length > 2 ? int.parse(startParts[2]) : 0,
        );
      }
    } catch (e) {
      debugPrint('Error getting exam start time: $e');
    }
    return null;
  }

  String _formatCountdown(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _setupExamStatusRefresh() {
    // Refresh exam status every minute to update button states
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        setState(() {
          // Force rebuild to update exam status
        });
        _setupExamStatusRefresh();
      }
    });
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _fetchExamSchedule() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        debugPrint('No access token found');
        _navigateToLogin();
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        Future<http.Response> makeExamRequest(String token) {
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/attendance/exams/view/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeExamRequest(accessToken);

        debugPrint('Exam Schedule response status: ${response.statusCode}');
        debugPrint('Exam Schedule response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');

          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeExamRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            debugPrint('❌ Token refresh failed');
            await _authService.logout();
            _navigateToLogin();
            return;
          }
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);

          if (responseData['success'] == true && responseData['exams'] != null) {
            setState(() {
              _allExams = List<Map<String, dynamic>>.from(responseData['exams']);
              _categorizeAndCacheExams();
              _isLoading = false;
            });
          } else {
            setState(() {
              _errorMessage = 'No exams found';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = 'Failed to load exam schedule';
            _isLoading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load exam schedule: ${response.statusCode}'),
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
        _errorMessage = 'SSL certificate issue';
        _isLoading = false;
      });
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() {
        _errorMessage = 'No network connection';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching exam schedule: $e');
      setState(() {
        _errorMessage = 'Error loading exam schedule';
        _isLoading = false;
      });
    }
  }

  void _categorizeAndCacheExams() {
    // Clear existing lists
    _dailyExams.clear();
    _mockExams.clear();
    _dailyFilteredCache.clear();
    _mockFilteredCache.clear();
    
    // Categorize exams by type
    for (var exam in _allExams) {
      String examType = exam['exam_type']?.toString().toUpperCase() ?? 'DAILY';
      if (examType == 'MOCK') {
        _mockExams.add(exam);
      } else {
        _dailyExams.add(exam);
      }
    }
    
    // Sort both lists
    _sortExams(_dailyExams);
    _sortExams(_mockExams);
    
    // Cache filtered versions for all filter types
    _cacheFilteredExams();
  }

  void _cacheFilteredExams() {
    // Cache for Daily Exams
    _dailyFilteredCache['All'] = _dailyExams;
    _dailyFilteredCache['Today'] = _filterExamsByDate(_dailyExams, 'Today');
    _dailyFilteredCache['Upcoming'] = _filterExamsByDate(_dailyExams, 'Upcoming');
    _dailyFilteredCache['Past'] = _filterExamsByDate(_dailyExams, 'Past');
    
    // Cache for Mock Exams
    _mockFilteredCache['All'] = _mockExams;
    _mockFilteredCache['Today'] = _filterExamsByDate(_mockExams, 'Today');
    _mockFilteredCache['Upcoming'] = _filterExamsByDate(_mockExams, 'Upcoming');
    _mockFilteredCache['Past'] = _filterExamsByDate(_mockExams, 'Past');
  }

  void _sortExams(List<Map<String, dynamic>> examList) {
    // Sort exams: NEW exams first, then active, then upcoming, then past
    examList.sort((a, b) {
      String aExamId = a['id'] ?? '';
      String bExamId = b['id'] ?? '';
      
      // Check if exams are new (from notifications)
      bool aIsNew = _notificationExamIds.contains(aExamId);
      bool bIsNew = _notificationExamIds.contains(bExamId);
      
      // NEW exams always come first
      if (aIsNew && !bIsNew) return -1;
      if (!aIsNew && bIsNew) return 1;
      
      bool aIsActive = _isExamActive(a);
      bool bIsActive = _isExamActive(b);
      
      if (aIsActive && !bIsActive) return -1;
      if (!aIsActive && bIsActive) return 1;
      
      // If both are active or both are not active, sort by date
      DateTime dateA = DateTime.parse(a['date']);
      DateTime dateB = DateTime.parse(b['date']);
      
      // For active exams, we want the ones ending sooner first
      if (aIsActive && bIsActive) {
        return _getExamEndTime(a).compareTo(_getExamEndTime(b));
      }
      
      // For non-active exams, upcoming come before past, and within each category, sort by date
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime examDayA = DateTime(dateA.year, dateA.month, dateA.day);
      DateTime examDayB = DateTime(dateB.year, dateB.month, dateB.day);
      
      bool aIsUpcoming = examDayA.isAfter(today) || (examDayA.isAtSameMomentAs(today) && !aIsActive && !_isExamPast(a));
      bool bIsUpcoming = examDayB.isAfter(today) || (examDayB.isAtSameMomentAs(today) && !bIsActive && !_isExamPast(b));
      bool aIsPast = _isExamPast(a);
      bool bIsPast = _isExamPast(b);
      
      if (aIsUpcoming && bIsPast) return -1;
      if (aIsPast && bIsUpcoming) return 1;
      
      // Within same category, sort by date
      if (aIsUpcoming && bIsUpcoming) {
        return dateA.compareTo(dateB); // Sooner dates first for upcoming
      } else {
        return dateB.compareTo(dateA); // More recent first for past
      }
    });
  }

  List<Map<String, dynamic>> _filterExamsByDate(List<Map<String, dynamic>> exams, String filter) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    switch (filter) {
      case 'Today':
        return exams.where((exam) {
          DateTime examDate = DateTime.parse(exam['date']);
          DateTime examDay = DateTime(examDate.year, examDate.month, examDate.day);
          return examDay.isAtSameMomentAs(today);
        }).toList();
      case 'Upcoming':
        return exams.where((exam) {
          DateTime examDate = DateTime.parse(exam['date']);
          DateTime examDay = DateTime(examDate.year, examDate.month, examDate.day);
          return examDay.isAfter(today) || 
                 (examDay.isAtSameMomentAs(today) && 
                  !_isExamActive(exam) &&
                  !_isExamPast(exam));
        }).toList();
      case 'Past':
        return exams.where((exam) {
          return _isExamPast(exam);
        }).toList();
      default: // All
        return exams;
    }
  }

  List<Map<String, dynamic>> _getFilteredExams(bool isDailyTest) {
    final cache = isDailyTest ? _dailyFilteredCache : _mockFilteredCache;
    return cache[_selectedFilter] ?? (isDailyTest ? _dailyExams : _mockExams);
  }

  DateTime _getExamEndTime(Map<String, dynamic> exam) {
    try {
      DateTime examDate = DateTime.parse(exam['date']);
      String? endTime = exam['end_time'];
      if (endTime != null && endTime != 'None') {
        List<String> endParts = endTime.split(':');
        return DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
          endParts.length > 2 ? int.parse(endParts[2]) : 0,
        );
      }
    } catch (e) {
      debugPrint('Error getting exam end time: $e');
    }
    return DateTime.parse(exam['date']);
  }

  void _filterExams(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  bool _isExamActive(Map<String, dynamic> exam) {
    String date = exam['date'];
    String? startTime = exam['start_time'];
    String? endTime = exam['end_time'];

    if (startTime == null || startTime == 'None') return false;

    try {
      DateTime now = DateTime.now();
      DateTime examDate = DateTime.parse(date);
      
      // Parse start time
      List<String> startParts = startTime.split(':');
      DateTime startDateTime = DateTime(
        examDate.year,
        examDate.month,
        examDate.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
        startParts.length > 2 ? int.parse(startParts[2]) : 0,
      );

      // If end_time is provided and not 'None', check if current time is between start and end
      if (endTime != null && endTime != 'None') {
        List<String> endParts = endTime.split(':');
        DateTime endDateTime = DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
          endParts.length > 2 ? int.parse(endParts[2]) : 0,
        );

        return now.isAfter(startDateTime) && now.isBefore(endDateTime);
      } else {
        // If no end_time or end_time is 'None', exam is active for the entire day after start time
        DateTime endOfDay = DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
          23, 59, 59
        );
        
        return now.isAfter(startDateTime) && now.isBefore(endOfDay);
      }
    } catch (e) {
      debugPrint('Error checking exam active status: $e');
      return false;
    }
  }

  bool _isExamPast(Map<String, dynamic> exam) {
    String date = exam['date'];
    String? endTime = exam['end_time'];

    try {
      DateTime now = DateTime.now();
      DateTime examDate = DateTime.parse(date);
      
      // If end_time is provided and not 'None', check if current time is after end time
      if (endTime != null && endTime != 'None') {
        List<String> endParts = endTime.split(':');
        DateTime endDateTime = DateTime(
          examDate.year,
          examDate.month,
          examDate.day,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
          endParts.length > 2 ? int.parse(endParts[2]) : 0,
        );

        return now.isAfter(endDateTime);
      } else {
        // If no end_time or end_time is 'None', exam is past after the exam date ends
        DateTime nextDay = DateTime(
          examDate.year,
          examDate.month,
          examDate.day + 1, // Next day at 00:00:00
        );
        
        return now.isAfter(nextDay);
      }
    } catch (e) {
      debugPrint('Error checking exam past status: $e');
      
      // Fallback: check if the date is before today
      DateTime examDate = DateTime.parse(date);
      DateTime today = DateTime.now();
      DateTime examDay = DateTime(examDate.year, examDate.month, examDate.day);
      DateTime currentDay = DateTime(today.year, today.month, today.day);
      return examDay.isBefore(currentDay);
    }
  }
void _navigateToExamInstruction(Map<String, dynamic> exam) async {
  String examId = exam['id'] ?? '';
  bool isNewExam = _notificationExamIds.contains(examId);
  
  // Check if student is offline
  bool isOfflineStudent = widget.studentType.toLowerCase() == 'offline';
  
  if (isOfflineStudent) {
    // For offline students, just mark as viewed without navigation
    if (isNewExam) {
      // Remove the exam ID from notification set immediately for UI update
      setState(() {
        _notificationExamIds.remove(examId);
      });
      
      // Update the cached filtered lists to reflect the change
      _categorizeAndCacheExams();
    }
    
    // Show a message that offline students cannot access online exams
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Exam details are not available for offline students'),
          backgroundColor: AppColors.warningOrange,
          duration: Duration(seconds: 2),
        ),
      );
    }
    return; // Exit without navigation
  }
  
  // For online students, proceed with normal navigation
  // If this exam has NEW badge, remove it from the set
  if (isNewExam) {
    // Remove the exam ID from notification set immediately for UI update
    setState(() {
      _notificationExamIds.remove(examId);
    });
    
    // Update the cached filtered lists to reflect the change
    _categorizeAndCacheExams();
  }
  
  // Navigate to the exam instruction screen
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ExamInstructionScreen(
        examId: exam['id'] ?? '',
        examTitle: exam['title'] ?? 'Untitled Exam',
        examDate: exam['date'] ?? '',
        startTime: exam['start_time'] ?? '',
        endTime: exam['end_time'] ?? '',
        subject: exam['subject'] ?? '',
        isNewExam: isNewExam,
      ),
    ),
  );
  
  // When returning from exam instruction, refresh the data
  if (mounted) {
    await _fetchExamSchedule();
    await _loadUnreadNotifications(); // Reload notifications to update state
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

  void _navigateToMockTest() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MockTestScreen(),
      ),
    );
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0: // Home
        Navigator.pop(context);
        break;
      case 1: // Exam Schedule - already here
        break;
      case 2: // Result
        _navigateToMockTest();
        break;
      case 3: // Profile
        Navigator.pop(context); // Go back to home and open drawer
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Column(
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
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Exam Schedule',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Tabs for Daily Test and Mock Test
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryYellow,
              unselectedLabelColor: AppColors.textGrey,
              indicatorColor: AppColors.primaryYellow,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              tabs: const [
                Tab(text: 'Daily Test'),
                Tab(text: 'Mock Test'),
              ],
            ),
          ),

          // Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Today'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Upcoming'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Past'),
                ],
              ),
            ),
          ),

          // Exam List
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Daily Test Tab Content
                _buildExamList(true),
                // Mock Test Tab Content  
                _buildExamList(false),
              ],
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildExamList(bool isDailyTest) {
  final exams = _getFilteredExams(isDailyTest);
  bool isOfflineStudent = widget.studentType.toLowerCase() == 'offline';
  
  return _isLoading
      ? _buildSkeletonLoading()
      : _errorMessage.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 50,
                    color: AppColors.errorRed,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _fetchExamSchedule,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : exams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 50,
                        color: AppColors.grey400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No exams found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No ${isDailyTest ? 'Daily Test' : 'Mock Test'} exams ${_selectedFilter == 'All' ? '' : _selectedFilter.toLowerCase()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primaryYellow,
                  onRefresh: _fetchExamSchedule,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: exams.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: isOfflineStudent 
                            ? null // Disable tap for offline students
                            : () => _navigateToExamInstruction(exams[index]),
                        child: Opacity(
                          opacity: isOfflineStudent ? 0.6 : 1.0, // Visual feedback for disabled state
                          child: _buildExamCard(exams[index], isDailyTest),
                        ),
                      );
                    },
                  ),
                );
}
  // Skeleton Loading Widget
  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: 4, // Show 4 skeleton items
      itemBuilder: (context, index) {
        return _buildSkeletonCard();
      },
    );
  }

  // Skeleton Card Widget
  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skeleton Header Row
            Row(
              children: [
                // Skeleton Date Badge
                Container(
                  width: 80,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const Spacer(),
                // Skeleton Status Badge
                Container(
                  width: 60,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // Skeleton Title
            Container(
              width: double.infinity,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            
            // Skeleton Subject and Course Info
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.grey300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.grey300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Skeleton Time Info
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => _filterExams(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryYellow : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryYellow : AppColors.grey300,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryYellow.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildExamCard(Map<String, dynamic> exam, bool isDailyTest) {
    DateTime examDate = DateTime.parse(exam['date']);
    String formattedDate = DateFormat('MMM dd, yyyy').format(examDate);
    String? startTime = exam['start_time'];
    String? endTime = exam['end_time'];
    bool isActive = _isExamActive(exam);
    bool isPast = _isExamPast(exam);
    bool isToday = examDate.isToday();
    
    // Check if exam has countdown
    String examId = exam['id'] ?? '';
    Duration? countdown = _examCountdowns[examId];
    bool showCountdown = countdown != null && !isActive && !isPast;
    
    // Check if this exam has a notification (NEW badge)
    bool isNewExam = _notificationExamIds.contains(examId);
    
    // Check if mark is available
    dynamic mark = exam['mark'];
    bool hasMark = mark != null && mark.toString().isNotEmpty;
    
    // Determine card color based on tab
    Color cardColor = isDailyTest ? AppColors.primaryYellow : AppColors.primaryBlue;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isActive
            ? Border.all(color: AppColors.successGreen, width: 1.5)
            : showCountdown
                ? Border.all(color: cardColor, width: 1.5)
                : null,
        boxShadow: [
          BoxShadow(
            color: isActive
                ? AppColors.successGreen.withOpacity(0.15)
                : showCountdown
                    ? cardColor.withOpacity(0.15)
                    : Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPast
                            ? AppColors.grey300
                            : isToday
                                ? cardColor.withOpacity(0.15)
                                : cardColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: isPast
                                ? AppColors.textGrey
                                : isToday
                                    ? cardColor
                                    : cardColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isPast
                                  ? AppColors.textGrey
                                  : isToday
                                      ? cardColor
                                      : cardColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    
                    // Show mark if available
                    if (hasMark)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.grade_rounded,
                              size: 12,
                              color: AppColors.successGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Mark: $mark',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.successGreen,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.successGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Live Now',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.successGreen,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (showCountdown)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Exam starts within',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textGrey,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_rounded,
                                  size: 12,
                                  color: cardColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatCountdown(countdown!),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: cardColor,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // Exam Title
                Text(
                  exam['title'] ?? 'Untitled Exam',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    letterSpacing: -0.2,
                  ),
                ),

                const SizedBox(height: 8),

                // Time Info
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: isPast ? AppColors.textGrey : cardColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        startTime != null && startTime != 'None'
                            ? '${_formatTime(startTime)}${endTime != null && endTime != 'None' ? ' - ${_formatTime(endTime)}' : ''}'
                            : 'Time not specified',
                        style: TextStyle(
                          fontSize: 12,
                          color: isPast ? AppColors.textGrey : AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // NEW Badge in top right corner
          if (isNewExam)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(String time) {
    try {
      if (time == 'None') return 'Not specified';
      
      List<String> parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      
      String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      
      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return time;
    }
  }
}

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

// Extension to check if a date is today
extension DateExtensions on DateTime {
  bool isToday() {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }
}