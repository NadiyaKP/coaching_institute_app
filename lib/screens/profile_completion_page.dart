import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../service/api_config.dart';
import 'package:http/io_client.dart';
import '../common/theme_color.dart';

// ============= RESPONSIVE UTILITY CLASS =============
class ResponsiveUtils {
  static bool isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);
    
    double fontSize = baseSize;
    
    if (isTabletDevice) {
      fontSize = baseSize * 1.1;
    }
    
    if (isLandscapeMode) {
      fontSize = fontSize * 0.85;
    }
    
    final scaleFactor = (width / 375).clamp(0.8, 1.3);
    fontSize = fontSize * scaleFactor;
    
    return fontSize;
  }

  static double getResponsiveIconSize(BuildContext context, double baseSize) {
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    double iconSize = baseSize;
    
    if (isTabletDevice) {
      iconSize = baseSize * 1.15;
    }
    
    if (isLandscapeMode) {
      iconSize = iconSize * 0.8;
    }
    
    return iconSize;
  }

  static double getResponsivePadding(BuildContext context, double basePadding) {
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    double padding = basePadding;
    
    if (isTabletDevice) {
      padding = basePadding * 1.3;
    }
    
    if (isLandscapeMode) {
      padding = padding * 0.7;
    }
    
    return padding;
  }

  static double getFormWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    if (isLandscapeMode) {
      if (isTabletDevice) {
        return screenWidth * 0.6;
      }
      return screenWidth * 0.7;
    }
    
    if (isTabletDevice) {
      return screenWidth * 0.7;
    }
    
    return screenWidth * 0.85;
  }

  static double getContinueButtonWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    if (isLandscapeMode) {
      if (isTabletDevice) {
        return screenWidth * 0.3; 
      }
      return screenWidth * 0.4; 
    }
    
    return screenWidth * 0.6; 
  }

  static double getNextButtonWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscapeMode = isLandscape(context);
    final isTabletDevice = isTablet(context);
    
    if (isLandscapeMode) {
      if (isTabletDevice) {
        return screenWidth * 0.25; 
      }
      return screenWidth * 0.3; 
    }
    
    return screenWidth * 0.5; 
  }
}

// ==================== MODEL CLASSES ====================
class CourseModel {
  final String id;
  final String title;
  final bool isSubcourse;

  CourseModel({
    required this.id,
    required this.title,
    required this.isSubcourse,
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      isSubcourse: json['is_subcourse'] ?? false,
    );
  }
}

class SubcourseModel {
  final String id;
  final String title;
  final String course;

  SubcourseModel({
    required this.id,
    required this.title,
    required this.course,
  });

  factory SubcourseModel.fromJson(Map<String, dynamic> json) {
    return SubcourseModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      course: json['course'] ?? '',
    );
  }
}

// ==================== PROVIDER CLASS ====================
class ProfileCompletionProvider extends ChangeNotifier {
  final PageController pageController = PageController();
  
  // Form data
  DateTime? _selectedBirthDate;
  String? _selectedGender;
  String? _selectedCourse;
  String? _selectedSubCourse;
  String? _selectedSubCourseId;
  
  // API data
  List<CourseModel> _availableCourses = [];
  List<SubcourseModel> _availableSubcourses = [];
  bool _isLoadingData = false;
  String? _dataLoadError;
  bool _isSubmitting = false;

  int _currentPageIndex = 0;
  Map<String, dynamic> _routeArguments = {};

  // Getters
  DateTime? get selectedBirthDate => _selectedBirthDate;
  String? get selectedGender => _selectedGender;
  String? get selectedCourse => _selectedCourse;
  String? get selectedSubCourse => _selectedSubCourse;
  String? get selectedSubCourseId => _selectedSubCourseId;
  List<CourseModel> get availableCourses => _availableCourses;
  List<SubcourseModel> get availableSubcourses => _availableSubcourses;
  bool get isLoadingData => _isLoadingData;
  String? get dataLoadError => _dataLoadError;
  bool get isSubmitting => _isSubmitting;
  int get currentPageIndex => _currentPageIndex;
  Map<String, dynamic> get routeArguments => _routeArguments;

