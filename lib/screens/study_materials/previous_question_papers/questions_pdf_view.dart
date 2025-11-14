import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../../../service/api_config.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../common/theme_color.dart';

class QuestionsPDFViewScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String accessToken;
  final String questionPaperId;
  final bool enableReadingData;

  const QuestionsPDFViewScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
    required this.accessToken,
    required this.questionPaperId,
    this.enableReadingData = true,
  });

  @override
  State<QuestionsPDFViewScreen> createState() => _QuestionsPDFViewScreenState();
}

class _QuestionsPDFViewScreenState extends State<QuestionsPDFViewScreen> with WidgetsBindingObserver {
  String? localPath;
  bool isLoading = true;
  String? errorMessage;
  int currentPage = 0;
  int totalPages = 0;
  PDFViewController? pdfViewController;

  // Timer tracking variables
  DateTime? _startTime;
  Duration _totalViewingTime = Duration.zero;
  bool _isTracking = false;

  // App lifecycle tracking
  bool _isAppInForeground = true;
  late Box<PdfReadingRecord> _pdfRecordsBox;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
  }

  Future<void> _initializeHive() async {
    try {
      if (Hive.isBoxOpen('pdf_records_box')) {
        _pdfRecordsBox = Hive.box<PdfReadingRecord>('pdf_records_box');
        debugPrint('✅ Using existing Hive box in QuestionsPDFViewScreen');
      } else {
        debugPrint('⚠️ Box not open, trying to open...');
        _pdfRecordsBox = await Hive.openBox<PdfReadingRecord>('pdf_records_box');
        debugPrint('✅ Opened Hive box in QuestionsPDFViewScreen');
      }

      if (widget.enableReadingData) {
        _startTracking();
      } else {
        debugPrint('📊 Reading data collection DISABLED for student type');
      }

      _downloadAndSavePDF();
    } catch (e) {
      debugPrint('❌ Error in Hive initialization for Questions: $e');
      if (widget.enableReadingData) {
        _startTracking();
      }
      _downloadAndSavePDF();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (widget.enableReadingData) {
      _stopTrackingAndStore();
    }

    _cleanupTemporaryFile();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!widget.enableReadingData) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _isAppInForeground = true;
        _startTracking();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _isAppInForeground = false;
        _stopTrackingAndStore();
        break;
    }
  }

  void _startTracking() {
    if (!widget.enableReadingData) return;

    if (!_isTracking && _isAppInForeground) {
      _startTime = DateTime.now();
      _isTracking = true;
      debugPrint('📖 Question Paper Timer Started - encrypted_questionpaper_id: ${widget.questionPaperId}');
    }
  }

  void _stopTrackingAndStore() async {
    if (!widget.enableReadingData) return;

    if (_isTracking) {
      _isTracking = false;

      if (_startTime != null) {
        final sessionDuration = DateTime.now().difference(_startTime!);
        _totalViewingTime += sessionDuration;

        debugPrint('⏹️ Timer Stopped - ID: ${widget.questionPaperId}');
        await _storeViewingData();
      }
    }
  }

  Future<void> _storeViewingData() async {
    if (!widget.enableReadingData) {
      debugPrint('🚫 Reading data collection disabled - skipping storage');
      return;
    }

    try {
      final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final recordKey = 'questionpaper_record_${widget.questionPaperId}_$currentDate';

      final existingRecord = _pdfRecordsBox.values.firstWhere(
        (record) => record.recordKey == recordKey,
        orElse: () => PdfReadingRecord(
          encryptedNoteId: '',
          readedtime: 0,
          readedtimeSeconds: 0,
          readedDate: '',
          recordKey: '',
        ),
      );

      int totalSeconds = _totalViewingTime.inSeconds;

      if (existingRecord.recordKey.isNotEmpty) {
        totalSeconds = existingRecord.readedtimeSeconds + _totalViewingTime.inSeconds;
        await existingRecord.delete();
      }

      final readedTimeMinutes = totalSeconds > 0
          ? double.parse((totalSeconds / 60.0).toStringAsFixed(2))
          : 0.0;

      final viewingRecord = PdfReadingRecord(
        encryptedNoteId: widget.questionPaperId,
        readedtime: readedTimeMinutes,
        readedtimeSeconds: totalSeconds,
        readedDate: currentDate,
        recordKey: recordKey,
      );

      await _pdfRecordsBox.add(viewingRecord);

      debugPrint('💾 Stored viewing data for ID: ${widget.questionPaperId}');
    } catch (e) {
      debugPrint('❌ Error storing question paper viewing data: $e');
    }
  }

  Future<void> _downloadAndSavePDF() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      final parsedUri = Uri.parse(widget.pdfUrl);
      final isPresignedUrl = parsedUri.queryParameters.containsKey('X-Amz-Signature');

      final headers = {
        'ngrok-skip-browser-warning': 'true',
        ...ApiConfig.commonHeaders,
        if (!isPresignedUrl)
          'Authorization': 'Bearer ${widget.accessToken}',
      };

      final response = await httpClient
          .get(Uri.parse(widget.pdfUrl), headers: headers)
          .timeout(const Duration(minutes: 2));

      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final fileName = 'questionpaper_${widget.questionPaperId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          localPath = file.path;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage =
              'Failed to download Question Paper PDF: ${response.statusCode} - ${response.reasonPhrase}';
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error loading Question Paper PDF: ${e.toString()}';
      });
    }
  }

  void _cleanupTemporaryFile() {
    if (localPath != null) {
      try {
        final file = File(localPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        debugPrint('Error deleting temporary PDF file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryYellow,
              AppColors.backgroundLight,
              Colors.white,
            ],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: _buildBody(),
      ),
      bottomNavigationBar: !isLoading && localPath != null && totalPages > 0
          ? _buildBottomNavigationBar()
          : null,
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
            ),
            SizedBox(height: 16),
            Text(
              'Loading Question Paper...',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to load Question Paper',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _downloadAndSavePDF,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (localPath != null) {
      return Container(
        margin: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: PDFView(
            filePath: localPath!,
            enableSwipe: true,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: currentPage,
            fitPolicy: FitPolicy.BOTH,
            onRender: (pages) {
              setState(() => totalPages = pages ?? 0);
            },
            onViewCreated: (controller) => pdfViewController = controller,
            onPageChanged: (page, total) {
              setState(() => currentPage = page ?? 0);
            },
            onError: (error) {
              setState(() {
                errorMessage = 'PDF rendering error: $error';
                isLoading = false;
              });
            },
          ),
        ),
      );
    }

    return const Center(
      child: Text(
        'No Question Paper available',
        style: TextStyle(fontSize: 16, color: Colors.black54),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: currentPage > 0 ? _previousPage : null,
            icon: Icon(
              Icons.arrow_back_ios,
              color: currentPage > 0 ? AppColors.primaryYellow : Colors.grey,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Page ${currentPage + 1} of $totalPages',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.enableReadingData ? AppColors.warningOrange : Colors.grey,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.enableReadingData ? 'Question Paper' : 'No Tracking',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: currentPage < totalPages - 1 ? _nextPage : null,
            icon: Icon(
              Icons.arrow_forward_ios,
              color: currentPage < totalPages - 1 ? AppColors.primaryYellow : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  void _previousPage() {
    if (pdfViewController != null && currentPage > 0) {
      pdfViewController!.setPage(currentPage - 1);
    }
  }

  void _nextPage() {
    if (pdfViewController != null && currentPage < totalPages - 1) {
      pdfViewController!.setPage(currentPage + 1);
    }
  }
}
