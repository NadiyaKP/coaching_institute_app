import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import '../../../../service/api_config.dart';
import '../../../../service/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../common/theme_color.dart';
import '../video_stream/video_stream.dart';
import '../../screens/subscription/subscription.dart';
import '../../../service/http_interceptor.dart';

class NavigationState {
  final String pageType; 
  final String subjectId;
  final String subjectName;
  final String? unitId;
  final String? unitName;
  final String? chapterId;
  final String? chapterName;
  final bool hasDirectChapters; 
  final List<dynamic> unitsData; 
  final List<dynamic> chaptersData; 

  NavigationState({
    required this.pageType,
    required this.subjectId,
    required this.subjectName,
    this.unitId,
    this.unitName,
    this.chapterId,
    this.chapterName,
    this.hasDirectChapters = false,
    this.unitsData = const [],
    this.chaptersData = const [],
  });
}

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'subjects'; 
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  String _selectedSubjectName = '';
  String _selectedUnitName = '';
  String _selectedChapterName = '';
  String _studentType = '';
  
  // Data lists
  List<dynamic> _subjects = [];
  List<dynamic> _units = [];
  List<dynamic> _chapters = [];
  List<dynamic> _videos = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;
  String? _selectedUnitId;
  String? _selectedChapterId;

  final AuthService _authService = AuthService();
  late Box _videoEventsBox;
  bool _hiveInitialized = false;

  // Subscription message state
  bool _showSubscriptionMessage = false;
  bool _hasLockedVideos = false;

  // Enhanced navigation stack to track the complete path
  final List<NavigationState> _navigationStack = [];

  // Notification data
  List<dynamic> _notificationData = [];
  List<String> _idsToMarkRead = [];

  // FIX: Add debouncing and tracking for API calls
  bool _isSendingVideoEvents = false;
  DateTime? _lastVideoEventsCallTime;
  static const Duration _videoEventsDebounceTime = Duration(seconds: 10);
  final Set<String> _currentlyProcessingVideoIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    try {
      // Use the same box name as video_stream.dart - 'videoEvents'
      if (!Hive.isBoxOpen('videoEvents')) {
        _videoEventsBox = await Hive.openBox('videoEvents');
      } else {
        _videoEventsBox = Hive.box('videoEvents');
      }
      
      _hiveInitialized = true;
      debugPrint('✅ Hive initialized successfully for videos with box: videoEvents');
      
      // Print current stored data
      _printStoredVideoEvents();
    } catch (e) {
      debugPrint('❌ Error initializing Hive for videos: $e');
      // Try to create the box if it doesn't exist
      try {
        _videoEventsBox = await Hive.openBox('videoEvents');
        _hiveInitialized = true;
        debugPrint('✅ Created new videoEvents box');
      } catch (e2) {
        debugPrint('❌ Failed to create videoEvents box: $e2');
      }
    }
    
    _initializeData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🎬 VideoScreen Lifecycle State Changed: $state');
    
    // Send stored data when app goes to background (minimized or device locked)
    // Only for online students
    if (_studentType.toLowerCase() == 'online') {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        debugPrint('🎬 App going to background - sending video events to API');
        _sendStoredVideoEventsToAPI();
      }
    } else {
      debugPrint('🎬 Student type is $_studentType - skipping video events collection');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType(); // Load student type first
    await _loadNotificationData(); // Load notification data
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadDataFromSharedPreferences();
    } else {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
    }
  }

  // Load student type from SharedPreferences
  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _studentType = prefs.getString('profile_student_type') ?? '';
      });
      debugPrint('Student Type loaded: $_studentType');
    } catch (e) {
      debugPrint('Error loading student type: $e');
    }
  }

  // Load notification data from SharedPreferences
  Future<void> _loadNotificationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? notificationDataJson = prefs.getString('unread_notifications');
      
      if (notificationDataJson != null && notificationDataJson.isNotEmpty) {
        final List<dynamic> notificationData = json.decode(notificationDataJson);
        setState(() {
          _notificationData = notificationData;
        });
        debugPrint('✅ Loaded ${_notificationData.length} notification items');
        
        // Load existing IDs to mark read
        final String? idsJson = prefs.getString('ids_to_mark_read');
        if (idsJson != null && idsJson.isNotEmpty) {
          final List<dynamic> idsList = json.decode(idsJson);
          setState(() {
            _idsToMarkRead = idsList.map((id) => id.toString()).toList();
          });
          debugPrint('✅ Loaded ${_idsToMarkRead.length} IDs to mark read');
        }
      } else {
        debugPrint('⚠️ No notification data found in SharedPreferences');
        setState(() {
          _notificationData = [];
        });
      }
    } catch (e) {
      debugPrint('Error loading notification data: $e');
      setState(() {
        _notificationData = [];
      });
    }
  }

  // Save IDs to mark read in SharedPreferences
  Future<void> _saveIdsToMarkRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ids_to_mark_read', json.encode(_idsToMarkRead));
      debugPrint('💾 Saved ${_idsToMarkRead.length} IDs to mark read');
    } catch (e) {
      debugPrint('Error saving IDs to mark read: $e');
    }
  }

  // Remove notification data for a specific video and add to IDs list
  Future<void> _removeNotificationForVideo(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<dynamic> updatedNotifications = [];
      bool found = false;

      for (var notification in _notificationData) {
        final data = notification['data'];
        if (data != null && data['video_id']?.toString() == videoId) {
          // Add the notification ID to the mark read list
          final notificationId = notification['id']?.toString();
          if (notificationId != null && !_idsToMarkRead.contains(notificationId)) {
            _idsToMarkRead.add(notificationId);
            found = true;
            debugPrint('✅ Added notification ID $notificationId to mark read list for video $videoId');
          }
        } else {
          updatedNotifications.add(notification);
        }
      }

      if (found) {
        // Save updated notification data
        await prefs.setString('unread_notifications', json.encode(updatedNotifications));
        
        // Save IDs to mark read
        await _saveIdsToMarkRead();
        
        setState(() {
          _notificationData = updatedNotifications;
        });
        
        debugPrint('✅ Removed notification for video $videoId and added to mark read list');
      }
    } catch (e) {
      debugPrint('Error removing notification for video: $e');
    }
  }

  // Send mark read API call
  Future<void> _sendMarkReadApi() async {
    if (_idsToMarkRead.isEmpty) {
      debugPrint('📭 No IDs to mark as read');
      return;
    }

    if (_accessToken == null || _accessToken!.isEmpty) {
      debugPrint('❌ No access token available for mark read API');
      return;
    }

    try {
      final apiUrl = '${ApiConfig.baseUrl}/api/notifications/mark_read/';
      final requestBody = {
        "ids": _idsToMarkRead,
      };

      debugPrint('📤 Sending mark read API request to: $apiUrl');
      debugPrint('📦 Request body: ${json.encode(requestBody)}');

      final response = await globalHttpClient.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
          ...ApiConfig.commonHeaders,
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      debugPrint('📬 Mark read response status: ${response.statusCode}');
      debugPrint('📬 Mark read response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseJson = json.decode(response.body);
        if (responseJson['success'] == true) {
          debugPrint('✅ Successfully marked ${_idsToMarkRead.length} notifications as read');
          
          // Clear the IDs list from SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('ids_to_mark_read');
          
          setState(() {
            _idsToMarkRead.clear();
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Marked ${_idsToMarkRead.length} notifications as read'),
                backgroundColor: AppColors.successGreen,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('❌ Mark read API returned success: false');
        }
      } else {
        debugPrint('❌ Failed to mark notifications as read: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error sending mark read API: $e');
    }
  }

  // Check if subject has unread notifications
  bool _hasUnreadSubjectNotifications(String subjectId) {
    for (var notification in _notificationData) {
      final data = notification['data'];
      if (data != null && data['subject_id']?.toString() == subjectId) {
        return true;
      }
    }
    return false;
  }

  // Check if unit has unread notifications
  bool _hasUnreadUnitNotifications(String unitId) {
    for (var notification in _notificationData) {
      final data = notification['data'];
      if (data != null && data['unit_id']?.toString() == unitId) {
        return true;
      }
    }
    return false;
  }

  // Count unread chapter notifications
  int _countUnreadChapterNotifications(String chapterId) {
    int count = 0;
    for (var notification in _notificationData) {
      final data = notification['data'];
      if (data != null && data['chapter_id']?.toString() == chapterId) {
        count++;
      }
    }
    return count;
  }

  // Check if video has unread notifications
  bool _hasUnreadVideoNotifications(String videoId) {
    for (var notification in _notificationData) {
      final data = notification['data'];
      if (data != null && data['video_id']?.toString() == videoId) {
        return true;
      }
    }
    return false;
  }

  Future<void> _getAccessToken() async {
    try {
      _accessToken = await _authService.getAccessToken();
      debugPrint('🎬 Access token retrieved: ${_accessToken != null ? "Yes" : "No"}');
    } catch (e) {
      _showError('Failed to retrieve access token: $e');
    }
  }

  // Load data from SharedPreferences
  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        _courseName = prefs.getString('profile_course') ?? 'Course';
        _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
        _subcourseId = prefs.getString('profile_subcourse_id') ?? '';
      });

      // Load subjects data from stored JSON
      await _reloadSubjectsFromSharedPreferences();

      // Initialize navigation stack with subjects
      _navigationStack.add(NavigationState(
        pageType: 'subjects',
        subjectId: '',
        subjectName: 'Subjects',
        unitsData: _subjects,
      ));

      setState(() {
        _isLoading = false;
      });

      debugPrint('========== LOADED VIDEOS DATA ==========');
      debugPrint('Course Name: $_courseName');
      debugPrint('Subcourse Name: $_subcourseName');
      debugPrint('Subcourse ID: $_subcourseId');
      debugPrint('Student Type: $_studentType');
      debugPrint('Subjects Count: ${_subjects.length}');
      debugPrint('Notification Data Count: ${_notificationData.length}');
      debugPrint('========================================');

    } catch (e) {
      debugPrint('Error loading data from SharedPreferences: $e');
      _showError('Failed to load course data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Reload subjects from SharedPreferences
  Future<void> _reloadSubjectsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subjectsDataJson = prefs.getString('subjects_data');
      
      debugPrint('📦 Loading subjects data from SharedPreferences for Videos...');
      debugPrint('Subjects data JSON exists: ${subjectsDataJson != null && subjectsDataJson.isNotEmpty}');
      
      if (subjectsDataJson != null && subjectsDataJson.isNotEmpty) {
        try {
          final decodedData = json.decode(subjectsDataJson);
          debugPrint('📦 Decoded data type: ${decodedData.runtimeType}');
          
          List<dynamic> subjects = [];
          
          // Handle different possible data structures
          if (decodedData is List<dynamic>) {
            subjects = decodedData;
            debugPrint('✅ Data is List, subjects count: ${subjects.length}');
          } else if (decodedData is Map<String, dynamic>) {
            if (decodedData.containsKey('subjects') && decodedData['subjects'] is List) {
              subjects = decodedData['subjects'];
              debugPrint('✅ Found subjects in Map, count: ${subjects.length}');
            } else if (decodedData.containsKey('success') && decodedData['success'] == true && decodedData['subjects'] is List) {
              subjects = decodedData['subjects'];
              debugPrint('✅ Found subjects in API response structure, count: ${subjects.length}');
            } else {
              subjects = decodedData.values.toList();
              debugPrint('✅ Using Map values as subjects, count: ${subjects.length}');
            }
          }
          
          // Debug print all subjects with their titles and COMPLETE structure
          debugPrint('=== COMPLETE SUBJECTS STRUCTURE FOR VIDEOS ===');
          for (var i = 0; i < subjects.length; i++) {
            final subject = subjects[i];
            final title = subject['title']?.toString() ?? 'No Title';
            final id = subject['id']?.toString() ?? 'No ID';
            
            // Get units and chapters with proper null checking
            final dynamic unitsData = subject['units'];
            final dynamic chaptersData = subject['chapters'];
            
            final List<dynamic> units = (unitsData is List) ? unitsData : [];
            final List<dynamic> chapters = (chaptersData is List) ? chaptersData : [];
            
            debugPrint('Subject $i:');
            debugPrint('  - Title: "$title"');
            debugPrint('  - ID: $id');
            debugPrint('  - Units count: ${units.length}');
            debugPrint('  - Chapters count: ${chapters.length}');
            
            // Print actual units if they exist
            if (units.isNotEmpty) {
              debugPrint('  - Units:');
              for (var j = 0; j < units.length; j++) {
                final unit = units[j];
                debugPrint('    [${j + 1}] ${unit['title']} (${unit['chapters']?.length ?? 0} chapters)');
              }
            }
            
            // Print actual chapters if they exist
            if (chapters.isNotEmpty) {
              debugPrint('  - Direct Chapters:');
              for (var j = 0; j < chapters.length; j++) {
                final chapter = chapters[j];
                debugPrint('    [${j + 1}] ${chapter['title']}');
              }
            }
            
            if (units.isEmpty && chapters.isEmpty) {
              debugPrint('  - No content available');
            }
          }
          debugPrint('=== END COMPLETE SUBJECTS STRUCTURE FOR VIDEOS ===');
          
          // Store the properly parsed subjects
          setState(() {
            _subjects = subjects;
          });
          
          debugPrint('✅ Successfully loaded ${_subjects.length} subjects from SharedPreferences for Videos');
          
        } catch (e) {
          debugPrint('❌ Error parsing subjects data JSON: $e');
          setState(() {
            _subjects = [];
          });
        }
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Videos');
        debugPrint('Available keys in SharedPreferences: ${prefs.getKeys()}');
        setState(() {
          _subjects = [];
        });
      }
    } catch (e) {
      debugPrint('❌ Error reloading subjects from SharedPreferences: $e');
      setState(() {
        _subjects = [];
      });
    }
  }

  Map<String, String> _getAuthHeaders() {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Access token is null or empty');
    }
    
    return {
      'Authorization': 'Bearer $_accessToken',
      ...ApiConfig.commonHeaders,
    };
  }

  void _handleTokenExpiration() async {
    await _authService.logout();
    _showError('Session expired. Please login again.');
    _navigateToLogin();
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  void _loadSubjects() {
    if (_subjects.isEmpty) {
      _showError('No subjects data available. Please load study materials first.');
      return;
    }

    setState(() {
      _currentPage = 'subjects';
      _isLoading = false;
    });
  }

  // FIXED: Enhanced _loadUnits method to properly handle direct chapters
  void _loadUnits(String subjectId, String subjectName) {
    try {
      debugPrint('=== LOADING UNITS/CHAPTERS FOR SUBJECT FOR VIDEOS ===');
      debugPrint('Subject ID: $subjectId');
      debugPrint('Subject Name: $subjectName');
      
      // Find the subject in the stored data
      final subject = _subjects.firstWhere(
        (subject) => subject['id']?.toString() == subjectId,
        orElse: () => null,
      );

      if (subject == null) {
        _showError('Subject not found in stored data');
        return;
      }

      // Get units and chapters with proper null checking
      final dynamic unitsData = subject['units'];
      final dynamic chaptersData = subject['chapters'];
      
      final List<dynamic> units = (unitsData is List) ? unitsData : [];
      final List<dynamic> directChapters = (chaptersData is List) ? chaptersData : [];

      debugPrint('Units found: ${units.length}');
      debugPrint('Direct chapters found: ${directChapters.length}');
      
      // Check if units exist and are not empty
      final bool hasUnits = units.isNotEmpty;
      
      // Check if direct chapters exist and are not empty  
      final bool hasDirectChapters = directChapters.isNotEmpty;

      debugPrint('Has units: $hasUnits');
      debugPrint('Has direct chapters: $hasDirectChapters');

      // If subject has units, show units page
      if (hasUnits) {
        debugPrint('📚 Showing UNITS page for subject: $subjectName');
        setState(() {
          _units = units;
          _selectedSubjectId = subjectId;
          _selectedSubjectName = subjectName;
          _currentPage = 'units';
          _isLoading = false;
        });
        
        // Add to navigation stack with units data
        _navigationStack.add(NavigationState(
          pageType: 'units',
          subjectId: subjectId,
          subjectName: subjectName,
          hasDirectChapters: false,
          unitsData: units,
        ));
      } 
      // If subject has direct chapters but no units, show chapters directly
      else if (hasDirectChapters) {
        debugPrint('📖 Showing DIRECT CHAPTERS page for subject: $subjectName');
        setState(() {
          _chapters = directChapters;
          _selectedSubjectId = subjectId;
          _selectedSubjectName = subjectName;
          _selectedUnitName = ''; // No unit name since we're going directly to chapters
          _currentPage = 'chapters';
          _isLoading = false;
        });
        
        // Add to navigation stack with direct chapters flag and chapters data
        _navigationStack.add(NavigationState(
          pageType: 'chapters',
          subjectId: subjectId,
          subjectName: subjectName,
          hasDirectChapters: true,
          chaptersData: directChapters,
        ));
      }
      // If subject has neither units nor chapters
      else {
        debugPrint('❌ No content available for subject: $subjectName');
        _showError('No content available for this subject');
        setState(() {
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint('❌ Error loading units/chapters: $e');
      _showError('Failed to load content: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadChapters(String unitId, String unitName) {
    try {
      debugPrint('=== LOADING CHAPTERS FOR UNIT FOR VIDEOS ===');
      debugPrint('Unit ID: $unitId');
      debugPrint('Unit Name: $unitName');
      
      // Find the unit in the current subject's units
      final unit = _units.firstWhere(
        (unit) => unit['id']?.toString() == unitId,
        orElse: () => null,
      );

      if (unit == null) {
        _showError('Unit not found in stored data');
        return;
      }

      final List<dynamic> chapters = unit['chapters'] ?? [];
      
      debugPrint('Chapters found: ${chapters.length}');

      setState(() {
        _chapters = chapters;
        _selectedUnitId = unitId;
        _selectedUnitName = unitName;
        _currentPage = 'chapters';
        _isLoading = false;
      });

      // Add to navigation stack with chapters data
      _navigationStack.add(NavigationState(
        pageType: 'chapters',
        subjectId: _selectedSubjectId!,
        subjectName: _selectedSubjectName,
        unitId: unitId,
        unitName: unitName,
        hasDirectChapters: false,
        chaptersData: chapters,
      ));

    } catch (e) {
      debugPrint('Error loading chapters: $e');
      _showError('Failed to load chapters: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Fetch videos for a chapter from API - CORRECTED ENDPOINT
  Future<void> _fetchVideos(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String encodedId = Uri.encodeComponent(chapterId);
      // FIX: Using the correct API endpoint from your working videos.dart
      String apiUrl = '${ApiConfig.baseUrl}/api/videos/list/?chapter_id=$encodedId';
      
      debugPrint('=== FETCHING VIDEOS API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Access Token: ${_accessToken!.substring(0, 20)}...');
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== VIDEOS API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> videos = json.decode(response.body);
        
        debugPrint('Videos count: ${videos.length}');
        
        // Check if there are any locked videos (video_url is null or empty)
        final hasLockedVideos = videos.any((video) {
          final videoUrl = video['video_url']?.toString() ?? '';
          return videoUrl.isEmpty || videoUrl == 'null';
        });

        setState(() {
          _videos = videos;
          _selectedChapterId = chapterId;
          _selectedChapterName = chapterName;
          _currentPage = 'videos';
          _isLoading = false;
          _hasLockedVideos = hasLockedVideos;
        });
        
        debugPrint('✅ Successfully loaded ${_videos.length} videos for chapter: $chapterName');
        debugPrint('🔒 Locked videos present: $hasLockedVideos');
        
        // Add to navigation stack with videos data
        _navigationStack.add(NavigationState(
          pageType: 'videos',
          subjectId: _selectedSubjectId!,
          subjectName: _selectedSubjectName,
          unitId: _selectedUnitId,
          unitName: _selectedUnitName,
          chapterId: chapterId,
          chapterName: chapterName,
          hasDirectChapters: _selectedUnitId == null,
        ));

        // Show subscription message if there are locked videos
        if (hasLockedVideos) {
          _showAndHideSubscriptionMessage();
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_videos.length} videos found'),
              backgroundColor: AppColors.successGreen,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        debugPrint('Error: Failed to fetch videos. Status code: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        _showError('Failed to load videos: ${response.statusCode}');
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() => _isLoading = false);
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
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Exception occurred while fetching videos: $e');
      _showError('Error fetching videos: $e');
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> _sortVideos(List<dynamic> videos) {
    if (videos.isEmpty) return videos;

    // Create a copy to avoid modifying the original list
    List<dynamic> sortedVideos = List.from(videos);

    // Parse dates and determine locked status for sorting
    sortedVideos.sort((a, b) {
      final videoUrlA = a['video_url']?.toString() ?? '';
      final videoUrlB = b['video_url']?.toString() ?? '';
      final isLockedA = videoUrlA.isEmpty || videoUrlA == 'null';
      final isLockedB = videoUrlB.isEmpty || videoUrlB == 'null';

      // For public students, prioritize unlocked videos first
      if (_studentType.toLowerCase() == 'public') {
        if (isLockedA != isLockedB) {
          return isLockedA ? 1 : -1; // Unlocked videos come first
        }
      }

      // Sort by date (most recent first)
      try {
        final dateA = a['uploaded_at']?.toString() ?? '';
        final dateB = b['uploaded_at']?.toString() ?? '';

        if (dateA.isEmpty && dateB.isEmpty) return 0;
        if (dateA.isEmpty) return 1; // Videos without date go to bottom
        if (dateB.isEmpty) return -1;

        final parsedDateA = DateTime.parse(dateA);
        final parsedDateB = DateTime.parse(dateB);

        // Most recent first (descending order)
        return parsedDateB.compareTo(parsedDateA);
      } catch (e) {
        debugPrint('Error parsing dates for sorting videos: $e');
        return 0;
      }
    });

    return sortedVideos;
  }

  // Add this helper method to format date
  String _formatVideoDate(String dateString) {
    try {
      if (dateString.isEmpty) return 'Unknown date';
      
      final DateTime date = DateTime.parse(dateString);
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '$weeks week${weeks > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return '$months month${months > 1 ? 's' : ''} ago';
      } else {
        final years = (difference.inDays / 365).floor();
        return '$years year${years > 1 ? 's' : ''} ago';
      }
    } catch (e) {
      try {
        final parts = dateString.split('T')[0].split('-');
        if (parts.length == 3) {
          return '${parts[2]}/${parts[1]}/${parts[0]}';
        }
      } catch (e) {
        // If all else fails
      }
      return dateString.isNotEmpty ? dateString : 'Unknown date';
    }
  }

  // Show and hide subscription message with animation
  void _showAndHideSubscriptionMessage() {
    setState(() {
      _showSubscriptionMessage = true;
    });
  }

  void _showError(String message) {
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  // ENHANCED: Proper hierarchical backward navigation
  void _navigateBack() {
    debugPrint('=== BACK NAVIGATION START FOR VIDEOS ===');
    debugPrint('Current stack length: ${_navigationStack.length}');
    debugPrint('Current page: $_currentPage');
    
    if (_navigationStack.length > 1) {
      // Remove current state
      final currentState = _navigationStack.removeLast();
      debugPrint('Removed current state: ${currentState.pageType}');
      
      // Get previous state
      final previousState = _navigationStack.last;
      debugPrint('Previous state: ${previousState.pageType}');
      
      // Restore the previous state properly based on page type
      setState(() {
        _currentPage = previousState.pageType;
        _selectedSubjectId = previousState.subjectId;
        _selectedSubjectName = previousState.subjectName;
        
        switch (previousState.pageType) {
          case 'subjects':
            // Going back to subjects - restore subjects data
            _units = [];
            _chapters = [];
            _videos = [];
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
            
          case 'units':
            // Going back to units from chapters
            _units = previousState.unitsData;
            _chapters = [];
            _videos = [];
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
            
          case 'chapters':
            // Going back to chapters from videos
            if (previousState.hasDirectChapters) {
              // Direct chapters (no units)
              _chapters = previousState.chaptersData;
              _selectedUnitId = null;
              _selectedUnitName = '';
            } else {
              // Chapters with units
              _chapters = previousState.chaptersData;
              _selectedUnitId = previousState.unitId;
              _selectedUnitName = previousState.unitName ?? '';
            }
            _videos = [];
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
        }
        _isLoading = false;
      });
      
      debugPrint('=== BACK NAVIGATION COMPLETE FOR VIDEOS ===');
      debugPrint('New current page: $_currentPage');
      debugPrint('Stack length after: ${_navigationStack.length}');
    } else {
      // If we're at the root (subjects), exit the screen
      debugPrint('At root level - exiting videos screen');
      _exitScreen();
    }
  }

  // Enhanced exit screen method that sends data without waiting
  void _exitScreen() {
    if (_studentType.toLowerCase() == 'online') {
      // Send watching data to backend without waiting for response
      _sendStoredVideoEventsToAPI().catchError((e) {
        debugPrint('Error sending watching data on exit: $e');
        // Don't show error to user, just log it
      });
    }
    
    // Send mark read API when returning from videos section
    _sendMarkReadApi();
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // Method to check if there is stored video events data
  Future<bool> _hasStoredVideoEvents() async {
    try {
      final hasData = _videoEventsBox.isNotEmpty;
      debugPrint('🎬 Checking stored video events in videoEvents box: $hasData');
      if (hasData) {
        final allKeys = _videoEventsBox.keys.toList();
        debugPrint('🎬 Found ${allKeys.length} videos with events');
      }
      return hasData;
    } catch (e) {
      debugPrint('Error checking stored video events: $e');
      return false;
    }
  }

  // FIXED: Enhanced with debouncing and duplicate call prevention
  Future<void> _sendStoredVideoEventsToAPI() async {
    // Only send data for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('🎬 Student type is $_studentType - skipping video events collection');
      return;
    }

    // Check if we're already sending data
    if (_isSendingVideoEvents) {
      debugPrint('🎬 Video events API call already in progress, skipping duplicate call');
      return;
    }

    // Check debounce time
    final now = DateTime.now();
    if (_lastVideoEventsCallTime != null && 
        now.difference(_lastVideoEventsCallTime!) < _videoEventsDebounceTime) {
      debugPrint('🎬 Video events API call debounced, too soon since last call');
      return;
    }

    try {
      debugPrint('\n🎬 ===== ATTEMPTING TO SEND STORED VIDEO EVENTS TO API =====');
      
      final allKeys = _videoEventsBox.keys.toList();
      
      if (allKeys.isEmpty) {
        debugPrint('🎬 No stored video events found to send');
        return;
      }

      debugPrint('🎬 Total video entries to send: ${allKeys.length}');

      // Check if we have access token
      if (_accessToken == null || _accessToken!.isEmpty) {
        debugPrint('🎬 ❌ No access token available, cannot send video events');
        return;
      }

      // Set flags to prevent duplicate calls
      setState(() {
        _isSendingVideoEvents = true;
        _lastVideoEventsCallTime = now;
      });

      bool anyDataSent = false;
      final List<String> successfullySentVideoIds = [];

      for (final videoId in allKeys) {
        // Skip if this video is already being processed
        if (_currentlyProcessingVideoIds.contains(videoId)) {
          debugPrint('🎬 ⚠️ Skipping video $videoId - already being processed');
          continue;
        }

        final videoData = _videoEventsBox.get(videoId);
        
        if (videoData != null && videoData is Map) {
          final events = videoData['events'] as List?;
          final videoTitle = videoData['video_title'] as String? ?? 'Unknown Video';
          
          if (events != null && events.isNotEmpty) {
            debugPrint('\n🎬 Processing video: $videoTitle');
            debugPrint('🎬 Video ID: $videoId');
            debugPrint('🎬 Events count: ${events.length}');
            
            // Add to currently processing set
            _currentlyProcessingVideoIds.add(videoId);
            
            // Filter events to ensure only one 'ended' event
            List<dynamic> filteredEvents = _filterEvents(events);
            debugPrint('🎬 Filtered events count: ${filteredEvents.length}');
            
            // Flatten the events array if it contains nested sessions
            List<dynamic> flattenedEvents = _flattenEvents(filteredEvents);
            debugPrint('🎬 Flattened events count: ${flattenedEvents.length}');
            
            // Prepare request body according to API specification
            final requestBody = {
              "video_id": videoId,
              "events": flattenedEvents,
            };

            debugPrint('🎬 Request Body:');
            debugPrint(const JsonEncoder.withIndent('  ').convert(requestBody));

            // API endpoint
            final apiUrl = '${ApiConfig.baseUrl}/api/performance/video_events/';

            debugPrint('🎬 API URL: $apiUrl');

            try {
              // Send POST request
              final response = await globalHttpClient.post(
                Uri.parse(apiUrl),
                headers: _getAuthHeaders(),
                body: jsonEncode(requestBody),
              ).timeout(const Duration(seconds: 30));

              debugPrint('🎬 Response Status Code: ${response.statusCode}');
              debugPrint('🎬 Response Body: ${response.body}');

              if (response.statusCode == 200 || response.statusCode == 201) {
                try {
                  final responseJson = jsonDecode(response.body);
                  if (responseJson['success'] == true) {
                    debugPrint('🎬 ✅ Video events sent successfully for video: $videoTitle');
                    
                    // Mark this video for removal after successful API call
                    successfullySentVideoIds.add(videoId);
                    anyDataSent = true;
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Video progress synced for $videoTitle'),
                          backgroundColor: AppColors.successGreen,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    debugPrint('🎬 ❌ API returned success: false for video: $videoTitle');
                  }
                } catch (e) {
                  debugPrint('🎬 ❌ Error parsing response JSON: $e');
                }
              } else if (response.statusCode == 401) {
                debugPrint('🎬 ❌ Unauthorized - token may be expired');
                _handleTokenExpiration();
                break; // Stop trying to send more requests
              } else {
                debugPrint('🎬 ❌ Failed to send video events. Status: ${response.statusCode}');
              }
            } catch (e) {
              debugPrint('🎬 ❌ Error sending video events for $videoId: $e');
            } finally {
              // Remove from currently processing set
              _currentlyProcessingVideoIds.remove(videoId);
            }
          } else {
            debugPrint('🎬 ⚠️ No events found for video: $videoTitle');
            // Remove empty video entry
            successfullySentVideoIds.add(videoId);
          }
        }
      }

      // Remove successfully sent videos from Hive
      for (final videoId in successfullySentVideoIds) {
        await _videoEventsBox.delete(videoId);
        debugPrint('🎬 ✅ Removed video $videoId from local storage');
      }

      if (anyDataSent) {
        debugPrint('🎬 ✅ Successfully sent some video events to API');
      } else {
        debugPrint('🎬 ⚠️ No video events were successfully sent to API');
      }

      debugPrint('🎬 ===== FINISHED SENDING VIDEO EVENTS =====\n');
      
      // Print remaining data in Hive
      _printStoredVideoEvents();

    } catch (e) {
      debugPrint('🎬 ❌ Error in _sendStoredVideoEventsToAPI: $e');
    } finally {
      // Reset sending flag
      if (mounted) {
        setState(() {
          _isSendingVideoEvents = false;
        });
      }
    }
  }

  // Print stored video events for debugging
  void _printStoredVideoEvents() {
    final allKeys = _videoEventsBox.keys.toList();
    debugPrint('\n🎬 CURRENTLY STORED VIDEO EVENTS in videoEvents box:');
    debugPrint('═══════════════════════════════════════════════════════');
    if (allKeys.isEmpty) {
      debugPrint('No video events stored.');
    } else {
      debugPrint('Total videos with events: ${allKeys.length}');
      for (var key in allKeys) {
        final data = _videoEventsBox.get(key);
        if (data is Map) {
          final videoTitle = data['video_title'] as String? ?? 'Unknown Video';
          final events = data['events'] as List?;
          debugPrint('Video ID: $key');
          debugPrint('Title: $videoTitle');
          debugPrint('Events count: ${events?.length ?? 0}');
          if (events != null && events.isNotEmpty) {
            for (var event in events.take(3)) { // Show first 3 events
              debugPrint('  - ${event['event_type']} at ${event['time'] ?? event['new_position']}');
            }
            if (events.length > 3) {
              debugPrint('  ... and ${events.length - 3} more events');
            }
          }
          debugPrint('---');
        } else {
          debugPrint('Video ID: $key, Data: $data');
        }
      }
    }
    debugPrint('═══════════════════════════════════════════════════════\n');
  }

  // Filter events to ensure only one 'ended' event (the last one)
  List<dynamic> _filterEvents(List<dynamic> events) {
    List<dynamic> filtered = [];
    Map<String, dynamic>? lastEndedEvent;
    
    // First pass: collect all events and find the last 'ended' event
    for (var event in events) {
      if (event is Map) {
        final eventType = event['event_type'] as String?;
        
        if (eventType == 'ended') {
          // Store the last ended event
          lastEndedEvent = Map<String, dynamic>.from(event);
        } else {
          // Keep all non-ended events
          filtered.add(event);
        }
      } else if (event is List) {
        // Recursively filter nested events
        filtered.add(_filterEvents(event));
      } else {
        // Keep other types of events
        filtered.add(event);
      }
    }
    
    // Add the last ended event at the end if found
    if (lastEndedEvent != null) {
      filtered.add(lastEndedEvent);
      debugPrint('🎬 Filtered: Keeping only one ended event at position ${lastEndedEvent['time'] ?? lastEndedEvent['new_position']}');
    }
    
    debugPrint('🎬 Filtered ${events.length} events to ${filtered.length} events');
    return filtered;
  }

  // Method: Flatten nested events structure
  List<dynamic> _flattenEvents(List<dynamic> events) {
    List<dynamic> flattened = [];
    
    for (var event in events) {
      if (event is List) {
        // If event is a list (nested session), recursively flatten it
        flattened.addAll(_flattenEvents(event));
      } else if (event is Map) {
        // If event is a map, add it directly
        flattened.add(event);
      }
    }
    
    debugPrint('🎬 Flattened ${events.length} events to ${flattened.length} events');
    return flattened;
  }

  // Method: Send stored events for other videos when starting a new video
  Future<void> _sendOtherVideoEventsBeforeStartingNewVideo(String newVideoId) async {
    // Only send data for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('🎬 Student type is $_studentType - skipping video events collection');
      return;
    }

    try {
      debugPrint('\n🎬 ===== CHECKING FOR OTHER VIDEO EVENTS BEFORE STARTING NEW VIDEO =====');
      debugPrint('🎬 New video ID: $newVideoId');
      
      final allKeys = _videoEventsBox.keys.toList();
      final otherVideoKeys = allKeys.where((key) => key != newVideoId).toList();
      
      if (otherVideoKeys.isNotEmpty) {
        debugPrint('🎬 Found stored events for ${otherVideoKeys.length} other videos - sending to API first');
        await _sendStoredVideoEventsToAPI();
        debugPrint('🎬 Finished sending other video events, now starting new video');
      } else {
        debugPrint('🎬 No stored events for other videos found');
      }
      
      debugPrint('🎬 ===== FINISHED CHECKING OTHER VIDEO EVENTS =====\n');
    } catch (e) {
      debugPrint('🎬 ❌ Error in _sendOtherVideoEventsBeforeStartingNewVideo: $e');
    }
  }

  Future<bool> _handleDeviceBackButton() async {
    debugPrint('🎬 Back button pressed - current page: $_currentPage');
    
    if (_currentPage == 'subjects' && _navigationStack.length <= 1) {
      // On subjects page - check for stored data and send if exists
      // Only for online students
      if (_studentType.toLowerCase() == 'online') {
        debugPrint('🎬 On subjects page - checking for stored video events');
        final hasData = await _hasStoredVideoEvents();
        if (hasData) {
          debugPrint('🎬 Found stored video events - sending to API');
          // Send data in background without waiting for response
          _sendStoredVideoEventsToAPI();
        } else {
          debugPrint('🎬 No stored video events found');
        }
      } else {
        debugPrint('🎬 Student type is $_studentType - skipping video events collection');
      }
      // Exit the screen
      _exitScreen();
      return false; // Don't allow default back behavior
    } else {
      // For other pages, do normal navigation
      _navigateBack();
      return false; // Don't allow default back behavior
    }
  }

  String _getAppBarTitle() {
    if (_navigationStack.isNotEmpty) {
      final currentState = _navigationStack.last;
      switch (currentState.pageType) {
        case 'subjects':
          return 'Subjects';
        case 'units':
          return 'Units';
        case 'chapters':
          return 'Chapters';
        case 'videos':
          return 'Videos';
        default:
          return 'Videos';
      }
    }
    
    switch (_currentPage) {
      case 'subjects':
        return 'Subjects';
      case 'units':
        return 'Units';
      case 'chapters':
        return 'Chapters';
      case 'videos':
        return 'Videos';
      default:
        return 'Videos';
    }
  }

  String _getAppBarSubtitle() {
    if (_navigationStack.isNotEmpty) {
      final currentState = _navigationStack.last;
      switch (currentState.pageType) {
        case 'units':
          return currentState.subjectName;
        case 'chapters':
          if (currentState.hasDirectChapters) {
            return currentState.subjectName;
          } else {
            return currentState.unitName ?? currentState.subjectName;
          }
        case 'videos':
          return currentState.chapterName ?? currentState.subjectName;
        default:
          return '';
      }
    }
    return '';
  }

  // Show subscription popup for locked videos
  void _showSubscriptionPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primaryYellow,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Premium Content',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          content: const Text(
            'Take any subscription plan to view this content and unlock all premium features.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'Subscribe',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }
        
        await _handleDeviceBackButton();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Stack(
          children: [
            // Gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryYellow.withOpacity(0.08),
                    AppColors.backgroundLight,
                    Colors.white,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            
            // Main content
            Column(
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
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button and title row
                        Row(
                          children: [
                            IconButton(
                              onPressed: () async {
                                await _handleDeviceBackButton();
                              },
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getAppBarTitle(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  if (_getAppBarSubtitle().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _getAppBarSubtitle(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Subscription Message (appears only when there are locked videos)
                if (_showSubscriptionMessage && _hasLockedVideos)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SubscriptionScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryYellow.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_open_rounded,
                            color: AppColors.primaryYellow,
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Take subscription to unlock all premium features',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryYellowDark,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: AppColors.primaryYellow,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? _buildSkeletonLoading()
                      : _buildCurrentPage(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skeleton header
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 120,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Container(
                    width: 200,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Skeleton cards
            Column(
              children: List.generate(5, (index) => _buildSkeletonCard()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 100,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case 'subjects':
        return _buildSubjectsPage();
      case 'units':
        return _buildUnitsPage();
      case 'chapters':
        return _buildChaptersPage();
      case 'videos':
        return _buildVideosPage();
      default:
        return _buildSubjectsPage();
    }
  }

  Widget _buildSubjectsPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Subjects',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose a subject to view videos',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_subjects.length} subject${_subjects.length != 1 ? 's' : ''} available',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grey400,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_subjects.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.subject_rounded,
                          size: 50,
                          color: AppColors.primaryYellow.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No subjects available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please load study materials first',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: _subjects
                    .map((subject) {
                      // Get units and chapters with proper null checking
                      final dynamic unitsData = subject['units'];
                      final dynamic chaptersData = subject['chapters'];
                      
                      final List<dynamic> units = (unitsData is List) ? unitsData : [];
                      final List<dynamic> chapters = (chaptersData is List) ? chaptersData : [];
                      
                      final bool hasUnits = units.isNotEmpty;
                      final bool hasChapters = chapters.isNotEmpty;
                      
                      String contentCount;
                      if (hasUnits) {
                        contentCount = '${units.length} units';
                      } else if (hasChapters) {
                        contentCount = '${chapters.length} chapters';
                      } else {
                        contentCount = 'No content';
                      }
                              
                      return _buildSubjectCard(
                        title: subject['title']?.toString() ?? 'Untitled Subject',
                        subtitle: contentCount,
                        icon: Icons.subject_rounded,
                        color: AppColors.primaryBlue,
                        onTap: () => _loadUnits(
                          subject['id']?.toString() ?? '',
                          subject['title']?.toString() ?? 'Unknown Subject',
                        ),
                        showBadge: _hasUnreadSubjectNotifications(subject['id']?.toString() ?? ''),
                      );
                    })
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitsPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Units',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedSubjectName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '${_units.length} unit${_units.length != 1 ? 's' : ''} available',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_units.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.library_books_rounded,
                          size: 50,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No units available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Units for this subject will be added soon',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: _units
                    .map((unit) => _buildSubjectCard(
                          title: unit['title']?.toString() ?? 'Unknown Unit',
                          subtitle: '${unit['chapters']?.length ?? 0} chapters available',
                          icon: Icons.library_books_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => _loadChapters(
                            unit['id']?.toString() ?? '',
                            unit['title']?.toString() ?? 'Unknown Unit',
                          ),
                          showBadge: _hasUnreadUnitNotifications(unit['id']?.toString() ?? ''),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChaptersPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chapters',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedUnitName.isNotEmpty ? _selectedUnitName : _selectedSubjectName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '${_chapters.length} chapter${_chapters.length != 1 ? 's' : ''} available',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_chapters.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warningOrange.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 50,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No chapters available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chapters for this unit will be added soon',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: _chapters
                    .map((chapter) => _buildSubjectCard(
                          title: chapter['title']?.toString() ?? 'Unknown Chapter',
                          subtitle: 'Tap to view videos',
                          icon: Icons.menu_book_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => _fetchVideos(
                            chapter['id']?.toString() ?? '',
                            chapter['title']?.toString() ?? 'Unknown Chapter',
                          ),
                          showBadge: _countUnreadChapterNotifications(chapter['id']?.toString() ?? '') > 0,
                          badgeCount: _countUnreadChapterNotifications(chapter['id']?.toString() ?? ''),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideosPage() {
    // Sort videos before displaying
    List<dynamic> sortedVideos = _sortVideos(_videos);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Videos',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedChapterName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '${sortedVideos.length} video${sortedVideos.length != 1 ? 's' : ''} available',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (sortedVideos.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.videocam_off_rounded,
                          size: 50,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No videos available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Videos for this chapter\nwill be added soon',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: sortedVideos
                    .map((video) {
                      final videoUrl = video['video_url']?.toString() ?? '';
                      final isLocked = videoUrl.isEmpty || videoUrl == 'null';
                      final videoId = video['id']?.toString() ?? '';
                      final uploadedAt = video['uploaded_at']?.toString() ?? '';
                      
                      return _buildVideoCard(
                        videoId: videoId,
                        title: video['title']?.toString() ?? 'Untitled Video',
                        uploadedAt: uploadedAt,
                        isLocked: isLocked,
                        showBadge: _hasUnreadVideoNotifications(videoId),
                      );
                    })
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool showBadge = false,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color,
                      size: 14,
                    ),
                  ),
                  if (showBadge)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: badgeCount > 0 
                            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                            : const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: badgeCount > 0
                            ? Text(
                                badgeCount > 9 ? '9+' : badgeCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard({
    required String videoId,
    required String title,
    required String uploadedAt,
    required bool isLocked,
    bool showBadge = false,
  }) {
    return GestureDetector(
      onTap: () {
        if (isLocked) {
          _showSubscriptionPopup(context);
          return;
        }

        if (videoId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video ID not available'),
              backgroundColor: AppColors.errorRed,
            ),
          );
          return;
        }
        
        // Remove notification for this video and add to mark read list
        _removeNotificationForVideo(videoId);
        
        // Send stored events for other videos before starting new video
        // Only for online students
        if (_studentType.toLowerCase() == 'online') {
          _sendOtherVideoEventsBeforeStartingNewVideo(videoId);
        } else {
          debugPrint('🎬 Student type is $_studentType - skipping video events collection');
        }
        
        // Navigate to video stream page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoStreamScreen(
              videoId: videoId,
              videoTitle: title,
              videoDuration: '', 
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isLocked 
                  ? Colors.grey.withOpacity(0.1)
                  : AppColors.primaryYellow.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: isLocked 
                          ? Colors.grey.withOpacity(0.1)
                          : AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isLocked ? Icons.lock_outline_rounded : Icons.play_circle_fill_rounded,
                      size: 20,
                      color: isLocked ? Colors.grey : AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isLocked ? Colors.grey : AppColors.textDark,
                            letterSpacing: -0.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (uploadedAt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatVideoDate(uploadedAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isLocked ? Colors.grey : AppColors.grey400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: isLocked 
                              ? Colors.grey.withOpacity(0.1)
                              : AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isLocked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                          color: isLocked ? Colors.grey : AppColors.primaryBlue,
                          size: 16,
                        ),
                      ),
                      if (showBadge && !isLocked)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Blur effect for locked videos 
            if (isLocked)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ColorFilter.mode(
                      Colors.grey.withOpacity(0.3),
                      BlendMode.srcOver,
                    ),
                    child: Container(
                      color: Colors.white.withOpacity(0.7),
                      child: const Center(
                        child: Icon(
                          Icons.lock_rounded,
                          color: AppColors.primaryBlue,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
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