import 'package:coaching_institute_app/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'service/api_config.dart';
import 'service/auth_service.dart';
import 'service/notification_service.dart';
import 'service/timer_service.dart'; // 🆕 Added timer service
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/getin_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/account_creation_screen.dart';
import 'screens/profile_completion_page.dart';
import 'screens/study_materials/notes/notes.dart';
import 'screens/study_materials/previous_question_papers/question_papers.dart';
import 'screens/study_materials/reference_classes/reference_classes.dart';
import 'screens/forgot_password.dart';
import 'screens/forgot_otp_verification.dart';
import 'screens/reset_password.dart';
import 'screens/mock_test/mock_test.dart';
import './screens/performance.dart';
import 'screens/Academics/exam_schedule/exam_schedule.dart';
import './screens/subscription/subscription.dart';
import './screens/Academics/academics.dart';
import './screens/settings/about_us.dart';
import 'hive_model.dart';
import './screens/video_stream/videos.dart';
import './screens/focus_mode/focus_mode_entry.dart'; // 🆕 Added focus mode entry screen
import './screens/focus_mode/break_mode.dart'; // 🆕 Added break mode screen

// 🔹 Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔹 Global Scaffold Messenger Key for SnackBar
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// 🔹 Local notification instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ✅ Handle notification taps (navigating to target page)
void handleNotificationTap(Map<String, dynamic> data) {
  try {
    debugPrint('🔔 Notification tapped with data: $data');
    final type = data['type']?.toString().toLowerCase();
    final id = data['assignment_id'] ?? data['exam_id'] ?? '';

    if (type == 'assignment') {
      navigatorKey.currentState?.pushNamed('/academics', arguments: id);
    } else if (type == 'exam') {
      navigatorKey.currentState?.pushNamed('/exam_schedule', arguments: id);
    } else if (type == 'subscription') {
      navigatorKey.currentState?.pushNamed('/subscription');
    } else if (type == 'video_class') {
      navigatorKey.currentState?.pushNamed('/videos');
    } else {
      navigatorKey.currentState?.pushNamed('/home');
    }
  } catch (e) {
    debugPrint('⚠️ Error during notification tap handling: $e');
  }
}

// 🔹 Background message handler (required)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📩 Background FCM Data: ${message.data}');

  final type = message.data['type']?.toString().toLowerCase();
  if (type == 'assignment') {
    debugPrint('🆕 Background assignment notification detected');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_unread_assignments', true);
      debugPrint('💾 Badge state saved to SharedPreferences from background');
    } catch (e) {
      debugPrint('❌ Error saving badge state from background: $e');
    }
  }

  final data = message.data;
  final title = data['title'] ?? 'New Notification';
  final body = data['body'] ?? 'You have a new notification';

  const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'default_channel',
    'General Notifications',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
    payload: jsonEncode(data),
  );
}

// 🔹 Timer background task handler
@pragma('vm:entry-point')
void timerCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🕰️ Timer background task running: $task");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastDate = prefs.getString('last_timer_date');
      
      // Check if it's a new day
      if (lastDate != today) {
        await prefs.setString('last_timer_date', today);
        await prefs.setInt('focus_time_today', 0);
        await prefs.setInt('break_time_today', 0);
        debugPrint('🔄 Timer reset for new day: $today');
      }
      
      // Update timers if active
      final isFocusMode = prefs.getBool('is_focus_mode') ?? false;
      final isBreakActive = prefs.getString('break_start_time') != null;
      final isFocusActive = prefs.getString('focus_start_time') != null;
      
      if (isFocusMode && isFocusActive) {
        await _updateTimerInBackground(
          'focus_start_time',
          'focus_elapsed_before_pause',
          'focus_time_today',
          prefs,
        );
      } else if (!isFocusMode && isBreakActive) {
        await _updateTimerInBackground(
          'break_start_time',
          'break_elapsed_before_pause',
          'break_time_today',
          prefs,
        );
      }
      
      debugPrint('✅ Timer background update completed');
    } catch (e) {
      debugPrint('❌ Error in timer background task: $e');
    }
    
    return Future.value(true);
  });
}

