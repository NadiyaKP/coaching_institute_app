import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../service/api_config.dart';
import 'package:http/io_client.dart';
import '../common/theme_color.dart';
import '../common/continue_button.dart';

class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({super.key});

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage>
    with TickerProviderStateMixin {
  
  final PageController _pageController = PageController();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  int currentPageIndex = 0;
  
  // Form data
  DateTime? selectedBirthDate;
  String? selectedGender;
  String? selectedCourse;
  String? selectedSubCourse;
  String? selectedSubCourseId;
  
  final TextEditingController _birthDateController = TextEditingController();
  
  // API data
  List<CourseModel> availableCourses = [];
  List<SubcourseModel> availableSubcourses = [];
  bool isLoadingData = false;
  String? dataLoadError;
  bool isSubmitting = false;

  Map<String, dynamic> routeArguments = {};

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
    _fetchCoursesAndSubcourses();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      routeArguments = args;
      debugPrint('Profile Completion - Route arguments: $args');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  // Check if all fields are filled
  bool get _isAllFieldsFilled {
    return selectedBirthDate != null &&
           selectedGender != null &&
           selectedCourse != null &&
           selectedSubCourse != null &&
           selectedSubCourseId != null;
  }

  // Responsive helpers
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  bool _isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600;
  }

  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final isLandscape = _isLandscape(context);
    final isTablet = _isTablet(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    double fontSize = baseSize;
    
    if (isTablet) {
      fontSize = baseSize * 1.1;
    }
    
    if (isLandscape) {
      fontSize = fontSize * 0.85;
    }
    
    // Scale based on screen width
    final scaleFactor = (screenWidth / 375).clamp(0.8, 1.3);
    fontSize = fontSize * scaleFactor;
    
    return fontSize;
  }

  double _getResponsiveIconSize(BuildContext context, double baseSize) {
    final isLandscape = _isLandscape(context);
    final isTablet = _isTablet(context);
    
    double iconSize = baseSize;
    
    if (isTablet) {
      iconSize = baseSize * 1.15;
    }
    
    if (isLandscape) {
      iconSize = iconSize * 0.8;
    }
    
    return iconSize;
  }

  double _getResponsivePadding(BuildContext context, double basePadding) {
    final isLandscape = _isLandscape(context);
    final isTablet = _isTablet(context);
    
    double padding = basePadding;
    
    if (isTablet) {
      padding = basePadding * 1.3;
    }
    
    if (isLandscape) {
      padding = padding * 0.7;
    }
    
    return padding;
  }

  double _getFormWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = _isLandscape(context);
    final isTablet = _isTablet(context);
    
    if (isLandscape) {
      if (isTablet) {
        return screenWidth * 0.6;
      }
      return screenWidth * 0.7;
    }
    
    if (isTablet) {
      return screenWidth * 0.7;
    }
    
    return screenWidth * 0.85;
  }

  double _getContinueButtonWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = _isLandscape(context);
    final isTablet = _isTablet(context);
    
    if (isLandscape) {
      if (isTablet) {
        return screenWidth * 0.4;
      }
      return screenWidth * 0.5;
    }
    
    return double.infinity;
  }

  // Fetch courses and subcourses using ApiConfig
  Future<void> _fetchCoursesAndSubcourses() async {
    setState(() {
      isLoadingData = true;
      dataLoadError = null;
    });

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
          debugPrint('✅ Data loaded successfully: ${availableCourses.length} courses, ${availableSubcourses.length} subcourses');
        } else {
          throw Exception('Invalid response format: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to load data: HTTP ${response.statusCode}');
      }
      
      client.close();
    } catch (e) {
      setState(() {
        isLoadingData = false;
        dataLoadError = e.toString();
      });
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
    
    setState(() {
      availableCourses = coursesMap.values.toList();
      availableSubcourses = subcoursesList;
      isLoadingData = false;
    });
  }

  // Submit profile data to API using ApiConfig
  Future<void> _submitProfileToAPI() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken') ?? '';
      
      if (accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      if (selectedCourse == null) {
        throw Exception('Please select a course');
      }

      Map<String, dynamic> profileData = {
        'course_name': selectedCourse,
      };

      if (selectedGender != null) {
        profileData['gender'] = selectedGender!.toUpperCase();
      }
      
      if (selectedBirthDate != null) {
        profileData['dob'] = selectedBirthDate!.toIso8601String().split('T')[0];
      }

      if (selectedSubCourseId != null && selectedSubCourseId!.isNotEmpty) {
        profileData['subcourse_id'] = selectedSubCourseId;
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

      httpClient.close();

    } catch (e) {
      debugPrint('❌ Error submitting profile: $e');
      rethrow;
    }
  }

  Future<void> _saveProfileDataLocally(Map<String, dynamic> apiResponse) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      Map<String, dynamic> profileData = {
        'birth_date': selectedBirthDate?.toIso8601String(),
        'gender': selectedGender,
        'course': selectedCourse,
        'sub_course': selectedSubCourse,
        'sub_course_id': selectedSubCourseId,
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

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedBirthDate ?? DateTime(2000),
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
    
    if (picked != null && picked != selectedBirthDate) {
      setState(() {
        selectedBirthDate = picked;
        _birthDateController.text = 
            "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  void _nextPage() {
    if (currentPageIndex < 2) {
      setState(() {
        currentPageIndex++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeProfile();
    }
  }

  void _completeProfile() async {
    if (!_isAllFieldsFilled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      await _submitProfileToAPI();
      
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
        
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false,
          arguments: {
            ...routeArguments,
            'profile_completed': true,
            'profile_data': {
              'birth_date': selectedBirthDate?.toIso8601String(),
              'gender': selectedGender,
              'course': selectedCourse,
              'sub_course': selectedSubCourse,
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete profile: ${e.toString()}'),
            backgroundColor: AppColors.errorRed,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'Retry',
              textColor: AppColors.white,
              onPressed: _completeProfile,
            ),
          ),
        );
      }
      
      debugPrint('❌ Error completing profile: $e');
    }
  }

  Widget _buildDotIndicator() {
    final isLandscape = _isLandscape(context);
    final dotSize = isLandscape ? 6.0 : 8.0;
    final activeDotWidth = isLandscape ? 18.0 : 24.0;
    final spacing = isLandscape ? 3.0 : 4.0;
    
    return Container(
      margin: EdgeInsets.only(
        top: _getResponsivePadding(context, 20),
        bottom: _getResponsivePadding(context, 10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.symmetric(horizontal: spacing),
            width: currentPageIndex == index ? activeDotWidth : dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: currentPageIndex == index 
                  ? AppColors.primaryYellow 
                  : AppColors.grey300,
              borderRadius: BorderRadius.circular(dotSize / 2),
              boxShadow: currentPageIndex == index ? [
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
  }

  Widget _buildBirthDateForm() {
    final formWidth = _getFormWidth(context);
    final isLandscape = _isLandscape(context);
    
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: formWidth,
              padding: EdgeInsets.all(_getResponsivePadding(context, 28)),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(_getResponsivePadding(context, 20)),
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
                    width: _getResponsiveIconSize(context, 60),
                    height: _getResponsiveIconSize(context, 60),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(_getResponsivePadding(context, 15)),
                    ),
                    child: Icon(
                      Icons.cake_rounded,
                      size: _getResponsiveIconSize(context, 32),
                      color: AppColors.primaryYellow,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 20)),
                  
                  Text(
                    'When is your birthday?',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 20),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 8)),
                  
                  Text(
                    'Help us personalize your learning experience',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 14),
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 24)),
                  
                  GestureDetector(
                    onTap: _selectBirthDate,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(_getResponsivePadding(context, 18)),
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
                            size: _getResponsiveIconSize(context, 20),
                          ),
                          SizedBox(width: _getResponsivePadding(context, 12)),
                          Expanded(
                            child: Text(
                              selectedBirthDate != null
                                  ? "${selectedBirthDate!.day}/${selectedBirthDate!.month}/${selectedBirthDate!.year}"
                                  : 'Select your birth date',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 15),
                                color: selectedBirthDate != null 
                                    ? AppColors.textDark 
                                    : AppColors.grey500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: AppColors.primaryBlue,
                            size: _getResponsiveIconSize(context, 24),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Next button below card
            SizedBox(height: _getResponsivePadding(context, 24)),
            Container(
              width: formWidth,
              height: isLandscape ? 40.0 : 44.0,
              child: ElevatedButton(
                onPressed: _nextPage,
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
                    fontSize: _getResponsiveFontSize(context, 14),
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
  }

  Widget _buildGenderForm() {
    final formWidth = _getFormWidth(context);
    final isLandscape = _isLandscape(context);
    
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: formWidth,
              padding: EdgeInsets.all(_getResponsivePadding(context, 28)),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(_getResponsivePadding(context, 20)),
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
                    width: _getResponsiveIconSize(context, 60),
                    height: _getResponsiveIconSize(context, 60),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(_getResponsivePadding(context, 15)),
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: _getResponsiveIconSize(context, 32),
                      color: AppColors.primaryYellow,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 20)),
                  
                  Text(
                    'Select your gender',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 20),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 8)),
                  
                  Text(
                    'This helps us create a better experience for you',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 14),
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 24)),
                  
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: _getResponsivePadding(context, 18),
                      vertical: _getResponsivePadding(context, 4),
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.grey300, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.grey50,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedGender,
                        hint: Text(
                          'Select your gender',
                          style: TextStyle(
                            fontSize: _getResponsiveFontSize(context, 15),
                            color: AppColors.grey500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        isExpanded: true,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.primaryBlue,
                          size: _getResponsiveIconSize(context, 24),
                        ),
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 15),
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                        dropdownColor: AppColors.white,
                        items: ['Male', 'Female', 'Other'].map((String gender) {
                          return DropdownMenuItem<String>(
                            value: gender,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: _getResponsivePadding(context, 8),
                              ),
                              child: Text(gender),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedGender = newValue;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Next button below card
            SizedBox(height: _getResponsivePadding(context, 24)),
            Container(
              width: formWidth,
              height: isLandscape ? 40.0 : 44.0,
              child: ElevatedButton(
                onPressed: _nextPage,
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
                    fontSize: _getResponsiveFontSize(context, 14),
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
  }

  Widget _buildCourseForm() {
    final formWidth = _getFormWidth(context);
    final isLandscape = _isLandscape(context);
    final buttonWidth = _getContinueButtonWidth(context);
    
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: formWidth,
              padding: EdgeInsets.all(_getResponsivePadding(context, 28)),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(_getResponsivePadding(context, 20)),
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
                    width: _getResponsiveIconSize(context, 60),
                    height: _getResponsiveIconSize(context, 60),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(_getResponsivePadding(context, 15)),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      size: _getResponsiveIconSize(context, 32),
                      color: AppColors.primaryYellow,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 20)),
                  
                  Text(
                    'What course are you pursuing?',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 20),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 8)),
                  
                  Text(
                    'Select your main course and level',
                    style: TextStyle(
                      fontSize: _getResponsiveFontSize(context, 14),
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                  
                  SizedBox(height: _getResponsivePadding(context, 24)),
                  
                  // Course Dropdown - Scrollable
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: _getResponsivePadding(context, 18),
                      vertical: _getResponsivePadding(context, 4),
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.grey300, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.grey50,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: isLoadingData
                          ? Padding(
                              padding: EdgeInsets.all(_getResponsivePadding(context, 16)),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: _getResponsiveIconSize(context, 16),
                                    height: _getResponsiveIconSize(context, 16),
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primaryYellow,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: _getResponsivePadding(context, 12)),
                                  Text(
                                    'Loading courses...',
                                    style: TextStyle(
                                      fontSize: _getResponsiveFontSize(context, 15),
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : DropdownButton<String>(
                              value: selectedCourse,
                              hint: Text(
                                availableCourses.isEmpty && dataLoadError != null
                                    ? 'Error loading courses'
                                    : 'Select your course',
                                style: TextStyle(
                                  fontSize: _getResponsiveFontSize(context, 15),
                                  color: availableCourses.isEmpty && dataLoadError != null
                                      ? AppColors.errorRed
                                      : AppColors.grey500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              isExpanded: true,
                              icon: availableCourses.isEmpty && dataLoadError != null
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.refresh,
                                        color: AppColors.primaryBlue,
                                        size: _getResponsiveIconSize(context, 20),
                                      ),
                                      onPressed: _fetchCoursesAndSubcourses,
                                    )
                                  : Icon(
                                      Icons.arrow_drop_down,
                                      color: AppColors.primaryBlue,
                                      size: _getResponsiveIconSize(context, 24),
                                    ),
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 15),
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w500,
                              ),
                              dropdownColor: AppColors.white,
                              menuMaxHeight: isLandscape ? 200 : 300,
                              items: availableCourses.map((CourseModel course) {
                                return DropdownMenuItem<String>(
                                  value: course.title,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: _getResponsivePadding(context, 12),
                                    ),
                                    child: Text(
                                      course.title,
                                      style: TextStyle(
                                        fontSize: _getResponsiveFontSize(context, 15),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: availableCourses.isEmpty ? null : (String? newValue) {
                                setState(() {
                                  selectedCourse = newValue;
                                  selectedSubCourse = null;
                                  selectedSubCourseId = null;
                                });
                              },
                            ),
                    ),
                  ),
                  
                  if (dataLoadError != null && availableCourses.isEmpty) ...[
                    SizedBox(height: _getResponsivePadding(context, 16)),
                    Container(
                      padding: EdgeInsets.all(_getResponsivePadding(context, 12)),
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
                            size: _getResponsiveIconSize(context, 18),
                          ),
                          SizedBox(width: _getResponsivePadding(context, 10)),
                          Expanded(
                            child: Text(
                              dataLoadError!,
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 12),
                                color: AppColors.errorRed,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: _getResponsivePadding(context, 10)),
                          TextButton(
                            onPressed: _fetchCoursesAndSubcourses,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: _getResponsivePadding(context, 10),
                                vertical: _getResponsivePadding(context, 6),
                              ),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 12),
                                color: AppColors.primaryYellow,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  if (selectedCourse != null) ...[
                    SizedBox(height: _getResponsivePadding(context, 16)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: _getResponsivePadding(context, 18),
                        vertical: _getResponsivePadding(context, 4),
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.grey300, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.grey50,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedSubCourse,
                          hint: Text(
                            'Select your level',
                            style: TextStyle(
                              fontSize: _getResponsiveFontSize(context, 15),
                              color: AppColors.grey500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: AppColors.primaryBlue,
                            size: _getResponsiveIconSize(context, 24),
                          ),
                          style: TextStyle(
                            fontSize: _getResponsiveFontSize(context, 15),
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w500,
                          ),
                          dropdownColor: AppColors.white,
                          menuMaxHeight: isLandscape ? 200 : 300,
                          items: availableSubcourses
                              .where((subcourse) => subcourse.course == selectedCourse)
                              .map((SubcourseModel subcourse) {
                            return DropdownMenuItem<String>(
                              value: subcourse.title,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: _getResponsivePadding(context, 12),
                                ),
                                child: Text(
                                  subcourse.title,
                                  style: TextStyle(
                                    fontSize: _getResponsiveFontSize(context, 15),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  selectedSubCourseId = subcourse.id;
                                });
                              },
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              selectedSubCourse = newValue;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Continue button below card
            SizedBox(height: _getResponsivePadding(context, 24)),
            Container(
              width: buttonWidth,
              child: Opacity(
                opacity: _isAllFieldsFilled ? 1.0 : 0.5,
                child: Container(
                  height: isLandscape ? 40.0 : 44.0,
                  child: ElevatedButton(
                    onPressed: _isAllFieldsFilled && !isSubmitting ? _completeProfile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: _isAllFieldsFilled ? 3 : 0,
                      shadowColor: AppColors.shadowYellow,
                      disabledBackgroundColor: AppColors.primaryYellow,
                    ),
                    child: isSubmitting
                        ? SizedBox(
                            width: _getResponsiveIconSize(context, 20),
                            height: _getResponsiveIconSize(context, 20),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                            ),
                          )
                        : Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: _getResponsiveFontSize(context, 14),
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
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = _isLandscape(context);
    
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
            size: _getResponsiveIconSize(context, 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Complete Your Profile',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: _getResponsiveFontSize(context, 16),
          ),
        ),
      ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(screenHeight)
            : _buildPortraitLayout(screenHeight),
      ),
    );
  }

  Widget _buildPortraitLayout(double screenHeight) {
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
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      currentPageIndex = index;
                    });
                  },
                  children: [
                    _buildBirthDateForm(),
                    _buildGenderForm(),
                    _buildCourseForm(),
                  ],
                ),
              ),
              
              _buildDotIndicator(),
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

  Widget _buildLandscapeLayout(double screenHeight) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      currentPageIndex = index;
                    });
                  },
                  children: [
                    _buildBirthDateForm(),
                    _buildGenderForm(),
                    _buildCourseForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        _buildDotIndicator(),
      ],
    );
  }
}

// Model classes
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