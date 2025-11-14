import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import '../../../common/theme_color.dart';
import '../../../service/auth_service.dart';
import '../../../service/api_config.dart';
import 'new_leave_application.dart';
import 'leave_application_model.dart'; // Import the model
import 'package:intl/intl.dart';

class MyLeaveApplicationScreen extends StatefulWidget {
  const MyLeaveApplicationScreen({Key? key}) : super(key: key);

  @override
  State<MyLeaveApplicationScreen> createState() => _MyLeaveApplicationScreenState();
}

class _MyLeaveApplicationScreenState extends State<MyLeaveApplicationScreen> {
  final AuthService _authService = AuthService();
  
  bool _isLoading = true;
  List<LeaveApplication> _leaveApplications = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLeaveApplications();
  }

  Future<void> _fetchLeaveApplications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get access token
      final String? accessToken = await _authService.getAccessToken();
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Access token not found');
      }

      // Get base URL
      final String baseUrl = ApiConfig.currentBaseUrl;
      if (baseUrl.isEmpty) {
        throw Exception('Base URL is empty');
      }

      final String apiUrl = '$baseUrl/api/students/my_leaves/';
      
      // Create HTTP client
      final client = IOClient(ApiConfig.createHttpClient());
      
      try {
        final response = await client.get(
          Uri.parse(apiUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            ...ApiConfig.commonHeaders,
          },
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('Request timeout');
          },
        );

        debugPrint('Response Status: ${response.statusCode}');
        debugPrint('Response Body: ${response.body}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body);
          
          if (data['success'] == true && data['data'] != null) {
            final List<dynamic> leavesData = data['data'];
            
            setState(() {
              _leaveApplications = leavesData
                  .map((leave) => LeaveApplication.fromJson(leave))
                  .toList();
              _isLoading = false;
            });
          } else {
            throw Exception('Invalid response format');
          }
        } else if (response.statusCode == 401) {
          // Handle unauthorized
          await _authService.logout();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/signup',
              (Route<dynamic> route) => false,
            );
          }
        } else {
          throw Exception('Failed to load leave applications');
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() {
        _errorMessage = 'SSL connection error';
        _isLoading = false;
      });
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching leave applications: $e');
      setState(() {
        _errorMessage = 'Failed to load leave applications';
        _isLoading = false;
      });
    }
  }

  void _navigateToNewLeaveApplication() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewLeaveApplicationScreen(),
      ),
    );

    // Refresh the list if a new leave was submitted
    if (result == true) {
      _fetchLeaveApplications();
    }
  }

  void _navigateToEditLeaveApplication(LeaveApplication leave) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewLeaveApplicationScreen(
          isEditMode: true,
          leaveApplication: leave,
        ),
      ),
    );

    // Refresh the list if the leave was edited
    if (result == true) {
      _fetchLeaveApplications();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return AppColors.warningOrange;
      case 'APPROVED':
        return AppColors.successGreen;
      case 'REJECTED':
        return Colors.red;
      default:
        return AppColors.textGrey;
    }
  }

  String _formatLeaveType(String leaveType) {
    return leaveType.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _formatDate(String dateStr) {
    try {
      final DateTime date = DateTime.parse(dateStr);
      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final DateTime dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('dd-MM-yyyy, hh:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  void _showLeaveDetailsDialog(LeaveApplication leave) {
    final bool isPending = leave.status.toUpperCase() == 'PENDING';
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header - Compact
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _getStatusColor(leave.status).withOpacity(0.8),
                        _getStatusColor(leave.status),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Leave Details',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatLeaveType(leave.status),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Details Content - Scrollable
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // Leave Type
                      _buildDetailRow(
                        icon: Icons.category_rounded,
                        label: 'Leave Type',
                        value: _formatLeaveType(leave.leaveType),
                        iconColor: AppColors.primaryYellow,
                      ),
                      
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Reason
                      _buildDetailRow(
                        icon: Icons.notes_rounded,
                        label: 'Reason',
                        value: leave.reason,
                        iconColor: AppColors.primaryBlue,
                        isMultiline: true,
                      ),
                      
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Absence From
                      _buildDetailRow(
                        icon: Icons.calendar_today,
                        label: 'Absence From',
                        value: _formatDate(leave.startDate),
                        iconColor: AppColors.successGreen,
                      ),
                      
                      const SizedBox(height: 16),

                      // Absence Through
                      _buildDetailRow(
                        icon: Icons.event_rounded,
                        label: 'Absence Through',
                        value: _formatDate(leave.endDate),
                        iconColor: AppColors.warningOrange,
                      ),
                      
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),

                      // Applied On
                      _buildDetailRow(
                        icon: Icons.access_time_rounded,
                        label: 'Applied On',
                        value: _formatDateTime(leave.appliedOn),
                        iconColor: AppColors.textGrey,
                      ),

                      // Marked By (if available)
                      if (leave.markedBy != null) ...[
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          icon: Icons.person_rounded,
                          label: 'Marked By',
                          value: leave.markedBy!,
                          iconColor: AppColors.primaryYellowDark,
                        ),
                      ],

                      // Remark (if available)
                      if (leave.remark != null && leave.remark!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildDetailRow(
                          icon: Icons.comment_rounded,
                          label: 'Remark',
                          value: leave.remark!,
                          iconColor: Colors.purple,
                          isMultiline: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    // Edit Button (only for pending leaves)
                    if (isPending) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context); // Close dialog
                            _navigateToEditLeaveApplication(leave);
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Close Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getStatusColor(leave.status),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    bool isMultiline = false,
  }) {
    return Row(
      crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor,
          ),
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
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Column(
        children: [
          // Header Section
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
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'My Leave Applications',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // New Leave Application Button (Below App Bar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _navigateToNewLeaveApplication,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New Leave Application'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warningOrange,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? _buildSkeletonLoader()
                : _errorMessage != null
                    ? _buildErrorWidget()
                    : _leaveApplications.isEmpty
                        ? _buildEmptyState()
                        : _buildLeaveList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 80,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 60,
            color: Colors.red.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'An error occurred',
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textGrey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchLeaveApplications,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryYellow,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note,
            size: 80,
            color: AppColors.textGrey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Leave Applications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'You haven\'t applied for any leave yet',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveList() {
    return RefreshIndicator(
      onRefresh: _fetchLeaveApplications,
      color: AppColors.primaryYellow,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _leaveApplications.length,
        itemBuilder: (context, index) {
          final leave = _leaveApplications[index];
          return _buildLeaveCard(leave);
        },
      ),
    );
  }

  Widget _buildLeaveCard(LeaveApplication leave) {
    return GestureDetector(
      onTap: () => _showLeaveDetailsDialog(leave),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Leave Type and Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatLeaveType(leave.leaveType),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${_formatDate(leave.startDate)} - ${_formatDate(leave.endDate)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Status Badge (Clickable)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(leave.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _getStatusColor(leave.status).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatLeaveType(leave.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(leave.status),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: _getStatusColor(leave.status),
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