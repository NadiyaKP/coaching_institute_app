import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart'; 
import 'websocket_manager.dart';
import 'dart:convert';

// Timer snapshot for accurate state tracking
class _TimerSnapshot {
  final Duration totalElapsed;
  final DateTime snapshotTime;
  final bool isRunning;
  
  _TimerSnapshot({
    required this.totalElapsed,
    required this.snapshotTime,
    required this.isRunning,
  });
  
  Map<String, dynamic> toJson() => {
    'total_seconds': totalElapsed.inSeconds,
    'snapshot_time': snapshotTime.toUtc().toIso8601String(),
    'is_running': isRunning,
  };
  
  factory _TimerSnapshot.fromJson(Map<String, dynamic> json) => _TimerSnapshot(
    totalElapsed: Duration(seconds: json['total_seconds']),
    snapshotTime: DateTime.parse(json['snapshot_time']),
    isRunning: json['is_running'],
  );
}

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  // SharedPreferences Keys
  static const String focusKey = 'focus_time_today';
  static const String lastDateKey = 'last_timer_date';
  static const String isFocusModeKey = 'is_focus_mode';
  static const String focusStartTimeKey = 'focus_start_time';
  static const String focusElapsedKey = 'focus_elapsed_before_pause';
  static const String lastUserEmailKey = 'last_timer_user_email';
  static const String overlayPermissionKey = 'overlay_permission_granted';
  static const String appStateKey = 'app_last_state';
  static const String lastHeartbeatKey = 'last_heartbeat_time';
  static const String heartbeatDateKey = 'heartbeat_date';
  static const String lastStoredFocusTimeKey = 'last_stored_focus_time';
  static const String lastStoredFocusDateKey = 'last_stored_focus_date';
  static const String websocketDisconnectTimeKey = 'websocket_disconnect_time';
  static const String wasWebsocketDisconnectedKey = 'was_websocket_disconnected';
  static const String timerPausedByWebsocketKey = 'timer_paused_by_websocket';
  static const String timerSnapshotKey = 'timer_snapshot';
  static const String pausedTotalTimeKey = 'paused_total_time';
  
  // WebSocket state tracking
  static bool _isWebSocketConnected = false;
  static DateTime? _lastWebSocketDisconnectTime;
  StreamSubscription? _websocketSubscription;
  StreamSubscription<bool>? _websocketConnectionSubscription;

  final ValueNotifier<bool> _isFocusMode = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isFocusMode => _isFocusMode;

  final ValueNotifier<Duration> _focusTimeToday = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get focusTimeToday => _focusTimeToday;

  Timer? _activeTimer;
  Timer? _heartbeatTimer;
  Timer? _dateCheckTimer; // NEW: Timer for checking date changes
  DateTime? _timerStartTime;
  Duration _baseTimeWhenTimerStarted = Duration.zero;
  bool _isInitialized = false;
  String? _currentUserEmail;
  bool _hasOverlayPermission = false;
  DateTime? _lastAppResumeTime;
  bool _appInForeground = true;
  
  // Track current date for comparison
  String _currentDate = ''; // NEW: Track current date
  
  // Callback to navigate back to entry screen
  Function()? _onWebSocketDisconnectCallback;
  
  // NEW: Simplified state tracking
  Duration _exactTimeAtPause = Duration.zero;
  bool _isPausedByWebSocket = false;

  bool get hasOverlayPermission => _hasOverlayPermission;
  static const MethodChannel _overlayChannel = MethodChannel('focus_mode_overlay_channel');

  // Set callback for WebSocket disconnection
  void setWebSocketDisconnectCallback(Function() callback) {
    _onWebSocketDisconnectCallback = callback;
  }

  // Initialize WebSocket monitoring
  Future<void> _initializeWebSocketMonitoring() async {
    try {
      _startWebSocketMonitor();
    } catch (e) {
      debugPrint('❌ WebSocket monitoring init error: $e');
    }
  }

  void _startWebSocketMonitor() {
    // Register callback to send focus status when WebSocket requests it
    WebSocketManager.registerFocusStatusRequestCallback(() {
      _handleHeartbeatWithFocusStatus();
    });
    
    // Listen to WebSocket connection state changes
    _websocketConnectionSubscription?.cancel();
    _websocketConnectionSubscription = WebSocketManager.connectionStateStream.listen((isConnected) async {  
      debugPrint('🔌 WebSocket connection state changed: $isConnected (was: $_isWebSocketConnected)');
      
      final bool wasConnected = _isWebSocketConnected;
      _isWebSocketConnected = isConnected;
      
      if (wasConnected && !_isWebSocketConnected) {
        // WebSocket disconnected
        debugPrint('🔌 WebSocket disconnected - handling timer pause');
        await _handleWebSocketDisconnection();
      } else if (!wasConnected && _isWebSocketConnected) {
        // WebSocket reconnected
        debugPrint('🔗 WebSocket reconnected - checking for paused timer');
        _lastWebSocketDisconnectTime = null;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(wasWebsocketDisconnectedKey);
        
        // Send focus status immediately on reconnection
        _sendFocusStatusToWebSocket();
        
        // Check if timer was paused by WebSocket and resume it
        await _checkAndResumeTimerAfterReconnect();
      }
    });
    
    // Also listen to the reconnected stream for additional safety
    WebSocketManager.reconnectedStream.listen((_) async {
      debugPrint('🔗 WebSocketManager.reconnectedStream fired');
      await _checkAndResumeTimerAfterReconnect();
    });
    
    // Register callback in WebSocketManager
    WebSocketManager.registerDisconnectionCallback(() {
      if (_isFocusMode.value) {
        debugPrint('🔌 Immediate WebSocket disconnection detected');
        _handleWebSocketDisconnection();
      }
    });
    
    // Register reconnection callback
    WebSocketManager.registerReconnectionCallback(() {
      debugPrint('🔗 WebSocket reconnection callback - resuming timer');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndResumeTimerAfterReconnect();
      });
    });
  }

  // Send focus status to WebSocket
  void _sendFocusStatusToWebSocket() {
    if (WebSocketManager.isConnected) {
      final isFocusing = _isFocusMode.value ? 1 : 0;
      WebSocketManager.sendFocusStatus(_isFocusMode.value);
      debugPrint('📤 Focus status sent via WebSocket: is_focusing=$isFocusing');
    } else {
      debugPrint('⚠️ Cannot send focus status - WebSocket not connected');
    }
  }

  // Handle heartbeat with focus status
  void _handleHeartbeatWithFocusStatus() {
    if (WebSocketManager.isConnected) {
      final isFocusing = _isFocusMode.value ? 1 : 0;
      WebSocketManager.sendCombinedHeartbeat(_isFocusMode.value);
      debugPrint('💓 Combined heartbeat sent: is_focusing=$isFocusing');
    }
  }

  // NEW: Get exact current elapsed time
  Duration _getCurrentElapsedTime() {
    if (_timerStartTime != null && !_isPausedByWebSocket) {
      final elapsed = DateTime.now().difference(_timerStartTime!);
      return _baseTimeWhenTimerStarted + elapsed;
    }
    return _exactTimeAtPause.inSeconds > 0 ? _exactTimeAtPause : _baseTimeWhenTimerStarted;
  }

  // Create snapshot of current timer state
  _TimerSnapshot _createSnapshot() {
    final currentTotal = _getCurrentElapsedTime();
    
    return _TimerSnapshot(
      totalElapsed: currentTotal,
      snapshotTime: DateTime.now(),
      isRunning: _isFocusMode.value && _timerStartTime != null && !_isPausedByWebSocket,
    );
  }

  // Save snapshot to shared preferences
  Future<void> _saveSnapshot(_TimerSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(timerSnapshotKey, jsonEncode(snapshot.toJson()));
      await prefs.setInt(pausedTotalTimeKey, snapshot.totalElapsed.inSeconds);
      debugPrint('💾 Timer snapshot saved: ${snapshot.totalElapsed.inSeconds}s at ${snapshot.snapshotTime}');
    } catch (e) {
      debugPrint('❌ Error saving snapshot: $e');
    }
  }

  // Load snapshot from shared preferences
  Future<_TimerSnapshot?> _loadSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshotJson = prefs.getString(timerSnapshotKey);
      if (snapshotJson != null) {
        final snapshot = _TimerSnapshot.fromJson(jsonDecode(snapshotJson));
        debugPrint('📥 Timer snapshot loaded: ${snapshot.totalElapsed.inSeconds}s from ${snapshot.snapshotTime}');
        return snapshot;
      }
    } catch (e) {
      debugPrint('❌ Error loading snapshot: $e');
    }
    return null;
  }

  // Clear snapshot
  Future<void> _clearSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(timerSnapshotKey);
      await prefs.remove(pausedTotalTimeKey);
      debugPrint('🗑️ Timer snapshot cleared');
    } catch (e) {
      debugPrint('❌ Error clearing snapshot: $e');
    }
  }

  // NEW: Check and resume timer after reconnection
  Future<void> _checkAndResumeTimerAfterReconnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasPausedByWebSocket = prefs.getBool(timerPausedByWebsocketKey) ?? false;
      
      if (!wasPausedByWebSocket) {
        debugPrint('ℹ️ Timer was not paused by WebSocket - no action needed');
        return;
      }
      
      debugPrint('🔄 Timer was paused by WebSocket - attempting to resume');
      
      // Load the exact time at which we paused
      final pausedTotalSeconds = prefs.getInt(pausedTotalTimeKey);
      
      if (pausedTotalSeconds == null) {
        debugPrint('⚠️ No paused time found - cannot resume accurately');
        await prefs.remove(timerPausedByWebsocketKey);
        return;
      }
      
      final pausedTotal = Duration(seconds: pausedTotalSeconds);
      debugPrint('📊 Resuming from paused time: ${pausedTotal.inSeconds}s');
      
      // Resume the timer with exact time
      _isPausedByWebSocket = false;
      _isFocusMode.value = true;
      _baseTimeWhenTimerStarted = pausedTotal;
      _timerStartTime = DateTime.now();
      _exactTimeAtPause = Duration.zero;
      
      // Update UI immediately
      _focusTimeToday.value = pausedTotal;
      
      // Update shared preferences
      await prefs.setBool(isFocusModeKey, true);
      await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
      await prefs.setInt(focusKey, pausedTotal.inSeconds);
      await prefs.setInt(lastStoredFocusTimeKey, pausedTotal.inSeconds);
      
      // Clear pause flags
      await prefs.remove(timerPausedByWebsocketKey);
      await _clearSnapshot();
      
      // Start the timer
      _startFocusTimer();
      _startHeartbeat();
      
      // Send combined heartbeat after resuming
      _handleHeartbeatWithFocusStatus();
      
      debugPrint('✅ Timer resumed successfully at: ${pausedTotal.inSeconds}s');
      
    } catch (e) {
      debugPrint('❌ Error checking/resuming timer: $e');
      // Clean up on error
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(timerPausedByWebsocketKey);
      await _clearSnapshot();
    }
  }

  // NEW: Handle WebSocket disconnection with accurate pause
  Future<void> _handleWebSocketDisconnection() async {
    try {
      if (!_isFocusMode.value) {
        debugPrint('ℹ️ Timer not running - no action needed');
        return;
      }
      
      debugPrint('🔌 WebSocket disconnected - pausing focus timer');
      
      // Get exact current time BEFORE stopping anything
      final exactCurrentTime = _getCurrentElapsedTime();
      _exactTimeAtPause = exactCurrentTime;
      
      debugPrint('📊 Exact time at pause: ${_exactTimeAtPause.inSeconds}s');
      debugPrint('   - Base time: ${_baseTimeWhenTimerStarted.inSeconds}s');
      if (_timerStartTime != null) {
        final sessionElapsed = DateTime.now().difference(_timerStartTime!);
        debugPrint('   - Session elapsed: ${sessionElapsed.inSeconds}s');
      }
      
      // Create and save snapshot
      final snapshot = _createSnapshot();
      await _saveSnapshot(snapshot);
      
      // Stop the timer
      _stopActiveTimer();
      _stopHeartbeat();
      
      // Update display to show exact paused time
      _focusTimeToday.value = _exactTimeAtPause;
      
      // Save to preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(focusKey, _exactTimeAtPause.inSeconds);
      await prefs.setInt(lastStoredFocusTimeKey, _exactTimeAtPause.inSeconds);
      await prefs.setInt(pausedTotalTimeKey, _exactTimeAtPause.inSeconds);
      await prefs.setBool(timerPausedByWebsocketKey, true);
      await prefs.setBool(wasWebsocketDisconnectedKey, true);
      
      // Mark as paused but keep focus mode indicator
      _isPausedByWebSocket = true;
      _timerStartTime = null;
      
      _lastWebSocketDisconnectTime = DateTime.now();
      await prefs.setString(websocketDisconnectTimeKey, 
          _lastWebSocketDisconnectTime!.toUtc().toIso8601String());
      
      debugPrint('⏸️ Focus timer paused at exactly: ${_exactTimeAtPause.inSeconds}s');
      
      // Hide overlay if shown
      if (_hasOverlayPermission) {
        await hideOverlay();
      }
      
      // Trigger callback to show connection lost UI
      if (_onWebSocketDisconnectCallback != null) {
        debugPrint('🔄 Triggering navigation callback');
        _onWebSocketDisconnectCallback!();
      }
    } catch (e) {
      debugPrint('❌ Error handling WebSocket disconnection: $e');
    }
  }

  // NEW: Start date check timer to monitor date changes
  void _startDateCheckTimer() {
    _stopDateCheckTimer();
    
    // Check every 30 seconds for date changes
    _dateCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _checkForDateChange();
    });
    
    debugPrint('📅 Date check timer started');
  }

  // NEW: Stop date check timer
  void _stopDateCheckTimer() {
    _dateCheckTimer?.cancel();
    _dateCheckTimer = null;
  }

  // NEW: Check if date has changed and handle it
  Future<void> _checkForDateChange() async {
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      
      if (_currentDate != today) {
        debugPrint('📅 Date changed detected! Was: $_currentDate, Now: $today');
        
        // Store the previous date for debugging
        final previousDate = _currentDate;
        _currentDate = today;
        
        // Update last date in preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(lastDateKey, today);
        await prefs.setString(heartbeatDateKey, today);
        
        if (_isFocusMode.value) {
          debugPrint('🔄 Timer is running on date change - resetting and restarting');
          
          // If timer is running, we need to reset it and start fresh
          // First, stop the current timer
          _stopActiveTimer();
          _stopHeartbeat();
          
          // Reset all timer variables
          _baseTimeWhenTimerStarted = Duration.zero;
          _exactTimeAtPause = Duration.zero;
          _timerStartTime = DateTime.now(); // Reset start time to now
          _focusTimeToday.value = Duration.zero;
          
          // Update preferences
          await prefs.setInt(focusKey, 0);
          await prefs.setInt(lastStoredFocusTimeKey, 0);
          await prefs.setString(lastStoredFocusDateKey, today);
          await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
          await prefs.setInt(focusElapsedKey, 0);
          
          // Restart the timer
          _startFocusTimer();
          _startHeartbeat();
          
          // Send heartbeat to notify server of reset
          _handleHeartbeatWithFocusStatus();
          
          debugPrint('✅ Timer reset for new day: $today');
          debugPrint('   - Previous date: $previousDate');
          debugPrint('   - New start time: ${_timerStartTime!.toIso8601String()}');
        } else {
          // Timer is not running, just reset stored values
          debugPrint('📅 Date changed but timer not running - resetting stored values');
          
          await prefs.setInt(focusKey, 0);
          await prefs.setInt(lastStoredFocusTimeKey, 0);
          await prefs.setString(lastStoredFocusDateKey, today);
          await prefs.remove(focusStartTimeKey);
          await prefs.remove(focusElapsedKey);
          
          // Update UI
          _focusTimeToday.value = Duration.zero;
          
          debugPrint('✅ Stored values reset for new day: $today');
        }
        
        // Clear any disconnect flags since it's a new day
        await prefs.remove(websocketDisconnectTimeKey);
        await prefs.remove(wasWebsocketDisconnectedKey);
        await prefs.remove(timerPausedByWebsocketKey);
        await _clearSnapshot();
      }
    } catch (e) {
      debugPrint('❌ Error checking for date change: $e');
    }
  }

  Future<void> _storeFocusTimeOnDisconnect() async {
    try {
      if (_timerStartTime != null) {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now();
        final today = now.toIso8601String().split('T')[0];
        
        final elapsed = now.difference(_timerStartTime!);
        final newTotal = _baseTimeWhenTimerStarted + elapsed;
        
        await prefs.setInt(focusKey, newTotal.inSeconds);
        await prefs.setInt(lastStoredFocusTimeKey, newTotal.inSeconds);
        await prefs.setString(lastStoredFocusDateKey, today);
        
        debugPrint('💾 Focus time saved on disconnect: ${newTotal.inSeconds}s');
        debugPrint('📅 Saved date: $today');
        
        _focusTimeToday.value = newTotal;
      }
    } catch (e) {
      debugPrint('❌ Error storing focus time on disconnect: $e');
    }
  }

  Future<void> _checkAndRestoreFocusTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      _currentDate = today; // Initialize current date
      
      final lastStoredTime = prefs.getInt(lastStoredFocusTimeKey);
      final lastStoredDate = prefs.getString(lastStoredFocusDateKey);
      
      if (lastStoredTime != null && lastStoredDate != null) {
        debugPrint('📊 Last stored focus time: $lastStoredTime seconds on $lastStoredDate');
        debugPrint('📅 Today: $today');
        
        if (lastStoredDate != today) {
          debugPrint('📅 Date changed - resetting timer');
          await prefs.remove(lastStoredFocusTimeKey);
          await prefs.remove(lastStoredFocusDateKey);
          await prefs.setInt(focusKey, 0);
          _focusTimeToday.value = Duration.zero;
        } else {
          final savedTime = prefs.getInt(focusKey) ?? 0;
          if (savedTime < lastStoredTime) {
            debugPrint('🔄 Restoring focus time from last session');
            await prefs.setInt(focusKey, lastStoredTime);
            _focusTimeToday.value = Duration(seconds: lastStoredTime);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking/restoring focus time: $e');
    }
  }

  static Future<void> initializeBackgroundService() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    debugPrint('✅ TimerService: Background service initialized');
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        
        final accessToken = prefs.getString('accessToken');
        final username = prefs.getString('username');
        
        if (accessToken == null || username == null) {
          debugPrint('❌ Background: User not logged in');
          await Workmanager().cancelAll();
          return Future.value(true);
        }
        
        final now = DateTime.now();
        final today = now.toIso8601String().split('T')[0];
        final lastDate = prefs.getString(lastDateKey);
        
        if (lastDate != null && lastDate != today) {
          debugPrint('📅 Background: New day, resetting');
          await prefs.setString(lastDateKey, today);
          await prefs.setInt(focusKey, 0);
          await prefs.setBool(isFocusModeKey, false);
          await prefs.remove(focusStartTimeKey);
          await prefs.remove(focusElapsedKey);
          await prefs.remove(appStateKey);
          await prefs.remove(lastHeartbeatKey);
          await prefs.setString(heartbeatDateKey, today);
          await prefs.remove(lastStoredFocusTimeKey);
          await prefs.remove(lastStoredFocusDateKey);
          await prefs.remove(websocketDisconnectTimeKey);
          await prefs.remove(wasWebsocketDisconnectedKey);
          await prefs.remove(timerSnapshotKey);
          await prefs.remove(pausedTotalTimeKey);
          await prefs.remove(timerPausedByWebsocketKey);
          return Future.value(true);
        }
        
        final disconnectTimeStr = prefs.getString(websocketDisconnectTimeKey);
        if (disconnectTimeStr != null) {
          final disconnectTime = DateTime.parse(disconnectTimeStr);
          final timeSinceDisconnect = now.difference(disconnectTime);
          
          if (timeSinceDisconnect < const Duration(minutes: 5)) {
            final isFocusActive = prefs.getBool(isFocusModeKey) ?? false;
            if (isFocusActive) {
              debugPrint('🔌 Background: WebSocket was disconnected, stopping focus');
              await prefs.setBool(isFocusModeKey, false);
              await prefs.remove(focusStartTimeKey);
              await prefs.remove(focusElapsedKey);
              await prefs.remove(lastHeartbeatKey);
            }
          } else {
            await prefs.remove(websocketDisconnectTimeKey);
            await prefs.remove(wasWebsocketDisconnectedKey);
            await prefs.remove(timerSnapshotKey);
            await prefs.remove(pausedTotalTimeKey);
            await prefs.remove(timerPausedByWebsocketKey);
          }
        }
        
        return Future.value(true);
      } catch (e) {
        debugPrint('❌ Background error: $e');
        return Future.value(true);
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    debugPrint('💓 Starting heartbeat');
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isFocusMode.value && _appInForeground) {
        _sendHeartbeat();
      }
    });
  }

  Future<void> _sendHeartbeat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      
      await prefs.setString(lastHeartbeatKey, now.toIso8601String());
      await prefs.setString(heartbeatDateKey, today);
      
      debugPrint('💓 Heartbeat: ${now.toIso8601String()}');
      
      // Send combined heartbeat with focus status when WebSocket is connected
      if (WebSocketManager.isConnected) {
        _handleHeartbeatWithFocusStatus();
      }
    } catch (e) {
      debugPrint('❌ Heartbeat error: $e');
    }
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _saveAppState(String state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(appStateKey, state);
    } catch (e) {
      debugPrint('❌ Save state error: $e');
    }
  }

  Future<void> shutdownForLogout() async {
    debugPrint('🔴 SHUTDOWN FOR LOGOUT');
    try {
      _stopHeartbeat();
      _stopDateCheckTimer(); // NEW: Stop date check timer
      await Workmanager().cancelAll();
      await Future.delayed(const Duration(milliseconds: 500));
      _stopActiveTimer();
      await _forceHideOverlayWithRetries();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isFocusModeKey, false);
      await prefs.remove(focusStartTimeKey);
      await prefs.remove(focusElapsedKey);
      await prefs.remove(focusKey);
      await prefs.remove(lastDateKey);
      await prefs.remove(appStateKey);
      await prefs.remove(lastHeartbeatKey);
      await prefs.remove(heartbeatDateKey);
      await prefs.setBool(overlayPermissionKey, false);
      await prefs.remove(lastStoredFocusTimeKey);
      await prefs.remove(lastStoredFocusDateKey);
      await prefs.remove(websocketDisconnectTimeKey);
      await prefs.remove(wasWebsocketDisconnectedKey);
      await prefs.remove(timerSnapshotKey);
      await prefs.remove(pausedTotalTimeKey);
      await prefs.remove(timerPausedByWebsocketKey);
      
      _resetInstance();
      
      await Future.delayed(const Duration(milliseconds: 500));
      await _forceHideOverlayWithRetries();
      
      debugPrint('✅ SHUTDOWN COMPLETE');
    } catch (e) {
      debugPrint('❌ Shutdown error: $e');
      await _forceHideOverlayWithRetries();
    }
  }

  Future<void> _forceHideOverlayWithRetries() async {
    for (int i = 1; i <= 5; i++) {
      try {
        final result = await _overlayChannel.invokeMethod('hideOverlay');
        if (result == true) {
          await Future.delayed(const Duration(milliseconds: 200));
          await _overlayChannel.invokeMethod('hideOverlay');
          return;
        }
        if (i < 5) await Future.delayed(Duration(milliseconds: 300 * i));
      } catch (e) {
        if (i < 5) await Future.delayed(Duration(milliseconds: 300 * i));
      }
    }
  }

  Future<bool> checkOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.status;
      _hasOverlayPermission = status.isGranted;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(overlayPermissionKey, _hasOverlayPermission);
      return _hasOverlayPermission;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.request();
      _hasOverlayPermission = status.isGranted;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(overlayPermissionKey, _hasOverlayPermission);
      return _hasOverlayPermission;
    } catch (e) {
      return false;
    }
  }

  Future<void> showOverlay() async {
    try {
      if (_isFocusMode.value && _hasOverlayPermission && !_appInForeground) {
        await _overlayChannel.invokeMethod('showOverlay', {
          'message': 'You are in focus mode, focus on studies',
        });
      }
    } catch (e) {
      debugPrint('❌ Show overlay error: $e');
    }
  }

  Future<void> hideOverlay() async {
    try {
      await _overlayChannel.invokeMethod('hideOverlay');
    } catch (e) {
      debugPrint('❌ Hide overlay error: $e');
    }
  }

  Future<String?> _getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username') ?? 
           prefs.getString('profile_email') ?? 
           prefs.getString('user_email');
  }

  Future<void> initialize() async {
    try {
      debugPrint('🔄 Initializing...');
      final prefs = await SharedPreferences.getInstance();
      
      _currentUserEmail = await _getCurrentUserEmail();
      if (_currentUserEmail == null || _currentUserEmail!.isEmpty) {
        _resetInstance();
        return;
      }
      
      _hasOverlayPermission = prefs.getBool(overlayPermissionKey) ?? false;
      
      final lastUserEmail = prefs.getString(lastUserEmailKey);
      if (lastUserEmail != _currentUserEmail) {
        debugPrint('👤 User changed, clearing data');
        await _clearUserData(prefs);
        _resetInstance();
      } else if (_isInitialized) {
        return;
      }
      
      final lastDate = prefs.getString(lastDateKey);
      final today = DateTime.now().toIso8601String().split('T')[0];
      _currentDate = today; // Initialize current date
      
      if (lastDate != today) {
        debugPrint('📅 New day, resetting');
        await prefs.setString(lastDateKey, today);
        await prefs.setString(heartbeatDateKey, today);
        await prefs.setInt(focusKey, 0);
        _focusTimeToday.value = Duration.zero;
        await prefs.setBool(isFocusModeKey, false);
        await prefs.remove(focusStartTimeKey);
        await prefs.remove(focusElapsedKey);
        await prefs.remove(appStateKey);
        await prefs.remove(lastHeartbeatKey);
        await prefs.remove(lastStoredFocusTimeKey);
        await prefs.remove(lastStoredFocusDateKey);
        await prefs.remove(websocketDisconnectTimeKey);
        await prefs.remove(wasWebsocketDisconnectedKey);
        await prefs.remove(timerSnapshotKey);
        await prefs.remove(pausedTotalTimeKey);
        await prefs.remove(timerPausedByWebsocketKey);
      } else {
        await _checkAndRestoreFocusTime();
      }
      
      _isFocusMode.value = prefs.getBool(isFocusModeKey) ?? false;
      
      if (_isFocusMode.value && _appInForeground) {
        final startTimeStr = prefs.getString(focusStartTimeKey);
        final elapsedSeconds = prefs.getInt(focusElapsedKey) ?? 0;
        
        if (startTimeStr != null) {
          _timerStartTime = DateTime.parse(startTimeStr);
          _focusTimeToday.value += Duration(seconds: elapsedSeconds);
          _startFocusTimer();
          _startHeartbeat();
          _startDateCheckTimer(); // NEW: Start date checking
          
          // Send combined heartbeat on initialization if WebSocket is connected
          if (WebSocketManager.isConnected) {
            _handleHeartbeatWithFocusStatus();
          }
        } else {
          _isFocusMode.value = false;
          await prefs.setBool(isFocusModeKey, false);
        }
      }
      
      // NEW: Start date check timer even if timer is not running
      // This ensures we detect date changes when user opens the app
      _startDateCheckTimer();
      
      await _registerBackgroundTask();
      await prefs.setString(lastUserEmailKey, _currentUserEmail!);
      await _saveAppState('resumed');
      _isInitialized = true;
      
      await _initializeWebSocketMonitoring();
      
      debugPrint('✅ Initialized for: $_currentUserEmail');
      debugPrint('📅 Current date tracking: $_currentDate');
    } catch (e) {
      debugPrint('❌ Init error: $e');
      rethrow;
    }
  }

  Future<void> _clearUserData(SharedPreferences prefs) async {
    await prefs.remove(focusKey);
    await prefs.remove(lastDateKey);
    await prefs.remove(isFocusModeKey);
    await prefs.remove(focusStartTimeKey);
    await prefs.remove(focusElapsedKey);
    await prefs.remove(appStateKey);
    await prefs.remove(lastHeartbeatKey);
    await prefs.remove(heartbeatDateKey);
    await prefs.remove(lastStoredFocusTimeKey);
    await prefs.remove(lastStoredFocusDateKey);
    await prefs.remove(websocketDisconnectTimeKey);
    await prefs.remove(wasWebsocketDisconnectedKey);
    await prefs.remove(timerSnapshotKey);
    await prefs.remove(pausedTotalTimeKey);
    await prefs.remove(timerPausedByWebsocketKey);
    
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString(lastDateKey, today);
    await prefs.setString(heartbeatDateKey, today);
    await prefs.setInt(focusKey, 0);
    await prefs.setBool(isFocusModeKey, false);
  }

  Future<void> _registerBackgroundTask() async {
    try {
      await Workmanager().cancelAll();
      await Workmanager().registerPeriodicTask(
        "timer_update_task",
        "timer_background_update",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        initialDelay: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('❌ Background task error: $e');
    }
  }

  // Check WebSocket connection before starting
  Future<void> startFocusMode({bool skipPermissionCheck = false}) async {
    try {
      // Check WebSocket connection first
      if (!WebSocketManager.isConnected) {
        debugPrint('❌ Cannot start focus mode: WebSocket not connected');
        throw Exception('WebSocket connection required');
      }
      
      if (_currentUserEmail == null) {
        _currentUserEmail = await _getCurrentUserEmail();
        if (_currentUserEmail == null) throw Exception('No user');
      }
      
      if (!skipPermissionCheck && !await checkOverlayPermission()) {
        throw Exception('Overlay permission required');
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(websocketDisconnectTimeKey);
      await prefs.remove(wasWebsocketDisconnectedKey);
      await prefs.remove(timerPausedByWebsocketKey);
      await _clearSnapshot();
      
      // Check for date change before starting
      await _checkForDateChange();
      
      final currentSavedSeconds = prefs.getInt(focusKey) ?? 0;
      _baseTimeWhenTimerStarted = Duration(seconds: currentSavedSeconds);
      
      debugPrint('🚀 Starting focus mode with base time: ${currentSavedSeconds}s');
      
      _isFocusMode.value = true;
      _timerStartTime = DateTime.now();
      _appInForeground = true;
      _isPausedByWebSocket = false;
      _exactTimeAtPause = Duration.zero;
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      _currentDate = today; // Update current date
      
      await prefs.setBool(isFocusModeKey, true);
      await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
      await prefs.setString(lastDateKey, today);
      await prefs.setString(heartbeatDateKey, today);
      await prefs.remove(focusElapsedKey);
      await _saveAppState('resumed');
      
      _startFocusTimer();
      _startHeartbeat();
      
      // Send combined heartbeat to WebSocket
      _handleHeartbeatWithFocusStatus();
      
      await _registerBackgroundTask();
      
      debugPrint('✅ Focus mode started');
      debugPrint('📅 Current date: $_currentDate');
    } catch (e) {
      debugPrint('❌ Start focus error: $e');
      _isFocusMode.value = false;
      _stopHeartbeat();
      rethrow;
    }
  }

  Future<void> stopFocusMode() async {
    try {
      debugPrint('🛑 Stopping focus mode...');
      
      _isFocusMode.value = false;
      _stopActiveTimer();
      _stopHeartbeat();
      _isPausedByWebSocket = false;
      
      if (_hasOverlayPermission) await hideOverlay();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(timerPausedByWebsocketKey);
      await prefs.remove(pausedTotalTimeKey);
      await _clearSnapshot();
      
      if (_timerStartTime != null) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        final finalTotal = _baseTimeWhenTimerStarted + elapsed;
        
        _focusTimeToday.value = finalTotal;
        
        await prefs.setInt(focusKey, finalTotal.inSeconds);
        await prefs.setInt(lastStoredFocusTimeKey, finalTotal.inSeconds);
        
        final today = DateTime.now().toIso8601String().split('T')[0];
        await prefs.setString(lastStoredFocusDateKey, today);
        
        debugPrint('✅ Final focus time saved: ${finalTotal.inSeconds}s');
        debugPrint('   - Base time when started: ${_baseTimeWhenTimerStarted.inSeconds}s');
        debugPrint('   - Session elapsed: ${elapsed.inSeconds}s');
        debugPrint('   - Final total: ${finalTotal.inSeconds}s');
      } else {
        debugPrint('⚠️ No timer start time found, using current value: ${_focusTimeToday.value.inSeconds}s');
        
        await prefs.setInt(focusKey, _focusTimeToday.value.inSeconds);
        await prefs.setInt(lastStoredFocusTimeKey, _focusTimeToday.value.inSeconds);
        
        final today = DateTime.now().toIso8601String().split('T')[0];
        await prefs.setString(lastStoredFocusDateKey, today);
      }
      
      await prefs.setBool(isFocusModeKey, false);
      await prefs.remove(focusStartTimeKey);
      await prefs.remove(focusElapsedKey);
      await prefs.remove(lastHeartbeatKey);
      await prefs.remove(wasWebsocketDisconnectedKey);
      
      await _saveAppState('stopped');
      
      _timerStartTime = null;
      _baseTimeWhenTimerStarted = Duration.zero;
      _exactTimeAtPause = Duration.zero;
      
      // Send combined heartbeat to WebSocket when stopping
      _handleHeartbeatWithFocusStatus();
      
      debugPrint('✅ Focus mode stopped successfully');
      
    } catch (e) {
      debugPrint('❌ Error stopping focus mode: $e');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(isFocusModeKey, false);
        _isFocusMode.value = false;
        _stopActiveTimer();
        _stopHeartbeat();
        _timerStartTime = null;
        _baseTimeWhenTimerStarted = Duration.zero;
        _exactTimeAtPause = Duration.zero;
        _isPausedByWebSocket = false;
        
        // Send combined heartbeat even on error
        _handleHeartbeatWithFocusStatus();
      } catch (cleanupError) {
        debugPrint('❌ Error during cleanup: $cleanupError');
      }
      
      rethrow;
    }
  }

  // Check if focus was stopped by WebSocket
  Future<bool> wasStoppedByWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(wasWebsocketDisconnectedKey) ?? false;
  }

  Future<Duration?> getLastStoredFocusTime() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(lastStoredFocusTimeKey);
    return seconds != null ? Duration(seconds: seconds) : null;
  }

  Future<String?> getLastStoredFocusDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastStoredFocusDateKey);
  }

  Future<void> handleAppPaused() async {
    _appInForeground = false;
    if (_isFocusMode.value && _timerStartTime != null) {
      final prefs = await SharedPreferences.getInstance();
      final elapsed = DateTime.now().difference(_timerStartTime!);
      await prefs.setInt(focusElapsedKey, elapsed.inSeconds);
      await _saveAppState('paused');
      await _sendHeartbeat();
      if (_hasOverlayPermission) {
        await Future.delayed(const Duration(milliseconds: 500));
        await showOverlay();
      }
    }
  }

  Future<void> handleAppResumed() async {
    _appInForeground = true;
    _lastAppResumeTime = DateTime.now();
    
    // Check for date change immediately on app resume
    await _checkForDateChange();
    
    if (_isFocusMode.value) {
      final prefs = await SharedPreferences.getInstance();
      final startTimeStr = prefs.getString(focusStartTimeKey);
      final elapsedSeconds = prefs.getInt(focusElapsedKey) ?? 0;
      
      await _saveAppState('resumed');
      
      if (startTimeStr != null) {
        _timerStartTime = DateTime.parse(startTimeStr);
        _focusTimeToday.value += Duration(seconds: elapsedSeconds);
        _startFocusTimer();
        _startHeartbeat();
        
        // Send combined heartbeat on app resume
        _handleHeartbeatWithFocusStatus();
      }
      
      if (_hasOverlayPermission) await hideOverlay();
    }
  }

  Future<void> logout() async {
    try {
      await shutdownForLogout();
    } catch (e) {
      await _forceHideOverlayWithRetries();
    }
  }

  Future<void> handleAppDetached() async {
    _stopActiveTimer();
    _stopHeartbeat();
    await _saveAppState('detached');
    
    if (_isFocusMode.value && _timerStartTime != null) {
      final prefs = await SharedPreferences.getInstance();
      final elapsed = DateTime.now().difference(_timerStartTime!);
      final finalTotal = _baseTimeWhenTimerStarted + elapsed;
      _focusTimeToday.value = finalTotal;
      await prefs.setInt(focusKey, finalTotal.inSeconds);
      await prefs.setInt(lastStoredFocusTimeKey, finalTotal.inSeconds);
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString(lastStoredFocusDateKey, today);
      
      _isFocusMode.value = false;
      await prefs.setBool(isFocusModeKey, false);
      
      // Send combined heartbeat on app detached
      _handleHeartbeatWithFocusStatus();
    }
    
    if (_hasOverlayPermission) await hideOverlay();
  }

  // Accurate timer with snapshot support
  void _startFocusTimer() {
    _stopActiveTimer();
    
    debugPrint('⏱️ Starting timer:');
    debugPrint('   - Base time: ${_baseTimeWhenTimerStarted.inSeconds}s');
    debugPrint('   - Display value: ${_focusTimeToday.value.inSeconds}s');
    debugPrint('   - Is paused by WS: $_isPausedByWebSocket');
    
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_timerStartTime != null && _isFocusMode.value && _appInForeground && !_isPausedByWebSocket) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        final total = _baseTimeWhenTimerStarted + elapsed;
        
        // Update UI value
        _focusTimeToday.value = total;
        
        // Create snapshot periodically (every 30 seconds)
        if (elapsed.inSeconds % 30 == 0) {
          final snapshot = _createSnapshot();
          await _saveSnapshot(snapshot);
        }
        
        // Send combined heartbeat periodically
        if (elapsed.inSeconds % 30 == 0 && WebSocketManager.isConnected) {
          _handleHeartbeatWithFocusStatus();
        }
        
        // Auto-save periodically
        if (elapsed.inSeconds % 30 == 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(focusKey, total.inSeconds);
          await prefs.setInt(lastStoredFocusTimeKey, total.inSeconds);
          final today = DateTime.now().toIso8601String().split('T')[0];
          await prefs.setString(lastStoredFocusDateKey, today);
          debugPrint('💾 Auto-saved: ${total.inSeconds}s');
          debugPrint('   - Base: ${_baseTimeWhenTimerStarted.inSeconds}s + Elapsed: ${elapsed.inSeconds}s');
        }
      } else if (!_isFocusMode.value || _isPausedByWebSocket) {
        _stopActiveTimer();
      }
    });
  }

  void _stopActiveTimer() {
    _activeTimer?.cancel();
    _activeTimer = null;
  }

  static Future<void> clearAllTimerData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(focusKey);
      await prefs.remove(lastDateKey);
      await prefs.remove(isFocusModeKey);
      await prefs.remove(focusStartTimeKey);
      await prefs.remove(focusElapsedKey);
      await prefs.remove(lastUserEmailKey);
      await prefs.remove(overlayPermissionKey);
      await prefs.remove(appStateKey);
      await prefs.remove(lastHeartbeatKey);
      await prefs.remove(heartbeatDateKey);
      await prefs.remove(lastStoredFocusTimeKey);
      await prefs.remove(lastStoredFocusDateKey);
      await prefs.remove(websocketDisconnectTimeKey);
      await prefs.remove(wasWebsocketDisconnectedKey);
      await prefs.remove(timerSnapshotKey);
      await prefs.remove(pausedTotalTimeKey);
      await prefs.remove(timerPausedByWebsocketKey);
      
      await Workmanager().cancelAll();
      TimerService()._resetInstance();
    } catch (e) {
      debugPrint('❌ Clear data error: $e');
    }
  }

  void _resetInstance() {
    _stopActiveTimer();
    _stopHeartbeat();
    _stopDateCheckTimer(); // NEW: Stop date check timer
    _focusTimeToday.value = Duration.zero;
    _isFocusMode.value = false;
    _timerStartTime = null;
    _baseTimeWhenTimerStarted = Duration.zero;
    _isInitialized = false;
    _hasOverlayPermission = false;
    _appInForeground = true;
    _lastAppResumeTime = null;
    _isWebSocketConnected = false;
    _lastWebSocketDisconnectTime = null;
    _onWebSocketDisconnectCallback = null;
    _exactTimeAtPause = Duration.zero;
    _isPausedByWebSocket = false;
    _currentDate = ''; // NEW: Reset current date
    
    // Clean up WebSocket subscriptions
    _websocketConnectionSubscription?.cancel();
    _websocketConnectionSubscription = null;
    WebSocketManager.removeCallbacks();
  }

  String getFormattedFocusTime() => _formatDuration(_focusTimeToday.value);

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void dispose() {
    if (_isInitialized) {
      _stopActiveTimer();
      _stopHeartbeat();
      _stopDateCheckTimer(); // NEW: Stop date check timer
      _websocketConnectionSubscription?.cancel();
      WebSocketManager.removeCallbacks();
      _isFocusMode.dispose();
      _focusTimeToday.dispose();
      _isInitialized = false;
    }
  }
}