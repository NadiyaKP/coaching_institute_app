import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import '../service/api_config.dart';
import '../common/theme_color.dart';

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

class ViewProfileScreen extends StatefulWidget {
  final Function(Map<String, String>)? onProfileUpdated;

  const ViewProfileScreen({
    super.key,
    this.onProfileUpdated,
  });

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  bool isEditing = false;
  bool isLoading = true;
  bool isLoadingData = false;
  bool isSubscriptionExpanded = false;
  String? errorMessage;
  String? dataLoadError;
  
  late TextEditingController nameController;
  late TextEditingController phoneController;
  late TextEditingController emailController;
  
  String selectedGender = '';
  String selectedBirthday = '';
  String studentType = '';
  Map<String, dynamic>? subscriptionData;
  
  // Course and Subcourse data
  List<CourseModel> availableCourses = [];
  List<SubcourseModel> availableSubcourses = [];
  String? selectedCourse;
  String? selectedSubCourse;
  String? selectedSubCourseId;
  String originalCourse = '';
  String originalSubCourse = '';
  String originalSubCourseId = '';

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadProfileData();
  }

  void _initializeControllers() {
    nameController = TextEditingController();
    phoneController = TextEditingController();
    emailController = TextEditingController();
  }

  bool _isValidToken(String token) {
    if (token.isEmpty) return false;
    if (token.split('.').length == 3) return true;
    if (token.length > 10) return true;
    return false;
  }

  Future<String?> _getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<String> possibleKeys = [
      'access_token',
      'accessToken', 
      'token',
      'auth_token',
      'bearer_token',
      'jwt_token'
    ];
    
    for (String key in possibleKeys) {
      String? token = prefs.getString(key);
      if (token != null && token.isNotEmpty && _isValidToken(token)) {
        print('Found valid token with key: $key');
        return token;
      } else if (token != null) {
        print('Found token with key $key but it seems invalid: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
      }
    }
    
    print('Available SharedPreferences keys: ${prefs.getKeys()}');
    return null;
  }

  Future<void> _fetchCoursesAndSubcourses() async {
    setState(() {
      isLoadingData = true;
      dataLoadError = null;
    });

    try {
      final accessToken = await _getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
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
      print('❌ Error fetching course data: $e');
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

    // After loading courses and subcourses, set the selectedSubCourseId
    _setInitialSubCourseId();
  }

  void _setInitialSubCourseId() {
    if (selectedSubCourse != null && selectedSubCourse!.isNotEmpty) {
      final subcourse = availableSubcourses.firstWhere(
        (s) => s.title == selectedSubCourse && s.course == selectedCourse,
        orElse: () => SubcourseModel(id: '', title: '', course: ''),
      );
      if (subcourse.id.isNotEmpty) {
        setState(() {
          selectedSubCourseId = subcourse.id;
          originalSubCourseId = subcourse.id;
        });
        print('✅ Initial subcourse ID set: $selectedSubCourseId for subcourse: $selectedSubCourse');
      }
    }
  }

  Future<void> _loadProfileData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final prefs = await SharedPreferences.getInstance();
      print('All SharedPreferences keys: ${prefs.getKeys()}');
      
      String? accessToken = await _getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        setState(() {
          errorMessage = 'No access token found. Please login again.';
          isLoading = false;
        });
        return;
      }

      final httpClient = ApiConfig.createHttpClient();
      final profileUrl = ApiConfig.buildUrl('/api/students/get_profile/');

      final request = await httpClient.getUrl(Uri.parse(profileUrl));
      
      // Use common headers from ApiConfig
      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';
      
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close().timeout(ApiConfig.requestTimeout);
      
      final responseBody = await response.transform(utf8.decoder).join();
      
      httpClient.close();

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        
        if (data['success'] == true && data['profile'] != null) {
          final profile = data['profile'];
          
          setState(() {
            nameController.text = profile['name'] ?? '';
            phoneController.text = profile['phone_number'] ?? '';
            emailController.text = profile['email'] ?? '';
            selectedGender = _formatGender(profile['gender']);
            selectedBirthday = _formatDate(profile['dob']);
            studentType = profile['student_type'] ?? '';
            subscriptionData = profile['subscription'];
            
            // Handle course and subcourse from enrollments
            if (profile['enrollments'] != null) {
              selectedCourse = profile['enrollments']['course'] ?? '';
              selectedSubCourse = profile['enrollments']['subcourse'] ?? '';
              originalCourse = selectedCourse ?? '';
              originalSubCourse = selectedSubCourse ?? '';
              
              // Try to get subcourse_id from enrollments if available
              if (profile['enrollments']['subcourse_id'] != null) {
                selectedSubCourseId = profile['enrollments']['subcourse_id'].toString();
                originalSubCourseId = selectedSubCourseId ?? '';
                print('📥 Loaded subcourse ID from API: $selectedSubCourseId');
              }
            }
            
            isLoading = false;
          });
          
          print('📋 Profile Data Loaded:');
          print('   - Course: $selectedCourse');
          print('   - Subcourse: $selectedSubCourse');
          print('   - Subcourse ID: $selectedSubCourseId');
          
          // Load courses and subcourses for editing
          await _fetchCoursesAndSubcourses();
        } else {
          setState(() {
            errorMessage = 'Failed to load profile data';
            isLoading = false;
          });
        }
      } else if (response.statusCode == 401) {
        setState(() {
          errorMessage = 'Session expired. Please login again.';
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load profile: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading profile: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _submitProfileToAPI() async {
    try {
      final accessToken = await _getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      // Validate required fields
      if (selectedGender.isEmpty) {
        throw Exception('Please select your gender');
      }
      if (selectedBirthday.isEmpty) {
        throw Exception('Please select your birth date');
      }
      if (selectedCourse == null || selectedCourse!.isEmpty) {
        throw Exception('Please select your course');
      }

      // Parse birthday from DD/MM/YYYY to YYYY-MM-DD
      final birthdayParts = selectedBirthday.split('/');
      if (birthdayParts.length != 3) {
        throw Exception('Invalid birthday format');
      }
      final formattedBirthday = '${birthdayParts[2]}-${birthdayParts[1].padLeft(2, '0')}-${birthdayParts[0].padLeft(2, '0')}';

      // Prepare profile data according to API requirements
      Map<String, dynamic> profileData = {
        'gender': selectedGender.toUpperCase(),
        'dob': formattedBirthday,
        'course_name': selectedCourse,
      };

      // Add subcourse_id only if available and selected
      if (selectedSubCourseId != null && selectedSubCourseId!.isNotEmpty) {
        profileData['subcourse_id'] = selectedSubCourseId;
        print('📤 Sending subcourse_id to API: $selectedSubCourseId');
      } else {
        print('ℹ️ No subcourse_id to send (optional field)');
      }

      print('📦 Final API Payload: $profileData');

      final httpClient = IOClient(ApiConfig.createHttpClient());
      final apiUrl = ApiConfig.buildUrl('/api/students/complete_profile/');

      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';

      final response = await httpClient.put(
        Uri.parse(apiUrl),
        headers: headers,
        body: jsonEncode(profileData),
      ).timeout(ApiConfig.requestTimeout);
      
      print('Profile API Response Status: ${response.statusCode}');
      print('Profile API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          print('✅ Profile updated successfully');
          
          // Update the original values after successful save
          setState(() {
            originalCourse = selectedCourse ?? '';
            originalSubCourse = selectedSubCourse ?? '';
            originalSubCourseId = selectedSubCourseId ?? '';
          });
          
          return;
        } else {
          throw Exception('Profile update failed: ${responseData['message'] ?? 'Unknown error'}');
        }
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        throw Exception('Invalid data: ${errorData['message'] ?? 'Bad request'}');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please login again.');
      } else {
        throw Exception('Failed to update profile: HTTP ${response.statusCode}');
      }

      httpClient.close();

    } catch (e) {
      print('❌ Error updating profile: $e');
      rethrow;
    }
  }

  String _formatGender(String? gender) {
    if (gender == null) return '';
    switch (gender.toUpperCase()) {
      case 'MALE':
        return 'Male';
      case 'FEMALE':
        return 'Female';
      default:
        return gender;
    }
  }


  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.backgroundLight,
    body: Stack(
      children: [
        // Custom App Bar with Gradient
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 200,
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
          ),
        ),
        
        // Main Content
        SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (!isLoading && errorMessage == null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: Icon(
                            isEditing ? Icons.save_rounded : Icons.edit_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () {
                            if (isEditing) {
                              _saveProfile();
                            } else {
                              setState(() {
                                isEditing = true;
                              });
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Scrollable Content
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildBody() {
  if (isLoading) {
    return _buildSkeletonLoading();
  }

  if (errorMessage != null) {
    return _buildErrorState();
  }

  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: Column(
      children: [
        // Profile Avatar Card - Changed to Square Shape
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16), // Square shape with rounded corners
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryYellow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Profile Avatar
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryYellow,
                      AppColors.primaryYellowDark,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryYellow.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.person_rounded,
                    size: 50,
                    color: AppColors.primaryYellow,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Name
              Text(
                nameController.text.isNotEmpty ? nameController.text : 'User Name',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              
              // Email
              if (emailController.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  emailController.text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              
              // Student Type Badge
              if (studentType.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryYellow.withOpacity(0.2),
                        AppColors.primaryYellow.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.school_rounded,
                        color: AppColors.primaryYellow,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        studentType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryYellow,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),
        
        // Personal Information Section
        _buildSectionHeader('Personal Information', Icons.person_outline_rounded),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildModernReadOnlyField(
                  'Full Name',
                  nameController.text,
                  Icons.person_outline_rounded,
                  isFirst: true,
                ),
                _buildDivider(),
                _buildModernReadOnlyField(
                  'Mobile Number',
                  phoneController.text,
                  Icons.phone_outlined,
                ),
                _buildDivider(),
                _buildModernReadOnlyField(
                  'Email Address',
                  emailController.text,
                  Icons.email_outlined,
                ),
                _buildDivider(),
                _buildModernGenderField(),
                _buildDivider(),
                _buildModernBirthdayField(),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        
        // Academic Information Section
        _buildSectionHeader('Academic Information', Icons.menu_book_rounded),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildModernCourseField(isFirst: true),
                _buildDivider(),
                _buildModernSubCourseField(),
              ],
            ),
          ),
        ),

        // Subscription Information (Only for Public students)
        if (studentType.toLowerCase() == 'public' && subscriptionData != null) ...[
          const SizedBox(height: 24),
          _buildSubscriptionSection(),
        ],

        // Action Buttons
        if (isEditing) ...[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEditing,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.grey300, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 32),
      ],
    ),
  );
}

Future<void> _selectDate() async {
  final DateTime? picked = await showDatePicker(
    context: context,
    initialDate: selectedBirthday.isNotEmpty 
        ? _parseDateString(selectedBirthday) 
        : DateTime.now(),
    firstDate: DateTime(1900),
    lastDate: DateTime.now(),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryYellow,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.textDark,
          ),
          dialogBackgroundColor: Colors.white,
        ),
        child: child!,
      );
    },
  );
  
  if (picked != null) {
    setState(() {
      selectedBirthday = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
    });
  }
}