  // Check if all fields are filled
  bool get isAllFieldsFilled {
    return _selectedBirthDate != null &&
           _selectedGender != null &&
           _selectedCourse != null &&
           _selectedSubCourse != null &&
           _selectedSubCourseId != null;
  }

  // Initialize with route arguments
  void initialize(Map<String, dynamic>? args) {
    if (args != null) {
      _routeArguments = args;
      debugPrint('Profile Completion - Route arguments: $args');
    }
    _fetchCoursesAndSubcourses();
  }

  // Page navigation methods
  void nextPage() {
    if (_currentPageIndex < 2) {
      _currentPageIndex++;
      pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      notifyListeners();
    }
  }

  void setCurrentPageIndex(int index) {
    _currentPageIndex = index;
    notifyListeners();
  }

  // Form data setters
  void setBirthDate(DateTime? date) {
    _selectedBirthDate = date;
    notifyListeners();
  }

  void setGender(String? gender) {
    _selectedGender = gender;
    notifyListeners();
  }

  void setCourse(String? course) {
    _selectedCourse = course;
    _selectedSubCourse = null;
    _selectedSubCourseId = null;
    notifyListeners();
  }

  void setSubCourse(String? subCourse, String? subCourseId) {
    _selectedSubCourse = subCourse;
    _selectedSubCourseId = subCourseId;
    notifyListeners();
  }

  Future<void> _fetchCoursesAndSubcourses() async {
    _isLoadingData = true;
    _dataLoadError = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken') ?? '';
      
      if (accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final client = ApiConfig.createHttpClient();
      final apiUrl = ApiConfig.buildUrl('/api/course/list_subcourses/');
      
      final request = await client.getUrl(Uri.parse(apiUrl));
      
      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';
      
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      final response = await request.close().timeout(ApiConfig.requestTimeout);
      final String responseBody = await response.transform(utf8.decoder).join();
      
      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        
        if (data['success'] == true && data['subcourses'] != null) {
          final List<dynamic> subcoursesData = data['subcourses'];
          _processApiData(subcoursesData);
          debugPrint('✅ Data loaded successfully: ${_availableCourses.length} courses, ${_availableSubcourses.length} subcourses');
        } else {
          throw Exception('Invalid response format: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to load data: HTTP ${response.statusCode}');
      }
      
      client.close();
    } catch (e) {
      _isLoadingData = false;
      _dataLoadError = e.toString();
      notifyListeners();
      debugPrint('❌ Error fetching data: $e');
    }
  }

  void _processApiData(List<dynamic> subcoursesData) {
    final coursesMap = <String, CourseModel>{};
    final subcoursesList = <SubcourseModel>[];
    
    for (var item in subcoursesData) {
      final subcourse = SubcourseModel.fromJson(item);
      subcoursesList.add(subcourse);
      
      if (!coursesMap.containsKey(subcourse.course)) {
        coursesMap[subcourse.course] = CourseModel(
          id: subcourse.course,
          title: subcourse.course,
          isSubcourse: false,
        );
      }
    }
    
    _availableCourses = coursesMap.values.toList();
    _availableSubcourses = subcoursesList;
    _isLoadingData = false;
    notifyListeners();
  }

