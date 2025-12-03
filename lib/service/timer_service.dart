import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart'; // 🆕 Added for MethodChannel

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  // Public static keys for SharedPreferences (GLOBAL - not user-specific)
  static const String focusKey = 'focus_time_today';
  static const String lastDateKey = 'last_timer_date';
  static const String isFocusModeKey = 'is_focus_mode';
  static const String focusStartTimeKey = 'focus_start_time';
  static const String focusElapsedKey = 'focus_elapsed_before_pause';
  static const String lastUserEmailKey = 'last_timer_user_email';
  static const String overlayPermissionKey = 'overlay_permission_granted';

  final ValueNotifier<bool> _isFocusMode = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isFocusMode => _isFocusMode;

  final ValueNotifier<Duration> _focusTimeToday = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get focusTimeToday => _focusTimeToday;

  Timer? _activeTimer;
  DateTime? _timerStartTime;
  bool _isInitialized = false;
  String? _currentUserEmail;
  bool _hasOverlayPermission = false;

  // 🆕 Getter for overlay permission
  bool get hasOverlayPermission => _hasOverlayPermission;

  // 🆕 Method channel for native overlay
  static const MethodChannel _overlayChannel = MethodChannel('focus_mode_overlay_channel');

  // Initialize background service
  static Future<void> initializeBackgroundService() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    
    debugPrint('✅ TimerService: Background service initialized');
  }

  // Callback for background work
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now().toIso8601String().split('T')[0];
        final lastDate = prefs.getString(lastDateKey);
        
        // Check if it's a new day
        if (lastDate != today) {
          await prefs.setString(lastDateKey, today);
          await prefs.setInt(focusKey, 0);
          await prefs.setBool(isFocusModeKey, false);
          await prefs.remove(focusStartTimeKey);
          await prefs.remove(focusElapsedKey);
        }
        
        // Update focus timer if active
        final isFocusActive = prefs.getBool(isFocusModeKey) ?? false;
        if (isFocusActive) {
          final startTimeStr = prefs.getString(focusStartTimeKey);
          
          if (startTimeStr != null) {
            final startTime = DateTime.parse(startTimeStr);
            final elapsedBeforePause = Duration(seconds: prefs.getInt(focusElapsedKey) ?? 0);
            final now = DateTime.now();
            final elapsed = now.difference(startTime) + elapsedBeforePause;
            
            final currentTotal = Duration(seconds: prefs.getInt(focusKey) ?? 0);
            final newTotal = currentTotal + elapsed;
            
            await prefs.setInt(focusKey, newTotal.inSeconds);
          }
        }
        
        return Future.value(true);
      } catch (e) {
        return Future.value(true);
      }
    });
  }

  // 🆕 Check overlay permission
  Future<bool> checkOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.status;
      _hasOverlayPermission = status.isGranted;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(overlayPermissionKey, _hasOverlayPermission);
      
      debugPrint('🎯 TimerService: Overlay permission status: $_hasOverlayPermission');
      return _hasOverlayPermission;
    } catch (e) {
      debugPrint('❌ TimerService: Error checking overlay permission: $e');
      return false;
    }
  }

  // 🆕 Request overlay permission
  Future<bool> requestOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.request();
      _hasOverlayPermission = status.isGranted;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(overlayPermissionKey, _hasOverlayPermission);
      
      debugPrint('🎯 TimerService: Overlay permission requested - granted: $_hasOverlayPermission');
      return _hasOverlayPermission;
    } catch (e) {
      debugPrint('❌ TimerService: Error requesting overlay permission: $e');
      return false;
    }
  }

  // 🆕 NEW: Show overlay (called when app goes to background)
  Future<void> showOverlay() async {
    try {
      if (_isFocusMode.value && _hasOverlayPermission) {
        debugPrint('🎯 TimerService: Showing overlay (app in background)');
        final result = await _overlayChannel.invokeMethod('showOverlay', {
          'message': 'You are in focus mode, focus on studies',
        });
        
        if (result == true) {
          debugPrint('✅ TimerService: Overlay shown successfully');
        } else {
          debugPrint('⚠️ TimerService: Failed to show overlay');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('❌ TimerService: Error showing overlay: ${e.message}');
    } catch (e) {
      debugPrint('❌ TimerService: Unexpected error showing overlay: $e');
    }
  }

  // 🆕 NEW: Hide overlay (called when app comes to foreground)
  Future<void> hideOverlay() async {
    try {
      debugPrint('🎯 TimerService: Hiding overlay (app in foreground)');
      final result = await _overlayChannel.invokeMethod('hideOverlay');
      
      if (result == true) {
        debugPrint('✅ TimerService: Overlay hidden successfully');
      } else {
        debugPrint('⚠️ TimerService: Failed to hide overlay');
      }
    } on PlatformException catch (e) {
      debugPrint('❌ TimerService: Error hiding overlay: ${e.message}');
    } catch (e) {
      debugPrint('❌ TimerService: Unexpected error hiding overlay: $e');
    }
  }

  // 🆕 Get current user email from SharedPreferences
  Future<String?> _getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    
    String? userEmail = prefs.getString('username');
    
    if (userEmail == null || userEmail.isEmpty) {
      userEmail = prefs.getString('profile_email');
    }
    
    if (userEmail == null || userEmail.isEmpty) {
      userEmail = prefs.getString('user_email');
    }
    
    debugPrint('📧 TimerService looking for user email:');
    debugPrint('   - Found email: $userEmail');
    
    return userEmail;
  }

  // Initialize timer service
  Future<void> initialize() async {
    try {
      debugPrint('🔄 TimerService: Initializing...');
      final prefs = await SharedPreferences.getInstance();
      
      // Get current user email
      _currentUserEmail = await _getCurrentUserEmail();
      
      if (_currentUserEmail == null || _currentUserEmail!.isEmpty) {
        debugPrint('👤 TimerService: No user email found in SharedPreferences');
        _resetInstance();
        return;
      }
      
      debugPrint('👤 TimerService: User email found: $_currentUserEmail');
      
      // 🆕 Check overlay permission
      _hasOverlayPermission = prefs.getBool(overlayPermissionKey) ?? false;
      debugPrint('🎯 TimerService: Loaded overlay permission: $_hasOverlayPermission');
      
      // Check if user changed since last initialization
      final lastUserEmail = prefs.getString(lastUserEmailKey);
      
      if (lastUserEmail != _currentUserEmail) {
        debugPrint('👤 TimerService: User changed from $lastUserEmail to $_currentUserEmail');
        debugPrint('🧹 Clearing all timer data for new user...');
        
        await prefs.remove(focusKey);
        await prefs.remove(lastDateKey);
        await prefs.remove(isFocusModeKey);
        await prefs.remove(focusStartTimeKey);
        await prefs.remove(focusElapsedKey);
        
        await prefs.setString(lastDateKey, DateTime.now().toIso8601String().split('T')[0]);
        await prefs.setInt(focusKey, 0);
        await prefs.setBool(isFocusModeKey, false);
        
        _resetInstance();
        
        debugPrint('✅ Timer data cleared for new user: $_currentUserEmail');
      } else if (_isInitialized) {
        debugPrint('⚠️ TimerService: Already initialized for user $_currentUserEmail');
        return;
      }
      
      // Check if it's a new day
      final lastDate = prefs.getString(lastDateKey);
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      if (lastDate != today) {
        debugPrint('📅 TimerService: New day detected, resetting timers');
        await prefs.setString(lastDateKey, today);
        await prefs.setInt(focusKey, 0);
        _focusTimeToday.value = Duration.zero;
        await prefs.setBool(isFocusModeKey, false);
        await prefs.remove(focusStartTimeKey);
        await prefs.remove(focusElapsedKey);
      } else {
        final savedSeconds = prefs.getInt(focusKey) ?? 0;
        _focusTimeToday.value = Duration(seconds: savedSeconds);
        debugPrint('📊 TimerService: Loaded focus time: ${_formatDuration(_focusTimeToday.value)}');
      }
      
      _isFocusMode.value = prefs.getBool(isFocusModeKey) ?? false;
      debugPrint('🎯 TimerService: Focus mode active: ${_isFocusMode.value}');
      
      // If focus mode is active, start the timer
      if (_isFocusMode.value) {
        final startTimeStr = prefs.getString(focusStartTimeKey);
        final elapsedSeconds = prefs.getInt(focusElapsedKey) ?? 0;
        
        if (startTimeStr != null) {
          _timerStartTime = DateTime.parse(startTimeStr);
          _focusTimeToday.value += Duration(seconds: elapsedSeconds);
          debugPrint('⏱️ TimerService: Resuming timer from saved state');
          debugPrint('   - Start time: $_timerStartTime');
          debugPrint('   - Elapsed before: ${elapsedSeconds}s');
          debugPrint('   - Total: ${_focusTimeToday.value.inSeconds}s');
          _startFocusTimer();
        } else {
          debugPrint('⚠️ TimerService: Focus mode active but no start time found');
          _isFocusMode.value = false;
          await prefs.setBool(isFocusModeKey, false);
        }
      }
      
      await _registerBackgroundTask();
      
      await prefs.setString(lastUserEmailKey, _currentUserEmail!);
      _isInitialized = true;
      debugPrint('✅ TimerService: Initialization complete for user: $_currentUserEmail');
      
      debugPrint('📋 TimerService Current State:');
      debugPrint('   - Focus Time: ${_focusTimeToday.value.inSeconds} seconds');
      debugPrint('   - Focus Mode: ${_isFocusMode.value}');
      debugPrint('   - Timer Active: ${_activeTimer != null}');
      debugPrint('   - Start Time: $_timerStartTime');
      debugPrint('   - Overlay Permission: $_hasOverlayPermission');
      
    } catch (e) {
      debugPrint('❌ TimerService: Error during initialization: $e');
      rethrow;
    }
  }

  // 🆕 Helper method to register background task with proper configuration
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
        inputData: <String, dynamic>{
          'silent': true,
          'notification_title': 'Study Timer',
          'notification_body': 'Tracking your study time...',
        },
      );
      
      debugPrint('✅ Background task registered (silent mode)');
    } catch (e) {
      debugPrint('❌ Error registering background task: $e');
    }
  }

  // 🆕 Modified: Start focus mode with permission check
  Future<void> startFocusMode({bool skipPermissionCheck = false}) async {
    debugPrint('🚀 TimerService: Starting focus mode for user: $_currentUserEmail');
    
    try {
      // First, ensure we have the current user
      if (_currentUserEmail == null) {
        _currentUserEmail = await _getCurrentUserEmail();
        if (_currentUserEmail == null) {
          throw Exception('No user logged in');
        }
      }
      
      // 🆕 Check overlay permission if not skipping
      if (!skipPermissionCheck) {
        final hasPermission = await checkOverlayPermission();
        if (!hasPermission) {
          debugPrint('🎯 TimerService: Overlay permission not granted');
          throw Exception('Overlay permission required');
        }
      }
      
      _isFocusMode.value = true;
      _timerStartTime = DateTime.now();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isFocusModeKey, true);
      await prefs.setString(focusStartTimeKey, _timerStartTime!.toIso8601String());
      await prefs.remove(focusElapsedKey);
      
      debugPrint('   - Start time: $_timerStartTime');
      debugPrint('   - User: $_currentUserEmail');
      debugPrint('   - Overlay Permission: $_hasOverlayPermission');
      
      _startFocusTimer();
      
      await prefs.setInt(focusKey, _focusTimeToday.value.inSeconds);
      
      await _registerBackgroundTask();
      
      debugPrint('✅ TimerService: Focus mode started successfully');
      debugPrint('   - Timer started at: ${DateTime.now()}');
      debugPrint('   - Current focus time: ${_focusTimeToday.value.inSeconds}s');
      
    } catch (e) {
      debugPrint('❌ TimerService: Error starting focus mode: $e');
      _isFocusMode.value = false;
      rethrow;
    }
  }

  // Stop focus mode
  Future<void> stopFocusMode() async {
    debugPrint('🛑 TimerService: Stopping focus mode');
    
    try {
      _isFocusMode.value = false;
      _stopActiveTimer();
      
      // 🆕 Hide overlay when stopping focus mode
      if (_hasOverlayPermission) {
        await hideOverlay();
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(isFocusModeKey, false);
      
      if (_timerStartTime != null) {
        final elapsed = DateTime.now().difference(_timerStartTime!);
        await prefs.setInt(focusElapsedKey, elapsed.inSeconds);
        debugPrint('   - Elapsed time saved: ${elapsed.inSeconds}s');
        
        _focusTimeToday.value += elapsed;
        await prefs.setInt(focusKey, _focusTimeToday.value.inSeconds);
      }
      
      await prefs.remove(focusStartTimeKey);
      
      debugPrint('✅ TimerService: Focus mode stopped successfully');
      debugPrint('   - Total focus time: ${_focusTimeToday.value.inSeconds}s');
      
    } catch (e) {
      debugPrint('❌ TimerService: Error stopping focus mode: $e');
      rethrow;
    }
  }

  // 🆕 UPDATED: Handle app paused with overlay
  Future<void> handleAppPaused() async {
    debugPrint('📱 TimerService: App paused');
    
    if (_isFocusMode.value && _timerStartTime != null) {
      debugPrint('📱 App paused, saving timer state...');
      final prefs = await SharedPreferences.getInstance();
      final elapsed = DateTime.now().difference(_timerStartTime!);
      await prefs.setInt(focusElapsedKey, elapsed.inSeconds);
      debugPrint('   - Elapsed time saved for background: ${elapsed.inSeconds}s');
      
      // 🆕 Show overlay if permission is granted
      if (_hasOverlayPermission) {
        // Wait a moment before showing overlay to ensure app is in background
        await Future.delayed(const Duration(milliseconds: 500));
        await showOverlay();
      }
    }
  }

  // 🆕 UPDATED: Handle app resumed with overlay
  Future<void> handleAppResumed() async {
    debugPrint('📱 TimerService: App resumed');
    
    if (_isFocusMode.value) {
      debugPrint('📱 App resumed, checking timer state...');
      final prefs = await SharedPreferences.getInstance();
      final startTimeStr = prefs.getString(focusStartTimeKey);
      final elapsedSeconds = prefs.getInt(focusElapsedKey) ?? 0;
      
      if (startTimeStr != null) {
        _timerStartTime = DateTime.parse(startTimeStr);
        _focusTimeToday.value += Duration(seconds: elapsedSeconds);
        debugPrint('   - Timer resumed with ${elapsedSeconds}s background time');
        _startFocusTimer();
      }
      
      // 🆕 Hide overlay when app comes to foreground
      if (_hasOverlayPermission) {
        await hideOverlay();
      }
    }
  }

  // Private timer methods
  void _startFocusTimer() {
    debugPrint('⏱️ TimerService: Starting focus timer');
    
    _stopActiveTimer();
    
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerStartTime != null && _isFocusMode.value) {
        final now = DateTime.now();
        final elapsed = now.difference(_timerStartTime!);
        
        SharedPreferences.getInstance().then((prefs) {
          try {
            final savedSeconds = prefs.getInt(focusKey) ?? 0;
            final elapsedBefore = Duration(seconds: prefs.getInt(focusElapsedKey) ?? 0);
            final total = Duration(seconds: savedSeconds) + elapsedBefore + elapsed;
            
            if (_focusTimeToday.value != total) {
              _focusTimeToday.value = total;
            }
            
            if (elapsed.inSeconds % 30 == 0) {
              prefs.setInt(focusKey, total.inSeconds);
            }
          } catch (e) {
            debugPrint('❌ Timer tick error: $e');
          }
        });
      } else if (!_isFocusMode.value) {
        _stopActiveTimer();
      }
    });
    
    debugPrint('✅ TimerService: Timer started successfully');
  }

  void _stopActiveTimer() {
    if (_activeTimer != null) {
      _activeTimer!.cancel();
      _activeTimer = null;
      debugPrint('⏹️ TimerService: Timer stopped');
    }
  }

  // 🆕 Clear ALL timer data (call this on logout)
  static Future<void> clearAllTimerData() async {
    try {
      debugPrint('🧹 TimerService: Clearing ALL timer data...');
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(focusKey);
      await prefs.remove(lastDateKey);
      await prefs.remove(isFocusModeKey);
      await prefs.remove(focusStartTimeKey);
      await prefs.remove(focusElapsedKey);
      await prefs.remove(lastUserEmailKey);
      await prefs.remove(overlayPermissionKey);
      
      try {
        await Workmanager().cancelAll();
        debugPrint('✅ All background tasks cancelled');
      } catch (e) {
        debugPrint('⚠️ Error cancelling background tasks: $e');
      }
      
      final instance = TimerService();
      instance._resetInstance();
      
      debugPrint('✅ TimerService: ALL timer data cleared successfully');
    } catch (e) {
      debugPrint('❌ TimerService: Error clearing timer data: $e');
    }
  }

  // Reset instance values
  void _resetInstance() {
    _stopActiveTimer();
    _focusTimeToday.value = Duration.zero;
    _isFocusMode.value = false;
    _timerStartTime = null;
    _isInitialized = false;
    _hasOverlayPermission = false;
  }

  // Get formatted time string
  String getFormattedFocusTime() {
    return _formatDuration(_focusTimeToday.value);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // Cleanup
  void dispose() {
    if (_isInitialized) {
      debugPrint('🗑️ TimerService: Disposing...');
      _stopActiveTimer();
      _isFocusMode.dispose();
      _focusTimeToday.dispose();
      _isInitialized = false;
      debugPrint('✅ TimerService: Disposed successfully');
    }
  }
}