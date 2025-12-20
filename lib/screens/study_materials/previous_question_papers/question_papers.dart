import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../../../service/api_config.dart';
import '../../../../service/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../common/theme_color.dart';
import '../previous_question_papers/questions_pdf_view.dart';
import '../../subscription/subscription.dart';
import '../../../service/http_interceptor.dart';

// ==================== NAVIGATION STATE CLASS ====================
class NavigationState {
  final String pageType; 
  final String subjectId;
  final String subjectName;
  final List<dynamic> subjectsData; 
  final List<dynamic> questionPapersData; 

  NavigationState({
    required this.pageType,
    required this.subjectId,
    required this.subjectName,
    this.subjectsData = const [],
    this.questionPapersData = const [],
  });
}

// ==================== PROVIDER CLASS ====================
class QuestionPapersProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  
  // State variables
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'subjects';
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  String _selectedSubjectName = '';
  String _studentType = '';
  
  // Data lists
  List<dynamic> _subjects = [];
  List<dynamic> _questionPapers = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;

  late Box<PdfReadingRecord> _pdfRecordsBox;
  bool _hiveInitialized = false;

  // Subscription message state
  bool _showSubscriptionMessage = false;
  bool _hasLockedPapers = false;

  // Enhanced navigation stack to track the complete path
  final List<NavigationState> _navigationStack = [];

  // Debouncing for API calls
  bool _isSendingData = false;
  DateTime? _lastApiCallTime;
  static const Duration _apiCallDebounceTime = Duration(seconds: 5);

  // Getters
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String get currentPage => _currentPage;
  String get courseName => _courseName;
  String get subcourseName => _subcourseName;
  String get subcourseId => _subcourseId;
  String get selectedSubjectName => _selectedSubjectName;
  String get studentType => _studentType;
  List<dynamic> get subjects => _subjects;
  List<dynamic> get questionPapers => _questionPapers;
  bool get showSubscriptionMessage => _showSubscriptionMessage;
  bool get hasLockedPapers => _hasLockedPapers;
  List<NavigationState> get navigationStack => _navigationStack;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

 @override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  
  // Send stored data when app goes to background (minimized or device locked)
  // Enable for both 'online' and 'offline' students, but not 'public'
  if (_studentType.toLowerCase() == 'online' || _studentType.toLowerCase() == 'offline') {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _sendStoredReadingDataToAPI();
    }
  }
}

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _initializeHive();
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
        debugPrint('✅ Hive initialized successfully for Question Papers');
      } catch (e) {
        debugPrint('❌ Error initializing Hive for Question Papers: $e');

        try {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
          _hiveInitialized = true;
          debugPrint('✅ Using existing Hive box for Question Papers');
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box for Question Papers: $e');
        }
      }
    }
    
    await _initializeData();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadDataFromSharedPreferences();
    } else {
      _showError('Access token not found. Please login again.');
    }
  }

  // Load student type from SharedPreferences
  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _studentType = prefs.getString('profile_student_type') ?? '';
      notifyListeners();
      debugPrint('Student Type loaded: $_studentType');
    } catch (e) {
      debugPrint('Error loading student type: $e');
    }
  }

  Future<void> _getAccessToken() async {
    try {
      _accessToken = await _authService.getAccessToken();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to retrieve access token: $e');
    }
  }

  // Load data from SharedPreferences instead of API calls
  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load course and subcourse data
      _courseName = prefs.getString('profile_course') ?? 'Course';
      _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
      _subcourseId = prefs.getString('profile_subcourse_id') ?? '';

      await _reloadSubjectsFromSharedPreferences();

      // Initialize navigation stack with subjects
      _navigationStack.add(NavigationState(
        pageType: 'subjects',
        subjectId: '',
        subjectName: 'Subjects',
        subjectsData: _subjects,
      ));

      _isLoading = false;
      notifyListeners();

    } catch (e) {
      debugPrint('Error loading data from SharedPreferences: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadSubjectsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subjectsDataJson = prefs.getString('subjects_data');
      
      debugPrint('📦 Loading subjects data from SharedPreferences for Question Papers...');
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
          
          // Debug print all subjects with their titles and structure
          debugPrint('=== SUBJECTS STRUCTURE FOR QUESTION PAPERS ===');
          for (var i = 0; i < subjects.length; i++) {
            final subject = subjects[i];
            final title = subject['title']?.toString() ?? 'No Title';
            final id = subject['id']?.toString() ?? 'No ID';
            
            debugPrint('Subject $i:');
            debugPrint('  - Title: "$title"');
            debugPrint('  - ID: $id');
          }
          debugPrint('=== END SUBJECTS STRUCTURE ===');
          
          // Store the properly parsed subjects
          _subjects = subjects;
          notifyListeners();
          
          debugPrint('✅ Successfully loaded ${_subjects.length} subjects from SharedPreferences for Question Papers');
          
        } catch (e) {
          debugPrint('❌ Error parsing subjects data JSON: $e');
          _subjects = [];
          notifyListeners();
        }
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Question Papers');
        _subjects = [];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error reloading subjects from SharedPreferences: $e');
      _subjects = [];
      notifyListeners();
    }
  }

  // Helper method to get authorization headers
  Map<String, String> _getAuthHeaders() {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Access token is null or empty');
    }
    
    return {
      'Authorization': 'Bearer $_accessToken',
      ...ApiConfig.commonHeaders,
    };
  }

  // Load subjects from SharedPreferences (no API call)
  void loadSubjects() {
    if (_subjects.isEmpty) {
      return;
    }

    _currentPage = 'subjects';
    _isLoading = false;
    notifyListeners();
  }

  // Fetch question papers for a subject from API
  Future<void> fetchQuestionPapers(String subjectId, String subjectName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(subjectId);
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/notes/list_question_papers/?subject_id=$encodedId';
      
      debugPrint('=== FETCHING QUESTION PAPERS API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Method: GET');
      debugPrint('Headers: ${_getAuthHeaders()}');
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== QUESTION PAPERS API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
      
      // Use print() instead of debugPrint() to avoid masking
      print('Response Body (Raw):');
      print(response.body);
      
      // Pretty print JSON if possible
      try {
        final responseJson = jsonDecode(response.body);
        print('\nResponse Body (Formatted):');
        print(const JsonEncoder.withIndent('  ').convert(responseJson));
        
        // Print file URLs explicitly using print()
        if (responseJson['question_papers'] != null && responseJson['question_papers'] is List) {
          print('\n=== EXTRACTED FILE URLS ===');
          for (var i = 0; i < responseJson['question_papers'].length; i++) {
            final paper = responseJson['question_papers'][i];
            print('Paper ${i + 1}:');
            print('  ID: ${paper['id']}');
            print('  Title: ${paper['title']}');
            print('  File URL: ${paper['file_url']}');
          }
          print('=== END FILE URLS ===\n');
        }
      } catch (e) {
        debugPrint('Unable to format JSON: $e');
      }
      debugPrint('=== END QUESTION PAPERS API RESPONSE ===\n');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          final papers = data['question_papers'] ?? [];
          
          // Check if there are any locked papers
          final hasLockedPapers = papers.any((paper) {
            final fileUrl = paper['file_url']?.toString() ?? '';
            return fileUrl.isEmpty || fileUrl == 'null';
          });

          _questionPapers = papers;
          _selectedSubjectId = subjectId;
          _selectedSubjectName = subjectName;
          _currentPage = 'question_papers';
          _isLoading = false;
          _hasLockedPapers = hasLockedPapers;
          notifyListeners();

          // Add to navigation stack with question papers data
          _navigationStack.add(NavigationState(
            pageType: 'question_papers',
            subjectId: subjectId,
            subjectName: subjectName,
            questionPapersData: papers,
          ));

          // Show subscription message if there are locked papers
          if (hasLockedPapers) {
            _showAndHideSubscriptionMessage();
          }
        } else {
          debugPrint('Failed to fetch question papers: ${data['message'] ?? 'Unknown error'}');
          _isLoading = false;
          notifyListeners();
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        debugPrint('Failed to fetch question papers: ${response.statusCode}');
        _isLoading = false;
        notifyListeners();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      _isLoading = false;
      notifyListeners();
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching question papers: $e');
      _isLoading = false;
      notifyListeners();
    } finally {
      client.close();
    }
  }

  // Create HTTP client with custom certificate handling for development
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // Helper method to handle token expiration
  void _handleTokenExpiration() async {
    await _authService.logout();
  }

  // Show and hide subscription message with animation
  void _showAndHideSubscriptionMessage() {
    _showSubscriptionMessage = true;
    notifyListeners();
  }

  void hideSubscriptionMessage() {
    _showSubscriptionMessage = false;
    notifyListeners();
  }

  void _showError(String message) {
    _isLoading = false;
    notifyListeners();
  }

  // ENHANCED: Proper hierarchical backward navigation
  void navigateBack() {
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
      _currentPage = previousState.pageType;
      _selectedSubjectId = previousState.subjectId;
      _selectedSubjectName = previousState.subjectName;
      
      switch (previousState.pageType) {
        case 'subjects':
          // Going back to subjects - restore subjects data
          _questionPapers = [];
          _selectedSubjectId = null;
          _selectedSubjectName = '';
          break;
          
        case 'question_papers':
          // Going back to question papers from individual paper view
          _questionPapers = previousState.questionPapersData;
          break;
      }
      _isLoading = false;
      notifyListeners();
      
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
  // Enable for both 'online' and 'offline' students
  if (_studentType.toLowerCase() == 'online' || _studentType.toLowerCase() == 'offline') {
    // Send reading data to backend without waiting for response
    _sendStoredReadingDataToAPI().catchError((e) {
      debugPrint('Error sending reading data on exit: $e');
      // Don't show error to user, just log it
    });
  }
  
  // Navigation will be handled by the widget
}

  // Method to check if there is stored reading data
  Future<bool> hasStoredReadingData() async {
    try {
      return _pdfRecordsBox.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking stored reading data: $e');
      return false;
    }
  }

