import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import '../explore_student/explore_student_details.dart';
import '../../../service/http_interceptor.dart';

// ============= MODELS =============
class Batch {
  final String id;
  final String name;
  final String startDate;
  final String endDate;
  final String addedBy;

  Batch({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.addedBy,
  });

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
      addedBy: json['added_by'] ?? '',
    );
  }
}

class Course {
  final String id;
  final String title;
  final bool isSubcourse;

  Course({
    required this.id,
    required this.title,
    required this.isSubcourse,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      isSubcourse: json['is_subcourse'] ?? false,
    );
  }
}

class Student {
  final String id;  
  final String name;
  final String gender;
  final String studentType;
  final String registerNumber;
  final String course;
  final String? subcourse;
  final String batch;
  final String batchType;
  final String subscription;
  final String? previousInstitution;

  Student({
    required this.id,  
    required this.name,
    required this.gender,
    required this.studentType,
    required this.registerNumber,
    required this.course,
    this.subcourse,
    required this.batch,
    required this.batchType,
    required this.subscription,
    this.previousInstitution,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      gender: json['gender'] ?? '',
      studentType: json['student_type'] ?? '',
      registerNumber: json['register_number'] ?? '',
      course: json['course'] ?? '',
      subcourse: json['subcourse'],
      batch: json['batch'] ?? '',
      batchType: json['batch_type'] ?? '',
      subscription: json['subscription'] ?? '',
      previousInstitution: json['previous_institution'],
    );
  }
}

// ============= PROVIDER CLASS WITH GLOBAL HTTP CLIENT =============
class ExploreProvider extends ChangeNotifier {
  bool _isLoadingBatches = false;
  bool _isLoadingCourses = false;
  bool _isSearching = false;
  
  List<Batch> _batches = [];
  List<Course> _courses = [];
  List<Student> _students = [];
  
  String? _selectedCourseId;
  String? _selectedGender;
  String _searchQuery = '';
  
  String? _errorMessage;
  int _studentCount = 0;

  // Getters
  bool get isLoadingBatches => _isLoadingBatches;
  bool get isLoadingCourses => _isLoadingCourses;
  bool get isSearching => _isSearching;
  List<Batch> get batches => _batches;
  List<Course> get courses => _courses;
  List<Student> get students => _students;
  String? get selectedCourseId => _selectedCourseId;
  String? get selectedGender => _selectedGender;
  String get searchQuery => _searchQuery;
  String? get errorMessage => _errorMessage;
  int get studentCount => _studentCount;

