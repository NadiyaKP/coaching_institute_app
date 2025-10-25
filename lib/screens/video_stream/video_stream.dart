import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import 'package:coaching_institute_app/service/auth_service.dart';
import 'package:coaching_institute_app/service/api_config.dart';
import '../../common/theme_color.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoStreamScreen extends StatefulWidget {
  final String videoId;
  final String videoTitle;
  final String? videoDuration;

  const VideoStreamScreen({
    super.key,
    required this.videoId,
    required this.videoTitle,
    this.videoDuration,
  });

  @override
  State<VideoStreamScreen> createState() => _VideoStreamScreenState();
}

class _VideoStreamScreenState extends State<VideoStreamScreen> {
  BetterPlayerController? _betterPlayerController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  String? _accessToken;
  String _studentType = ''; // Added student type
  final AuthService _authService = AuthService();

  // Event tracking variables
  List<Map<String, dynamic>> _events = [];
  double _currentPlaybackSpeed = 1.0;
  Duration? _lastPosition;
  bool _isFirstPlay = true;
  bool _videoCompletedInThisSession = false;
  bool _hasEventsSaved = false;
  
  // Seek tracking variables
  bool _isSeeking = false;
  Duration? _seekStartPosition;
  DateTime? _lastSeekTime;
  Duration? _pendingSeekEndPosition;
  
  // Event deduplication variables
  String? _lastEventType;
  Duration? _lastEventPosition;
  DateTime? _lastEventTime;
  
  // Position tracking for seek detection
  Duration? _previousPosition;
  DateTime? _lastPositionCheckTime;

  @override
  void initState() {
    super.initState();
    _loadStudentType().then((_) {
      _initializeVideo();
    });
  }