Future<void> _sendStoredReadingDataToAPI() async {
  // Check for both 'online' and 'offline' student types, exclude 'public'
  if (_studentType.toLowerCase() != 'online' && _studentType.toLowerCase() != 'offline') {
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
      debugPrint('No stored question paper reading data found to send');
      return;
    }

    debugPrint('=== SENDING ALL STORED QUESTION PAPER READING DATA TO API ===');
    debugPrint('Total records to send: ${allRecords.length}');

    List<Map<String, dynamic>> allQuestionPapersData = [];

    for (final record in allRecords) {
      // Prepare the question paper data (without readedtime_seconds)
      final questionPaperData = {
        'encrypted_questionpaper_id': record.encryptedNoteId,
        'readedtime': record.readedtime,
        'readed_date': record.readedDate,
      };
      allQuestionPapersData.add(questionPaperData);
      
      debugPrint('Prepared record for encrypted_questionpaper_id: ${record.encryptedNoteId}');
    }

    if (allQuestionPapersData.isEmpty) {
      debugPrint('No valid question paper records to send');
      return;
    }

    // Prepare request body with all question paper records
    final requestBody = {
      'questionpapers': allQuestionPapersData,
    };

    debugPrint('REQUEST:');
    debugPrint('Endpoint: /api/performance/add_readed_questionpaper/');
    debugPrint('Method: POST');
    debugPrint('Authorization: Bearer $_accessToken');
    debugPrint('Request Body:');
    debugPrint(const JsonEncoder.withIndent('  ').convert(requestBody));

    // Set flags to prevent duplicate calls
    _isSendingData = true;
    _lastApiCallTime = now;
    notifyListeners();

    // Fire and forget - don't wait for response
    globalHttpClient.post(
      Uri.parse('${ApiConfig.baseUrl}/api/performance/add_readed_questionpaper/'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        ...ApiConfig.commonHeaders,
      },
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 10)).then((response) {
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ All question paper data sent successfully to API');
        _clearStoredReadingData().catchError((e) {
          debugPrint('Error clearing stored data: $e');
        });
      } else {
        debugPrint('✗ Failed to send question paper data. Status: ${response.statusCode}');
      }
      
      // Reset sending flag after completion
      _isSendingData = false;
      notifyListeners();
    }).catchError((e) {
      debugPrint('✗ Error sending stored question paper records to API: $e');
      // Reset sending flag on error
      _isSendingData = false;
      notifyListeners();
    });

  } catch (e) {
    debugPrint('✗ Error preparing to send stored question paper records: $e');
    // Reset sending flag on error
    _isSendingData = false;
    notifyListeners();
  }
}

  // Method to clear all stored reading data
  Future<void> _clearStoredReadingData() async {
    try {
      await _pdfRecordsBox.clear();
      debugPrint('✓ All stored question paper reading data cleared');
    } catch (e) {
      debugPrint('Error clearing stored question paper reading data: $e');
    }
  }

 // Handle device back button press
