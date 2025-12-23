import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/theme_color.dart';
import '../../../service/api_config.dart';
import '../../../service/auth_service.dart';
import '../../../service/http_interceptor.dart';

class TimeTableScreen extends StatefulWidget {
  const TimeTableScreen({Key? key}) : super(key: key);

  @override
  State<TimeTableScreen> createState() => _TimeTableScreenState();
}

class _TimeTableScreenState extends State<TimeTableScreen> {
  List<TimeTableDay> _timeTableDays = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String? _accessToken;
  String _timeTableTitle = '';
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  
  // Zoom variables - Changed approach
  double _scaleFactor = 1.0;
  final double _minScaleFactor = 0.5;
  final double _maxScaleFactor = 2.0;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _fetchTimeTable();
    } else {
      _showError('Access token not found. Please login again.');
      _navigateToLogin();
    }
  }

  Future<void> _getAccessToken() async {
    try {
      _accessToken = await _authService.getAccessToken();
    } catch (e) {
      _showError('Failed to retrieve access token: $e');
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  Map<String, String> _getAuthHeaders() {
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Access token is null or empty');
    }
    
    return {
      'Authorization': 'Bearer $_accessToken',
      ...ApiConfig.commonHeaders,
    };
  }

  void _handleTokenExpiration() async {
    await _authService.logout();
    _showError('Session expired. Please login again.');
    _navigateToLogin();
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/signup',
        (Route<dynamic> route) => false,
      );
    }
  }

  Future<void> _fetchTimeTable() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      _showError('Access token not found');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final client = _createHttpClientWithCustomCert();

    try {
      final apiUrl = '${ApiConfig.currentBaseUrl}/api/attendance/time_table/list/';
      
      final response = await globalHttpClient.get(
        Uri.parse(apiUrl),
        headers: _getAuthHeaders(),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final String? title = data['title'];
        final List<dynamic>? daysJson = data['days'];
        
        if (daysJson != null) {
          setState(() {
            _timeTableTitle = title ?? 'Time Table';
            _timeTableDays = daysJson
                .map((json) => TimeTableDay.fromJson(json))
                .toList();
            _isLoading = false;
          });
        } else {
          throw Exception('Invalid response format');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else if (response.statusCode == 404) {
        setState(() {
          _timeTableDays = [];
          _errorMessage = 'Time Table not set';
          _isLoading = false;
        });
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } on HandshakeException catch (e) {
      debugPrint('SSL Handshake error: $e');
      setState(() => _isLoading = false);
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
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No network connection'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching time table: $e');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    } finally {
      client.close();
    }
  }

  void _showError(String message) {
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  // Modified zoom controls - Now affects cell sizes
  void _zoomIn() {
    setState(() {
      _scaleFactor = (_scaleFactor * 1.2).clamp(_minScaleFactor, _maxScaleFactor);
    });
  }

  void _zoomOut() {
    setState(() {
      _scaleFactor = (_scaleFactor / 1.2).clamp(_minScaleFactor, _maxScaleFactor);
    });
  }

  void _resetZoom() {
    setState(() {
      _scaleFactor = 1.0;
    });
  }

  Widget _buildSkeletonLoader() {
    return RefreshIndicator(
      onRefresh: _fetchTimeTable,
      color: AppColors.primaryYellow,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          if (index == 0) {
            // Header skeleton
            return Container(
              height: 50,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }
          // Row skeleton
          return Container(
            height: 60,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTableCell(String text, double width, {
    bool isHeader = false,
    bool isBold = false,
    bool isRemark = false,
    bool isDate = false,
    bool isFirstInGroup = false,
    bool isLastInGroup = false,
  }) {
    // Apply scale factor to width and padding
    final scaledWidth = width * _scaleFactor;
    final scaledPadding = 12.0 * _scaleFactor;
    final scaledFontSize = (isHeader ? 13.0 : 12.0) * _scaleFactor;
    final scaledMinHeight = (isHeader ? 50.0 : 45.0) * _scaleFactor;
    
    return Container(
      width: scaledWidth,
      constraints: BoxConstraints(
        minHeight: scaledMinHeight,
      ),
      padding: EdgeInsets.all(scaledPadding),
      decoration: BoxDecoration(
        color: isHeader ? AppColors.primaryYellow : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: isHeader ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
            width: 0.5,
          ),
          right: BorderSide(
            color: isHeader ? Colors.white.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
            width: 0.5,
          ),
          top: BorderSide(
            color: isHeader 
                ? Colors.white.withOpacity(0.3) 
                : isFirstInGroup 
                    ? Colors.grey.withOpacity(0.3) 
                    : Colors.grey.withOpacity(0.3),
            width: isHeader ? 0.5 : isFirstInGroup ? 0.5 : 0.5,
          ),
          bottom: BorderSide(
            color: isHeader 
                ? Colors.white.withOpacity(0.3) 
                : isLastInGroup 
                    ? Colors.grey.withOpacity(0.8) 
                    : Colors.grey.withOpacity(0.3),
            width: isHeader ? 0.5 : isLastInGroup ? 2.0 : 0.5,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: scaledFontSize,
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
          color: isHeader 
              ? Colors.white 
              : isRemark 
                  ? Colors.grey[700] 
                  : AppColors.textDark,
          fontStyle: isRemark ? FontStyle.italic : FontStyle.normal,
        ),
        textAlign: isHeader || isDate ? TextAlign.center : TextAlign.left,
      ),
    );
  }

  Widget _buildDataTable() {
    // Base column widths
    const double dateWidth = 110.0;
    const double subjectWidth = 180.0;
    const double chapterWidth = 150.0;
    const double topicWidth = 200.0;
    const double remarkWidth = 200.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Table Header
              Row(
                children: [
                  _buildTableCell('Date', dateWidth, isHeader: true),
                  _buildTableCell('Subject', subjectWidth, isHeader: true),
                  _buildTableCell('Chapter', chapterWidth, isHeader: true),
                  _buildTableCell('Topic', topicWidth, isHeader: true),
                  _buildTableCell('Remark', remarkWidth, isHeader: true),
                ],
              ),
              
              // Table Body
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _buildTableRows(
                      dateWidth, 
                      subjectWidth, 
                      chapterWidth, 
                      topicWidth, 
                      remarkWidth
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTableRows(
    double dateWidth,
    double subjectWidth,
    double chapterWidth,
    double topicWidth,
    double remarkWidth,
  ) {
    List<Widget> rows = [];
    int globalRowIndex = 0;

    for (var day in _timeTableDays) {
      final entriesCount = day.entries.length;
      
      for (int entryIndex = 0; entryIndex < entriesCount; entryIndex++) {
        final entry = day.entries[entryIndex];
        final isEven = globalRowIndex % 2 == 0;
        final isFirstInGroup = entryIndex == 0;
        final isLastInGroup = entryIndex == entriesCount - 1;
        
        final displaySubject = entry.displaySubject;
        
        final displayChapter = entry.chapterTitles.isNotEmpty 
            ? entry.chapterTitles
                .where((chapter) => chapter.isNotEmpty && chapter.toLowerCase() != 'null')
                .join(', ') 
            : '';
        
        final displayTopic = entry.topicTitles.isNotEmpty 
            ? entry.topicTitles
                .where((topic) => topic.isNotEmpty && topic.toLowerCase() != 'null')
                .join(', ') 
            : '';
        
        final displayRemark = (entry.remark != null && 
                               entry.remark!.isNotEmpty && 
                               entry.remark!.toLowerCase() != 'null') 
            ? entry.remark! 
            : '';

        rows.add(
          IntrinsicHeight(
            child: Container(
              color: isEven ? Colors.white : AppColors.backgroundLight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTableCell(
                    isFirstInGroup ? _formatDate(day.date) : '', 
                    dateWidth, 
                    isDate: true,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  ),
                  _buildTableCell(
                    displaySubject, 
                    subjectWidth, 
                    isBold: true,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  ),
                  _buildTableCell(
                    displayChapter, 
                    chapterWidth,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  ),
                  _buildTableCell(
                    displayTopic, 
                    topicWidth,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  ),
                  _buildTableCell(
                    displayRemark, 
                    remarkWidth, 
                    isRemark: true,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                  ),
                ],
              ),
            ),
          ),
        );
        
        globalRowIndex++;
      }
    }

    return rows;
  }

  Widget _buildZoomControls() {
    return Positioned(
      bottom: 60,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.primaryYellow, size: 24),
              onPressed: _zoomIn,
              tooltip: 'Zoom In',
            ),
            Container(
              width: 40,
              height: 1,
              color: Colors.grey[300],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primaryYellow, size: 24),
              onPressed: _resetZoom,
              tooltip: 'Reset Zoom',
            ),
            Container(
              width: 40,
              height: 1,
              color: Colors.grey[300],
            ),
            IconButton(
              icon: const Icon(Icons.remove, color: AppColors.primaryYellow, size: 24),
              onPressed: _zoomOut,
              tooltip: 'Zoom Out',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          Column(
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
                  padding: const EdgeInsets.fromLTRB(16, 50, 16, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _timeTableTitle.isNotEmpty ? _timeTableTitle : 'Time Table',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),

              // Main Content - Table
              Expanded(
                child: _isLoading
                    ? _buildSkeletonLoader()
                    : SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height,
                          ),
                          child: IntrinsicHeight(
                            child: _errorMessage.isNotEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24),
                                          child: Text(
                                            _errorMessage,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textGrey,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: _fetchTimeTable,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Retry'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primaryYellow,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _timeTableDays.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.schedule_outlined,
                                              size: 64,
                                              color: Colors.grey[400],
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'No time table available',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Your time table will appear here',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.textGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : RefreshIndicator(
                                        onRefresh: _fetchTimeTable,
                                        color: AppColors.primaryYellow,
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: _buildDataTable(),
                                        ),
                                      ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          
          if (!_isLoading && _timeTableDays.isNotEmpty && _errorMessage.isEmpty)
            _buildZoomControls(),
        ],
      ),
    );
  }
}

// Time Table Day Model
class TimeTableDay {
  final int dayNumber;
  final String date;
  final List<TimeTableEntry> entries;

  TimeTableDay({
    required this.dayNumber,
    required this.date,
    required this.entries,
  });

  factory TimeTableDay.fromJson(Map<String, dynamic> json) {
    return TimeTableDay(
      dayNumber: json['day_number'] ?? 0,
      date: json['date'] ?? '',
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => TimeTableEntry.fromJson(e))
              .toList() ??
          [],
    );
  }
}

// Time Table Entry Model
class TimeTableEntry {
  final String subjectTitle;
  final String? sectionTitle;
  final List<String> chapterTitles;
  final List<String> topicTitles;
  final String? markedQuestions;
  final String? remark;

  TimeTableEntry({
    required this.subjectTitle,
    this.sectionTitle,
    required this.chapterTitles,
    required this.topicTitles,
    this.markedQuestions,
    this.remark,
  });

  String get displaySubject {
    if (sectionTitle != null && sectionTitle!.isNotEmpty) {
      return sectionTitle!;
    }
    return subjectTitle;
  }

  factory TimeTableEntry.fromJson(Map<String, dynamic> json) {
    return TimeTableEntry(
      subjectTitle: json['subject_title'] ?? '',
      sectionTitle: json['section_title'],
      chapterTitles: (json['chapter_titles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      topicTitles: (json['topic_titles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      markedQuestions: json['marked_questions'],
      remark: json['remark'],
    );
  }
}

// Curved Header Clipper
class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 25);
    
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 25,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}