  // Load student type from SharedPreferences
  Future<void> _loadStudentType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _studentType = prefs.getString('profile_student_type') ?? '';
      });
      debugPrint('🎬 Student Type loaded in video stream: $_studentType');
    } catch (e) {
      debugPrint('Error loading student type in video stream: $e');
    }
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });

      _accessToken = await _authService.getAccessToken();

      if (_accessToken == null || _accessToken!.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Access token not found. Please login again.';
          _isLoading = false;
        });
        return;
      }

      String videoUrl = '${ApiConfig.baseUrl}/api/videos/stream/${widget.videoId}/';

      debugPrint('🎬 Initializing BetterPlayer...');
      debugPrint('Video URL: $videoUrl');
      debugPrint('Student Type: $_studentType');
      debugPrint('Event Tracking Enabled: ${_studentType.toLowerCase() == 'online'}');

      BetterPlayerDataSource dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        videoUrl,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
      );

      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          fit: BoxFit.contain,
          allowedScreenSleep: false,
          autoDispose: true,
          aspectRatio: 16 / 9,
          handleLifecycle: true,
          fullScreenByDefault: false,
          errorBuilder: (context, errorMessage) {
            return _buildErrorContent(errorMessage);
          },
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            enableFullscreen: true,
            enableProgressText: true,
            enablePlaybackSpeed: true,
            enableSkips: true,
            forwardSkipTimeInMilliseconds: 10000,
            backwardSkipTimeInMilliseconds: 10000,
            loadingColor: AppColors.primaryYellow,
          ),
        ),
        betterPlayerDataSource: dataSource,
      );

      // Add event listeners only for online students
      if (_studentType.toLowerCase() == 'online') {
        _betterPlayerController!.addEventsListener(_handleVideoEvent);
        
        // Add position listener to detect seeks (including skip buttons)
        _betterPlayerController!.videoPlayerController?.addListener(_onPositionChanged);
        
        debugPrint('🎬 Event tracking ENABLED for online student');
      } else {
        debugPrint('🎬 Event tracking DISABLED for student type: $_studentType');
      }

      setState(() {
        _isLoading = false;
      });

      debugPrint('✅ BetterPlayer ready to play');
    } catch (e) {
      debugPrint('❌ Exception during video initialization: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load video: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onPositionChanged() {
    // Only track position changes for online students
    if (_studentType.toLowerCase() != 'online') return;
    
    final controller = _betterPlayerController?.videoPlayerController;
    if (controller == null) return;
    
    final currentPosition = controller.value.position;
    final isPlaying = controller.value.isPlaying;
    final now = DateTime.now();
    
    // Check if this is a significant position jump (seek detection)
    if (_previousPosition != null && _lastPositionCheckTime != null) {
      final timeDiff = now.difference(_lastPositionCheckTime!).inMilliseconds;
      final positionDiff = (currentPosition.inSeconds - _previousPosition!.inSeconds).abs();
      
      // If position jumped more than expected for normal playback, it's likely a seek
      // Expected change = (timeDiff/1000) * playbackSpeed, allow 2 second tolerance
      final expectedChange = (timeDiff / 1000) * _currentPlaybackSpeed;
      
      if (positionDiff > expectedChange + 2 && timeDiff < 1000) {
        // This is a seek (including skip buttons and scrubbing)
        if (!_isSeeking) {
          // Start of a new seek operation
          debugPrint('🔍 Seek started: from ${_formatTime(_previousPosition!)}');
          _handleSeekStart(_previousPosition, _currentPlaybackSpeed);
        }
        
        // Update the pending end position (will be updated multiple times during scrubbing)
        _pendingSeekEndPosition = currentPosition;
        _lastSeekTime = now;
        
        debugPrint('🔍 Seek in progress: to ${_formatTime(currentPosition)}');
      } else if (_isSeeking && timeDiff > 500) {
        // No more position jumps for 500ms - seek operation completed
        if (_pendingSeekEndPosition != null) {
          debugPrint('🔍 Seek completed: finalizing to ${_formatTime(_pendingSeekEndPosition!)}');
          _finalizeSeekEvent(_pendingSeekEndPosition!, _currentPlaybackSpeed);
          _pendingSeekEndPosition = null;
        }
      }
    }
    
    _previousPosition = currentPosition;
    _lastPositionCheckTime = now;
  }

  void _handleVideoEvent(BetterPlayerEvent event) {
    // Only handle events for online students
    if (_studentType.toLowerCase() != 'online') return;
    
    final currentPosition = _betterPlayerController?.videoPlayerController?.value.position;
    final currentSpeed = _betterPlayerController?.videoPlayerController?.value.speed ?? 1.0;

    if (event.betterPlayerEventType == BetterPlayerEventType.play) {
      debugPrint('📹 Video PLAY event');
      
      // Finalize any pending seek before recording play
      if (_isSeeking && _pendingSeekEndPosition != null) {
        _finalizeSeekEvent(_pendingSeekEndPosition!, currentSpeed);
        _pendingSeekEndPosition = null;
      }
      
      _addPlayEvent(currentPosition, currentSpeed);
      _isFirstPlay = false;
    } else if (event.betterPlayerEventType == BetterPlayerEventType.pause) {
      debugPrint('⏸️ Video PAUSE event');
      
      // Finalize any pending seek before recording pause
      if (_isSeeking && _pendingSeekEndPosition != null) {
        _finalizeSeekEvent(_pendingSeekEndPosition!, currentSpeed);
        _pendingSeekEndPosition = null;
      }
      
      _addPauseEvent(currentPosition, currentSpeed);
    } else if (event.betterPlayerEventType == BetterPlayerEventType.seekTo) {
      debugPrint('⏩ Video SEEK event detected from BetterPlayer');
      // The position listener will handle the actual seek tracking
      // This event just confirms a seek started
      if (!_isSeeking && currentPosition != null) {
        _handleSeekStart(currentPosition, currentSpeed);
      }
    } else if (event.betterPlayerEventType == BetterPlayerEventType.setSpeed) {
      debugPrint('🎚️ Video SPEED change event');
      _handleSpeedChange(currentPosition, currentSpeed);
    } else if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      debugPrint('✅ Video FINISHED event (video completed)');
      _videoCompletedInThisSession = true;
      _addEndedEvent(currentPosition, currentSpeed);
    }
  }

  bool _shouldIgnoreEvent(String eventType, Duration? position) {
    if (_lastEventType == eventType && 
        _lastEventPosition != null && 
        position != null &&
        _lastEventTime != null) {
      
      final timeDiff = DateTime.now().difference(_lastEventTime!).inMilliseconds;
      final positionDiff = (position.inSeconds - _lastEventPosition!.inSeconds).abs();
      
      // Strict deduplication for play/pause: ignore events within 2 seconds at same position
      if (timeDiff < 2000 && positionDiff <= 1) {
        debugPrint('⏭️ Ignoring duplicate $eventType event (within 2s at position ${_formatTime(position)})');
        return true;
      }
    }
    
    // Special case: If last event was a seek and this is a play at the seek's new position
    // Check if we just recorded a seek event within the last 500ms to same position
    if (eventType == 'play' && _events.isNotEmpty) {
      final lastEvent = _events.last;
      if (lastEvent['event_type'] == 'seek' && _lastEventTime != null) {
        final timeSinceSeek = DateTime.now().difference(_lastEventTime!).inMilliseconds;
        if (timeSinceSeek < 500 && position != null) {
          // Check if play position matches seek's new_position
          final seekNewPosition = lastEvent['new_position'] as String;
          final playPosition = _formatTime(position);
          if (seekNewPosition == playPosition) {
            debugPrint('⏭️ Ignoring play event immediately after seek to same position');
            return true;
          }
        }
      }
    }
    
    return false;
  }

  void _updateLastEvent(String eventType, Duration? position) {
    _lastEventType = eventType;
    _lastEventPosition = position;
    _lastEventTime = DateTime.now();
  }

  void _handleSeekStart(Duration? currentPosition, double speed) {
    if (currentPosition == null) return;
    
    // Only record the start position if we're not already seeking
    if (!_isSeeking) {
      _isSeeking = true;
      _seekStartPosition = _lastPosition ?? currentPosition;
      _lastSeekTime = DateTime.now();
      
      debugPrint('🎯 SEEK STARTED: from=${_formatTime(_seekStartPosition!)}');
    }
  }

  void _finalizeSeekEvent(Duration newPosition, double speed) {
    if (_seekStartPosition == null) return;
    
    // Check if there was actual position change (threshold: 1 second)
    final positionDifference = (newPosition.inSeconds - _seekStartPosition!.inSeconds).abs();
    
    if (positionDifference >= 1) {
      // Check for duplicate seek event
      if (_shouldIgnoreEvent('seek', newPosition)) {
        _isSeeking = false;
        _seekStartPosition = null;
        return;
      }
      
      final oldTimeFormatted = _formatTime(_seekStartPosition!);
      final newTimeFormatted = _formatTime(newPosition);
      
      final event = {
        'event_type': 'seek',
        'old_position': oldTimeFormatted,
        'new_position': newTimeFormatted,
        'playback_speed': speed,
      };
      
      _events.add(event);
      _updateLastEvent('seek', newPosition);
      
      debugPrint('🎯 SEEK FINALIZED: from=$oldTimeFormatted to=$newTimeFormatted, speed=${speed}x');
    } else {
      debugPrint('⏭️ Seek ignored (position change < 1 second)');
    }
    
    _lastPosition = newPosition;
    _isSeeking = false;
    _seekStartPosition = null;
  }

  void _addPlayEvent(Duration? position, double speed) {
    if (position == null) return;
    
    if (_shouldIgnoreEvent('play', position)) return;
    
    final timeFormatted = _formatTime(position);
    
    final event = {
      'event_type': 'play',
      'time': timeFormatted,
      'playback_speed': speed,
    };
    
    _events.add(event);
    _lastPosition = position;
    _updateLastEvent('play', position);
    
    debugPrint('▶️ Added PLAY event: time=$timeFormatted, speed=${speed}x');
  }

  void _addPauseEvent(Duration? position, double speed) {
    if (position == null) return;
    
    if (_shouldIgnoreEvent('pause', position)) return;
    
    final timeFormatted = _formatTime(position);
    
    final event = {
      'event_type': 'pause',
      'time': timeFormatted,
      'playback_speed': speed,
    };
    
    _events.add(event);
    _lastPosition = position;
    _updateLastEvent('pause', position);
    
    debugPrint('⏸️ Added PAUSE event: time=$timeFormatted, speed=${speed}x');
  }

  void _handleSpeedChange(Duration? position, double newSpeed) {
    if (position == null) return;
    
    if (newSpeed != _currentPlaybackSpeed) {
      final timeFormatted = _formatTime(position);
      
      final event = {
        'event_type': 'ratechange',
        'time': timeFormatted,
        'playback_speed': newSpeed,
      };
      
      _events.add(event);
      _lastPosition = position;
      _updateLastEvent('ratechange', position);
      
      debugPrint('🎚️ Added RATECHANGE event: time=$timeFormatted, old_speed=${_currentPlaybackSpeed}x, new_speed=${newSpeed}x');
      
      _currentPlaybackSpeed = newSpeed;
    }
  }

  void _addEndedEvent(Duration? position, double speed) {
    if (position == null) return;
    
    if (_shouldIgnoreEvent('ended', position)) return;
    
    final timeFormatted = _formatTime(position);
    
    final event = {
      'event_type': 'ended',
      'time': timeFormatted,
      'playback_speed': speed,
    };
    
    _events.add(event);
    _updateLastEvent('ended', position);
    
    debugPrint('🏁 Added ENDED event: time=$timeFormatted, speed=${speed}x');
  }

  String _formatTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (minutes > 0) {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '0:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _saveEventsToHive() async {
    // Only save events for online students
    if (_studentType.toLowerCase() != 'online') {
      debugPrint('🎬 Student type is $_studentType - skipping event saving to Hive');
      return;
    }
    
    if (_hasEventsSaved) {
      debugPrint('⚠️ Events already saved, skipping duplicate save');
      return;
    }
    
    try {
      final currentPosition = _betterPlayerController?.videoPlayerController?.value.position;
      final currentSpeed = _betterPlayerController?.videoPlayerController?.value.speed ?? _currentPlaybackSpeed;
      
      // Finalize any pending seek before saving
      if (_isSeeking && _pendingSeekEndPosition != null) {
        _finalizeSeekEvent(_pendingSeekEndPosition!, currentSpeed);
        _pendingSeekEndPosition = null;
      }
      
      if (_events.isEmpty || _events.last['event_type'] != 'ended') {
        if (currentPosition != null) {
          _addEndedEvent(currentPosition, currentSpeed);
          
          if (_videoCompletedInThisSession) {
            debugPrint('📝 Added ENDED event - Video completed naturally');
          } else {
            debugPrint('📝 Added ENDED event - User exited early at ${_formatTime(currentPosition)}');
          }
        }
      }

      if (_events.isEmpty) {
        debugPrint('⚠️ No events to save');
        _hasEventsSaved = true;
        return;
      }

      final box = await Hive.openBox('videoEvents');
      
      Map<String, dynamic> videoData;
      
      if (box.containsKey(widget.videoId)) {
        final existingData = box.get(widget.videoId) as Map;
        videoData = Map<String, dynamic>.from(existingData);
        
        List<dynamic> allSessions = List.from(videoData['events'] ?? []);
        
        if (allSessions.isNotEmpty && allSessions.last is! List) {
          allSessions = [allSessions];
        }
        
        allSessions.add(_events);
        debugPrint('📌 Created NEW SESSION');
        
        videoData['events'] = allSessions;
        videoData['lastSessionCompleted'] = _videoCompletedInThisSession;
      } else {
        videoData = {
          'video_id': widget.videoId,
          'video_title': widget.videoTitle, // Added video title for better tracking
          'events': [_events],
          'lastSessionCompleted': _videoCompletedInThisSession,
        };
        debugPrint('📌 Created FIRST VIDEO ENTRY');
      }
      
      await box.put(widget.videoId, videoData);
      
      _hasEventsSaved = true;
      
      int totalSessions = 0;
      int totalEvents = 0;
      final allEvents = videoData['events'] as List;
      for (var session in allEvents) {
        if (session is List) {
          totalSessions++;
          totalEvents += session.length;
        }
      }
      
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('💾 VIDEO EVENTS SAVED TO HIVE');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Video ID: ${widget.videoId}');
      debugPrint('Video Title: ${widget.videoTitle}');
      debugPrint('Events recorded in this watch: ${_events.length}');
      debugPrint('Video Completed: $_videoCompletedInThisSession');
      debugPrint('Total watch sessions: $totalSessions');
      debugPrint('Total events across all sessions: $totalEvents');
      debugPrint('Saved at: ${DateTime.now()}');
      debugPrint('═══════════════════════════════════════════════════════');
      
      _printAllHiveData(box);
      
    } catch (e) {
      debugPrint('❌ Error saving events to Hive: $e');
    }
  }

  void _printAllHiveData(Box box) {
    debugPrint('\n📦 ALL VIDEO EVENTS IN HIVE DATABASE:');
    debugPrint('═══════════════════════════════════════════════════════');
    
    if (box.isEmpty) {
      debugPrint('No data stored yet.');
    } else {
      for (var key in box.keys) {
        final data = box.get(key);
        debugPrint('\n🎥 Video ID: $key');
        debugPrint('---------------------------------------------------');
        if (data is Map) {
          debugPrint('  video_id: ${data['video_id']}');
          debugPrint('  video_title: ${data['video_title']}');
          debugPrint('  events: [');
          
          final allEvents = data['events'] as List;
          
          for (var sessionIndex = 0; sessionIndex < allEvents.length; sessionIndex++) {
            final session = allEvents[sessionIndex];
            
            if (session is List) {
              debugPrint('    // Session ${sessionIndex + 1}');
              debugPrint('    [');
              
              for (var eventIndex = 0; eventIndex < session.length; eventIndex++) {
                final event = session[eventIndex] as Map;
                debugPrint('      {');
                
                if (event.containsKey('event_type')) {
                  debugPrint('        "event_type": "${event['event_type']}",');
                }
                if (event.containsKey('time')) {
                  debugPrint('        "time": ${event['time']},');
                }
                if (event.containsKey('old_position')) {
                  debugPrint('        "old_position": ${event['old_position']},');
                }
                if (event.containsKey('new_position')) {
                  debugPrint('        "new_position": ${event['new_position']},');
                }
                if (event.containsKey('playback_speed')) {
                  debugPrint('        "playback_speed": ${event['playback_speed']}');
                }
                
                debugPrint('      }${eventIndex < session.length - 1 ? ',' : ''}');
              }
              
              debugPrint('    ]${sessionIndex < allEvents.length - 1 ? ',' : ''}');
            }
          }
          
          debugPrint('  ]');
        }
        debugPrint('---------------------------------------------------');
      }
    }
    debugPrint('═══════════════════════════════════════════════════════\n');
  }

  Widget _buildErrorContent(String? errorMessage) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 60,
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to Play Video',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _initializeVideo,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Only save events for online students
    if (_studentType.toLowerCase() == 'online') {
      _saveEventsToHive();
    }
    
    // Only remove listeners if they were added (for online students)
    if (_studentType.toLowerCase() == 'online') {
      _betterPlayerController?.videoPlayerController?.removeListener(_onPositionChanged);
      _betterPlayerController?.removeEventsListener(_handleVideoEvent);
    }
    
    _betterPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Only save events for online students
        if (_studentType.toLowerCase() == 'online') {
          await _saveEventsToHive();
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            widget.videoTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryYellow),
              strokeWidth: 3,
            ),
            SizedBox(height: 20),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Please wait',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return _buildErrorContent(_errorMessage);
    }

    if (_betterPlayerController != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: BetterPlayer(controller: _betterPlayerController!),
        ),
      );
    }

    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off,
            size: 80,
            color: Colors.white54,
          ),
          SizedBox(height: 20),
          Text(
            'Video player not ready',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}