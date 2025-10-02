import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'otp_verification_screen.dart';
import 'login_otp_verification.dart';
import 'email_login.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:coaching_institute_app/common/continue_button.dart';


class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with TickerProviderStateMixin {
  final TextEditingController phoneController = TextEditingController();
  String selectedCountryCode = '+91';
  bool isLoading = false;
  AnimationController? _fadeController;
  AnimationController? _slideController;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;
  
  // Validation variables
  String? phoneError;
  bool isPhoneValid = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    phoneController.addListener(_validatePhoneNumber);
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController!, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController!, curve: Curves.easeOutCubic));
    
    _fadeController?.forward();
    _slideController?.forward();
  }

  @override
  void dispose() {
    phoneController.dispose();
    _fadeController?.dispose();
    _slideController?.dispose();
    super.dispose();
  }

  // Helper method to format the complete phone number with dynamic country code
  String getCompletePhoneNumber() {
    String mobileNumber = phoneController.text.trim();
    if (mobileNumber.isEmpty) return '';
    return '$selectedCountryCode $mobileNumber';
  }

  // Phone number validation based on country code
  void _validatePhoneNumber() {
    final phoneNumber = phoneController.text.trim();
    
    if (phoneNumber.isEmpty) {
      setState(() {
        phoneError = null;
        isPhoneValid = false;
      });
      return;
    }
    
    // Check if contains only digits
    if (!RegExp(r'^[0-9]+$').hasMatch(phoneNumber)) {
      setState(() {
        phoneError = 'Phone number must contain only digits';
        isPhoneValid = false;
      });
      return;
    }
    
    // Special validation for India
    if (selectedCountryCode == '+91') {
      if (phoneNumber.length != 10) {
        setState(() {
          phoneError = 'Enter a valid phone number';
          isPhoneValid = false;
        });
        return;
      }
      
      // Additional Indian mobile number validation (starts with 6,7,8,9)
      if (!RegExp(r'^[6-9]').hasMatch(phoneNumber)) {
        setState(() {
          phoneError = 'Enter a valid phone number';
          isPhoneValid = false;
        });
        return;
      }
    } else {
      // General validation for other countries (7-15 digits as per ITU E.164)
      if (phoneNumber.length < 7 || phoneNumber.length > 15) {
        setState(() {
          phoneError = 'Enter a valid phone number';
          isPhoneValid = false;
        });
        return;
      }
    }
    
    // If all validations pass
    setState(() {
      phoneError = null;
      isPhoneValid = true;
    });
  }

  Future<void> checkAccountAvailability() async {
    // Validate phone number before proceeding
    _validatePhoneNumber();
    
    if (!isPhoneValid) {
      if (phoneController.text.trim().isEmpty) {
        _showSnackBar('Please enter a mobile number', AppColors.errorRed);
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    String completePhoneNumber = getCompletePhoneNumber();
    
    debugPrint('Selected country code: $selectedCountryCode');
    debugPrint('Mobile number: ${phoneController.text.trim()}');
    debugPrint('Complete phone number to send: $completePhoneNumber');

    try {
      debugPrint('Making API call with dynamic country code');
      debugPrint('Country Code: $selectedCountryCode');
      debugPrint('Mobile Number: ${phoneController.text.trim()}');
      debugPrint('Complete Phone Number: $completePhoneNumber');
      debugPrint('Using API URL: ${ApiConfig.currentStudentLoginUrl}');
      
      // Create HTTP client using ApiConfig
      final httpClient = ApiConfig.createHttpClient();
      
      final request = await httpClient.postUrl(
        Uri.parse(ApiConfig.currentStudentLoginUrl),
      );
      
      // Set headers using ApiConfig
      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      
      // Set body with complete phone number using 'identifier' as requested
      final body = jsonEncode({
        'identifier': completePhoneNumber,
      });
      request.contentLength = body.length;
      request.write(body);
      
      final httpResponse = await request.close().timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      final responseBody = await httpResponse.transform(utf8.decoder).join();
      
      debugPrint('Response status: ${httpResponse.statusCode}');
      debugPrint('Response body: $responseBody');

      if (httpResponse.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        
        // Check for OTP in API response
        if (responseData.containsKey('otp')) {
          debugPrint('🔐 OTP RECEIVED FROM API: ${responseData['otp']}');
          debugPrint('📱 OTP sent to: $completePhoneNumber');
          debugPrint('⏰ OTP received at: ${DateTime.now().toLocal()}');
        }
        
        // Check for other possible OTP field names
        if (responseData.containsKey('otp_code')) {
          debugPrint('🔐 OTP CODE RECEIVED: ${responseData['otp_code']}');
        }
        if (responseData.containsKey('verification_code')) {
          debugPrint('🔐 VERIFICATION CODE RECEIVED: ${responseData['verification_code']}');
        }
        
        // Handle different result codes based on your API response
        if (responseData['result'] == 1 || responseData['result'] == 2) {
          bool accountAvailable = responseData['account_available'] ?? false;
          
          debugPrint('Result code: ${responseData['result']}');
          debugPrint('Account available: $accountAvailable');
          
          if (accountAvailable) {
            debugPrint('Account exists - navigating to OTP verification');
            debugPrint('API Message: ${responseData['message']}');
            
            // Extract OTP from response
            String? receivedOtp;
            if (responseData.containsKey('otp')) {
              receivedOtp = responseData['otp'].toString();
            } else if (responseData.containsKey('otp_code')) {
              receivedOtp = responseData['otp_code'].toString();
            } else if (responseData.containsKey('verification_code')) {
              receivedOtp = responseData['verification_code'].toString();
            }
            
            _navigateToOtpVerification(otpFromApi: receivedOtp);
          } else {
            debugPrint('New account - navigating to account creation');
            _navigateToAccountCreation();
          }
        } else {
          _showSnackBar('Error: ${responseData['message'] ?? 'Unknown error'}', AppColors.errorRed);
        }
      } else if (httpResponse.statusCode == 404) {
        _showSnackBar('API endpoint not found. Please check the URL.', AppColors.errorRed);
      } else if (httpResponse.statusCode >= 500) {
        _showSnackBar('Server error. Please try again later.', AppColors.errorRed);
      } else {
        _showSnackBar('Server error: ${httpResponse.statusCode} - $responseBody', AppColors.errorRed);
      }
      
      httpClient.close();
      
    } on TimeoutException catch (e) {
      _showSnackBar('Request timeout. Please check your connection.', AppColors.errorRed);
      debugPrint('Timeout Error: $e');
    } on FormatException catch (e) {
      _showSnackBar('Invalid response format from server.', AppColors.errorRed);
      debugPrint('JSON Format Error: $e');
    } on Exception catch (e) {
      String errorMessage = 'Network error: ${e.toString()}';
      if (e.toString().contains('SocketException')) {
        errorMessage = 'No internet connection. Please check your network.';
      } else if (e.toString().contains('HandshakeException')) {
        errorMessage = 'SSL/TLS error. Trying alternative connection...';
        _tryHttpFallback();
        return;
      }
      _showSnackBar(errorMessage, AppColors.errorRed);
      debugPrint('API Error: $e');
    } catch (e) {
      _showSnackBar('Unexpected error: ${e.toString()}', AppColors.errorRed);
      debugPrint('Unexpected Error: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _tryHttpFallback() async {
    try {
      debugPrint('Trying HTTP fallback with dynamic country code...');
      debugPrint('Using fallback API URL: ${ApiConfig.currentStudentLoginUrl}');
      
      String completePhoneNumber = getCompletePhoneNumber();
      debugPrint('HTTP Fallback - Country Code: $selectedCountryCode');
      debugPrint('HTTP Fallback - Mobile Number: ${phoneController.text.trim()}');
      debugPrint('HTTP Fallback - Complete Phone Number: $completePhoneNumber');
      
      final response = await http.post(
        Uri.parse(ApiConfig.currentStudentLoginUrl),
        headers: ApiConfig.commonHeaders,
        body: jsonEncode({
          'identifier': completePhoneNumber,
        }),
      ).timeout(ApiConfig.requestTimeout);

      debugPrint('HTTP Fallback Response status: ${response.statusCode}');
      debugPrint('HTTP Fallback Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        // Check for OTP in HTTP fallback response
        if (responseData.containsKey('otp')) {
          debugPrint('🔐 FALLBACK OTP RECEIVED: ${responseData['otp']}');
          debugPrint('📱 Fallback OTP sent to: $completePhoneNumber');
        }
        
        // Handle different result codes based on your API response
        if (responseData['result'] == 1 || responseData['result'] == 2) {
          bool accountAvailable = responseData['account_available'] ?? false;
          
          debugPrint('HTTP Fallback - Result code: ${responseData['result']}');
          debugPrint('HTTP Fallback - Account available: $accountAvailable');
          
          if (accountAvailable) {
            debugPrint('HTTP Fallback - Account exists - navigating to OTP verification');
            debugPrint('HTTP Fallback - API Message: ${responseData['message']}');
            
            // Extract OTP from fallback response
            String? receivedOtp;
            if (responseData.containsKey('otp')) {
              receivedOtp = responseData['otp'].toString();
            }
            
            _navigateToOtpVerification(otpFromApi: receivedOtp);
          } else {
            debugPrint('HTTP Fallback - New account - navigating to account creation');
            _navigateToAccountCreation();
          }
        } else {
          _showSnackBar('Error: ${responseData['message'] ?? 'Unknown error'}', AppColors.errorRed);
        }
      } else {
        _showSnackBar('Server error: ${response.statusCode}', AppColors.errorRed);
      }
    } catch (e) {
      _showSnackBar('Both HTTPS and HTTP failed. Please check your server.', AppColors.errorRed);
      debugPrint('HTTP Fallback Error: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _navigateToOtpVerification({String? otpFromApi}) {
    debugPrint('Navigating to OTP verification screen...');
    debugPrint('Phone number: ${getCompletePhoneNumber()}');
    debugPrint('Country code: $selectedCountryCode');
    debugPrint('Mobile number: ${phoneController.text.trim()}');
    
    if (otpFromApi != null) {
      debugPrint('🔐🔐🔐 FINAL OTP TO BE USED: $otpFromApi 🔐🔐🔐');
      debugPrint('📋 Copy this OTP for testing: $otpFromApi');
    }
    
    // Show success message
    _showSnackBar('OTP sent! Redirecting to verification...', AppColors.successGreen);
    
    // Add a small delay to let the user see the success message
    Future.delayed(const Duration(milliseconds: 800), () {
      // Try named route first
      try {
        Navigator.pushNamed(
          context, 
          '/login_otp_verification',
          arguments: {
            'phone_number': getCompletePhoneNumber(),
            'country_code': selectedCountryCode,
            'mobile_number': phoneController.text.trim(),
            'otp_from_api': otpFromApi,
          },
        ).then((result) {
          debugPrint('Named route navigation successful: $result');
        }).catchError((error) {
          debugPrint('Named route navigation failed: $error');
          _tryDirectNavigation(otpFromApi: otpFromApi);
        });
      } catch (e) {
        debugPrint('Named route error: $e');
        _tryDirectNavigation(otpFromApi: otpFromApi);
      }
    });
  }

  void _tryDirectNavigation({String? otpFromApi}) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LoginOtpVerificationScreen(),
          settings: RouteSettings(
            arguments: {
              'phone_number': getCompletePhoneNumber(),
              'country_code': selectedCountryCode,
              'mobile_number': phoneController.text.trim(),
              'otp_from_api': otpFromApi,
            },
          ),
        ),
      ).then((result) {
        debugPrint('Direct navigation successful: $result');
      }).catchError((error) {
        debugPrint('Direct navigation also failed: $error');
        _showSnackBar('Unable to navigate to OTP screen. Please restart the app.', AppColors.errorRed);
      });
    } catch (e) {
      debugPrint('Direct navigation error: $e');
      _showSnackBar('Navigation system error. Please restart the app.', AppColors.errorRed);
    }
  }

  void _navigateToAccountCreation() {
    debugPrint('Navigating to account creation screen...');
    debugPrint('Phone number: ${getCompletePhoneNumber()}');
    debugPrint('Country code: $selectedCountryCode');
    debugPrint('Mobile number: ${phoneController.text.trim()}');
    
    // Show info message
    _showSnackBar('New user! Redirecting to account creation...', AppColors.primaryBlue);
    
    // Navigate to account creation page with complete phone number and mobile number
    Navigator.pushNamed(
      context, 
      '/account_creation',
      arguments: {
        'phone_number': getCompletePhoneNumber(),
        'country_code': selectedCountryCode,
        'mobile_number': phoneController.text.trim(),
      },
    ).then((result) {
      debugPrint('Returned from account creation screen: $result');
    }).catchError((error) {
      debugPrint('Navigation error to account creation: $error');
      _showSnackBar('Navigation error. Please try again.', AppColors.errorRed);
    });
  }

  void _navigateToEmailLogin() {
    debugPrint('Navigating to email login screen...');
    
    try {
      // Try named route first
      Navigator.pushNamed(context, '/email_login').then((result) {
        debugPrint('Email login navigation successful: $result');
      }).catchError((error) {
        debugPrint('Named route navigation failed: $error');
        _tryDirectEmailNavigation();
      });
    } catch (e) {
      debugPrint('Named route error: $e');
      _tryDirectEmailNavigation();
    }
  }

  void _tryDirectEmailNavigation() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EmailLoginScreen(),
        ),
      ).then((result) {
        debugPrint('Direct email navigation successful: $result');
      }).catchError((error) {
        debugPrint('Direct email navigation also failed: $error');
        _showSnackBar('Unable to navigate to email login. Please restart the app.', AppColors.errorRed);
      });
    } catch (e) {
      debugPrint('Direct email navigation error: $e');
      _showSnackBar('Email navigation system error. Please restart the app.', AppColors.errorRed);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Widget _buildHeader() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      width: double.infinity,
      height: screenHeight * 0.35,
      decoration: BoxDecoration(
        gradient: AppGradients.background,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(35),
          bottomRight: Radius.circular(35),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowYellow,
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.grey300.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: -25,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.grey400.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 30,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white.withOpacity(0.06),
              ),
            ),
          ),
          
          // Main content - Logo positioned lower in the container
          Positioned(
            left: 0,
            right: 0,
            bottom: screenHeight * 0.08,
            child: _fadeAnimation != null 
              ? FadeTransition(
                  opacity: _fadeAnimation!,
                  child: Image.asset(
                    "assets/images/signature_logo.png",
                    width: screenWidth * 0.20,
                    height: screenWidth * 0.20,
                    fit: BoxFit.contain,
                  ),
                )
              : Image.asset(
                  "assets/images/signature_logo.png",
                  width: screenWidth * 0.20,
                  height: screenWidth * 0.20,
                  fit: BoxFit.contain,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneContainer(double screenWidth) {
  return Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(25),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadowGrey,
          spreadRadius: 0,
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: AppColors.shadowYellow,
          spreadRadius: 0,
          blurRadius: 20,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Enhanced section header with icon
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppGradients.primaryYellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.phone_android,
                color: AppColors.white,
                size: screenWidth * 0.040,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Mobile Number",
              style: TextStyle(
                fontSize: screenWidth * 0.040,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Enhanced phone input with better styling and proper country code visibility
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.grey50,
                AppColors.grey100,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPhoneValid 
                ? AppColors.successGreen.withOpacity(0.6)
                : phoneError != null
                  ? AppColors.errorRed.withOpacity(0.6)
                  : AppColors.grey300,
              width: 1.5,
            ),
            boxShadow: isPhoneValid ? [
              BoxShadow(
                color: AppColors.successGreen.withOpacity(0.1),
                spreadRadius: 0,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : phoneError != null ? [
              BoxShadow(
                color: AppColors.errorRed.withOpacity(0.1),
                spreadRadius: 0,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : [],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Enhanced Country code picker with proper visibility
                  Container(
                    constraints: BoxConstraints(
                      minWidth: screenWidth * 0.28,
                      maxWidth: screenWidth * 0.35,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.7),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                      ),
                    ),
                    child: CountryCodePicker(
                      onChanged: (code) {
                        setState(() {
                          selectedCountryCode = code.dialCode!;
                          _validatePhoneNumber(); // Revalidate when country changes
                        });
                        debugPrint("Country changed to: ${code.name} (${code.dialCode})");
                        debugPrint("New complete number format: ${getCompletePhoneNumber()}");
                      },
                      initialSelection: 'IN',
                      favorite: const ['+91', 'IN'],
                      showCountryOnly: false,
                      showOnlyCountryWhenClosed: false,
                      alignLeft: false,
                      showDropDownButton: true,
                      padding: EdgeInsets.zero,
                      textStyle: TextStyle(
                        fontSize: screenWidth * 0.038,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey800,
                      ),
                      flagWidth: 24,
                      dialogTextStyle: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppColors.grey800,
                      ),
                      searchStyle: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppColors.grey800,
                      ),
                    ),
                  ),
                  
                  // Divider with better visibility
                  Container(
                    width: 1.5,
                    height: 40,
                    color: AppColors.grey300,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  
                  // Expanded Phone number input
                  Expanded(
                    child: TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey800,
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        hintText: "Enter your mobile number",
                        hintStyle: TextStyle(
                          color: AppColors.grey500,
                          fontSize: screenWidth * 0.037,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        suffixIcon: isPhoneValid
                          ? Icon(
                              Icons.check_circle,
                              color: AppColors.successGreen,
                              size: screenWidth * 0.05,
                            )
                          : phoneError != null
                            ? Icon(
                                Icons.error,
                                color: AppColors.errorRed,
                                size: screenWidth * 0.05,
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _validatePhoneNumber();
                        });
                        debugPrint("Mobile number changed: $value");
                        debugPrint("Current complete number: ${getCompletePhoneNumber()}");
                      },
                    ),
                  ),
                ],
              ),
              
              // Error message display
              if (phoneError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.errorRed,
                        size: screenWidth * 0.035,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          phoneError!,
                          style: TextStyle(
                            color: AppColors.errorRed,
                            fontSize: screenWidth * 0.032,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),

        // Continue button using the separate class
        ContinueButton(
          isEnabled: isPhoneValid,
          isLoading: isLoading,
          onPressed: checkAccountAvailability,
          screenWidth: screenWidth,
        ),
      ],
    ),
  );
}

  Widget _buildAlternativeOptions() {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          // Enhanced divider with animated text
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.grey[300]!,
                        Colors.grey[400]!,
                        Colors.grey[300]!,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.grey[50]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.15),
                      spreadRadius: 1,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: Text(
                  "OR",
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: screenWidth * 0.032,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.grey[300]!,
                        Colors.grey[400]!,
                        Colors.grey[300]!,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Enhanced Email login button
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Colors.grey[50]!,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Color.fromARGB(255, 13, 70, 136).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  spreadRadius: 0,
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  spreadRadius: 0,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextButton(
              onPressed: _navigateToEmailLogin,
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color.fromARGB(255, 7, 49, 98).withOpacity(0.1),
                          const Color.fromARGB(255, 7, 49, 98).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.email_outlined,
                      color: Color.fromARGB(255, 7, 49, 98),
                      size: screenWidth * 0.045,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Continue with Email",
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      color: Color.fromARGB(255, 9, 55, 107),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Color.fromARGB(255, 7, 49, 98),
                    size: screenWidth * 0.035,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 25),
            _buildPhoneContainer(MediaQuery.of(context).size.width),
            _buildAlternativeOptions(),
            // Added extra padding at the bottom to prevent overflow
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
          ],
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}