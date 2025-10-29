import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';
import 'subscription.dart';
import '../subscription/razorpay_payment.dart';

class SubscriptionDetailPage extends StatefulWidget {
  final SubscriptionPlan plan;
  final String courseId;

  const SubscriptionDetailPage({
    super.key,
    required this.plan,
    required this.courseId,
  });

  @override
  State<SubscriptionDetailPage> createState() => _SubscriptionDetailPageState();
}

class _SubscriptionDetailPageState extends State<SubscriptionDetailPage> {
  final AuthService _authService = AuthService();
  bool isLoading = false;
  SubscriptionResponse? subscriptionResponse;
  String? errorMessage;
  String courseName = 'Loading...';
  String subcourseName = '';
  bool isFetchingCourseName = true;

  // SharedPreferences keys matching home.dart
  static const String _keyCourse = 'profile_course';
  static const String _keySubcourse = 'profile_subcourse';

  @override
  void initState() {
    super.initState();
    _loadCourseNameFromSharedPreferences();
  }

  Future<void> _loadCourseNameFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      String? course = prefs.getString(_keyCourse);
      String? subcourse = prefs.getString(_keySubcourse);
      
      debugPrint('========== LOADING COURSE DATA ==========');
      debugPrint('Course from SharedPreferences: $course');
      debugPrint('Subcourse from SharedPreferences: $subcourse');
      debugPrint('=========================================');

      setState(() {
        if (course != null && course.isNotEmpty) {
          courseName = course;
          if (subcourse != null && subcourse.isNotEmpty) {
            subcourseName = subcourse;
          }
          isFetchingCourseName = false;
        } else {
          // If course not found in SharedPreferences, try fetching from API
          courseName = 'Course';
          isFetchingCourseName = false;
        }
      });

