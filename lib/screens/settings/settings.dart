import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simple_icons/simple_icons.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';
import '../../service/websocket_manager.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../service/focus_mode_overlay_service.dart'; 
import '../../screens/focus_mode/focus_overlay_manager.dart';
import '../../service/timer_service.dart';
import 'package:workmanager/workmanager.dart';
import '../settings/ip_config.dart';

// ============= PROVIDER CLASS =============
class SettingsProvider extends ChangeNotifier {
  // Change Password Dialog State
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;
  bool _isLoading = false;
  
  // Contact Us State
  bool _showContactUsSheet = false;
  
  // Logout State
  bool _isLoggingOut = false;

  // Getters
  bool get currentPasswordVisible => _currentPasswordVisible;
  bool get newPasswordVisible => _newPasswordVisible;
  bool get confirmPasswordVisible => _confirmPasswordVisible;
  bool get isLoading => _isLoading;
  bool get showContactUsSheet => _showContactUsSheet;
  bool get isLoggingOut => _isLoggingOut;

  // Change Password Visibility Methods
  void toggleCurrentPasswordVisibility() {
    _currentPasswordVisible = !_currentPasswordVisible;
    notifyListeners();
  }

  void toggleNewPasswordVisibility() {
    _newPasswordVisible = !_newPasswordVisible;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _confirmPasswordVisible = !_confirmPasswordVisible;
    notifyListeners();
  }

  // Loading State Methods
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setLoggingOut(bool loggingOut) {
    _isLoggingOut = loggingOut;
    notifyListeners();
  }

  // Contact Us Sheet Methods
  void showContactUs() {
    _showContactUsSheet = true;
    notifyListeners();
  }

  void hideContactUs() {
    _showContactUsSheet = false;
    notifyListeners();
  }

  // Reset all states
  void resetAllStates() {
    _currentPasswordVisible = false;
    _newPasswordVisible = false;
    _confirmPasswordVisible = false;
    _isLoading = false;
    _showContactUsSheet = false;
    _isLoggingOut = false;
    notifyListeners();
  }
}

