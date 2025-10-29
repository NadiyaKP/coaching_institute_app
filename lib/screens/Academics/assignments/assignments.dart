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

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({Key? key}) : super(key: key);

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  List<Assignment> _assignments = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String? _accessToken;
  String _studentType = '';
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType();
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

  // PDF Upload functionality using file_selector
  Future<void> _pickAndUploadPDF(Assignment assignment) async {
    try {
      // Define PDF file type
      const XTypeGroup pdfTypeGroup = XTypeGroup(
        label: 'PDFs',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
      );

      // Pick PDF file
      final XFile? file = await openFile(
        acceptedTypeGroups: [pdfTypeGroup],
      );

      if (file != null) {
        String fileName = file.name;
        
        // Validate file size (e.g., max 10MB)
        int fileSizeInBytes = await file.length();
        double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
        
        if (fileSizeInMB > 10) {
          _showError('File size must be less than 10MB');
          return;
        }

        // Show loading dialog
        _showUploadingDialog(fileName);

        // TODO: Replace with your actual API endpoint
        // await _uploadAssignmentPDF(assignment.id, file, fileName);
        
        // Simulate upload delay (remove this when implementing actual API)
        await Future.delayed(const Duration(seconds: 2));
        
        // Close loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$fileName uploaded successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Refresh assignments list
        await _fetchAssignments();
        
      } else {
        // User canceled the picker
        debugPrint('File selection canceled');
      }
    } catch (e) {
      debugPrint('Error picking/uploading file: $e');
      
      // Close loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      _showError('Failed to upload file: ${e.toString()}');
    }
  }

  void _showUploadingDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
              ),
              const SizedBox(height: 16),
              Text('Uploading $fileName...'),
            ],
          ),
        );
      },
    );
  }

  // TODO: Implement this method with your actual API endpoint
  // Future<void> _uploadAssignmentPDF(String assignmentId, XFile file, String fileName) async {
  //   final client = _createHttpClientWithCustomCert();
  //   
  //   try {
  //     final apiUrl = '${ApiConfig.currentBaseUrl}/api/attendance/assignments/upload/';
  //     
  //     var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
  //     request.headers.addAll(_getAuthHeaders());
  //     request.fields['assignment_id'] = assignmentId;
  //     
  //     // Read file bytes and add to request
  //     final bytes = await file.readAsBytes();
  //     request.files.add(http.MultipartFile.fromBytes(
  //       'file',
  //       bytes,
  //       filename: fileName,
  //     ));
  //     
  //     var streamedResponse = await request.send();
  //     var response = await http.Response.fromStream(streamedResponse);
  //     
  //     if (response.statusCode == 200) {
  //       final data = json.decode(response.body);
  //       if (data['success'] != true) {
  //         throw Exception(data['message'] ?? 'Upload failed');
  //       }
  //     } else if (response.statusCode == 401) {
  //       _handleTokenExpiration();
  //     } else {
  //       throw Exception('Server error: ${response.statusCode}');
  //     }
  //   } finally {
  //     client.close();
  //   }
  // }

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
      return DateTime.now().isAfter(date);
    } catch (e) {
      return false;
    }
  }

  void _showAssignmentDetails(Assignment assignment) {
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

                    // Upload Button (Only for Online Students and Not Submitted)
                    if (isOnlineStudent && !assignment.hasSubmitted) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close bottom sheet
                            _pickAndUploadPDF(assignment);
                          },
                          icon: const Icon(Icons.upload_file_rounded, size: 20),
                          label: const Text(
                            'Upload Assignment (PDF)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryYellow,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
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
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: assignment.hasSubmitted
                              ? Colors.green.withOpacity(0.3)
                              : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            assignment.hasSubmitted
                                ? Icons.check_circle_outline
                                : Icons.pending_outlined,
                            color: assignment.hasSubmitted
                                ? Colors.green
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
                                      : 'Not Submitted',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: assignment.hasSubmitted
                                        ? Colors.green
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Column(
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
                  Text(
                    'View and track your assignments',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
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
                        : RefreshIndicator(
                            onRefresh: _fetchAssignments,
                            color: AppColors.primaryYellow,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _assignments.length,
                              itemBuilder: (context, index) {
                                final assignment = _assignments[index];
                                final isOverdue = _isOverdue(assignment.lastDate) &&
                                    !assignment.hasSubmitted;

                                return GestureDetector(
                                  onTap: () => _showAssignmentDetails(assignment),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: isOverdue
                                          ? Border.all(color: Colors.red.withOpacity(0.3))
                                          : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryYellow.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          // Icon Container
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryYellow.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              assignment.hasSubmitted
                                                  ? Icons.check_circle
                                                  : Icons.assignment_rounded,
                                              color: assignment.hasSubmitted
                                                  ? Colors.green
                                                  : AppColors.primaryYellow,
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
                                                        color: assignment.hasSubmitted
                                                            ? Colors.green.withOpacity(0.1)
                                                            : Colors.orange.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        assignment.hasSubmitted
                                                            ? 'Submitted'
                                                            : 'Pending',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: assignment.hasSubmitted
                                                              ? Colors.green
                                                              : Colors.orange,
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
                                                      color: isOverdue ? Colors.red : AppColors.textGrey,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Due: ${_formatDate(assignment.lastDate)}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isOverdue ? Colors.red : AppColors.textGrey,
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
                                  ),
                                );
                              },
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