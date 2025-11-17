import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:coaching_institute_app/common/theme_color.dart';
import 'package:provider/provider.dart';

// Provider for Document State Management
class DocumentProvider with ChangeNotifier {
  String? _localFilePath;
  bool _isLoading = true;
  String _errorMessage = '';
  int _currentPage = 0;
  int _totalPages = 0;
  PDFViewController? _pdfViewController;

  String? get localFilePath => _localFilePath;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  PDFViewController? get pdfViewController => _pdfViewController;

  set localFilePath(String? value) {
    _localFilePath = value;
    notifyListeners();
  }

  set isLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  set errorMessage(String value) {
    _errorMessage = value;
    notifyListeners();
  }

  set currentPage(int value) {
    _currentPage = value;
    notifyListeners();
  }

  set totalPages(int value) {
    _totalPages = value;
    notifyListeners();
  }

  set pdfViewController(PDFViewController? value) {
    _pdfViewController = value;
    notifyListeners();
  }

  bool get canNavigatePrevious => _currentPage > 0;
  bool get canNavigateNext => _currentPage < _totalPages - 1;

  void navigateToPreviousPage() {
    if (canNavigatePrevious) {
      _pdfViewController?.setPage(_currentPage - 1);
    }
  }

  void navigateToNextPage() {
    if (canNavigateNext) {
      _pdfViewController?.setPage(_currentPage + 1);
    }
  }

  void reset() {
    _localFilePath = null;
    _isLoading = true;
    _errorMessage = '';
    _currentPage = 0;
    _totalPages = 0;
    _pdfViewController = null;
  }
}

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
  late DocumentProvider _documentProvider;

  @override
  void initState() {
    super.initState();
    _documentProvider = DocumentProvider();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _downloadAndOpenPdf();
    });
  }

  @override
  void dispose() {
    // Clean up the temporary file
    if (_documentProvider.localFilePath != null) {
      try {
        final file = File(_documentProvider.localFilePath!);
        if (file.existsSync()) {
          file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting temporary file: $e');
      }
    }
    super.dispose();
  }

  Future<void> _downloadAndOpenPdf() async {
    _documentProvider.isLoading = true;
    _documentProvider.errorMessage = '';

    try {
      debugPrint('Downloading PDF from: ${widget.fileUrl}');

      final response = await http.get(Uri.parse(widget.fileUrl));

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.fileName}');

        await file.writeAsBytes(response.bodyBytes);

        debugPrint('PDF downloaded to: ${file.path}');

        _documentProvider.localFilePath = file.path;
        _documentProvider.isLoading = false;
      } else {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading PDF: $e');
      _documentProvider.errorMessage = 'Failed to load PDF: ${e.toString()}';
      _documentProvider.isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _documentProvider,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Stack(
          children: [
            // Background Gradient Header
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
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
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildBody(),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  Widget _buildAppBar() {
    return Consumer<DocumentProvider>(
      builder: (context, documentProvider, child) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!documentProvider.isLoading && documentProvider.localFilePath != null)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _downloadAndOpenPdf,
                    tooltip: 'Reload PDF',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return Consumer<DocumentProvider>(
      builder: (context, documentProvider, child) {
        if (documentProvider.isLoading) {
          return _buildLoadingState();
        }

        if (documentProvider.errorMessage.isNotEmpty) {
          return _buildErrorState(documentProvider);
        }

        if (documentProvider.localFilePath != null) {
          return _buildPDFView(documentProvider);
        }

        return _buildEmptyState();
      },
    );
  }

  Widget _buildLoadingState() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryYellow.withOpacity(0.2),
                    AppColors.primaryYellow.withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Loading Document',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please wait while we fetch your document...',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(DocumentProvider documentProvider) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 32),
            const Text(
              'Failed to Load Document',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              documentProvider.errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _downloadAndOpenPdf,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPDFView(DocumentProvider documentProvider) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: PDFView(
        filePath: documentProvider.localFilePath!,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        pageSnap: true,
        defaultPage: documentProvider.currentPage,
        fitPolicy: FitPolicy.WIDTH,
        preventLinkNavigation: false,
        onRender: (pages) {
          documentProvider.totalPages = pages ?? 0;
          debugPrint('PDF rendered with ${documentProvider.totalPages} pages');
        },
        onError: (error) {
          debugPrint('PDF Error: $error');
          documentProvider.errorMessage = 'Error loading PDF: $error';
        },
        onPageError: (page, error) {
          debugPrint('Page $page Error: $error');
        },
        onViewCreated: (PDFViewController controller) {
          documentProvider.pdfViewController = controller;
        },
        onPageChanged: (int? page, int? total) {
          if (page != null) {
            documentProvider.currentPage = page;
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const  EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.grey200,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 64,
                color: AppColors.grey400,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Document Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'There is no PDF document to display',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Consumer<DocumentProvider>(
      builder: (context, documentProvider, child) {
        if (documentProvider.isLoading || documentProvider.localFilePath == null) {
          return const SizedBox.shrink();
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous Button
                _buildNavigationButton(
                  icon: Icons.arrow_back_ios_rounded,
                  onPressed: documentProvider.canNavigatePrevious
                      ? documentProvider.navigateToPreviousPage
                      : null,
                  enabled: documentProvider.canNavigatePrevious,
                ),
                
                // Page Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryYellow.withOpacity(0.15),
                        AppColors.primaryYellow.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.description_rounded,
                        color: AppColors.primaryYellow,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Page ${documentProvider.currentPage + 1} of ${documentProvider.totalPages}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryYellow,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Next Button
                _buildNavigationButton(
                  icon: Icons.arrow_forward_ios_rounded,
                  onPressed: documentProvider.canNavigateNext
                      ? documentProvider.navigateToNextPage
                      : null,
                  enabled: documentProvider.canNavigateNext,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool enabled,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
                colors: [
                  AppColors.primaryYellow,
                  AppColors.primaryYellowDark,
                ],
              )
            : null,
        color: enabled ? null : AppColors.grey200,
        borderRadius: BorderRadius.circular(12),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.primaryYellow.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(
              icon,
              color: enabled ? Colors.white : AppColors.grey400,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}