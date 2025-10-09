import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/auth_service.dart';
import '../service/api_config.dart';
import '../common/theme_color.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                
                // Account Settings Section
                Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Change Password Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: _showChangePasswordDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryYellow.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.lock_outline,
                              color: AppColors.primaryYellow,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Change Password',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Update your account password',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.textGrey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // App Settings Section
                Text(
                  'App Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Notifications Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.notifications_outlined,
                            color: AppColors.primaryYellow,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notifications',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Manage notification preferences',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Coming Soon',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show Change Password Dialog
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final currentPasswordFocus = FocusNode();
    final newPasswordFocus = FocusNode();
    final confirmPasswordFocus = FocusNode();
    
    bool currentPasswordVisible = false;
    bool newPasswordVisible = false;
    bool confirmPasswordVisible = false;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.lock_reset,
                    color: AppColors.primaryYellow,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Current Password Field
                    TextField(
                      controller: currentPasswordController,
                      focusNode: currentPasswordFocus,
                      obscureText: !currentPasswordVisible,
                      onEditingComplete: () {
                        // Validate when moving to next field
                        if (currentPasswordController.text.isNotEmpty && 
                            currentPasswordController.text.length < 4) {
                          _showErrorSnackBar('Current password must be at least 4 characters');
                        }
                        newPasswordFocus.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter current password',
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: AppColors.primaryYellow,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            currentPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              currentPasswordVisible = !currentPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppColors.primaryYellow,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // New Password Field
                    TextField(
                      controller: newPasswordController,
                      focusNode: newPasswordFocus,
                      obscureText: !newPasswordVisible,
                      onEditingComplete: () {
                        // Validate when moving to next field
                        if (newPasswordController.text.isNotEmpty && 
                            newPasswordController.text.length < 4) {
                          _showErrorSnackBar('New password must be at least 4 characters');
                        }
                        confirmPasswordFocus.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        hintText: 'Enter new password',
                        prefixIcon: Icon(
                          Icons.lock,
                          color: AppColors.primaryYellow,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            newPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              newPasswordVisible = !newPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppColors.primaryYellow,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Confirm Password Field
                    TextField(
                      controller: confirmPasswordController,
                      focusNode: confirmPasswordFocus,
                      obscureText: !confirmPasswordVisible,
                      onEditingComplete: () {
                        // Validate when moving away from field
                        if (confirmPasswordController.text.isNotEmpty && 
                            confirmPasswordController.text.length < 4) {
                          _showErrorSnackBar('Confirm password must be at least 4 characters');
                        }
                        confirmPasswordFocus.unfocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        hintText: 'Re-enter new password',
                        prefixIcon: Icon(
                          Icons.lock_clock,
                          color: AppColors.primaryYellow,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            confirmPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              confirmPasswordVisible = !confirmPasswordVisible;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppColors.primaryYellow,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          // Validate all fields
                          if (currentPasswordController.text.isEmpty) {
                            _showErrorSnackBar('Please enter current password');
                            return;
                          }
                          
                          if (currentPasswordController.text.length < 4) {
                            _showErrorSnackBar('Current password must be at least 4 characters');
                            return;
                          }
                          
                          if (newPasswordController.text.isEmpty) {
                            _showErrorSnackBar('Please enter new password');
                            return;
                          }
                          
                          if (newPasswordController.text.length < 4) {
                            _showErrorSnackBar('New password must be at least 4 characters');
                            return;
                          }
                          
                          if (confirmPasswordController.text.isEmpty) {
                            _showErrorSnackBar('Please confirm new password');
                            return;
                          }
                          
                          if (confirmPasswordController.text.length < 4) {
                            _showErrorSnackBar('Confirm password must be at least 4 characters');
                            return;
                          }
                          
                          // Check if current password and new password are the same
                          if (currentPasswordController.text == newPasswordController.text) {
                            _showErrorSnackBar('New password must be different from current password');
                            return;
                          }
                          
                          // Check if new password and confirm password match
                          if (newPasswordController.text != confirmPasswordController.text) {
                            _showErrorSnackBar('New password and confirm password do not match');
                            return;
                          }
                          
                          // Show loading
                          setState(() {
                            isLoading = true;
                          });
                          
                          // Call change password API
                          final result = await _changePassword(
                            currentPasswordController.text,
                            newPasswordController.text,
                          );
                          
                          setState(() {
                            isLoading = false;
                          });
                          
                          // Close dialog if successful
                          if (result['success'] == true) {
                            // Close dialog first
                            if (Navigator.of(dialogContext).canPop()) {
                              Navigator.of(dialogContext).pop();
                            }
                            
                            // Show success message on main screen after a short delay
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(result['message'] ?? 'Password changed successfully'),
                                    backgroundColor: AppColors.successGreen,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            });
                          } else {
                            // Show error message
                            _showErrorSnackBar(result['message'] ?? 'Failed to change password');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Submit',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Defer disposal to avoid "used after being disposed" errors
      SchedulerBinding.instance.addPostFrameCallback((_) {
        currentPasswordController.dispose();
        newPasswordController.dispose();
        confirmPasswordController.dispose();
        currentPasswordFocus.dispose();
        newPasswordFocus.dispose();
        confirmPasswordFocus.dispose();
      });
    });
  }

  // Change Password API call - Returns result map
  Future<Map<String, dynamic>> _changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      // Get access token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken');
      
      if (accessToken == null || accessToken.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication failed. Please login again.'
        };
      }

      // Create HTTP client
      final client = ApiConfig.createHttpClient();
      
      try {
        // Prepare request body
        final body = jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        });

        debugPrint('Change Password Request Body: $body');

        // Make API call with PUT method
        final response = await http.put(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/students/password_change/'),
          headers: {
            ...ApiConfig.commonHeaders,
            'Authorization': 'Bearer $accessToken',
          },
          body: body,
        ).timeout(ApiConfig.requestTimeout);

        debugPrint('Change Password Response Status: ${response.statusCode}');
        debugPrint('Change Password Response Body: ${response.body}');

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          
          if (responseData['success'] == true) {
            return {
              'success': true,
              'message': responseData['message'] ?? 'Password changed successfully'
            };
          } else {
            return {
              'success': false,
              'message': responseData['message'] ?? 'Failed to change password'
            };
          }
        } else if (response.statusCode == 400) {
          final responseData = json.decode(response.body);
          return {
            'success': false,
            'message': responseData['message'] ?? 'Invalid current password'
          };
        } else if (response.statusCode == 401) {
          // Logout and navigate to login
          await _authService.logout();
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/signup',
              (Route<dynamic> route) => false,
            );
          }
          return {
            'success': false,
            'message': 'Session expired. Please login again.'
          };
        } else {
          return {
            'success': false,
            'message': 'Failed to change password. Please try again.'
          };
        }
      } finally {
        client.close();
      }
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      return {
        'success': false,
        'message': 'No internet connection'
      };
    } on HandshakeException catch (e) {
      debugPrint('SSL error: $e');
      return {
        'success': false,
        'message': 'Connection error. Please try again.'
      };
    } catch (e) {
      debugPrint('Error changing password: $e');
      return {
        'success': false,
        'message': 'An error occurred. Please try again.'
      };
    }
  }

  // Show error snackbar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.errorRed,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}