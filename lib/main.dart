import 'package:coaching_institute_app/screens/home.dart';
import 'package:coaching_institute_app/screens/view_profile.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:coaching_institute_app/hive_model.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/account_creation_screen.dart';
import 'screens/login_otp_verification.dart';
import 'screens/email_login.dart';
import 'screens/profile_completion_page.dart';
import 'screens/email_login_otp.dart';
import 'screens/study_materials/study_materials.dart';
import 'screens/study_materials/notes/notes.dart';
import 'screens/study_materials/previous_question_papers/question_papers.dart';
import 'screens/study_materials/video_classes/video_classes.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive with Flutter-specific initialization
  await Hive.initFlutter();
  
  // Register the adapter for PdfReadingRecord
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(PdfReadingRecordAdapter());
  }
  
  // Open the box once globally so it's available throughout the app
  try {
    await Hive.openBox<PdfReadingRecord>('pdf_records_box');
    debugPrint('✅ Hive initialized and box opened successfully in main.dart');
  } catch (e) {
    debugPrint('❌ Error opening Hive box in main.dart: $e');
  }
  
  runApp(const CoachingInstituteApp());
}

class CoachingInstituteApp extends StatelessWidget {
  const CoachingInstituteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        '/signup': (context) => const SignupScreen(),
        '/otp_verification': (context) => const OtpVerificationScreen(),
        '/account_creation': (context) => const AccountCreationScreen(),
        '/home': (context) => const HomeScreen(),
        '/login_otp_verification': (context) => const LoginOtpVerificationScreen(),
        '/email_login': (context) => const EmailLoginScreen(),
        '/email_login_otp': (context) => const EmailLoginOtpScreen(),
        '/profile_completion_page': (context) => const ProfileCompletionPage(),
        '/study_materials': (context) => const StudyMaterialsScreen(),
        '/notes': (context) => const NotesScreen(),
        '/question_papers': (context) => const QuestionPapersScreen(),
        '/video_classes': (context) => const VideoClassesScreen(), 
      },
      // Handle route generation for passing arguments
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/otp_verification':
            return MaterialPageRoute(
              builder: (context) => const OtpVerificationScreen(),
              settings: settings, 
            );
          case '/account_creation':
            // For AccountCreationScreen, we don't pass constructor parameters
            // The screen will get the data from route arguments in didChangeDependencies
            return MaterialPageRoute(
              builder: (context) => const AccountCreationScreen(),
              settings: settings, // This ensures the arguments are available via ModalRoute.of(context)
            );
          default:
            return null;
        }
      },
      // Handle unknown routes
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