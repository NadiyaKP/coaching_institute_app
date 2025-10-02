import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import '../service/api_config.dart';

class AccountCreationScreen extends StatefulWidget {
  const AccountCreationScreen({super.key});

  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

class _AccountCreationScreenState extends State<AccountCreationScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool agreedToTerms = false;
  
  // Variables to store phone data
  String phoneNumber = '';
  String countryCode = '+91';
  String mobileNumber = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Extract arguments passed from SignupScreen
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    
    if (args != null) {
      phoneNumber = args['phone_number'] ?? '';
      countryCode = args['country_code'] ?? '+91';
      mobileNumber = args['mobile_number'] ?? '';
      
      debugPrint('AccountCreation - Received phone_number: $phoneNumber');
      debugPrint('AccountCreation - Received country_code: $countryCode');
      debugPrint('AccountCreation - Received mobile_number: $mobileNumber');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    super.dispose();
  }

  String getDisplayPhoneNumber() {
    if (phoneNumber.startsWith(countryCode)) {
      return phoneNumber;
    }
    else if (mobileNumber.isNotEmpty) {
      return '$countryCode $mobileNumber';
    }
    else {
      return '$countryCode $phoneNumber';
    }
  }

  String getApiPhoneNumber() {
    String cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    String cleanCountryCode = countryCode.replaceAll(RegExp(r'\s+'), '');
    String cleanMobileNumber = mobileNumber.replaceAll(RegExp(r'\s+'), '');
    
    String formattedPhone;
    
    if (cleanPhoneNumber.startsWith(cleanCountryCode)) {
      formattedPhone = '$cleanCountryCode ${cleanPhoneNumber.substring(cleanCountryCode.length)}';
    }
    else if (cleanMobileNumber.isNotEmpty) {
      formattedPhone = '$cleanCountryCode $cleanMobileNumber';
    }
    else if (cleanPhoneNumber.isNotEmpty) {
      formattedPhone = '$cleanCountryCode $cleanPhoneNumber';
    }
    else {
      formattedPhone = '$cleanCountryCode $cleanPhoneNumber';
    }
    
    return formattedPhone;
  }

  Future<void> _registerStudent() async {
    if (!agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Terms and Conditions'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (formKey.currentState?.validate() ?? false) {
      setState(() {
        isLoading = true;
      });

      try {
        String fullPhoneNumber = getApiPhoneNumber();
        String trimmedName = nameController.text.trim();
        String trimmedEmail = emailController.text.trim();
        
        if (trimmedName.isEmpty) {
          throw Exception('Name is required');
        }
        if (trimmedEmail.isEmpty) {
          throw Exception('Email is required');
        }
        if (fullPhoneNumber.isEmpty || fullPhoneNumber == countryCode || fullPhoneNumber == '$countryCode ') {
          throw Exception('Phone number is required');
        }
        
        final requestData = {
          "phone_number": fullPhoneNumber,
          "email": trimmedEmail,
          "name": trimmedName,
        };

        debugPrint('=== API REQUEST DEBUG ===');
        debugPrint('URL: ${ApiConfig.buildUrl('/api/students/register_student/')}');
        debugPrint('Request Data: ${json.encode(requestData)}');

        final httpClient = ApiConfig.createHttpClient();
        final ioClient = IOClient(httpClient);
        
        try {
          final response = await ioClient.post(
            Uri.parse(ApiConfig.buildUrl('/api/students/register_student/')),
            headers: ApiConfig.commonHeaders,
            body: json.encode(requestData),
          ).timeout(ApiConfig.requestTimeout);
          
          ioClient.close();

          debugPrint('=== API RESPONSE DEBUG ===');
          debugPrint('Status Code: ${response.statusCode}');
          debugPrint('Response Body: ${response.body}');

          if (response.statusCode == 200 || response.statusCode == 201) {
            final responseData = json.decode(response.body);
            
            debugPrint('Parsed Response Data: $responseData');
            
            if (responseData['success'] == true) {
              debugPrint('Registration successful, navigating to OTP verification');
              
              if (mounted) {
                Navigator.pushNamed(
                  context,
                  '/otp_verification',
                  arguments: {
                    'phone_number': fullPhoneNumber,
                    'country_code': countryCode,
                    'mobile_number': mobileNumber,
                    'name': trimmedName,
                    'email': trimmedEmail,
                    'is_login': false, // This is registration flow
                  },
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(responseData['message'] ?? 'Registration failed'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          } else {
            debugPrint('HTTP Error: ${response.statusCode}');
            
            if (mounted) {
              String errorMessage = 'Failed to register';
              try {
                final errorData = json.decode(response.body);
                errorMessage = errorData['message'] ?? errorMessage;
              } catch (e) {
                debugPrint('Failed to parse error response: $e');
              }
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${response.statusCode} - $errorMessage'),
                  backgroundColor: Colors.red,
                ),
              );
            }
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
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Network error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.02),
              
              // Header section
              Text(
                'Create Your Account',
                style: TextStyle(
                  fontSize: screenWidth * 0.058,
                  fontWeight: FontWeight.w700,
                  color: Color.fromARGB(255, 9, 55, 107),
                ),
              ),
              
              SizedBox(height: screenHeight * 0.015),
              
              // Phone verification badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Mobile number: ${getDisplayPhoneNumber()}',
                      style: TextStyle(
                        fontSize: screenWidth * 0.032,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: screenHeight * 0.04),
              
              // Main form container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Name Field
                      Text(
                        'Full Name',
                        style: TextStyle(
                          fontSize: screenWidth * 0.036,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        enabled: !isLoading,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your full name',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: screenWidth * 0.036,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: Colors.grey[500],
                            size: 22,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFF4B400),
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          filled: true,
                          fillColor: isLoading ? Colors.grey[50] : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        validator: (value) {
                          if (value?.trim().isEmpty ?? true) {
                            return 'Please enter your full name';
                          }
                          if (value!.trim().length < 2) {
                            return 'Name must be at least 2 characters long';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: screenHeight * 0.025),
                      
                      // Email Field
                      Text(
                        'Email Address',
                        style: TextStyle(
                          fontSize: screenWidth * 0.036,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your email address',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: screenWidth * 0.036,
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: Colors.grey[500],
                            size: 22,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFF4B400),
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          filled: true,
                          fillColor: isLoading ? Colors.grey[50] : Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        validator: (value) {
                          if (value?.trim().isEmpty ?? true) {
                            return 'Please enter your email address';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!.trim())) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: screenHeight * 0.03),
                      
                      // Terms and Conditions
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.scale(
                            scale: 0.9,
                            child: Checkbox(
                              value: agreedToTerms,
                              onChanged: isLoading ? null : (value) {
                                setState(() {
                                  agreedToTerms = value ?? false;
                                });
                              },
                              activeColor: const Color(0xFFF4B400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: isLoading ? null : () {
                                setState(() {
                                  agreedToTerms = !agreedToTerms;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.032,
                                      color: Colors.grey[600],
                                      height: 1.4,
                                    ),
                                    children: const [
                                      TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                        text: 'Terms and Conditions',
                                        style: TextStyle(
                                          color: Color(0xFFF4B400),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: TextStyle(
                                          color: Color(0xFFF4B400),
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
                      
                      SizedBox(height: screenHeight * 0.035),
                      
                      // Continue Button
                      Container(
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF4B400), Color(0xFFE6A200)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF4B400).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _registerStudent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.grey[300],
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: screenWidth * 0.042,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: screenHeight * 0.03),
            ],
          ),
        ),
      ),
    );
  }
}