Future<bool> handleDeviceBackButton(BuildContext context) async {
  debugPrint('=== DEVICE BACK BUTTON PRESSED ===');
  debugPrint('Current page: $_currentPage');
  debugPrint('Stack length: ${_navigationStack.length}');
  
  if (_currentPage == 'subjects' && _navigationStack.length <= 1) {
    debugPrint('At root subjects - exiting screen and navigating to home');
    
    // Send reading data to backend without waiting for response
    // Enable for both 'online' and 'offline' students
    if (_studentType.toLowerCase() == 'online' || _studentType.toLowerCase() == 'offline') {
      _sendStoredReadingDataToAPI().catchError((e) {
        debugPrint('Error sending reading data on exit: $e');
      });
    }
    
    // Navigate back to home page
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    return false; // Don't allow default back behavior
  } else {
    navigateBack();
    return false; // Don't allow default back behavior
  }
}
 
 // Method to handle back button from subjects page to home
void navigateBackToHome(BuildContext context) {
  debugPrint('=== NAVIGATING BACK TO HOME FROM SUBJECTS ===');
  
  // Send reading data to backend without waiting for response
  // Enable for both 'online' and 'offline' students
  if (_studentType.toLowerCase() == 'online' || _studentType.toLowerCase() == 'offline') {
    _sendStoredReadingDataToAPI().catchError((e) {
      debugPrint('Error sending reading data on exit: $e');
    });
  }
  
  // Navigate back to home page
  if (context.mounted) {
    Navigator.of(context).pop();
  }
}

  String getAppBarTitle() {
    if (_navigationStack.isNotEmpty) {
      final currentState = _navigationStack.last;
      switch (currentState.pageType) {
        case 'subjects':
          return 'Subjects';
        case 'question_papers':
          return 'Question Papers';
        default:
          return 'Question Papers';
      }
    }
    
    switch (_currentPage) {
      case 'subjects':
        return 'Subjects';
      case 'question_papers':
        return 'Question Papers';
      default:
        return 'Question Papers';
    }
  }

  String getAppBarSubtitle() {
    if (_navigationStack.isNotEmpty) {
      final currentState = _navigationStack.last;
      switch (currentState.pageType) {
        case 'question_papers':
          return currentState.subjectName;
        default:
          return '';
      }
    }
    return '';
  }

  // Sort question papers before displaying
  List<dynamic> sortQuestionPapers(List<dynamic> papers) {
    if (papers.isEmpty) return papers;

    // Create a copy to avoid modifying the original list
    List<dynamic> sortedPapers = List.from(papers);

    // Parse dates and determine locked status for sorting
    sortedPapers.sort((a, b) {
      final fileUrlA = a['file_url']?.toString() ?? '';
      final fileUrlB = b['file_url']?.toString() ?? '';
      final isLockedA = fileUrlA.isEmpty || fileUrlA == 'null';
      final isLockedB = fileUrlB.isEmpty || fileUrlB == 'null';

      // For public students, prioritize unlocked papers first
      if (_studentType.toLowerCase() == 'public') {
        if (isLockedA != isLockedB) {
          return isLockedA ? 1 : -1; // Unlocked papers come first
        }
      }

      // Sort by date (most recent first)
      try {
        final dateA = a['uploaded_at']?.toString() ?? '';
        final dateB = b['uploaded_at']?.toString() ?? '';

        if (dateA.isEmpty && dateB.isEmpty) return 0;
        if (dateA.isEmpty) return 1; // Papers without date go to bottom
        if (dateB.isEmpty) return -1;

        final parsedDateA = DateTime.parse(dateA);
        final parsedDateB = DateTime.parse(dateB);

        // Most recent first (descending order)
        return parsedDateB.compareTo(parsedDateA);
      } catch (e) {
        debugPrint('Error parsing dates for sorting: $e');
        return 0;
      }
    });

    return sortedPapers;
  }

  // Public method to send stored reading data (can be called from UI)
  Future<void> sendStoredReadingDataToAPI() async {
    await _sendStoredReadingDataToAPI();
  }
}

