import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';

class StudyMaterialsScreen extends StatefulWidget {
  const StudyMaterialsScreen({super.key});

  @override
  State<StudyMaterialsScreen> createState() => _StudyMaterialsScreenState();
}

class _StudyMaterialsScreenState extends State<StudyMaterialsScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAndStoreSubjects();
  }

  // Fetch subjects from API and store in SharedPreferences
  Future<void> _fetchAndStoreSubjects() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get subcourse_id and access_token from SharedPreferences
      final String? encryptedId = prefs.getString('profile_subcourse_id');
      final String? accessToken = prefs.getString('accessToken');
      
      if (encryptedId == null || encryptedId.isEmpty) {
        print('Error: profile_subcourse_id not found in SharedPreferences');
        print('Available keys: ${prefs.getKeys()}');
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
        print('Error: accessToken not found in SharedPreferences');
        print('Available keys: ${prefs.getKeys()}');
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication required. Please login again.'),
              backgroundColor: AppColors.errorRed,
            ),
          );
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/signup',
            (Route<dynamic> route) => false,
          );
        }
        return;
      }

      // Check if subjects data already exists in SharedPreferences for this subcourse_id
      final String? cachedSubjectsData = prefs.getString('subjects_data');
      final String? cachedSubcourseId = prefs.getString('cached_subcourse_id');
      
      if (cachedSubjectsData != null && 
          cachedSubjectsData.isNotEmpty && 
          cachedSubcourseId == encryptedId) {
        print('✅ Using cached subjects data from SharedPreferences');
        print('Cached subcourse_id matches current: $encryptedId');
        
        // Display stored data in console
        _displayStoredData();
        
        setState(() {
          _isLoading = false;
        });
        
        return;
      }

      // No cached data or subcourse_id changed, fetch from API
      print('📡 No cached data found or subcourse_id changed. Fetching from API...');
      
      // Encode the subcourse_id
      String encodedId = Uri.encodeComponent(encryptedId);
      
      // Build the API URL
      String apiUrl = '${ApiConfig.baseUrl}/api/course/all/?subcourse_id=$encodedId';
      
      print('Fetching subjects from: $apiUrl');
      
      // Make GET request with Bearer token
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      print('Response Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          // Store the entire subjects data as JSON string
          await prefs.setString('subjects_data', json.encode(responseData['subjects']));
          
          // Store the subcourse_id to track which data is cached
          await prefs.setString('cached_subcourse_id', encryptedId);
          
          // Also store individual subject details for easy access
          final List<dynamic> subjects = responseData['subjects'];
          await prefs.setInt('subjects_count', subjects.length);
          
          print('✅ Subjects data stored successfully!');
          print('Total subjects: ${subjects.length}');
          print('Cached for subcourse_id: $encryptedId');
          
          // Display stored data in console
          _displayStoredData();
        } else {
          print('Error: API returned success: false');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to load study materials'),
                backgroundColor: AppColors.errorRed,
              ),
            );
          }
        }
      } else {
        print('Error: Failed to fetch subjects. Status code: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load study materials: ${response.statusCode}'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    } catch (e) {
      print('Exception occurred while fetching subjects: $e');
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

  // Display stored SharedPreferences data in console
  Future<void> _displayStoredData() async {
    final prefs = await SharedPreferences.getInstance();
    
    print('\n========== STORED SHARED PREFERENCES DATA ==========');
    
    // Display subcourse_id
    final subcourseId = prefs.getString('profile_subcourse_id');
    print('Subcourse ID (profile_subcourse_id): $subcourseId');
    
    // Display cached subcourse_id
    final cachedSubcourseId = prefs.getString('cached_subcourse_id');
    print('Cached Subcourse ID (cached_subcourse_id): $cachedSubcourseId');
    
    // Display access_token
    final accessToken = prefs.getString('accessToken');
    if (accessToken != null && accessToken.length > 20) {
      print('Access Token (accessToken): ${accessToken.substring(0, 20)}...');
    } else {
      print('Access Token (accessToken): $accessToken');
    }
    
    // Display subjects count
    final subjectsCount = prefs.getInt('subjects_count');
    print('Subjects Count: $subjectsCount');
    
    // Display full subjects data
    final subjectsData = prefs.getString('subjects_data');
    if (subjectsData != null) {
      print('\nSubjects Data (JSON):');
      final subjects = json.decode(subjectsData);
      print(JsonEncoder.withIndent('  ').convert(subjects));
      
      // Display structured information
      print('\n--- Subject Details ---');
      for (int i = 0; i < subjects.length; i++) {
        final subject = subjects[i];
        print('\nSubject ${i + 1}:');
        print('  ID: ${subject['id']}');
        print('  Title: ${subject['title']}');
        print('  Units Count: ${subject['units'].length}');
        
        if (subject['units'].isNotEmpty) {
          for (int j = 0; j < subject['units'].length; j++) {
            final unit = subject['units'][j];
            print('    Unit ${j + 1}: ${unit['title']} (${unit['chapters'].length} chapters)');
            
            if (unit['chapters'].isNotEmpty) {
              for (var chapter in unit['chapters']) {
                print('      - ${chapter['title']}');
              }
            }
          }
        }
      }
    }
    
    print('\n====================================================\n');
  }

  // Navigation methods for each study material type
  void _navigateToVideoClasses() {
    Navigator.pushNamed(context, '/video_classes');
  }

  void _navigateToNotes() {
    Navigator.pushNamed(context, '/notes');
  }

  void _navigateToPreviousQuestionPapers() {
    Navigator.pushNamed(context, '/question_papers');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Study Materials',
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: AppColors.white),
        elevation: 0,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryYellow,
              AppColors.backgroundLight,
              AppColors.white,
            ],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                
                // Study Material Cards
                // Video Classes Card
                _buildStudyMaterialCard(
                  title: 'Video Classes',
                  subtitle: 'Watch expert lectures and tutorials',
                  icon: Icons.play_circle_fill,
                  containerColor: AppColors.warningOrange,
                  iconColor: AppColors.primaryYellow,
                  textColor: AppColors.primaryBlue,
                  onTap: _navigateToVideoClasses,
                ),
                
                const SizedBox(height: 20),
                
                // Notes Card
                _buildStudyMaterialCard(
                  title: 'Notes',
                  subtitle: 'Access comprehensive study notes',
                  icon: Icons.note_alt,
                  containerColor: AppColors.warningOrange,
                  iconColor: AppColors.primaryYellow,
                  textColor: AppColors.primaryBlue,
                  onTap: _navigateToNotes,
                ),
                
                const SizedBox(height: 20),
                
                // Previous Question Papers Card
                _buildStudyMaterialCard(
                  title: 'Previous Question Papers',
                  subtitle: 'Practice with past exam papers',
                  icon: Icons.quiz,
                  containerColor: AppColors.warningOrange,
                  iconColor: AppColors.primaryYellow,
                  textColor: AppColors.primaryBlue,
                  onTap: _navigateToPreviousQuestionPapers,
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudyMaterialCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color containerColor,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 8,
      shadowColor: containerColor.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.white,
                containerColor.withOpacity(0.1),
              ],
            ),
          ),
          child: Row(
            children: [
              // Icon section
              Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: iconColor.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: iconColor,
                ),
              ),
              
              const SizedBox(width: 20),
              
              // Text section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor.withOpacity(0.7),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Arrow icon
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: containerColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.white,
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