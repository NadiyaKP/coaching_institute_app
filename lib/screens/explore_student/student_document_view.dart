import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:coaching_institute_app/common/theme_color.dart';

class StudentDocumentViewScreen extends StatefulWidget {
  final String fileUrl;
  final String fileName;

  const StudentDocumentViewScreen({
    Key? key,
    required this.fileUrl,
    required this.fileName,
  }) : super(key: key);

  @override
  State<StudentDocumentViewScreen> createState() => _StudentDocumentViewScreenState();
}

class _StudentDocumentViewScreenState extends State<StudentDocumentViewScreen> {
  String? _localFilePath;
  bool _isLoading = true;
  String _errorMessage = '';
  int _currentPage = 0;
  int _totalPages = 0;
  PDFViewController? _pdfViewController;

  @override
  void initState() {
    super.initState();
    _downloadAndOpenPdf();
  }

  Future<void> _downloadAndOpenPdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      debugPrint('Downloading PDF from: ${widget.fileUrl}');

      // Download the PDF file
      final response = await http.get(Uri.parse(widget.fileUrl));

      if (response.statusCode == 200) {
        // Get temporary directory
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.fileName}');

        // Write the file
        await file.writeAsBytes(response.bodyBytes);

        debugPrint('PDF downloaded to: ${file.path}');

        setState(() {
          _localFilePath = file.path;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading PDF: $e');
      setState(() {
        _errorMessage = 'Failed to load PDF: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppGradients.primaryYellow,
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.fileName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!_isLoading && _localFilePath != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _downloadAndOpenPdf,
              tooltip: 'Reload PDF',
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: !_isLoading && _localFilePath != null
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: _currentPage > 0 
                          ? AppGradients.primaryYellow 
                          : null,
                      color: _currentPage > 0 
                          ? null 
                          : AppColors.grey300,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _currentPage > 0
                          ? [
                              BoxShadow(
                                color: AppColors.shadowYellow.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      onPressed: _currentPage > 0
                          ? () {
                              _pdfViewController?.setPage(_currentPage - 1);
                            }
                          : null,
                      color: _currentPage > 0
                          ? AppColors.white
                          : AppColors.grey500,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryBlue.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'Page ${_currentPage + 1} of $_totalPages',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: _currentPage < _totalPages - 1 
                          ? AppGradients.primaryYellow 
                          : null,
                      color: _currentPage < _totalPages - 1 
                          ? null 
                          : AppColors.grey300,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _currentPage < _totalPages - 1
                          ? [
                              BoxShadow(
                                color: AppColors.shadowYellow.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded),
                      onPressed: _currentPage < _totalPages - 1
                          ? () {
                              _pdfViewController?.setPage(_currentPage + 1);
                            }
                          : null,
                      color: _currentPage < _totalPages - 1
                          ? AppColors.white
                          : AppColors.grey500,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Loading Document...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.grey700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
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
                  Icons.error_outline,
                  size: 64,
                  color: AppColors.errorRed,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Failed to Load Document',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.grey800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryYellow,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowYellow.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _downloadAndOpenPdf,
                  icon: const Icon(Icons.refresh, color: AppColors.white),
                  label: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_localFilePath != null) {
      return PDFView(
        filePath: _localFilePath!,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        pageSnap: true,
        defaultPage: _currentPage,
        fitPolicy: FitPolicy.WIDTH,
        preventLinkNavigation: false,
        onRender: (pages) {
          setState(() {
            _totalPages = pages ?? 0;
          });
          debugPrint('PDF rendered with $_totalPages pages');
        },
        onError: (error) {
          debugPrint('PDF Error: $error');
          setState(() {
            _errorMessage = 'Error loading PDF: $error';
          });
        },
        onPageError: (page, error) {
          debugPrint('Page $page Error: $error');
        },
        onViewCreated: (PDFViewController controller) {
          _pdfViewController = controller;
        },
        onPageChanged: (int? page, int? total) {
          if (page != null) {
            setState(() {
              _currentPage = page;
            });
          }
        },
      );
    }

    return const Center(
      child: Text('No PDF to display'),
    );
  }

  @override
  void dispose() {
    // Clean up the temporary file
    if (_localFilePath != null) {
      try {
        final file = File(_localFilePath!);
        if (file.existsSync()) {
          file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting temporary file: $e');
      }
    }
    super.dispose();
  }
}