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
import 'service/api_config.dart';
import 'service/auth_service.dart';
import 'service/notification_service.dart';
import 'service/timer_service.dart';
import 'service/websocket_manager.dart'; // WebSocket manager
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
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
import './screens/focus_mode/focus_mode_entry.dart';
import './screens/focus_mode/focus_overlay_manager.dart';
import 'service/focus_mode_overlay_service.dart'; // 🆕 Import overlay service

// 🔹 Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔹 Global Scaffold Messenger Key for SnackBar
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// 🔹 Local notification instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 🆕 Global overlay service instance
final FocusModeOverlayService overlayService = FocusModeOverlayService();

// ✅ Handle notification taps (navigating to target page)
void handleNotificationTap(Map<String, dynamic> data) {
  try {
    debugPrint('🔔 Notification tapped with data: $data');
    final type = data['type']?.toString().toLowerCase() ?? '';
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
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🕰️ Timer background task running: $task");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastDate = prefs.getString(TimerService.lastDateKey);
      
      // Check if it's a new day
      if (lastDate != today) {
        await prefs.setString(TimerService.lastDateKey, today);
        await prefs.setInt(TimerService.focusKey, 0);
        await prefs.setBool(TimerService.isFocusModeKey, false);
        await prefs.remove(TimerService.focusStartTimeKey);
        await prefs.remove(TimerService.focusElapsedKey);
        debugPrint('🔄 Timer reset for new day: $today');
      }
      
      // 🆕 Check if app is completely closed
      final lastAppState = prefs.getString(TimerService.appStateKey);
      if (lastAppState == 'detached' || lastAppState == null) {
        // App was completely closed, stop any running timers
        final isFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
        if (isFocusActive) {
          // Calculate final elapsed time before app closure
          final startTimeStr = prefs.getString(TimerService.focusStartTimeKey);
          final elapsedBeforePause = Duration(seconds: prefs.getInt(TimerService.focusElapsedKey) ?? 0);
          
          if (startTimeStr != null) {
            final startTime = DateTime.parse(startTimeStr);
            final elapsed = DateTime.now().difference(startTime) + elapsedBeforePause;
            final currentTotal = Duration(seconds: prefs.getInt(TimerService.focusKey) ?? 0);
            final newTotal = currentTotal + elapsed;
            
            await prefs.setInt(TimerService.focusKey, newTotal.inSeconds);
            debugPrint('🛑 App was closed - Stopped focus timer: ${newTotal.inSeconds}s');
          }
          
          await prefs.setBool(TimerService.isFocusModeKey, false);
          await prefs.remove(TimerService.focusStartTimeKey);
          await prefs.remove(TimerService.focusElapsedKey);
        }
        return Future.value(true);
      }
      
      // Update focus timer if active AND app is in foreground state
      final isFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
      final currentAppState = prefs.getString(TimerService.appStateKey);
      
      if (isFocusActive && currentAppState == 'resumed') {
        // Only update if app is in foreground/resumed state
        final startTimeStr = prefs.getString(TimerService.focusStartTimeKey);
        
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          final elapsedBeforePause = Duration(seconds: prefs.getInt(TimerService.focusElapsedKey) ?? 0);
          final now = DateTime.now();
          final elapsed = now.difference(startTime) + elapsedBeforePause;
          
          final currentTotal = Duration(seconds: prefs.getInt(TimerService.focusKey) ?? 0);
          final newTotal = currentTotal + elapsed;
          
          await prefs.setInt(TimerService.focusKey, newTotal.inSeconds);
          debugPrint('📈 Updated focus time in background: ${newTotal.inSeconds} seconds');
        }
      }
      
      debugPrint('✅ Timer background update completed');
      debugPrint('📱 Current app state in background: $currentAppState');
    } catch (e) {
      debugPrint('❌ Error in timer background task: $e');
    }
    
    return Future.value(true);
  });
}

