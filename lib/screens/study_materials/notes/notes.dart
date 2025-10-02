import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../service/api_config.dart';
import '../../../service/auth_service.dart';
import 'package:path_provider/path_provider.dart';
import '../notes/pdf_viewer_screen.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'course'; // course, subjects, units, chapters, notes
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  String _selectedSubjectName = '';
  String _selectedUnitName = '';
  String _selectedChapterName = '';
  
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
        debugPrint('✅ Hive initialized successfully');
      } catch (e) {
        debugPrint('❌ Error initializing Hive: $e');
        // Fallback: try to use existing box if available
        try {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
          _hiveInitialized = true;
          debugPrint('✅ Using existing Hive box');
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box: $e');
        }
      }
    }
    
    _initializeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Don't close the box here as it might be used by other parts of the app
    // Only close if you're sure it won't be used again
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Send stored data when app goes to background (minimized or device locked)
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _sendStoredReadingDataToAPI();
    }
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadDataFromSharedPreferences();
    } else {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
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
        debugPrint('✅ Reloaded ${_subjects.length} subjects from SharedPreferences');
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences');
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

  // Fetch notes for a chapter from API (this still calls the API)
  Future<void> _fetchNotes(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(chapterId);
      final response = await client.get(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/notes/list_notes?chapter_id=$encodedId'),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          setState(() {
            _notes = data['notes'] ?? [];
            _selectedChapterId = chapterId;
            _selectedChapterName = chapterName;
            _currentPage = 'notes';
            _isLoading = false;
          });
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
      _showError('Error fetching notes: $e');
      setState(() => _isLoading = false);
    } finally {
      client.close();
    }
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
          _currentPage = 'course';
          // Don't clear subjects when going back to course
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

  // Method to send all stored reading data to API (only called from course page back button and app lifecycle)
  Future<void> _sendStoredReadingDataToAPI() async {
    try {
      final allRecords = _pdfRecordsBox.values.toList();
      
      if (allRecords.isEmpty) {
        debugPrint('No stored reading data found to send');
        return;
      }

      debugPrint('=== SENDING ALL STORED READING DATA TO API ===');
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
        debugPrint('No valid records to send');
        return;
      }

      // Prepare request body with all notes records
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

      debugPrint('=== END BULK API CALL ===\n');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ All data sent successfully to API');
        
        // Clear all stored records after successful API call
        await _clearStoredReadingData();
        
      } else {
        debugPrint('✗ Failed to send data. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Error sending stored records to API: $e');
      debugPrint('=== END BULK API CALL (ERROR) ===\n');
    }
  }

  // Method to clear all stored reading data
  Future<void> _clearStoredReadingData() async {
    try {
      await _pdfRecordsBox.clear();
      debugPrint('✓ All stored reading data cleared');
    } catch (e) {
      debugPrint('Error clearing stored reading data: $e');
    }
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    if (_currentPage == 'course') {
      // On course page - check for stored data and send if exists
      final hasData = await _hasStoredReadingData();
      if (hasData) {
        // Send data in background without waiting for response
        _sendStoredReadingDataToAPI();
      }
      // Allow normal back navigation
      return true;
    } else if (_currentPage == 'notes') {
      // From notes page, jump directly to course page
      _jumpToCoursePage();
      // Prevent default back behavior
      return false;
    } else {
      // For other pages (subjects, units, chapters), do normal navigation
      _navigateBack();
      // Prevent default back behavior
      return false;
    }
  }

  // Method to jump directly to course page and reload data
  void _jumpToCoursePage() {
    setState(() {
      _isLoading = true;
      _currentPage = 'course';
      _notes.clear();
      _chapters.clear();
      _units.clear();
      _selectedChapterId = null;
      _selectedChapterName = '';
      _selectedUnitId = null;
      _selectedUnitName = '';
      _selectedSubjectId = null;
      _selectedSubjectName = '';
    });
    
    // Reload the data for course page
    _reloadCoursePageData();
  }

  // Reload data specifically for course page
  Future<void> _reloadCoursePageData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Reload course and subcourse data
      setState(() {
        _courseName = prefs.getString('profile_course') ?? 'Course';
        _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
        _subcourseId = prefs.getString('profile_subcourse_id') ?? '';
      });

      // Reload subjects data
      await _reloadSubjectsFromSharedPreferences();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error reloading course page data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'course':
        return 'Notes';
      case 'subjects':
        return 'Subjects';
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
        appBar: AppBar(
          title: Text(
            _getAppBarTitle(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          backgroundColor: const Color(0xFF2196F3),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          leading: _currentPage != 'course'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    // App bar back button: Navigate through hierarchy
                    // notes → chapters → units → subjects → course
                    _navigateBack();
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    // Only send stored data when navigating back FROM COURSE PAGE
                    final hasData = await _hasStoredReadingData();
                    if (hasData) {
                      // Send data in background without waiting
                      _sendStoredReadingDataToAPI();
                    }
                    // Navigate immediately without waiting for API response
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  },
                ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2196F3),
                Color(0xFFE3F2FD),
                Colors.white,
              ],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                  ),
                )
              : _buildCurrentPage(),
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case 'course':
        return _buildCoursePage();
      case 'subjects':
        return _buildSubjectsPage();
      case 'units':
        return _buildUnitsPage();
      case 'chapters':
        return _buildChaptersPage();
      case 'notes':
        return _buildNotesPage();
      default:
        return _buildCoursePage();
    }
  }

  Widget _buildCoursePage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Your Enrolled Course',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 30),
            
            // Course Card
            Card(
              elevation: 8,
              shadowColor: const Color(0xFF2196F3).withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFF2196F3).withOpacity(0.05),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 60,
                          width: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school,
                            size: 32,
                            color: Color(0xFF2196F3),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _courseName.isNotEmpty ? _courseName : 'Course',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Course',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Subcourse Card
                    InkWell(
                      onTap: _subjects.isNotEmpty ? _loadSubjects : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _subjects.isNotEmpty 
                              ? const Color(0xFF2196F3).withOpacity(0.08)
                              : Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _subjects.isNotEmpty
                                ? const Color(0xFF2196F3).withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.book,
                              color: _subjects.isNotEmpty 
                                  ? const Color(0xFF2196F3)
                                  : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _subcourseName.isNotEmpty ? _subcourseName : 'Subcourse',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _subjects.isNotEmpty 
                                          ? Colors.black87 
                                          : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _subjects.isNotEmpty 
                                        ? 'Tap to view ${_subjects.length} subjects' 
                                        : 'No subjects available',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _subjects.isNotEmpty 
                                          ? Colors.black54 
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              color: _subjects.isNotEmpty 
                                  ? const Color(0xFF2196F3)
                                  : Colors.grey,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Select Subject',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a subject from $_subcourseName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            
            if (_subjects.isEmpty)
              const Center(
                child: Column(
                  children: [
                    SizedBox(height: 50),
                    Icon(
                      Icons.subject,
                      size: 80,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No subjects available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please load study materials first',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._subjects.map((subject) => _buildListCard(
                title: subject['title']?.toString() ?? 'Unknown Subject',
                subtitle: '${subject['units']?.length ?? 0} units available',
                icon: Icons.subject,
                onTap: () => _loadUnits(
                  subject['id']?.toString() ?? '', 
                  subject['title']?.toString() ?? 'Unknown Subject'
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitsPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Select Unit',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a unit from $_selectedSubjectName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            
            if (_units.isEmpty)
              const Center(
                child: Column(
                  children: [
                    SizedBox(height: 50),
                    Icon(
                      Icons.library_books,
                      size: 80,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No units available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._units.map((unit) => _buildListCard(
                title: unit['title']?.toString() ?? 'Unknown Unit',
                subtitle: '${unit['chapters']?.length ?? 0} chapters available',
                icon: Icons.library_books,
                onTap: () => _loadChapters(
                  unit['id']?.toString() ?? '', 
                  unit['title']?.toString() ?? 'Unknown Unit'
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildChaptersPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Select Chapter',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a chapter from $_selectedUnitName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            
            if (_chapters.isEmpty)
              const Center(
                child: Column(
                  children: [
                    SizedBox(height: 50),
                    Icon(
                      Icons.menu_book,
                      size: 80,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No chapters available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._chapters.map((chapter) => _buildListCard(
                title: chapter['title']?.toString() ?? 'Unknown Chapter',
                subtitle: 'Tap to view notes',
                icon: Icons.menu_book,
                onTap: () => _fetchNotes(
                  chapter['id']?.toString() ?? '', 
                  chapter['title']?.toString() ?? 'Unknown Chapter'
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Notes',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Notes for $_selectedChapterName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            
            if (_notes.isEmpty)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    Icon(
                      Icons.note_alt_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notes available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Notes for this chapter will be added soon',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._notes.map((note) => _buildNoteCard(
                noteId: note['id']?.toString() ?? '',
                title: note['title']?.toString() ?? 'Untitled Note',
                fileUrl: note['file_url']?.toString() ?? '',
                dateUploaded: note['uploaded_at']?.toString() ?? '',
              )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: const Color(0xFF2196F3).withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFF2196F3).withOpacity(0.03),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: const Color(0xFF2196F3),
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
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFF2196F3),
                size: 16,
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
      } catch (e) {}
      return dateString.isNotEmpty ? dateString : 'Unknown date';
    }
  }

 Widget _buildNoteCard({
  required String noteId,
  required String title,
  required String fileUrl,
  required String dateUploaded,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 4,
    shadowColor: const Color(0xFF2196F3).withOpacity(0.2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: InkWell(
      onTap: () {
        debugPrint('=== NOTE CARD CLICKED ===');
        debugPrint('Note ID: $noteId');
        debugPrint('Title: $title');
        debugPrint('Raw File URL from API: "$fileUrl"');
        
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
        debugPrint('=== END NOTE CARD CLICK ===\n');
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PDFViewerScreen(
              pdfUrl: fileUrl,  // Pass directly without any cleaning
              title: title,
              accessToken: _accessToken!,
              noteId: noteId,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFF2196F3).withOpacity(0.03),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    size: 20,
                    color: Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 20,
                  color: Colors.grey[600],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.visibility,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  'PDF File • Tap to view',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            if (dateUploaded.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Uploaded: ${_formatDate(dateUploaded)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'PDF Document',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF2196F3),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}