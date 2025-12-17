import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart'; 
import 'websocket_manager.dart';
import 'dart:convert';

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
  static const String timerStateBeforeDisconnectKey = 'timer_state_before_disconnect';
  
  // 🆕 WebSocket state tracking
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
  DateTime? _timerStartTime;
  Duration _baseTimeWhenTimerStarted = Duration.zero;
  bool _isInitialized = false;
  String? _currentUserEmail;
  bool _hasOverlayPermission = false;
  DateTime? _lastAppResumeTime;
  bool _appInForeground = true;
  
  // 🆕 NEW: Callback to navigate back to entry screen
  Function()? _onWebSocketDisconnectCallback;

  bool get hasOverlayPermission => _hasOverlayPermission;
  static const MethodChannel _overlayChannel = MethodChannel('focus_mode_overlay_channel');

  // 🆕 NEW: Set callback for WebSocket disconnection
  void setWebSocketDisconnectCallback(Function() callback) {
    _onWebSocketDisconnectCallback = callback;
  }

  // 🆕 NEW: Initialize WebSocket monitoring
  Future<void> _initializeWebSocketMonitoring() async {
    try {
      _startWebSocketMonitor();
    } catch (e) {
      debugPrint('❌ WebSocket monitoring init error: $e');
    }
  }

  void _startWebSocketMonitor() {
    // 🆕 NEW: Register callback to send focus status when WebSocket requests it
    WebSocketManager.registerFocusStatusRequestCallback(() {
      _handleHeartbeatWithFocusStatus();
    });
    
    // 🆕 NEW: Listen to WebSocket connection state changes
    _websocketConnectionSubscription?.cancel();
    _websocketConnectionSubscription = WebSocketManager.connectionStateStream.listen((isConnected) async {  
      debugPrint('🔌 WebSocket connection state changed: $isConnected');
      
      final bool wasConnected = _isWebSocketConnected;
      _isWebSocketConnected = isConnected;
      
      if (wasConnected && !_isWebSocketConnected) {
        debugPrint('🔌 WebSocket disconnected - pausing focus mode');
        _handleWebSocketDisconnection();
      } else if (!wasConnected && _isWebSocketConnected) {
        debugPrint('🔗 WebSocket reconnected - checking for paused timer');
        _lastWebSocketDisconnectTime = null;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(wasWebsocketDisconnectedKey);
        
        // 🆕 NEW: Send focus status immediately on reconnection
        _sendFocusStatusToWebSocket();
        
        // 🆕 NEW: Check if timer was paused by WebSocket and resume it
        await _checkAndResumeTimerAfterReconnect();
      }
    });
    
    // 🆕 NEW: Also listen to the reconnected stream for additional safety
    WebSocketManager.reconnectedStream.listen((_) async {
      debugPrint('🔗 WebSocketManager.reconnectedStream fired');
      await _checkAndResumeTimerAfterReconnect();
    });
    
    // 🆕 NEW: Register callback in WebSocketManager
    WebSocketManager.registerDisconnectionCallback(() {
      if (_isFocusMode.value) {
        debugPrint('🔌 Immediate WebSocket disconnection detected');
        _handleWebSocketDisconnection();
      }
    });
    
    // 🆕 NEW: Register reconnection callback
    WebSocketManager.registerReconnectionCallback(() {
      debugPrint('🔗 WebSocket reconnection callback - resuming timer');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndResumeTimerAfterReconnect();
      });
    });
  }

  // 🆕 NEW: Send focus status to WebSocket
  void _sendFocusStatusToWebSocket() {
    if (WebSocketManager.isConnected) {
      final isFocusing = _isFocusMode.value ? 1 : 0;
      WebSocketManager.sendFocusStatus(_isFocusMode.value);
      debugPrint('📤 Focus status sent via WebSocket: is_focusing=$isFocusing');
    } else {
      debugPrint('⚠️ Cannot send focus status - WebSocket not connected');
    }
  }

  // 🆕 NEW: Handle heartbeat with focus status
  void _handleHeartbeatWithFocusStatus() {
    if (WebSocketManager.isConnected) {
      final isFocusing = _isFocusMode.value ? 1 : 0;
      WebSocketManager.sendCombinedHeartbeat(_isFocusMode.value);
      debugPrint('💓 Combined heartbeat sent: is_focusing=$isFocusing');
    }
  }

 Future<void> _checkAndResumeTimerAfterReconnect() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final wasPausedByWebSocket = prefs.getBool(timerPausedByWebsocketKey) ?? false;
    
    if (wasPausedByWebSocket) {
      debugPrint('🔄 Timer was paused by WebSocket - attempting to resume');
      
      // Check if we should resume
      final stateJson = prefs.getString(timerStateBeforeDisconnectKey);
      if (stateJson != null) {
        final state = jsonDecode(stateJson);
        final timestamp = DateTime.parse(state['timestamp']);
        final timeSincePause = DateTime.now().difference(timestamp);
        
        debugPrint('📊 Resume check:');
        debugPrint('   - Time since pause: ${timeSincePause.inSeconds}s');
        debugPrint('   - Saved total: ${state['currentTotal']}s');
        
        // Only resume if it's been less than 5 minutes
        if (timeSincePause < const Duration(minutes: 5)) {
          debugPrint('⏱️ Resuming timer from saved state');
          
          // Restore exact timer state
          final exactTotal = Duration(seconds: state['currentTotal']);
          
          _isFocusMode.value = true;
          _baseTimeWhenTimerStarted = exactTotal; // Set base to exact paused value
          _timerStartTime = DateTime.now(); // Start new session from now
          _focusTimeToday.value = exactTotal; // Set UI to exact value
          
          debugPrint('📊 Resume values:');
          debugPrint('   - Base time: ${_baseTimeWhenTimerStarted.inSeconds}s');
          debugPrint('   - Display value: ${_focusTimeToday.value.inSeconds}s');
          debugPrint('   - New session starts: now');
          
          // Update shared preferences
          await prefs.setBool(isFocusModeKey, true);
          await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
          await prefs.setInt(focusKey, exactTotal.inSeconds);
          await prefs.setInt(lastStoredFocusTimeKey, exactTotal.inSeconds);
          
          // Start the timer
          _startFocusTimer();
          _startHeartbeat();
          
          // Send combined heartbeat after resuming
          _handleHeartbeatWithFocusStatus();
          
          debugPrint('✅ Timer resumed successfully at exactly: ${exactTotal.inSeconds}s (${_formatDuration(exactTotal)})');
        } else {
          debugPrint('⏰ Too much time has passed (${timeSincePause.inMinutes}min), not resuming');
        }
      } else {
        debugPrint('⚠️ No saved state found - cannot resume');
      }
      
      // Clean up flags
      await prefs.remove(timerPausedByWebsocketKey);
      await prefs.remove(timerStateBeforeDisconnectKey);
    }
  } catch (e) {
    debugPrint('❌ Error checking/resuming timer: $e');
  }
}

