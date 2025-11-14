import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../../service/api_config.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../common/theme_color.dart';

class PDFViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final String accessToken;
  final String noteId;
  final bool enableReadingData;

  const PDFViewerScreen({
    super.key,
    required this.pdfUrl,
    required this.title,
    required this.accessToken,
    required this.noteId,
    this.enableReadingData = false,
  });

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> with WidgetsBindingObserver {
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
        debugPrint('✅ Using existing Hive box in PDFViewerScreen');
      } else {
        debugPrint('⚠️ Box not open, trying to open...');
        _pdfRecordsBox = await Hive.openBox<PdfReadingRecord>('pdf_records_box');
        debugPrint('✅ Opened Hive box in PDFViewerScreen');
      }
      
      if (widget.enableReadingData) {
        _startTracking();
      } else {
        debugPrint('📊 Reading data collection DISABLED for student type');
      }
      
      _downloadAndSavePDF();
    } catch (e) {
      debugPrint('❌ Error in Hive initialization: $e');
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
    if (!_isTracking && _isAppInForeground && widget.enableReadingData) {
      _startTime = DateTime.now();
      _isTracking = true;
      debugPrint('PDF Timer Started - encrypted_note_id: ${widget.noteId}');
    }
  }

  void _stopTrackingAndStore() async {
    if (_isTracking && widget.enableReadingData) {
      _isTracking = false;
      
      if (_startTime != null) {
        final sessionDuration = DateTime.now().difference(_startTime!);
        _totalViewingTime += sessionDuration;
        
        debugPrint('PDF Timer Stopped - encrypted_note_id: ${widget.noteId}');
        debugPrint('Session Duration: ${sessionDuration.inSeconds} seconds');
        debugPrint('Total Viewing Time: ${_totalViewingTime.inSeconds} seconds');
        
        await _storeViewingData();
      }
    }
  }

  Future<void> _storeViewingData() async {
    if (!widget.enableReadingData) return;
    
    try {
      final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final recordKey = 'pdf_record_${widget.noteId}_$currentDate';
      
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
        debugPrint('Found existing record. Adding ${_totalViewingTime.inSeconds}s to ${existingRecord.readedtimeSeconds}s');
        await existingRecord.delete();
      }
      
      final readedTimeMinutes = totalSeconds > 0 
          ? double.parse((totalSeconds / 60.0).toStringAsFixed(2))
          : 0.0;
      
      final viewingRecord = PdfReadingRecord(
        encryptedNoteId: widget.noteId,
        readedtime: readedTimeMinutes,
        readedtimeSeconds: totalSeconds,
        readedDate: currentDate,
        recordKey: recordKey,
      );
      
      await _pdfRecordsBox.add(viewingRecord);
      
      debugPrint('Stored viewing data for encrypted_note_id: ${widget.noteId}');
      debugPrint('readed_date: $currentDate');
      debugPrint('Total Seconds: $totalSeconds');
      debugPrint('readedtime (minutes): $readedTimeMinutes');
      debugPrint('Storage Key: $recordKey');
      
      _printStoredRecords();
      
    } catch (e) {
      debugPrint('Error storing viewing data: $e');
    }
  }

  Future<void> _printStoredRecords() async {
    try {
      final allRecords = _pdfRecordsBox.values.toList();
      debugPrint('=== STORED PDF RECORDS ===');
      debugPrint('Total records: ${allRecords.length}');
      for (final record in allRecords) {
        debugPrint('Record Key: ${record.recordKey}');
        debugPrint('  encrypted_note_id: ${record.encryptedNoteId}');
        debugPrint('  readedtime: ${record.readedtime}');
        debugPrint('  readedtime_seconds: ${record.readedtimeSeconds}');
        debugPrint('  readed_date: ${record.readedDate}');
        debugPrint('---');
      }
      debugPrint('=== END STORED RECORDS ===');
    } catch (e) {
      debugPrint('Error reading stored records: $e');
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

      Uri parsedUri = Uri.parse(widget.pdfUrl);
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
        final fileName = 'pdf_${widget.noteId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          localPath = file.path;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = 'Failed to download PDF: ${response.statusCode} - ${response.reasonPhrase}';
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading PDF: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Error loading PDF: ${e.toString()}';
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
              AppColors.white,
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
              'Loading PDF...',
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
              const Icon(Icons.error_outline, size: 80, color: AppColors.errorRed),
              const SizedBox(height: 16),
              const Text(
                'Failed to load PDF',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _downloadAndSavePDF,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryYellow,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
              color: AppColors.warningOrange.withOpacity(0.3),
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
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: currentPage,
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false,
            onRender: (pages) {
              setState(() {
                totalPages = pages ?? 0;
              });
            },
            onViewCreated: (PDFViewController controller) {
              pdfViewController = controller;
            },
            onPageChanged: (int? page, int? total) {
              setState(() {
                currentPage = page ?? 0;
              });
            },
            onError: (error) {
              setState(() {
                errorMessage = 'PDF rendering error: $error';
                isLoading = false;
              });
            },
            onPageError: (page, error) {
              setState(() {
                errorMessage = 'Page $page error: $error';
              });
            },
          ),
        ),
      );
    }

    return const Center(
      child: Text(
        'No PDF available',
        style: TextStyle(fontSize: 16, color: Colors.black54),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.warningOrange.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: currentPage > 0 
                  ? AppColors.primaryYellow 
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: currentPage > 0 ? [
                BoxShadow(
                  color: AppColors.primaryYellow.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ] : [],
            ),
            child: IconButton(
              onPressed: currentPage > 0 ? _previousPage : null,
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: currentPage > 0 ? Colors.white : Colors.grey,
                size: 18,
              ),
              padding: EdgeInsets.zero,
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
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.enableReadingData ? 'PDF 📊' : 'PDF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.enableReadingData ? AppColors.primaryBlue : AppColors.primaryYellow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: currentPage < totalPages - 1 
                  ? AppColors.warningOrange
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: currentPage < totalPages - 1 ? [
                BoxShadow(
                  color: AppColors.warningOrange.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ] : [],
            ),
            child: IconButton(
              onPressed: currentPage < totalPages - 1 ? _nextPage : null,
              icon: Icon(
                Icons.arrow_forward_ios,
                color: currentPage < totalPages - 1 ? Colors.white : Colors.grey,
                size: 18,
              ),
              padding: EdgeInsets.zero,
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

  void _sharePDF() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share functionality can be implemented here'),
        backgroundColor: AppColors.primaryYellow,
      ),
    );
  }

  void _showTimerStatus() {
    if (!widget.enableReadingData) return;

    final totalSeconds = _totalViewingTime.inSeconds;
    final readedTimeMinutes = totalSeconds > 0 
        ? double.parse((totalSeconds / 60.0).toStringAsFixed(2))
        : 0.0;
    
    debugPrint('=== CURRENT TIMER STATUS ===');
    debugPrint('encrypted_note_id: ${widget.noteId}');
    debugPrint('Is Tracking: $_isTracking');
    debugPrint('App in Foreground: $_isAppInForeground');
    debugPrint('Total Seconds: $totalSeconds');
    debugPrint('readedtime (minutes): $readedTimeMinutes');
    debugPrint('Current Page: $currentPage');
    debugPrint('Total Pages: $totalPages');
    debugPrint('=== END TIMER STATUS ===');
  }
}
