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
import '../../study_materials/notes/pdf_viewer_screen.dart';
import '../../subscription/subscription.dart';
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

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
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
  List<dynamic> _notes = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;
  String? _selectedUnitId;
  String? _selectedChapterId;

  final AuthService _authService = AuthService();
  late Box<PdfReadingRecord> _pdfRecordsBox;
  bool _hiveInitialized = false;

  // Subscription message state
  bool _showSubscriptionMessage = false;
  bool _hasLockedNotes = false;

  // Enhanced navigation stack to track the complete path
  final List<NavigationState> _navigationStack = [];

  // FIX: Add debouncing for API calls
  bool _isSendingData = false;
  DateTime? _lastApiCallTime;
  static const Duration _apiCallDebounceTime = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    if (!_hiveInitialized) {
      try {
        if (!Hive.isAdapterRegistered(0)) {
          Hive.registerAdapter(PdfReadingRecordAdapter());
        }
        
        if (!Hive.isBoxOpen('pdf_records_box')) {
          _pdfRecordsBox = await Hive.openBox<PdfReadingRecord>('pdf_records_box');
        } else {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
        }
        
        _hiveInitialized = true;
        debugPrint('✅ Hive initialized successfully for Notes');
      } catch (e) {
        debugPrint('❌ Error initializing Hive for Notes: $e');
        try {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
          _hiveInitialized = true;
          debugPrint('✅ Using existing Hive box for Notes');
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box for Notes: $e');
        }
      }
    }
    
    _initializeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_studentType.toLowerCase() == 'online') {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        _sendStoredReadingDataToAPI();
      }
    }
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadDataFromSharedPreferences();
    } else {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
    }
  }

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
    } catch (e) {
      _showError('Failed to retrieve access token: $e');
    }
  }

  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        _courseName = prefs.getString('profile_course') ?? 'Course';
        _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
        _subcourseId = prefs.getString('profile_subcourse_id') ?? '';
      });

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

    } catch (e) {
      debugPrint('Error loading data from SharedPreferences: $e');
      _showError('Failed to load study materials data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _reloadSubjectsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subjectsDataJson = prefs.getString('subjects_data');
      
      debugPrint('📦 Loading subjects data from SharedPreferences...');
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
          debugPrint('=== COMPLETE SUBJECTS STRUCTURE ===');
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
          debugPrint('=== END COMPLETE SUBJECTS STRUCTURE ===');
          
          // Store the properly parsed subjects
          setState(() {
            _subjects = subjects;
          });
          
          debugPrint('✅ Successfully loaded ${_subjects.length} subjects from SharedPreferences for Notes');
          
        } catch (e) {
          debugPrint('❌ Error parsing subjects data JSON: $e');
          setState(() {
            _subjects = [];
          });
        }
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Notes');
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

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
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
      debugPrint('=== LOADING UNITS/CHAPTERS FOR SUBJECT ===');
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
      debugPrint('=== LOADING CHAPTERS FOR UNIT ===');
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

  Future<void> _fetchNotes(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(chapterId);
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/notes/list_notes/?chapter_id=$encodedId';
      
      debugPrint('=== FETCHING NOTES API CALL ===');
      debugPrint('URL: $apiUrl');
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== NOTES API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          final notes = data['notes'] ?? [];
          
          final hasLockedNotes = notes.any((note) {
            final fileUrl = note['file_url']?.toString() ?? '';
            return fileUrl.isEmpty || fileUrl == 'null';
          });

          setState(() {
            _notes = notes;
            _selectedChapterId = chapterId;
            _selectedChapterName = chapterName;
            _currentPage = 'notes';
            _isLoading = false;
            _hasLockedNotes = hasLockedNotes;
          });

          // Add to navigation stack with notes data
          _navigationStack.add(NavigationState(
            pageType: 'notes',
            subjectId: _selectedSubjectId!,
            subjectName: _selectedSubjectName,
            unitId: _selectedUnitId,
            unitName: _selectedUnitName,
            chapterId: chapterId,
            chapterName: chapterName,
            hasDirectChapters: _selectedUnitId == null, // If no unit, it's direct chapters
          ));

          if (hasLockedNotes) {
            _showAndHideSubscriptionMessage();
          }
        } else {
          _showError(data['message'] ?? 'Failed to fetch notes');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        _showError('Failed to fetch notes: ${response.statusCode}');
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
      debugPrint('Error fetching notes: $e');
      _showError('Error fetching notes: $e');
      setState(() => _isLoading = false);
    } finally {
      client.close();
    }
  }

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
    debugPrint('=== BACK NAVIGATION START ===');
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
            _notes = [];
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
            
          case 'units':
            // Going back to units from chapters
            _units = previousState.unitsData;
            _chapters = [];
            _notes = [];
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
            
          case 'chapters':
            // Going back to chapters from notes
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
            _notes = [];
            _selectedChapterId = null;
            _selectedChapterName = '';
            break;
        }
        _isLoading = false;
      });
      
      debugPrint('=== BACK NAVIGATION COMPLETE ===');
      debugPrint('New current page: $_currentPage');
      debugPrint('Stack length after: ${_navigationStack.length}');
    } else {
      // If we're at the root (subjects), exit the screen
      debugPrint('At root level - exiting screen');
      _exitScreen();
    }
  }

  // Enhanced exit screen method that sends data without waiting
  void _exitScreen() {
    if (_studentType.toLowerCase() == 'online') {
      // Send reading data to backend without waiting for response
      _sendStoredReadingDataToAPI().catchError((e) {
        debugPrint('Error sending reading data on exit: $e');
        // Don't show error to user, just log it
      });
    }
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<bool> _hasStoredReadingData() async {
    try {
      return _pdfRecordsBox.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking stored reading data: $e');
      return false;
    }
  }

  // FIXED: Enhanced with debouncing to prevent multiple API calls
  Future<void> _sendStoredReadingDataToAPI() async {
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('Student type is $_studentType - skipping reading data collection');
      return;
    }

    // Check if we're already sending data
    if (_isSendingData) {
      debugPrint('📱 API call already in progress, skipping duplicate call');
      return;
    }

    // Check debounce time
    final now = DateTime.now();
    if (_lastApiCallTime != null && 
        now.difference(_lastApiCallTime!) < _apiCallDebounceTime) {
      debugPrint('📱 API call debounced, too soon since last call');
      return;
    }

    try {
      final allRecords = _pdfRecordsBox.values.toList();
      
      if (allRecords.isEmpty) {
        debugPrint('No stored note reading data found to send');
        return;
      }

      debugPrint('=== SENDING ALL STORED NOTE READING DATA TO API ===');
      debugPrint('Total records to send: ${allRecords.length}');

      List<Map<String, dynamic>> allNotesData = [];

      for (final record in allRecords) {
        final noteData = {
          'encrypted_note_id': record.encryptedNoteId,
          'readedtime': record.readedtime,
          'readed_date': record.readedDate,
        };
        allNotesData.add(noteData);
        
        debugPrint('Prepared record for encrypted_note_id: ${record.encryptedNoteId}');
      }

      if (allNotesData.isEmpty) {
        debugPrint('No valid note records to send');
        return;
      }

      final requestBody = {
        'notes': allNotesData,
      };

      // Set flags to prevent duplicate calls
      setState(() {
        _isSendingData = true;
        _lastApiCallTime = now;
      });

      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      final apiUrl = '${ApiConfig.baseUrl}/api/performance/add_readed_notes/';

      // Fire and forget - don't wait for response
      globalHttpClient.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
          ...ApiConfig.commonHeaders,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 10)).then((response) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✓ All note data sent successfully to API');
          _clearStoredReadingData().catchError((e) {
            debugPrint('Error clearing stored data: $e');
          });
        } else {
          debugPrint('✗ Failed to send note data. Status: ${response.statusCode}');
        }
        
        // Reset sending flag after completion
        if (mounted) {
          setState(() {
            _isSendingData = false;
          });
        }
      }).catchError((e) {
        debugPrint('✗ Error sending stored note records to API: $e');
        // Reset sending flag on error
        if (mounted) {
          setState(() {
            _isSendingData = false;
          });
        }
      });

    } catch (e) {
      debugPrint('✗ Error preparing to send stored note records: $e');
      // Reset sending flag on error
      if (mounted) {
        setState(() {
          _isSendingData = false;
        });
      }
    }
  }

  Future<void> _clearStoredReadingData() async {
    try {
      await _pdfRecordsBox.clear();
      debugPrint('✓ All stored note reading data cleared');
    } catch (e) {
      debugPrint('Error clearing stored note reading data: $e');
    }
  }

  Future<bool> _handleDeviceBackButton() async {
    debugPrint('=== DEVICE BACK BUTTON PRESSED ===');
    debugPrint('Current page: $_currentPage');
    debugPrint('Stack length: ${_navigationStack.length}');
    
    if (_currentPage == 'subjects' && _navigationStack.length <= 1) {
      debugPrint('At root subjects - exiting screen');
      _exitScreen();
      return false; // Don't allow default back behavior
    } else {
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
          return 'Sections';
        case 'chapters':
          return 'Chapters';
        case 'notes':
          return 'Notes';
        default:
          return 'Notes';
      }
    }
    
    switch (_currentPage) {
      case 'subjects':
        return 'Subjects';
      case 'units':
        return 'Sections';
      case 'chapters':
        return 'Chapters';
      case 'notes':
        return 'Notes';
      default:
        return 'Notes';
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
        case 'notes':
          return currentState.chapterName ?? currentState.subjectName;
        default:
          return '';
      }
    }
    return '';
  }

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
            
            Column(
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
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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

                if (_showSubscriptionMessage && _hasLockedNotes)
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

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case 'subjects':
        return _buildSubjectsPage();
      case 'units':
        return _buildUnitsPage();
      case 'chapters':
        return _buildChaptersPage();
      case 'notes':
        return _buildNotesPage();
      default:
        return _buildSubjectsPage();
    }
  }

  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

 Widget _buildSubjectsPage() {
  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      'Choose a subject to view notes',
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
                      contentCount = '${units.length} section${units.length != 1 ? 's' : ''}'; 
                    } else if (hasChapters) {
                      contentCount = '${chapters.length} chapter${chapters.length != 1 ? 's' : ''}';
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
                          'Sections',
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
                  '${_units.length} section${_units.length != 1 ? 's' : ''} available',
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
                      'No sections available', 
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sections for this subject will be added soon',
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
                        title: unit['title']?.toString() ?? 'Unknown Section',
                        subtitle: '${unit['chapters']?.length ?? 0} chapter${(unit['chapters']?.length ?? 0) != 1 ? 's' : ''} available', // Added plural handling
                        icon: Icons.library_books_rounded,
                        color: AppColors.primaryBlue,
                        onTap: () => _loadChapters(
                          unit['id']?.toString() ?? '',
                          unit['title']?.toString() ?? 'Unknown Section', 
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          subtitle: 'Tap to view notes',
                          icon: Icons.menu_book_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => _fetchNotes(
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

  Widget _buildNotesPage() {
    List<dynamic> sortedNotes = _sortNotes(_notes);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                            'Notes',
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
                    '${sortedNotes.length} note${sortedNotes.length != 1 ? 's' : ''} available',
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

            if (sortedNotes.isEmpty)
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
                          Icons.note_rounded,
                          size: 50,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No notes available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Notes for this chapter\nwill be added soon',
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
                children: sortedNotes
                    .map((note) {
                      final fileUrl = note['file_url']?.toString() ?? '';
                      final isLocked = fileUrl.isEmpty || fileUrl == 'null';
                      
                      return _buildNoteCard(
                        noteId: note['id']?.toString() ?? '',
                        title: note['title']?.toString() ?? 'Untitled Note',
                        fileUrl: fileUrl,
                        uploadedAt: note['uploaded_at']?.toString() ?? '',
                        isLocked: isLocked,
                      );
                    })
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _sortNotes(List<dynamic> notes) {
    if (notes.isEmpty) return notes;

    List<dynamic> sortedNotes = List.from(notes);

    sortedNotes.sort((a, b) {
      final fileUrlA = a['file_url']?.toString() ?? '';
      final fileUrlB = b['file_url']?.toString() ?? '';
      final isLockedA = fileUrlA.isEmpty || fileUrlA == 'null';
      final isLockedB = fileUrlB.isEmpty || fileUrlB == 'null';

      if (_studentType.toLowerCase() == 'public') {
        if (isLockedA != isLockedB) {
          return isLockedA ? 1 : -1;
        }
      }

      try {
        final dateA = a['uploaded_at']?.toString() ?? '';
        final dateB = b['uploaded_at']?.toString() ?? '';

        if (dateA.isEmpty && dateB.isEmpty) return 0;
        if (dateA.isEmpty) return 1;
        if (dateB.isEmpty) return -1;

        final parsedDateA = DateTime.parse(dateA);
        final parsedDateB = DateTime.parse(dateB);

        return parsedDateB.compareTo(parsedDateA);
      } catch (e) {
        debugPrint('Error parsing dates for sorting: $e');
        return 0;
      }
    });

    return sortedNotes;
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
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

  Widget _buildNoteCard({
    required String noteId,
    required String title,
    required String fileUrl,
    required String uploadedAt,
    required bool isLocked,
  }) {
    return GestureDetector(
      onTap: () {
        if (isLocked) {
          _showSubscriptionPopup(context);
          return;
        }

        debugPrint('=== NOTE CARD CLICKED ===');
        debugPrint('Note ID: $noteId');
        debugPrint('Title: $title');
        debugPrint('Raw File URL from API: "$fileUrl"');
        debugPrint('Student Type: $_studentType');
        
        if (fileUrl.isEmpty) {
          debugPrint('❌ File URL is empty');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF URL is empty'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        if (_accessToken == null || _accessToken!.isEmpty) {
          debugPrint('❌ Access token is null or empty');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access token not available. Please login again.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        debugPrint('Navigating to PDF viewer with URL: "$fileUrl"');
        debugPrint('Reading data collection enabled for student type: $_studentType');
        debugPrint('=== END NOTE CARD CLICK ===\n');
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PDFViewerScreen(
              pdfUrl: fileUrl,
              title: title,
              accessToken: _accessToken!,
              noteId: noteId,
              enableReadingData: _studentType.toLowerCase() == 'online', 
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
                      isLocked ? Icons.lock_outline_rounded : Icons.picture_as_pdf_rounded,
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
                        ),
                        if (uploadedAt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(uploadedAt),
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
                      isLocked ? Icons.lock_rounded : Icons.open_in_new_rounded,
                      color: isLocked ? Colors.grey : AppColors.primaryBlue,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
            
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