// 🆕 Handle app permission updates from WebSocket (UPDATED)
Future<void> _handleAppPermissionUpdate(Map<String, dynamic> payload) async {
  try {
    final appPackage = payload['app']?.toString();
    final allowedValue = payload['allowed'];
    
    // 🆕 FIX: Proper boolean handling
    bool isAllowed;
    if (allowedValue is bool) {
      isAllowed = allowedValue;
    } else if (allowedValue is String) {
      isAllowed = allowedValue.toLowerCase() == 'true';
    } else if (allowedValue is int) {
      isAllowed = allowedValue == 1;
    } else {
      isAllowed = false;
      debugPrint('⚠️ Unknown allowed value type: ${allowedValue.runtimeType}, value: $allowedValue');
    }
    
    if (appPackage == null || appPackage.isEmpty) {
      debugPrint('❌ Invalid app package: $appPackage');
      return;
    }
    
    debugPrint('🎯 [MAIN.DART] App permission update received: $appPackage -> allowed: $isAllowed (raw: $allowedValue)');
    debugPrint('📍 From main.dart at: ${DateTime.now().toIso8601String()}');
    
    // 🔥 CRITICAL: Update overlay immediately from ANYWHERE using the singleton
    await overlayService.handleAppPermissionUpdate(appPackage, isAllowed);
    
    // 🔥 ALSO: Update the app permission state globally for UI
    await _updateAppPermissionGlobally(appPackage, isAllowed);
    
    // 🔥 Show notification to user
    _showAppPermissionNotification(appPackage, isAllowed);
    
  } catch (e) {
    debugPrint('❌ [MAIN.DART] Error handling app permission update: $e');
    debugPrint('❌ Stack trace: ${e.toString()}');
  }
}
// 🆕 Update app permission globally
Future<void> _updateAppPermissionGlobally(String packageName, bool isAllowed) async {
  try {
    debugPrint('📢 Notifying global app permission change: $packageName -> $isAllowed');
    
    final prefs = await SharedPreferences.getInstance();
    
    // Get current allowed apps
    final savedAllowedApps = prefs.getStringList('allowed_apps_list') ?? [];
    
    if (isAllowed) {
      // Add to allowed apps if not already present
      if (!savedAllowedApps.contains(packageName)) {
        savedAllowedApps.add(packageName);
        await prefs.setStringList('allowed_apps_list', savedAllowedApps);
        debugPrint('✅ Added $packageName to global allowed apps list');
      }
    } else {
      // Remove from allowed apps
      if (savedAllowedApps.contains(packageName)) {
        savedAllowedApps.remove(packageName);
        await prefs.setStringList('allowed_apps_list', savedAllowedApps);
        debugPrint('❌ Removed $packageName from global allowed apps list');
      }
    }
    
    // You can use this to update UI state if needed
    // Example with Provider:
    // if (navigatorKey.currentContext != null) {
    //   final provider = navigatorKey.currentContext!.read<AppPermissionsProvider>();
    //   if (provider != null) {
    //     provider.updateAppPermission(packageName, isAllowed);
    //   }
    // }
    
  } catch (e) {
    debugPrint('❌ Error updating app permission globally: $e');
  }
}

// 🆕 Show app permission notification
void _showAppPermissionNotification(String packageName, bool isAllowed) {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  
  String appName = packageName;
  // Try to get app name from package
  if (packageName == 'com.whatsapp') appName = 'WhatsApp';
  else if (packageName == 'com.instagram.android') appName = 'Instagram';
  else if (packageName == 'com.facebook.katana') appName = 'Facebook';
  else if (packageName == 'com.google.android.youtube') appName = 'YouTube';
  
  final message = isAllowed 
    ? '$appName has been added to your allowed apps'
    : '$appName has been removed from your allowed apps';
  
  final color = isAllowed ? Colors.green : Colors.orange;
  final icon = isAllowed ? Icons.check_circle : Icons.block;
  
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
      duration: Duration(seconds: 4),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Navigate to allowed apps screen
          navigatorKey.currentState?.pushNamed('/allow_apps');
        },
      ),
    ),
  );
}