DateTime _parseDateString(String dateStr) {
  try {
    final parts = dateStr.split('/');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    }
  } catch (e) {
    debugPrint('Error parsing date: $e');
  }
  return DateTime.now();
}

void _saveProfile() async {
  try {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
        ),
      ),
    );

    await _submitProfileToAPI();
    
    if (!mounted) return;
    Navigator.pop(context);
    
    setState(() {
      isEditing = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully!'),
        backgroundColor: AppColors.primaryYellow,
      ),
    );

    await _loadProfileData();

  } catch (e) {
    if (!mounted) return;
    Navigator.pop(context);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to update profile: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

void _cancelEditing() {
  setState(() {
    isEditing = false;
    selectedCourse = originalCourse;
    selectedSubCourse = originalSubCourse;
    selectedSubCourseId = originalSubCourseId;
  });
  print('↩️ Editing cancelled - restored original values');
  print('   - Course: $originalCourse');
  print('   - Subcourse: $originalSubCourse');
  print('   - Subcourse ID: $originalSubCourseId');
}

Widget _buildSectionHeader(String title, IconData icon) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: AppColors.primaryYellow,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
            letterSpacing: -0.2,
          ),
        ),
      ],
    ),
  );
}

Widget _buildDivider() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(
      height: 1,
      thickness: 1,
      color: AppColors.grey200,
    ),
  );
}

