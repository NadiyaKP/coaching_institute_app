import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import '../service/api_config.dart';
import '../common/theme_color.dart';

// ============= PROVIDER CLASS =============
class AccountCreationProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get isLoading => _isLoading;
  bool get agreedToTerms => _agreedToTerms;
  bool get obscurePassword => _obscurePassword;
  bool get obscureConfirmPassword => _obscureConfirmPassword;

  void toggleTermsAgreement() {
    _agreedToTerms = !_agreedToTerms;
    notifyListeners();
  }

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  void toggleConfirmPasswordVisibility() {
    _obscureConfirmPassword = !_obscureConfirmPassword;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> registerStudent({
    required String name,
    required String mobile,
    required String email,
    required String password,
    required String countryCode,
  }) async {
    if (!_agreedToTerms) {
      return {'error': 'Please agree to the Terms and Conditions'};
    }

    _isLoading = true;
    notifyListeners();

    try {
      String trimmedName = name.trim();
      String trimmedMobile = mobile.trim();
      String trimmedEmail = email.trim();
      String trimmedPassword = password;
      String fullPhoneNumber = '$countryCode $trimmedMobile';

      if (trimmedName.isEmpty) {
        throw Exception('Name is required');
      }
      if (trimmedMobile.isEmpty) {
        throw Exception('Mobile number is required');
      }
      if (trimmedEmail.isEmpty) {
        throw Exception('Email is required');
      }
      if (trimmedPassword.isEmpty) {
        throw Exception('Password is required');
      }

      final requestData = {
        "phone_number": fullPhoneNumber,
        "email": trimmedEmail,
        "name": trimmedName,
        "password": trimmedPassword,
      };

      debugPrint('=== API REQUEST DEBUG ===');
      debugPrint('URL: ${ApiConfig.buildUrl('/api/students/register_student/')}');
      debugPrint('Request Data: ${json.encode(requestData)}');

      final httpClient = ApiConfig.createHttpClient();
      final ioClient = IOClient(httpClient);

      try {
        final response = await ioClient
            .post(
              Uri.parse(ApiConfig.buildUrl('/api/students/register_student/')),
              headers: ApiConfig.commonHeaders,
              body: json.encode(requestData),
            )
            .timeout(ApiConfig.requestTimeout);

        ioClient.close();

        debugPrint('=== API RESPONSE DEBUG ===');
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Response Body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);

          debugPrint('Parsed Response Data: $responseData');

          if (responseData['success'] == true) {
            debugPrint('Registration successful');
            debugPrint('OTP: ${responseData['otp']}');

            return {
              'success': true,
              'message': responseData['message'] ?? 'OTP sent successfully',
              'phone_number': responseData['phone_number'] ?? fullPhoneNumber,
              'email': trimmedEmail,
              'otp': responseData['otp'],
              'name': trimmedName,
              'password': trimmedPassword,
            };
          } else {
            return {
              'success': false,
              'message': responseData['message'] ?? 'Registration failed',
            };
          }
        } else {
          debugPrint('HTTP Error: ${response.statusCode}');

          String errorMessage = 'Failed to register';
          try {
            final errorData = json.decode(response.body);
            errorMessage = errorData['message'] ?? errorMessage;
          } catch (e) {
            debugPrint('Failed to parse error response: $e');
          }

          return {
            'success': false,
            'message': 'Error: ${response.statusCode} - $errorMessage',
          };
        }
      } finally {
        try {
          httpClient.close(force: true);
        } catch (e) {
          debugPrint('Error closing HTTP client: $e');
        }
      }
    } catch (e) {
      debugPrint('Error Message: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

// ============= SCREEN CLASS =============
class AccountCreationScreen extends StatefulWidget {
  const AccountCreationScreen({super.key});

  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

class _AccountCreationScreenState extends State<AccountCreationScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  String countryCode = '+91';

  @override
  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerStudent(BuildContext context) async {
    debugPrint('=== REGISTRATION STARTED ===');
    final provider = Provider.of<AccountCreationProvider>(context, listen: false);

    if (!provider.agreedToTerms) {
      debugPrint('Terms not agreed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please agree to the Terms and Conditions'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
      return;
    }

    debugPrint('Form validation check');
    if (formKey.currentState?.validate() ?? false) {
      debugPrint('Form validated, calling API');
      final result = await provider.registerStudent(
        name: nameController.text,
        mobile: mobileController.text,
        email: emailController.text,
        password: passwordController.text,
        countryCode: countryCode,
      );

      debugPrint('API Result: $result');

      if (result != null && result['success'] == true) {
        debugPrint('Registration successful, showing snackbar');
        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'OTP sent successfully'),
              backgroundColor: AppColors.successGreen,
              duration: const Duration(seconds: 2),
            ),
          );

          debugPrint('Navigating to OTP verification');
          // Navigate immediately
          Navigator.pushNamed(
            context,
            '/otp_verification',
            arguments: {
              'phone_number': result['phone_number'],
              'email': result['email'],
              'otp': result['otp'],
              'name': result['name'],
              'is_login': false,
              'password': result['password'],
            },
          );
          debugPrint('Navigation called');
        }
      } else {
        debugPrint('Registration failed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['message'] ?? 'Registration failed'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
      }
    } else {
      debugPrint('Form validation failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return ChangeNotifierProvider(
      create: (_) => AccountCreationProvider(),
      child: Builder(
        builder: (context) => Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.textDark, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
            child: Column(
              children: [
                SizedBox(height: screenHeight * 0.015),

                // Header section
                Text(
                  'Create Your Account',
                  style: TextStyle(
                    fontSize: screenWidth * 0.072,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),

                SizedBox(height: screenHeight * 0.03),

                // Main form container
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowGrey,
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: AppColors.shadowGrey.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Form(
                    key: formKey,
                    child: Consumer<AccountCreationProvider>(
                      builder: (context, provider, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Full Name Field
                            _buildFieldLabel('Full Name', screenWidth),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: nameController,
                              hintText: 'Enter your full name',
                              icon: Icons.person_outline,
                              validator: (value) {
                                if (value?.trim().isEmpty ?? true) {
                                  return 'Please enter your full name';
                                }
                                if (value!.trim().length < 2) {
                                  return 'Name must be at least 2 characters long';
                                }
                                return null;
                              },
                              textCapitalization: TextCapitalization.words,
                              screenWidth: screenWidth,
                              isLoading: provider.isLoading,
                            ),

                            SizedBox(height: screenHeight * 0.02),

                            // Mobile Number Field
                            _buildFieldLabel('Mobile Number', screenWidth),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: mobileController,
                              hintText: 'Enter your mobile number',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value?.trim().isEmpty ?? true) {
                                  return 'Please enter your mobile number';
                                }
                                if (value!.trim().length < 10) {
                                  return 'Please enter a valid mobile number';
                                }
                                return null;
                              },
                              screenWidth: screenWidth,
                              isLoading: provider.isLoading,
                            ),

                            SizedBox(height: screenHeight * 0.02),

                            // Email Field
                            _buildFieldLabel('Email Address', screenWidth),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: emailController,
                              hintText: 'Enter your email address',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value?.trim().isEmpty ?? true) {
                                  return 'Please enter your email address';
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                    .hasMatch(value!.trim())) {
                                  return 'Please enter a valid email address';
                                }
                                return null;
                              },
                              screenWidth: screenWidth,
                              isLoading: provider.isLoading,
                            ),

                            SizedBox(height: screenHeight * 0.02),

                            // Password Field
                            _buildFieldLabel('Password', screenWidth),
                            const SizedBox(height: 6),
                            _buildPasswordField(
                              controller: passwordController,
                              hintText: 'Enter your password',
                              obscureText: provider.obscurePassword,
                              onToggleVisibility: provider.togglePasswordVisibility,
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return 'Please enter a password';
                                }
                                if (value!.length < 4) {
                                  return 'Password must be at least 4 characters';
                                }
                                return null;
                              },
                              screenWidth: screenWidth,
                              isLoading: provider.isLoading,
                            ),

                            SizedBox(height: screenHeight * 0.02),

                            // Confirm Password Field
                            _buildFieldLabel('Confirm Password', screenWidth),
                            const SizedBox(height: 6),
                            _buildPasswordField(
                              controller: confirmPasswordController,
                              hintText: 'Confirm your password',
                              obscureText: provider.obscureConfirmPassword,
                              onToggleVisibility: provider.toggleConfirmPasswordVisibility,
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return 'Please confirm your password';
                                }
                                if (value != passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                              screenWidth: screenWidth,
                              isLoading: provider.isLoading,
                            ),

                            SizedBox(height: screenHeight * 0.025),

                            // Terms and Conditions
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Transform.scale(
                                  scale: 0.85,
                                  child: Checkbox(
                                    value: provider.agreedToTerms,
                                    onChanged: provider.isLoading
                                        ? null
                                        : (value) {
                                            provider.toggleTermsAgreement();
                                          },
                                    activeColor: AppColors.primaryYellow,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: provider.isLoading
                                        ? null
                                        : () {
                                            provider.toggleTermsAgreement();
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.03,
                                            color: AppColors.textGrey,
                                            height: 1.4,
                                          ),
                                          children: const [
                                            TextSpan(text: 'I agree to the '),
                                            TextSpan(
                                              text: 'Terms and Conditions',
                                              style: TextStyle(
                                                color: AppColors.primaryYellow,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(text: ' and '),
                                            TextSpan(
                                              text: 'Privacy Policy',
                                              style: TextStyle(
                                                color: AppColors.primaryYellow,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: screenHeight * 0.03),

                            // Continue Button
                            Container(
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: AppGradients.primaryYellow,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.shadowYellow,
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: provider.isLoading ? null : () => _registerStudent(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  disabledBackgroundColor: AppColors.grey300,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: provider.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: AppColors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontSize: screenWidth * 0.038,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.025),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, double screenWidth) {
    return Text(
      label,
      style: TextStyle(
        fontSize: screenWidth * 0.032,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required String? Function(String?) validator,
    required double screenWidth,
    required bool isLoading,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !isLoading,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: TextStyle(
        fontSize: screenWidth * 0.035,
        fontWeight: FontWeight.w500,
        color: AppColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: AppColors.grey400,
          fontSize: screenWidth * 0.033,
        ),
        prefixIcon: Icon(
          icon,
          color: AppColors.grey500,
          size: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryYellow,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
        ),
        filled: true,
        fillColor: isLoading ? AppColors.grey100 : AppColors.grey50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        errorStyle: TextStyle(
          fontSize: screenWidth * 0.028,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    required double screenWidth,
    required bool isLoading,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !isLoading,
      obscureText: obscureText,
      style: TextStyle(
        fontSize: screenWidth * 0.035,
        fontWeight: FontWeight.w500,
        color: AppColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: AppColors.grey400,
          fontSize: screenWidth * 0.033,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: AppColors.grey500,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.grey500,
            size: 20,
          ),
          onPressed: onToggleVisibility,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.grey300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryYellow,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
        ),
        filled: true,
        fillColor: isLoading ? AppColors.grey100 : AppColors.grey50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        errorStyle: TextStyle(
          fontSize: screenWidth * 0.028,
        ),
      ),
      validator: validator,
    );
  }
}