// 🆕 WebSocket message handler (UPDATED with FIX for boolean parsing)
void _handleWebSocketMessage(dynamic message) {
  try {
    debugPrint('📩 WebSocket message received in main.dart: $message');
    
    // Parse the message if it's JSON
    dynamic data;
    try {
      if (message is String) {
        data = jsonDecode(message);
      } else {
        data = message;
      }
    } catch (e) {
      // If not JSON, treat as string message
      data = {'message': message.toString()};
      debugPrint('⚠️ Message is not JSON, treating as string');
    }
    
    // Handle different message formats
    if (data is Map<String, dynamic>) {
      final type = data['type']?.toString().toLowerCase() ?? data['event']?.toString().toLowerCase();
      
      debugPrint('📊 WebSocket message type: $type');
      debugPrint('📦 Full message data: $data'); // 🆕 ADD THIS FOR DEBUGGING
      
      // Handle different types of WebSocket messages
      switch (type) {
        case 'app_permission':
        case 'app_permission_update':
          debugPrint('🎯 App permission update detected in main.dart');
          
          // 🆕 CRITICAL FIX: Properly extract data
          Map<String, dynamic> permissionData;
          
          if (data.containsKey('data') && data['data'] is Map<String, dynamic>) {
            permissionData = Map<String, dynamic>.from(data['data']);
            debugPrint('📋 Permission data from "data" field: $permissionData');
          } else {
            permissionData = Map<String, dynamic>.from(data);
            debugPrint('📋 Permission data from root: $permissionData');
          }
          
          final appPackage = permissionData['app']?.toString();
          
          // 🆕 CRITICAL FIX: Handle boolean correctly
          dynamic allowedValue = permissionData['allowed'];
          bool isAllowed;
          
          if (allowedValue is bool) {
            isAllowed = allowedValue;
          } else if (allowedValue is String) {
            isAllowed = allowedValue.toLowerCase() == 'true';
          } else if (allowedValue is int) {
            isAllowed = allowedValue == 1;
          } else {
            // Default to false if can't parse
            isAllowed = false;
            debugPrint('⚠️ Could not parse "allowed" value: $allowedValue, defaulting to false');
          }
          
          debugPrint('🎯 Parsed values - app: $appPackage, allowed: $isAllowed (raw: $allowedValue)');
          
          if (appPackage != null && appPackage.isNotEmpty) {
            // 🔥 CRITICAL: Handle app permission updates
            _handleAppPermissionUpdate({
              'app': appPackage,
              'allowed': isAllowed,
            });
          } else {
            debugPrint('❌ Missing or empty app package in permission update');
          }
          break;
          
        case 'attendance_update':
          final payload = data['data'] ?? data;
          _handleAttendanceUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'exam_update':
          final payload = data['data'] ?? data;
          _handleExamUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'assignment_update':
          final payload = data['data'] ?? data;
          _handleAssignmentUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'notification':
          final payload = data['data'] ?? data;
          _handleWebSocketNotification(Map<String, dynamic>.from(payload));
          break;
        case 'focus_mode':
          final payload = data['data'] ?? data;
          _handleFocusModeUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'system_message':
          final payload = data['data'] ?? data;
          _showSystemMessage(Map<String, dynamic>.from(payload));
          break;
        case 'heartbeat':
          // Handle heartbeat response if needed
          debugPrint('💓 Heartbeat response received');
          break;
        default:
          debugPrint('ℹ️ Unhandled WebSocket message type: $type');
      }
    } else {
      // Handle non-JSON messages
      debugPrint('📝 Raw WebSocket message: $data');
    }
  } catch (e) {
    debugPrint('❌ Error handling WebSocket message: $e');
    debugPrint('❌ Stack trace: ${e.toString()}');
  }
}

// 🆕 Handle attendance updates from WebSocket
void _handleAttendanceUpdate(Map<String, dynamic> payload) {
  final studentId = payload['student_id'];
  final status = payload['status'];
  final timestamp = payload['timestamp'];
  
  debugPrint('🎯 Attendance update - Student: $studentId, Status: $status, Time: $timestamp');
  
  // Show snackbar notification
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('Attendance updated: $status at ${timestamp.toString()}'),
      duration: const Duration(seconds: 3),
      backgroundColor: Colors.green,
    ),
  );
}

// 🆕 Handle exam updates from WebSocket
void _handleExamUpdate(Map<String, dynamic> payload) {
  final examId = payload['exam_id'];
  final title = payload['title'];
  final action = payload['action']; // created, updated, deleted
  
  debugPrint('📝 Exam update - ID: $examId, Title: $title, Action: $action');
  
  if (action == 'created' || action == 'updated') {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('New exam update: $title'),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.blue,
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            navigatorKey.currentState?.pushNamed('/exam_schedule', arguments: examId);
          },
        ),
      ),
    );
  }
}

// 🆕 Handle assignment updates from WebSocket
void _handleAssignmentUpdate(Map<String, dynamic> payload) {
  final assignmentId = payload['assignment_id'];
  final title = payload['title'];
  final deadline = payload['deadline'];
  final action = payload['action'];
  
  debugPrint('📚 Assignment update - ID: $assignmentId, Title: $title');
  
  // Update badge state for assignments
  if (action == 'created' || action == 'assigned') {
    _updateAssignmentBadge(true);
    
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('New assignment: $title (Due: $deadline)'),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            navigatorKey.currentState?.pushNamed('/academics', arguments: assignmentId);
          },
        ),
      ),
    );
  }
}

