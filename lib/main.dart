import 'package:coaching_institute_app/screens/home.dart';
import 'package:coaching_institute_app/screens/view_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'service/api_config.dart'; // ✅ Corrected import path
import 'service/auth_service.dart';
import 'service/notification_service.dart';
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

// 🔹 Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

Future<void> main() async {
  // ✅ Ensure Flutter bindings and system UI are ready
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // ✅ Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ Initialize Hive
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

  // ✅ Initialize Local Notifications
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

  // ✅ Initialize API Config before running app
  await ApiConfig.initializeBaseUrl(printLogs: true);
  ApiConfig.startAutoListen(updateImmediately: false);

  // 🟩🟩 Print currently active API in debug console 🟩🟩
  debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  debugPrint("🌐  ACTIVE API BASE URL → ${ApiConfig.currentBaseUrl}");
  debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

  runApp(const CoachingInstituteApp());
}

class CoachingInstituteApp extends StatefulWidget {
  const CoachingInstituteApp({super.key});

  @override
  State<CoachingInstituteApp> createState() => _CoachingInstituteAppState();
}

class _CoachingInstituteAppState extends State<CoachingInstituteApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationService();

    // ✅ Listen to API URL changes when network changes
    ApiConfig.startAutoListen(updateImmediately: true);

    // ✅ Print debug message whenever network switches
    debugPrint('🔎 Listening for network changes...');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle changed: $state');
    final bool isOnlineStudent = await _isOnlineStudent();
    if (!isOnlineStudent) return;

    if (state == AppLifecycleState.paused) {
      await _storeEndTimeAndLastActive();
    }

    if (state == AppLifecycleState.resumed) {
      _checkLastActiveTimeOnResume();
      await NotificationService.checkBadgeStateOnResume();
      debugPrint('🔄 Badge state reloaded on app resume');
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

  void _showContinueDialog() {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Continue'),
          content: const Text('Continue using the app'),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                DateTime okClickTime = DateTime.now();
                String? endTimeStr = prefs.getString('end_time');
                if (endTimeStr != null) {
                  DateTime endTime = DateTime.parse(endTimeStr);
                  Duration elapsed = okClickTime.difference(endTime);
                  if (elapsed.inSeconds <= 120) {
                    await prefs.remove('end_time');
                    await prefs.remove('last_active_time');
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pop();
                    await _logoutUser();
                  }
                } else {
                  Navigator.of(context).pop();
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
            Uri.parse(ApiConfig.buildUrl('/api/performance/add_onlineattendance/')),
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

    navigatorKey.currentState?.pushReplacementNamed('/getin');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
      },
    );
  }
}
