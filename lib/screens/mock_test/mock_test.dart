import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/service/auth_service.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../common/theme_color.dart';
import 'mock_test_view.dart';

class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  bool _isLoading = true;
  String? _accessToken;
  
  // Navigation state
  String _currentPage = 'course'; // course, subjects, units
  
  // Course data from SharedPreferences
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  
  // Data lists
  List<dynamic> _subjects = [];
  List<dynamic> _units = [];
  
  // Selected IDs for navigation
  String? _selectedSubjectId;
  String _selectedSubjectName = '';

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeData();
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

      debugPrint('========== LOADED MOCK TEST DATA ==========');
      debugPrint('Course Name: $_courseName');
      debugPrint('Subcourse Name: $_subcourseName');
      debugPrint('Subcourse ID: $_subcourseId');
      debugPrint('Subjects Count: ${_subjects.length}');
      debugPrint('==========================================');

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
        debugPrint('✅ Reloaded ${_subjects.length} subjects from SharedPreferences for Mock Tests');
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Mock Tests');
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

  // Fetch subjects from API and store in SharedPreferences
  Future<void> _fetchAndStoreSubjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      final String? encryptedId = prefs.getString('profile_subcourse_id');
      final String? accessToken = prefs.getString('accessToken');
      
      if (encryptedId == null || encryptedId.isEmpty) {
        debugPrint('Error: profile_subcourse_id not found in SharedPreferences');
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login and select a course first'),
              backgroundColor: AppColors.warningOrange,
            ),
          );
        }
        return;
      }

      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('Error: accessToken not found in SharedPreferences');
        setState(() {
          _isLoading = false;
        });
        _navigateToLogin();
        return;
      }

      String encodedId = Uri.encodeComponent(encryptedId);
      String apiUrl = '${ApiConfig.baseUrl}/api/course/all/?subcourse_id=$encodedId';
      
      debugPrint('Fetching subjects from: $apiUrl');
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('Response Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          await prefs.setString('subjects_data', json.encode(responseData['subjects']));
          
          final List<dynamic> subjects = responseData['subjects'];
          await prefs.setInt('subjects_count', subjects.length);
          
          debugPrint('✅ Subjects data stored successfully!');
          debugPrint('Total subjects: ${subjects.length}');
          
          // Reload subjects from SharedPreferences
          await _reloadSubjectsFromSharedPreferences();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Subjects loaded successfully!'),
                backgroundColor: AppColors.successGreen,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('Error: API returned success: false');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        debugPrint('Error: Failed to fetch subjects. Status code: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load subjects: ${response.statusCode}'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Exception occurred while fetching subjects: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
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

  // Load subjects from SharedPreferences or fetch from API
  Future<void> _loadSubjects() async {
    if (_subjects.isEmpty) {
      // No subjects in SharedPreferences, fetch from API
      await _fetchAndStoreSubjects();
    }
    
    // Only navigate if subjects are now available
    if (_subjects.isNotEmpty) {
      setState(() {
        _currentPage = 'subjects';
      });
    }
  }

  // Load units for selected subject - FIXED VERSION
  void _loadUnits(String subjectId, String subjectName) {
    debugPrint('========== LOADING UNITS ==========');
    debugPrint('Subject ID: $subjectId');
    debugPrint('Subject Name: $subjectName');
    debugPrint('Available subjects count: ${_subjects.length}');
    
    // Find the subject
    dynamic subject;
    try {
      subject = _subjects.firstWhere(
        (s) => s['id']?.toString() == subjectId,
        orElse: () => null,
      );
    } catch (e) {
      debugPrint('Error finding subject: $e');
      subject = null;
    }

    if (subject != null) {
      debugPrint('✅ Found subject: ${subject['title']}');
      debugPrint('Subject data keys: ${subject.keys.toList()}');
      
      if (subject['units'] != null) {
        final List<dynamic> units = subject['units'] is List 
            ? subject['units'] 
            : [];
        
        debugPrint('Units count: ${units.length}');
        
        if (units.isNotEmpty) {
          setState(() {
            _units = List.from(units); // Create a new list copy
            _selectedSubjectId = subjectId;
            _selectedSubjectName = subjectName;
            _currentPage = 'units';
          });
          
          debugPrint('✅ Successfully loaded ${_units.length} units for subject: $subjectName');
          debugPrint('Units: ${_units.map((u) => u['title']).toList()}');
        } else {
          debugPrint('⚠️ Units list is empty');
          _showError('No units found for this subject');
        }
      } else {
        debugPrint('⚠️ No units field found in subject');
        _showError('No units found for this subject');
      }
    } else {
      debugPrint('❌ Subject not found with ID: $subjectId');
      debugPrint('Available subject IDs: ${_subjects.map((s) => s['id']?.toString()).toList()}');
      _showError('Subject not found. Please try again.');
    }
    debugPrint('===================================');
  }

  // Navigate to Mock Test View
  void _navigateToMockTest(String unitId, String unitName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MockTestViewScreen(
          unitId: unitId,
          unitName: unitName,
          accessToken: _accessToken!,
        ),
      ),
    );
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

  // MODIFIED: Keep track of selected subject ID
  void _navigateBack() {
    setState(() {
      switch (_currentPage) {
        case 'subjects':
          _currentPage = 'course';
          break;
        case 'units':
          _currentPage = 'subjects';
          _units.clear();
          // Keep _selectedSubjectId and _selectedSubjectName for potential re-navigation
          // But clear them if you want a fresh state
          _selectedSubjectId = null;
          _selectedSubjectName = '';
          break;
      }
    });
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'course':
        return 'Mock Test';
      case 'subjects':
        return 'Subjects';
      case 'units':
        return 'Units - $_selectedSubjectName';
      default:
        return 'Mock Test';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentPage == 'course',
      onPopInvoked: (bool didPop) async {
        if (!didPop && _currentPage != 'course') {
          _navigateBack();
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
                  onPressed: _navigateBack,
                )
              : null,
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
              stops: const [0.0, 0.3, 1.0],
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
      case 'units':
        return _buildUnitsPage();
      default:
        return _buildCoursePage();
    }
  }

  Widget _buildCoursePage() {
    return SafeArea(
      child: SingleChildScrollView(
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
                      onTap: _loadSubjects,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warningOrange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warningOrange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.book,
                              color: AppColors.primaryYellow,
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
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tap to view subjects',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: AppColors.warningOrange,
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
                  ],
                ),
              )
            else
              ..._subjects.map((subject) => _buildListCard(
                title: subject['title']?.toString() ?? 'Unknown Subject',
                subtitle: 'Tap to view units',
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
            Text(
              'Units',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Units for $_selectedSubjectName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            
            if (_units.isEmpty)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 50),
                    Icon(
                      Icons.list_alt,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No units available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._units.map((unit) => _buildListCard(
                title: unit['title']?.toString() ?? 'Untitled Unit',
                subtitle: '${unit['chapters']?.length ?? 0} chapters',
                icon: Icons.folder_open,
                onTap: () {
                  final unitId = unit['id']?.toString();
                  final unitName = unit['title']?.toString() ?? 'Untitled Unit';
                  
                  if (unitId != null && unitId.isNotEmpty) {
                    _navigateToMockTest(unitId, unitName);
                  } else {
                    _showError('Invalid unit ID');
                  }
                },
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
}