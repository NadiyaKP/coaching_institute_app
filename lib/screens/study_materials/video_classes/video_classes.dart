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

  // Navigation state
  String _currentPage = 'course'; // course, videos
  String _courseName = '';
  String _subcourseName = '';

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
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _sendStoredVideoDataToAPI();
    }
  }

  Future<void> _initializeData() async {
    await _getAccessToken();
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
        _courseName = prefs.getString('profile_course') ?? 'Course';
        _subcourseName = prefs.getString('profile_subcourse') ?? 'Subcourse';
        _subcourseId = prefs.getString('profile_subcourse_id') ?? '';
      });

      setState(() {
        _isLoading = false;
      });

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
            _currentPage = 'videos';
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

  void _navigateBack() {
    setState(() {
      switch (_currentPage) {
        case 'videos':
          _currentPage = 'course';
          _videos.clear();
          _filteredVideos.clear();
          _searchController.clear();
          _isSearching = false;
          break;
      }
    });
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

      final response = await httpClient.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
          ...ApiConfig.commonHeaders,
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      debugPrint('\nRESPONSE:');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Headers: ${response.headers}');

      try {
        final responseJson = jsonDecode(response.body);
        debugPrint('Response Body:');
        debugPrint(const JsonEncoder.withIndent('  ').convert(responseJson));
      } catch (e) {
        debugPrint('Response Body: ${response.body}');
      }

      debugPrint('=== END BULK API CALL ===\n');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✓ All video watching data sent successfully to API');
        
        await _clearStoredVideoData();
        
      } else {
        debugPrint('✗ Failed to send video watching data. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('✗ Error sending stored video records to API: $e');
      debugPrint('=== END BULK API CALL (ERROR) ===\n');
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
    if (_currentPage == 'course') {
      final hasData = await _hasStoredVideoData();
      if (hasData) {
        _sendStoredVideoDataToAPI();
      }
      return true;
    } else {
      _navigateBack();
      return false;
    }
  }

  String _getAppBarTitle() {
    switch (_currentPage) {
      case 'course':
        return 'Video Classes';
      case 'videos':
        return _isSearching ? 'Search Videos' : 'Videos - $_subcourseName';
      default:
        return 'Video Classes';
    }
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
        
        final shouldPop = await _handleDeviceBackButton();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _getAppBarTitle(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          backgroundColor: AppColors.primaryYellow,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          leading: _currentPage != 'course'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _navigateBack,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    final hasData = await _hasStoredVideoData();
                    if (hasData) {
                      _sendStoredVideoDataToAPI();
                    }
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  },
                ),
          actions: _currentPage == 'videos'
              ? [
                  if (!_isSearching)
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        setState(() {
                          _isSearching = true;
                        });
                      },
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _isSearching = false;
                          _searchController.clear();
                        });
                      },
                    ),
                ]
              : null,
        ),
        body: Container(
          decoration: BoxDecoration(
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
                  ),
                )
              : _buildCurrentPage(),
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case 'course':
        return _buildCoursePage();
      case 'videos':
        return _buildVideosPage();
      default:
        return _buildCoursePage();
    }
  }

  Widget _buildCoursePage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Your Enrolled Course',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 30),

            Card(
              elevation: 8,
              shadowColor: AppColors.primaryYellow.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.white,
                      AppColors.primaryYellow.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 60,
                          width: 60,
                          decoration: BoxDecoration(
                            color: AppColors.primaryYellow.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school,
                            size: 32,
                            color: AppColors.primaryYellow,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _courseName.isNotEmpty ? _courseName : 'Course',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Course',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    InkWell(
                      onTap: _subcourseId != null ? _fetchVideos : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryYellow.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryYellow.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.play_circle_fill,
                              color: AppColors.primaryYellow,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _subcourseName.isNotEmpty ? _subcourseName : 'Subcourse',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Tap to view video classes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: AppColors.primaryYellow,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isNotEmpty ? Icons.search_off : Icons.video_library_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty ? 'No videos found' : 'No videos available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Try searching with different keywords'
                  : 'Video classes will be added soon',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isSearching) ...[
            const SizedBox(height: 20),
            const Text(
              'Video Classes',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Video lectures for $_subcourseName',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
          ],
          ..._filteredVideos.map((video) => _buildVideoCard(
                videoId: video['id']?.toString() ?? '',
                title: video['title']?.toString() ?? 'Untitled Video',
                url: video['url']?.toString() ?? '',
                addedAt: video['added_at']?.toString() ?? '',
                encryptedReferencelinkId: video['id']?.toString() ?? '',
              )).toList(),
        ],
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: AppColors.primaryYellow.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openVideo(url, title, encryptedReferencelinkId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.white,
                AppColors.primaryYellow.withOpacity(0.03),
              ],
            ),
          ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail - Left side (smaller size)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 90,
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
                                  child: Icon(Icons.broken_image, size: 30),
                                ),
                              );
                            },
                          ),
                          Container(
                            color: Colors.black.withOpacity(0.25),
                          ),
                          Center(
                            child: Container(
                              height: 40,
                              width: 40,
                              decoration: BoxDecoration(
                                color:  Color.fromARGB(255, 255, 106, 0).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 28,
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
                              size: 30,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(width: 12),

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
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // Added date
                  if (addedAt.isNotEmpty)
                    Text(
                      'Added: ${_formatDate(addedAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),

                  const SizedBox(height: 6),

                  // Tap to play
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_fill,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tap to play video',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Video Class tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryYellow.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Video Class',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
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

  const VideoPlayerPage({
    Key? key,
    required this.videoId,
    required this.title,
    required this.encryptedReferencelinkId,
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

      // Handle video state changes for timer tracking
      _handleVideoStateChange(event.playerState);
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
      // Handle any other states if needed
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
    _saveWatchingRecord();
    debugPrint('⏹️ Video stopped - total watched: $_totalWatchedSeconds seconds');
  }
Future<void> _saveWatchingRecord() async {
  if (_totalWatchedSeconds > 0 && _hiveInitialized) {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white),
            onPressed: () async {
              final url = 'https://youtu.be/${widget.videoId}';
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cannot open video externally')),
                  );
                }
              }
            },
          )
        ],
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
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_totalWatchedSeconds > 0)
                    Text(
                      'Watched: $_totalWatchedSeconds seconds',
                      style: TextStyle(
                        fontSize: 14, 
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Video ID: ${widget.encryptedReferencelinkId}',
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