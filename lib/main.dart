import 'package:coaching_institute_app/screens/home.dart';
import 'package:coaching_institute_app/screens/view_profile.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:coaching_institute_app/hive_model.dart';
import '../service/api_config.dart';
import '../service/auth_service.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(PdfReadingRecordAdapter());
  }

  try {
    await Hive.openBox<PdfReadingRecord>('pdf_records_box');
    debugPrint('✅ Hive initialized and box opened successfully in main.dart');
  } catch (e) {
    debugPrint('❌ Error opening Hive box in main.dart: $e');
  }

  runApp(const CoachingInstituteApp());
}

class CoachingInstituteApp extends StatefulWidget {
  const CoachingInstituteApp({super.key});

  @override
  State<CoachingInstituteApp> createState() => _CoachingInstituteAppState();
}

class _CoachingInstituteAppState extends State<CoachingInstituteApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  // Remove the _isOnlineStudent flag - we'll check dynamically each time

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Removed _checkStudentType() - we'll check dynamically
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('📱 App lifecycle changed: $state');

    // Check student type dynamically each time
    final bool isOnlineStudent = await _isOnlineStudent();
    if (!isOnlineStudent) {
      debugPrint('🎯 Skipping attendance tracking for non-online student');
      return;
    }

    if (state == AppLifecycleState.paused) {
      debugPrint('🟡 App minimized or locked, storing end time...');
      await _storeEndTimeAndLastActive();
    }

    if (state == AppLifecycleState.resumed) {
      debugPrint('🟢 App resumed, checking last active time...');
      _checkLastActiveTimeOnResume();
    }
  }

  // Check if student is online dynamically
  Future<bool> _isOnlineStudent() async {
    final prefs = await SharedPreferences.getInstance();
    final studentType = prefs.getString('profile_student_type') ?? 
                       prefs.getString('student_type') ?? '';
    final bool isOnline = studentType.toUpperCase() == 'ONLINE';
    debugPrint('🎯 Dynamic student type check: $studentType -> Online: $isOnline');
    return isOnline;
  }

  // Store end timestamp and last_active_time
  Future<void> _storeEndTimeAndLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Only store if not already stored (prevent duplicates)
    String? existingEndTime = prefs.getString('end_time');
    if (existingEndTime == null) {
      String nowStr = DateTime.now().toIso8601String();
      await prefs.setString('end_time', nowStr);
      await prefs.setString('last_active_time', nowStr);
      debugPrint('✅ End timestamp stored: $nowStr');
      debugPrint('✅ Last active timestamp stored: $nowStr');
    } else {
      debugPrint('ℹ️ End time already exists, skipping duplicate storage');
    }
  }

  // Check last_active_time on resume
  Future<void> _checkLastActiveTimeOnResume() async {
    final prefs = await SharedPreferences.getInstance();
    String? endTimeStr = prefs.getString('end_time');

    if (endTimeStr != null) {
      debugPrint('⏱️ End time found: $endTimeStr');
      debugPrint('🟢 Showing continue dialog');
      _showContinueDialog();
    }
  }

  // Continue dialog with time check on OK button press
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
                // Get the current time when OK is clicked
                DateTime okClickTime = DateTime.now();
                debugPrint('⏰ OK button clicked at: ${okClickTime.toIso8601String()}');

                final prefs = await SharedPreferences.getInstance();
                String? endTimeStr = prefs.getString('end_time');

                if (endTimeStr != null) {
                  DateTime endTime = DateTime.parse(endTimeStr);
                  
                  // Calculate the difference between OK click time and end time
                  Duration elapsed = okClickTime.difference(endTime);
                  int totalSeconds = elapsed.inSeconds;
                  int minutes = elapsed.inMinutes;
                  int seconds = totalSeconds % 60;
                  
                  debugPrint('⏱️ Time elapsed since app was minimized: $totalSeconds seconds ($minutes minutes and $seconds seconds)');

                  // Check if total seconds is less than or equal to 120 seconds (2 minutes)
                  if (totalSeconds <= 120) {
                    // Less than or equal to 2 minutes - continue using the app
                    debugPrint('🟢 Time elapsed: $minutes min $seconds sec (≤ 2 minutes), continuing app');
                    await prefs.remove('end_time');
                    await prefs.remove('last_active_time');
                    debugPrint('✅ End timestamp and last_active_time removed');
                    Navigator.of (context).pop();
                  } else {
                    // More than 2 minutes - logout
                    debugPrint('🔴 Time elapsed: $minutes min $seconds sec (> 2 minutes), logging out');
                    Navigator.of(context).pop();
                    await _logoutUser();
                  }
                } else {
                  // If no end_time found, just continue
                  debugPrint('⚠️ No end_time found, continuing app');
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

  // Logout and send timestamps to backend (only for online students)
  Future<void> _logoutUser() async {
    debugPrint('🚪 Logging out user...');
    final prefs = await SharedPreferences.getInstance();
    
    // Check student type dynamically before proceeding with attendance tracking
    final bool isOnlineStudent = await _isOnlineStudent();
    
    if (isOnlineStudent) {
      String? start = prefs.getString('start_time');
      String? end = prefs.getString('end_time');

      if (start != null && end != null) {
        debugPrint('📤 Preparing API request with timestamps:');
        debugPrint('Start: $start, End: $end');

        final authService = AuthService();
        final accessToken = await authService.getAccessToken();

        // Remove milliseconds from timestamps
        String cleanStart = start.split('.')[0].replaceFirst('T', ' ');
        String cleanEnd = end.split('.')[0].replaceFirst('T', ' ');

        final body = {
          "records": [
            {"time_stamp": cleanStart, "is_checkin": 1},
            {"time_stamp": cleanEnd, "is_checkin": 0}
          ]
        };

        debugPrint('📦 API request payload: ${jsonEncode(body)}');

        try {
          final response = await http.post(
            Uri.parse(ApiConfig.buildUrl('/api/performance/add_onlineattendance/')),
            headers: {
              ...ApiConfig.commonHeaders,
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          );

          debugPrint('🌐 API response status: ${response.statusCode}');
          debugPrint('🌐 API response body: ${response.body}');

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('✅ Attendance sent successfully');
          } else {
            debugPrint('❌ Error sending attendance');
          }
        } catch (e) {
          debugPrint('❌ Exception while sending attendance: $e');
        }

        await prefs.remove('start_time');
        await prefs.remove('end_time');
        await prefs.remove('last_active_time');
        debugPrint('🗑️ SharedPreferences timestamps cleared');
      }
    } else {
      debugPrint('🎯 Skipping attendance tracking for non-online student during logout');
    }

    await AuthService().logout();
    debugPrint('✅ User auth data cleared');

    navigatorKey.currentState?.pushReplacementNamed('/signup');
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
        '/otp_verification': (context) => const OtpVerificationScreen(),
        '/account_creation': (context) => const AccountCreationScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile_completion_page': (context) => const ProfileCompletionPage(),
        '/notes': (context) => const NotesScreen(),
        '/question_papers': (context) => const QuestionPapersScreen(),
        '/video_classes': (context) => const VideoClassesScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/forgot_otp_verification': (context) => const ForgotOtpVerificationScreen(),
        '/reset_password': (context) => const ResetPasswordScreen(),
        '/mock_test': (context) => const MockTestScreen(),
        '/performance': (context) => const PerformanceScreen(),
        '/exam_schedule': (context) => const ExamScheduleScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/otp_verification':
            return MaterialPageRoute(
              builder: (context) => const OtpVerificationScreen(),
              settings: settings,
            );
          case '/account_creation':
            return MaterialPageRoute(
              builder: (context) => const AccountCreationScreen(),
              settings: settings,
            );
          default:
            return null;
        }
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Page Not Found'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Page Not Found',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('The requested page could not be found.'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}