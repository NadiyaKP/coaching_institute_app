import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../common/theme_color.dart';
import '../../../service/auth_service.dart';
import '../../../service/api_config.dart';
import 'leave_application_model.dart'; 

class NewLeaveApplicationScreen extends StatefulWidget {
  final bool isEditMode;
  final LeaveApplication? leaveApplication;

  const NewLeaveApplicationScreen({
    Key? key,
    this.isEditMode = false,
    this.leaveApplication,
  }) : super(key: key);

  @override
  State<NewLeaveApplicationScreen> createState() => _NewLeaveApplicationScreenState();
}

class _NewLeaveApplicationScreenState extends State<NewLeaveApplicationScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  
  String _selectedLeaveType = 'SICK';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    
    // If in edit mode, prefill the form with existing data
    if (widget.isEditMode && widget.leaveApplication != null) {
      _prefillForm();
    }
  }

  void _prefillForm() {
    final leave = widget.leaveApplication!;
    
    setState(() {
      _selectedLeaveType = leave.leaveType;
      _reasonController.text = leave.reason;
      
      // Parse dates
      try {
        _startDate = DateTime.parse(leave.startDate);
        _endDate = DateTime.parse(leave.endDate);
      } catch (e) {
        debugPrint('Error parsing dates: $e');
      }
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // Check if string contains emoji
  bool _containsEmoji(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{FE00}-\u{FE0F}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]',
      unicode: true,
    );
    return emojiRegex.hasMatch(text);
  }

  // Format date to DD-MM-YYYY for display
  String _formatDateForDisplay(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date);
  }

  // Format date to YYYY-MM-DD for API
  String _formatDateForAPI(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Select start date
  Future<void> _selectStartDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryYellow,
              onPrimary: Colors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _startDate = pickedDate;
        // Reset end date if it's before the new start date
        if (_endDate != null && _endDate!.isBefore(pickedDate)) {
          _endDate = null;
        }
      });
    }
  }

  // Select end date
  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select "Absence From" date first'),
          backgroundColor: AppColors.warningOrange,
        ),
      );
      return;
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!,
      firstDate: _startDate!,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryYellow,
              onPrimary: Colors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _endDate = pickedDate;
      });
    }
  }

  // Validate and submit form (handles both create and edit)
  Future<void> _submitLeaveApplication() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select "Absence From" date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select "Absence Through" date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
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

      // Prepare API URL based on mode
      final String apiUrl;
      if (widget.isEditMode && widget.leaveApplication != null) {
        apiUrl = '$baseUrl/api/students/edit_leave/${widget.leaveApplication!.encryptedId}/';
      } else {
        apiUrl = '$baseUrl/api/students/apply_leave/';
      }
      
      // Prepare request body
      final Map<String, dynamic> requestBody = {
        'leave_type': _selectedLeaveType,
        'start_date': _formatDateForAPI(_startDate!),
        'end_date': _formatDateForAPI(_endDate!),
        'reason': _reasonController.text.trim(),
      };

      debugPrint('Request URL: $apiUrl');
      debugPrint('Request Body: ${json.encode(requestBody)}');

      // Create HTTP client
      final client = IOClient(ApiConfig.createHttpClient());
      
      try {
        final response;
        
        if (widget.isEditMode) {
          // Use PUT method for edit
          response = await client.put(
            Uri.parse(apiUrl),
            headers: {
              'Authorization': 'Bearer $accessToken',
              ...ApiConfig.commonHeaders,
            },
            body: json.encode(requestBody),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );
        } else {
          // Use POST method for new application
          response = await client.post(
            Uri.parse(apiUrl),
            headers: {
              'Authorization': 'Bearer $accessToken',
              ...ApiConfig.commonHeaders,
            },
            body: json.encode(requestBody),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );
        }

        debugPrint('Response Status: ${response.statusCode}');
        debugPrint('Response Body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Success - show success message and navigate back
          if (mounted) {
            final successMessage = widget.isEditMode
                ? 'Leave application updated successfully!'
                : 'Leave application submitted successfully!';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage),
                backgroundColor: AppColors.successGreen,
                duration: const Duration(seconds: 2),
              ),
            );

            // Navigate back with success flag
            Navigator.pop(context, true);
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
          // Handle error response
          String errorMessage = widget.isEditMode
              ? 'Failed to update leave application'
              : 'Failed to submit leave application';
          
          try {
            final Map<String, dynamic> errorData = json.decode(response.body);
            if (errorData['message'] != null) {
              errorMessage = errorData['message'];
            } else if (errorData['error'] != null) {
              errorMessage = errorData['error'];
            }
          } catch (e) {
            debugPrint('Error parsing error response: $e');
          }
          
          throw Exception(errorMessage);
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      _showErrorSnackBar('SSL connection error');
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      _showErrorSnackBar('Network error. Please check your connection.');
    } catch (e) {
      debugPrint('Error submitting leave application: $e');
      _showErrorSnackBar(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
                      Expanded(
                        child: Text(
                          widget.isEditMode 
                              ? 'Edit Leave Application' 
                              : 'New Leave Application',
                          style: const TextStyle(
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

          // Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type of Leave Request Section
                    const Text(
                      'Type of Leave Request',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Leave Type Radio Buttons
                    Container(
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
                      child: Column(
                        children: [
                          _buildRadioOption('SICK', 'Sick'),
                          const Divider(height: 1),
                          _buildRadioOption('PERSONAL', 'Personal Leave'),
                          const Divider(height: 1),
                          _buildRadioOption('OTHERS', 'Others'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Date Selection Row
                    Row(
                      children: [
                        // Absence From
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Absence From',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _selectStartDate,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _startDate == null
                                          ? Colors.grey.shade300
                                          : AppColors.primaryYellow,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 18,
                                        color: _startDate == null
                                            ? AppColors.textGrey
                                            : AppColors.primaryYellow,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _startDate == null
                                              ? 'Select date'
                                              : _formatDateForDisplay(_startDate!),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _startDate == null
                                                ? AppColors.textGrey
                                                : AppColors.textDark,
                                            fontWeight: _startDate == null
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Absence Through
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Absence Through',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _selectEndDate,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _endDate == null
                                          ? Colors.grey.shade300
                                          : AppColors.primaryYellow,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 18,
                                        color: _endDate == null
                                            ? AppColors.textGrey
                                            : AppColors.primaryYellow,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _endDate == null
                                              ? 'Select date'
                                              : _formatDateForDisplay(_endDate!),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _endDate == null
                                                ? AppColors.textGrey
                                                : AppColors.textDark,
                                            fontWeight: _endDate == null
                                                ? FontWeight.normal
                                                : FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Reason Section
                    const Text(
                      'Reason',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
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
                      child: TextFormField(
                        controller: _reasonController,
                        maxLines: 5,
                        maxLength: 500,
                        inputFormatters: [
                          // Filter out emojis
                          FilteringTextInputFormatter.deny(
                            RegExp(
                              r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{FE00}-\u{FE0F}]|[\u{1F018}-\u{1F270}]|[\u{238C}-\u{2454}]|[\u{20D0}-\u{20FF}]',
                              unicode: true,
                            ),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Enter reason for leave...',
                          hintStyle: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(16),
                          counterStyle: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a reason for leave';
                          }
                          if (_containsEmoji(value)) {
                            return 'Emojis are not allowed';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitLeaveApplication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryYellow,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.textGrey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                widget.isEditMode ? 'Update' : 'Submit',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(String value, String label) {
    final bool isSelected = _selectedLeaveType == value;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedLeaveType = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryYellow
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryYellow,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.textDark : AppColors.textGrey,
              ),
            ),
          ],
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