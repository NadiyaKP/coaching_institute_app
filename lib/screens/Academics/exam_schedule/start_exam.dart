import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../common/theme_color.dart';
import '../../../service/http_interceptor.dart';

class StartExamScreen extends StatefulWidget {
  final String examId;
  final String title;
  final String subject;
  final String fileUrl;

  const StartExamScreen({
    super.key,
    required this.examId,
    required this.title,
    required this.subject,
    required this.fileUrl,
  });

  @override
  State<StartExamScreen> createState() => _StartExamScreenState();
}

class _StartExamScreenState extends State<StartExamScreen> {
  bool _isLoading = true;
  String _errorMessage = '';
  String _localFilePath = '';
  int _totalPages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfViewController;

  @override
  void initState() {
    super.initState();
    _downloadAndLoadPdf();
  }

  Future<void> _downloadAndLoadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      debugPrint('Downloading PDF from: ${widget.fileUrl}');

      // Download the PDF file
      final response = await globalHttpClient.get(Uri.parse(widget.fileUrl));

      if (response.statusCode == 200) {
        // Get temporary directory
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/exam_${widget.examId}.pdf');

        // Write the file
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

  void _showExitConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: AppColors.errorRed),
               SizedBox(width: 12),
               Text(
                'Exit Exam?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to exit the exam?',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pop(context); 
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (!didPop) {
          _showExitConfirmationDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.primaryYellow,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: _showExitConfirmationDialog,
          ),
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
              ),
              Text(
                widget.subject,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            if (!_isLoading && _localFilePath.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Page ${_currentPage + 1}/$_totalPages',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
                                onPressed: () => Navigator.pop(context),
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

  @override
  void dispose() {
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
}