// 🆕 Handle WebSocket notifications
void _handleWebSocketNotification(Map<String, dynamic> payload) {
  final title = payload['title'] ?? 'Notification';
  final message = payload['message'] ?? '';
  final priority = payload['priority'] ?? 'normal';
  
  debugPrint('🔔 WebSocket notification: $title - $message');
  
  // Show local notification
  flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'websocket_channel',
        'WebSocket Notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: jsonEncode({'type': 'websocket_notification', 'data': payload}),
  );
  
  // Show snackbar for high priority messages
  if (priority == 'high') {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// 🆕 Handle focus mode updates
void _handleFocusModeUpdate(Map<String, dynamic> payload) {
  final action = payload['action'];
  final duration = payload['duration'];
  final studentId = payload['student_id'];
  
  debugPrint('🎯 Focus mode update - Action: $action, Duration: $duration');
  
  if (action == 'completed' || action == 'interrupted') {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Focus mode ${action == 'completed' ? 'completed' : 'interrupted'} after $duration minutes'),
        duration: const Duration(seconds: 3),
        backgroundColor: action == 'completed' ? Colors.green : Colors.amber,
      ),
    );
  }
}

// 🆕 Show system messages
void _showSystemMessage(Map<String, dynamic> payload) {
  final message = payload['message'] ?? '';
  final level = payload['level'] ?? 'info'; // info, warning, error
  
  Color backgroundColor;
  switch (level) {
    case 'warning':
      backgroundColor = Colors.orange;
      break;
    case 'error':
      backgroundColor = Colors.red;
      break;
    default:
      backgroundColor = Colors.blue;
  }
  
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      backgroundColor: backgroundColor,
    ),
  );
}

