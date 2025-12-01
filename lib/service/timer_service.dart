import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  // Make keys public static so they can be accessed in callbackDispatcher
  static const String focusKey = 'focus_time_today';
  static const String breakKey = 'break_time_today';
  static const String lastDateKey = 'last_timer_date';
  static const String isFocusModeKey = 'is_focus_mode';
  static const String focusStartTimeKey = 'focus_start_time';
  static const String breakStartTimeKey = 'break_start_time';
  static const String focusElapsedKey = 'focus_elapsed_before_pause';
  static const String breakElapsedKey = 'break_elapsed_before_pause';

  final ValueNotifier<bool> _isFocusMode = ValueNotifier<bool>(false);
  ValueNotifier<bool> get isFocusMode => _isFocusMode;

  final ValueNotifier<Duration> _focusTimeToday = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get focusTimeToday => _focusTimeToday;

  final ValueNotifier<Duration> _breakTimeToday = ValueNotifier<Duration>(Duration.zero);
  ValueNotifier<Duration> get breakTimeToday => _breakTimeToday;

  Timer? _activeTimer;
  DateTime? _lastTickTime;
  bool _isInitialized = false;

  // Initialize background service
  static Future<void> initializeBackgroundService() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    
    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await FlutterLocalNotificationsPlugin().initialize(initializationSettings);
  }

  // Callback for background work
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      debugPrint("Background task running: $task");
      
      final prefs = await SharedPreferences.getInstance();
      final lastDate = prefs.getString(lastDateKey);
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      // Reset timers if it's a new day
      if (lastDate != today) {
        await prefs.setString(lastDateKey, today);
        await prefs.setInt(focusKey, 0);
        await prefs.setInt(breakKey, 0);
      }
      
      // Update timers if active
      if (prefs.getBool(isFocusModeKey) ?? false) {
        await _updateFocusTimeInBackgroundStatic(prefs);
      } else {
        await _updateBreakTimeInBackgroundStatic(prefs);
      }
      
      return Future.value(true);
    });
  }

  // Static methods for background updates (can't access instance in background)
  static Future<void> _updateFocusTimeInBackgroundStatic(SharedPreferences prefs) async {
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

  static Future<void> _updateBreakTimeInBackgroundStatic(SharedPreferences prefs) async {
    final startTimeStr = prefs.getString(breakStartTimeKey);
    
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      final elapsedBeforePause = Duration(seconds: prefs.getInt(breakElapsedKey) ?? 0);
      final now = DateTime.now();
      final elapsed = now.difference(startTime) + elapsedBeforePause;
      
      final currentTotal = Duration(seconds: prefs.getInt(breakKey) ?? 0);
      final newTotal = currentTotal + elapsed;
      
      await prefs.setInt(breakKey, newTotal.inSeconds);
    }
  }

  // Initialize timer service
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint("TimerService already initialized, skipping...");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    
    // Check if it's a new day
    final lastDate = prefs.getString(lastDateKey);
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    if (lastDate != today) {
      await _resetDailyTimers();
    } else {
      // Load existing timers
      _focusTimeToday.value = Duration(seconds: prefs.getInt(focusKey) ?? 0);
      _breakTimeToday.value = Duration(seconds: prefs.getInt(breakKey) ?? 0);
    }
    
    // Check if focus mode was active
    final isFocusActive = prefs.getBool(isFocusModeKey) ?? false;
    if (isFocusActive) {
      final startTimeStr = prefs.getString(focusStartTimeKey);
      if (startTimeStr != null) {
        final startTime = DateTime.parse(startTimeStr);
        final elapsedBeforePause = Duration(seconds: prefs.getInt(focusElapsedKey) ?? 0);
        final now = DateTime.now();
        final elapsed = now.difference(startTime) + elapsedBeforePause;
        _focusTimeToday.value += elapsed;
        _isFocusMode.value = true;
        _startFocusTimer();
      }
    } else {
      // Check if break was active
      final startTimeStr = prefs.getString(breakStartTimeKey);
      if (startTimeStr != null) {
        final startTime = DateTime.parse(startTimeStr);
        final elapsedBeforePause = Duration(seconds: prefs.getInt(breakElapsedKey) ?? 0);
        final now = DateTime.now();
        final elapsed = now.difference(startTime) + elapsedBeforePause;
        _breakTimeToday.value += elapsed;
        _isFocusMode.value = false;
        _startBreakTimer();
      }
    }
    
    // Start periodic background updates
    await Workmanager().registerPeriodicTask(
      "timer_update",
      "timer_update_task",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    _isInitialized = true;
    debugPrint("TimerService initialized successfully");
  }

  // Start focus mode
  Future<void> startFocusMode() async {
    _isFocusMode.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(isFocusModeKey, true);
    await prefs.setString(focusStartTimeKey, DateTime.now().toIso8601String());
    await prefs.remove(focusElapsedKey); // Clear any previous pause
    
    _startFocusTimer();
  }

  // Pause focus mode (start break)
  Future<void> pauseFocusMode() async {
    _isFocusMode.value = false;
    final prefs = await SharedPreferences.getInstance();
    
    // Save current focus elapsed
    final currentFocus = _focusTimeToday.value;
    await prefs.setInt(focusKey, currentFocus.inSeconds);
    await prefs.setInt(focusElapsedKey, currentFocus.inSeconds);
    await prefs.setBool(isFocusModeKey, false);
    await prefs.remove(focusStartTimeKey);
    
    // Start break timer
    await prefs.setString(breakStartTimeKey, DateTime.now().toIso8601String());
    await prefs.remove(breakElapsedKey);
    
    _stopActiveTimer();
    _startBreakTimer();
  }

  // Resume focus mode (from break)
  Future<void> resumeFocusMode() async {
    _isFocusMode.value = true;
    final prefs = await SharedPreferences.getInstance();
    
    // Save current break elapsed
    final currentBreak = _breakTimeToday.value;
    await prefs.setInt(breakKey, currentBreak.inSeconds);
    await prefs.setInt(breakElapsedKey, currentBreak.inSeconds);
    await prefs.setBool(isFocusModeKey, true);
    await prefs.remove(breakStartTimeKey);
    
    // Start focus timer
    await prefs.setString(focusStartTimeKey, DateTime.now().toIso8601String());
    await prefs.remove(focusElapsedKey);
    
    _stopActiveTimer();
    _startFocusTimer();
  }

  // Stop all timers (when user manually stops focus mode)
  Future<void> stopAllTimers() async {
    _stopActiveTimer();
    _isFocusMode.value = false;
    
    final prefs = await SharedPreferences.getInstance();
    
    // Save final times
    await prefs.setInt(focusKey, _focusTimeToday.value.inSeconds);
    await prefs.setInt(breakKey, _breakTimeToday.value.inSeconds);
    
    // Clear active session data
    await prefs.setBool(isFocusModeKey, false);
    await prefs.remove(focusStartTimeKey);
    await prefs.remove(breakStartTimeKey);
    await prefs.remove(focusElapsedKey);
    await prefs.remove(breakElapsedKey);
  }

  // Private timer methods
  void _startFocusTimer() {
    _stopActiveTimer();
    _lastTickTime = DateTime.now();
    
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final diff = now.difference(_lastTickTime!);
      _focusTimeToday.value += diff;
      _lastTickTime = now;
      
      // Save to shared preferences every 30 seconds
      if (_focusTimeToday.value.inSeconds % 30 == 0) {
        _saveFocusTime();
      }
    });
  }

  void _startBreakTimer() {
    _stopActiveTimer();
    _lastTickTime = DateTime.now();
    
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final diff = now.difference(_lastTickTime!);
      _breakTimeToday.value += diff;
      _lastTickTime = now;
      
      // Save to shared preferences every 30 seconds
      if (_breakTimeToday.value.inSeconds % 30 == 0) {
        _saveBreakTime();
      }
    });
  }

  void _stopActiveTimer() {
    _activeTimer?.cancel();
    _activeTimer = null;
    _lastTickTime = null;
  }

  Future<void> _saveFocusTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(focusKey, _focusTimeToday.value.inSeconds);
  }

  Future<void> _saveBreakTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(breakKey, _breakTimeToday.value.inSeconds);
  }

  Future<void> _resetDailyTimers() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    await prefs.setString(lastDateKey, today);
    await prefs.setInt(focusKey, 0);
    await prefs.setInt(breakKey, 0);
    
    _focusTimeToday.value = Duration.zero;
    _breakTimeToday.value = Duration.zero;
  }

  Future<void> _updateFocusTimeInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await _updateFocusTimeInBackgroundStatic(prefs);
  }

  Future<void> _updateBreakTimeInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await _updateBreakTimeInBackgroundStatic(prefs);
  }

  // Get formatted time strings
  String getFormattedFocusTime() {
    return _formatDuration(_focusTimeToday.value);
  }

  String getFormattedBreakTime() {
    return _formatDuration(_breakTimeToday.value);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // Add method to manually reset timers (for testing)
  Future<void> resetTimersForNewDay() async {
    await _resetDailyTimers();
  }

  // Add method to get today's date key
  static String getTodayDateKey() {
    return DateTime.now().toIso8601String().split('T')[0];
  }

  // REMOVED dispose() method - Singleton services should NEVER be disposed
  // The ValueNotifiers will live for the entire app lifetime
  // If you need to clean up, call stopAllTimers() instead
}