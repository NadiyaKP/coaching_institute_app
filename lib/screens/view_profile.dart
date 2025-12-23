import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

// Profile Provider
class ProfileProvider with ChangeNotifier {
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isLoadingData = false;
  bool _isSubscriptionExpanded = false;
  String? _errorMessage;
  String? _dataLoadError;
  
  TextEditingController nameController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  
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

  // Public visibility
  bool showPublic = false;

  bool get isEditing => _isEditing;
  bool get isLoading => _isLoading;
  bool get isLoadingData => _isLoadingData;
  bool get isSubscriptionExpanded => _isSubscriptionExpanded;
  String? get errorMessage => _errorMessage;
  String? get dataLoadError => _dataLoadError;

  set isEditing(bool value) {
    _isEditing = value;
    notifyListeners();
  }

  set isLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  set isLoadingData(bool value) {
    _isLoadingData = value;
    notifyListeners();
  }

  set isSubscriptionExpanded(bool value) {
    _isSubscriptionExpanded = value;
    notifyListeners();
  }

  set errorMessage(String? value) {
    _errorMessage = value;
    notifyListeners();
  }

  set dataLoadError(String? value) {
    _dataLoadError = value;
    notifyListeners();
  }

  // Check if user can edit profile
  bool get canEditProfile => studentType.toLowerCase() == 'public';