Widget _buildModernReadOnlyField(
  String label,
  String value,
  IconData icon, {
  bool isFirst = false,
}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 14, 16, 14),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryYellow, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.isNotEmpty ? value : 'Not specified',
                style: const TextStyle(
                  fontSize: 15,
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
  );
}

Widget _buildModernGenderField() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.wc_rounded, color: AppColors.primaryYellow, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gender',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              if (isEditing)
                DropdownButtonFormField<String>(
                  value: selectedGender.isNotEmpty ? selectedGender : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: AppColors.grey100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primaryYellow, width: 2),
                    ),
                    isDense: true,
                  ),
                  items: ['Male', 'Female'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    setState(() {
                      selectedGender = value ?? '';
                    });
                  },
                  hint: const Text('Select Gender', style: TextStyle(fontSize: 14)),
                )
              else
                Text(
                  selectedGender.isNotEmpty ? selectedGender : 'Not specified',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
            ],
          ),
        ),
        if (isEditing) const SizedBox(width: 8),
        if (isEditing)
          const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
      ],
    ),
  );
}

Widget _buildModernBirthdayField() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.cake_outlined, color: AppColors.primaryYellow, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date of Birth',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              if (isEditing)
                InkWell(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.grey100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            selectedBirthday.isNotEmpty ? selectedBirthday : 'Select Date',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: selectedBirthday.isNotEmpty 
                                  ? AppColors.textDark 
                                  : AppColors.grey400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.calendar_today_rounded, color: AppColors.primaryYellow, size: 16),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  selectedBirthday.isNotEmpty ? selectedBirthday : 'Not specified',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
            ],
          ),
        ),
        if (isEditing)
          const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
      ],
    ),
  );
}

