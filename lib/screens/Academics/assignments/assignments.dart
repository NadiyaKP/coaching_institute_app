import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import '../../../common/theme_color.dart';
import '../../../service/api_config.dart';
import '../../../service/auth_service.dart';
import 'upload_assignment_view.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({Key? key}) : super(key: key);

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

bool _isUploading = false;

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  List<Assignment> _assignments = [];
  List<Assignment> _pendingAssignments = [];
  List<Assignment> _overdueAssignments = [];
  List<Assignment> _submittedAssignments = [];
  Set<String> _notificationAssignmentIds = {}; // IDs from notifications
  List<Map<String, dynamic>> _unreadNotifications = []; // Complete notification data
  bool _isLoading = true;
  String _errorMessage = '';
  String? _accessToken;
  String _studentType = '';
  final AuthService _authService = AuthService();
  
  // Filter state
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    // Call mark notifications as read when the screen is disposed (user navigates back)
    _markNotificationsAsRead();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType();
    await _loadUnreadNotifications(); // Load unread notifications
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _fetchAssignments();
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

  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _studentType = prefs.getString('profile_student_type') ?? '';
      });
      debugPrint('Student Type loaded: $_studentType');
    } catch (e) {
      debugPrint('Error loading student type: $e');
    }
  }

  // Load unread notifications from shared preferences
  Future<void> _loadUnreadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? unreadNotificationsJson = prefs.getString('unread_notifications');
      
      if (unreadNotificationsJson != null && unreadNotificationsJson.isNotEmpty) {
        final List<dynamic> notifications = jsonDecode(unreadNotificationsJson);
        debugPrint('Stored unread notifications data: $notifications');
        
        setState(() {
          _unreadNotifications = notifications.cast<Map<String, dynamic>>();
          
          // Extract assignment IDs from notifications where type is 'assignment'
          _notificationAssignmentIds = _unreadNotifications
              .where((notification) => 
                  notification['data'] != null && 
                  notification['data']['type'] == 'assignment' &&
                  notification['data']['assignment_id'] != null)
              .map((notification) => notification['data']['assignment_id'] as String)
              .toSet();
        });
        
        debugPrint('Loaded notification assignment IDs: $_notificationAssignmentIds');
      } else {
        debugPrint('No unread notifications data found in SharedPreferences');
      }
    } catch (e) {
      debugPrint('Error loading unread notifications: $e');
    }
  }

  // Mark assignment as viewed - remove from unread_notifications and add id to ids list
  Future<void> _markAssignmentAsViewed(String assignmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Find the notification with this assignment_id
      final notificationToRemove = _unreadNotifications.firstWhere(
        (notification) => 
            notification['data'] != null && 
            notification['data']['assignment_id'] == assignmentId,
        orElse: () => {},
      );
      
      if (notificationToRemove.isNotEmpty) {
        final notificationId = notificationToRemove['id'];
        debugPrint('=== MARKING ASSIGNMENT AS VIEWED ===');
        debugPrint('Assignment ID: $assignmentId');
        debugPrint('Notification ID: $notificationId');
        debugPrint('Notification to remove: $notificationToRemove');
        
        // Remove from unread notifications data
        _unreadNotifications.removeWhere((notification) => 
            notification['data'] != null && 
            notification['data']['assignment_id'] == assignmentId);
        
        // Save updated unread notifications data (without the removed notification)
        await prefs.setString('unread_notifications', jsonEncode(_unreadNotifications));
        debugPrint('Updated unread_notifications (notification removed): $_unreadNotifications');
        
        // Get existing ids list or create new one
        List<int> idsList = [];
        final idsJson = prefs.getString('ids');
        if (idsJson != null && idsJson.isNotEmpty) {
          try {
            idsList = (jsonDecode(idsJson) as List).cast<int>();
            debugPrint('Existing ids list found: $idsList');
          } catch (e) {
            debugPrint('Error parsing ids list: $e');
          }
        } else {
          debugPrint('No existing ids list found, creating new one');
        }
        
        // Add notification id to ids list if not already present
        if (!idsList.contains(notificationId)) {
          idsList.add(notificationId);
          await prefs.setString('ids', jsonEncode(idsList));
          debugPrint('Added notification id to ids list: $notificationId');
          debugPrint('Updated ids list: $idsList');
        } else {
          debugPrint('Notification id already exists in ids list: $notificationId');
        }
        
        // REMOVE the entire notification content from SharedPreferences
        // The notification with its id, data, and created_at has already been removed from unread_notifications above
        // So the content is effectively deleted from SharedPreferences
        debugPrint('Notification content completely removed from unread_notifications');
        debugPrint('Removed notification details:');
        debugPrint('  - id: ${notificationToRemove['id']}');
        debugPrint('  - data: ${notificationToRemove['data']}');
        debugPrint('  - created_at: ${notificationToRemove['created_at']}');
        debugPrint('=== ASSIGNMENT MARKED AS VIEWED ===\n');
        
        // Update local state
        setState(() {
          _notificationAssignmentIds.remove(assignmentId);
        });
        
        // Re-categorize assignments
        _categorizeAssignments();
      } else {
        debugPrint('No notification found for assignment_id: $assignmentId');
      }
    } catch (e) {
      debugPrint('Error marking assignment as viewed: $e');
    }
  }

  // Mark notifications as read by sending IDs to API (similar to academics.dart)
  Future<void> _markNotificationsAsRead() async {
    debugPrint('🔍 _markNotificationsAsRead() called from AssignmentsScreen');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Debug: Check all keys in SharedPreferences
      final allKeys = prefs.getKeys();
      debugPrint('🔑 All SharedPreferences keys: $allKeys');
      
      final String? idsData = prefs.getString('ids');
      debugPrint('📝 Raw IDs data from SharedPreferences: $idsData');
      
      if (idsData == null || idsData.isEmpty) {
        debugPrint('📭 No IDs to mark as read');
        return;
      }
      
      // Parse the IDs list
      List<dynamic> idsList;
      try {
        idsList = json.decode(idsData);
        debugPrint('✅ Successfully parsed IDs list: $idsList (Type: ${idsList.runtimeType})');
      } catch (e) {
        debugPrint('❌ Failed to parse IDs JSON: $e');
        // Clear corrupted data
        await prefs.remove('ids');
        return;
      }
      
      if (idsList.isEmpty) {
        debugPrint('📭 IDs list is empty after parsing');
        await prefs.remove('ids');
        return;
      }
      
      debugPrint('📤 Marking ${idsList.length} notifications as read - IDs: $idsList');
      
      // Get fresh access token using AuthService (handles token refresh)
      final String? accessToken = await _authService.getAccessToken();
      debugPrint('🔐 Access token obtained from AuthService');
      
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('❌ Access token not found or empty');
        return;
      }
      
      // Get base URL using ApiConfig.currentBaseUrl
      final String baseUrl = ApiConfig.currentBaseUrl;
      debugPrint('🌐 Base URL from ApiConfig: $baseUrl');
      
      if (baseUrl.isEmpty) {
        debugPrint('❌ Base URL is empty');
        return;
      }
      
      // Prepare API endpoint
      final String apiUrl = '$baseUrl/api/notifications/mark_read/';
      
      // Prepare request body
      final Map<String, dynamic> requestBody = {
        'ids': idsList,
      };
      
      debugPrint('🌐 Full API URL: $apiUrl');
      debugPrint('📦 Request Body: ${json.encode(requestBody)}');
      debugPrint('🔐 Authorization Header: Bearer ${accessToken.substring(0, 10)}...');
      
      // Create HTTP client with custom certificate handling
      final client = IOClient(ApiConfig.createHttpClient());
      
      try {
        // Make POST request with authorization headers
        debugPrint('📡 Sending POST request...');
        final response = await client.post(
          Uri.parse(apiUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            ...ApiConfig.commonHeaders,
          },
          body: json.encode(requestBody),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('⏱️ Request timed out after 10 seconds');
            throw Exception('Request timeout');
          },
        );
        
        debugPrint('📨 Response Status Code: ${response.statusCode}');
        debugPrint('📨 Response Body: ${response.body}');
        debugPrint('📨 Response Headers: ${response.headers}');
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          // Successfully marked as read, clear the IDs from SharedPreferences
          await prefs.remove('ids');
          debugPrint('✅ Notifications marked as read successfully from AssignmentsScreen!');
          debugPrint('🗑️ IDs list cleared from SharedPreferences');
        } else if (response.statusCode == 401) {
          debugPrint('⚠️ Token expired or invalid - User needs to login again');
          // Handle token expiration
          await _authService.logout();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/signup',
              (Route<dynamic> route) => false,
            );
          }
        } else {
          debugPrint('⚠️ Failed to mark notifications as read from AssignmentsScreen');
          debugPrint('⚠️ Status Code: ${response.statusCode}');
          debugPrint('⚠️ Response: ${response.body}');
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('❌ SSL Handshake error: $e');
      debugPrint('This is normal in development environments with self-signed certificates');
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      debugPrint('Please check your internet connection');
    } catch (e, stackTrace) {
      debugPrint('❌ Error marking notifications as read from AssignmentsScreen: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
    
    debugPrint('🏁 _markNotificationsAsRead() completed from AssignmentsScreen');
  }

  // Categorize assignments into pending, overdue, and submitted
  void _categorizeAssignments() {
    final List<Assignment> pendingAssignments = [];
    final List<Assignment> overdueAssignments = [];
    final List<Assignment> submittedAssignments = [];

    for (final assignment in _assignments) {
      if (assignment.hasSubmitted) {
        submittedAssignments.add(assignment);
      } else {
        if (_isOverdue(assignment.lastDate)) {
          overdueAssignments.add(assignment);
        } else {
          pendingAssignments.add(assignment);
        }
      }
    }

    setState(() {
      _pendingAssignments = pendingAssignments;
      _overdueAssignments = overdueAssignments;
      _submittedAssignments = submittedAssignments;
    });
    
    debugPrint('Categorized assignments - Pending: ${_pendingAssignments.length}, Overdue: ${_overdueAssignments.length}, Submitted: ${_submittedAssignments.length}');
  }

  // Filter assignments based on selected filter
  void _filterAssignments(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  // Get assignments based on current filter
  List<Assignment> _getFilteredAssignments() {
    switch (_selectedFilter) {
      case 'Pending':
        return _pendingAssignments;
      case 'Overdue':
        return _overdueAssignments;
      case 'Submitted':
        return _submittedAssignments;
      default: // 'All'
        return _assignments;
    }
  }

  // Helper method to check if student is online
  bool get isOnlineStudent => _studentType.toLowerCase() == 'online';

  // Create HTTP client with custom certificate handling
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // Helper method to get authorization headers
  Map<String, String> _getAuthHeaders() {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Access token is null or empty');
    }
    
    return {
      'Authorization': 'Bearer $_accessToken',
      ...ApiConfig.commonHeaders,
    };
  }

  // Helper method to handle token expiration
  void _handleTokenExpiration() async {
    await _authService.logout();
    _showError('Session expired. Please login again.');
    _navigateToLogin();
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _fetchAssignments() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final client = _createHttpClientWithCustomCert();

    try {
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/attendance/assignments/';
      
      debugPrint('=== FETCHING ASSIGNMENTS API CALL ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Method: GET');
      debugPrint('Headers: ${_getAuthHeaders()}');
      
      final response = await client.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('\n=== ASSIGNMENTS API RESPONSE ===');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');
      
      // Pretty print JSON response
      try {
        final responseJson = jsonDecode(response.body);
        debugPrint('Response Body (Formatted):');
        debugPrint(const JsonEncoder.withIndent('  ').convert(responseJson));
      } catch (e) {
        debugPrint('Response Body: ${response.body}');
      }
      debugPrint('=== END ASSIGNMENTS API RESPONSE ===\n');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> assignmentsJson = data['assignments'];
          
          setState(() {
            _assignments = assignmentsJson
                .map((json) => Assignment.fromJson(json))
                .toList();
            _isLoading = false;
          });

          // Categorize assignments after fetching
          _categorizeAssignments();
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch assignments');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SSL certificate issue - this is normal in development'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching assignments: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    } finally {
      client.close();
    }
  }

  // File Upload functionality using file_selector - PDF ONLY
  Future<void> _pickAndUploadFile(Assignment assignment) async {
  try {
    // Define PDF file type only
    const XTypeGroup fileTypeGroup = XTypeGroup(
      label: 'PDF Documents',
      extensions: ['pdf'],
    );

    // Pick file
    final XFile? file = await openFile(
      acceptedTypeGroups: [fileTypeGroup],
    );

    if (file != null) {
      String fileName = file.name;
      
      // Validate file extension
      if (!fileName.toLowerCase().endsWith('.pdf')) {
        _showError('Only PDF files are allowed');
        return;
      }
      
      // Validate file size (e.g., max 10MB)
      int fileSizeInBytes = await file.length();
      double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      
      if (fileSizeInMB > 10) {
        _showError('File size must be less than 10MB');
        return;
      }

      // Show confirmation dialog before uploading
      await _showUploadConfirmationDialog(assignment, file, fileName);
      
    } else {
      // User canceled the picker
      debugPrint('File selection canceled');
    }
  } catch (e) {
    debugPrint('Error picking/uploading file: $e');
    _showError('Failed to upload file: ${e.toString()}');
  }
}

  // Show confirmation dialog before uploading
  Future<void> _showUploadConfirmationDialog(Assignment assignment, XFile file, String fileName) async {
    bool? shouldUpload = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                assignment.hasSubmitted ? Icons.replay_rounded : Icons.upload_rounded,
                color: AppColors.primaryYellow,
              ),
              const SizedBox(width: 8),
              Text(
                assignment.hasSubmitted ? 'Resubmit Assignment?' : 'Submit Assignment?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assignment.hasSubmitted 
                  ? 'You are about to resubmit this assignment. This will replace your previous submission.'
                  : 'You are about to submit this assignment:',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.topic,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'File: $fileName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                    if (assignment.hasSubmitted) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Note: Your previous marks and remarks will be reset.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Cancel
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textGrey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // Confirm
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: assignment.hasSubmitted ? Colors.orange : AppColors.primaryYellow,
                foregroundColor: Colors.white,
              ),
              child: Text(
                assignment.hasSubmitted ? 'Resubmit' : 'Submit',
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );

    if (shouldUpload == true) {
      // Upload the file
      await _uploadAssignmentFile(assignment.id, file, fileName, assignment.hasSubmitted);
    }
  }

 Future<void> _uploadAssignmentFile(String assignmentId, XFile file, String fileName, bool isResubmission) async {
  final client = _createHttpClientWithCustomCert();
  
  // Show loading indicator
  setState(() {
    _isUploading = true;
  });
  
  try {
    // Encode the assignment ID
    String encodedId = Uri.encodeComponent(assignmentId);
    
    final apiUrl = '${ApiConfig.currentBaseUrl}/api/attendance/assignments/$encodedId/submit/';
    
    debugPrint('=== UPLOADING ASSIGNMENT FILE ===');
    debugPrint('URL: $apiUrl');
    debugPrint('Assignment ID (Original): $assignmentId');
    debugPrint('Assignment ID (Encoded): $encodedId');
    debugPrint('File Name: $fileName');
    debugPrint('Is Resubmission: $isResubmission');
    
    var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
    request.headers.addAll(_getAuthHeaders());
    
    // Read file bytes and add to request
    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'submission_file',
      bytes,
      filename: fileName,
    ));
    
    debugPrint('Sending request...');
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    
    debugPrint('\n=== UPLOAD RESPONSE ===');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('=== END UPLOAD RESPONSE ===\n');
    
    // Hide loading indicator before showing message
    setState(() {
      _isUploading = false;
    });
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isResubmission 
                  ? 'Assignment resubmitted successfully!' 
                  : data['message'] ?? '$fileName uploaded successfully!'
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        // Refresh assignments list to get updated data
        await _fetchAssignments();
      } else {
        throw Exception(data['message'] ?? 'Upload failed');
      }
    } else if (response.statusCode == 401) {
      _handleTokenExpiration();
    } else {
      final data = json.decode(response.body);
      throw Exception(data['message'] ?? 'Server error: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error uploading file: $e');
    
    // Hide loading indicator on error
    setState(() {
      _isUploading = false;
    });
    
    _showError('Failed to upload file: ${e.toString().replaceAll("Exception: ", "")}');
  } finally {
    client.close();
  }
}

  // Open PDF in-app
  void _openPdfInApp(String fileUrl, String fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadAssignmentView(
          fileUrl: fileUrl,
          fileName: fileName,
        ),
      ),
    );
  }

  // Extract filename from URL
  String _getFileNameFromUrl(String url) {
    try {
      Uri uri = Uri.parse(url);
      String path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return 'Submitted File';
    }
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

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('MMM dd, yyyy hh:mm a').format(dateTime);
    } catch (e) {
      return dateTimeString;
    }
  }

  bool _isOverdue(String lastDate) {
    try {
      final date = DateTime.parse(lastDate);
      final now = DateTime.now();
      // Consider overdue if the current date is after the last date (excluding today)
      return now.isAfter(DateTime(date.year, date.month, date.day + 1));
    } catch (e) {
      return false;
    }
  }

  bool _isDueToday(String lastDate) {
    try {
      final date = DateTime.parse(lastDate);
      final now = DateTime.now();
      return now.year == date.year && now.month == date.month && now.day == date.day;
    } catch (e) {
      return false;
    }
  }

  void _showAssignmentDetails(Assignment assignment) {
    // Mark assignment as viewed when details are shown
    _markAssignmentAsViewed(assignment.id);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.assignment_rounded,
                            color: AppColors.primaryYellow,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                assignment.topic,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                assignment.chapter,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Assignment Details
                    _buildDetailRow(
                      icon: Icons.person_outline,
                      label: 'Assigned By',
                      value: assignment.assignedBy,
                    ),

                    const SizedBox(height: 12),

                    _buildDetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Last Date',
                      value: _formatDate(assignment.lastDate),
                      valueColor: _isOverdue(assignment.lastDate) && !assignment.hasSubmitted
                          ? Colors.red
                          : _isDueToday(assignment.lastDate) && !assignment.hasSubmitted
                              ? Colors.orange
                              : null,
                    ),

                    const SizedBox(height: 12),

                    // For submitted assignments, show both Total Marks and Marks Obtained
                    if (assignment.hasSubmitted) ...[
                      if (assignment.mark != null)
                        _buildDetailRow(
                          icon: Icons.grade_outlined,
                          label: 'Total Marks',
                          value: assignment.mark.toString(),
                        ),
                      
                      const SizedBox(height: 12),
                      
                      if (assignment.obtainedMark != null)
                        _buildDetailRow(
                          icon: Icons.star_outline,
                          label: 'Marks Obtained',
                          value: assignment.obtainedMark.toString(),
                          valueColor: Colors.green,
                        ),
                    ] else ...[
                      // For pending assignments, show only Total Marks
                      if (assignment.mark != null)
                        _buildDetailRow(
                          icon: Icons.grade_outlined,
                          label: 'Total Marks',
                          value: assignment.mark.toString(),
                        ),
                    ],

                    const SizedBox(height: 20),

                    // Remarks Section (only for submitted assignments with non-empty remarks)
                    if (assignment.hasSubmitted && 
                        assignment.remarks != null && 
                        assignment.remarks!.trim().isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.comment_outlined,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Remarks',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              assignment.remarks!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textDark,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Question Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryYellow.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                               Icon(
                                Icons.help_outline,
                                color: AppColors.primaryYellow,
                                size: 20,
                              ),
                               SizedBox(width: 8),
                               Text(
                                'Question',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            assignment.question,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textDark,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Upload/Resubmit Button (Only for Online Students)
                    if (isOnlineStudent && (!assignment.hasSubmitted || !_isOverdue(assignment.lastDate))) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close bottom sheet
                            _pickAndUploadFile(assignment);
                          },
                          icon: Icon(
                            assignment.hasSubmitted ? Icons.replay_rounded : Icons.upload_file_rounded, 
                            size: 20
                          ),
                          label: Text(
                            assignment.hasSubmitted ? 'Resubmit Assignment' : 'Upload Assignment',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: assignment.hasSubmitted 
                                ? Colors.orange 
                                : _isOverdue(assignment.lastDate) 
                                    ? Colors.red 
                                    : AppColors.primaryYellow,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          '(Upload in PDF format)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      if (assignment.hasSubmitted) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Note: Resubmitting will replace your previous file',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],

                    // Display uploaded file link if available
                    if (assignment.hasSubmitted && assignment.fileUrl != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.attach_file,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Submitted File',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => _openPdfInApp(
                                assignment.fileUrl!,
                                _getFileNameFromUrl(assignment.fileUrl!),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _getFileNameFromUrl(assignment.fileUrl!),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.open_in_new,
                                      color: Colors.blue,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Submission Status
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: assignment.hasSubmitted
                            ? Colors.green.withOpacity(0.1)
                            : _isOverdue(assignment.lastDate)
                                ? Colors.red.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: assignment.hasSubmitted
                              ? Colors.green.withOpacity(0.3)
                              : _isOverdue(assignment.lastDate)
                                  ? Colors.red.withOpacity(0.3)
                                  : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            assignment.hasSubmitted
                                ? Icons.check_circle_outline
                                : _isOverdue(assignment.lastDate)
                                    ? Icons.error_outline
                                    : Icons.pending_outlined,
                            color: assignment.hasSubmitted
                                ? Colors.green
                                : _isOverdue(assignment.lastDate)
                                    ? Colors.red
                                    : Colors.orange,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  assignment.hasSubmitted
                                      ? 'Submitted'
                                      : _isOverdue(assignment.lastDate)
                                          ? 'Overdue'
                                          : 'Pending',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: assignment.hasSubmitted
                                        ? Colors.green
                                        : _isOverdue(assignment.lastDate)
                                            ? Colors.red
                                            : Colors.orange,
                                  ),
                                ),
                                if (assignment.hasSubmitted &&
                                    assignment.submittedAt != null)
                                  Text(
                                    'on ${_formatDateTime(assignment.submittedAt!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                if (!assignment.hasSubmitted && _isOverdue(assignment.lastDate))
                                  Text(
                                    'Submission deadline has passed',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red[700],
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: AppColors.primaryYellow,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
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
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: 100,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build filter chip
  Widget _buildFilterChip(String label) {
    bool isSelected = _selectedFilter == label;
    Color chipColor;
    
    // Set colors based on filter type
    switch (label) {
      case 'Pending':
        chipColor = Colors.orange;
        break;
      case 'Overdue':
        chipColor = Colors.red;
        break;
      case 'Submitted':
        chipColor = Colors.green;
        break;
      default: // 'All'
        chipColor = AppColors.primaryYellow;
    }
    
    return GestureDetector(
      onTap: () => _filterAssignments(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? chipColor : AppColors.grey300,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: chipColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textGrey,
          ),
        ),
      ),
    );
  }

  // Build assignment item widget with status badge
  Widget _buildAssignmentItem(Assignment assignment) {
    final bool isOverdue = _isOverdue(assignment.lastDate) && !assignment.hasSubmitted;
    final bool isDueToday = _isDueToday(assignment.lastDate) && !assignment.hasSubmitted;
    final bool isNew = _notificationAssignmentIds.contains(assignment.id);

    // Determine status color and text
    Color statusColor;
    String statusText;
    
    if (assignment.hasSubmitted) {
      statusColor = Colors.green;
      statusText = 'Submitted';
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
    } else {
      statusColor = Colors.orange;
      statusText = isDueToday ? 'Due Today' : 'Pending';
    }

    return GestureDetector(
      onTap: () => _showAssignmentDetails(assignment),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isOverdue
              ? Border.all(color: Colors.red.withOpacity(0.3))
              : isDueToday
                  ? Border.all(color: Colors.orange.withOpacity(0.3))
                  : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryYellow.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon Container
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      assignment.hasSubmitted
                          ? Icons.check_circle
                          : isOverdue
                              ? Icons.error_outline
                              : Icons.assignment_rounded,
                      color: statusColor,
                      size: 26,
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Text Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                assignment.topic,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          assignment.chapter,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 12,
                              color: isOverdue 
                                  ? Colors.red 
                                  : isDueToday
                                      ? Colors.orange
                                      : AppColors.textGrey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Due: ${_formatDate(assignment.lastDate)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isOverdue 
                                    ? Colors.red 
                                    : isDueToday
                                        ? Colors.orange
                                        : AppColors.textGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        // Display marks for submitted assignments
                        if (assignment.hasSubmitted && 
                            assignment.obtainedMark != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Marks: ${assignment.obtainedMark}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Arrow Icon
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.primaryYellow.withOpacity(0.6),
                    size: 16,
                  ),
                ],
              ),
            ),
            
            // New Badge in top right corner
            if (isNew)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
  final filteredAssignments = _getFilteredAssignments();

  return Scaffold(
    backgroundColor: AppColors.backgroundLight,
    body: Stack(
      children: [
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
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button and title
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Assignments',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),              
                  ],
                ),
              ),
            ),

            // Filter Chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 6),
                    _buildFilterChip('Pending'),
                    const SizedBox(width: 6),
                    _buildFilterChip('Overdue'),
                    const SizedBox(width: 6),
                    _buildFilterChip('Submitted'),
                  ],
                ),
              ),
            ),

            // Main Content
            Expanded(
              child: _isLoading
                  ? _buildSkeletonLoader()
                  : _errorMessage.isNotEmpty
                      ? Center(
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
                                _errorMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textGrey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetchAssignments,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryYellow,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _assignments.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment_outlined,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No assignments yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Your assignments will appear here',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filteredAssignments.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _selectedFilter == 'Pending'
                                            ? Icons.pending_actions
                                            : _selectedFilter == 'Overdue'
                                                ? Icons.error_outline
                                                : _selectedFilter == 'Submitted'
                                                    ? Icons.check_circle_outline
                                                    : Icons.assignment_outlined,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No $_selectedFilter assignments',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _fetchAssignments,
                                  color: AppColors.primaryYellow,
                                  child: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      ...filteredAssignments.map((assignment) => 
                                        _buildAssignmentItem(assignment)
                                      ).toList(),
                                    ],
                                  ),
                                ),
            ),
          ],
        ),
        
        // Loading Overlay
        if (_isUploading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryYellow,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Uploading Assignment...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
}
// Assignment Model
class Assignment {
  final String id;
  final String topic;
  final String chapter;
  final String question;
  final int? mark;
  final String lastDate;
  final String assignedBy;
  final bool hasSubmitted;
  final String? submittedAt;
  final double? obtainedMark;
  final String? remarks;
  final String? fileUrl;

  Assignment({
    required this.id,
    required this.topic,
    required this.chapter,
    required this.question,
    this.mark,
    required this.lastDate,
    required this.assignedBy,
    required this.hasSubmitted,
    this.submittedAt,
    this.obtainedMark,
    this.remarks,
    this.fileUrl,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'],
      topic: json['topic'],
      chapter: json['chapter'],
      question: json['question'],
      mark: json['mark'],
      lastDate: json['last_date'],
      assignedBy: json['assigned_by'],
      hasSubmitted: json['has_submitted'],
      submittedAt: json['submitted_at'],
      obtainedMark: json['obtained_mark']?.toDouble(),
      remarks: json['remarks'],
      fileUrl: json['file_url'],
    );
  }
}

// Curved Header Clipper
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 25);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 25,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}