Future<void> _handleWebSocketDisconnection() async {
  try {
    if (_isFocusMode.value) {
      debugPrint('🔌 WebSocket disconnected - pausing focus timer');
      
      // Save timer state BEFORE any modifications
      await _saveTimerStateBeforeDisconnect();
      
      // Pause the timer without losing precision
      await _pauseTimerForWebSocketDisconnect();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(timerPausedByWebsocketKey, true);
      await prefs.setBool(wasWebsocketDisconnectedKey, true);
      
      _lastWebSocketDisconnectTime = DateTime.now();
      await prefs.setString(websocketDisconnectTimeKey, 
          _lastWebSocketDisconnectTime!.toUtc().toIso8601String()); // Use UTC
      
      debugPrint('⏸️ Focus timer paused due to WebSocket disconnect');
      
      // Hide overlay if shown
      if (_hasOverlayPermission) {
        await hideOverlay();
      }
      
      // Trigger callback to show connection lost UI
      if (_onWebSocketDisconnectCallback != null) {
        debugPrint('🔄 Triggering navigation callback');
        _onWebSocketDisconnectCallback!();
      }
    }
  } catch (e) {
    debugPrint('❌ Error handling WebSocket disconnection: $e');
  }
}
  
  Future<void> _pauseTimerForWebSocketDisconnect() async {
  debugPrint('⏸️ Pausing timer for WebSocket disconnect');
  
  // Stop active timer
  _stopActiveTimer();
  _stopHeartbeat();
  
  // Calculate and store exact current time
  if (_timerStartTime != null) {
    final elapsed = DateTime.now().difference(_timerStartTime!);
    final exactTotal = _baseTimeWhenTimerStarted + elapsed;
    
    debugPrint('📊 Pause calculation:');
    debugPrint('   - Base time: ${_baseTimeWhenTimerStarted.inSeconds}s');
    debugPrint('   - Session elapsed: ${elapsed.inSeconds}s');
    debugPrint('   - Exact total: ${exactTotal.inSeconds}s');
    
    // Update the focus time to exact current value
    _focusTimeToday.value = exactTotal;
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(focusKey, exactTotal.inSeconds);
    await prefs.setInt(lastStoredFocusTimeKey, exactTotal.inSeconds);
    
    // Reset base time to current total for accurate resume
    _baseTimeWhenTimerStarted = exactTotal;
    _timerStartTime = null;
    
    debugPrint('✅ Timer paused at exactly: ${exactTotal.inSeconds}s (${_formatDuration(exactTotal)})');
  }
}

  Future<void> _saveTimerStateBeforeDisconnect() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Calculate exact current total
    Duration currentTotal = _baseTimeWhenTimerStarted;
    if (_timerStartTime != null) {
      final elapsed = DateTime.now().difference(_timerStartTime!);
      currentTotal = _baseTimeWhenTimerStarted + elapsed;
    }
    
    // Save current timer state with precise values
    final state = {
      'isFocusMode': _isFocusMode.value,
      'currentTotal': currentTotal.inSeconds, // Exact total time
      'timestamp': DateTime.now().toUtc().toIso8601String(), // Use UTC
    };
    
    await prefs.setString(timerStateBeforeDisconnectKey, jsonEncode(state));
    debugPrint('💾 Timer state saved at disconnect:');
    debugPrint('   - Current total: ${currentTotal.inSeconds}s (${_formatDuration(currentTotal)})');
    debugPrint('   - Timestamp: ${state['timestamp']}');
    
  } catch (e) {
    debugPrint('❌ Error saving timer state: $e');
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
      
      // 🆕 NEW: Send combined heartbeat with focus status when WebSocket is connected
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
          
          // 🆕 NEW: Send combined heartbeat on initialization if WebSocket is connected
          if (WebSocketManager.isConnected) {
            _handleHeartbeatWithFocusStatus();
          }
        } else {
          _isFocusMode.value = false;
          await prefs.setBool(isFocusModeKey, false);
        }
      }
      
      await _registerBackgroundTask();
      await prefs.setString(lastUserEmailKey, _currentUserEmail!);
      await _saveAppState('resumed');
      _isInitialized = true;
      
      await _initializeWebSocketMonitoring();
      
      debugPrint('✅ Initialized for: $_currentUserEmail');
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

  // 🆕 MODIFIED: Check WebSocket connection before starting
  Future<void> startFocusMode({bool skipPermissionCheck = false}) async {
    try {
      // 🆕 NEW: Check WebSocket connection first
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
      
      final currentSavedSeconds = prefs.getInt(focusKey) ?? 0;
      _baseTimeWhenTimerStarted = Duration(seconds: currentSavedSeconds);
      
      debugPrint('🚀 Starting focus mode with base time: ${currentSavedSeconds}s');
      
      _isFocusMode.value = true;
      _timerStartTime = DateTime.now();
      _appInForeground = true;
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      await prefs.setBool(isFocusModeKey, true);
      await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
      await prefs.setString(lastDateKey, today);
      await prefs.setString(heartbeatDateKey, today);
      await prefs.remove(focusElapsedKey);
      await _saveAppState('resumed');
      
      _startFocusTimer();
      _startHeartbeat();
      
      // 🆕 NEW: Send combined heartbeat to WebSocket
      _handleHeartbeatWithFocusStatus();
      
      await _registerBackgroundTask();
      
      debugPrint('✅ Focus mode started');
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
      
      if (_hasOverlayPermission) await hideOverlay();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(timerPausedByWebsocketKey);
      await prefs.remove(timerStateBeforeDisconnectKey);
      
      if (_timerStartTime != null) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        final finalTotal = _baseTimeWhenTimerStarted + elapsed;
        
        _focusTimeToday.value = finalTotal;
        
        await prefs.setInt(focusKey, finalTotal.inSeconds);
        await prefs.setInt(lastStoredFocusTimeKey, finalTotal.inSeconds);
        
        final today = DateTime.now().toIso8601String().split('T')[0];
        await prefs.setString(lastStoredFocusDateKey, today);
        
        debugPrint('✅ Final focus time saved: ${finalTotal.inSeconds}s (${_formatDuration(finalTotal)})');
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
      
      // 🆕 NEW: Send combined heartbeat to WebSocket when stopping
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
        
        // 🆕 NEW: Send combined heartbeat even on error
        _handleHeartbeatWithFocusStatus();
      } catch (cleanupError) {
        debugPrint('❌ Error during cleanup: $cleanupError');
      }
      
      rethrow;
    }
  }

  // 🆕 NEW: Check if focus was stopped by WebSocket
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
        
        // 🆕 NEW: Send combined heartbeat on app resume
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
      
      // 🆕 NEW: Send combined heartbeat on app detached
      _handleHeartbeatWithFocusStatus();
    }
    
    if (_hasOverlayPermission) await hideOverlay();
  }

  void _startFocusTimer() {
  _stopActiveTimer();
  
  debugPrint('⏱️ Starting timer:');
  debugPrint('   - Base time: ${_baseTimeWhenTimerStarted.inSeconds}s (${_formatDuration(_baseTimeWhenTimerStarted)})');
  debugPrint('   - Display value: ${_focusTimeToday.value.inSeconds}s (${_formatDuration(_focusTimeToday.value)})');
  
  _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (_timerStartTime != null && _isFocusMode.value && _appInForeground) {
      final elapsed = DateTime.now().difference(_timerStartTime!);
      final total = _baseTimeWhenTimerStarted + elapsed;
      
      // Update UI value
      _focusTimeToday.value = total;
      
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
        debugPrint('💾 Auto-saved: ${total.inSeconds}s (${_formatDuration(total)})');
        debugPrint('   - Base: ${_baseTimeWhenTimerStarted.inSeconds}s + Elapsed: ${elapsed.inSeconds}s');
      }
    } else if (!_isFocusMode.value) {
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
      
      await Workmanager().cancelAll();
      TimerService()._resetInstance();
    } catch (e) {
      debugPrint('❌ Clear data error: $e');
    }
  }

  void _resetInstance() {
    _stopActiveTimer();
    _stopHeartbeat();
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
    
    // 🆕 NEW: Clean up WebSocket subscriptions
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
      _websocketConnectionSubscription?.cancel();
      WebSocketManager.removeCallbacks();
      _isFocusMode.dispose();
      _focusTimeToday.dispose();
      _isInitialized = false;
    }
  }
}