  // Submit profile data to API using ApiConfig
  Future<Map<String, dynamic>> submitProfile() async {
    _isSubmitting = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken') ?? '';
      
      if (accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      if (_selectedCourse == null) {
        throw Exception('Please select a course');
      }

      Map<String, dynamic> profileData = {
        'course_name': _selectedCourse,
      };

      if (_selectedGender != null) {
        profileData['gender'] = _selectedGender!.toUpperCase();
      }
      
      if (_selectedBirthDate != null) {
        profileData['dob'] = _selectedBirthDate!.toIso8601String().split('T')[0];
      }

      if (_selectedSubCourseId != null && _selectedSubCourseId!.isNotEmpty) {
        profileData['subcourse_id'] = _selectedSubCourseId;
      }

      final httpClient = IOClient(ApiConfig.createHttpClient());
      final apiUrl = ApiConfig.buildUrl('/api/students/complete_profile/');
      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';

      final response = await httpClient.put(
        Uri.parse(apiUrl),
        headers: headers,
        body: jsonEncode(profileData),
      ).timeout(ApiConfig.requestTimeout);
      
      debugPrint('Profile API Response Status: ${response.statusCode}');
      debugPrint('Profile API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          debugPrint('✅ Profile completed successfully');
          await _saveProfileDataLocally(responseData);
          return {
            'success': true,
            'message': 'Profile completed successfully',
            'data': responseData,
          };
        } else {
          throw Exception('Profile completion failed: ${responseData['message'] ?? 'Unknown error'}');
        }
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        throw Exception('Invalid data: ${errorData['message'] ?? 'Bad request'}');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please login again.');
      } else {
        throw Exception('Failed to complete profile: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error submitting profile: $e');
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> _saveProfileDataLocally(Map<String, dynamic> apiResponse) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      Map<String, dynamic> profileData = {
        'birth_date': _selectedBirthDate?.toIso8601String(),
        'gender': _selectedGender,
        'course': _selectedCourse,
        'sub_course': _selectedSubCourse,
        'sub_course_id': _selectedSubCourseId,
        'profile_completed': true,
        'completion_timestamp': DateTime.now().toIso8601String(),
        'api_response': apiResponse,
      };
      
      await prefs.setString('profileData', json.encode(profileData));
      await prefs.setBool('profileCompleted', true);
      
      debugPrint('✅ Profile data saved locally successfully');
      
    } catch (e) {
      debugPrint('❌ Error saving profile data locally: $e');
      throw Exception('Failed to save profile data locally');
    }
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}

// ==================== SCREEN WIDGET ====================
class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({super.key});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage>
    with TickerProviderStateMixin {
  
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showSnackBar(BuildContext context, String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _handleCompleteProfile(BuildContext context) async {
    final provider = Provider.of<ProfileCompletionProvider>(context, listen: false);
    
    if (!provider.isAllFieldsFilled) {
      _showSnackBar(context, 'Please complete all fields', AppColors.errorRed);
      return;
    }

    try {
      final result = await provider.submitProfile();
      
      if (mounted) {
        _showSnackBar(context, result['message'], AppColors.successGreen);
        
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false,
          arguments: {
            ...provider.routeArguments,
            'profile_completed': true,
            'profile_data': {
              'birth_date': provider.selectedBirthDate?.toIso8601String(),
              'gender': provider.selectedGender,
              'course': provider.selectedCourse,
              'sub_course': provider.selectedSubCourse,
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(context, 'Failed to complete profile: ${e.toString()}', AppColors.errorRed);
      }
      
      debugPrint('❌ Error completing profile: $e');
    }
  }

  Future<void> _selectBirthDate(BuildContext context) async {
    final provider = Provider.of<ProfileCompletionProvider>(context, listen: false);
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryYellow,
              onPrimary: AppColors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != provider.selectedBirthDate) {
      provider.setBirthDate(picked);
    }
  }

  Widget _buildDotIndicator(BuildContext context) {
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final dotSize = isLandscape ? 6.0 : 8.0;
    final activeDotWidth = isLandscape ? 18.0 : 24.0;
    final spacing = isLandscape ? 3.0 : 4.0;
    
    return Consumer<ProfileCompletionProvider>(
      builder: (context, provider, child) {
        return Container(
          margin: EdgeInsets.only(
            top: ResponsiveUtils.getResponsivePadding(context, 20),
            bottom: ResponsiveUtils.getResponsivePadding(context, 10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: EdgeInsets.symmetric(horizontal: spacing),
                width: provider.currentPageIndex == index ? activeDotWidth : dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: provider.currentPageIndex == index 
                      ? AppColors.primaryYellow 
                      : AppColors.grey300,
                  borderRadius: BorderRadius.circular(dotSize / 2),
                  boxShadow: provider.currentPageIndex == index ? [
                    BoxShadow(
                      color: AppColors.shadowYellow,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildBirthDateForm(BuildContext context) {
    final formWidth = ResponsiveUtils.getFormWidth(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final nextButtonWidth = ResponsiveUtils.getNextButtonWidth(context);
    
    return Consumer<ProfileCompletionProvider>(
      builder: (context, provider, child) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: formWidth,
                  padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 28)),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 20)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowGrey,
                        blurRadius: isLandscape ? 15 : 20,
                        offset: Offset(0, isLandscape ? 4 : 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFD54F).withOpacity(0.6),
                        blurRadius: isLandscape ? 20 : 30,
                        spreadRadius: isLandscape ? 1 : 2,
                        offset: Offset(0, isLandscape ? 2 : 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        height: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 15)),
                        ),
                        child: Icon(
                          Icons.cake_rounded,
                          size: ResponsiveUtils.getResponsiveIconSize(context, 32),
                          color: AppColors.primaryYellow,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 20)),
                      
                      Text(
                        'When is your birthday?',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 8)),
                      
                      Text(
                        'Help us personalize your learning experience',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                          color: AppColors.textGrey,
                          height: 1.4,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                      
                      GestureDetector(
                        onTap: () => _selectBirthDate(context),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 18)),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.grey300, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.grey50,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: AppColors.primaryBlue,
                                size: ResponsiveUtils.getResponsiveIconSize(context, 20),
                              ),
                              SizedBox(width: ResponsiveUtils.getResponsivePadding(context, 12)),
                              Expanded(
                                child: Text(
                                  provider.selectedBirthDate != null
                                      ? "${provider.selectedBirthDate!.day}/${provider.selectedBirthDate!.month}/${provider.selectedBirthDate!.year}"
                                      : 'Select your birth date',
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                    color: provider.selectedBirthDate != null 
                                        ? AppColors.textDark 
                                        : AppColors.grey500,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.primaryBlue,
                                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Next button below card - Reduced width
                SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                Container(
                  width: nextButtonWidth,
                  height: isLandscape ? 40.0 : 44.0,
                  child: ElevatedButton(
                    onPressed: provider.selectedBirthDate != null ? provider.nextPage : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      shadowColor: AppColors.shadowYellow,
                    ),
                    child: Text(
                      'Next',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenderForm(BuildContext context) {
    final formWidth = ResponsiveUtils.getFormWidth(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final nextButtonWidth = ResponsiveUtils.getNextButtonWidth(context);
    
    return Consumer<ProfileCompletionProvider>(
      builder: (context, provider, child) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: formWidth,
                  padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 28)),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 20)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowGrey,
                        blurRadius: isLandscape ? 15 : 20,
                        offset: Offset(0, isLandscape ? 4 : 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFD54F).withOpacity(0.6),
                        blurRadius: isLandscape ? 20 : 30,
                        spreadRadius: isLandscape ? 1 : 2,
                        offset: Offset(0, isLandscape ? 2 : 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        height: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 15)),
                        ),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: ResponsiveUtils.getResponsiveIconSize(context, 32),
                          color: AppColors.primaryYellow,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 20)),
                      
                      Text(
                        'Select your gender',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 8)),
                      
                      Text(
                        'This helps us create a better experience for you',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                          color: AppColors.textGrey,
                          height: 1.4,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                      
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveUtils.getResponsivePadding(context, 18),
                          vertical: ResponsiveUtils.getResponsivePadding(context, 4),
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.grey300, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.grey50,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: provider.selectedGender,
                            hint: Text(
                              'Select your gender',
                              style: TextStyle(
                                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                color: AppColors.grey500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            isExpanded: true,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: AppColors.primaryBlue,
                              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                            ),
                            style: TextStyle(
                              fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                            dropdownColor: AppColors.white,
                            items: ['Male', 'Female'].map((String gender) { 
                              return DropdownMenuItem<String>(
                                value: gender,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: ResponsiveUtils.getResponsivePadding(context, 8),
                                  ),
                                  child: Text(gender),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              provider.setGender(newValue);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                Container(
                  width: nextButtonWidth,
                  height: isLandscape ? 40.0 : 44.0,
                  child: ElevatedButton(
                    onPressed: provider.selectedGender != null ? provider.nextPage : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      shadowColor: AppColors.shadowYellow,
                    ),
                    child: Text(
                      'Next',
                      style: TextStyle(
                        fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCourseForm(BuildContext context) {
    final formWidth = ResponsiveUtils.getFormWidth(context);
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final continueButtonWidth = ResponsiveUtils.getContinueButtonWidth(context);
    
    return Consumer<ProfileCompletionProvider>(
      builder: (context, provider, child) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: formWidth,
                  padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 28)),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 20)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowGrey,
                        blurRadius: isLandscape ? 15 : 20,
                        offset: Offset(0, isLandscape ? 4 : 8),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFFD54F).withOpacity(0.6),
                        blurRadius: isLandscape ? 20 : 30,
                        spreadRadius: isLandscape ? 1 : 2,
                        offset: Offset(0, isLandscape ? 2 : 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        height: ResponsiveUtils.getResponsiveIconSize(context, 60),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD54F).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(ResponsiveUtils.getResponsivePadding(context, 15)),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: ResponsiveUtils.getResponsiveIconSize(context, 32),
                          color: AppColors.primaryYellow,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 20)),
                      
                      Text(
                        'What course are you pursuing?',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 20),
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          height: 1.3,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 8)),
                      
                      Text(
                        'Select your main course and level',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                          color: AppColors.textGrey,
                          height: 1.4,
                        ),
                      ),
                      
                      SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                      
                      // Course Dropdown - Scrollable
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveUtils.getResponsivePadding(context, 18),
                          vertical: ResponsiveUtils.getResponsivePadding(context, 4),
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.grey300, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.grey50,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: provider.isLoadingData
                              ? Padding(
                                  padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 16)),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: ResponsiveUtils.getResponsiveIconSize(context, 16),
                                        height: ResponsiveUtils.getResponsiveIconSize(context, 16),
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            AppColors.primaryYellow,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: ResponsiveUtils.getResponsivePadding(context, 12)),
                                      Text(
                                        'Loading courses...',
                                        style: TextStyle(
                                          fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                          color: AppColors.textGrey,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : DropdownButton<String>(
                                  value: provider.selectedCourse,
                                  hint: Text(
                                    provider.availableCourses.isEmpty && provider.dataLoadError != null
                                        ? 'Error loading courses'
                                        : 'Select your course',
                                    style: TextStyle(
                                      fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                      color: provider.availableCourses.isEmpty && provider.dataLoadError != null
                                          ? AppColors.errorRed
                                          : AppColors.grey500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  isExpanded: true,
                                  icon: provider.availableCourses.isEmpty && provider.dataLoadError != null
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.refresh,
                                            color: AppColors.primaryBlue,
                                            size: ResponsiveUtils.getResponsiveIconSize(context, 20),
                                          ),
                                          onPressed: () {
                                            final provider = Provider.of<ProfileCompletionProvider>(context, listen: false);
                                            provider._fetchCoursesAndSubcourses();
                                          },
                                        )
                                      : Icon(
                                          Icons.arrow_drop_down,
                                          color: AppColors.primaryBlue,
                                          size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                                        ),
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  dropdownColor: AppColors.white,
                                  menuMaxHeight: isLandscape ? 200 : 300,
                                  items: provider.availableCourses.map((CourseModel course) {
                                    return DropdownMenuItem<String>(
                                      value: course.title,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: ResponsiveUtils.getResponsivePadding(context, 12),
                                        ),
                                        child: Text(
                                          course.title,
                                          style: TextStyle(
                                            fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: provider.availableCourses.isEmpty ? null : (String? newValue) {
                                    provider.setCourse(newValue);
                                  },
                                ),
                        ),
                      ),
                      
                      if (provider.dataLoadError != null && provider.availableCourses.isEmpty) ...[
                        SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 16)),
                        Container(
                          padding: EdgeInsets.all(ResponsiveUtils.getResponsivePadding(context, 12)),
                          decoration: BoxDecoration(
                            color: AppColors.errorRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.errorRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: AppColors.errorRed,
                                size: ResponsiveUtils.getResponsiveIconSize(context, 18),
                              ),
                              SizedBox(width: ResponsiveUtils.getResponsivePadding(context, 10)),
                              Expanded(
                                child: Text(
                                  provider.dataLoadError!,
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                                    color: AppColors.errorRed,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(width: ResponsiveUtils.getResponsivePadding(context, 10)),
                              TextButton(
                                onPressed: () {
                                  final provider = Provider.of<ProfileCompletionProvider>(context, listen: false);
                                  provider._fetchCoursesAndSubcourses();
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveUtils.getResponsivePadding(context, 10),
                                    vertical: ResponsiveUtils.getResponsivePadding(context, 6),
                                  ),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Retry',
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils.getResponsiveFontSize(context, 12),
                                    color: AppColors.primaryYellow,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      if (provider.selectedCourse != null) ...[
                        SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 16)),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveUtils.getResponsivePadding(context, 18),
                            vertical: ResponsiveUtils.getResponsivePadding(context, 4),
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.grey300, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.grey50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: provider.selectedSubCourse,
                              hint: Text(
                                'Select your level',
                                style: TextStyle(
                                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                  color: AppColors.grey500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              isExpanded: true,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.primaryBlue,
                                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                              ),
                              style: TextStyle(
                                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                              dropdownColor: AppColors.white,
                              menuMaxHeight: isLandscape ? 200 : 300,
                              items: provider.availableSubcourses
                                  .where((subcourse) => subcourse.course == provider.selectedCourse)
                                  .map((SubcourseModel subcourse) {
                                return DropdownMenuItem<String>(
                                  value: subcourse.title,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: ResponsiveUtils.getResponsivePadding(context, 12),
                                    ),
                                    child: Text(
                                      subcourse.title,
                                      style: TextStyle(
                                        fontSize: ResponsiveUtils.getResponsiveFontSize(context, 15),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  onTap: () {
                                    provider.setSubCourse(subcourse.title, subcourse.id);
                                  },
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                provider.setSubCourse(newValue, provider.selectedSubCourseId);
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                SizedBox(height: ResponsiveUtils.getResponsivePadding(context, 24)),
                Container(
                  width: continueButtonWidth,
                  child: Opacity(
                    opacity: provider.isAllFieldsFilled ? 1.0 : 0.5,
                    child: Container(
                      height: isLandscape ? 40.0 : 44.0,
                      child: ElevatedButton(
                        onPressed: provider.isAllFieldsFilled && !provider.isSubmitting 
                            ? () => _handleCompleteProfile(context) 
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryYellow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: provider.isAllFieldsFilled ? 3 : 0,
                          shadowColor: AppColors.shadowYellow,
                          disabledBackgroundColor: AppColors.primaryYellow,
                        ),
                        child: provider.isSubmitting
                            ? SizedBox(
                                width: ResponsiveUtils.getResponsiveIconSize(context, 20),
                                height: ResponsiveUtils.getResponsiveIconSize(context, 20),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                                ),
                              )
                            : Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.white,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = ResponsiveUtils.isLandscape(context);
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    return ChangeNotifierProvider(
      create: (context) => ProfileCompletionProvider()..initialize(args),
      builder: (context, child) {
        final provider = Provider.of<ProfileCompletionProvider>(context);
        
        return Scaffold(
          backgroundColor: AppColors.backgroundGrey,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: AppColors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                color: AppColors.textDark,
                size: ResponsiveUtils.getResponsiveIconSize(context, 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            centerTitle: true,
            title: Text(
              'Complete Your Profile',
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
                fontSize: ResponsiveUtils.getResponsiveFontSize(context, 16),
              ),
            ),
          ),
          body: SafeArea(
            child: isLandscape
                ? _buildLandscapeLayout(context, screenHeight, provider)
                : _buildPortraitLayout(context, screenHeight, provider),
          ),
        );
      },
    );
  }

  Widget _buildPortraitLayout(BuildContext context, double screenHeight, ProfileCompletionProvider provider) {
    return Column(
      children: [
        const Expanded(
          flex: 1,
          child: SizedBox(),
        ),
        
        Expanded(
          flex: 8,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: PageView(
                  controller: provider.pageController,
                  onPageChanged: (index) {
                    provider.setCurrentPageIndex(index);
                  },
                  children: [
                    _buildBirthDateForm(context),
                    _buildGenderForm(context),
                    _buildCourseForm(context),
                  ],
                ),
              ),
              
              _buildDotIndicator(context),
            ],
          ),
        ),
        
        const Expanded(
          flex: 1,
          child: SizedBox(),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, double screenHeight, ProfileCompletionProvider provider) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: PageView(
                  controller: provider.pageController,
                  onPageChanged: (index) {
                    provider.setCurrentPageIndex(index);
                  },
                  children: [
                    _buildBirthDateForm(context),
                    _buildGenderForm(context),
                    _buildCourseForm(context),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        _buildDotIndicator(context),
      ],
    );
  }
}