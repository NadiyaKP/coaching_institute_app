import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simple_icons/simple_icons.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';

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
                const Text(
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
                            child: const Icon(
                              Icons.lock_outline,
                              color: AppColors.primaryYellow,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
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
                                SizedBox(height: 4),
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
                          const Icon(
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
                const Text(
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
                          child: const Icon(
                            Icons.notifications_outlined,
                            color: AppColors.primaryYellow,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
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
                              SizedBox(height: 4),
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
                        const Text(
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
                
                const SizedBox(height: 24),
                
                // Information Section
                const Text(
                  'Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textGrey,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // About Us Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/about_us');
                    },
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
                            child: const Icon(
                              Icons.info_outline,
                              color: AppColors.primaryYellow,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'About Us',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Learn more about us',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textGrey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Contact Us Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: _showContactUsBottomSheet,
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
                            child: const Icon(
                              Icons.mail_outline,
                              color: AppColors.primaryYellow,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Contact Us',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Get in touch with our team',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textGrey,
                          ),
                        ],
                      ),
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
              title: const Row(
                children: [
                  Icon(
                    Icons.lock_reset,
                    color: AppColors.primaryYellow,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
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
                        if (currentPasswordController.text.isNotEmpty && 
                            currentPasswordController.text.length < 4) {
                          _showErrorSnackBar('Current password must be at least 4 characters');
                        }
                        newPasswordFocus.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter current password',
                        prefixIcon: const Icon(
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
                          borderSide: const BorderSide(
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
                        if (newPasswordController.text.isNotEmpty && 
                            newPasswordController.text.length < 4) {
                          _showErrorSnackBar('New password must be at least 4 characters');
                        }
                        confirmPasswordFocus.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        hintText: 'Enter new password',
                        prefixIcon: const Icon(
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
                          borderSide: const BorderSide(
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
                        if (confirmPasswordController.text.isNotEmpty && 
                            confirmPasswordController.text.length < 4) {
                          _showErrorSnackBar('Confirm password must be at least 4 characters');
                        }
                        confirmPasswordFocus.unfocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        hintText: 'Re-enter new password',
                        prefixIcon: const Icon(
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
                          borderSide: const BorderSide(
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
                  child: const Text(
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
                          
                          if (currentPasswordController.text == newPasswordController.text) {
                            _showErrorSnackBar('New password must be different from current password');
                            return;
                          }
                          
                          if (newPasswordController.text != confirmPasswordController.text) {
                            _showErrorSnackBar('New password and confirm password do not match');
                            return;
                          }
                          
                          setState(() {
                            isLoading = true;
                          });
                          
                          final result = await _changePassword(
                            currentPasswordController.text,
                            newPasswordController.text,
                          );
                          
                          setState(() {
                            isLoading = false;
                          });
                          
                          if (result['success'] == true) {
                            if (Navigator.of(dialogContext).canPop()) {
                              Navigator.of(dialogContext).pop();
                            }
                            
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

  // Show Contact Us Bottom Sheet
  void _showContactUsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Title
              const Text(
                'Contact Us',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              
              const SizedBox(height: 8),
              
              const Text(
                'Choose how you want to reach us',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textGrey,
                ),
              ),
              
              const SizedBox(height: 28),
              
              // Contact Options Grid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildContactOption(
                    icon: Icons.phone,
                    label: 'Call',
                    color: const Color(0xFF34C759),
                    onTap: _showPhoneNumberSelection,
                    useSimpleIcon: false,
                  ),
                  _buildContactOption(
                    icon: SimpleIcons.instagram,
                    label: 'Instagram',
                    color: const Color(0xFFE4405F),
                    onTap: () => _launchUrl('https://www.instagram.com/signature.institute/'),
                    useSimpleIcon: true,
                  ),
                  _buildContactOption(
                    icon: SimpleIcons.facebook,
                    label: 'Facebook',
                    color: const Color(0xFF1877F2),
                    onTap: () => _launchUrl('https://www.facebook.com/people/Signature-Institute/61574634887436/'),
                    useSimpleIcon: true,
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildContactOption(
                    icon: SimpleIcons.linkedin,
                    label: 'LinkedIn',
                    color: const Color(0xFF0A66C2),
                    onTap: () => _launchUrl('https://www.linkedin.com/company/signature-institute/'),
                    useSimpleIcon: true,
                  ),
                  _buildContactOption(
                    icon: Icons.language,
                    label: 'Website',
                    color: const Color(0xFF4285F4),
                    onTap: () => _launchUrl('https://www.signaturecampus.com/'),
                    useSimpleIcon: false,
                  ),
                  // Empty space for alignment
                  const SizedBox(width: 70),
                ],
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Build Contact Option Widget
  Widget _buildContactOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool useSimpleIcon = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: useSimpleIcon ? 40 : 44,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // Show Phone Number Selection Dialog
  void _showPhoneNumberSelection() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.phone,
                color: Color(0xFF34C759),
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Select Number',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPhoneNumberOption(
                phoneNumber: '+91 90745 70207',
                onTap: () {
                  Navigator.of(context).pop();
                  _makePhoneCall('+919074570207');
                },
              ),
              const SizedBox(height: 12),
              _buildPhoneNumberOption(
                phoneNumber: '+91 85920 00085',
                onTap: () {
                  Navigator.of(context).pop();
                  _makePhoneCall('+918592000085');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
          ],
        );
      },
    );
  }

  // Build Phone Number Option Widget
  Widget _buildPhoneNumberOption({
    required String phoneNumber,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF34C759).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF34C759).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone,
                color: Color(0xFF34C759),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              phoneNumber,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  // Make Phone Call
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          _showErrorSnackBar('Could not launch phone dialer');
        }
      }
    } catch (e) {
      debugPrint('Error making phone call: $e');
      if (mounted) {
        _showErrorSnackBar('Error making phone call');
      }
    }
  }

  // Launch URL
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          _showErrorSnackBar('Could not launch $urlString');
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        _showErrorSnackBar('Error opening link');
      }
    }
  }

  // Change Password API call
  Future<Map<String, dynamic>> _changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken');
      
      if (accessToken == null || accessToken.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication failed. Please login again.'
        };
      }

      final client = ApiConfig.createHttpClient();
      
      try {
        final body = jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        });

        debugPrint('Change Password Request Body: $body');

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