  String? getSelectedCourseName() {
    if (_selectedCourseId == null) return null;
    final course = _courses.firstWhere(
      (c) => c.id == _selectedCourseId,
      orElse: () => Course(id: '', title: '', isSubcourse: false),
    );
    return course.title.isEmpty ? null : course.title;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedCourse(String? courseId) {
    _selectedCourseId = courseId;
    notifyListeners();
  }

  void setSelectedGender(String? gender) {
    _selectedGender = gender;
    notifyListeners();
  }

  void clearFilters() {
    _selectedCourseId = null;
    _selectedGender = null;
    _searchQuery = '';
    _students = [];
    _studentCount = 0;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> fetchBatches() async {
    _isLoadingBatches = true;
    _errorMessage = null;
    notifyListeners();

    HttpClient? httpClient;

    try {
      httpClient = ApiConfig.createHttpClient();
      
      final request = await httpClient.getUrl(
        Uri.parse('${ApiConfig.baseUrl}/api/students/get_batches'),
      );
      
      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      final httpResponse = await request.close().timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      final responseBody = await httpResponse.transform(utf8.decoder).join();
      
      debugPrint('=== FETCH BATCHES RESPONSE ===');
      debugPrint('Status: ${httpResponse.statusCode}');
      debugPrint('Body: $responseBody');

      if (httpResponse.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        
        if (responseData['success'] == true) {
          _batches = (responseData['batches'] as List)
              .map((batch) => Batch.fromJson(batch))
              .toList();
        } else {
          throw Exception('Failed to fetch batches');
        }
      } else {
        throw Exception('Server error: ${httpResponse.statusCode}');
      }
      
    } catch (e) {
      debugPrint('Error fetching batches: $e');
      _errorMessage = 'Failed to load batches: ${e.toString()}';
    } finally {
      httpClient?.close();
      _isLoadingBatches = false;
      notifyListeners();
    }
  }

  Future<void> fetchCourses() async {
    _isLoadingCourses = true;
    _errorMessage = null;
    notifyListeners();

    HttpClient? httpClient;

    try {
      httpClient = ApiConfig.createHttpClient();
      
      final request = await httpClient.getUrl(
        Uri.parse('${ApiConfig.baseUrl}/api/course/list_courses/'),
      );
      
      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      final httpResponse = await request.close().timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      final responseBody = await httpResponse.transform(utf8.decoder).join();
      
      debugPrint('=== FETCH COURSES RESPONSE ===');
      debugPrint('Status: ${httpResponse.statusCode}');
      debugPrint('Body: $responseBody');

      if (httpResponse.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        
        if (responseData['success'] == true) {
          _courses = (responseData['courses'] as List)
              .map((course) => Course.fromJson(course))
              .toList();
        } else {
          throw Exception('Failed to fetch courses');
        }
      } else {
        throw Exception('Server error: ${httpResponse.statusCode}');
      }
      
    } catch (e) {
      debugPrint('Error fetching courses: $e');
      _errorMessage = 'Failed to load courses: ${e.toString()}';
    } finally {
      httpClient?.close();
      _isLoadingCourses = false;
      notifyListeners();
    }
  }

  // ✅ UPDATED: Using globalHttpClient with http package
  Future<void> searchStudents() async {
    _isSearching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Build query parameters - REMOVED batch_id parameter
      Map<String, String> queryParams = {};
      
      if (_selectedCourseId != null && _selectedCourseId!.isNotEmpty) {
        queryParams['course_id'] = _selectedCourseId!;
      }
      
      if (_selectedGender != null && _selectedGender!.isNotEmpty) {
        queryParams['gender'] = _selectedGender!;
      }
      
      // REMOVED: Batch filter query parameter
      
      if (_searchQuery.isNotEmpty) {
        queryParams['search'] = _searchQuery;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/students/explore/')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      debugPrint('=== SEARCH STUDENTS REQUEST ===');
      debugPrint('URL: $uri');
      debugPrint('Query Params: $queryParams');

      // ✅ Use globalHttpClient instead of HttpClient
      final response = await globalHttpClient.get(
        uri,
        headers: ApiConfig.commonHeaders,
      ).timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );
      
      debugPrint('=== SEARCH STUDENTS RESPONSE ===');
      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        if (responseData['success'] == true) {
          _students = (responseData['students'] as List)
              .map((student) => Student.fromJson(student))
              .toList();
          _studentCount = responseData['count'] ?? 0;
        } else {
          throw Exception('Failed to search students');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('Error searching students: $e');
      _errorMessage = 'Failed to search students: ${e.toString()}';
      _students = [];
      _studentCount = 0;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }
}
// ============= SKELETAL LOADING WIDGETS =============
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                AppColors.grey200,
                AppColors.grey300,
                AppColors.grey200,
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
            ),
          ),
        );
      },
    );
  }
}

