import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/service/auth_service.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../common/theme_color.dart';
import 'mock_test_view.dart';
import 'descriptive_practice.dart'; 
import '../../common/bottom_navbar.dart';
import '../view_profile.dart';
import '../settings/settings.dart';
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

class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  bool _isLoading = true;
  String? _accessToken;
  bool _showPremiumBanner = false;
  
  // Navigation state
  String _currentPage = 'subjects';
  
  // Course data from SharedPreferences
  String _courseName = '';
  String _subcourseName = '';
  String _subcourseId = '';
  
  // Profile data for drawer
  String _userName = '';
  String _userEmail = '';
  bool _profileCompleted = false;
  
  // Data lists - Updated to include chapters
  List<dynamic> _subjects = [];
  List<dynamic> _units = [];
  List<dynamic> _chapters = [];
  
  // Selected IDs for navigation - Updated to include chapters
  String? _selectedSubjectId;
  String? _selectedUnitId;
  String _selectedSubjectName = '';
  String _selectedUnitName = '';
  String _selectedChapterName = '';

  // Bottom Navigation Bar
  int _currentIndex = 2; // Mock Test is at index 2
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _studentType = '';

  // Practice type selection
  String _selectedPracticeType = 'mcq'; 

  final AuthService _authService = AuthService();

  // Enhanced navigation stack to track the complete path
  final List<NavigationState> _navigationStack = [];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadStudentType();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('profile_name') ?? 'User Name';
        _userEmail = prefs.getString('profile_email') ?? '';
        _profileCompleted = prefs.getBool('profile_completed') ?? false;
      });
    } catch (e) {
      debugPrint('Error loading profile data for drawer: $e');
    }
  }

  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _studentType = prefs.getString('profile_student_type') ?? '';
      });
    } catch (e) {
      debugPrint('Error loading student type: $e');
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
      
      debugPrint('📦 Loading subjects data from SharedPreferences for Mock Tests...');
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
          debugPrint('=== COMPLETE SUBJECTS STRUCTURE FOR MOCK TESTS ===');
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
          debugPrint('=== END COMPLETE SUBJECTS STRUCTURE FOR MOCK TESTS ===');
          
          // Store the properly parsed subjects
          setState(() {
            _subjects = subjects;
          });
          
          debugPrint('✅ Successfully loaded ${_subjects.length} subjects from SharedPreferences for Mock Tests');
          
        } catch (e) {
          debugPrint('❌ Error parsing subjects data JSON: $e');
          setState(() {
            _subjects = [];
          });
        }
      } else {
        debugPrint('⚠️ No subjects data found in SharedPreferences for Mock Tests');
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

  void _loadUnits(String subjectId, String subjectName) {
    try {
      debugPrint('=== LOADING UNITS/CHAPTERS FOR MOCK TEST SUBJECT ===');
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
          _selectedUnitName = ''; 
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
        _showError('No mock tests available for this subject');
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

  // Load chapters for selected unit from SharedPreferences
  void _loadChapters(String unitId, String unitName) {
    try {
      debugPrint('=== LOADING CHAPTERS FOR MOCK TEST UNIT ===');
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

  // Navigate to View Profile
void _navigateToViewProfile() async {
  // DON'T close the drawer here - let it stay open
  final result = await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => ViewProfileScreen(
        onProfileUpdated: (Map<String, String> updatedData) {
          // Refresh profile data when returning from view profile
          _loadProfileData();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Color(0xFFF4B400),
            ),
          );
        },
      ),
    ),
  );
}

  // Navigate to Settings
void _navigateToSettings() {
  // DON'T close the drawer here - let it stay open
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const SettingsScreen(),
    ),
  );
}

  // Navigate to Mock Test View or Descriptive Practice
  void _navigateToMockTest(String chapterId, String chapterName) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
      return;
    }

    if (_selectedPracticeType == 'mcq') {
      // Navigate to MCQ Practice
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MockTestViewScreen(
            chapterId: chapterId,
            chapterName: chapterName,
            accessToken: _accessToken!,
            practiceType: _selectedPracticeType,
          ),
        ),
      );

      // Handle result from MockTestViewScreen if needed
      if (result != null && result is Map<String, dynamic>) {
        if (result['showPremiumMessage'] == true) {
          _showPremiumLimitMessage(result['message'] ?? 'Free users can attempt only one practice. Upgrade to premium for unlimited attempts.');
        }
      }
    } else {
      // Navigate to Descriptive Practice
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DescriptivePracticeScreen(
            chapterId: chapterId,
            chapterName: chapterName,
            accessToken: _accessToken!,
          ),
        ),
      );
    }
  }

  void _showPremiumLimitMessage(String message) {
    setState(() {
      _showPremiumBanner = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warningOrange,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Upgrade',
          textColor: Colors.white,
          onPressed: () {
            _navigateToSubscription();
          },
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

  void _navigateToSubscription() {
    if (mounted) {
      Navigator.of(context).pushNamed('/subscription');
    }
  }

  // FIXED: Enhanced proper hierarchical backward navigation with bottom nav reset
  void _navigateBack() {
    debugPrint('=== MOCK TEST BACK NAVIGATION START ===');
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
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterName = '';
            break;
            
          case 'units':
            // Going back to units from chapters
            _units = previousState.unitsData;
            _chapters = [];
            _selectedUnitId = null;
            _selectedUnitName = '';
            _selectedChapterName = '';
            break;
            
          case 'chapters':
            // Going back to chapters from mock test selection
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
            _selectedChapterName = '';
            break;
        }
        _isLoading = false;
      });
      
      debugPrint('=== MOCK TEST BACK NAVIGATION COMPLETE ===');
      debugPrint('New current page: $_currentPage');
      debugPrint('Stack length after: ${_navigationStack.length}');
    } else {
      // If we're at the root (subjects), exit the screen and reset bottom nav to home
      debugPrint('At root level - exiting screen and resetting bottom nav to home');
      _exitScreenAndResetNav();
    }
  }

  // FIXED: Exit screen and properly reset bottom navigation to home
  void _exitScreenAndResetNav() {
    if (mounted) {
      // Navigate to home screen with proper route clearing to reset bottom nav
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (Route<dynamic> route) => false,
      );
    }
  }

  // Handle device back button press - FIXED to properly reset bottom nav
  Future<bool> _handleDeviceBackButton() async {
    debugPrint('=== MOCK TEST DEVICE BACK BUTTON PRESSED ===');
    debugPrint('Current page: $_currentPage');
    debugPrint('Stack length: ${_navigationStack.length}');
    
    if (_currentPage == 'subjects' && _navigationStack.length <= 1) {
      debugPrint('At root subjects - exiting screen and resetting bottom nav');
      _exitScreenAndResetNav();
      return false; 
    } else {
      _navigateBack();
      return false; 
    }
  }

  // Bottom Navigation Bar methods
  void _onTabTapped(int index) {
    if (index == 3) {
  
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }
    
    setState(() {
      _currentIndex = index;
    });

    BottomNavBarHelper.handleTabSelection(
      index,
      context,
      _studentType,
      _scaffoldKey,
    );
  }

  String _getAppBarTitle() {
  if (_navigationStack.isNotEmpty) {
    final currentState = _navigationStack.last;
    switch (currentState.pageType) {
      case 'subjects':
        return 'Practice Tests';
      case 'units':
        return 'Sections';
      case 'chapters':
        return 'Chapters';
      default:
        return 'Practice Tests';
    }
  }
  
  switch (_currentPage) {
    case 'subjects':
      return 'Practice Tests';
    case 'units':
      return 'Sections';
    case 'chapters':
      return 'Chapters';
    default:
      return 'Practice Tests';
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
        default:
          return '';
      }
    }
    return '';
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4B400),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Logging out...'),
              ],
            ),
          );
        },
      );

      await _authService.logout();
      
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout completed (Error: ${e.toString()})'),
            backgroundColor: Colors.red,
          ),
        );
        
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundLight,
     endDrawer: CommonProfileDrawer(
      name: _userName,
      email: _userEmail,
      course: _courseName,
      subcourse: _subcourseName,
      studentType: _studentType,
      profileCompleted: _profileCompleted,
      onViewProfile: () {
        _navigateToViewProfile();
      },
      onSettings: () {
        _navigateToSettings();
      },
      onClose: () {
        Navigator.of(context).pop();
      },
    ),
      body: PopScope(
        canPop: false,
        onPopInvoked: (bool didPop) async {
          if (didPop) {
            return;
          }
          
          await _handleDeviceBackButton();
        },
        child: Stack(
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

                // Practice Type Selector - Only show on chapters page
                if (_currentPage == 'chapters')
                  _buildPracticeTypeSelector(),

                // Premium Banner
                if (_showPremiumBanner)
                  _buildPremiumBanner(),

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
      bottomNavigationBar: CommonBottomNavBar(
        currentIndex: _currentIndex,
        onTabSelected: _onTabTapped,
        studentType: _studentType,
        scaffoldKey: _scaffoldKey,
      ),
    );
  }

  Widget _buildPracticeTypeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPracticeTypeButton(
              title: 'MCQ Practice',
              type: 'mcq',
              icon: Icons.quiz_rounded,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildPracticeTypeButton(
              title: 'Descriptive Practice',
              type: 'descriptive',
              icon: Icons.description_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeTypeButton({
    required String title,
    required String type,
    required IconData icon,
  }) {
    final isSelected = _selectedPracticeType == type;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPracticeType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppColors.textGrey,
              size: 18,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textGrey,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBanner() {
    return GestureDetector(
      onTap: _navigateToSubscription,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryYellow.withOpacity(0.9),
              AppColors.primaryYellowDark.withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryYellow.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upgrade to Premium',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.2,
                  ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Take subscription to unlock all premium features',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 18,
              ),
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

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case 'subjects':
        return _buildSubjectsPage();
      case 'units':
        return _buildUnitsPage();
      case 'chapters':
        return _buildChaptersPage();
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
                      'Choose a subject to take practice tests',
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
                          Icons.quiz_rounded,
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
                        'Mock tests for this unit will be added soon',
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
                    .map((chapter) => _buildChapterCard(
                          title: chapter['title']?.toString() ?? 'Unknown Chapter',
                          subtitle: _selectedPracticeType == 'mcq'
                              ? 'Take MCQ mock test for this chapter'
                              : 'Take descriptive practice for this chapter',
                          icon: _selectedPracticeType == 'mcq'
                              ? Icons.quiz_rounded
                              : Icons.description_rounded,
                          color: _selectedPracticeType == 'mcq'
                              ? AppColors.primaryBlue
                              : AppColors.primaryYellow,
                          onTap: () {
                            final chapterId = chapter['id']?.toString();
                            final chapterName = chapter['title']?.toString() ?? 'Unknown Chapter';
                            
                            if (chapterId != null && chapterId.isNotEmpty) {
                              _navigateToMockTest(chapterId, chapterName);
                            } else {
                              _showError('Invalid chapter ID');
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

  Widget _buildChapterCard({
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