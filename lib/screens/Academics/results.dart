import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../../service/api_config.dart';
import '../../../service/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/theme_color.dart';
import '../../../service/http_interceptor.dart';

// ==================== NAVIGATION STATE CLASS ====================
class ResultsNavigationState {
  final String pageType; 
  final String subjectId;
  final String subjectName;
  final List<dynamic> subjectsData; 
  final List<dynamic> resultsData; 

  ResultsNavigationState({
    required this.pageType,
    required this.subjectId,
    required this.subjectName,
    this.subjectsData = const [],
    this.resultsData = const [],
  });
}

// ==================== PROVIDER CLASS ====================
class ResultsProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  // State variables
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'subjects';
  String _selectedSubjectName = '';
  
  // Data lists
  List<dynamic> _subjects = [];
  List<dynamic> _results = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;

  // Enhanced navigation stack to track the complete path
  final List<ResultsNavigationState> _navigationStack = [];

  // Getters
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String get currentPage => _currentPage;
  String get selectedSubjectName => _selectedSubjectName;
  List<dynamic> get subjects => _subjects;
  List<dynamic> get results => _results;
  List<ResultsNavigationState> get navigationStack => _navigationStack;

  Future<void> initialize() async {
    await _getAccessToken();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadSubjectsFromSharedPreferences();
    } else {
      _showError('Access token not found. Please login again.');
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

  // Load subjects from SharedPreferences
  Future<void> _loadSubjectsFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subjectsDataJson = prefs.getString('subjects_data');
      
      debugPrint('📦 Loading subjects data from SharedPreferences for Results...');
      debugPrint('Subjects data JSON exists: ${subjectsDataJson != null && subjectsDataJson.isNotEmpty}');
      
      if (subjectsDataJson != null && subjectsDataJson.isNotEmpty) {
        try {
          final decodedData = json.decode(subjectsDataJson);
          debugPrint('📦 Decoded data type: ${decodedData.runtimeType}');
          
          List<dynamic> subjects = [];
          
          // Handle different possible data structures (same as question papers)
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
          debugPrint('=== SUBJECTS STRUCTURE FOR RESULTS ===');
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

          // Initialize navigation stack with subjects
          _navigationStack.add(ResultsNavigationState(
            pageType: 'subjects',
            subjectId: '',
            subjectName: 'Subjects',
            subjectsData: _subjects,
          ));

          _isLoading = false;
          notifyListeners();
          
          debugPrint('✅ Successfully loaded ${_subjects.length} subjects from SharedPreferences for Results');
          
        } catch (e) {
          debugPrint('❌ Error parsing subjects data JSON: $e');
          _subjects = [];
          _isLoading = false;
          notifyListeners();
        }
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Results');
        _subjects = [];
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error loading subjects from SharedPreferences: $e');
      _subjects = [];
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create HTTP client with custom certificate handling
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
  }

  // Fetch exam results for a subject from API
  Future<void> fetchResults(String subjectId, String subjectName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(subjectId);
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/attendance/exams/my_marks?subject_id=$encodedId';
      
      debugPrint('=== FETCHING EXAM RESULTS API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Method: GET');
      debugPrint('Headers: ${_getAuthHeaders()}');
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== EXAM RESULTS API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
      
      // Pretty print JSON response
      try {
        final responseJson = jsonDecode(response.body);
        debugPrint('Response Body (Formatted):');
        debugPrint(const JsonEncoder.withIndent('  ').convert(responseJson));
      } catch (e) {
        debugPrint('Response Body: ${response.body}');
      }
      debugPrint('=== END EXAM RESULTS API RESPONSE ===\n');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          final results = data['results'] ?? [];
          
          // Sort results by exam_date in descending order (latest first)
          results.sort((a, b) {
            try {
              final dateA = DateTime.parse(a['exam_date'] ?? '');
              final dateB = DateTime.parse(b['exam_date'] ?? '');
              return dateB.compareTo(dateA); // Descending order
            } catch (e) {
              return 0; // Keep original order if parsing fails
            }
          });
          
          _results = results;
          _selectedSubjectId = subjectId;
          _selectedSubjectName = subjectName;
          _currentPage = 'results';
          _isLoading = false;
          notifyListeners();

          // Add to navigation stack with results data
          _navigationStack.add(ResultsNavigationState(
            pageType: 'results',
            subjectId: subjectId,
            subjectName: subjectName,
            resultsData: results,
          ));

        } else {
          debugPrint('Failed to fetch results: ${data['message'] ?? 'Unknown error'}');
          _isLoading = false;
          notifyListeners();
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        debugPrint('Failed to fetch results: ${response.statusCode}');
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
      debugPrint('Error fetching results: $e');
      _isLoading = false;
      notifyListeners();
    } finally {
      client.close();
    }
  }

  void _showError(String message) {
    _isLoading = false;
    notifyListeners();
  }

  // ENHANCED: Proper hierarchical backward navigation
  void navigateBack() {
    debugPrint('=== RESULTS BACK NAVIGATION START ===');
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
          _results = [];
          _selectedSubjectId = null;
          _selectedSubjectName = '';
          break;
          
        case 'results':
          // Going back to results from individual result view (if needed)
          _results = previousState.resultsData;
          break;
      }
      _isLoading = false;
      notifyListeners();
      
      debugPrint('=== RESULTS BACK NAVIGATION COMPLETE ===');
      debugPrint('New current page: $_currentPage');
      debugPrint('Stack length after: ${_navigationStack.length}');
    } else {
      // If we're at the root (subjects), exit the screen
      debugPrint('At root level - exiting screen');
      _exitScreen();
    }
  }

  void _exitScreen() {
    // Navigation will be handled by the widget
  }

  // Handle device back button press
  Future<bool> handleDeviceBackButton(BuildContext context) async {
    debugPrint('=== RESULTS DEVICE BACK BUTTON PRESSED ===');
    debugPrint('Current page: $_currentPage');
    debugPrint('Stack length: ${_navigationStack.length}');
    
    if (_currentPage == 'subjects' && _navigationStack.length <= 1) {
      debugPrint('At root subjects - exiting screen and navigating to home');
      
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
    debugPrint('=== NAVIGATING BACK TO HOME FROM RESULTS SUBJECTS ===');
    
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
          return 'Results';
        case 'results':
          return 'Results';
        default:
          return 'Results';
      }
    }
    
    switch (_currentPage) {
      case 'subjects':
        return 'Results';
      case 'results':
        return 'Results';
      default:
        return 'Results';
    }
  }

  String getAppBarSubtitle() {
    if (_navigationStack.isNotEmpty) {
      final currentState = _navigationStack.last;
      switch (currentState.pageType) {
        case 'results':
          return currentState.subjectName;
        default:
          return '';
      }
    }
    return '';
  }
}

