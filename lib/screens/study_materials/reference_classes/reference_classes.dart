import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import '../../../../service/api_config.dart';
import '../../../../service/auth_service.dart';
import '../../../../common/theme_color.dart';
import '../../../service/http_interceptor.dart';

class ReferenceClassesScreen extends StatefulWidget {
  const ReferenceClassesScreen({super.key});

  @override
  State<ReferenceClassesScreen> createState() => _ReferenceClassesScreenState();
}

class _ReferenceClassesScreenState extends State<ReferenceClassesScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _accessToken;
  String? _subcourseId;
  String _studentType = '';

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
    
    if (_studentType.toLowerCase() == 'online') {
      if (state == AppLifecycleState.paused || 
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        _sendStoredVideoDataToAPI();
      }
    }
  }

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
    await _loadStudentType();
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
      final response = await globalHttpClient.get(
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
          debugPrint('✅ Fetched ${_videos.length} videos');
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

      debugPrint('Request Body: ${const JsonEncoder.withIndent('  ').convert(requestBody)}');

      final client = ApiConfig.createHttpClient();
      final httpClient = IOClient(client);

      final apiUrl = '${ApiConfig.baseUrl}/api/performance/add_readed_referencelink/';

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
        debugPrint('Status Code: ${response.statusCode}');
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint('✓ All video watching data sent successfully to API');
          _clearStoredVideoData();
        } else {
          debugPrint('✗ Failed to send video watching data. Status: ${response.statusCode}');
        }
      }).catchError((error) {
        debugPrint('✗ Error sending stored video records to API: $error');
      });

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
    if (_studentType.toLowerCase() == 'online') {
      final hasData = await _hasStoredVideoData();
      if (hasData) {
        _sendStoredVideoDataToAPI();
      }
    }
    return true;
  }

  void _handleBackNavigation() async {
    if (_studentType.toLowerCase() == 'online') {
      final hasData = await _hasStoredVideoData();
      if (hasData) {
        _sendStoredVideoDataToAPI();
      }
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  String _getAppBarTitle() {
    return _isSearching ? 'Search Videos' : 'Reference Classes';
  }

  String? _extractYouTubeId(String url) {
    try {
      // Handle youtu.be short URLs
      if (url.contains('youtu.be/')) {
        final regex = RegExp(r'youtu\.be\/([a-zA-Z0-9_-]{11})');
        final match = regex.firstMatch(url);
        return match?.group(1);
      }
      
      // Handle youtube.com URLs
      if (url.contains('youtube.com') || url.contains('youtu.be')) {
        final regex = RegExp(r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})');
        final match = regex.firstMatch(url);
        return match?.group(1);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error extracting YouTube ID from $url: $e');
      return null;
    }
  }

  String _getYouTubeThumbnail(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  void _openVideo(String url, String title, String encryptedReferencelinkId) {
    final videoId = _extractYouTubeId(url);
    if (videoId != null && videoId.isNotEmpty) {
      debugPrint('🎬 Opening YouTube video: $videoId - $title');
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VideoPlayerPage(
            youtubeUrl: url,
            videoId: videoId, 
            title: title,
            encryptedReferencelinkId: encryptedReferencelinkId,
            enableWatchingData: _studentType.toLowerCase() == 'online', 
          ),
        ),
      );
    } else {
      _showError('Could not extract YouTube video ID from URL');
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
        if (didPop) return;
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
                      ? _buildSkeletalLoading()
                      : _buildVideosPage(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletalLoading() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Skeleton for header section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 180,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
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
                      Container(
                        width: 200,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Skeleton video cards
            Column(
              children: List.generate(6, (index) => _buildSkeletalVideoCard()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletalVideoCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Skeleton thumbnail
            Container(
              width: 80,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            
            // Skeleton text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            
            // Skeleton play button
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
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
                        'Reference Classes',
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

    debugPrint('Building video card: $title - YouTube ID: $youtubeId - Thumbnail: $thumbnailUrl');

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
              // Thumbnail 
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80, 
                  height: 60, 
                  child: thumbnailUrl != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              thumbnailUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: Colors.grey[300],
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                debugPrint('Error loading thumbnail: $error');
                                return Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 24, color: Colors.grey),
                                  ),
                                );
                              },
                            ),
                            Container(
                              color: Colors.black.withOpacity(0.3),
                            ),
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 32,
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
                                size: 24,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'No Thumbnail',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 16),

              // Video details 
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

                    // Added date
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
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Play button
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

/// Full-screen video player page
class VideoPlayerPage extends StatefulWidget {
  final String youtubeUrl;
  final String videoId;
  final String title;
  final String encryptedReferencelinkId;
  final bool enableWatchingData; 

  const VideoPlayerPage({
    Key? key,
    required this.youtubeUrl,
    required this.videoId,
    required this.title,
    required this.encryptedReferencelinkId,
    required this.enableWatchingData,
  }) : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
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
    _initializeVideo();
    
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
      }
    }
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('🔄 Initializing YouTube video: ${widget.videoId}');
      
      final yt = YoutubeExplode();
      
      // Get video stream manifest
      final streamManifest = await yt.videos.streamsClient.getManifest(widget.videoId);
      
      // Get the best muxed stream (video + audio)
      final streamInfo = streamManifest.muxed.withHighestBitrate();
      
      if (streamInfo == null) {
        throw Exception('No suitable video stream found');
      }
      
      final streamUrl = streamInfo.url.toString();
      debugPrint('🎬 Video stream URL obtained: ${streamUrl.substring(0, 100)}...');

      // Initialize video player
      _videoPlayerController = VideoPlayerController.network(streamUrl);
      
      await _videoPlayerController!.initialize();

      // Set up listener for video state changes
      _videoPlayerController!.addListener(() {
        if (widget.enableWatchingData) {
          _handleVideoStateChange(_videoPlayerController!.value);
        }
      });

      // Initialize Chewie controller
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primaryYellow,
          handleColor: AppColors.primaryYellow,
          backgroundColor: Colors.grey.shade700,
          bufferedColor: Colors.grey.shade500,
        ),
        autoInitialize: true,
      );

      setState(() {
        _isLoading = false;
      });

      debugPrint('✅ Video player initialized successfully');

    } catch (e) {
      debugPrint('❌ Error loading video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        _showError('Failed to load video: $e');
      }
    }
  }

  void _handleVideoStateChange(VideoPlayerValue value) {
    if (value.isPlaying && !_isPlaying) {
      _startWatchingTimer();
    } else if (!value.isPlaying && _isPlaying) {
      _pauseWatchingTimer();
    }
    
    // Check if video ended
    if (value.position >= value.duration && value.duration > Duration.zero) {
      _stopWatchingTimer();
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
    
    debugPrint('▶ Video playing - timer started');
  }

  void _pauseWatchingTimer() {
    _isPlaying = false;
    _watchTimer?.cancel();
    debugPrint('⏸ Video paused - timer stopped at $_totalWatchedSeconds seconds');
  }

  void _stopWatchingTimer() {
    _isPlaying = false;
    _watchTimer?.cancel();
    if (widget.enableWatchingData) {
      _saveWatchingRecord();
    }
    debugPrint('⏹ Video stopped - total watched: $_totalWatchedSeconds seconds');
  }

  Future<void> _saveWatchingRecord() async {
    if (_totalWatchedSeconds > 0 && _hiveInitialized && widget.enableWatchingData) {
      try {
        final now = DateTime.now();
        final currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        
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
          final updatedRecord = VideoWatchingRecord(
            encryptedReferencelinkId: widget.encryptedReferencelinkId,
            watchedTime: existingRecord.watchedTime + _totalWatchedSeconds,
            watchedDate: currentDate,
            createdAt: existingRecord.createdAt,
          );
          
          await _videoRecordsBox.put(existingKey, updatedRecord);
          debugPrint('✅ Video watching record UPDATED in Hive');
        } else {
          final record = VideoWatchingRecord(
            encryptedReferencelinkId: widget.encryptedReferencelinkId,
            watchedTime: _totalWatchedSeconds,
            watchedDate: currentDate,
            createdAt: now,
          );

          await _videoRecordsBox.add(record);
          debugPrint('✅ Video watching record CREATED in Hive');
        }
      } catch (e) {
        debugPrint('❌ Error saving video watching record: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _initializeVideo,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _stopWatchingTimer();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
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
        actions: [
          if (_hasError)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _initializeVideo,
              tooltip: 'Retry',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Video Player Section
            Expanded(
              child: Container(
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_chewieController != null && 
                        _videoPlayerController != null && 
                        _videoPlayerController!.value.isInitialized)
                      Chewie(controller: _chewieController!)
                    else if (_isLoading)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading video...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    else if (_hasError)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 50,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Failed to load video',
                              style: TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _initializeVideo,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryYellow,
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Video Info Section 
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.enableWatchingData)
                    Text(
                      'Watched: $_totalWatchedSeconds seconds',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                ],
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