      // If course name is still empty, try API as fallback
      if (course == null || course.isEmpty) {
        await _fetchCourseNameFromAPI();
      }
    } catch (e) {
      debugPrint('Error loading course from SharedPreferences: $e');
      setState(() {
        courseName = 'Course';
        isFetchingCourseName = false;
      });
    }
  }

  Future<void> _fetchCourseNameFromAPI() async {
    try {
      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        setState(() {
          courseName = 'Course';
          isFetchingCourseName = false;
        });
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        // Try to fetch profile data to get course name
        final response = await client.get(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/students/get_profile/'),
          headers: {
            ...ApiConfig.commonHeaders,
            'Authorization': 'Bearer $accessToken',
          },
        ).timeout(ApiConfig.requestTimeout);

        debugPrint('Profile API response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          
          if (responseData['success'] == true && responseData['profile'] != null) {
            final profile = responseData['profile'];
            
            if (profile['enrollments'] != null) {
              final enrollments = profile['enrollments'];
              String course = enrollments['course'] ?? 'Course';
              String subcourse = enrollments['subcourse'] ?? '';
              
              setState(() {
                courseName = course;
                subcourseName = subcourse;
                isFetchingCourseName = false;
              });
              
              debugPrint('✅ Fetched course name from API: $courseName');
              debugPrint('✅ Fetched subcourse name from API: $subcourseName');
              
              // Save to SharedPreferences for future use
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_keyCourse, course);
              if (subcourse.isNotEmpty) {
                await prefs.setString(_keySubcourse, subcourse);
              }
            }
          }
        } else {
          setState(() {
            courseName = 'Course';
            isFetchingCourseName = false;
          });
        }
      } catch (e) {
        debugPrint('Error fetching course name from API: $e');
        setState(() {
          courseName = 'Course';
          isFetchingCourseName = false;
        });
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error in _fetchCourseNameFromAPI: $e');
      setState(() {
        courseName = 'Course';
        isFetchingCourseName = false;
      });
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _createSubscription() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        debugPrint('No access token found');
        _navigateToLogin();
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        Future<http.Response> makeRequest(String token) {
          final requestBody = {
            'course_id': widget.courseId,
            'plan_type_id': widget.plan.id,
          };

          debugPrint('Subscription request body: $requestBody');

          return client.post(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/subscriptions/subscribe/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
            body: json.encode(requestBody),
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Subscription response status: ${response.statusCode}');
        debugPrint('Subscription response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');

          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            debugPrint('❌ Token refresh failed');
            await _authService.logout();
            _navigateToLogin();
            return;
          }
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final Map<String, dynamic> responseData = json.decode(response.body);
          
          setState(() {
            subscriptionResponse = SubscriptionResponse.fromJson(responseData);
            isLoading = false;
          });

          debugPrint('✅ Successfully created subscription: ${subscriptionResponse!.subscriptionId}');
        } else {
          setState(() {
            errorMessage = 'Failed to create subscription: ${response.statusCode}';
            isLoading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to create subscription: ${response.statusCode}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } finally {
        client.close();
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() {
        errorMessage = 'SSL certificate issue';
        isLoading = false;
      });
    } on SocketException catch (e) {
      debugPrint('Network error: $e');
      setState(() {
        errorMessage = 'No network connection';
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error creating subscription: $e');
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

 void _handlePayment() {
  if (subscriptionResponse != null) {
    // Navigate to Razorpay payment screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RazorpayPaymentScreen(
          subscriptionId: subscriptionResponse!.subscriptionId.toString(),
          razorpaySubscriptionId: subscriptionResponse!.razorpaySubscriptionId,
          amount: widget.plan.amount,
          planName: widget.plan.name,
          courseName: courseName,
        ),
      ),
    ).then((paymentSuccess) {
      if (paymentSuccess == true) {
        // Payment was successful - show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully subscribed to ${widget.plan.name}'),
            backgroundColor: AppColors.successGreen,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate back to subscription screen
        Navigator.of(context).pop(true);
      } else if (paymentSuccess == false) {
        // Payment failed or was cancelled
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment was cancelled'),
            backgroundColor: AppColors.errorRed,
            duration: Duration(seconds: 3),
          ),
        );
      }
      // If paymentSuccess is null, user just pressed back without attempting payment
    });
  }
}
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.5),
      body: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryYellow,
                      AppColors.primaryYellowDark,
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Subscription Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLoading) _buildLoadingState(),
                      if (errorMessage != null) _buildErrorState(),
                      if (!isLoading && errorMessage == null) _buildContent(),
                    ],
                  ),
                ),
              ),

              // Footer with Pay Button
              if (subscriptionResponse != null && !isLoading)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.grey200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _handlePayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryYellow,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payment_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Pay Now',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Column(
      children: [
        SizedBox(height: 40),
        Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryYellow,
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Creating subscription...',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AppColors.errorRed,
        ),
        const SizedBox(height: 12),
        Text(
          errorMessage ?? 'Something went wrong',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _createSubscription,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryYellow,
            foregroundColor: Colors.white,
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final plan = widget.plan;
    final response = subscriptionResponse;

    // Build course display text
    String courseDisplayText = courseName;
    if (subcourseName.isNotEmpty) {
      courseDisplayText = '$courseName - $subcourseName';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plan Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryYellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${plan.durationInMonths} ${plan.durationInMonths == 1 ? "Month" : "Months"} Access',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${plan.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Subscription Details
        const Text(
          'Subscription Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),

        _buildDetailItem(
          icon: Icons.school_rounded,
          title: 'Course',
          value: isFetchingCourseName ? 'Loading...' : courseDisplayText,
        ),
        _buildDetailItem(
          icon: Icons.calendar_today_rounded,
          title: 'Plan Validity',
          value: '${plan.durationInMonths} ${plan.durationInMonths == 1 ? "Month" : "Months"}',
        ),
        if (response != null) ...[
          _buildDetailItem(
            icon: Icons.play_arrow_rounded,
            title: 'Start Date',
            value: _formatDate(response.startDate),
          ),
          _buildDetailItem(
            icon: Icons.stop_rounded,
            title: 'End Date',
            value: _formatDate(response.endDate),
          ),
        ],
        _buildDetailItem(
          icon: Icons.credit_card_rounded,
          title: 'Amount',
          value: '₹${plan.amount.toStringAsFixed(0)}',
          isAmount: true,
        ),

        const SizedBox(height: 20),

        // Features Included
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Features Included:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              _buildFeatureIncluded('Video Classes'),
              _buildFeatureIncluded('Study Notes'),
              _buildFeatureIncluded('Question Papers'),
              _buildFeatureIncluded('Mock Tests'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
    bool isAmount = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.grey200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryYellow,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isAmount ? AppColors.primaryYellow : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureIncluded(String feature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppColors.successGreen,
          ),
          const SizedBox(width: 8),
          Text(
            feature,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Create subscription when the page loads
    if (subscriptionResponse == null && !isLoading && errorMessage == null) {
      _createSubscription();
    }
  }
}