// ============= SCREEN CLASS =============
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  late SettingsProvider _settingsProvider;

  // Create HTTP client with custom certificate handling
  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  @override
  void initState() {
    super.initState();
    _settingsProvider = SettingsProvider();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _settingsProvider,
      child: Scaffold(
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
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IpConfigPage(),
                    ),
                  );
                },
                tooltip: 'IP Configuration',
              ),
            ],
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
                  
                  const SizedBox(height: 32),
                  
                  // Logout Button Section - Reduced Size
                  Consumer<SettingsProvider>(
                    builder: (context, settingsProvider, child) {
                      return Center(
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.5,
                          child: ElevatedButton.icon(
                            onPressed: settingsProvider.isLoggingOut ? null : () => _showLogoutDialog(settingsProvider),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: settingsProvider.isLoggingOut
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Logout',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
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
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return ChangeNotifierProvider(
          create: (context) => SettingsProvider(),
          child: Consumer<SettingsProvider>(
            builder: (context, settingsProvider, child) {
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
                        obscureText: !settingsProvider.currentPasswordVisible,
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
                              settingsProvider.currentPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: settingsProvider.toggleCurrentPasswordVisibility,
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
                        obscureText: !settingsProvider.newPasswordVisible,
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
                              settingsProvider.newPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: settingsProvider.toggleNewPasswordVisibility,
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
                        obscureText: !settingsProvider.confirmPasswordVisible,
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
                              settingsProvider.confirmPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: settingsProvider.toggleConfirmPasswordVisibility,
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
                    onPressed: settingsProvider.isLoading
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
                    onPressed: settingsProvider.isLoading
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
                            
                            settingsProvider.setLoading(true);
                            
                            final result = await _changePassword(
                              currentPasswordController.text,
                              newPasswordController.text,
                            );
                            
                            settingsProvider.setLoading(false);
                            
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
                    child: settingsProvider.isLoading
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
          ),
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

      final client = _createHttpClientWithCustomCert();
      
      try {
        final body = jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        });

        debugPrint('Change Password Request Body: $body');

        final response = await client.put(
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

  // ============== LOGOUT FUNCTIONALITY ==============
  
  // Show Logout Dialog
  void _showLogoutDialog(SettingsProvider settingsProvider) {
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
                Icons.logout_rounded,
                color: Colors.red,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Confirm Logout',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to logout? This will stop the active focus mode timer.',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textDark,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout(settingsProvider);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearTimetableCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Clear all timetable-related keys
    await prefs.remove('timetable_data');
    await prefs.remove('timetable_last_fetch_date');
    await prefs.remove('timetable_cache');
    
    debugPrint('✅ Timetable cache cleared');
  } catch (e) {
    debugPrint('❌ Error clearing timetable cache: $e');
  }
}

Future<void> _performLogout(SettingsProvider settingsProvider) async {
  String? accessToken;
  
  try {
    settingsProvider.setLoggingOut(true);
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Logging out...'),
            ],
          ),
        );
      },
    );

    // 🔴 STEP 1: Shutdown TimerService completely
    debugPrint('🔴 STEP 1: Shutting down TimerService...');
    try {
      final timerService = TimerService();
      await timerService.shutdownForLogout();
      debugPrint('✅ TimerService shutdown complete');
    } catch (e) {
      debugPrint('❌ Error shutting down TimerService: $e');
    }
    
    await Future.delayed(const Duration(seconds: 1));
    
    // 🔴 STEP 2: Cancel ALL background tasks
    debugPrint('🔴 STEP 2: Cancelling background tasks...');
    try {
      await Workmanager().cancelAll();
      debugPrint('✅ Background tasks cancelled');
    } catch (e) {
      debugPrint('❌ Error cancelling background tasks: $e');
    }
    
    // 🔴 STEP 3: Hide all overlays
    debugPrint('🔴 STEP 3: Hiding all overlays...');
    await _hideAllOverlaysWithRetries();
    
    // 🔴 STEP 4: Disconnect WebSocket
    debugPrint('🔴 STEP 4: Disconnecting WebSocket...');
    try {
      _sendFocusEndEvent();
      await Future.delayed(const Duration(milliseconds: 300));
      
      final disconnectFuture = WebSocketManager.forceDisconnect();
      final timeoutFuture = Future.delayed(const Duration(seconds: 3));
      await Future.any([disconnectFuture, timeoutFuture]);
      
      debugPrint('✅ WebSocket disconnected');
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('⚠️ Error during WebSocket disconnect: $e');
    }
    
    // 🔴 STEP 5: Get access token and send attendance
    debugPrint('🔴 STEP 5: Sending attendance...');
    accessToken = await _authService.getAccessToken();
    String endTime = DateTime.now().toIso8601String();
    await _sendAttendanceData(accessToken, endTime);
    
    // 🔴 STEP 6: Perform logout API call
    debugPrint('🔴 STEP 6: Calling logout API...');
    final client = _createHttpClientWithCustomCert();
    
    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/students/student_logout/'),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('Logout response status: ${response.statusCode}');
      debugPrint('Logout response body: ${response.body}');
    } finally {
      client.close();
    }
    
    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog
    }
    
    // 🔴 STEP 7: Clear SharedPreferences (including allowed apps)
    debugPrint('🔴 STEP 7: Clearing SharedPreferences...');
    await _clearSharedPreferences();
    
    // 🔴 STEP 8: Final cleanup and clear other data
    debugPrint('🔴 STEP 8: Final cleanup...');
    await _clearOverlayFlags();
    
    // Clear timetable cache explicitly
    await _clearTimetableCache();
    
    await _clearLogoutData();
    
    // 🔴 STEP 9: One more overlay hide after everything
    await Future.delayed(const Duration(milliseconds: 500));
    await _hideAllOverlaysWithRetries();
    
  } catch (e) {
    debugPrint('❌ Logout error: $e');
    
    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog
    }
    
    // Ensure cleanup on error
    try {
      await Workmanager().cancelAll();
      await WebSocketManager.forceDisconnect();
      await _hideAllOverlaysWithRetries();
      await _clearOverlayFlags();
      await _clearTimetableCache();
      await _clearSharedPreferences(); // Also clear on error
    } catch (_) {}
    
    await _clearLogoutData();
    
  } finally {
    settingsProvider.setLoggingOut(false);
    
    // Final safety cleanup
    try {
      await Workmanager().cancelAll();
      await WebSocketManager.forceDisconnect();
      await _hideAllOverlaysWithRetries();
      await _clearOverlayFlags();
      await _clearTimetableCache();
      await _clearSharedPreferences(); // Also clear in finally block
    } catch (_) {}
  }
}

