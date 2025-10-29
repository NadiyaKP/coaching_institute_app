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
        // Fallback: try to open if somehow not open
        debugPrint('⚠️ Box not open, trying to open...');
        _pdfRecordsBox = await Hive.openBox<PdfReadingRecord>('pdf_records_box');
        debugPrint('✅ Opened Hive box in QuestionsPDFViewScreen');
      }
      
      // Only start tracking if reading data is enabled
      if (widget.enableReadingData) {
        _startTracking();
      } else {
        debugPrint('📊 Reading data collection DISABLED for student type');
      }
      
      _downloadAndSavePDF();
    } catch (e) {
      debugPrint('❌ Error in Hive initialization for Questions: $e');
      // Continue loading PDF even if Hive fails
      if (widget.enableReadingData) {
        _startTracking();
      }
      _downloadAndSavePDF();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // Only stop tracking and store if reading data is enabled
    if (widget.enableReadingData) {
      _stopTrackingAndStore();
    }
    
    _cleanupTemporaryFile();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Only handle lifecycle events if reading data is enabled
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
    // Only track if enabled and conditions are met
    if (!widget.enableReadingData) return;
    
    if (!_isTracking && _isAppInForeground) {
      _startTime = DateTime.now();
      _isTracking = true;
      debugPrint('📖 Question Paper Timer Started - encrypted_questionpaper_id: ${widget.questionPaperId}');
      debugPrint('📊 Reading data collection: ${widget.enableReadingData ? "ENABLED" : "DISABLED"}');
    }
  }

  void _stopTrackingAndStore() async {
    // Only track if enabled
    if (!widget.enableReadingData) return;
    
    if (_isTracking) {
      _isTracking = false;
      
      if (_startTime != null) {
        final sessionDuration = DateTime.now().difference(_startTime!);
        _totalViewingTime += sessionDuration;
        
        debugPrint('⏹️ Question Paper Timer Stopped - encrypted_questionpaper_id: ${widget.questionPaperId}');
        debugPrint('⏱️ Session Duration: ${sessionDuration.inSeconds} seconds');
        debugPrint('📊 Total Viewing Time: ${_totalViewingTime.inSeconds} seconds');
        debugPrint('🔧 Reading data collection: ${widget.enableReadingData ? "ENABLED" : "DISABLED"}');
        
        // Store the viewing data in Hive (don't send to API yet)
        await _storeViewingData();
      }
    }
  }

  Future<void> _storeViewingData() async {
    // Only store data if reading data is enabled
    if (!widget.enableReadingData) {
      debugPrint('🚫 Reading data collection disabled - skipping storage');
      return;
    }
    
    try {
      // Get current date in yy-MM-dd format
      final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      // Create a unique key based on encrypted_questionpaper_id and date
      final recordKey = 'questionpaper_record_${widget.questionPaperId}_$currentDate';
      
      // Check if a record already exists for this encrypted_questionpaper_id and date
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
        // Add the new duration to existing record
        totalSeconds = existingRecord.readedtimeSeconds + _totalViewingTime.inSeconds;
        debugPrint('📝 Found existing question paper record. Adding ${_totalViewingTime.inSeconds}s to ${existingRecord.readedtimeSeconds}s');
        
        // Remove the existing record to update it
        await existingRecord.delete();
      }
      
      // Convert seconds to minutes with 2 decimal precision (
      final readedTimeMinutes = totalSeconds > 0 
          ? double.parse((totalSeconds / 60.0).toStringAsFixed(2))
          : 0.0;
      
      // Create new record
      final viewingRecord = PdfReadingRecord(
        encryptedNoteId: widget.questionPaperId,
        readedtime: readedTimeMinutes,
        readedtimeSeconds: totalSeconds,
        readedDate: currentDate,
        recordKey: recordKey,
      );
      
      // Store the record in Hive
      await _pdfRecordsBox.add(viewingRecord);
      
      debugPrint('💾 Stored question paper viewing data for encrypted_questionpaper_id: ${widget.questionPaperId}');
      debugPrint('📅 readed_date: $currentDate');
      debugPrint('⏱️ Total Seconds: $totalSeconds');
      debugPrint('📊 readedtime (minutes): $readedTimeMinutes');
      debugPrint('🔑 Storage Key: $recordKey');
      debugPrint('🔧 Reading data collection: ${widget.enableReadingData ? "ENABLED" : "DISABLED"}');
      
      // Print all stored records for debugging
      _printStoredRecords();
      
    } catch (e) {
      debugPrint('❌ Error storing question paper viewing data: $e');
    }
  }

  Future<void> _printStoredRecords() async {
    try {
      final allRecords = _pdfRecordsBox.values.toList();
      
      debugPrint('=== STORED QUESTION PAPER RECORDS ===');
      debugPrint('Total records: ${allRecords.length}');
      
      for (final record in allRecords) {
        debugPrint('Record Key: ${record.recordKey}');
        debugPrint('  encrypted_questionpaper_id: ${record.encryptedNoteId}');
        debugPrint('  readedtime: ${record.readedtime}');
        debugPrint('  readedtime_seconds: ${record.readedtimeSeconds}');
        debugPrint('  readed_date: ${record.readedDate}');
        debugPrint('---');
      }
      debugPrint('=== END STORED QUESTION PAPER RECORDS ===');
    } catch (e) {
      debugPrint('❌ Error reading stored question paper records: $e');
    }
  }

  Future<void> _downloadAndSavePDF() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      debugPrint('\n=== QUESTION PAPER PDF DOWNLOAD DETAILED DEBUG ===');
      debugPrint('PDF URL received: "${widget.pdfUrl}"');
      debugPrint('PDF URL length: ${widget.pdfUrl.length}');
      debugPrint('Question Paper ID: ${widget.questionPaperId}');
      debugPrint('Title: ${widget.title}');
      debugPrint('Access Token length: ${widget.accessToken.length}');
      debugPrint('Access Token (first 50 chars): ${widget.accessToken.substring(0, widget.accessToken.length > 50 ? 50 : widget.accessToken.length)}...');
      debugPrint('Reading Data Collection: ${widget.enableReadingData ? "ENABLED" : "DISABLED"}');

      // Parse and inspect URL
      Uri parsedUri = Uri.parse(widget.pdfUrl);
      debugPrint('--- PARSED URL COMPONENTS ---');
      debugPrint('Scheme: ${parsedUri.scheme}');
      debugPrint('Host: ${parsedUri.host}');
      debugPrint('Path: ${parsedUri.path}');
      debugPrint('Query: ${parsedUri.query}');
      debugPrint('--- END PARSED COMPONENTS ---');

      // Detect presigned MinIO/S3 URL
      final isPresignedUrl = parsedUri.queryParameters.containsKey('X-Amz-Signature');
      debugPrint('Presigned URL detected: $isPresignedUrl');

      // Create secure HTTP client
      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      // Build headers conditionally
      final headers = {
        'ngrok-skip-browser-warning': 'true',
        ...ApiConfig.commonHeaders,
        if (!isPresignedUrl)
          'Authorization': 'Bearer ${widget.accessToken}',
      };

      debugPrint('Sending GET request to: ${widget.pdfUrl}');
      debugPrint('Using Authorization header: ${!isPresignedUrl}');

      // Perform GET request
      final response = await httpClient
          .get(Uri.parse(widget.pdfUrl), headers: headers)
          .timeout(const Duration(minutes: 2));

      debugPrint('Response Status Code: ${response.statusCode}');
      debugPrint('Response Reason: ${response.reasonPhrase}');
      debugPrint('Response Headers: ${response.headers}');
      debugPrint('Response Body Length: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        debugPrint('✅ Question Paper PDF downloaded successfully, saving to file...');

        final dir = await getTemporaryDirectory();
        final fileName = 'questionpaper_${widget.questionPaperId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${dir.path}/$fileName');

        await file.writeAsBytes(response.bodyBytes);

        debugPrint('✅ PDF saved at: ${file.path}');
        debugPrint('File size: ${await file.length()} bytes');

        setState(() {
          localPath = file.path;
          isLoading = false;
        });

        debugPrint('✅ PDF ready to display');
      } else {
        final errorBody = response.body.length > 500
            ? '${response.body.substring(0, 500)}...'
            : response.body;

        debugPrint('--- ERROR RESPONSE BODY ---');
        debugPrint(errorBody);
        debugPrint('--- END ERROR RESPONSE ---');

        setState(() {
          isLoading = false;
          errorMessage =
              'Failed to download Question Paper PDF: ${response.statusCode} - ${response.reasonPhrase}';
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading Question Paper PDF: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      setState(() {
        isLoading = false;
        errorMessage = 'Error loading Question Paper PDF: ${e.toString()}';
      });
    } finally {
      debugPrint('=== END QUESTION PAPER PDF DOWNLOAD DEBUG ===\n');
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
        debugPrint('Error deleting temporary Question Paper PDF file: $e');
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
        actions: [
          if (!isLoading && localPath != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _sharePDF,
            ),
          if (!isLoading && localPath != null)
            IconButton(
              icon: Icon(
                widget.enableReadingData ? Icons.timer : Icons.timer_off,
                color: widget.enableReadingData ? Colors.white : Colors.white70,
              ),
              onPressed: _showTimerStatus,
            ),
        ],
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
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
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
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to load Question Paper',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
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
            onLinkHandler: (String? uri) {
              // Handle link clicks if needed
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
        'No Question Paper available',
        style: TextStyle(
          fontSize: 16,
          color: Colors.black54,
        ),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
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

  void _sharePDF() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share functionality can be implemented here'),
        backgroundColor: AppColors.primaryYellow,
      ),
    );
  }

  void _showTimerStatus() {
    final totalSeconds = _totalViewingTime.inSeconds;
    final readedTimeMinutes = totalSeconds > 0 
        ? double.parse((totalSeconds / 60.0).toStringAsFixed(2))
        : 0.0;
    
    debugPrint('=== CURRENT QUESTION PAPER TIMER STATUS ===');
    debugPrint('encrypted_questionpaper_id: ${widget.questionPaperId}');
    debugPrint('Is Tracking: $_isTracking');
    debugPrint('App in Foreground: $_isAppInForeground');
    debugPrint('Total Seconds: $totalSeconds');
    debugPrint('readedtime (minutes): $readedTimeMinutes');
    debugPrint('Current Page: $currentPage');
    debugPrint('Total Pages: $totalPages');
    debugPrint('Reading Data Collection: ${widget.enableReadingData ? "ENABLED" : "DISABLED"}');
    debugPrint('=== END QUESTION PAPER TIMER STATUS ===');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'readedtime: $readedTimeMinutes minutes',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Tracking: ${widget.enableReadingData ? "Enabled" : "Disabled"}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (!widget.enableReadingData) ...[
              const SizedBox(height: 4),
              Text(
                'Student Type: Not Online',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10),
              ),
            ],
          ],
        ),
        backgroundColor: widget.enableReadingData ? AppColors.primaryYellow : Colors.grey,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}