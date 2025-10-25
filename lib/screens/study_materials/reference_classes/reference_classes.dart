import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../service/api_config.dart';
import '../../../../service/auth_service.dart';
import '../../../../common/theme_color.dart';

class VideoClassesScreen extends StatefulWidget {
  const VideoClassesScreen({super.key});

  @override
  State<VideoClassesScreen> createState() => _VideoClassesScreenState();
}

class _VideoClassesScreenState extends State<VideoClassesScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  String? _subcourseId;
  String _studentType = ''; // Added student type

  // Navigation state
  String _currentPage = 'videos'; // videos only now

  // Data lists
  List<dynamic> _videos = [];
  List<dynamic> _filteredVideos = [];

  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final AuthService _authService = AuthService();
  late Box<VideoWatchingRecord> _videoRecordsBox;
  bool _hiveInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHive();
    _searchController.addListener(_filterVideos);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeHive() async {
    if (!_hiveInitialized) {
      try {
        if (!Hive.isAdapterRegistered(1)) {
          Hive.registerAdapter(VideoWatchingRecordAdapter());
        }
        
        if (!Hive.isBoxOpen('video_records_box')) {
          _videoRecordsBox = await Hive.openBox<VideoWatchingRecord>('video_records_box');
        } else {
          _videoRecordsBox = Hive.box<VideoWatchingRecord>('video_records_box');
        }
        
        _hiveInitialized = true;
        debugPrint('✅ Hive initialized successfully for video records');
      } catch (e) {
        debugPrint('❌ Error initializing Hive: $e');
        try {
          _videoRecordsBox = Hive.box<VideoWatchingRecord>('video_records_box');
          _hiveInitialized = true;
          debugPrint('✅ Using existing Hive box for video records');
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box: $e');
        }
      }
    }
    
    _initializeData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Only send data for online students
    if (_studentType.toLowerCase() == 'online') {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        _sendStoredVideoDataToAPI(); // Fire and forget
      }
    }
  }

  // Load student type from SharedPreferences
  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _studentType = prefs.getString('profile_student_type') ?? '';
      });
      debugPrint('Student Type loaded: $_studentType');
    } catch (e) {
      debugPrint('Error loading student type: $e');
    }
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
    await _loadStudentType(); // Load student type
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _loadDataFromSharedPreferences();
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

  Future<void> _loadDataFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        _subcourseId = prefs.getString('profile_subcourse_id') ?? '';
      });

      // Directly fetch videos since we removed the course page
      if (_subcourseId != null && _subcourseId!.isNotEmpty) {
        await _fetchVideos();
      } else {
        setState(() {
          _isLoading = false;
        });
        _showError('Subcourse ID not found');
      }

    } catch (e) {
      debugPrint('Error loading data from SharedPreferences: $e');
      _showError('Failed to load video classes data: $e');
      setState(() {
        _isLoading = false;
      });
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

  Future<void> _fetchVideos() async {
    if (_subcourseId == null || _accessToken == null || _accessToken!.isEmpty) {
      _showError('Required data not available');
      return;
    }

    setState(() => _isLoading = true);

    final client = _createHttpClientWithCustomCert();

    try {
      String encodedId = Uri.encodeComponent(_subcourseId!);
      final response = await client
          .get(
            Uri.parse('${ApiConfig.currentBaseUrl}/api/notes/list_referencelinks/?subcourse_id=$encodedId'),
            headers: _getAuthHeaders(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] ?? false) {
          setState(() {
            _videos = data['reference_links'] ?? [];
            _filteredVideos = List.from(_videos);
            _isLoading = false;
          });
        } else {
          _showError(data['message'] ?? 'Failed to fetch videos');
        }
      } else if (response.statusCode == 401) {
        _handleTokenExpiration();
      } else {
        _showError('Failed to fetch videos: ${response.statusCode}');
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
      _showError('Error fetching videos: $e');
      setState(() => _isLoading = false);
    } finally {
      client.close();
    }
  }

  void _filterVideos() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredVideos = List.from(_videos);
      } else {
        _filteredVideos = _videos.where((video) {
          final title = video['title']?.toString().toLowerCase() ?? '';
          return title.contains(query);
        }).toList();
      }
    });
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

  Future<bool> _hasStoredVideoData() async {
    try {
      return _videoRecordsBox.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking stored video data: $e');
      return false;
    }
  }

  Future<void> _sendStoredVideoDataToAPI() async {
    // Only send data for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('Student type is $_studentType - skipping video data collection');
      return;
    }

    try {
      final allRecords = _videoRecordsBox.values.toList();
      
      if (allRecords.isEmpty) {
        debugPrint('No stored video watching data found to send');
        return;
      }

      debugPrint('=== SENDING ALL STORED VIDEO WATCHING DATA TO API ===');
      debugPrint('Total records to send: ${allRecords.length}');

      List<Map<String, dynamic>> allVideoData = [];

      for (final record in allRecords) {
        final watchedMinutes = double.parse((record.watchedTime / 60).toStringAsFixed(2));
        
        final videoData = {
          'encrypted_referencelink_id': record.encryptedReferencelinkId,
          'watched_time': watchedMinutes,
          'watched_date': record.watchedDate,
        };
        allVideoData.add(videoData);
        
        debugPrint('Prepared record for encrypted_referencelink_id: ${record.encryptedReferencelinkId}');
        debugPrint('   - Watched time: ${record.watchedTime} seconds = $watchedMinutes minutes');
      }

      if (allVideoData.isEmpty) {
        debugPrint('No valid records to send');
        return;
      }

      final requestBody = {
        'referencelinks': allVideoData,
      };

      debugPrint('REQUEST:');
      debugPrint('Endpoint: /api/performance/add_readed_referencelink/');
      debugPrint('Method: POST');
      debugPrint('Authorization: Bearer $_accessToken');
      debugPrint('Request Body:');
      debugPrint(const JsonEncoder.withIndent('  ').convert(requestBody));

      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      final apiUrl = '${ApiConfig.baseUrl}/api/performance/add_readed_referencelink/';

      debugPrint('Full URL: $apiUrl');

      // Fire and forget - don't await the response
      httpClient.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
          ...ApiConfig.commonHeaders,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30)).then((response) {
        debugPrint('\nRESPONSE RECEIVED (async):');
        debugPrint('Status Code: ${response.statusCode}');
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✓ All video watching data sent successfully to API');
          _clearStoredVideoData(); // Clear data only on success
        } else {
          debugPrint('✗ Failed to send video watching data. Status: ${response.statusCode}');
          // Don't clear data on failure, it will be retried later
        }
      }).catchError((error) {
        debugPrint('✗ Error sending stored video records to API: $error');
        // Don't clear data on error, it will be retried later
      });

      debugPrint('=== API CALL INITIATED (fire and forget) ===\n');

    } catch (e) {
      debugPrint('✗ Error preparing API call: $e');
    }
  }

  Future<void> _clearStoredVideoData() async {
    try {
      await _videoRecordsBox.clear();
      debugPrint('✓ All stored video watching data cleared');
    } catch (e) {
      debugPrint('Error clearing stored video watching data: $e');
    }
  }

  Future<bool> _handleDeviceBackButton() async {
    // Only check for stored data for online students
    if (_studentType.toLowerCase() == 'online') {
      final hasData = await _hasStoredVideoData();
      if (hasData) {
        // Fire and forget - don't wait for response
        _sendStoredVideoDataToAPI();
      }
    }
    // Always return true to allow immediate navigation
    return true;
  }

  void _handleBackNavigation() async {
    // Only check for stored data for online students
    if (_studentType.toLowerCase() == 'online') {
      final hasData = await _hasStoredVideoData();
      if (hasData) {
        // Fire and forget - don't wait for response
        _sendStoredVideoDataToAPI();
      }
    }
    // Navigate back immediately
    if (mounted) {
      Navigator.pop(context);
    }
  }

  String _getAppBarTitle() {
    return _isSearching ? 'Search Videos' : 'Video Classes';
  }

  String? _extractYouTubeId(String url) {
    try {
      final regex = RegExp(
        r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
        caseSensitive: false,
      );
      final match = regex.firstMatch(url);
      return (match != null && match.groupCount >= 7) ? match.group(7) : null;
    } catch (e) {
      debugPrint('Error extracting YouTube ID: $e');
      return null;
    }
  }

  String _getYouTubeThumbnail(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  void _openVideo(String url, String title, String encryptedReferencelinkId) {
    final videoId = _extractYouTubeId(url);
    if (videoId != null && videoId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(
            videoId: videoId, 
            title: title,
            encryptedReferencelinkId: encryptedReferencelinkId,
            enableWatchingData: _studentType.toLowerCase() == 'online', // Pass student type check
          ),
        ),
      );
    } else {
      _launchExternalUrl(url);
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showError('Invalid URL');
      return;
    }
    if (!await canLaunchUrl(uri)) {
      _showError('Cannot open link');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Failed to open link: $e');
    }
  }

  String _formatDate(String dateString) {
    try {
      if (dateString.isEmpty) return 'Unknown date';

      final DateTime date = DateTime.parse(dateString);
      final DateTime now = DateTime.now();
      final Duration difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '$weeks week${weeks > 1 ? 's' : ''} ago';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return '$months month${months > 1 ? 's' : ''} ago';
      } else {
        final years = (difference.inDays / 365).floor();
        return '$years year${years > 1 ? 's' : ''} ago';
      }
    } catch (e) {
      try {
        final parts = dateString.split('T')[0].split('-');
        if (parts.length == 3) {
          return '${parts[2]}/${parts[1]}/${parts[0]}';
        }
      } catch (e) {
        // If all else fails
      }
      return dateString.isNotEmpty ? dateString : 'Unknown date';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }
        
        // This will handle the back navigation immediately
        final shouldPop = await _handleDeviceBackButton();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Stack(
          children: [
            // Gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryYellow.withOpacity(0.08),
                    AppColors.backgroundLight,
                    Colors.white,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            
            // Main content
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
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button and title row
                        Row(
                          children: [
                            IconButton(
                              onPressed: _handleBackNavigation,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getAppBarTitle(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (!_isSearching)
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isSearching = true;
                                  });
                                },
                                icon: const Icon(
                                  Icons.search_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              )
                            else
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isSearching = false;
                                    _searchController.clear();
                                  });
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                              ),
                               SizedBox(height: 16),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildVideosPage(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideosPage() {
    return Column(
      children: [
        if (_isSearching)
          Container(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search videos by title...',
                prefixIcon: const Icon(Icons.search, color: AppColors.primaryYellow),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.primaryYellow.withOpacity(0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primaryYellow,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

        Expanded(
          child: _buildVideosList(),
        ),
      ],
    );
  }

  Widget _buildVideosList() {
    if (_filteredVideos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryYellow.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _searchController.text.isNotEmpty ? Icons.search_off_rounded : Icons.video_library_rounded,
                  size: 60,
                  color: AppColors.primaryYellow.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _searchController.text.isNotEmpty ? 'No videos found' : 'No videos available',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchController.text.isNotEmpty
                    ? 'Try searching with different keywords'
                    : 'Video classes will be added soon',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            if (!_isSearching) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Video Classes',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Available video lectures for your course',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_filteredVideos.length} video${_filteredVideos.length != 1 ? 's' : ''} available',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey400,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
            // Videos List
            Column(
              children: _filteredVideos.map((video) => _buildVideoCard(
                videoId: video['id']?.toString() ?? '',
                title: video['title']?.toString() ?? 'Untitled Video',
                url: video['url']?.toString() ?? '',
                addedAt: video['added_at']?.toString() ?? '',
                encryptedReferencelinkId: video['id']?.toString() ?? '',
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard({
    required String videoId,
    required String title,
    required String url,
    required String addedAt,
    required String encryptedReferencelinkId,
  }) {
    final youtubeId = _extractYouTubeId(url);
    final thumbnailUrl = youtubeId != null ? _getYouTubeThumbnail(youtubeId) : null;

    return GestureDetector(
      onTap: () => _openVideo(url, title, encryptedReferencelinkId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryYellow.withOpacity(0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Thumbnail - Left side (reduced size)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80, // Reduced from 120
                  height: 60, // Reduced from 90
                  child: thumbnailUrl != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              thumbnailUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 24),
                                  ),
                                );
                              },
                            ),
                            Container(
                              color: Colors.black.withOpacity(0.25),
                            ),
                            Center(
                              child: Container(
                                height: 32, // Reduced size
                                width: 32, // Reduced size
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 255, 106, 0).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 20, // Reduced size
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.videocam_off,
                                size: 24, // Reduced size
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 16),

              // Video details - Right side
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 6),

                    // Added date and play indicator
                    Row(
                      children: [
                        if (addedAt.isNotEmpty)
                          Text(
                            _formatDate(addedAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.grey400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (addedAt.isNotEmpty) const SizedBox(width: 8),
                       
                        const SizedBox(width: 4),
                       
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Play button with light blue color
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen video player page using youtube_player_iframe
class VideoPlayerPage extends StatefulWidget {
  final String videoId;
  final String title;
  final String encryptedReferencelinkId;
  final bool enableWatchingData; // New parameter to control data collection

  const VideoPlayerPage({
    Key? key,
    required this.videoId,
    required this.title,
    required this.encryptedReferencelinkId,
    required this.enableWatchingData,
  }) : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late YoutubePlayerController _controller;
  bool _isLoading = true;
  late Box<VideoWatchingRecord> _videoRecordsBox;
  bool _hiveInitialized = false;
  
  // Timer tracking variables
  Timer? _watchTimer;
  int _totalWatchedSeconds = 0;
  DateTime? _videoStartTime;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeHive();
    _initializeController();
    
    // Set preferred orientations to allow both portrait and landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initializeHive() async {
    if (!_hiveInitialized) {
      try {
        if (!Hive.isBoxOpen('video_records_box')) {
          _videoRecordsBox = await Hive.openBox<VideoWatchingRecord>('video_records_box');
        } else {
          _videoRecordsBox = Hive.box<VideoWatchingRecord>('video_records_box');
        }
        _hiveInitialized = true;
        debugPrint('✅ Hive initialized for video player');
      } catch (e) {
        debugPrint('❌ Error initializing Hive in video player: $e');
        try {
          _videoRecordsBox = Hive.box<VideoWatchingRecord>('video_records_box');
          _hiveInitialized = true;
        } catch (e) {
          debugPrint('❌ Failed to use existing Hive box in video player: $e');
        }
      }
    }
  }

  void _initializeController() {
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        mute: false,
        enableCaption: true,
        loop: false,
        showVideoAnnotations: false,
        strictRelatedVideos: true,
      ),
    );

    // Load the video after controller is created
    _controller.loadVideoById(videoId: widget.videoId);

    // Listen for player state changes
    _controller.listen((event) {
      // Handle loading state
      if (event.playerState == PlayerState.playing || 
          event.playerState == PlayerState.paused ||
          event.playerState == PlayerState.cued) {
        if (_isLoading) {
          setState(() {
            _isLoading = false;
          });
        }
      }

      // Handle video state changes for timer tracking (only if enabled)
      if (widget.enableWatchingData) {
        _handleVideoStateChange(event.playerState);
      }
    });
  }

  void _handleVideoStateChange(PlayerState state) {
    switch (state) {
      case PlayerState.playing:
        if (!_isPlaying) {
          _startWatchingTimer();
        }
        break;
      case PlayerState.paused:
        if (_isPlaying) {
          _pauseWatchingTimer();
        }
        break;
      case PlayerState.ended:
      case PlayerState.unStarted:
      case PlayerState.buffering:
        _stopWatchingTimer();
        break;
      default:
        break;
    }
  }

  void _startWatchingTimer() {
    _isPlaying = true;
    _videoStartTime ??= DateTime.now();
    
    _watchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _totalWatchedSeconds++;
      });
    });
    
    debugPrint('▶️ Video playing - timer started');
    debugPrint('📹 encrypted_referencelink_id: ${widget.encryptedReferencelinkId}');
  }

  void _pauseWatchingTimer() {
    _isPlaying = false;
    _watchTimer?.cancel();
    debugPrint('⏸️ Video paused - timer stopped at $_totalWatchedSeconds seconds');
  }

  void _stopWatchingTimer() {
    _isPlaying = false;
    _watchTimer?.cancel();
    if (widget.enableWatchingData) {
      _saveWatchingRecord();
    }
    debugPrint('⏹️ Video stopped - total watched: $_totalWatchedSeconds seconds');
  }

  Future<void> _saveWatchingRecord() async {
    if (_totalWatchedSeconds > 0 && _hiveInitialized && widget.enableWatchingData) {
      try {
        final now = DateTime.now();
        final currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        
        // Check if a record with same encrypted_referencelink_id and watched_date exists
        VideoWatchingRecord? existingRecord;
        dynamic existingKey;
        
        for (var key in _videoRecordsBox.keys) {
          final record = _videoRecordsBox.get(key);
          if (record != null && 
              record.encryptedReferencelinkId == widget.encryptedReferencelinkId &&
              record.watchedDate == currentDate) {
            existingRecord = record;
            existingKey = key;
            break;
          }
        }
        
        if (existingRecord != null && existingKey != null) {
          // Update existing record by adding watched time
          final updatedRecord = VideoWatchingRecord(
            encryptedReferencelinkId: widget.encryptedReferencelinkId,
            watchedTime: existingRecord.watchedTime + _totalWatchedSeconds,
            watchedDate: currentDate,
            createdAt: existingRecord.createdAt, // Keep original creation time
          );
          
          await _videoRecordsBox.put(existingKey, updatedRecord);
          
          debugPrint('✅ Video watching record UPDATED in Hive:');
          debugPrint('   - encrypted_referencelink_id: ${widget.encryptedReferencelinkId}');
          debugPrint('   - previous watched_time: ${existingRecord.watchedTime} seconds');
          debugPrint('   - added watched_time: $_totalWatchedSeconds seconds');
          debugPrint('   - total watched_time: ${updatedRecord.watchedTime} seconds');
          debugPrint('   - watched_date: $currentDate');
        } else {
          // Create new record
          final record = VideoWatchingRecord(
            encryptedReferencelinkId: widget.encryptedReferencelinkId,
            watchedTime: _totalWatchedSeconds,
            watchedDate: currentDate,
            createdAt: now,
          );

          await _videoRecordsBox.add(record);
          
          debugPrint('✅ Video watching record CREATED in Hive:');
          debugPrint('   - encrypted_referencelink_id: ${widget.encryptedReferencelinkId}');
          debugPrint('   - watched_time: $_totalWatchedSeconds seconds');
          debugPrint('   - watched_date: $currentDate');
        }
      } catch (e) {
        debugPrint('❌ Error saving video watching record: $e');
      }
    }
  }

  @override
  void dispose() {
    // Stop timer and save record when leaving the player
    _stopWatchingTimer();
    
    // Restore portrait orientation and system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        // Removed the open in browser action button
      ),
      body: SafeArea(
        child: Column(
          children: [
            // YouTube Player
            Expanded(
              child: Container(
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    YoutubePlayer(
                      controller: _controller,
                      aspectRatio: 16 / 9,
                    ),
                    if (_isLoading)
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                      ),
                  ],
                ),
              ),
            ),

            // Video Info Section (simplified - only title)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    
    // Create a quadratic bezier curve for smooth bottom
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 30,
    );
    
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CurvedHeaderClipper oldClipper) => false;
}