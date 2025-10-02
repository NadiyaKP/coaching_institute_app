import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../service/api_config.dart';
import 'package:http/io_client.dart';
import '../common/theme_color.dart';

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

      // Use ApiConfig to create HttpClient and build URL
      final client = ApiConfig.createHttpClient();
      final apiUrl = ApiConfig.buildUrl('/api/course/list_subcourses/');
      
      final request = await client.getUrl(Uri.parse(apiUrl));
      
      // Use common headers from ApiConfig and add authorization
      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';
      
      // Set headers
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

      // Only validate course as required
      if (selectedCourse == null) {
        throw Exception('Please select a course');
      }

      // Prepare profile data according to API requirements
      Map<String, dynamic> profileData = {
        'course_name': selectedCourse,
      };

      // Add optional fields only if they are provided
      if (selectedGender != null) {
        profileData['gender'] = selectedGender!.toUpperCase();
      }
      
      if (selectedBirthDate != null) {
        profileData['dob'] = selectedBirthDate!.toIso8601String().split('T')[0];
      }

      // Add subcourse_id only if available and selected
      if (selectedSubCourseId != null && selectedSubCourseId!.isNotEmpty) {
        profileData['subcourse_id'] = selectedSubCourseId;
      }

      // Use ApiConfig to create HTTP client
      final httpClient = IOClient(ApiConfig.createHttpClient());

      // Build complete profile URL using ApiConfig
      final apiUrl = ApiConfig.buildUrl('/api/students/complete_profile/');

      // Prepare headers with authorization
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
          
          // Save profile data locally if success is true
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

      // Close the IOClient
      httpClient.close();

    } catch (e) {
      debugPrint('❌ Error submitting profile: $e');
      rethrow;
    }
  }

  // Save profile data to SharedPreferences
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

  // Date picker function
  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
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

  void _skipPage() {
    if (currentPageIndex < 2) {
      setState(() {
        currentPageIndex++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _completeProfile() async {
    // Only validate course as required
    if (selectedCourse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a course'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowGrey,
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                ),
                SizedBox(height: 16),
                Text(
                  'Completing Profile...',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await _submitProfileToAPI();
      
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
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
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
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
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: currentPageIndex == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: currentPageIndex == index 
                  ? AppColors.primaryYellow 
                  : AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
              boxShadow: currentPageIndex == index ? [
                BoxShadow(
                  color: AppColors.shadowYellow,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ] : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBirthDateForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cake_rounded,
            size: 40,
            color: AppColors.primaryYellow,
          ),
          
          SizedBox(height: 16),
          
          Text(
            'When is your birthday?',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          
          SizedBox(height: 8),
          
          Text(
            'Help us personalize your learning experience (Optional)',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.textGrey,
            ),
          ),
          
          SizedBox(height: 24),
          
          GestureDetector(
            onTap: _selectBirthDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey300),
                borderRadius: BorderRadius.circular(12),
                color: AppColors.grey50,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: AppColors.primaryBlue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selectedBirthDate != null
                          ? "${selectedBirthDate!.day}/${selectedBirthDate!.month}/${selectedBirthDate!.year}"
                          : 'Select your birth date',
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: selectedBirthDate != null 
                            ? AppColors.textDark 
                            : AppColors.grey500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 40,
            color: AppColors.primaryYellow,
          ),
          
          SizedBox(height: 16),
          
          Text(
            'What\'s your gender?',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          
          SizedBox(height: 8),
          
          Text(
            'This helps us create a better experience for you (Optional)',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.textGrey,
            ),
          ),
          
          SizedBox(height: 24),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.grey300),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.grey50,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedGender,
                hint: Text(
                  'Select your gender',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: AppColors.grey500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue),
                style: TextStyle(
                  fontSize: screenWidth * 0.038,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w500,
                ),
                dropdownColor: AppColors.white,
                items: ['Male', 'Female', 'Other'].map((String gender) {
                  return DropdownMenuItem<String>(
                    value: gender,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
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
    );
  }

  Widget _buildCourseForm() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.school_rounded,
            size: 40,
            color: AppColors.primaryYellow,
          ),
          
          SizedBox(height: 16),
          
          Text(
            'What course are you pursuing?',
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          
          SizedBox(height: 8),
          
          Text(
            'Select your main course and level',
            style: TextStyle(
              fontSize: screenWidth * 0.035,
              color: AppColors.textGrey,
            ),
          ),
          
          SizedBox(height: 24),
          
          // Course Dropdown
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.grey300),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.grey50,
            ),
            child: DropdownButtonHideUnderline(
              child: isLoadingData
                  ? Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primaryYellow,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Loading courses...',
                            style: TextStyle(
                              fontSize: screenWidth * 0.038,
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
                          fontSize: screenWidth * 0.038,
                          color: availableCourses.isEmpty && dataLoadError != null
                              ? AppColors.errorRed
                              : AppColors.grey500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      isExpanded: true,
                      icon: availableCourses.isEmpty && dataLoadError != null
                          ? IconButton(
                              icon: Icon(Icons.refresh, color: AppColors.primaryBlue, size: 20),
                              onPressed: _fetchCoursesAndSubcourses,
                            )
                          : Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue),
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                      dropdownColor: AppColors.white,
                      menuMaxHeight: 200,
                      items: availableCourses.map((CourseModel course) {
                        return DropdownMenuItem<String>(
                          value: course.title,
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(course.title),
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
            SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.errorRed.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.errorRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dataLoadError!,
                      style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: AppColors.errorRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _fetchCoursesAndSubcourses,
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: AppColors.primaryYellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: 16),
          
          if (selectedCourse != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.grey300),
                borderRadius: BorderRadius.circular(12),
                color: AppColors.grey50,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedSubCourse,
                  hint: Text(
                    'Select your level (Optional)',
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: AppColors.primaryBlue),
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w500,
                  ),
                  dropdownColor: AppColors.white,
                  menuMaxHeight: 200,
                  items: availableSubcourses
                      .where((subcourse) => subcourse.course == selectedCourse)
                      .map((SubcourseModel subcourse) {
                    return DropdownMenuItem<String>(
                      value: subcourse.title,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(subcourse.title),
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
    );
  }

  Widget _buildActionButtons() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08, vertical: 16),
      child: Row(
        children: [
          if (currentPageIndex < 2) ...[
            Expanded(
              child: Container(
                height: 48,
                margin: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: _skipPage,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primaryYellow),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: AppColors.white,
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryYellow,
                    ),
                  ),
                ),
              ),
            ),
          ],
          
          Expanded(
            flex: currentPageIndex < 2 ? 1 : 2,
            child: Container(
              height: 48,
              margin: EdgeInsets.only(left: currentPageIndex < 2 ? 8 : 0),
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  shadowColor: AppColors.shadowYellow,
                ),
                child: Text(
                  currentPageIndex == 2 ? 'Continue' : 'Next',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Complete Your Profile',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
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
                  
                  Expanded(
                    flex: 1,
                    child: _buildActionButtons(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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