// NEW: Method to clear SharedPreferences data
Future<void> _clearSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Keys from AllowAppsScreen
    await prefs.remove('allowed_apps_list');
    await prefs.remove('allowed_apps_details');
    
    // Other session-related keys that should be cleared
    final sessionKeys = [
      'accessToken', // or 'access_token' based on your storage key
      'refresh_token',
      'user_id',
      'user_data',
      'student_id',
      'last_login',
      'session_expiry',
      'auth_token',
      'user_email',
      'user_name',
      // Add any other user-specific keys
    ];
    
    for (final key in sessionKeys) {
      await prefs.remove(key);
    }
    
    debugPrint('✅ SharedPreferences cleared (including allowed apps)');
  } catch (e) {
    debugPrint('❌ Error clearing SharedPreferences: $e');
  }
}

// Optional: If you want to clear ALL SharedPreferences (including settings)
Future<void> _clearAllSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    debugPrint('✅ All SharedPreferences cleared completely');
  } catch (e) {
    debugPrint('❌ Error clearing all SharedPreferences: $e');
  }
}

Future<void> _hideAllOverlaysWithRetries() async {
  debugPrint('🎯 Hiding all overlays with retries...');
  
  for (int attempt = 1; attempt <= 3; attempt++) {
    try {
      debugPrint('🔄 Overlay hide attempt $attempt/3');
      
      // Method 1: FocusModeOverlayService
      try {
        final focusModeService = FocusModeOverlayService();
        await focusModeService.hideOverlay();
        debugPrint('✅ FocusModeOverlayService: Hidden');
      } catch (e) {
        debugPrint('⚠️ FocusModeOverlayService error: $e');
      }
      
      // Method 2: FocusOverlayManager
      try {
        final overlayManager = FocusOverlayManager();
        await overlayManager.initialize();
        await overlayManager.hideOverlay();
        debugPrint('✅ FocusOverlayManager: Hidden');
      } catch (e) {
        debugPrint('⚠️ FocusOverlayManager error: $e');
      }
      
      // Method 3: Direct method channel (MOST IMPORTANT)
      try {
        const platform = MethodChannel('focus_mode_overlay_channel');
        await platform.invokeMethod('hideOverlay');
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Try force hide if available
        try {
          await platform.invokeMethod('forceHideOverlay');
        } catch (_) {}
        
        debugPrint('✅ Direct method channel: Hidden');
      } catch (e) {
        debugPrint('⚠️ Direct method channel error: $e');
      }
      
      // Wait between attempts
      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
      
    } catch (e) {
      debugPrint('⚠️ Attempt $attempt error: $e');
    }
  }
  
  debugPrint('✅ All overlay hide attempts completed');
}
  // Hide all overlays comprehensively
  Future<void> _hideAllOverlaysCompletely() async {
    try {
      debugPrint('🎯 Hiding all overlays completely...');
      
      // Method 1: Try FocusModeOverlayService
      try {
        final focusModeService = FocusModeOverlayService();
        if (focusModeService.isOverlayVisible) {
          await focusModeService.hideOverlay();
          debugPrint('✅ FocusModeOverlayService: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusModeOverlayService: $e');
      }
      
      // Method 2: Try FocusOverlayManager
      try {
        final overlayManager = FocusOverlayManager();
        await overlayManager.initialize();
        if (overlayManager.isOverlayVisible) {
          await overlayManager.hideOverlay();
          debugPrint('✅ FocusOverlayManager: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusOverlayManager: $e');
      }
      
      // Method 3: Direct method channel calls
      try {
        const platform = MethodChannel('focus_mode_overlay_channel');
        
        // Try regular hide
        await platform.invokeMethod('hideOverlay');
        debugPrint('✅ Direct method channel: hideOverlay called');
        
        // Try force hide if available
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          await platform.invokeMethod('forceHideOverlay');
          debugPrint('✅ Direct method channel: forceHideOverlay called');
        } on PlatformException catch (e) {
          debugPrint('⚠️ forceHideOverlay not available: ${e.message}');
        }
      } on PlatformException catch (e) {
        debugPrint('⚠️ Direct method channel failed: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ Direct method channel error: $e');
      }
      
      // Wait to ensure overlays are hidden
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Clear SharedPreferences flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_focus_mode', false);
      await prefs.setBool('overlay_visible', false);
      
      debugPrint('✅ All overlays hidden completely');
      
    } catch (e) {
      debugPrint('❌ Error hiding all overlays completely: $e');
    }
  }

  // Clear overlay flags in SharedPreferences
  Future<void> _clearOverlayFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear all focus mode and overlay related flags
      await prefs.setBool('is_focus_mode', false);
      await prefs.remove('focus_mode_start_time');
      await prefs.remove('focus_time_today');
      await prefs.remove('focus_elapsed_time');
      await prefs.remove('overlay_visible');
      await prefs.remove('overlay_permission_granted');
      
      debugPrint('✅ Overlay flags cleared from SharedPreferences');
    } catch (e) {
      debugPrint('❌ Error clearing overlay flags: $e');
    }
  }

  // Stop focus mode for logout
  Future<void> _stopFocusModeForLogout() async {
    try {
      // Check if focus mode is active
      final prefs = await SharedPreferences.getInstance();
      final bool isFocusModeActive = prefs.getBool('is_focus_mode') ?? false;
      
      if (!isFocusModeActive) {
        debugPrint('⏱️ Focus mode not active, skipping stop');
        return;
      }
      
      debugPrint('⏱️ Stopping focus mode for logout...');
      
      // 1. Send WebSocket focus_end event
      _sendFocusEndEvent();
      
      // 2. Clear focus mode flags in SharedPreferences
      await prefs.setBool('is_focus_mode', false);
      await prefs.remove('focus_mode_start_time');
      
      // 3. Clear today's focus time if needed
      await prefs.remove('focus_time_today');
      
      // 4. Also clear TimerService specific keys
      await prefs.remove(TimerService.focusStartTimeKey);
      await prefs.remove(TimerService.focusElapsedKey);
      await prefs.setBool(TimerService.isFocusModeKey, false);
      
      debugPrint('✅ Focus mode stopped successfully for logout');
      
    } catch (e) {
      debugPrint('❌ Error stopping focus mode for logout: $e');
    }
  }

  // Send focus end event
  void _sendFocusEndEvent() {
    try {
      // Always try to send the event directly
      WebSocketManager.send({"event": "focus_end"});
      debugPrint('📤 WebSocket event sent from settings: {"event": "focus_end"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_end event from settings: $e');
      
      // Try to reconnect WebSocket if sending failed
      try {
        WebSocketManager.connect();
        debugPrint('🔄 Attempting to reconnect WebSocket from settings...');
        
        // Try sending again after a short delay
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            WebSocketManager.send({"event": "focus_end"});
            debugPrint('📤 Retry: WebSocket event sent from settings: {"event": "focus_end"}');
          } catch (retryError) {
            debugPrint('❌ Retry failed from settings: $retryError');
          }
        });
      } catch (connectError) {
        debugPrint('❌ WebSocket reconnection failed from settings: $connectError');
      }
    }
  }

  // HIDE FOCUS MODE OVERLAY (legacy method, kept for compatibility)
  Future<void> _hideFocusModeOverlay() async {
    try {
      debugPrint('🎯 Hiding focus mode overlay...');
      
      // Try both overlay services to ensure overlay is hidden
      try {
        // Using FocusModeOverlayService
        final focusModeService = FocusModeOverlayService();
        if (focusModeService.isOverlayVisible) {
          await focusModeService.hideOverlay();
          debugPrint('✅ FocusModeOverlayService: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusModeOverlayService: $e');
      }
      
      try {
        // Using FocusOverlayManager
        final overlayManager = FocusOverlayManager();
        if (overlayManager.isOverlayVisible) {
          await overlayManager.hideOverlay();
          debugPrint('✅ FocusOverlayManager: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusOverlayManager: $e');
      }
      
      // Also try direct method channel call as fallback
      try {
        const platform = MethodChannel('focus_mode_overlay_channel');
        await platform.invokeMethod('hideOverlay');
        debugPrint('✅ Direct method channel: hideOverlay called');
      } catch (e) {
        debugPrint('⚠️ Direct method channel failed: $e');
      }
      
      debugPrint('✅ Focus mode overlay hidden successfully');
      
    } catch (e) {
      debugPrint('❌ Error hiding focus mode overlay: $e');
    }
  }

  // Send Attendance Data
  Future<void> _sendAttendanceData(String? accessToken, String endTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check student type dynamically
      final studentType = prefs.getString('profile_student_type') ?? '';
      final bool isOnlineStudent = studentType.toUpperCase() == 'ONLINE';
      
      if (!isOnlineStudent) {
        debugPrint('🎯 Skipping attendance data for non-online student during logout');
        return;
      }
      
      String? startTime = prefs.getString('start_time');

      if (startTime != null && accessToken != null && accessToken.isNotEmpty) {
        debugPrint('📤 Preparing API request with timestamps:');
        debugPrint('Start: $startTime, End: $endTime');

        String cleanStart = startTime.split('.')[0].replaceFirst('T', ' ');
        String cleanEnd = endTime.split('.')[0].replaceFirst('T', ' ');

        final body = {
          "records": [
            {"time_stamp": cleanStart, "is_checkin": 1},
            {"time_stamp": cleanEnd, "is_checkin": 0}
          ]
        };

        debugPrint('📦 API request payload: ${jsonEncode(body)}');

        try {
          final response = await http.post(
            Uri.parse(ApiConfig.buildUrl('/api/performance/add_onlineattendance/')),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          ).timeout(const Duration(seconds: 10));

          debugPrint('🌐 API response status: ${response.statusCode}');
          debugPrint('🌐 API response body: ${response.body}');

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('✅ Attendance sent successfully');
          } else {
            debugPrint('⚠️ Error sending attendance: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('❌ Exception while sending attendance: $e');
        }
      } else {
        debugPrint('⚠️ Missing data: startTime=$startTime, accessToken=$accessToken');
      }
    } catch (e) {
      debugPrint('❌ Error in _sendAttendanceData: $e');
    }
  }

  Future<void> _clearLogoutData() async {
  try {
    // Log WebSocket state before clearing
    WebSocketManager.logConnectionState();
    
    await _authService.logout();
    await _clearCachedProfileData(); // This now includes timetable cache
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('start_time');
    await prefs.remove('end_time');
    await prefs.remove('last_active_time');
    
    // Clear focus mode related data
    await prefs.remove('is_focus_mode');
    await prefs.remove('focus_mode_start_time');
    await prefs.remove('focus_time_today');
    await prefs.remove(TimerService.focusStartTimeKey);
    await prefs.remove(TimerService.focusElapsedKey);
    await prefs.remove(TimerService.focusKey);
    await prefs.remove(TimerService.lastStoredFocusTimeKey);
    await prefs.remove(TimerService.lastDateKey);
    await prefs.setBool(TimerService.isFocusModeKey, false);
    
    debugPrint('🗑️ All SharedPreferences data cleared (including timetable)');
    
    // Log WebSocket state after clearing
    WebSocketManager.logConnectionState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  } catch (e) {
    debugPrint('❌ Error in _clearLogoutData: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout completed (Error: ${e.toString()})'),
          backgroundColor: Colors.red,
        ),
      );
      
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }
}
Future<void> _clearCachedProfileData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // List of profile-related keys to clear
    final profileKeys = [
      'profile_name',
      'profile_email',
      'profile_phone',
      'profile_course',
      'profile_subcourse',
      'profile_subcourse_id', 
      'profile_enrollment_status',
      'profile_subscription_type',
      'profile_subscription_end_date',
      'profile_is_subscription_active',
      'profile_student_type',
      'profile_current_streak',
      'profile_longest_streak',
      'profile_completed',
      'profile_cache_time',
      'fcm_token',
      'device_token_registered',
      'subjects_data',
      'cached_subcourse_id',
      'first_login_subjects_fetched',
      'subjects_count',
      'unread_notifications',
      'device_registered_for_session',
      'timetable_data',
      'timetable_last_fetch_date',
      'timetable_cache',
    ];
    
    for (String key in profileKeys) {
      await prefs.remove(key);
      debugPrint('🗑️ Cleared: $key');
    }
    
    debugPrint('✅ All cached profile and timetable data cleared');
  } catch (e) {
    debugPrint('❌ Error clearing cached profile data: $e');
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