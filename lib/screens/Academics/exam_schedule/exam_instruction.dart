import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import '../../../service/auth_service.dart';
import '../../../service/api_config.dart';
import '../../../common/theme_color.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'start_exam.dart';

class ExamInstructionScreen extends StatefulWidget {
  final String examId;
  final String examTitle;
  final String examDate;
  final String startTime;
  final String endTime;
  final String subject;
  final bool isNewExam; // Add this parameter

  const ExamInstructionScreen({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.examDate,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.isNewExam = false, // Default to false
  });

  @override
  State<ExamInstructionScreen> createState() => _ExamInstructionScreenState();
}

class _ExamInstructionScreenState extends State<ExamInstructionScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _examStatus;
  Timer? _countdownTimer;
  Duration? _countdown;
  bool _isStartButtonActive = false;
  bool _isStartingExam = false;
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    _fetchExamStatus();
    _setupCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshController.dispose();
    super.dispose();
  }

  void _setupCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCountdown();
        setState(() {});
      }
    });
  }

  void _updateCountdown() {
    if (widget.startTime == null || widget.startTime == 'None') {
      _countdown = null;
      return;
    }

    try {
      DateTime now = DateTime.now();
      DateTime examDate = DateTime.parse(widget.examDate);

      List<String> startParts = widget.startTime.split(':');
      DateTime startDateTime = DateTime(
        examDate.year,
        examDate.month,
        examDate.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
        startParts.length > 2 ? int.parse(startParts[2]) : 0,
      );

      final difference = startDateTime.difference(now);

      if (difference.isNegative == false && difference.inMinutes <= 60) {
        _countdown = difference;

        if (difference.inSeconds <= 0) {
          _isStartButtonActive = true;
        }
      } else {
        _countdown = null;
      }
    } catch (e) {
      debugPrint('Error updating countdown: $e');
      _countdown = null;
    }
  }

  String _formatCountdown(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(String time) {
    try {
      if (time == 'None' || time.isEmpty) return 'Not specified';

      List<String> parts = time.split(':');
      if (parts.length < 2) return time;

      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);

      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      debugPrint('Error formatting time: $e');
      return time;
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Future<void> _fetchExamStatus() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        debugPrint('No access token found');
        _showErrorSnackBar('Please login again');
        return;
      }

      final client = _createHttpClientWithCustomCert();
      String encodedExamId = Uri.encodeComponent(widget.examId);

      try {
        Future<http.Response> makeStatusRequest(String token) {
          return client.get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/attendance/exams/$encodedExamId/status/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeStatusRequest(accessToken);

        if (response.statusCode == 401) {
          final newAccessToken = await _authService.refreshAccessToken();
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeStatusRequest(newAccessToken);
          } else {
            await _authService.logout();
            _showErrorSnackBar('Session expired. Please login again.');
            return;
          }
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);

          if (responseData['success'] == true) {
            setState(() {
              _examStatus = responseData;
              _isLoading = false;

              if (responseData['status'] == 'ongoing' || responseData['already_started'] == true) {
                _isStartButtonActive = true;
              }
            });
          } else {
            setState(() {
              _errorMessage = responseData['message'] ?? 'Failed to load exam status';
              _isLoading = false;
            });
          }
        } else {
          setState(() {
            _errorMessage = 'Failed to load exam status: ${response.statusCode}';
            _isLoading = false;
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error fetching exam status: $e');
      setState(() {
        _errorMessage = 'Error loading exam status';
        _isLoading = false;
      });
    }
  }

  // Force refresh method
  Future<void> _forceRefresh() async {
    debugPrint('Force refreshing exam status...');
    await _fetchExamStatus();
  }

  Future<Map<String, dynamic>?> _startExamApi() async {
    try {
      String accessToken = await _authService.getAccessToken();

      if (accessToken.isEmpty) {
        _showErrorSnackBar('Please login again');
        return null;
      }

      final client = _createHttpClientWithCustomCert();
      String encodedExamId = Uri.encodeComponent(widget.examId);

      try {
        Future<http.Response> makeStartRequest(String token) {
          return client.post(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/attendance/exams/$encodedExamId/start/'),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $token',
            },
          ).timeout(ApiConfig.requestTimeout);
        }

        var response = await makeStartRequest(accessToken);

        if (response.statusCode == 401) {
          final newAccessToken = await _authService.refreshAccessToken();
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            response = await makeStartRequest(newAccessToken);
          } else {
            await _authService.logout();
            _showErrorSnackBar('Session expired. Please login again.');
            return null;
          }
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);

          if (responseData['success'] == true) {
            return responseData;
          } else {
            _showErrorSnackBar(responseData['message'] ?? 'Failed to start exam');
            return null;
          }
        } else {
          _showErrorSnackBar('Failed to start exam: ${response.statusCode}');
          return null;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Error starting exam: $e');
      _showErrorSnackBar('Error starting exam: $e');
      return null;
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 13)),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  // Skeletal Loading Widget
  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton for exam info card
          _buildExamInfoSkeleton(),
          const SizedBox(height: 16),

          // Skeleton for countdown/status banner
          _buildCountdownSkeleton(),
          const SizedBox(height: 16),

          // Skeleton for instructions
          _buildInstructionsSkeleton(),
          const SizedBox(height: 20),

          // Skeleton for button
          Container(
            width: double.infinity,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamInfoSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 200,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          _buildSkeletonInfoRow(),
          const SizedBox(height: 10),
          _buildSkeletonInfoRow(),
        ],
      ),
    );
  }

  Widget _buildSkeletonInfoRow() {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 150,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownSkeleton() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 180,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 140,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 150,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSkeletonInstructionItem(),
          const SizedBox(height: 12),
          _buildSkeletonInstructionItem(),
          const SizedBox(height: 12),
          _buildSkeletonInstructionItem(),
          const SizedBox(height: 12),
          _buildSkeletonInstructionItem(),
        ],
      ),
    );
  }

  Widget _buildSkeletonInstructionItem() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 180,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionContent() {
    if (_examStatus == null) {
      return const SizedBox();
    }

    String status = _examStatus!['status'] ?? 'not_started';

    switch (status) {
      case 'submitted':
        return _buildSubmittedState();
      case 'time_over':
        return _buildTimeOverState();
      case 'not_started':
      case 'ongoing':
        return _buildActiveState(status);
      default:
        return _buildUnknownState(status);
    }
  }

  Widget _buildSubmittedState() {
    return Column(
      children: [
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 60,
            color: AppColors.successGreen,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Exam Submitted Successfully',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'You have already submitted this exam.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textGrey,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        _buildExamInfoCard(),
      ],
    );
  }

  Widget _buildTimeOverState() {
    return Column(
      children: [
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.errorRed.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.timer_off_rounded,
            size: 60,
            color: AppColors.errorRed,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Exam Time Expired',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'The time for this exam has expired.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textGrey,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        _buildExamInfoCard(),
      ],
    );
  }

  Widget _buildActiveState(String status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status == 'ongoing') _buildOngoingBanner(),

        _buildExamInfoCard(),
        const SizedBox(height: 16),

        if (status == 'not_started' && _countdown != null)
          _buildCountdownCard(),

        _buildInstructionsSection(),
        const SizedBox(height: 20),

        _buildStartButton(status),
      ],
    );
  }

  Widget _buildUnknownState(String status) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.help_outline_rounded,
            size: 50,
            color: AppColors.textGrey,
          ),
          const SizedBox(height: 12),
          Text(
            'Unknown exam status: $status',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOngoingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.successGreen.withOpacity(0.12),
            AppColors.successGreen.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.successGreen.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: AppColors.successGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exam is Live',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.successGreen,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'You can start the exam now',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.successGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.successGreen.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamInfoCard() {
    String formattedDate = '';
    try {
      formattedDate = DateFormat('EEEE, MMM dd, yyyy').format(DateTime.parse(widget.examDate));
    } catch (e) {
      formattedDate = widget.examDate;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppColors.primaryYellow,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Exam Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.examTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            Icons.calendar_today_rounded,
            'Date',
            formattedDate,
            AppColors.primaryYellow,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            Icons.access_time_rounded,
            'Time',
            widget.startTime != null && widget.startTime != 'None'
                ? '${_formatTime(widget.startTime)}${widget.endTime != null && widget.endTime != 'None' ? ' - ${_formatTime(widget.endTime)}' : ''}'
                : 'Time not specified',
            AppColors.primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 15,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryYellow.withOpacity(0.12),
            AppColors.primaryYellow.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryYellow.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_rounded,
                color: AppColors.primaryYellow,
                size: 16,
              ),
              SizedBox(width: 6),
              Text(
                'Exam starts in',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatCountdown(_countdown!),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryYellow,
              letterSpacing: 2,
              fontFamily: 'RobotoMono',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _countdown!.inHours > 0 ? 'Hours : Minutes : Seconds' : 'Minutes : Seconds',
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textGrey,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: AppColors.primaryBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Important Instructions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (widget.startTime != null && widget.startTime != 'None')
            _buildInstructionItem(
              Icons.play_circle_outline_rounded,
              'Exam starts at ${_formatTime(widget.startTime)}',
              AppColors.successGreen,
            ),

          if (_examStatus!['end_time'] != null && _examStatus!['end_time'] != 'None')
            _buildInstructionItem(
              Icons.stop_circle_outlined,
              'Exam ends at ${_formatTime(_examStatus!['end_time'])}',
              AppColors.errorRed,
            ),

          _buildInstructionItem(
            Icons.lock_rounded,
            'Once started, you cannot return without finishing',
            AppColors.warningOrange,
          ),

          _buildInstructionItem(
            Icons.check_circle_outline_rounded,
            'After finishing, you cannot return to the exam',
            AppColors.primaryBlue,
          ),

          _buildInstructionItem(
            Icons.upload_rounded,
            'Submit your answers after clicking "Finish"',
            AppColors.primaryYellow,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(IconData icon, String text, Color color, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(String status) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: _isStartButtonActive
                ? const LinearGradient(
                    colors: [
                      AppColors.successGreen,
                      Color(0xFF00C853),
                    ],
                  )
                : null,
            boxShadow: _isStartButtonActive
                ? [
                    BoxShadow(
                      color: AppColors.successGreen.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: _isStartButtonActive && !_isStartingExam ? _startExam : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isStartButtonActive
                  ? Colors.transparent
                  : AppColors.grey300,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.grey300,
              disabledForegroundColor: AppColors.textGrey,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isStartingExam)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                else
                  Icon(
                    _isStartButtonActive
                        ? Icons.play_arrow_rounded
                        : Icons.lock_rounded,
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Text(
                  _isStartingExam ? 'Starting...' : (_isStartButtonActive ? 'Start Exam' : 'Exam Not Started'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_isStartButtonActive && status == 'not_started')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.textGrey,
                ),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Button will be enabled when exam time begins',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _startExam() async {
    debugPrint('Starting exam: ${widget.examId}');

    setState(() {
      _isStartingExam = true;
    });

    try {
      final response = await _startExamApi();

      if (response != null && response['success'] == true && response['pdf_url'] != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StartExamScreen(
              examId: widget.examId,
              title: widget.examTitle,
              subject: widget.subject,
              pdfUrl: response['pdf_url'],
              endTime: widget.endTime,
              examDate: widget.examDate,
            ),
          ),
        );
      } else if (response != null && response['message'] != null) {
        _showErrorSnackBar(response['message']);
      } else {
        _showErrorSnackBar('Failed to start exam');
      }
    } catch (e) {
      debugPrint('Error starting exam: $e');
      _showErrorSnackBar('Error starting exam: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isStartingExam = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Column(
        children: [
          // Header Section with curved bottom
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
              padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Exam Instructions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content Area - Make it scrollable with pull-to-refresh
          Expanded(
            child: _isLoading
                ? _buildSkeletonLoading()
                : _errorMessage.isNotEmpty
                    ? SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorRed.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.error_outline_rounded,
                                    size: 50,
                                    color: AppColors.errorRed,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Something went wrong',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _fetchExamStatus,
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text(
                                    'Try Again',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryYellow,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: AppColors.primaryYellow,
                        onRefresh: _forceRefresh,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: _buildInstructionContent(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// Refresh Controller class
class RefreshController {
  void dispose() {}
}

// Curved Header Clipper
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 20);

    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 20,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}