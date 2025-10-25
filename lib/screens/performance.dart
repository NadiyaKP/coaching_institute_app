import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../service/auth_service.dart';
import '../service/api_config.dart';
import '../common/theme_color.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool isLoading = true;
  Map<String, dynamic>? performanceData;
  String errorMessage = '';
  late AnimationController _scoreAnimationController;
  late Animation<double> _scoreAnimation;
  late AnimationController _barAnimationController;
  late Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _scoreAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _barAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _scoreAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scoreAnimationController, curve: Curves.easeOutCubic),
    );
    _barAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _barAnimationController, curve: Curves.easeOutCubic),
    );
    
    _fetchPerformanceData();
  }

  @override
  void dispose() {
    _scoreAnimationController.dispose();
    _barAnimationController.dispose();
    super.dispose();
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _fetchPerformanceData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        setState(() {
          errorMessage = 'No access token found';
          isLoading = false;
        });
        return;
      }

      final client = _createHttpClientWithCustomCert();

      try {
        Future<http.Response> makeRequest(String token) {
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/performance/my_report/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeRequest(accessToken);

        debugPrint('Performance API response status: ${response.statusCode}');
        debugPrint('Performance API response body: ${response.body}');

        if (response.statusCode == 401) {
          debugPrint('⚠️ Access token expired, trying refresh...');
          final newAccessToken = await _authService.refreshAccessToken();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeRequest(newAccessToken);
            debugPrint('🔄 Retried with refreshed token: ${response.statusCode}');
          } else {
            setState(() {
              errorMessage = 'Session expired. Please login again.';
              isLoading = false;
            });
            return;
          }
        }

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            performanceData = data;
            isLoading = false;
          });
          _scoreAnimationController.forward(from: 0);
          _barAnimationController.forward(from: 0);
        } else {
          setState(() {
            errorMessage = 'Failed to load performance data: ${response.statusCode}';
            isLoading = false;
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error fetching performance data: $e');
      setState(() {
        errorMessage = 'Error loading performance: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    
    double numValue = 0.0;
    if (value is int) {
      numValue = value.toDouble();
    } else if (value is double) {
      numValue = value;
    } else {
      numValue = double.tryParse(value.toString()) ?? 0.0;
    }
    
    if (numValue == numValue.toInt()) {
      return numValue.toInt().toString();
    }
    
    String formatted = numValue.toStringAsFixed(2);
    formatted = formatted.replaceAll(RegExp(r'0*$'), '');
    formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      body: Stack(
        children: [
          // Modern Header
          Container(
            width: double.infinity,
            height: 200,
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
          ),

          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: isLoading
                      ? _buildLoadingState()
                      : errorMessage.isNotEmpty
                          ? _buildErrorState()
                          : _buildPerformanceContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance Report',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Track your progress',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           StaggeredDotsWaveLoading(),
           SizedBox(height: 24),
          Text(
            'Analyzing your performance...',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _fetchPerformanceData,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Retry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceContent() {
    if (performanceData == null) return const SizedBox();

    final overallScore = performanceData!['overall_score'] ?? 0.0;
    final remarks = performanceData!['remarks'] ?? 'No remarks';

    return RefreshIndicator(
      onRefresh: _fetchPerformanceData,
      color: AppColors.primaryYellow,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverallScoreCard(overallScore, remarks),
            const SizedBox(height: 20),
            _buildWeeklyAnalysisCard(),
            const SizedBox(height: 24),
            _buildSectionHeader('Activity Details'),
            const SizedBox(height: 14),
            _buildMetricCard(
              title: 'Attendance',
              icon: Icons.schedule_rounded,
              gradient: [AppColors.primaryBlue, AppColors.primaryBlueLight],
              data: performanceData!['attendance'] ?? {},
              type: 'attendance',
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Video Classes',
              icon: Icons.play_circle_rounded,
              gradient: [AppColors.primaryYellow, AppColors.primaryYellowLight],
              data: performanceData!['videos'] ?? {},
              type: 'videos',
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Study Notes',
              icon: Icons.menu_book_rounded,
              gradient: [const Color(0xFF10B981), const Color(0xFF34D399)],
              data: performanceData!['notes'] ?? {},
              type: 'notes',
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Mock Tests',
              icon: Icons.assignment_turned_in_rounded,
              gradient: [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)],
              data: performanceData!['mock_tests'] ?? {},
              type: 'mock_tests',
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Question Papers',
              icon: Icons.quiz_rounded,
              gradient: [const Color(0xFFEF4444), const Color(0xFFF87171)],
              data: performanceData!['question_papers'] ?? {},
              type: 'question_papers',
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Reference Videos',
              icon: Icons.video_library_rounded,
              gradient: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
              data: performanceData!['reference_links'] ?? {},
              type: 'reference_links',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallScoreCard(dynamic score, String remarks) {
    double scoreValue = 0.0;
    if (score is int) {
      scoreValue = score.toDouble();
    } else if (score is double) {
      scoreValue = score;
    } else {
      scoreValue = double.tryParse(score.toString()) ?? 0.0;
    }

    Color scoreColor;
    String performanceLabel;
    IconData performanceIcon;
    
    if (scoreValue >= 75) {
      scoreColor = const Color(0xFF10B981);
      performanceLabel = 'Excellent';
      performanceIcon = Icons.workspace_premium_rounded;
    } else if (scoreValue >= 50) {
      scoreColor = AppColors.primaryYellow;
      performanceLabel = 'Good';
      performanceIcon = Icons.trending_up_rounded;
    } else {
      scoreColor = const Color(0xFFEF4444);
      performanceLabel = 'Needs Improvement';
      performanceIcon = Icons.trending_down_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Last Week Summary Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: AppColors.primaryBlue,
                ),
                 SizedBox(width: 6),
                Text(
                  'Last Week Summary',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          
          // Doughnut Chart - Reduced Size
          AnimatedBuilder(
            animation: _scoreAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(140, 140),
                painter: DoughnutScorePainter(
                  score: scoreValue * _scoreAnimation.value,
                  color: scoreColor,
                ),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatNumber(scoreValue * _scoreAnimation.value),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                            letterSpacing: -2,
                          ),
                        ),
                        const Text(
                          'out of 100',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          
          // Remarks
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scoreColor.withOpacity(0.12), scoreColor.withOpacity(0.04)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scoreColor.withOpacity(0.25), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.format_quote_rounded, color: scoreColor, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    remarks,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyAnalysisCard() {
    final categories = ['Attend', 'Videos', 'Notes', 'Tests', 'Papers', 'Refs'];
    final scores = [
      (performanceData!['attendance']?['score'] ?? 0).toDouble(),
      (performanceData!['videos']?['score'] ?? 0).toDouble(),
      (performanceData!['notes']?['score'] ?? 0).toDouble(),
      (performanceData!['mock_tests']?['score'] ?? 0).toDouble(),
      (performanceData!['question_papers']?['score'] ?? 0).toDouble(),
      (performanceData!['reference_links']?['score'] ?? 0).toDouble(),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryBlue, AppColors.primaryBlueLight],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Weekly Analysis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(categories.length, (index) {
                return _buildBarChart(categories[index], scores[index]);
              }),
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildBarChart(String label, double score) {
  Color barColor;
  if (score >= 75) {
    barColor = const Color(0xFF10B981);
  } else if (score >= 50) {
    barColor = AppColors.primaryYellow;
  } else {
    barColor = const Color(0xFFEF4444);
  }

  return Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            _formatNumber(score),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: barColor,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedBuilder(
            animation: _barAnimation,
            builder: (context, child) {
              return Container(
                width: double.infinity,
                height: (score / 100 * 120 * _barAnimation.value).clamp(15, 120),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [barColor, barColor.withOpacity(0.6)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  boxShadow: [
                    BoxShadow(
                      color: barColor.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryBlue, AppColors.primaryBlueLight],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2937),
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required Map<String, dynamic> data,
    required String type,
  }) {
    final score = data['score'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Compact Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: gradient[0], size: 14),
                        const SizedBox(width: 3),
                        Text(
                          _formatNumber(score),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: gradient[0],
                          ),
                        ),
                        Text(
                          '/100',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: gradient[0].withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Compact Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildMetricContent(type, data, gradient[0]),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricContent(String type, Map<String, dynamic> data, Color color) {
    switch (type) {
      case 'attendance':
        return _buildAttendanceContent(data, color);
      case 'videos':
        return _buildVideosContent(data, color);
      case 'notes':
        return _buildNotesContent(data, color);
      case 'mock_tests':
        return _buildMockTestsContent(data, color);
      case 'question_papers':
        return _buildQuestionPapersContent(data, color);
      case 'reference_links':
        return _buildReferenceLinksContent(data, color);
      default:
        return const SizedBox();
    }
  }

  Widget _buildAttendanceContent(Map<String, dynamic> data, Color color) {
    final totalTime = data['total_time_hrs'] ?? 0.0;
    
    return _buildCompactStatRow(
      icon: Icons.timer_rounded,
      label: 'Total Time',
      value: '${_formatNumber(totalTime)} hrs',
      color: color,
    );
  }

  Widget _buildVideosContent(Map<String, dynamic> data, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCompactStatItem(
                icon: Icons.visibility_rounded,
                label: 'Watched',
                value: '${data['watched_logs'] ?? 0}',
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactStatItem(
                icon: Icons.access_time_rounded,
                label: 'Watch Time',
                value: '${_formatNumber(data['total_watch_time_min'])} min',
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildCompactStatRow(
          icon: Icons.speed_rounded,
          label: 'Avg Speed',
          value: '${_formatNumber(data['avg_playback_speed'])}x',
          color: color,
        ),
      ],
    );
  }

  Widget _buildNotesContent(Map<String, dynamic> data, Color color) {
    return Row(
      children: [
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.menu_book_rounded,
            label: 'Notes Read',
            value: '${data['notes_read'] ?? 0}',
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.schedule_rounded,
            label: 'Total Time',
            value: '${_formatNumber(data['total_read_time_min'])} min',
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMockTestsContent(Map<String, dynamic> data, Color color) {
    return Row(
      children: [
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.assignment_rounded,
            label: 'Total Tests',
            value: '${data['total_tests'] ?? 0}',
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.grade_rounded,
            label: 'Avg Score',
            value: _formatNumber(data['average_score']),
            color: color,
          ),
        ),
      ],
    );
  }

 Widget _buildQuestionPapersContent(Map<String, dynamic> data, Color color) {
    return Row(
      children: [
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.description_rounded,
            label: 'Papers Read',
            value: '${data['papers_read'] ?? 0}',
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.timer_rounded,
            label: 'Total Time',
            value: '${_formatNumber(data['total_time_min'])} min',
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceLinksContent(Map<String, dynamic> data, Color color) {
    return Row(
      children: [
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.video_library_rounded,
            label: 'Videos Watched',
            value: '${data['links_read'] ?? 0}',
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatItem(
            icon: Icons.access_time_filled_rounded,
            label: 'Total Time',
            value: '${_formatNumber(data['total_time_min'])} min',
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for doughnut chart
class DoughnutScorePainter extends CustomPainter {
  final double score;
  final Color color;

  DoughnutScorePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = 14.0;

    // Background circle
    final backgroundPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - strokeWidth / 2, backgroundPaint);

    // Progress arc
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [color, color.withOpacity(0.7)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -math.pi / 2,
      sweepAngle,
      false,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(DoughnutScorePainter oldDelegate) {
    return oldDelegate.score != score;
  }
}

// Staggered Dots Wave Loading Animation
class StaggeredDotsWaveLoading extends StatefulWidget {
  const StaggeredDotsWaveLoading({
    Key? key,
    this.size = 50.0,
    this.color = AppColors.primaryYellowDark,
    this.duration = const Duration(milliseconds: 1200),
  }) : super(key: key);

  final double size;
  final Color color;
  final Duration duration;

  @override
  State<StaggeredDotsWaveLoading> createState() => _StaggeredDotsWaveLoadingState();
}

class _StaggeredDotsWaveLoadingState extends State<StaggeredDotsWaveLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();

    _animations = List.generate(5, (index) {
      final delay = (index * 100).toDouble();
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            delay / widget.duration.inMilliseconds,
            1.0,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(5, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              final animationValue = _animations[index].value;
              final scale = 0.5 + (animationValue * 0.5);
              final opacity = 0.3 + (animationValue * 0.7);
              
              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: widget.size / 5,
                    height: widget.size / 5,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}