// ==================== SCREEN WIDGET ====================
class QuestionPapersScreen extends StatefulWidget {
  const QuestionPapersScreen({super.key});

  @override
  State<QuestionPapersScreen> createState() => _QuestionPapersScreenState();
}

class _QuestionPapersScreenState extends State<QuestionPapersScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => QuestionPapersProvider()..initialize(),
      builder: (context, child) {
        return Consumer<QuestionPapersProvider>(
          builder: (context, provider, child) {
            return PopScope(
              canPop: false,
              onPopInvoked: (bool didPop) async {
                if (didPop) {
                  return;
                }
                
                await provider.handleDeviceBackButton(context);
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
                                        if (provider.currentPage == 'subjects' && provider.navigationStack.length <= 1) {
                                          // On subjects page - navigate back to home
                                          provider.navigateBackToHome(context);
                                        } else {
                                          // Use normal back navigation for other pages
                                          await provider.handleDeviceBackButton(context);
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
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            provider.getAppBarTitle(),
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          if (provider.getAppBarSubtitle().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              provider.getAppBarSubtitle(),
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

                        // Subscription Message (appears only when there are locked papers)
                        if (provider.showSubscriptionMessage && provider.hasLockedPapers)
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
                          child: provider.isLoading
                              ? _buildSkeletonLoading()
                              : _buildCurrentPage(context, provider),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  Widget _buildCurrentPage(BuildContext context, QuestionPapersProvider provider) {
    switch (provider.currentPage) {
      case 'subjects':
        return _buildSubjectsPage(context, provider);
      case 'question_papers':
        return _buildQuestionPapersPage(context, provider);
      default:
        return _buildSubjectsPage(context, provider);
    }
  }

  Widget _buildSubjectsPage(BuildContext context, QuestionPapersProvider provider) {
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
                        'Choose a subject to view question papers',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${provider.subjects.length} subject${provider.subjects.length != 1 ? 's' : ''} available',
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

            if (provider.subjects.isEmpty)
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
                children: provider.subjects
                    .map((subject) => _buildSubjectCard(
                          title: subject['title']?.toString() ?? 'Unknown Subject',
                          subtitle: 'Tap to view question papers',
                          icon: Icons.quiz_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => provider.fetchQuestionPapers(
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

  Widget _buildQuestionPapersPage(BuildContext context, QuestionPapersProvider provider) {
    // Sort question papers before displaying
    List<dynamic> sortedQuestionPapers = provider.sortQuestionPapers(provider.questionPapers);

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
                            'Question Papers',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            provider.selectedSubjectName,
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
                    '${sortedQuestionPapers.length} paper${sortedQuestionPapers.length != 1 ? 's' : ''} available',
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

            if (sortedQuestionPapers.isEmpty)
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
                          Icons.quiz_rounded,
                          size: 50,
                          color: AppColors.primaryBlue.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No papers available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Question papers for this subject\nwill be added soon',
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
                children: sortedQuestionPapers
                    .map((paper) {
                      final fileUrl = paper['file_url']?.toString() ?? '';
                      final isLocked = fileUrl.isEmpty || fileUrl == 'null';
                      
                      return _buildQuestionPaperCard(
                        context: context,
                        provider: provider,
                        paperId: paper['id']?.toString() ?? '',
                        title: paper['title']?.toString() ?? 'Untitled Paper',
                        fileUrl: fileUrl,
                        uploadedAt: paper['uploaded_at']?.toString() ?? '',
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

  Widget _buildQuestionPaperCard({
    required BuildContext context,
    required QuestionPapersProvider provider,
    required String paperId,
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

        debugPrint('=== QUESTION PAPER CARD CLICKED ===');
        debugPrint('Question Paper ID: $paperId');
        debugPrint('Title: $title');
        debugPrint('Raw File URL from API: "$fileUrl"');
        debugPrint('Student Type: ${provider.studentType}');
        
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
        
        if (provider.accessToken == null || provider.accessToken!.isEmpty) {
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
      debugPrint('Reading data collection enabled for student type: ${provider.studentType}');
      debugPrint('=== END QUESTION PAPER CARD CLICK ===\n');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QuestionsPDFViewScreen(
            pdfUrl: fileUrl,
            title: title,
            accessToken: provider.accessToken!,
            questionPaperId: paperId,
            enableReadingData: provider.studentType.toLowerCase() == 'online' || provider.studentType.toLowerCase() == 'offline', // Modified this line
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
            
            // Blur effect for locked papers - only on the content area
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

  // Show subscription popup for locked papers
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