// 🆕 Update assignment badge state
Future<void> _updateAssignmentBadge(bool hasNewAssignments) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_unread_assignments', hasNewAssignments);
    debugPrint('🔄 Updated assignment badge state: $hasNewAssignments');
  } catch (e) {
    debugPrint('❌ Error updating assignment badge: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // ✅ Initialize background timer service FIRST
  await TimerService.initializeBackgroundService();
  
  debugPrint('✅ Timer background service initialized');

  // ✅ Initialize overlay service
  await overlayService.initialize();
  debugPrint('✅ Overlay service initialized');

  // ✅ Request overlay permission at startup (optional)
  try {
    final timerService = TimerService();
    await timerService.checkOverlayPermission();
    debugPrint('🎯 Initial overlay permission check completed');
  } catch (e) {
    debugPrint('❌ Error checking overlay permission at startup: $e');
  }

  // ✅ Request location permission
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
  debugPrint("🌐  WEBSOCKET BASE URL → ${ApiConfig.websocketBase}");
  debugPrint("🎯  OVERLAY PERMISSION → ${await Permission.systemAlertWindow.status}");
  debugPrint("🎯  OVERLAY SERVICE INIT → ✅");
  debugPrint("📱  INITIAL APP STATE → Initializing...");
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
  StreamSubscription? _websocketSubscription; // WebSocket subscription
  StreamSubscription? _connectionStateSubscription; // 🆕 Connection state subscription
  StreamSubscription? _reconnectedSubscription; // 🆕 Reconnection event subscription
  final TimerService _timerService = TimerService(); // 🆕 Timer service instance
  bool _isFocusModeActive = false; // 🆕 Track focus mode state
  bool _appInForeground = true; // 🆕 Track if app is in foreground
  bool _isShowingReconnectionSnackbar = false; // 🆕 Track reconnection snackbar state
  bool _shouldNavigateOnReconnect = true; // 🆕 Control navigation on reconnection
  bool _wasWebSocketConnected = false;
  Timer? _reconnectionNavigationTimer;
  bool _hasNavigatedOnReconnection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationService();
    
    // Initialize WebSocket handler
    _initWebSocketHandler();
    
    // 🆕 Setup global reconnection handler
    _setupGlobalReconnectionHandler();
    
    // 🆕 Ensure overlay is hidden when app starts
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureOverlayHidden();
    });
    
    // 🆕 Initialize timer service and check focus mode state
    _timerService.initialize().then((_) {
      debugPrint('✅ TimerService initialized in main.dart');
      _checkFocusModeState();
    }).catchError((e) {
      debugPrint('❌ Error initializing TimerService: $e');
    });
    
    // Check if user should be redirected to focus mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRedirectToFocusMode();
    });

    // Setup API Config callbacks for UI notifications
    _setupApiConfigCallbacks();

    // Listen to API URL changes when network changes
    ApiConfig.startAutoListen(updateImmediately: false);

    // Start listening to location service status changes
    _startLocationServiceListener();

    // Start periodic location check when on Coremicron Wi-Fi
    _startPeriodicLocationCheck();

    debugPrint('🔎 Listening for network changes...');
  }

  // 🆕 Check current focus mode state
  Future<void> _checkFocusModeState() async {
    final prefs = await SharedPreferences.getInstance();
    _isFocusModeActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
    debugPrint('🎯 Current focus mode state: $_isFocusModeActive');
    
    // 🆕 Set initial app state
    if (_isFocusModeActive) {
      await _timerService.handleAppResumed(); // Initialize timer if focus is active
    }
  }
  
 void _initWebSocketHandler() async {
  // Initialize WebSocket listener
  _websocketSubscription = WebSocketManager.stream.listen(
    _handleWebSocketMessage,
    onError: (error) {
      debugPrint('❌ WebSocket stream error: $error');
      if (_appInForeground) {
         //_showWebSocketErrorSnackbar('Connection error. Reconnecting...');
      }
      _wasWebSocketConnected = false;
    },
  );

  // Listen to connection state
  _connectionStateSubscription = WebSocketManager.connectionStateStream.listen((isConnected) {
    debugPrint('📡 WebSocket connection state changed: $isConnected | Previous: $_wasWebSocketConnected');
    
    if (!isConnected && _appInForeground) {
      // WebSocket disconnected
      _wasWebSocketConnected = false;
      _hasNavigatedOnReconnection = false;
      
      if (WebSocketManager.connectionStatus != 'force_disconnected') {
        // Don't show if we're already showing a snackbar
        if (!_isShowingReconnectionSnackbar) {
           _showWebSocketErrorSnackbar('Connection lost. Reconnecting...');
        }
      }
    } else if (isConnected && _appInForeground) {
      // Connection restored
      _isShowingReconnectionSnackbar = false;
      
      // 🆕 CRITICAL: Check if this is a reconnection (was previously disconnected)
      if (!_wasWebSocketConnected && !_hasNavigatedOnReconnection) {
        debugPrint('🔄🔄🔄 WEB SOCKET RECONNECTED FROM DISCONNECTED STATE! 🔄🔄🔄');
        
        // Cancel any existing timer
        _reconnectionNavigationTimer?.cancel();
        
        // Schedule navigation with a delay to ensure connection is stable
        _reconnectionNavigationTimer = Timer(const Duration(milliseconds: 1000), () {
          if (WebSocketManager.isConnected) {
            _navigateToFocusModeEntryOnReconnection();
            _hasNavigatedOnReconnection = true;
          }
        });
      }
      
      _wasWebSocketConnected = true;
      
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text('Connected to server', style: TextStyle(fontSize: 15)),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  });

  // 🆕 Listen specifically for reconnection events
  _reconnectedSubscription = WebSocketManager.reconnectedStream.listen((_) {
    debugPrint('🔄 WebSocket reconnection event detected via stream');
    
    // Cancel any existing timer
    _reconnectionNavigationTimer?.cancel();
    
    // Schedule navigation with delay
    _reconnectionNavigationTimer = Timer(const Duration(milliseconds: 800), () {
      if (!_hasNavigatedOnReconnection) {
        _navigateToFocusModeEntryOnReconnection();
        _hasNavigatedOnReconnection = true;
      }
    });
  });

  // Check initial connection state
  _wasWebSocketConnected = WebSocketManager.isConnected;
  debugPrint('📡 Initial WebSocket connection state: $_wasWebSocketConnected');

  // Initial connection check with delay
  Timer(const Duration(seconds: 3), () async {
    await _checkWebSocketConnection();
  });
}

  // 🆕 Setup global reconnection handler
  void _setupGlobalReconnectionHandler() {
    // Listen for reconnection events globally
    _reconnectedSubscription = WebSocketManager.reconnectedStream.listen((_) async {
      if (!_appInForeground) return;
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Check current route
      final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
      if (currentRoute == null) return;
      
      final routeName = currentRoute.settings.name;
      
      // Skip if we're already on focus mode or on certain screens
      final screensToSkip = [
        '/focus_mode',
        '/getin',
        '/signup',
        '/otp_verification',
        '/account_creation',
        '/profile_completion_page',
      ];
      
      if (screensToSkip.contains(routeName)) {
        return;
      }
      
      // Check user type
      final prefs = await SharedPreferences.getInstance();
      final studentType = prefs.getString('profile_student_type')?.toUpperCase() ?? '';
      final isFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
      
      // Only navigate for Online/Offline students when focus mode is not active
      if ((studentType == 'ONLINE' || studentType == 'OFFLINE') && !isFocusActive) {
        debugPrint('🔄 Global reconnection handler: Navigating to focus mode');
        
        // Navigate with a slight delay for better UX
        Timer(const Duration(milliseconds: 500), () {
          if (navigatorKey.currentState?.mounted ?? false) {
            navigatorKey.currentState?.pushReplacementNamed('/focus_mode');
          }
        });
      }
    });
  }

 void _navigateToFocusModeEntryOnReconnection() async {
  try {
    // Check if navigation should be prevented
    if (!_shouldNavigateOnReconnect) {
      debugPrint('⏸️ Navigation on reconnect is currently disabled');
      return;
    }
    
    // Reset flag at beginning
    _hasNavigatedOnReconnection = true;
    
    // Check if we're already on focus mode or home screen
    final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
    if (currentRoute == null) {
      _hasNavigatedOnReconnection = false; // Reset if can't navigate
      return;
    }
    
    final routeName = currentRoute.settings.name;
    
    // Don't navigate if we're already on focus mode entry page
    if (routeName == '/focus_mode') {
      debugPrint('✅ Already on focus mode page, skipping navigation');
      return;
    }
    
    // List of routes where we shouldn't navigate away
    final protectedRoutes = [
      '/getin',
      '/signup',
      '/otp_verification',
      '/account_creation',
      '/profile_completion_page',
      '/forgot_password',
      '/forgot_otp_verification',
      '/reset_password',
      '/splash',
    ];
    
    if (protectedRoutes.contains(routeName)) {
      debugPrint('🛑 Protected route, not navigating away: $routeName');
      return;
    }
    
    // Check user type
    final prefs = await SharedPreferences.getInstance();
    final studentType = prefs.getString('profile_student_type')?.toUpperCase() ?? '';
    
    // Only redirect Online/Offline students
    if (studentType == 'ONLINE' || studentType == 'OFFLINE') {
      final isFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
      
      // Only navigate if focus mode is not active
      if (!isFocusActive) {
        debugPrint('🔄🔄🔄 WEB SOCKET RECONNECTED - Navigating to focus mode entry 🔄🔄🔄');
        
        // Use pushReplacementNamed to replace current screen
        if (navigatorKey.currentState?.mounted ?? false) {
          navigatorKey.currentState?.pushReplacementNamed('/focus_mode');
        }
      } else {
        debugPrint('🎯 Focus mode already active, staying on current page');
      }
    } else {
      debugPrint('🎯 Student type $studentType does not require focus mode navigation');
    }
  } catch (e) {
    debugPrint('❌ Error navigating to focus mode on reconnection: $e');
    _hasNavigatedOnReconnection = false; // Reset on error
  }
}

  // Enhanced WebSocket connection check
  Future<void> _checkWebSocketConnection() async {
    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    debugPrint("🔍 WEB SOCKET CONNECTION CHECK");
    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    
    if (token == null || token.isEmpty) {
      debugPrint("❌ No access token - WebSocket cannot connect");
      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return;
    }
    
    debugPrint("✅ Token exists - checking connection...");
    debugPrint("📊 Current WebSocket status: ${WebSocketManager.connectionStatus}");
    WebSocketManager.logConnectionState(); // 🆕 Log detailed state
    
    // Reset if stuck in connecting state for too long
    if (WebSocketManager.connectionStatus == 'connecting') {
      debugPrint("🔄 Resetting stuck connection state...");
      await WebSocketManager.resetConnectionState();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // Connect if disconnected
    if (WebSocketManager.connectionStatus == 'disconnected') {
      debugPrint("🔄 Attempting to connect WebSocket...");
      await WebSocketManager.connect();
    } else {
      debugPrint("✅ WebSocket already ${WebSocketManager.connectionStatus}");
    }
    
    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  }

  // Show WebSocket error snackbar
  void _showWebSocketErrorSnackbar(String message) {
    _isShowingReconnectionSnackbar = true;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 24),
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
        backgroundColor: Colors.orange.shade700,
        action: SnackBarAction(
          label: 'RECONNECT',
          textColor: Colors.white,
          onPressed: () {
            _isShowingReconnectionSnackbar = false;
            WebSocketManager.forceReconnect(); // 🔥 Use forceReconnect method
          },
        ),
      ),
    );
  }
  
  // 🆕 Temporarily disable reconnect navigation
  void _temporarilyDisableReconnectNavigation() {
    _shouldNavigateOnReconnect = false;
    Timer(const Duration(seconds: 5), () {
      _shouldNavigateOnReconnect = true;
    });
  }
  
  // Check if user should be redirected to focus mode
  Future<void> _checkAndRedirectToFocusMode() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Small delay for SharedPreferences
    
    final prefs = await SharedPreferences.getInstance();
    final studentType = prefs.getString('profile_student_type')?.toUpperCase() ?? '';
    
    // Only redirect Online/Offline students who are not in focus mode
    if (studentType == 'ONLINE' || studentType == 'OFFLINE') {
      final isFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
      
      if (!isFocusActive && mounted) {
        // Check if we're already on focus mode or home screen
        final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
        if (currentRoute == null || 
            (currentRoute.settings.name != '/focus_mode' && 
             currentRoute.settings.name != '/home')) {
          
          debugPrint('🎯 Redirecting to focus mode for student type: $studentType');
          navigatorKey.currentState?.pushReplacementNamed('/focus_mode');
        }
      } else if (isFocusActive) {
        debugPrint('🎯 Focus mode already active for student type: $studentType');
      }
    } else {
      debugPrint('🎯 Student type $studentType does not require focus mode');
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
          
          // Disconnect WebSocket if location disabled on Coremicron
          if (ApiConfig.isOnCoremicronWifi) {
            await WebSocketManager.disconnect();
            _showLocationRequiredDialog();
          }
        } else {
          debugPrint('✅ Location services ENABLED');
          
          // Re-check Wi-Fi and switch API
          await ApiConfig.initializeBaseUrl(printLogs: true);
          
          // Reconnect WebSocket if location enabled
          if (ApiConfig.isOnCoremicronWifi) {
            await _connectWebSocketIfLoggedIn();
          }
          
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
          // Disconnect WebSocket
          await WebSocketManager.disconnect();
        } else {
          // Try to connect WebSocket if not connected
          await _connectWebSocketIfLoggedIn();
        }
      }
    });
  }

  // Connect WebSocket if user is logged in
  Future<void> _connectWebSocketIfLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken');
      
      if (accessToken != null && accessToken.isNotEmpty) {
        if (WebSocketManager.connectionStatus == 'disconnected') {
          debugPrint('🔗 Attempting to connect WebSocket...');
          await WebSocketManager.connect();
        }
      } else {
        debugPrint('🔐 User not logged in, skipping WebSocket connection');
      }
    } catch (e) {
      debugPrint('❌ Error checking WebSocket connection: $e');
    }
  }

  // ✅ Setup callbacks for API switching, location requirement, and error snackbars
  void _setupApiConfigCallbacks() {
    // API switch notification
    ApiConfig.onApiSwitch = (String message, String apiUrl) {
      debugPrint('🔄 $message → $apiUrl');
      _showApiSwitchSnackBar(message);
      
      // Reconnect WebSocket when API switches
      Future.delayed(const Duration(seconds: 1), () async {
        await _connectWebSocketIfLoggedIn();
      });
    };

    // Location required dialog
    ApiConfig.onLocationRequired = () {
      debugPrint('📍 Location permission required for local Wi-Fi');
      _showLocationRequiredDialog();
    };

    // Error snackbar handler
    ApiConfig.onShowSnackbar = (String message, {bool isError = false}) {
      debugPrint('📢 Showing snackbar: $message');
      _showErrorSnackBar(message, isError: isError);
    };
  }

  // 🆕 Ensure overlay is hidden when app starts or during logout
  Future<void> ensureOverlayHidden() async {
    try {
      debugPrint('🎯 Ensuring overlay is hidden...');
      
      // Try using FocusOverlayManager if available
      try {
        final overlayManager = FocusOverlayManager();
        await overlayManager.initialize();
        if (overlayManager.isOverlayVisible) {
          await overlayManager.hideOverlay();
          debugPrint('✅ FocusOverlayManager: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusOverlayManager: $e');
      }
      
      // Also try overlay service
      try {
        if (overlayService.isOverlayVisible) {
          await overlayService.hideOverlay();
          debugPrint('✅ OverlayService: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with OverlayService: $e');
      }
      
      // Also try direct method channel call as fallback
      try {
        const platform = MethodChannel('focus_mode_overlay_channel');
        await platform.invokeMethod('hideOverlay');
        debugPrint('✅ Direct method channel: hideOverlay called');
      } catch (e) {
        debugPrint('⚠️ Direct method channel failed: $e');
      }
      
      // Clear overlay-related SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_focus_mode', false);
      
      debugPrint('✅ Overlay cleanup completed');
    } catch (e) {
      debugPrint('❌ Error ensuring overlay hidden: $e');
    }
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

  // ✅ Show error SnackBar with location prompt
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
              'You are connected to Coremicron Wi-Fi. To use the local API and WebSocket, '
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
  _websocketSubscription?.cancel();
  _connectionStateSubscription?.cancel();
  _reconnectedSubscription?.cancel();
  _reconnectionNavigationTimer?.cancel(); 
  ApiConfig.stopAutoListen();
  ApiConfig.onApiSwitch = null;
  ApiConfig.onLocationRequired = null;
  ApiConfig.onShowSnackbar = null;
  
  // Clean up WebSocket resources
  WebSocketManager.dispose();
  
  // 🆕 Dispose overlay service
  overlayService.dispose();
  
  // 🆕 Handle app detachment when app is being disposed (completely closed)
  if (_isFocusModeActive) {
    // Save state before disposing
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _timerService.handleAppDetached();
    });
  }
  
  // 🆕 Dispose timer service
  _timerService.dispose();
  
  super.dispose();
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle changed: $state');
    _appInForeground = state == AppLifecycleState.resumed;
    
    // 🆕 FIRST: Check focus mode state
    await _checkFocusModeState();
    
    // 🆕 Handle app state changes with TimerService
    if (state == AppLifecycleState.resumed) {
      // App is coming back to foreground
      debugPrint('📱 App RESUMED - handling TimerService');
      
      // Save app state as resumed
      await _timerService.handleAppResumed();
      
      // Always reinitialize API and check badge state on resume
      await ApiConfig.initializeBaseUrl(printLogs: true);
      await NotificationService.checkBadgeStateOnResume();
      
      // Reconnect WebSocket if disconnected when app comes to foreground
      if (WebSocketManager.connectionStatus == 'disconnected') {
        await _connectWebSocketIfLoggedIn();
      }
      
      // Check if user should see focus mode
      _checkAndRedirectToFocusMode();
      
      // Check overlay permission status on resume
      await _timerService.checkOverlayPermission();
      
    } else if (state == AppLifecycleState.paused) {
      // App is going to background
      debugPrint('📱 App PAUSED - handling TimerService');
      
      // Save app state as paused
      await _timerService.handleAppPaused();
      
    } else if (state == AppLifecycleState.detached) {
      // App is being completely closed/removed from recents
      debugPrint('📱 App DETACHED - stopping all timers and hiding overlay');
      
      // 🆕 CRITICAL: Hide overlay when app is completely closed
      await _ensureOverlayHidden();
      
      // 🆕 CRITICAL: Handle app detachment - stop timer and save state
      await _timerService.handleAppDetached();
    }
  }

  Future<void> _ensureOverlayHidden() async {
    try {
      debugPrint('🎯 Ensuring overlay is hidden...');
      
      // Clear overlay-related SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_focus_mode', false);
      
      // Try using FocusOverlayManager if available
      try {
        final overlayManager = FocusOverlayManager();
        await overlayManager.initialize();
        if (overlayManager.isOverlayVisible) {
          await overlayManager.hideOverlay();
          debugPrint('✅ FocusOverlayManager: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with FocusOverlayManager: $e');
      }
      
      // Also try overlay service
      try {
        if (overlayService.isOverlayVisible) {
          await overlayService.hideOverlay();
          debugPrint('✅ OverlayService: Overlay hidden');
        }
      } catch (e) {
        debugPrint('⚠️ Error with OverlayService: $e');
      }
      
      // Also try direct method channel call as fallback
      try {
        const platform = MethodChannel('focus_mode_overlay_channel');
        await platform.invokeMethod('hideOverlay');
        debugPrint('✅ Direct method channel: hideOverlay called');
      } on PlatformException catch (e) {
        debugPrint('⚠️ Direct method channel failed: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ Direct method channel error: $e');
      }
      
      // Additional delay to ensure overlay is hidden
      await Future.delayed(const Duration(milliseconds: 300));
      
      debugPrint('✅ Overlay cleanup completed for app detachment');
    } catch (e) {
      debugPrint('❌ Error ensuring overlay hidden: $e');
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

  Future<void> _logoutUser() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 🆕 CRITICAL: Clear ALL timer data on logout - DO THIS FIRST
    await TimerService.clearAllTimerData();
    
    debugPrint('🧹 Cleared ALL timer data on logout');

    // 🆕 Cancel any running background timer tasks
    await Workmanager().cancelAll();
    
    // 🆕 Disconnect WebSocket on logout
    await WebSocketManager.forceDisconnect();
    
    // 🆕 Clear user-specific data
    await prefs.remove('user_id');
    await prefs.remove('student_id');
    await prefs.remove('profile_student_type');
    await prefs.remove('is_new_login'); // Clear login flag if exists
    await prefs.remove('accessToken'); // Clear token for WebSocket

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
        '/focus_mode': (context) => const FocusModeEntryScreen(), 
      },
    );
  }
}