// ==================== SCREEN WIDGET ====================
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({Key? key}) : super(key: key);

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ResultsProvider()..initialize(),
      builder: (context, child) {
        return Consumer<ResultsProvider>(
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

  Widget _buildCurrentPage(BuildContext context, ResultsProvider provider) {
    switch (provider.currentPage) {
      case 'subjects':
        return _buildSubjectsPage(context, provider);
      case 'results':
        return _buildResultsPage(context, provider);
      default:
        return _buildSubjectsPage(context, provider);
    }
  }

  Widget _buildSubjectsPage(BuildContext context, ResultsProvider provider) {
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
                        'Choose a subject to view exam results',
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
                          Icons.assessment_rounded,
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
                          subtitle: 'View exam results',
                          icon: Icons.assessment_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () => provider.fetchResults(
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

  Widget _buildResultsPage(BuildContext context, ResultsProvider provider) {
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Exam Results',
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
                    '${provider.results.length} exam${provider.results.length != 1 ? 's' : ''} found',
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

            if (provider.results.isEmpty)
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
                          Icons.assignment_rounded,
                          size: 50,
                          color: AppColors.primaryYellow.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No exam results available',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Results will appear here once\nexams are conducted',
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
                children: provider.results
                    .map((result) => _buildResultCard(
                          examTitle: result['exam_title']?.toString() ?? 'Unknown Exam',
                          marks: (result['marks'] ?? 0).toDouble(),
                          examDate: result['exam_date']?.toString() ?? '',
                          hasAttended: result['has_attended'] ?? false,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      final List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      
      return '${date.day} ${months[date.month - 1]}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildResultCard({
    required String examTitle,
    required double marks,
    required String examDate,
    required bool hasAttended,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exam Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assignment_rounded,
                    color: AppColors.primaryBlue,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    examTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Divider
            Container(
              height: 1,
              color: AppColors.grey200,
            ),
            
            const SizedBox(height: 12),
            
            // Marks and Date Row
            Row(
              children: [
                // Marks Section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 14,
                            color: AppColors.textGrey,
                          ),
                           SizedBox(width: 5),
                           Text(
                            'Marks',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textGrey,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (hasAttended)
                        Text(
                          '${marks.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.successGreen,
                            letterSpacing: -0.5,
                          ),
                        )
                      else
                        const Text(
                          'Not Attended',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.errorRed,
                            letterSpacing: -0.1,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Vertical Divider
                Container(
                  width: 1,
                  height: 45,
                  color: AppColors.grey200,
                ),
                
                const SizedBox(width: 14),
                
                // Date Section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: AppColors.textGrey,
                          ),
                           SizedBox(width: 6),
                           Text(
                            'Exam Date',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textGrey,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(examDate),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Curved Header Clipper
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