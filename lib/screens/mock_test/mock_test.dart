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
  String _currentPage = 'subjects'; // subjects, units
  
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

  // Load units for selected subject
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

  void _navigateBack() {
    setState(() {
      switch (_currentPage) {
        case 'units':
          _currentPage = 'subjects';
          _units.clear();
          _selectedSubjectId = null;
          _selectedSubjectName = '';
          break;
      }
    });
  }

  // Handle device back button press
  Future<bool> _handleDeviceBackButton() async {
    if (_currentPage == 'subjects') {
      // On subjects page - allow normal back navigation
      return true;
    } else {
      // For units page, do normal navigation
      _navigateBack();
      // Prevent default back behavior
      return false;
    }
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'subjects':
        return 'Mock Tests';
      case 'units':
        return 'Units - $_selectedSubjectName';
      default:
        return 'Mock Tests';
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
                        'Choose a subject to take mock tests',
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
                          Icons.quiz_rounded,
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
                        'Mock tests for this subject will be added soon',
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
                    .map((unit) => _buildUnitCard(
                          title: unit['title']?.toString() ?? 'Unknown Unit',
                          subtitle: 'Take mock test for this unit',
                          icon: Icons.quiz_rounded,
                          color: AppColors.primaryBlue,
                          onTap: () {
                            final unitId = unit['id']?.toString();
                            final unitName = unit['title']?.toString() ?? 'Unknown Unit';
                            
                            if (unitId != null && unitId.isNotEmpty) {
                              _navigateToMockTest(unitId, unitName);
                            } else {
                              _showError('Invalid unit ID');
                            }
                          },
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

  Widget _buildUnitCard({
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