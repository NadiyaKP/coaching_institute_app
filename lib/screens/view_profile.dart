import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import '../service/api_config.dart';

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
            }
            
            isLoading = false;
          });
          
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
      
      print('Profile API Response Status: ${response.statusCode}');
      print('Profile API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          print('✅ Profile updated successfully');
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

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      return "${date.day}/${date.month}/${date.year}";
    } catch (e) {
      return dateString;
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
      appBar: AppBar(
        title: const Text(
          'Profile Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFFF4B400),
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        actions: [
          if (!isLoading && errorMessage == null)
            IconButton(
              icon: Icon(isEditing ? Icons.save : Icons.edit, color: Colors.white, size: 20),
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
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF4B400)),
            ),
            SizedBox(height: 16),
            Text('Loading profile...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProfileData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4B400),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Profile Avatar
          const CircleAvatar(
            radius: 50,
            backgroundColor: Color(0xFFF4B400),
            child: Icon(
              Icons.person,
              size: 60,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          
          // Profile Details Card
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildReadOnlyField(
                    'Full Name',
                    nameController.text,
                    Icons.person_outline,
                  ),
                  
                  _buildReadOnlyField(
                    'Mobile Number',
                    phoneController.text,
                    Icons.phone_outlined,
                  ),
                  
                  _buildReadOnlyField(
                    'Email',
                    emailController.text,
                    Icons.email_outlined,
                  ),
                  
                  _buildGenderField(),
                  
                  _buildBirthdayField(),
                  
                  _buildReadOnlyField(
                    'Student Type',
                    studentType,
                    Icons.school_outlined,
                  ),
                  
                  _buildCourseField(),
                  
                  _buildSubCourseField(),
                ],
              ),
            ),
          ),

          // Subscription Information Card
          if (subscriptionData != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Subscription Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildReadOnlyField(
                      'Subscription Type',
                      subscriptionData!['type']?.toString().toUpperCase() ?? '',
                      Icons.card_membership,
                    ),
                    
                    _buildReadOnlyField(
                      'Start Date',
                      _formatDate(subscriptionData!['start_date']),
                      Icons.calendar_today,
                    ),
                    
                    _buildReadOnlyField(
                      'End Date',
                      _formatDate(subscriptionData!['end_date']),
                      Icons.calendar_today_outlined,
                    ),
                    
                    _buildReadOnlyField(
                      'Status',
                      subscriptionData!['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                      Icons.info_outline,
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          if (isEditing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelEditing,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.grey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4B400),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: TextFormField(
              enabled: false,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: Icon(icon, color: Colors.grey[400], size: 18),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              controller: TextEditingController(text: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gender',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: DropdownButtonFormField<String>(
              value: selectedGender.isNotEmpty ? selectedGender : null,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFF4B400), size: 18),
                filled: true,
                fillColor: isEditing ? Colors.white : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFF4B400), width: 2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              items: isEditing
                  ? ['Male', 'Female'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList()
                  : null,
              onChanged: isEditing
                  ? (String? value) {
                      setState(() {
                        selectedGender = value ?? '';
                      });
                    }
                  : null,
              hint: Text(
                selectedGender.isNotEmpty ? selectedGender : 'Select Gender',
                style: TextStyle(
                  color: selectedGender.isNotEmpty ? Colors.black87 : Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayField() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Birthday',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: TextFormField(
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Icons.cake_outlined, color: Color(0xFFF4B400), size: 18),
                suffixIcon: isEditing 
                    ? const Icon(Icons.calendar_today, color: Color(0xFFF4B400), size: 18)
                    : null,
                filled: true,
                fillColor: isEditing ? Colors.white : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFF4B400), width: 2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              controller: TextEditingController(
                text: selectedBirthday.isNotEmpty ? selectedBirthday : 'Select Birthday',
              ),
              onTap: isEditing ? _selectDate : null,
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildCourseField() {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Course',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: DropdownButtonFormField<String>(
            value: selectedCourse,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              prefixIcon: const Icon(Icons.menu_book_outlined, color: Color(0xFFF4B400), size: 18),
              filled: true,
              fillColor: isEditing ? Colors.white : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFF4B400), width: 2),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            items: isEditing && availableCourses.isNotEmpty
                ? availableCourses.map((CourseModel course) {
                    return DropdownMenuItem<String>(
                      value: course.title,
                      child: Text(course.title, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList()
                : null,
            onChanged: isEditing
                ? (String? value) {
                    setState(() {
                      selectedCourse = value;
                      // Clear subcourse when course changes
                      selectedSubCourse = null;
                      selectedSubCourseId = null;
                    });
                  }
                : null,
            hint: isLoadingData
                ? const Text('Loading courses...')
                : Text(
                    selectedCourse ?? 'Select Course',
                    style: TextStyle(
                      color: selectedCourse != null ? Colors.black87 : Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}
Widget _buildSubCourseField() {
  final filteredSubcourses = availableSubcourses
      .where((subcourse) => subcourse.course == selectedCourse)
      .toList();

  // Check if the current selectedSubCourse is valid for the filtered subcourses
  String? validatedSubCourse = selectedSubCourse;
  if (selectedSubCourse != null && 
      !filteredSubcourses.any((subcourse) => subcourse.title == selectedSubCourse)) {
    validatedSubCourse = null;
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subcourse',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: DropdownButtonFormField<String>(
            value: validatedSubCourse,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              prefixIcon: const Icon(Icons.book_outlined, color: Color(0xFFF4B400), size: 18),
              filled: true,
              fillColor: isEditing ? Colors.white : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFF4B400), width: 2),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            items: isEditing && selectedCourse != null && filteredSubcourses.isNotEmpty
                ? filteredSubcourses.map((SubcourseModel subcourse) {
                    return DropdownMenuItem<String>(
                      value: subcourse.title,
                      child: Text(subcourse.title, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList()
                : null,
            onChanged: isEditing && selectedCourse != null
                ? (String? value) {
                    setState(() {
                      selectedSubCourse = value;
                      // Find and set the subcourse ID
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
                  }
                : null,
            hint: Text(
              selectedCourse == null 
                  ? 'Select course first'
                  : filteredSubcourses.isEmpty
                    ? 'No subcourses available'
                    : selectedSubCourse ?? 'Select Subcourse (Optional)',
              style: TextStyle(
                color: selectedSubCourse != null ? Colors.black87 : Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
  
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF4B400),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        selectedBirthday = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

void _saveProfile() async {
  try {
    // Show loading
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF4B400)),
        ),
      ),
    );

    await _submitProfileToAPI();
    
    // Check if widget is still mounted before any context operations
    if (!mounted) return;
    
    Navigator.pop(context); // Close loading dialog
    
    setState(() {
      isEditing = false;
    });

    // Check mounted again before showing snackbar
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully!'),
        backgroundColor: Color(0xFFF4B400),
      ),
    );

    // Reload profile data to get updated information
    await _loadProfileData();

  } catch (e) {
    // Check if widget is still mounted before any context operations
    if (!mounted) return;
    
    Navigator.pop(context); // Close loading dialog
    
    // Check mounted again before showing snackbar
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
    });
    _loadProfileData(); // Reload original data
  }
}