class FiltersSkeleton extends StatelessWidget {
  const FiltersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search bar skeleton
          SkeletonLoader(
            width: double.infinity,
            height: 50,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 12),
          // Filter chips skeleton - Updated to show only 2 filters
          Row(
            children: [
              SkeletonLoader(
                width: 100,
                height: 40,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(width: 8),
              SkeletonLoader(
                width: 90,
                height: 40,
                borderRadius: BorderRadius.circular(20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search button skeleton
          SkeletonLoader(
            width: double.infinity,
            height: 46,
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
    );
  }
}

class StudentCardSkeleton extends StatelessWidget {
  const StudentCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonLoader(
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      width: double.infinity,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    SkeletonLoader(
                      width: 120,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.grey200, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              SkeletonLoader(
                width: 18,
                height: 18,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 8),
              SkeletonLoader(
                width: 180,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SkeletonLoader(
                width: 18,
                height: 18,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 8),
              SkeletonLoader(
                width: 150,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StudentsListSkeleton extends StatelessWidget {
  const StudentsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: ResponsiveUtils.getHorizontalPadding(context),
      itemCount: 6,
      itemBuilder: (context, index) => const StudentCardSkeleton(),
    );
  }
}

// ============= RESPONSIVE UTILITY CLASS =============
class ResponsiveUtils {
  static bool isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  static double getFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    final isLandscapeMode = isLandscape(context);
    
    if (isLandscapeMode) {
      return baseSize * 0.85;
    } else if (isTabletDevice) {
      return baseSize * 1.2;
    }
    return (baseSize / 375) * width;
  }

  static EdgeInsets getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTabletDevice = isTablet(context);
    
    if (isTabletDevice) {
      return EdgeInsets.symmetric(horizontal: width * 0.1);
    }
    return const EdgeInsets.symmetric(horizontal: 20);
  }
}

// ============= SCREEN CLASS =============
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late ExploreProvider _provider;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _provider = ExploreProvider();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _provider.fetchBatches(),
      _provider.fetchCourses(),
    ]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _provider.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color color) {
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

  // REMOVED: _showBatchDropdown method

  void _showCourseDropdown() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildDropdownSheet(
        title: 'Select Course',
        items: _provider.courses.map((c) => c.title).toList(),
        selectedValue: _provider.getSelectedCourseName(),
        onSelected: (title) {
          final course = _provider.courses.firstWhere((c) => c.title == title);
          _provider.setSelectedCourse(course.id);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showGenderDropdown() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildDropdownSheet(
        title: 'Select Gender',
        items: ['Male', 'Female'],
        selectedValue: _provider.selectedGender,
        onSelected: (gender) {
          _provider.setSelectedGender(gender);
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildDropdownSheet({
    required String title,
    required List<String> items,
    required String? selectedValue,
    required Function(String) onSelected,
  }) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: ResponsiveUtils.getFontSize(context, 18),
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.primaryBlue),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.grey200),
          Flexible(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No items available',
                        style: TextStyle(
                          fontSize: ResponsiveUtils.getFontSize(context, 14),
                          color: AppColors.grey600,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = item == selectedValue;
                      
                      return InkWell(
                        onTap: () => onSelected(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primaryBlue.withOpacity(0.1)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.grey200,
                                width: index < items.length - 1 ? 1 : 0,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils.getFontSize(context, 15),
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? AppColors.primaryBlue
                                        : AppColors.grey800,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.primaryBlue,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: AppColors.grey800,
        ),
        decoration: InputDecoration(
          hintText: 'Search students...',
          hintStyle: TextStyle(
            color: AppColors.grey500,
            fontSize: fontSize,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.primaryBlue,
            size: ResponsiveUtils.getFontSize(context, 20),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) => _provider.setSearchQuery(value),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String? value,
    required VoidCallback onTap,
    required VoidCallback? onClear,
    required IconData icon,
  }) {
    final fontSize = ResponsiveUtils.getFontSize(context, 13);
    final hasValue = value != null && value.isNotEmpty;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: hasValue ? AppGradients.primaryYellow : null,
          color: hasValue ? null : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasValue ? Colors.transparent : AppColors.grey300,
            width: 1.5,
          ),
          boxShadow: hasValue
              ? [
                  BoxShadow(
                    color: AppColors.shadowYellow.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: hasValue ? AppColors.white : AppColors.primaryBlue,
              size: fontSize * 1.2,
            ),
            const SizedBox(width: 8),
            Text(
              hasValue ? value : label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: hasValue ? AppColors.white : AppColors.grey700,
              ),
            ),
            const SizedBox(width: 4),
            if (hasValue && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  color: AppColors.white,
                  size: fontSize * 1.3,
                ),
              )
            else
              Icon(
                Icons.arrow_drop_down,
                color: hasValue ? AppColors.white : AppColors.grey600,
                size: fontSize * 1.4,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    final fontSize = ResponsiveUtils.getFontSize(context, 15);
    
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        gradient: AppGradients.primaryYellow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowYellow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _provider.isSearching ? null : () async {
          await _provider.searchStudents();
          if (_provider.errorMessage != null) {
            _showSnackBar(_provider.errorMessage!, AppColors.errorRed);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _provider.isSearching
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'Search',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

 Widget _buildStudentCard(Student student) {
    final fontSize = ResponsiveUtils.getFontSize(context, 14);
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExploreStudentDetailsScreen(
              studentId: student.id,
              studentName: student.name,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowGrey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: AppColors.white,
                      size: ResponsiveUtils.getFontSize(context, 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: TextStyle(
                            fontSize: fontSize * 1.1,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          student.registerNumber,
                          style: TextStyle(
                            fontSize: fontSize * 0.85,
                            fontWeight: FontWeight.w500,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: fontSize,
                    color: AppColors.grey400,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.grey200, height: 1),
              const SizedBox(height: 12),
              _buildInfoRow(
                icon: Icons.school_outlined,
                label: 'Course',
                value: student.course,
                fontSize: fontSize,
              ),
              if (student.subcourse != null && student.subcourse!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  icon: Icons.subject_outlined,
                  label: 'Level',
                  value: student.subcourse!,
                  fontSize: fontSize,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required double fontSize,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: AppColors.primaryBlue,
          size: fontSize * 1.1,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: fontSize * 0.9,
            fontWeight: FontWeight.w600,
            color: AppColors.grey600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: fontSize * 0.9,
              fontWeight: FontWeight.w500,
              color: AppColors.grey800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSection() {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, child) {
        // Show skeleton while searching
        if (_provider.isSearching) {
          return const StudentsListSkeleton();
        }
        
        if (_provider.students.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.search_off,
                  size: 64,
                  color: AppColors.grey400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No students found',
                  style: TextStyle(
                    fontSize: ResponsiveUtils.getFontSize(context, 16),
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try adjusting your search or filters',
                  style: TextStyle(
                    fontSize: ResponsiveUtils.getFontSize(context, 14),
                    color: AppColors.grey500,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                'Found ${_provider.studentCount} student${_provider.studentCount != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: ResponsiveUtils.getFontSize(context, 16),
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: ResponsiveUtils.getHorizontalPadding(context),
                itemCount: _provider.students.length,
                itemBuilder: (context, index) {
                  return _buildStudentCard(_provider.students[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.background,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primaryBlue),
        ),
        title: Text(
          'Explore Students',
          style: TextStyle(
            fontSize: ResponsiveUtils.getFontSize(context, 18),
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _provider,
            builder: (context, child) {
              // Updated: Only check for course, gender, and search query
              final hasFilters = _provider.selectedCourseId != null ||
                  _provider.selectedGender != null ||
                  _provider.searchQuery.isNotEmpty;
              
              if (hasFilters) {
                return IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _provider.clearFilters();
                  },
                  icon: const Icon(Icons.clear_all, color: AppColors.primaryBlue),
                  tooltip: 'Clear all filters',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, child) {
          // Show skeleton loading on initial page load
          if (_provider.isLoadingBatches || _provider.isLoadingCourses) {
            return const Column(
              children: [
                 FiltersSkeleton(),
                Expanded(
                  child: StudentsListSkeleton(),
                ),
              ],
            );
          }

          return Column(
            children: [
              // Search and Filters Section
              Container(
                width: screenWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowGrey.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: screenWidth,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: 'Course',
                              value: _provider.getSelectedCourseName(),
                              onTap: _showCourseDropdown,
                              onClear: () => _provider.setSelectedCourse(null),
                              icon: Icons.school_outlined,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: 'Gender',
                              value: _provider.selectedGender,
                              onTap: _showGenderDropdown,
                              onClear: () => _provider.setSelectedGender(null),
                              icon: Icons.person_outline,
                            ),
                            // REMOVED: Batch filter chip
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSearchButton(),
                  ],
                ),
              ),
              
              // Results Section
              Expanded(
                child: _buildResultsSection(),
              ),
            ],
          );
        },
      ),
    );
  }
}