Widget _buildModernCourseField({bool isFirst = false}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 14, 16, 14),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.menu_book_rounded, color: AppColors.primaryBlue, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Course',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              if (isEditing && availableCourses.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: selectedCourse,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: AppColors.grey100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primaryYellow, width: 2),
                    ),
                    isDense: true,
                  ),
                  items: availableCourses.map((CourseModel course) {
                    return DropdownMenuItem<String>(
                      value: course.title,
                      child: Text(
                        course.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    setState(() {
                      selectedCourse = value;
                      selectedSubCourse = null;
                      selectedSubCourseId = null;
                    });
                  },
                  hint: Text(
                    isLoadingData ? 'Loading courses...' : 'Select Course',
                    style: const TextStyle(fontSize: 14),
                  ),
                )
              else
                Text(
                  selectedCourse ?? 'Not specified',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
            ],
          ),
        ),
        if (isEditing) const SizedBox(width: 8),
        if (isEditing)
          const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
      ],
    ),
  );
}

Widget _buildModernSubCourseField() {
  final filteredSubcourses = availableSubcourses
      .where((subcourse) => subcourse.course == selectedCourse)
      .toList();

  String? validatedSubCourse = selectedSubCourse;
  if (selectedSubCourse != null && 
      !filteredSubcourses.any((subcourse) => subcourse.title == selectedSubCourse)) {
    validatedSubCourse = null;
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.book_outlined, color: AppColors.primaryBlue, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subcourse',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey400,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              if (isEditing && selectedCourse != null && filteredSubcourses.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: validatedSubCourse,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: AppColors.grey100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primaryYellow, width: 2),
                    ),
                    isDense: true,
                  ),
                  items: filteredSubcourses.map((SubcourseModel subcourse) {
                    return DropdownMenuItem<String>(
                      value: subcourse.title,
                      child: Text(
                        subcourse.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    setState(() {
                      selectedSubCourse = value;
                      if (value != null) {
                        final subcourse = filteredSubcourses.firstWhere(
                          (s) => s.title == value,
                          orElse: () => SubcourseModel(id: '', title: '', course: ''),
                        );
                        selectedSubCourseId = subcourse.id.isNotEmpty ? subcourse.id : null;
                      } else {
                        selectedSubCourseId = null;
                      }
                    });
                  },
                  hint: Text(
                    selectedCourse == null 
                        ? 'Select course first'
                        : 'Select Subcourse (Optional)',
                    style: const TextStyle(fontSize: 14),
                  ),
                )
              else
                Text(
                  selectedSubCourse ?? 'Not specified',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
            ],
          ),
        ),
        if (isEditing)
          const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
      ],
    ),
  );
}

