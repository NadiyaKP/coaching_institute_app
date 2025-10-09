import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import '../../../../service/api_config.dart';
import '../../../../service/auth_service.dart';
import '../previous_question_papers/questions_pdf_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../common/theme_color.dart';

class QuestionPapersScreen extends StatefulWidget {
  const QuestionPapersScreen({super.key});

  @override
  State<QuestionPapersScreen> createState() => _QuestionPapersScreenState();
}

class _QuestionPapersScreenState extends State<QuestionPapersScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'course'; // course, subjects, question_papers
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  String _selectedSubjectName = '';
  
  // Data lists
  List<dynamic> _subjects = [];
  List<dynamic> _questionPapers = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;

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
        debugPrint('✅ Hive initialized successfully for Question Papers');
      } catch (e) {
        debugPrint('❌ Error initializing Hive for Question Papers: $e');
        // Fallback: try to use existing box if available
        try {
          _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
          _hiveInitialized = true;
          debugPrint('✅ Using existing Hive box for Question Papers');
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box for Question Papers: $e');
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
        debugPrint('✅ Reloaded ${_subjects.length} subjects from SharedPreferences for Question Papers');
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Question Papers');
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

  // Fetch question papers for a subject from API
  Future<void> _fetchQuestionPapers(String subjectId, String subjectName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() => _isLoading = true);

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(subjectId);
      final response = await client.get(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/notes/list_question_papers/?subject_id=$encodedId'),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          setState(() {
            _questionPapers = data['question_papers'] ?? [];
            _selectedSubjectId = subjectId;
            _selectedSubjectName = subjectName;
            _currentPage = 'question_papers';
            _isLoading = false;
          });
        } else {
          _showError(data['message'] ?? 'Failed to fetch question papers');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        _showError('Failed to fetch question papers: ${response.statusCode}');
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
      _showError('Error fetching question papers: $e');
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
        case 'question_papers':
          _currentPage = 'subjects';
          _questionPapers.clear(); // Only clear question papers as they come from API
          _selectedSubjectId = null;
          _selectedSubjectName = '';
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

      // Create HTTP client
      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      // API endpoint
      final apiUrl = '${ApiConfig.baseUrl}/api/performance/add_readed_questionpaper/';

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

      debugPrint('=== END BULK QUESTION PAPER API CALL ===\n');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ All question paper data sent successfully to API');
        
        // Clear all stored records after successful API call
        await _clearStoredReadingData();
        
      } else {
        debugPrint('✗ Failed to send question paper data. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Error sending stored question paper records to API: $e');
      debugPrint('=== END BULK QUESTION PAPER API CALL (ERROR) ===\n');
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
    } else if (_currentPage == 'question_papers') {
      // From question papers page, jump directly to course page
      _jumpToCoursePage();
      // Prevent default back behavior
      return false;
    } else {
      // For other pages (subjects), do normal navigation
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
      _questionPapers.clear();
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
        return 'Question Papers';
      case 'subjects':
        return 'Subjects';
      case 'question_papers':
        return 'Papers - $_selectedSubjectName';
      default:
        return 'Question Papers';
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
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        leading: _currentPage != 'course'
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // App bar back button: Navigate through hierarchy
                  // question_papers → subjects → course
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryYellow,
              AppColors.backgroundLight,
              Colors.white,
            ],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
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
    case 'question_papers':
      return _buildQuestionPapersPage();
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
          Text(
            'Your Enrolled Course',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 30),
          
          // Course Card
          Card(
            elevation: 8,
            shadowColor: AppColors.warningOrange.withOpacity(0.3),
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
                    AppColors.warningOrange.withOpacity(0.05),
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
                          color: AppColors.primaryYellow.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.school,
                          size: 32,
                          color: AppColors.primaryYellow,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _courseName.isNotEmpty ? _courseName : 'Course',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
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
                            ? AppColors.warningOrange.withOpacity(0.08)
                            : Colors.grey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _subjects.isNotEmpty
                              ? AppColors.warningOrange.withOpacity(0.3)
                              : Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.book,
                            color: _subjects.isNotEmpty 
                                ? AppColors.primaryYellow
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
                                        ? AppColors.primaryBlue
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
                                ? AppColors.warningOrange
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
          Text(
            'Select Subject',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
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
              subtitle: 'Tap to view question papers',
              icon: Icons.quiz,
              onTap: () => _fetchQuestionPapers(
                subject['id']?.toString() ?? '', 
                subject['title']?.toString() ?? 'Unknown Subject'
              ),
            )).toList(),
        ],
      ),
    ),
  );
}

Widget _buildQuestionPapersPage() {
  return SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Question Papers',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Question papers for $_selectedSubjectName',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 30),
          
          if (_questionPapers.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  Icon(
                    Icons.quiz_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No question papers available',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Question papers for this subject will be added soon',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
          else
            ..._questionPapers.map((paper) => _buildQuestionPaperCard(
              paperId: paper['id']?.toString() ?? '',
              title: paper['title']?.toString() ?? 'Untitled Paper',
              fileUrl: paper['file_url']?.toString() ?? '',
              uploadedAt: paper['uploaded_at']?.toString() ?? '',
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
    shadowColor: AppColors.warningOrange.withOpacity(0.2),
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
              AppColors.warningOrange.withOpacity(0.03),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: AppColors.primaryYellow.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryYellow.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: 24,
                color: AppColors.primaryYellow,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.primaryBlue.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.warningOrange,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.warningOrange.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 18,
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
  required String paperId,
  required String title,
  required String fileUrl,
  required String uploadedAt,
}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 4,
    shadowColor: AppColors.warningOrange.withOpacity(0.2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: InkWell(
      onTap: () {
        debugPrint('=== QUESTION PAPER CARD CLICKED ===');
        debugPrint('Question Paper ID: $paperId');
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
        debugPrint('=== END QUESTION PAPER CARD CLICK ===\n');
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuestionsPDFViewScreen(
              pdfUrl: fileUrl,  // Pass directly without any cleaning
              title: title,
              accessToken: _accessToken!,
              questionPaperId: paperId,
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
              AppColors.warningOrange.withOpacity(0.03),
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
                    color: AppColors.primaryYellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    size: 20,
                    color: AppColors.primaryYellow,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
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
            if (uploadedAt.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Uploaded: ${_formatDate(uploadedAt)}',
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
                color: AppColors.warningOrange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Question Paper',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
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