  void disposeControllers() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }

  // Toggle public visibility
  Future<void> togglePublicVisibility(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? accessToken = await _getAccessToken(prefs);
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      final httpClient = IOClient(ApiConfig.createHttpClient());
      final apiUrl = ApiConfig.buildUrl('/api/students/toggle_visibility/');

      final headers = Map<String, String>.from(ApiConfig.commonHeaders);
      headers['Authorization'] = 'Bearer $accessToken';

      final response = await httpClient.patch(
        Uri.parse(apiUrl),
        headers: headers,
        body: jsonEncode({'show_public': value}),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          showPublic = responseData['show_public'] ?? value;
          notifyListeners();
          print('✅ Public visibility updated to: $showPublic');
        } else {
          throw Exception(responseData['message'] ?? 'Failed to update visibility');
        }
      } else {
        throw Exception('Failed to update visibility: HTTP ${response.statusCode}');
      }

      httpClient.close();
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> _getAccessToken(SharedPreferences prefs) async {
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
        return token;
      }
    }
    return null;
  }

  bool _isValidToken(String token) {
    if (token.isEmpty) return false;
    if (token.split('.').length == 3) return true;
    if (token.length > 10) return true;
    return false;
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
  late ProfileProvider _profileProvider;

  @override
  void initState() {
    super.initState();
    _profileProvider = ProfileProvider();
    
    // Load profile data when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfileData(_profileProvider);
    });
  }

  @override
  void dispose() {
    _profileProvider.disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _profileProvider,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Stack(
          children: [
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
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(), 
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildBody(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
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
              if (!profileProvider.isLoading && profileProvider.errorMessage == null && profileProvider.canEditProfile)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(
                      profileProvider.isEditing ? Icons.save_rounded : Icons.edit_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () {
                      if (profileProvider.isEditing) {
                        _saveProfile(context);
                      } else {
                        profileProvider.isEditing = true;
                      }
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        if (profileProvider.isLoading) {
          return _buildSkeletonLoading();
        }

        if (profileProvider.errorMessage != null) {
          return _buildErrorState(profileProvider);
        }

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildProfileCard(profileProvider),
              
              const SizedBox(height: 24),
              
              // Personal Information Section
              _buildSectionHeader('Personal Information', Icons.person_outline_rounded),
              _buildPersonalInfoSection(profileProvider),

              const SizedBox(height: 24),
              
              // Academic Information Section
              _buildSectionHeader('Academic Information', Icons.menu_book_rounded),
              _buildAcademicInfoSection(profileProvider),

              // Public Visibility Section (For all student types)
              const SizedBox(height: 24),
              _buildPublicVisibilitySection(profileProvider),

              // Subscription Information (Only for Public students)
              if (profileProvider.studentType.toLowerCase() == 'public' && profileProvider.subscriptionData != null) ...[
                const SizedBox(height: 24),
                _buildSubscriptionSection(profileProvider),
              ],

              // Action Buttons
              if (profileProvider.isEditing) ...[
                const SizedBox(height: 32),
                _buildActionButtons(context, profileProvider),
              ],
              
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(ProfileProvider profileProvider) {
  const cardSize = 240.0; 
  
  return Container(
    width: cardSize,
    height: cardSize, 
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryYellow.withOpacity(0.15),
          blurRadius: 25,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center, 
      children: [
        // Profile Avatar
        Container(
          padding: const EdgeInsets.all(3),
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
            radius: 30, 
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person_rounded,
              size: 35, 
              color: AppColors.primaryYellow,
            ),
          ),
        ),
        
        const SizedBox(height: 10),
        
        // Name
        Text(
          profileProvider.nameController.text.isNotEmpty 
              ? profileProvider.nameController.text 
              : 'User Name',
          style: const TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
            letterSpacing: -0.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        
        // Email
        if (profileProvider.emailController.text.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            profileProvider.emailController.text,
            style: const TextStyle(
              fontSize: 11, 
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        
        // Student Type Badge
        if (profileProvider.studentType.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryYellow.withOpacity(0.2),
                  AppColors.primaryYellow.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
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
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  profileProvider.studentType.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
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
  );
}
  Widget _buildPublicVisibilitySection(ProfileProvider profileProvider) {
    return Padding(
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
            _buildSectionHeaderWithToggle(
              'Show profile to public',
              Icons.public_rounded,
              profileProvider.showPublic,
              onToggle: (value) {
                _showPublicVisibilityDialog(context, profileProvider, value);
              },
              isFirst: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeaderWithToggle(
    String title,
    IconData icon,
    bool value, {
    required Function(bool) onToggle,
    bool isFirst = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 14, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
          Switch(
            value: value,
            onChanged: onToggle,
            activeColor: AppColors.primaryYellow,
            activeTrackColor: AppColors.primaryYellow.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

 void _showPublicVisibilityDialog(BuildContext context, ProfileProvider profileProvider, bool newValue) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: const EdgeInsets.all(0),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      content: SizedBox(
        width: MediaQuery.of(context).size.width - 48,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Manage your profile visibility',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textGrey),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 24,
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Description
              const Text(
                "Allow recruiters and others to view your profile when they search. Enabling this helps you get discovered for opportunities.",
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  height: 1.4,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        // Call API with false to turn off visibility
                        await _togglePublicVisibility(profileProvider, false);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Don't Allow",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        // Call API with true to turn on visibility
                        await _togglePublicVisibility(profileProvider, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryYellow,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Allow',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Future<void> _togglePublicVisibility(ProfileProvider profileProvider, bool value) async {
    try {
      await profileProvider.togglePublicVisibility(value);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value ? 'Profile is now visible to public' : 'Profile is now private',
            ),
            backgroundColor: AppColors.primaryYellow,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update visibility: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPersonalInfoSection(ProfileProvider profileProvider) {
    return Padding(
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
              profileProvider.nameController.text,
              Icons.person_outline_rounded,
              isFirst: true,
            ),
            _buildDivider(),
            _buildModernReadOnlyField(
              'Mobile Number',
              profileProvider.phoneController.text,
              Icons.phone_outlined,
            ),
            _buildDivider(),
            _buildModernReadOnlyField(
              'Email Address',
              profileProvider.emailController.text,
              Icons.email_outlined,
            ),
            _buildDivider(),
            _buildModernGenderField(profileProvider),
            _buildDivider(),
            _buildModernBirthdayField(profileProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicInfoSection(ProfileProvider profileProvider) {
    return Padding(
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
            _buildModernCourseField(profileProvider, isFirst: true),
            _buildDivider(),
            _buildModernSubCourseField(profileProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ProfileProvider profileProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _cancelEditing(profileProvider),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.grey300, width: 1.5),
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
              onPressed: () => _saveProfile(context),
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
    );
  }

  // Helper methods
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
    return const Padding(
      padding:  EdgeInsets.symmetric(horizontal: 16),
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
                  style: const TextStyle(
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

  Widget _buildModernGenderField(ProfileProvider profileProvider) {
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
                const Text(
                  'Gender',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey400,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                if (profileProvider.isEditing)
                  DropdownButtonFormField<String>(
                    value: profileProvider.selectedGender.isNotEmpty ? profileProvider.selectedGender : null,
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
                      profileProvider.selectedGender = value ?? '';
                    },
                    hint: const Text('Select Gender', style: TextStyle(fontSize: 14)),
                  )
                else
                  Text(
                    profileProvider.selectedGender.isNotEmpty ? profileProvider.selectedGender : 'Not specified',
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
          if (profileProvider.isEditing) const SizedBox(width: 8),
          if (profileProvider.isEditing)
            const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
        ],
      ),
    );
  }

  Widget _buildModernBirthdayField(ProfileProvider profileProvider) {
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
                const Text(
                  'Date of Birth',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey400,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                if (profileProvider.isEditing)
                  InkWell(
                    onTap: () => _selectDate(profileProvider),
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
                              profileProvider.selectedBirthday.isNotEmpty ? profileProvider.selectedBirthday : 'Select Date',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: profileProvider.selectedBirthday.isNotEmpty 
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
                    profileProvider.selectedBirthday.isNotEmpty ? profileProvider.selectedBirthday : 'Not specified',
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
          if (profileProvider.isEditing)
            const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
        ],
      ),
    );
  }

  Widget _buildModernCourseField(ProfileProvider profileProvider, {bool isFirst = false}) {
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
                const Text(
                  'Course',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey400,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                if (profileProvider.isEditing && profileProvider.availableCourses.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: profileProvider.selectedCourse,
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
                    items: profileProvider.availableCourses.map((CourseModel course) {
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
                      profileProvider.selectedCourse = value;
                      profileProvider.selectedSubCourse = null;
                      profileProvider.selectedSubCourseId = null;
                    },
                    hint: Text(
                      profileProvider.isLoadingData ? 'Loading courses...' : 'Select Course',
                      style: const TextStyle(fontSize: 14),
                    ),
                  )
                else
                  Text(
                    profileProvider.selectedCourse ?? 'Not specified',
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
          if (profileProvider.isEditing) const SizedBox(width: 8),
          if (profileProvider.isEditing)
            const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
        ],
      ),
    );
  }

  Widget _buildModernSubCourseField(ProfileProvider profileProvider) {
    final filteredSubcourses = profileProvider.availableSubcourses
        .where((subcourse) => subcourse.course == profileProvider.selectedCourse)
        .toList();

    String? validatedSubCourse = profileProvider.selectedSubCourse;
    if (profileProvider.selectedSubCourse != null && 
        !filteredSubcourses.any((subcourse) => subcourse.title == profileProvider.selectedSubCourse)) {
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
                const Text(
                  'Level',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey400,
                    letterSpacing: 0.3,
                ),
                ),
                const SizedBox(height: 6),
                if (profileProvider.isEditing && profileProvider.selectedCourse != null && filteredSubcourses.isNotEmpty)
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
                      profileProvider.selectedSubCourse = value;
                      if (value != null) {
                        final subcourse = filteredSubcourses.firstWhere(
                          (s) => s.title == value,
                          orElse: () => SubcourseModel(id: '', title: '', course: ''),
                        );
                        profileProvider.selectedSubCourseId = subcourse.id.isNotEmpty ? subcourse.id : null;
                      } else {
                        profileProvider.selectedSubCourseId = null;
                      }
                    },
                    hint: Text(
                      profileProvider.selectedCourse == null 
                          ? 'Select course first'
                          : 'Select Level (Optional)',
                      style: const TextStyle(fontSize: 14),
                    ),
                  )
                else
                  Text(
                    profileProvider.selectedSubCourse ?? 'Not specified',
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
          if (profileProvider.isEditing)
            const Icon(Icons.edit_outlined, color: AppColors.primaryYellow, size: 18),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSection(ProfileProvider profileProvider) {
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
                profileProvider.isSubscriptionExpanded = !profileProvider.isSubscriptionExpanded;
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
                      profileProvider.isSubscriptionExpanded 
                          ? Icons.keyboard_arrow_up_rounded 
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.successGreen,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
            
            if (profileProvider.isSubscriptionExpanded && profileProvider.subscriptionData != null) ...[
              const Divider(height: 1, color: AppColors.grey200),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSubscriptionInfoRow(
                      'Type',
                      profileProvider.subscriptionData!['type']?.toString().toUpperCase() ?? 'N/A',
                      Icons.label_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSubscriptionInfoRow(
                      'Start Date',
                      _formatDate(profileProvider.subscriptionData!['start_date']),
                      Icons.calendar_today_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSubscriptionInfoRow(
                      'End Date',
                      _formatDate(profileProvider.subscriptionData!['end_date']),
                      Icons.event_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSubscriptionInfoRow(
                      'Status',
                      profileProvider.subscriptionData!['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                      profileProvider.subscriptionData!['is_active'] == true 
                          ? Icons.check_circle_outline_rounded 
                          : Icons.cancel_outlined,
                      statusColor: profileProvider.subscriptionData!['is_active'] == true 
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
                style: const TextStyle(
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

  Widget _buildErrorState(ProfileProvider profileProvider) {
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
              profileProvider.errorMessage ?? 'Unable to load profile data',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadProfileData(profileProvider),
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
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(24), 
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20), 
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
                  width: 104, 
                  height: 104,
                  decoration: const BoxDecoration(
                    color: AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 20), 
                Container(
                  width: 180,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 140,
                  height: 16, 
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 100,
                  height: 36, 
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
          
          // Public Visibility Skeleton
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
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                      child: Container(
                        width: double.infinity,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.grey200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 48,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.grey200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
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

  // Service methods
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
        return token;
      } else if (token != null) {
        print('⚠️ Found token with key $key but it seems invalid: ${token.substring(0, token.length > 20 ? 20 : token.length)}...');
      }
    }
    
    return null;
  }

  Future<void> _loadProfileData(ProfileProvider profileProvider) async {
    try {
      profileProvider.isLoading = true;
      profileProvider.errorMessage = null;

      final prefs = await SharedPreferences.getInstance();
      
      String? accessToken = await _getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        profileProvider.errorMessage = 'No access token found. Please login again.';
        profileProvider.isLoading = false;
        return;
      }

      final httpClient = ApiConfig.createHttpClient();
      final profileUrl = ApiConfig.buildUrl('/api/students/get_profile/');
      final request = await httpClient.getUrl(Uri.parse(profileUrl));
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
          
          profileProvider.nameController.text = profile['name']?.toString() ?? '';
          profileProvider.phoneController.text = profile['phone_number']?.toString() ?? '';
          profileProvider.emailController.text = profile['email']?.toString() ?? '';
          profileProvider.selectedGender = _formatGender(profile['gender']?.toString());
          profileProvider.selectedBirthday = _formatDate(profile['dob']);
          profileProvider.studentType = profile['student_type']?.toString() ?? '';
          profileProvider.subscriptionData = profile['subscription'];
          profileProvider.showPublic = profile['show_public'] ?? false;
          
          if (profile['enrollments'] != null) {
            profileProvider.selectedCourse = profile['enrollments']['course']?.toString() ?? '';
            profileProvider.selectedSubCourse = profile['enrollments']['subcourse']?.toString() ?? '';
            profileProvider.originalCourse = profileProvider.selectedCourse ?? '';
            profileProvider.originalSubCourse = profileProvider.selectedSubCourse ?? '';
            
            if (profile['enrollments']['subcourse_id'] != null) {
              profileProvider.selectedSubCourseId = profile['enrollments']['subcourse_id'].toString();
              profileProvider.originalSubCourseId = profileProvider.selectedSubCourseId ?? '';
            }
          } else {
            print('ℹ️ No enrollments data found');
          }
          
          profileProvider.isLoading = false;
          
          await _fetchCoursesAndSubcourses(profileProvider);
        } else {
          profileProvider.errorMessage = 'Failed to load profile data';
          profileProvider.isLoading = false;
        }
      } else if (response.statusCode == 401) {
        profileProvider.errorMessage = 'Session expired. Please login again.';
        profileProvider.isLoading = false;
      } else {
        profileProvider.errorMessage = 'Failed to load profile: ${response.statusCode}';
        profileProvider.isLoading = false;
      }
    } catch (e) {
      profileProvider.errorMessage = 'Error loading profile: $e';
      profileProvider.isLoading = false;
    }
  }

  Future<void> _fetchCoursesAndSubcourses(ProfileProvider profileProvider) async {
    profileProvider.isLoadingData = true;
    profileProvider.dataLoadError = null;

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
          final subcoursesData = data['subcourses'];
          _processApiData(profileProvider, subcoursesData);
        } else {
          throw Exception('Invalid response format: ${data['message'] ?? 'Unknown error'}');
        }
      } else {
        throw Exception('Failed to load data: HTTP ${response.statusCode}');
      }
      
      client.close();
    } catch (e) {
      print('❌ Error fetching course data: $e');
      profileProvider.isLoadingData = false;
      profileProvider.dataLoadError = e.toString();
    }
  }

  void _processApiData(ProfileProvider profileProvider, List<dynamic> subcoursesData) {
    final coursesMap = <String, CourseModel>{};
    final subcoursesList = <SubcourseModel>[];
    
    for (var item in subcoursesData) {
      try {
        final subcourse = SubcourseModel.fromJson(item);
        subcoursesList.add(subcourse);
        
        if (!coursesMap.containsKey(subcourse.course)) {
          coursesMap[subcourse.course] = CourseModel(
            id: subcourse.course,
            title: subcourse.course,
            isSubcourse: false,
          );
        }
      } catch (e) {
        print('⚠️ Error processing subcourse item: $e');
      }
    }
    
    profileProvider.availableCourses = coursesMap.values.toList();
    profileProvider.availableSubcourses = subcoursesList;
    profileProvider.isLoadingData = false;

    print('✅ Processed ${profileProvider.availableCourses.length} courses and ${profileProvider.availableSubcourses.length} subcourses');
    _setInitialSubCourseId(profileProvider);
  }

  void _setInitialSubCourseId(ProfileProvider profileProvider) {
    if (profileProvider.selectedSubCourse != null && profileProvider.selectedSubCourse!.isNotEmpty) {
      final subcourse = profileProvider.availableSubcourses.firstWhere(
        (s) => s.title == profileProvider.selectedSubCourse && s.course == profileProvider.selectedCourse,
        orElse: () => SubcourseModel(id: '', title: '', course: ''),
      );
      if (subcourse.id.isNotEmpty) {
        profileProvider.selectedSubCourseId = subcourse.id;
        profileProvider.originalSubCourseId = subcourse.id;
        print('✅ Initial subcourse ID set: ${profileProvider.selectedSubCourseId} for subcourse: ${profileProvider.selectedSubCourse}');
      } else {
        print('⚠️ Could not find matching subcourse for: ${profileProvider.selectedSubCourse}');
      }
    } else {
      print('ℹ️ No selected subcourse to set ID for');
    }
  }

  Future<void> _selectDate(ProfileProvider profileProvider) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: profileProvider.selectedBirthday.isNotEmpty 
          ? _parseDateString(profileProvider.selectedBirthday) 
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
      profileProvider.selectedBirthday = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
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

  void _saveProfile(BuildContext context) async {
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    
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

      await _submitProfileToAPI(profileProvider);
      
      if (!mounted) return;
      Navigator.pop(context);
      
      profileProvider.isEditing = false;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: AppColors.primaryYellow,
        ),
      );

      await _loadProfileData(profileProvider);

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

  Future<void> _submitProfileToAPI(ProfileProvider profileProvider) async {
    try {
      final accessToken = await _getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('No access token found');
      }

      if (profileProvider.selectedGender.isEmpty) {
        throw Exception('Please select your gender');
      }
      if (profileProvider.selectedBirthday.isEmpty) {
        throw Exception('Please select your birth date');
      }
      if (profileProvider.selectedCourse == null || profileProvider.selectedCourse!.isEmpty) {
        throw Exception('Please select your course');
      }

      final birthdayParts = profileProvider.selectedBirthday.split('/');
      if (birthdayParts.length != 3) {
        throw Exception('Invalid birthday format');
      }
      final formattedBirthday = '${birthdayParts[2]}-${birthdayParts[1].padLeft(2, '0')}-${birthdayParts[0].padLeft(2, '0')}';

      Map<String, dynamic> profileData = {
        'gender': profileProvider.selectedGender.toUpperCase(),
        'dob': formattedBirthday,
        'course_name': profileProvider.selectedCourse,
      };

      if (profileProvider.selectedSubCourseId != null && profileProvider.selectedSubCourseId!.isNotEmpty) {
        profileData['subcourse_id'] = profileProvider.selectedSubCourseId;
        print('📤 Sending subcourse_id to API: ${profileProvider.selectedSubCourseId}');
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

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          print('✅ Profile updated successfully');
          
          profileProvider.originalCourse = profileProvider.selectedCourse ?? '';
          profileProvider.originalSubCourse = profileProvider.selectedSubCourse ?? '';
          profileProvider.originalSubCourseId = profileProvider.selectedSubCourseId ?? '';
          
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

  void _cancelEditing(ProfileProvider profileProvider) {
    profileProvider.isEditing = false;
    profileProvider.selectedCourse = profileProvider.originalCourse;
    profileProvider.selectedSubCourse = profileProvider.originalSubCourse;
    profileProvider.selectedSubCourseId = profileProvider.originalSubCourseId;
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
}