import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../common/theme_color.dart';
import '../../../service/http_interceptor.dart';
import '../../../service/auth_service.dart'; 
import '../../../service/api_config.dart'; 
import 'dart:convert'; 
import 'package:http/io_client.dart';
import 'dart:async';
import 'submit_answers.dart';


class StartExamScreen extends StatefulWidget {
  final String examId;
  final String title;
  final String subject;
  final String pdfUrl;
  final String? endTime; // Add end time parameter
  final String? examDate; // Add exam date parameter

  const StartExamScreen({
    super.key,
    required this.examId,
    required this.title,
    required this.subject,
    required this.pdfUrl,
    this.endTime,
    this.examDate,
  });

  @override
  State<StartExamScreen> createState() => _StartExamScreenState();
}

class _StartExamScreenState extends State<StartExamScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isFinishingExam = false;
  String _errorMessage = '';
  String _localFilePath = '';
  int _totalPages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfViewController;
  final AuthService _authService = AuthService();
  bool _isDialogShowing = false;
  Timer? _countdownTimer;
  Duration? _remainingTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _downloadAndLoadPdf();
    _setupExamTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    // Clean up the downloaded file
    if (_localFilePath.isNotEmpty) {
      try {
        File(_localFilePath).deleteSync();
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }
    }
    super.dispose();
  }

  void _setupExamTimer() {
    if (widget.endTime == null || widget.endTime == 'None' || 
        widget.examDate == null) {
      debugPrint('No end time provided for exam timer');
      return;
    }

    try {
      DateTime examDate = DateTime.parse(widget.examDate!);
      List<String> endParts = widget.endTime!.split(':');
      
      DateTime endDateTime = DateTime(
        examDate.year,
        examDate.month,
        examDate.day,
        int.parse(endParts[0]),
        int.parse(endParts[1]),
        endParts.length > 2 ? int.parse(endParts[2]) : 0,
      );

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          DateTime now = DateTime.now();
          Duration difference = endDateTime.difference(now);

          if (difference.isNegative || difference.inSeconds <= 0) {
            timer.cancel();
            // Time's up - navigate to submit page
            _navigateToSubmitPage();
          } else {
            setState(() {
              _remainingTime = difference;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Error setting up exam timer: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      if (!_isFinishingExam && !_isLoading && !_isDialogShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isDialogShowing) {
            _showFinishConfirmationDialog();
          }
        });
      }
    }
  }

  Future<void> _downloadAndLoadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      debugPrint('Downloading PDF from: ${widget.pdfUrl}');

      final response = await globalHttpClient.get(Uri.parse(widget.pdfUrl));

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/exam_${widget.examId}.pdf');

        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          _localFilePath = file.path;
          _isLoading = false;
        });

        debugPrint('PDF downloaded successfully: $_localFilePath');
      } else {
        setState(() {
          _errorMessage = 'Failed to download exam file';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error downloading PDF: $e');
      setState(() {
        _errorMessage = 'Error loading exam file: $e';
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _finishExamApi() async {
    // This method is no longer needed since we don't call finish API
    // The finish will happen when images are submitted in submit_answers.dart
    // Keeping it here for future use if needed
    return null;
  }

  void _showFinishConfirmationDialog() {
    if (_isDialogShowing) return;
    
    setState(() {
      _isDialogShowing = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.successGreen),
                SizedBox(width: 12),
                Text(
                  'Finish Exam?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: const Text(
              'Are you sure you want to finish and submit your exam? This action cannot be undone.',
              style: TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _isDialogShowing = false;
                  });
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _finishExam();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Finish Exam',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      setState(() {
        _isDialogShowing = false;
      });
    });
  }

  Future<void> _finishExam() async {
    setState(() {
      _isFinishingExam = true;
      _isDialogShowing = false;
    });
    
    // Simply navigate to submit page without calling finish API
    // The finish API will be called when images are submitted
    _navigateToSubmitPage();
  }

  void _navigateToSubmitPage() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitAnswersScreen(
            examId: widget.examId,
            examTitle: widget.title,
            subject: widget.subject,
          ),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (!didPop && !_isDialogShowing) {
          _showFinishConfirmationDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.primaryYellow,
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.subject,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!_isLoading && _localFilePath.isNotEmpty && !_isFinishingExam)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ElevatedButton.icon(
                  onPressed: _showFinishConfirmationDialog,
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text(
                    'Finish Exam',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            if (_isFinishingExam)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.primaryYellow,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Loading exam...',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please wait while we prepare your exam',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 80,
                            color: AppColors.errorRed,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Oops!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _showFinishConfirmationDialog,
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Go Back'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryYellow,
                                  side: const BorderSide(color: AppColors.primaryYellow, width: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _downloadAndLoadPdf,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryYellow,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : _localFilePath.isNotEmpty
                    ? Column(
                        children: [
                          // Timer Display
                          if (_remainingTime != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _remainingTime!.inMinutes <= 5
                                        ? AppColors.errorRed.withOpacity(0.15)
                                        : AppColors.primaryYellow.withOpacity(0.15),
                                    _remainingTime!.inMinutes <= 5
                                        ? AppColors.errorRed.withOpacity(0.05)
                                        : AppColors.primaryYellow.withOpacity(0.05),
                                  ],
                                ),
                                border: Border(
                                  bottom: BorderSide(
                                    color: _remainingTime!.inMinutes <= 5
                                        ? AppColors.errorRed.withOpacity(0.3)
                                        : AppColors.primaryYellow.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.timer_rounded,
                                    color: _remainingTime!.inMinutes <= 5
                                        ? AppColors.errorRed
                                        : AppColors.primaryYellow,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Exam ends within: ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(_remainingTime!),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _remainingTime!.inMinutes <= 5
                                          ? AppColors.errorRed
                                          : AppColors.primaryYellow,
                                      fontFamily: 'RobotoMono',
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // PDF Viewer
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: PDFView(
                                  filePath: _localFilePath,
                                  enableSwipe: true,
                                  swipeHorizontal: false,
                                  autoSpacing: true,
                                  pageFling: true,
                                  pageSnap: true,
                                  defaultPage: _currentPage,
                                  fitPolicy: FitPolicy.WIDTH,
                                  onRender: (pages) {
                                    setState(() {
                                      _totalPages = pages ?? 0;
                                    });
                                  },
                                  onViewCreated: (PDFViewController controller) {
                                    _pdfViewController = controller;
                                  },
                                  onPageChanged: (int? page, int? total) {
                                    setState(() {
                                      _currentPage = page ?? 0;
                                    });
                                  },
                                  onError: (error) {
                                    debugPrint('PDF Error: $error');
                                    setState(() {
                                      _errorMessage = 'Error displaying PDF: $error';
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),

                          // Navigation Controls
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  onPressed: _currentPage > 0
                                      ? () {
                                          _pdfViewController?.setPage(_currentPage - 1);
                                        }
                                      : null,
                                  icon: const Icon(Icons.arrow_back_ios_rounded),
                                  color: AppColors.primaryYellow,
                                  disabledColor: AppColors.grey400,
                                  iconSize: 24,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryYellow.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Page ${_currentPage + 1} of $_totalPages',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryYellow,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _currentPage < _totalPages - 1
                                      ? () {
                                          _pdfViewController?.setPage(_currentPage + 1);
                                        }
                                      : null,
                                  icon: const Icon(Icons.arrow_forward_ios_rounded),
                                  color: AppColors.primaryYellow,
                                  disabledColor: AppColors.grey400,
                                  iconSize: 24,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Text(
                          'No exam file available',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ),
      ),
    );
  }
}