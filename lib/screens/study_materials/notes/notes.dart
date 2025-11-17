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

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'subjects'; // subjects, units, chapters, notes
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    // Check if Hive is already initialized for this adapter
    if (!_hiveInitialized) {
      try {
        // Check if adapter is already registered
        if (!Hive.isAdapterRegistered(0)) {
          Hive.registerAdapter(PdfReadingRecordAdapter());
        }
        
        // Initialize Hive if not already initialized
        if (!Hive.isBoxOpen('pdf_records_box')) {
          _pdfRecordsBox = await Hive.openBox<PdfReadingRecord>('pdf_records_box');
        } else {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
        }
        
        _hiveInitialized = true;
        debugPrint('✅ Hive initialized successfully for Notes');
      } catch (e) {
        debugPrint('❌ Error initializing Hive for Notes: $e');
        // Fallback: try to use existing box if available
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
    
    // Send stored data when app goes to background (minimized or device locked)
    // Only for online students
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
    } catch (e) {
      _showError('Failed to retrieve access token: $e');
    }
  }

  // Load data from SharedPreferences instead of API calls
  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load course and subcourse data
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

    } catch (e) {
      debugPrint('Error loading data from SharedPreferences: $e');
      _showError('Failed to load study materials data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Reload subjects from SharedPreferences (used when returning to course page)
  Future<void> _reloadSubjectsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subjectsDataJson = prefs.getString('subjects_data');
      if (subjectsDataJson != null && subjectsDataJson.isNotEmpty) {
        final List<dynamic> subjects = json.decode(subjectsDataJson);
        setState(() {
          _subjects = subjects;
        });
        debugPrint('✅ Reloaded ${_subjects.length} subjects from SharedPreferences for Notes');
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Notes');
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

  // Create HTTP client with custom certificate handling for development
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
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

  // Helper method to handle token expiration
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

  // Fetch notes for a chapter from API
  Future<void> _fetchNotes(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(chapterId);
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/notes/list_notes?chapter_id=$encodedId';
      
      debugPrint('=== FETCHING NOTES API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Method: GET');
      debugPrint('Headers: ${_getAuthHeaders()}');
      
      final response = await client.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== NOTES API RESPONSE ===');
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
        if (responseJson['notes'] != null && responseJson['notes'] is List) {
          print('\n=== EXTRACTED FILE URLS ===');
          for (var i = 0; i < responseJson['notes'].length; i++) {
            final note = responseJson['notes'][i];
            print('Note ${i + 1}:');
            print('  ID: ${note['id']}');
            print('  Title: ${note['title']}');
            print('  File URL: ${note['file_url']}');
          }
          print('=== END FILE URLS ===\n');
        }
      } catch (e) {
        debugPrint('Unable to format JSON: $e');
      }
      debugPrint('=== END NOTES API RESPONSE ===\n');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          final notes = data['notes'] ?? [];
          
          // Check if there are any locked notes
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

          // Show subscription message if there are locked notes
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

  void _navigateBack() {
    setState(() {
      switch (_currentPage) {
        case 'subjects':
          // When going back from subjects page, check for stored data and send if exists
          // Only for online students
          if (_studentType.toLowerCase() == 'online') {
            _sendStoredReadingDataToAPI();
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
        case 'notes':
          _currentPage = 'chapters';
          _notes.clear(); // Only clear notes as they come from API
          _selectedChapterId = null;
          _selectedChapterName = '';
          break;
      }
    });
  }

  // Method to check if there is stored reading data
  Future<bool> _hasStoredReadingData() async {
    try {
      return _pdfRecordsBox.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking stored reading data: $e');
      return false;
    }
  }

  // Method to send all stored reading data to API (only called from subjects page back button and app lifecycle)
  Future<void> _sendStoredReadingDataToAPI() async {
    // Only send data for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('Student type is $_studentType - skipping reading data collection');
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
        // Prepare the note data (without readedtime_seconds)
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

      // Prepare request body with all note records
      final requestBody = {
        'notes': allNotesData,
      };

      debugPrint('REQUEST:');
      debugPrint('Endpoint: /api/performance/add_readed_notes/');
      debugPrint('Method: POST');
      debugPrint('Authorization: Bearer $_accessToken');
      debugPrint('Request Body:');
      debugPrint(const JsonEncoder.withIndent('  ').convert(requestBody));

      // Create HTTP client
      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      // API endpoint
      final apiUrl = '${ApiConfig.baseUrl}/api/performance/add_readed_notes/';

      debugPrint('Full URL: $apiUrl');

      // Send POST request
      final response = await httpClient.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
          ...ApiConfig.commonHeaders,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      debugPrint('\nRESPONSE:');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');

      // Pretty print JSON response if possible
      try {
        final responseJson = jsonDecode(response.body);
        debugPrint('Response Body:');
        debugPrint(const JsonEncoder.withIndent('  ').convert(responseJson));
      } catch (e) {
        debugPrint('Response Body: ${response.body}');
      }

      debugPrint('=== END BULK NOTES API CALL ===\n');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ All note data sent successfully to API');
        
        // Clear all stored records after successful API call
        await _clearStoredReadingData();
        
      } else {
        debugPrint('✗ Failed to send note data. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Error sending stored note records to API: $e');
      debugPrint('=== END BULK NOTES API CALL (ERROR) ===\n');
    }
  }

  // Method to clear all stored reading data
  Future<void> _clearStoredReadingData() async {
    try {
      await _pdfRecordsBox.clear();
      debugPrint('✓ All stored note reading data cleared');
    } catch (e) {
      debugPrint('Error clearing stored note reading data: $e');
    }
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    if (_currentPage == 'subjects') {
      // On subjects page - check for stored data and send if exists
      // Only for online students
      if (_studentType.toLowerCase() == 'online') {
        final hasData = await _hasStoredReadingData();
        if (hasData) {
          // Send data in background without waiting for response
          _sendStoredReadingDataToAPI();
        }
      }
      // Allow normal back navigation
      return true;
    } else if (_currentPage == 'notes') {
      // From notes page, go back to chapters page
      _navigateBack();
      // Prevent default back behavior
      return false;
    } else {
      // For other pages (units, chapters), do normal navigation
      _navigateBack();
      // Prevent default back behavior
      return false;
    }
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'subjects':
        return 'Notes';
      case 'units':
        return 'Units - $_selectedSubjectName';
      case 'chapters':
        return 'Chapters - $_selectedUnitName';
      case 'notes':
        return 'Notes - $_selectedChapterName';
      default:
        return 'Notes';
    }
  }

  // Show subscription popup for locked notes
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
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
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
                                    final hasData = await _hasStoredReadingData();
                                    if (hasData) {
                                      _sendStoredReadingDataToAPI();
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
                      ],
                    ),
                  ),
                ),

                // Subscription Message (appears only when there are locked notes)
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
      case 'notes':
        return _buildNotesPage();
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
                            _selectedUnitName,
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
                    '${_notes.length} note${_notes.length != 1 ? 's' : ''} available',
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

            if (_notes.isEmpty)
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
                children: _notes
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
                    // maxLines removed
                    // overflow removed
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
          
          // Blur effect for locked notes - only on the content area
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