import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../common/theme_color.dart';
import '../subscription/subscription_detail.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final AuthService _authService = AuthService();
  bool isLoading = true;
  List<SubscriptionPlan> plans = [];
  String? errorMessage;
  int? selectedPlanIndex;
  int _currentIndex = 1; // Subscription tab is selected
  String studentType = '';
  String? courseId;

  @override
  void initState() {
    super.initState();
    _loadStudentType();
    _loadCourseId();
    _fetchSubscriptionPlans();
  }

  Future<void> _loadStudentType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentType = prefs.getString('profile_student_type') ?? '';
    });
  }

  Future<void> _loadCourseId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      courseId = prefs.getString('course_id') ?? 'aNYuWH6tZ2ShfSZZ0-4-zg'; // Fallback to default
    });
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _fetchSubscriptionPlans() async {
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
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/subscriptions/plans/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Subscription Plans response status: ${response.statusCode}');
        debugPrint('Subscription Plans response body: ${response.body}');

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

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          
          setState(() {
            plans = responseData
                .map((plan) => SubscriptionPlan.fromJson(plan))
                .toList();
            isLoading = false;
          });

          debugPrint('✅ Successfully loaded ${plans.length} subscription plans');
        } else {
          setState(() {
            errorMessage = 'Failed to load subscription plans';
            isLoading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load plans: ${response.statusCode}'),
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
      setState(() {
        errorMessage = 'No network connection';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching subscription plans: $e');
      setState(() {
        errorMessage = 'Error loading plans: ${e.toString()}';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  void _handleSubscribe(SubscriptionPlan plan) async {
    if (courseId == null || courseId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Course information not found'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Navigate to subscription detail page
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SubscriptionDetailPage(
          plan: plan,
          courseId: courseId!,
        ),
      ),
    );

    // Handle result if needed (e.g., payment success)
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully subscribed to ${plan.name}'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    }
  }

  // Bottom Navigation methods
  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    switch (index) {
      case 0: // Home
        Navigator.of(context).pop();
        break;
      case 1: // Already on Subscription
        break;
      case 2: // Mock Test
        Navigator.pushNamed(context, '/mock_test');
        break;
      case 3: // Profile
        Navigator.pushNamed(context, '/view_profile');
        break;
    }
  }

  IconData _getSecondTabIcon() {
    final String studentTypeUpper = studentType.toUpperCase();
    if (studentTypeUpper == 'ONLINE') {
      return Icons.analytics_rounded;
    } else if (studentTypeUpper == 'PUBLIC') {
      return Icons.card_membership_rounded;
    } else {
      return Icons.calendar_today_rounded;
    }
  }

  String _getSecondTabLabel() {
    final String studentTypeUpper = studentType.toUpperCase();
    if (studentTypeUpper == 'ONLINE') {
      return 'Performance';
    } else if (studentTypeUpper == 'PUBLIC') {
      return 'Subscription';
    } else {
      return 'Exam Schedule';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: errorMessage != null
          ? _buildErrorState()
          : isLoading
              ? _buildSkeletonLoading()
              : plans.isEmpty
                  ? _buildEmptyState()
                  : _buildPlansContent(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primaryYellow,
            unselectedItemColor: AppColors.grey400,
            selectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(_getSecondTabIcon()),
                label: _getSecondTabLabel(),
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.assignment_turned_in_rounded),
                label: 'Mock Test',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Skeleton Loading Widget
  Widget _buildSkeletonLoading() {
    return Column(
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Skeleton Content
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              children: [
                // Skeleton Plan Cards
                _buildSkeletonPlanCard(),
                const SizedBox(height: 12),
                _buildSkeletonPlanCard(),
                const SizedBox(height: 12),
                _buildSkeletonPlanCard(),
                const SizedBox(height: 16),
                
                // Skeleton Features Section
                _buildSkeletonFeaturesSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonPlanCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Plan name skeleton
                _buildShimmerBox(width: 100, height: 24, radius: 5),
                // Radio skeleton
                _buildShimmerBox(width: 24, height: 24, radius: 12),
              ],
            ),
            const SizedBox(height: 8),
            // Duration skeleton
            _buildShimmerBox(width: 120, height: 14, radius: 4),
            const SizedBox(height: 16),
            // Price skeleton
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildShimmerBox(width: 30, height: 30, radius: 4),
                const SizedBox(width: 4),
                _buildShimmerBox(width: 80, height: 40, radius: 4),
                const SizedBox(width: 6),
                _buildShimmerBox(width: 60, height: 14, radius: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonFeaturesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildShimmerBox(width: 3, height: 20, radius: 2),
              const SizedBox(width: 10),
              _buildShimmerBox(width: 140, height: 20, radius: 4),
            ],
          ),
          const SizedBox(height: 14),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(),
          _buildSkeletonFeatureItem(isLast: true),
        ],
      ),
    );
  }

  Widget _buildSkeletonFeatureItem({bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          _buildShimmerBox(width: 32, height: 32, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildShimmerBox(width: 100, height: 14, radius: 4),
                const SizedBox(height: 4),
                _buildShimmerBox(width: 180, height: 10, radius: 4),
              ],
            ),
          ),
          _buildShimmerBox(width: 16, height: 16, radius: 8),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.grey200,
            AppColors.grey200.withOpacity(0.5),
            AppColors.grey200,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: _ShimmerAnimation(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.errorRed.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Oops! Something went wrong',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _fetchSubscriptionPlans,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Retry',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
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
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Plans',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Choose the plan that works best for you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 64,
                    color: AppColors.grey400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Plans Available',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'There are no subscription plans available at the moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlansContent() {
    return RefreshIndicator(
      onRefresh: _fetchSubscriptionPlans,
      color: AppColors.primaryYellow,
      child: Column(
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
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Subscription Plans',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose the plan that works best for you',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plans List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: plans.length,
                    itemBuilder: (context, index) {
                      final plan = plans[index];
                      final bool isSelected = selectedPlanIndex == index;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildPlanCard(plan, index, isSelected),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Features Section
                  _buildFeaturesSection(),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPlanIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected 
                ? AppColors.primaryYellow 
                : AppColors.grey200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected 
                  ? AppColors.primaryYellow.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isSelected ? 10 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Plan Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryYellow.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                plan.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryYellow,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${plan.durationInMonths} ${plan.durationInMonths == 1 ? "Month" : "Months"} Access',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Selection Radio
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected 
                                ? AppColors.primaryYellow 
                                : AppColors.grey300,
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: isSelected 
                              ? AppColors.primaryYellow 
                              : Colors.transparent,
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        plan.amount.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          '/ ${plan.durationInMonths} ${plan.durationInMonths == 1 ? "month" : "months"}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Only show per month rate for plans with more than 2 months
                  if (plan.durationInMonths > 2) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.trending_down_rounded,
                            size: 13,
                            color: AppColors.successGreen,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '₹${(plan.amount / plan.durationInMonths).toStringAsFixed(0)} per month',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.successGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Subscribe Button
            if (isSelected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ElevatedButton(
                  onPressed: () => _handleSubscribe(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Subscribe Now',
                        style: TextStyle(
                          fontSize: 13,
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
    );
  }

  Widget _buildFeaturesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'All Plans Include',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildFeatureItem(
            icon: Icons.video_library_rounded,
            title: 'Video Classes',
            description: 'Access to all video lectures',
          ),
          _buildFeatureItem(
            icon: Icons.description_rounded,
            title: 'Notes',
            description: 'Comprehensive study notes',
          ),
          _buildFeatureItem(
            icon: Icons.quiz_rounded,
            title: 'Question Papers',
            description: 'Previous year question papers',
          ),
          _buildFeatureItem(
            icon: Icons.assignment_rounded,
            title: 'Mock Tests',
            description: 'Practice with unlimited tests',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryYellow,
              size: 18,
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
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.successGreen,
            size: 16,
          ),
        ],
      ),
    );
  }
}

// Custom Clipper for curved header (same as home page)
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 30,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}

// Model class for Subscription Plan
class SubscriptionPlan {
  final String id;
  final String name;
  final int durationInMonths;
  final double amount;
  final String razorpayPlanId;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.durationInMonths,
    required this.amount,
    required this.razorpayPlanId,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      durationInMonths: json['duration_in_months'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      razorpayPlanId: json['razorpay_plan_id'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'duration_in_months': durationInMonths,
      'amount': amount,
      'razorpay_plan_id': razorpayPlanId,
    };
  }
}

// Model class for Subscription Response
class SubscriptionResponse {
  final bool success;
  final int subscriptionId;
  final String razorpaySubscriptionId;
  final String status;
  final String startDate;
  final String endDate;

  SubscriptionResponse({
    required this.success,
    required this.subscriptionId,
    required this.razorpaySubscriptionId,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  factory SubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionResponse(
      success: json['success'] ?? false,
      subscriptionId: json['subscription_id'] ?? 0,
      razorpaySubscriptionId: json['razorpay_subscription_id'] ?? '',
      status: json['status'] ?? '',
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
    );
  }
}

// Shimmer Animation Widget for skeleton loading
class _ShimmerAnimation extends StatefulWidget {
  final Widget child;

  const _ShimmerAnimation({required this.child});

  @override
  __ShimmerAnimationState createState() => __ShimmerAnimationState();
}

class __ShimmerAnimationState extends State<_ShimmerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withOpacity(0.3),
                Colors.white.withOpacity(0.7),
                Colors.white.withOpacity(0.3),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * slidePercent - bounds.width,
      0.0,
      0.0,
    );
  }
}