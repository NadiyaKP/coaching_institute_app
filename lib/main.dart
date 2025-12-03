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
import './screens/focus_mode/focus_mode_entry.dart';

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
      
      // Update focus timer if active
      final isFocusMode = prefs.getBool(TimerService.isFocusModeKey) ?? false;
      if (isFocusMode) {
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
    } catch (e) {
      debugPrint('❌ Error in timer background task: $e');
    }
    
    return Future.value(true);
  });
}

// 🆕 WebSocket message handler
void _handleWebSocketMessage(dynamic message) {
  try {
    debugPrint('📩 WebSocket message received in main.dart: $message');
    
    // Parse the message if it's JSON
    dynamic data;
    try {
      data = jsonDecode(message.toString());
    } catch (e) {
      // If not JSON, treat as string message
      data = {'message': message.toString()};
    }
    
    // Handle different message formats
    if (data is Map<String, dynamic>) {
      final type = data['event']?.toString().toLowerCase() ?? data['type']?.toString().toLowerCase();
      final payload = data['data'] ?? data;
      
      debugPrint('📊 WebSocket message type: $type');
      
      // Handle different types of WebSocket messages
      switch (type) {
        case 'attendance_update':
          _handleAttendanceUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'exam_update':
          _handleExamUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'assignment_update':
          _handleAssignmentUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'notification':
          _handleWebSocketNotification(Map<String, dynamic>.from(payload));
          break;
        case 'focus_mode':
          _handleFocusModeUpdate(Map<String, dynamic>.from(payload));
          break;
        case 'system_message':
          _showSystemMessage(Map<String, dynamic>.from(payload));
          break;
        case 'heartbeat':
          // Handle heartbeat response if needed
          debugPrint('💓 Heartbeat response received');
          break;
        default:
          debugPrint('ℹ️ Unhandled WebSocket message type: $type');
          // Broadcast the raw message for other listeners
          // scaffoldMessengerKey.currentState?.showSnackBar(
          //   SnackBar(
          //     content: Text('New update received'),
          //     duration: Duration(seconds: 3),
          //   ),
          // );
      }
    } else {
      // Handle non-JSON messages
      debugPrint('📝 Raw WebSocket message: $data');
    }
  } catch (e) {
    debugPrint('❌ Error handling WebSocket message: $e');
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
      duration: Duration(seconds: 3),
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
        duration: Duration(seconds: 4),
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
        duration: Duration(seconds: 5),
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
        duration: Duration(seconds: 5),
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
        duration: Duration(seconds: 3),
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
      duration: Duration(seconds: 4),
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

  // ✅ Request overlay permission at startup (optional)
  // We'll check it when needed, but can pre-check here
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
  final TimerService _timerService = TimerService(); // 🆕 Timer service instance
  bool _isFocusModeActive = false; // 🆕 Track focus mode state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationService();
    
    // Initialize WebSocket listener
    _initWebSocketListener();

    // Check WebSocket connection after app starts
    Timer(const Duration(seconds: 3), () {
      _checkWebSocketConnection();
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
  }
  
  // Initialize WebSocket listener
  void _initWebSocketListener() {
    _websocketSubscription = WebSocketManager.stream.listen(
      _handleWebSocketMessage,
      onError: (error) {
        debugPrint('❌ WebSocket stream error: $error');
        _showWebSocketErrorSnackbar('WebSocket connection error');
      },
      onDone: () {
        debugPrint('🔌 WebSocket stream closed');
        if (WebSocketManager.connectionStatus != 'disconnected') {
          _showWebSocketErrorSnackbar('WebSocket connection lost');
        }
      },
    );
  }

  // Show WebSocket error snackbar
  void _showWebSocketErrorSnackbar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        duration: Duration(seconds: 5),
        backgroundColor: Colors.orange.shade700,
        action: SnackBarAction(
          label: 'RECONNECT',
          textColor: Colors.white,
          onPressed: () {
            _checkWebSocketConnection();
          },
        ),
      ),
    );
  }

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
    
    // Only connect if not already connected and not currently connecting
    if (WebSocketManager.connectionStatus == 'disconnected') {
      debugPrint("🔄 Attempting to connect WebSocket...");
      await WebSocketManager.connect();
    } else {
      debugPrint("✅ WebSocket already ${WebSocketManager.connectionStatus}");
    }
    
    debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
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
    _websocketSubscription?.cancel(); // Dispose WebSocket subscription
    ApiConfig.stopAutoListen();
    ApiConfig.onApiSwitch = null;
    ApiConfig.onLocationRequired = null;
    ApiConfig.onShowSnackbar = null;
    
    // Clean up WebSocket resources
    WebSocketManager.dispose();
    
    // 🆕 Dispose timer service
    _timerService.dispose();
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle changed: $state');
    
    // 🆕 FIRST: Check focus mode state
    await _checkFocusModeState();
    
    // 🆕 Handle overlay based on focus mode state
    if (_isFocusModeActive) {
      debugPrint('🎯 Focus mode is ACTIVE - handling overlay');
      
      if (state == AppLifecycleState.paused) {
        // App is going to background during focus mode
        debugPrint('📱 App going to background during focus mode');
        await _timerService.handleAppPaused();
        
        // 🆕 Check if overlay permission is granted
        final hasOverlayPermission = await Permission.systemAlertWindow.isGranted;
        if (hasOverlayPermission) {
          debugPrint('🎯 Overlay permission granted - will show overlay');
        } else {
          debugPrint('⚠️ Overlay permission not granted - cannot show overlay');
        }
        
        // We'll keep WebSocket connected in background for real-time updates
        // If you want to disconnect when in background, uncomment below:
        // if (!WebSocketManager.isConnected) {
        //   await WebSocketManager.disconnect();
        // }
      } else if (state == AppLifecycleState.resumed) {
        // App is coming back to foreground during focus mode
        debugPrint('📱 App coming to foreground during focus mode');
        await _timerService.handleAppResumed();
        
        // Also reinitialize API and check badge state
        await ApiConfig.initializeBaseUrl(printLogs: true);
        await NotificationService.checkBadgeStateOnResume();
        
        // Reconnect WebSocket if disconnected when app comes to foreground
        if (WebSocketManager.connectionStatus == 'disconnected') {
          await _connectWebSocketIfLoggedIn();
        }
        
        // Check if user should see focus mode
        _checkAndRedirectToFocusMode();
        
        // 🆕 Check overlay permission status on resume
        await _timerService.checkOverlayPermission();
      }
    } else {
      // Focus mode is NOT active
      debugPrint('🎯 Focus mode is NOT active - normal lifecycle handling');
      
      if (state == AppLifecycleState.paused) {
        await _timerService.handleAppPaused();
      } else if (state == AppLifecycleState.resumed) {
        await _timerService.handleAppResumed();
        
        // Also reinitialize API and check badge state
        await ApiConfig.initializeBaseUrl(printLogs: true);
        await NotificationService.checkBadgeStateOnResume();
        
        // Reconnect WebSocket if disconnected when app comes to foreground
        if (WebSocketManager.connectionStatus == 'disconnected') {
          await _connectWebSocketIfLoggedIn();
        }
      }
    }
    
    // Keep your existing online student code...
    final bool isOnlineStudent = await _isOnlineStudent();
    if (!isOnlineStudent) return;

    if (state == AppLifecycleState.paused) {
      await _storeEndTimeAndLastActive();
    }

    if (state == AppLifecycleState.resumed) {
      _checkLastActiveTimeOnResume();
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

    // 🆕 CRITICAL: Clear ALL timer data on logout - DO THIS FIRST
    await TimerService.clearAllTimerData();
    
    debugPrint('🧹 Cleared ALL timer data on logout');

    // 🆕 Cancel any running background timer tasks
    await Workmanager().cancelAll();
    
    // 🆕 Disconnect WebSocket on logout
    await WebSocketManager.disconnect();
    
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
        '/focus_mode': (context) => const FocusModeEntryScreen(), 
      },
    );
  }
}