Widget _buildSubscriptionSection() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.successGreen.withOpacity(0.1),
            AppColors.successGreen.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.successGreen.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                isSubscriptionExpanded = !isSubscriptionExpanded;
              });
            },
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.card_membership_rounded,
                      color: AppColors.successGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Subscription Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    isSubscriptionExpanded 
                        ? Icons.keyboard_arrow_up_rounded 
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.successGreen,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          
          if (isSubscriptionExpanded && subscriptionData != null) ...[
            const Divider(height: 1, color: AppColors.grey200),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSubscriptionInfoRow(
                    'Type',
                    subscriptionData!['type']?.toString().toUpperCase() ?? 'N/A',
                    Icons.label_outline_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildSubscriptionInfoRow(
                    'Start Date',
                    _formatDate(subscriptionData!['start_date']),
                    Icons.calendar_today_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildSubscriptionInfoRow(
                    'End Date',
                    _formatDate(subscriptionData!['end_date']),
                    Icons.event_rounded,
                  ),
                  const SizedBox(height: 12),
                  _buildSubscriptionInfoRow(
                    'Status',
                    subscriptionData!['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                    subscriptionData!['is_active'] == true 
                        ? Icons.check_circle_outline_rounded 
                        : Icons.cancel_outlined,
                    statusColor: subscriptionData!['is_active'] == true 
                        ? AppColors.successGreen 
                        : AppColors.errorRed,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildSubscriptionInfoRow(
  String label,
  String value,
  IconData icon, {
  Color? statusColor,
}) {
  return Row(
    children: [
      Icon(
        icon,
        color: statusColor ?? AppColors.successGreen,
        size: 18,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.grey400,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: statusColor ?? AppColors.textDark,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// Format date method for subscription dates
String _formatDate(dynamic date) {
  if (date == null) return 'N/A';
  try {
    if (date is String) {
      final parsedDate = DateTime.parse(date);
      return "${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}";
    } else if (date is DateTime) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    }
    return date.toString();
  } catch (e) {
    debugPrint('Error formatting date: $e');
    return 'N/A';
  }
}

Widget _buildErrorState() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.errorRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.errorRed,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Oops! Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? 'Unable to load profile data',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadProfileData,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text(
              'Try Again',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
    child: Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 94,
                height: 94,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 180,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: 100,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 160,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: List.generate(
                5,
                (index) => Column(
                  children: [
                    if (index > 0) _buildDivider(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        index == 0 ? 16 : 14,
                        16,
                        index == 4 ? 16 : 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.grey200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 80,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppColors.grey200,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: AppColors.grey200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),
        
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 180,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: List.generate(
                2,
                (index) => Column(
                  children: [
                    if (index > 0) _buildDivider(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        index == 0 ? 16 : 14,
                        16,
                        index == 1 ? 16 : 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.grey200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 60,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppColors.grey200,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: AppColors.grey200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 32),
      ],
    ),
  );
}
}