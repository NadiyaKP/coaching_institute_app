import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart'; 
import 'package:web_socket_channel/web_socket_channel.dart';

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
  
  // 🆕 WebSocket state tracking
  static bool _isWebSocketConnected = false;
  static DateTime? _lastWebSocketDisconnectTime;
  StreamSubscription? _websocketSubscription;

  final ValueNotifier<bool> _isFocusMode = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isFocusMode => _isFocusMode;

  final ValueNotifier<Duration> _focusTimeToday = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get focusTimeToday => _focusTimeToday;

  Timer? _activeTimer;
  Timer? _heartbeatTimer;
  DateTime? _timerStartTime;
  Duration _baseTimeWhenTimerStarted = Duration.zero; // 🔥 NEW: Track base time when timer starts
  bool _isInitialized = false;
  String? _currentUserEmail;
  bool _hasOverlayPermission = false;
  DateTime? _lastAppResumeTime;
  bool _appInForeground = true;

  bool get hasOverlayPermission => _hasOverlayPermission;
  static const MethodChannel _overlayChannel = MethodChannel('focus_mode_overlay_channel');

  // Initialize WebSocket monitoring
  Future<void> _initializeWebSocketMonitoring() async {
    try {
      _startWebSocketMonitor();
    } catch (e) {
      debugPrint('❌ WebSocket monitoring init error: $e');
    }
  }

  void _startWebSocketMonitor() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final bool wasConnected = _isWebSocketConnected;
        
        // Replace this with actual WebSocket connection check
        _isWebSocketConnected = true; // TODO: Replace with actual check
        
        if (wasConnected && !_isWebSocketConnected) {
          debugPrint('🔌 WebSocket disconnected - stopping focus mode');
          _handleWebSocketDisconnection();
        } else if (!wasConnected && _isWebSocketConnected) {
          debugPrint('🔗 WebSocket reconnected');
          _lastWebSocketDisconnectTime = null;
        }
      } catch (e) {
        debugPrint('❌ WebSocket monitor error: $e');
      }
    });
  }

  Future<void> _handleWebSocketDisconnection() async {
    try {
      if (_isFocusMode.value) {
        debugPrint('⏸️ WebSocket disconnected - pausing focus timer');
        
        await _storeFocusTimeOnDisconnect();
        
        _isFocusMode.value = false;
        _stopActiveTimer();
        _stopHeartbeat();
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(isFocusModeKey, false);
        
        _lastWebSocketDisconnectTime = DateTime.now();
        await prefs.setString(websocketDisconnectTimeKey, 
            _lastWebSocketDisconnectTime!.toIso8601String());
        
        final currentTime = _focusTimeToday.value.inSeconds;
        await prefs.setInt(lastStoredFocusTimeKey, currentTime);
        final today = DateTime.now().toIso8601String().split('T')[0];
        await prefs.setString(lastStoredFocusDateKey, today);
        
        debugPrint('✅ Focus mode paused due to WebSocket disconnect');
        debugPrint('💾 Stored focus time: ${currentTime}s on $today');
      }
    } catch (e) {
      debugPrint('❌ Error handling WebSocket disconnection: $e');
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

  // 🔥 FIXED: startFocusMode method
  Future<void> startFocusMode({bool skipPermissionCheck = false}) async {
    try {
      if (_currentUserEmail == null) {
        _currentUserEmail = await _getCurrentUserEmail();
        if (_currentUserEmail == null) throw Exception('No user');
      }
      
      if (!skipPermissionCheck && !await checkOverlayPermission()) {
        throw Exception('Overlay permission required');
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(websocketDisconnectTimeKey);
      
      // 🔥 CRITICAL: Save the current accumulated time as the base
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
      
      await _registerBackgroundTask();
      
      debugPrint('✅ Focus mode started');
    } catch (e) {
      debugPrint('❌ Start focus error: $e');
      _isFocusMode.value = false;
      _stopHeartbeat();
      rethrow;
    }
  }

  // 🔥 FIXED: stopFocusMode method
  Future<void> stopFocusMode() async {
    try {
      debugPrint('🛑 Stopping focus mode...');
      
      _isFocusMode.value = false;
      _stopActiveTimer();
      _stopHeartbeat();
      
      if (_hasOverlayPermission) await hideOverlay();
      
      final prefs = await SharedPreferences.getInstance();
      
      if (_timerStartTime != null) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        
        // 🔥 CRITICAL: Use the base time that was set when timer STARTED
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
      
      await _saveAppState('stopped');
      
      _timerStartTime = null;
      _baseTimeWhenTimerStarted = Duration.zero;
      
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
      } catch (cleanupError) {
        debugPrint('❌ Error during cleanup: $cleanupError');
      }
      
      rethrow;
    }
  }

  Future<void> handleWebSocketDisconnection() async {
    await _handleWebSocketDisconnection();
  }

  Future<bool> wasFocusStoppedByWebSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final disconnectTimeStr = prefs.getString(websocketDisconnectTimeKey);
    return disconnectTimeStr != null;
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
    }
    
    if (_hasOverlayPermission) await hideOverlay();
  }

  // 🔥 FIXED: _startFocusTimer method
  void _startFocusTimer() {
    _stopActiveTimer();
    
    debugPrint('⏱️ Starting timer with base: ${_baseTimeWhenTimerStarted.inSeconds}s');
    
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_timerStartTime != null && _isFocusMode.value && _appInForeground) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        
        // 🔥 CRITICAL: Use base time from when timer started
        final total = _baseTimeWhenTimerStarted + elapsed;
        
        if (_focusTimeToday.value != total) {
          _focusTimeToday.value = total;
        }
        
        if (elapsed.inSeconds % 30 == 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(focusKey, total.inSeconds);
          await prefs.setInt(lastStoredFocusTimeKey, total.inSeconds);
          final today = DateTime.now().toIso8601String().split('T')[0];
          await prefs.setString(lastStoredFocusDateKey, today);
          debugPrint('💾 Auto-saved: ${total.inSeconds}s (base: ${_baseTimeWhenTimerStarted.inSeconds}s + elapsed: ${elapsed.inSeconds}s)');
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
    _baseTimeWhenTimerStarted = Duration.zero; // 🔥 RESET BASE TIME
    _isInitialized = false;
    _hasOverlayPermission = false;
    _appInForeground = true;
    _lastAppResumeTime = null;
    _isWebSocketConnected = false;
    _lastWebSocketDisconnectTime = null;
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
      _isFocusMode.dispose();
      _focusTimeToday.dispose();
      _isInitialized = false;
    }
  }
}