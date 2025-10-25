import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/service/auth_service.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../../../common/theme_color.dart';
import '../video_stream/video_stream.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'subjects'; // subjects, units, chapters, videos
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  String _selectedSubjectName = '';
  String _selectedUnitName = '';
  String _selectedChapterName = '';
  String _studentType = ''; // Added student type
  
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

      setState(() {
        _isLoading = false;
      });

      debugPrint('========== LOADED VIDEOS DATA ==========');
      debugPrint('Course Name: $_courseName');
      debugPrint('Subcourse Name: $_subcourseName');
      debugPrint('Subcourse ID: $_subcourseId');
      debugPrint('Student Type: $_studentType');
      debugPrint('Subjects Count: ${_subjects.length}');
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
      
      if (subjectsDataJson != null && subjectsDataJson.isNotEmpty) {
        final List<dynamic> subjects = json.decode(subjectsDataJson);
        setState(() {
          _subjects = subjects;
        });
        debugPrint('✅ Reloaded ${_subjects.length} subjects from SharedPreferences for Videos');
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Videos');
        setState(() {
          _subjects = [];
        });
      }
    } catch (e) {
      debugPrint('Error reloading subjects from SharedPreferences: $e');
      setState(() {
        _subjects = [];
      });
    }
  }

  // Load subjects from SharedPreferences (no API call)
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

  // Load units for a subject from SharedPreferences (no API call)
  void _loadUnits(String subjectId, String subjectName) {
    try {
      // Find the subject in the stored data
      final subject = _subjects.firstWhere(
        (subject) => subject['id']?.toString() == subjectId,
        orElse: () => null,
      );

      if (subject == null) {
        _showError('Subject not found in stored data');
        return;
      }

      final List<dynamic> units = subject['units'] ?? [];

      setState(() {
        _units = units;
        _selectedSubjectId = subjectId;
        _selectedSubjectName = subjectName;
        _currentPage = 'units';
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error loading units: $e');
      _showError('Failed to load units: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Load chapters for a unit from SharedPreferences (no API call)
  void _loadChapters(String unitId, String unitName) {
    try {
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

      setState(() {
        _chapters = chapters;
        _selectedUnitId = unitId;
        _selectedUnitName = unitName;
        _currentPage = 'chapters';
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('Error loading chapters: $e');
      _showError('Failed to load chapters: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Fetch videos for a chapter from API
  Future<void> _fetchVideos(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String encodedId = Uri.encodeComponent(chapterId);
      String apiUrl = '${ApiConfig.baseUrl}/api/videos/list?chapter_id=$encodedId';
      
      debugPrint('Fetching videos from: $apiUrl');
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $_accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Response Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> videos = json.decode(response.body);
        
        setState(() {
          _videos = videos;
          _selectedChapterId = chapterId;
          _selectedChapterName = chapterName;
          _currentPage = 'videos';
          _isLoading = false;
        });
        
        debugPrint('✅ Successfully loaded ${_videos.length} videos for chapter: $chapterName');
        
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
        _showError('Failed to load videos: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception occurred while fetching videos: $e');
      _showError('Error fetching videos: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleTokenExpiration() async {
    await _authService.logout();
    _showError('Session expired. Please login again.');
    _navigateToLogin();
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

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
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

  // Method to send all stored video events data to API (only called from subjects page back button and app lifecycle)
  Future<void> _sendStoredVideoEventsToAPI() async {
    // Only send data for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('🎬 Student type is $_studentType - skipping video events collection');
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

      bool anyDataSent = false;
      final List<String> successfullySentVideoIds = [];

      for (final videoId in allKeys) {
        final videoData = _videoEventsBox.get(videoId);
        
        if (videoData != null && videoData is Map) {
          final events = videoData['events'] as List?;
          final videoTitle = videoData['video_title'] as String? ?? 'Unknown Video';
          
          if (events != null && events.isNotEmpty) {
            debugPrint('\n🎬 Processing video: $videoTitle');
            debugPrint('🎬 Video ID: $videoId');
            debugPrint('🎬 Events count: ${events.length}');
            
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
              final response = await http.post(
                Uri.parse(apiUrl),
                headers: {
                  'Authorization': 'Bearer $_accessToken',
                  'Content-Type': 'application/json',
                  ...ApiConfig.commonHeaders,
                },
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

  void _navigateBack() {
    setState(() {
      switch (_currentPage) {
        case 'subjects':
          // When going back from subjects page, check for stored data and send if exists
          // Only for online students
          if (_studentType.toLowerCase() == 'online') {
            _sendStoredVideoEventsToAPI();
          }
          if (mounted) {
            Navigator.pop(context);
          }
          break;
        case 'units':
          _currentPage = 'subjects';
          // Don't clear units - they will be reloaded when needed
          _selectedSubjectId = null;
          _selectedSubjectName = '';
          break;
        case 'chapters':
          _currentPage = 'units';
          // Don't clear chapters - they will be reloaded when needed
          _selectedUnitId = null;
          _selectedUnitName = '';
          break;
        case 'videos':
          _currentPage = 'chapters';
          _videos.clear(); // Only clear videos as they come from API
          _selectedChapterId = null;
          _selectedChapterName = '';
          break;
      }
    });
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    debugPrint('🎬 Back button pressed - current page: $_currentPage');
    
    if (_currentPage == 'subjects') {
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
      // Allow normal back navigation
      return true;
    } else if (_currentPage == 'videos') {
      // From videos page, go back to chapters page
      _navigateBack();
      // Prevent default back behavior
      return false;
    } else {
      // For other pages (units, chapters), do normal navigation
      debugPrint('🎬 On $_currentPage page - normal back navigation');
      _navigateBack();
      // Prevent default back behavior
      return false;
    }
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'subjects':
        return 'Videos';
      case 'units':
        return 'Units - $_selectedSubjectName';
      case 'chapters':
        return 'Chapters - $_selectedUnitName';
      case 'videos':
        return 'Videos - $_selectedChapterName';
      default:
        return 'Videos';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }
        
        final shouldPop = await _handleDeviceBackButton();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
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
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button and title row
                        Row(
                          children: [
                            IconButton(
                              onPressed: () async {
                                if (_currentPage == 'subjects') {
                                  if (_studentType.toLowerCase() == 'online') {
                                    final hasData = await _hasStoredVideoEvents();
                                    if (hasData) {
                                      _sendStoredVideoEventsToAPI();
                                    }
                                  }
                                  if (mounted) {
                                    Navigator.pop(context);
                                  }
                                } else {
                                  _navigateBack();
                                }
                              },
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getAppBarTitle(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Course and Subcourse Info
                        if (_courseName.isNotEmpty || _subcourseName.isNotEmpty)
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
                                      if (_courseName.isNotEmpty)
                                        TextSpan(
                                          text: _courseName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (_courseName.isNotEmpty && _subcourseName.isNotEmpty)
                                        const TextSpan(
                                          text: ' • ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (_subcourseName.isNotEmpty)
                                        TextSpan(
                                          text: _subcourseName,
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

                // Content Area
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                              ),
                               SizedBox(height: 16),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildCurrentPage(),
                ),
              ],
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primaryYellow,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Subjects',
                      style: TextStyle(
                        fontSize: 22,
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
                          fontSize: 14,
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

            const SizedBox(height: 32),

            if (_subjects.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.subject_rounded,
                          size: 60,
                          color: AppColors.primaryYellow.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No subjects available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please load study materials first',
                        style: TextStyle(
                          fontSize: 14,
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
                    .map((subject) => _buildSubjectCard(
                          title: subject['title']?.toString() ?? 'Unknown Subject',
                          subtitle: '${subject['units']?.length ?? 0} units available',
                          icon: Icons.subject_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => _loadUnits(
                            subject['id']?.toString() ?? '',
                            subject['title']?.toString() ?? 'Unknown Subject',
                          ),
                        ))
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                      height: 28,
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
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedSubjectName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

            const SizedBox(height: 32),

            if (_units.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.library_books_rounded,
                          size: 60,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No units available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Units for this subject will be added soon',
                        style: TextStyle(
                          fontSize: 14,
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                      height: 28,
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
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedUnitName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

            const SizedBox(height: 32),

            if (_chapters.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.warningOrange.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 60,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No chapters available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chapters for this unit will be added soon',
                        style: TextStyle(
                          fontSize: 14,
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
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideosPage() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                      height: 28,
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
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedChapterName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    '${_videos.length} video${_videos.length != 1 ? 's' : ''} available',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            if (_videos.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.videocam_off_rounded,
                          size: 60,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No videos available',
                        style: TextStyle(
                          fontSize: 18,
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
                          fontSize: 14,
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
                children: _videos
                    .map((video) => _buildVideoCard(
                          videoId: video['id']?.toString() ?? '',
                          title: video['title']?.toString() ?? 'Untitled Video',
                          duration: video['duration_minutes']?.toString() ?? 'N/A',
                        ))
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color,
                  size: 16,
                ),
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
    required String duration,
  }) {
    return GestureDetector(
      onTap: () async {
        if (videoId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video ID not available'),
              backgroundColor: AppColors.errorRed,
            ),
          );
          return;
        }
        
        // Send stored events for other videos before starting new video
        // Only for online students
        if (_studentType.toLowerCase() == 'online') {
          await _sendOtherVideoEventsBeforeStartingNewVideo(videoId);
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
              videoDuration: duration,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryYellow.withOpacity(0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 24,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (duration.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Duration: ${duration}min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grey400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
            ],
          ),
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