// Helper function to update timer in background
Future<void> _updateTimerInBackground(
  String startTimeKey,
  String elapsedKey,
  String totalKey,
  SharedPreferences prefs,
) async {
  final startTimeStr = prefs.getString(startTimeKey);
  
  if (startTimeStr != null) {
    final startTime = DateTime.parse(startTimeStr);
    final elapsedBeforePause = Duration(seconds: prefs.getInt(elapsedKey) ?? 0);
    final now = DateTime.now();
    final elapsed = now.difference(startTime) + elapsedBeforePause;
    
    final currentTotal = Duration(seconds: prefs.getInt(totalKey) ?? 0);
    final newTotal = currentTotal + elapsed;
    
    await prefs.setInt(totalKey, newTotal.inSeconds);
    
    debugPrint('📈 Updated $totalKey: ${newTotal.inSeconds} seconds');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // ✅ Initialize background timer service FIRST
  await Workmanager().initialize(
    timerCallbackDispatcher,
    isInDebugMode: true,
  );
  
  // Register periodic timer task
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
  );
  
  debugPrint('✅ Timer background service initialized');

  // ✅ Request location permission before anything else
  await _requestLocationPermission();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Hive
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(PdfReadingRecordAdapter());
  }
  try {
    await Hive.openBox<PdfReadingRecord>('pdf_records_box');
    debugPrint('✅ Hive initialized successfully');
  } catch (e) {
    debugPrint('❌ Error opening Hive box: $e');
  }

  // Initialize Local Notifications
  const AndroidInitializationSettings androidInitSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInitSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        final data = jsonDecode(response.payload!);
        handleNotificationTap(Map<String, dynamic>.from(data));
      }
    },
  );

  // Initialize API Config before running app
  await ApiConfig.initializeBaseUrl(printLogs: true);

  // Print currently active API in debug console
  debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  debugPrint("🌐  ACTIVE API BASE URL → ${ApiConfig.currentBaseUrl}");
  debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  runApp(const CoachingInstituteApp());
}

// ✅ Request location permission at app startup
Future<void> _requestLocationPermission() async {
  try {
    // Check if location services are enabled on device using Geolocator
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('📍 Location services enabled on device: $serviceEnabled');

    if (!serviceEnabled) {
      debugPrint('⚠️ Location services are disabled on device');
      // We'll handle this in ApiConfig when detecting Coremicron WiFi
    }

    // Check permission status
    final status = await Permission.locationWhenInUse.status;
    debugPrint('📍 Initial location permission status: $status');

    if (!status.isGranted) {
      final result = await Permission.locationWhenInUse.request();
      debugPrint('📍 Location permission request result: $result');
      
      if (result.isDenied || result.isPermanentlyDenied) {
        debugPrint('⚠️ Location permission denied by user');
      } else if (result.isGranted) {
        debugPrint('✅ Location permission granted');
        
        // Check again if location services are enabled after permission granted
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint('⚠️ Permission granted but location services still disabled');
        }
      }
    } else {
      debugPrint('✅ Location permission already granted');
    }
  } catch (e) {
    debugPrint('❌ Error requesting location permission: $e');
  }
}

class CoachingInstituteApp extends StatefulWidget {
  const CoachingInstituteApp({super.key});

  @override
  State<CoachingInstituteApp> createState() => _CoachingInstituteAppState();
}

