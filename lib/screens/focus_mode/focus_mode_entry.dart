import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../service/timer_service.dart';
import '../../service/websocket_manager.dart';

class FocusModeEntryScreen extends StatefulWidget {
  const FocusModeEntryScreen({super.key});

  @override
  State<FocusModeEntryScreen> createState() => _FocusModeEntryScreenState();
}

class _FocusModeEntryScreenState extends State<FocusModeEntryScreen> with WidgetsBindingObserver {
  final TimerService _timerService = TimerService();
  late Future<Duration> _initializationFuture;
  Duration _focusTimeToday = Duration.zero;
  bool _hasOverlayPermission = false;
  bool _isStartingFocusMode = false;
  bool _isRestoredFromDisconnect = false; // 🆕 Track if time was restored

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializationFuture = _initializeData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      debugPrint('📱 AppLifecycleState.detached - App being closed');
    }
  }

  Future<Duration> _initializeData() async {
    try {
      debugPrint('🔄 Starting focus mode entry initialization...');
      
      // Initialize timer service first
      await _timerService.initialize();
      
      // Get SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      debugPrint('📅 Today: $today');
      
      // 🆕 NEW LOGIC: Check WebSocket disconnect time first
      final disconnectTimeStr = prefs.getString(TimerService.websocketDisconnectTimeKey);
      if (disconnectTimeStr != null) {
        final disconnectTime = DateTime.parse(disconnectTimeStr);
        final disconnectDate = disconnectTime.toIso8601String().split('T')[0];
        
        debugPrint('🔌 Found WebSocket disconnect time: $disconnectDate');
        
        if (disconnectDate == today) {
          // Same day as disconnect - check for stored focus time
          await _handleWebSocketDisconnectRecovery(prefs, today);
        } else {
          // Different day - clear disconnect time and proceed normally
          debugPrint('📅 Disconnect was on different day, clearing');
          await prefs.remove(TimerService.websocketDisconnectTimeKey);
          await _handleNormalInitialization(prefs, today);
        }
      } else {
        // No WebSocket disconnect - proceed with normal initialization
        await _handleNormalInitialization(prefs, today);
      }
      
      // Check overlay permission using TimerService
      _hasOverlayPermission = await _timerService.checkOverlayPermission();
      
      debugPrint('📋 Initialization Summary:');
      debugPrint('   - Focus time today: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Overlay permission: $_hasOverlayPermission');
      debugPrint('   - Restored from disconnect: $_isRestoredFromDisconnect');
      debugPrint('   - Date: $today');
      
      return _focusTimeToday;
      
    } catch (e) {
      debugPrint('❌ Error initializing data: $e');
      return Duration.zero;
    }
  }

  // 🆕 NEW: Handle WebSocket disconnect recovery
  Future<void> _handleWebSocketDisconnectRecovery(SharedPreferences prefs, String today) async {
    try {
      debugPrint('🔌 Recovering from WebSocket disconnect...');
      
      // Check for last stored focus time
      final lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey) ?? 0;
      final lastStoredDate = prefs.getString(TimerService.lastStoredFocusDateKey);
      final savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      
      debugPrint('   - Last stored time: ${lastStoredTime}s');
      debugPrint('   - Last stored date: $lastStoredDate');
      debugPrint('   - Saved focus time: ${savedFocusTime}s');
      
      // Determine which time to use (use the maximum)
      int focusSeconds = 0;
      if (lastStoredDate == today) {
        focusSeconds = lastStoredTime > savedFocusTime ? lastStoredTime : savedFocusTime;
        _isRestoredFromDisconnect = true;
        debugPrint('   ✅ Using restored time: ${focusSeconds}s');
      } else {
        focusSeconds = savedFocusTime;
        debugPrint('   ⚠️ Last stored date mismatch, using saved time: ${focusSeconds}s');
      }
      
      // Update focus time
      _focusTimeToday = Duration(seconds: focusSeconds);
      
      // Ensure SharedPreferences is consistent
      await prefs.setInt(TimerService.focusKey, focusSeconds);
      
      // Clear the disconnect flag since we've recovered
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      
      // Also clear WebSocket disconnect tracking in TimerService
      final bool wasStoppedByWebSocket = await _timerService.wasFocusStoppedByWebSocket();
      if (wasStoppedByWebSocket) {
        debugPrint('   🧹 Clearing WebSocket disconnect tracking');
        // The timer service should handle this internally
      }
      
    } catch (e) {
      debugPrint('❌ Error in WebSocket disconnect recovery: $e');
      await _handleNormalInitialization(prefs, today);
    }
  }

  // 🆕 NEW: Handle normal initialization (no WebSocket disconnect)
  Future<void> _handleNormalInitialization(SharedPreferences prefs, String today) async {
    final lastDate = prefs.getString(TimerService.lastDateKey);
    
    debugPrint('📅 Normal initialization - Last saved date: $lastDate');
    
    if (lastDate != today) {
      // New day detected - Reset timer
      debugPrint('🔄 New day detected! Resetting timer...');
      await _resetTimerForNewDay(prefs, today);
    } else {
      // Same day - Load saved timer
      final savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      final lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey) ?? 0;
      
      // Use the greater of the two values
      final focusSeconds = savedFocusTime > lastStoredTime ? savedFocusTime : lastStoredTime;
      _focusTimeToday = Duration(seconds: focusSeconds);
      
      debugPrint('📊 Loaded focus time: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Saved: ${savedFocusTime}s');
      debugPrint('   - Last stored: ${lastStoredTime}s');
    }
  }

  // 🆕 NEW: Helper method to reset timer for new day
  Future<void> _resetTimerForNewDay(SharedPreferences prefs, String today) async {
    await prefs.setString(TimerService.lastDateKey, today);
    await prefs.setString(TimerService.heartbeatDateKey, today);
    await prefs.setInt(TimerService.focusKey, 0);
    await prefs.setBool(TimerService.isFocusModeKey, false);
    await prefs.remove(TimerService.focusStartTimeKey);
    await prefs.remove(TimerService.focusElapsedKey);
    await prefs.remove(TimerService.appStateKey);
    await prefs.remove(TimerService.lastHeartbeatKey);
    
    // Clear all stored times
    await prefs.remove(TimerService.lastStoredFocusTimeKey);
    await prefs.remove(TimerService.lastStoredFocusDateKey);
    await prefs.remove(TimerService.websocketDisconnectTimeKey);
    
    _focusTimeToday = Duration.zero;
    _isRestoredFromDisconnect = false;
    debugPrint('✅ Timer reset to 00:00:00 for new day');
  }

  void _startFocusMode() async {
    if (_isStartingFocusMode) return;
    
    setState(() {
      _isStartingFocusMode = true;
    });

    try {
      // Check WebSocket connection first
      if (!WebSocketManager.isConnected) {
        await _showWebSocketErrorPopup();
        setState(() {
          _isStartingFocusMode = false;
        });
        return;
      }

      // Verify date one more time before starting
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastDate = prefs.getString(TimerService.lastDateKey);
      
      if (lastDate != today) {
        debugPrint('⚠️ Date changed during start, resetting timer');
        await prefs.setString(TimerService.lastDateKey, today);
        await prefs.setInt(TimerService.focusKey, 0);
        _focusTimeToday = Duration.zero;
        _isRestoredFromDisconnect = false;
      }

      // Ensure timer service is initialized
      await _timerService.initialize();
      
      // 🆕 IMPORTANT: Clear any WebSocket disconnect flags before starting
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      
      // Check overlay permission using TimerService
      final hasPermission = await _timerService.checkOverlayPermission();
      
      if (!hasPermission) {
        // Show popup asking for permission
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          // User clicked OK - open settings
          await openAppSettings();
          
          // After returning from settings, check permission again
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            // Permission granted, start focus mode
            await _actuallyStartFocusMode();
          } else {
            // User still hasn't granted permission
            await _showPermissionRequiredPopup();
            setState(() {
              _isStartingFocusMode = false;
            });
            return;
          }
        } else {
          // User clicked Cancel, stay on this page
          setState(() {
            _isStartingFocusMode = false;
          });
          return;
        }
      } else {
        // Already have permission, start focus mode
        await _actuallyStartFocusMode();
      }
    } catch (e) {
      debugPrint('❌ Error starting focus mode: $e');
      
      // Check if error is about overlay permission
      if (e.toString().contains('Overlay permission required')) {
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            await _actuallyStartFocusMode();
          } else {
            await _showPermissionRequiredPopup();
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start focus mode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  Future<void> _showWebSocketErrorPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text('Connection Error'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unable to start Focus Mode. The app is not connected to the server.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Please check your internet connection and try again.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Reconnecting...'),
                      ],
                    ),
                    duration: Duration(seconds: 3),
                  ),
                );
                
                await WebSocketManager.cleanReconnect();
                await Future.delayed(const Duration(milliseconds: 1500));
                
                if (WebSocketManager.isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connected successfully!'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reconnection failed. Please check your connection.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showPermissionPopup() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Permission Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable Focus Mode with distraction blocking, you need to grant "Display over other apps" permission.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildPermissionStep('1. Click "OK" below'),
              _buildPermissionStep('2. Find "Display over other apps" in settings'),
              _buildPermissionStep('3. Enable it for this app'),
              _buildPermissionStep('4. Return to this app'),
              const SizedBox(height: 12),
              const Text(
                'Without this permission, Focus Mode will not block other apps.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
              ),
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPermissionRequiredPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Permission Not Granted'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus Mode requires "Display over other apps" permission to block distractions.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Please enable it in Settings to use Focus Mode.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isStartingFocusMode = false;
                });
              },
              child: const Text(
                'STAY HERE',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
                await Future.delayed(const Duration(milliseconds: 500));
                final hasPermission = await _timerService.checkOverlayPermission();
                if (hasPermission) {
                  await _actuallyStartFocusMode();
                } else {
                  setState(() {
                    _isStartingFocusMode = false;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
              ),
              child: const Text(
                'OPEN SETTINGS',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _actuallyStartFocusMode() async {
    try {
      debugPrint('🚀 Starting focus mode with current time: ${_focusTimeToday.inSeconds}s');
      
      // 🆕 IMPORTANT: Update TimerService with current focus time before starting
      _timerService.focusTimeToday.value = _focusTimeToday;
      
      // Start focus mode
      await _timerService.startFocusMode();
      
      debugPrint('✅ Focus mode started, navigating to home');
      
      // Send WebSocket event for focus start
      _sendFocusStartEvent();
      
      // Navigate to home screen with focus mode active
      Navigator.pushReplacementNamed(
        context, 
        '/home',
        arguments: {'isFocusMode': true}
      );
      
    } catch (e) {
      debugPrint('❌ Error in actuallyStartFocusMode: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start focus mode: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  void _sendFocusStartEvent() {
    try {
      WebSocketManager.send({"event": "focus_start"});
      debugPrint('📤 WebSocket event sent: {"event": "focus_start"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_start event: $e');
      
      try {
        WebSocketManager.connect();
        debugPrint('🔄 Attempting to reconnect WebSocket...');
        
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            WebSocketManager.send({"event": "focus_start"});
            debugPrint('📤 Retry: WebSocket event sent: {"event": "focus_start"}');
          } catch (retryError) {
            debugPrint('❌ Retry failed: $retryError');
          }
        });
      } catch (connectError) {
        debugPrint('❌ WebSocket reconnection failed: $connectError');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Duration>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to initialize timer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _initializationFuture = _initializeData();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          // 🆕 Get the actual focus time with proper fallback
          final Duration focusTime = snapshot.data ?? Duration.zero;
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Focus Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF43E97B).withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF43E97B),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.timer,
                    size: 60,
                    color: Color(0xFF43E97B),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Enter Focus Mode',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Description
                Text(
                  _hasOverlayPermission 
                    ? 'Full distraction blocking is enabled. Stay focused!'
                    : 'Grant permission to block distractions and maximize focus.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Today's Focus Time Statistics
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      _buildStatItem(
                        icon: Icons.timer,
                        value: _formatDuration(focusTime),
                        label: 'Focus Today',
                        color: const Color(0xFF43E97B),
                      ),
                      const SizedBox(height: 8),
                      // 🆕 Show restoration status
                      if (_isRestoredFromDisconnect)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Restored from last session',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _buildPermissionStatus(),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Start Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isStartingFocusMode ? null : _startFocusMode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43E97B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF43E97B).withOpacity(0.3),
                    ),
                    child: _isStartingFocusMode
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: Colors.white),
                              SizedBox(width: 10),
                              Text(
                                'Start Focus Session',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Skip for now button
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context, 
                      '/home',
                      arguments: {'isFocusMode': false}
                    );
                  },
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _hasOverlayPermission ? Icons.check_circle : Icons.warning,
          color: _hasOverlayPermission ? Colors.green : Colors.orange,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          _hasOverlayPermission 
            ? 'Permission granted'
            : 'Permission required for full features',
          style: TextStyle(
            fontSize: 12,
            color: _hasOverlayPermission ? Colors.green : Colors.orange,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}