class _CoachingInstituteAppState extends State<CoachingInstituteApp>
    with WidgetsBindingObserver {
  Timer? _locationCheckTimer;
  StreamSubscription? _locationServiceSubscription;
  final TimerService _timerService = TimerService(); // 🆕 Timer service instance

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationService();
    
    // 🆕 Initialize timer service
    _timerService.initialize();
    
    // Check if user should be redirected to focus mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRedirectToFocusMode();
    });

    // ✅ Setup API Config callbacks for UI notifications
    _setupApiConfigCallbacks();

    // Listen to API URL changes when network changes
    ApiConfig.startAutoListen(updateImmediately: false);

    // ✅ Start listening to location service status changes
    _startLocationServiceListener();

    // ✅ Start periodic location check when on Coremicron Wi-Fi
    _startPeriodicLocationCheck();

    // Print debug message whenever network switches
    debugPrint('🔎 Listening for network changes...');
  }
  
  // 🆕 Check if user should be redirected to focus mode
  Future<void> _checkAndRedirectToFocusMode() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Small delay for SharedPreferences
    
    final prefs = await SharedPreferences.getInstance();
    final studentType = prefs.getString('profile_student_type')?.toUpperCase() ?? '';
    
    // Only redirect Online/Offline students who are not in focus mode
    if (studentType == 'ONLINE' || studentType == 'OFFLINE') {
      final isFocusActive = prefs.getBool('is_focus_mode') ?? false;
      
      if (!isFocusActive && mounted) {
        // Check if we're already on focus mode or home screen
        final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
        if (currentRoute == null || 
            (currentRoute.settings.name != '/focus_mode' && 
             currentRoute.settings.name != '/home')) {
          
          navigatorKey.currentState?.pushReplacementNamed('/focus_mode');
        }
      }
    }
  }

  // ✅ Real-time listener for location service status changes
  void _startLocationServiceListener() {
    _locationServiceSubscription = Geolocator.getServiceStatusStream().listen(
      (status) async {
        debugPrint('📍 Location service status changed: $status');
        
        // Check current location service status
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        
        if (!serviceEnabled) {
          debugPrint('⚠️ Location services DISABLED');
          
          // Re-check Wi-Fi and switch API
          await ApiConfig.initializeBaseUrl(printLogs: true);
          
          // Show dialog only if still on Coremicron Wi-Fi
          if (ApiConfig.isOnCoremicronWifi) {
            _showLocationRequiredDialog();
          }
        } else {
          debugPrint('✅ Location services ENABLED');
          
          // Re-check Wi-Fi and switch API
          await ApiConfig.initializeBaseUrl(printLogs: true);
          
          // If now on Coremicron with location enabled, it will auto-switch to local
          debugPrint('🔄 API reinitialized after location enabled');
        }
      },
      onError: (error) {
        debugPrint('❌ Error listening to location service: $error');
      },
    );
  }

  // ✅ Periodically check if location is still enabled when on Coremicron Wi-Fi
  void _startPeriodicLocationCheck() {
    _locationCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Always check and reinitialize API based on current Wi-Fi and location status
      final status = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      debugPrint('📍 Periodic check - Permission: $status, Services: $serviceEnabled, On Coremicron: ${ApiConfig.isOnCoremicronWifi}');
      
      if (ApiConfig.isOnCoremicronWifi) {
        // On Coremicron Wi-Fi
        if (!status.isGranted || !serviceEnabled) {
          debugPrint('⚠️ Location disabled while on Coremicron Wi-Fi - switching to external API');
          // Re-check Wi-Fi and switch API
          await ApiConfig.initializeBaseUrl(printLogs: true);
        }
      }
    });
  }

  // ✅ Setup callbacks for API switching, location requirement, and error snackbars
  void _setupApiConfigCallbacks() {
    // API switch notification
    ApiConfig.onApiSwitch = (String message, String apiUrl) {
      debugPrint('🔄 $message → $apiUrl');
      _showApiSwitchSnackBar(message);
    };

    // Location required dialog
    ApiConfig.onLocationRequired = () {
      debugPrint('📍 Location permission required for local Wi-Fi');
      _showLocationRequiredDialog();
    };

    // ✅ NEW: Error snackbar handler
    ApiConfig.onShowSnackbar = (String message, {bool isError = false}) {
      debugPrint('📢 Showing snackbar: $message');
      _showErrorSnackBar(message, isError: isError);
    };
  }

  // ✅ Show SnackBar for API switching
  void _showApiSwitchSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.indigo,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  // ✅ NEW: Show error SnackBar with location prompt
  void _showErrorSnackBar(String message, {bool isError = false}) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade700 : Colors.orange.shade700,
        action: message.contains('Location')
            ? SnackBarAction(
                label: 'OPEN SETTINGS',
                textColor: Colors.white,
                onPressed: () async {
                  await openAppSettings();
                },
              )
            : SnackBarAction(
                label: 'DISMISS',
                textColor: Colors.white,
                onPressed: () {},
              ),
      ),
    );
  }

  // ✅ Show dialog for location permission requirement
  void _showLocationRequiredDialog() {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    // Check if dialog is already showing
    if (ModalRoute.of(context)?.isCurrent != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button dismiss
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.location_off, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Location Services Required',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: const Text(
              'You are connected to Coremicron Wi-Fi. To use the local API, '
              'please turn on Location Services in your device settings.\n\n'
              'Steps:\n'
              '1. Go to Settings\n'
              '2. Enable Location/GPS\n'
              '3. Grant location permission to this app\n\n'
              'Without location enabled, the app will use the external API.',
              style: TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'Use External API',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  // Open location settings
                  final opened = await openAppSettings();
                  if (opened) {
                    debugPrint('✅ Opened device settings for location');
                  }
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationCheckTimer?.cancel();
    _locationServiceSubscription?.cancel();
    TimerService().stopAllTimers();
    ApiConfig.stopAutoListen();
    ApiConfig.onApiSwitch = null;
    ApiConfig.onLocationRequired = null;
    ApiConfig.onShowSnackbar = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle changed: $state');
    
    if (state == AppLifecycleState.resumed) {
      // Always re-check Wi-Fi and location on resume
      final status = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      debugPrint('📍 On resume - Permission: $status, Services: $serviceEnabled');
      
      // Reinitialize API (will check Wi-Fi name and location)
      await ApiConfig.initializeBaseUrl(printLogs: true);
      
      debugPrint('🔄 API reinitialized on resume - Current URL: ${ApiConfig.currentBaseUrl}');
      
      await NotificationService.checkBadgeStateOnResume();
      debugPrint('🔄 Badge state reloaded on app resume');
      
      // 🆕 Check if user should see focus mode on resume
      _checkAndRedirectToFocusMode();
      
      // 🆕 Resume timer if active
      _checkAndResumeTimer();
    }

    final bool isOnlineStudent = await _isOnlineStudent();
    if (!isOnlineStudent) return;

    if (state == AppLifecycleState.paused) {
      await _storeEndTimeAndLastActive();
    }

    if (state == AppLifecycleState.resumed) {
      _checkLastActiveTimeOnResume();
    }
  }
  
  // 🆕 Check and resume timer if it was active
  Future<void> _checkAndResumeTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isFocusActive = prefs.getBool('is_focus_mode') ?? false;
    
    if (isFocusActive) {
      final startTimeStr = prefs.getString('focus_start_time');
      if (startTimeStr != null) {
        final startTime = DateTime.parse(startTimeStr);
        final elapsedBeforePause = Duration(seconds: prefs.getInt('focus_elapsed_before_pause') ?? 0);
        final now = DateTime.now();
        final elapsed = now.difference(startTime) + elapsedBeforePause;
        
        // Update the timer service
        _timerService.focusTimeToday.value += elapsed;
        
        // Restart the timer
        _timerService.startFocusMode();
      }
    } else {
      final startTimeStr = prefs.getString('break_start_time');
      if (startTimeStr != null) {
        final startTime = DateTime.parse(startTimeStr);
        final elapsedBeforePause = Duration(seconds: prefs.getInt('break_elapsed_before_pause') ?? 0);
        final now = DateTime.now();
        final elapsed = now.difference(startTime) + elapsedBeforePause;
        
        // Update the timer service
        _timerService.breakTimeToday.value += elapsed;
        
        // Restart the break timer
        _timerService.pauseFocusMode();
      }
    }
  }

  Future<void> _initNotificationService() async {
    await NotificationService.init(navigatorKey);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('📩 Foreground message: ${message.data}');
      final data = message.data;

      await flutterLocalNotificationsPlugin.show(
        0,
        data['title'] ?? message.notification?.title ?? 'New Notification',
        data['body'] ?? message.notification?.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(data),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🚀 App opened via notification tap (background)');
      handleNotificationTap(message.data);
    });

    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🧊 App launched via notification (terminated)');
      handleNotificationTap(initialMessage.data);
    }
  }

  Future<bool> _isOnlineStudent() async {
    final prefs = await SharedPreferences.getInstance();
    final studentType = prefs.getString('profile_student_type') ??
        prefs.getString('student_type') ??
        '';
    return studentType.toUpperCase() == 'ONLINE';
  }

  Future<void> _storeEndTimeAndLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('end_time') == null) {
      String nowStr = DateTime.now().toIso8601String();
      await prefs.setString('end_time', nowStr);
      await prefs.setString('last_active_time', nowStr);
    }
  }

  Future<void> _checkLastActiveTimeOnResume() async {
    final prefs = await SharedPreferences.getInstance();
    String? endTimeStr = prefs.getString('end_time');
    if (endTimeStr != null) _showContinueDialog();
  }

  // ✅ Fixed method - no more BuildContext warnings
  void _showContinueDialog() {
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) return;

    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Continue'),
          content: const Text('Continue using the app'),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final okClickTime = DateTime.now();
                final endTimeStr = prefs.getString('end_time');

                // ✅ Do all async work first
                bool shouldLogout = false;

                if (endTimeStr != null) {
                  final endTime = DateTime.parse(endTimeStr);
                  final elapsed = okClickTime.difference(endTime);

                  if (elapsed.inSeconds <= 120) {
                    await prefs.remove('end_time');
                    await prefs.remove('last_active_time');
                  } else {
                    shouldLogout = true;
                  }
                }

                // Then use context after checking if mounted
                if (!context.mounted) return;

                Navigator.of(context).pop();

                if (shouldLogout) {
                  await _logoutUser();
                }
              },
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  // Fixed method with safety check
  Future<void> _logoutUser() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isOnlineStudent = await _isOnlineStudent();

    if (isOnlineStudent) {
      String? start = prefs.getString('start_time');
      String? end = prefs.getString('end_time');

      if (start != null && end != null) {
        final authService = AuthService();
        final accessToken = await authService.getAccessToken();
        String cleanStart = start.split('.')[0].replaceFirst('T', ' ');
        String cleanEnd = end.split('.')[0].replaceFirst('T', ' ');

        final body = {
          "records": [
            {"time_stamp": cleanStart, "is_checkin": 1},
            {"time_stamp": cleanEnd, "is_checkin": 0}
          ]
        };

        try {
          final response = await http.post(
            Uri.parse(
                ApiConfig.buildUrl('/api/performance/add_onlineattendance/')),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          );

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('✅ Attendance sent successfully');
          }
        } catch (e) {
          debugPrint('❌ Exception while sending attendance: $e');
        }

        await prefs.remove('start_time');
        await prefs.remove('end_time');
        await prefs.remove('last_active_time');
      }
    }

    // 🆕 Also clear focus mode data on logout
    await prefs.remove('is_focus_mode');
    await prefs.remove('focus_start_time');
    await prefs.remove('break_start_time');
    await prefs.remove('focus_elapsed_before_pause');
    await prefs.remove('break_elapsed_before_pause');
    await prefs.remove('focus_time_today');
    await prefs.remove('break_time_today');
    await prefs.remove('last_timer_date');

    // Safe navigation using global key with mounted check
    if (navigatorKey.currentState?.mounted ?? false) {
      navigatorKey.currentState?.pushReplacementNamed('/getin');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Coaching Institute App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/signup': (context) => const LoginScreen(),
        '/getin': (context) => const GetInScreen(),
        '/otp_verification': (context) => const OtpVerificationScreen(),
        '/account_creation': (context) => const AccountCreationScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile_completion_page': (context) =>
            const ProfileCompletionPage(),
        '/notes': (context) => const NotesScreen(),
        '/question_papers': (context) => const QuestionPapersScreen(),
        '/video_classes': (context) => const ReferenceClassesScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/forgot_otp_verification': (context) =>
            const ForgotOtpVerificationScreen(),
        '/reset_password': (context) => const ResetPasswordScreen(),
        '/mock_test': (context) => const MockTestScreen(),
        '/performance': (context) => const PerformanceScreen(),
        '/exam_schedule': (context) => const ExamScheduleScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/academics': (context) => const AcademicsScreen(),
        '/about_us': (context) => const AboutUsScreen(),
        '/videos': (context) => const VideosScreen(),
        '/focus_mode': (context) => const FocusModeEntryScreen(), // 🆕 Added focus mode route
        '/break_mode': (context) => const BreakModeScreen(), // 🆕 Added break mode route
      },
    );
  }
}