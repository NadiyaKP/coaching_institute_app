import 'dart:convert';
import 'dart:developer' as developer; 
import 'dart:io';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../service/api_config.dart';
import '../service/auth_service.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final AuthService _authService = AuthService();

  static late GlobalKey<NavigatorState> navigatorKey;

  // 🟢 ValueNotifier to track multiple badge states
  static final ValueNotifier<Map<String, bool>> badgeNotifier = 
      ValueNotifier<Map<String, bool>>({
    'hasUnreadAssignments': false,
    'hasUnreadSubscription': false,
    'hasUnreadVideoLectures': false, // 🆕 Added for video lectures
  });

  // Backward compatibility getters
  static bool get hasUnreadAssignment => badgeNotifier.value['hasUnreadAssignments'] ?? false;
  static bool get hasUnreadVideoLectures => badgeNotifier.value['hasUnreadVideoLectures'] ?? false; // 🆕 Getter for video lectures

  static Future<void> init(GlobalKey<NavigatorState> navKey) async {
    navigatorKey = navKey;

    // Load initial badge state from shared preferences
    await _loadBadgeState();

    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: initSettingsAndroid);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          _handleNavigation(Map<String, dynamic>.from(data));
        }
      },
    );

    NotificationSettings settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      developer.log('✅ Notification permission granted');

      // Save FCM token
      String? token = await _messaging.getToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
        developer.log('🔑 Token saved: $token'); 
      }

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        developer.log('📩 Foreground message: ${message.data}');
        _showLocalNotification(message);
        _updateBadge(message);
        // 🆕 Fetch unread notifications when a new notification arrives
        _fetchUnreadNotifications();
      });

      // When user taps notification (app in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        developer.log('🚀 Notification tapped (background): ${message.data}'); 
        _handleNavigation(message.data);
      });

      // When app is launched via notification (terminated)
      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        developer.log('🧊 App launched via notification (terminated): ${initialMessage.data}');
        _handleNavigation(initialMessage.data);
      }

      // Background handler - IMPORTANT: This handles background notifications
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  }

  // 🔄 Load badge state from shared preferences
  static Future<void> _loadBadgeState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool hasUnreadAssignments = prefs.getBool('has_unread_assignments') ?? false;
      bool hasUnreadSubscription = prefs.getBool('has_unread_subscription') ?? false;
      bool hasUnreadVideoLectures = prefs.getBool('has_unread_video_lectures') ?? false; // 🆕 Load video lectures badge
      
      badgeNotifier.value = {
        'hasUnreadAssignments': hasUnreadAssignments,
        'hasUnreadSubscription': hasUnreadSubscription,
        'hasUnreadVideoLectures': hasUnreadVideoLectures, // 🆕 Set video lectures badge
      };
      
      developer.log('📱 Loaded badge state - Assignments: $hasUnreadAssignments, Subscription: $hasUnreadSubscription, Video Lectures: $hasUnreadVideoLectures'); // ✅ Fixed log
    } catch (e) {
      developer.log('❌ Error loading badge state: $e'); 
    }
  }

  // 💾 Save badge state to shared preferences
  static Future<void> _saveBadgeState(String key, bool hasUnread) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, hasUnread);
      developer.log('💾 Saved badge state for $key: $hasUnread'); 
    } catch (e) {
      developer.log('❌ Error saving badge state: $e'); 
    }
  }

  // 🌐 Background message handler - This runs when app is in background
  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    developer.log('📩 Background FCM Data: ${message.data}'); 
    
    // Update badge state in background
    await _updateBadgeFromBackground(message);
    
    // 🆕 Fetch unread notifications in background
    await _fetchUnreadNotifications();
    
    // Show local notification
    await _showLocalNotification(message);
  }

  // 🔔 Update badge from background (without ValueNotifier)
  static Future<void> _updateBadgeFromBackground(RemoteMessage message) async {
    final type = message.data['type']?.toString().toLowerCase();
    if (type == 'assignment') {
      developer.log('🆕 Setting badge from background for assignment'); 
      await _saveBadgeState('has_unread_assignments', true);
    } else if (type == 'subscription_warning') {
      developer.log('🆕 Setting badge from background for subscription'); 
      await _saveBadgeState('has_unread_subscription', true);
    }
     else if (type == 'subscription_expired') {
      developer.log('🆕 Setting badge from background for subscription'); 
      await _saveBadgeState('has_unread_subscription', true);
    } else if (type == 'video_lecture') { // 🆕 Handle video_lecture type
      developer.log('🆕 Setting badge from background for video lecture'); 
      await _saveBadgeState('has_unread_video_lectures', true);
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final data = message.data;
    final title = data['title'] ?? message.notification?.title ?? 'New Notification';
    final body = data['body'] ?? message.notification?.body ?? 'You have a new notification';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Important notifications from the app',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: jsonEncode(data),
    );
    
    developer.log('📲 Local notification shown: $title');
  }

  // 🧭 Navigation handler based on notification type
  static void _handleNavigation(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      developer.log('⚠️ No navigator context available for navigation.'); 
      return;
    }

    final type = data['type']?.toString().toLowerCase();

    if (type == 'assignment') {
      // Clear badge when user navigates to academics via notification
      clearAssignmentBadge();
      developer.log('📘 Navigating to Academics Screen via notification');
      navigatorKey.currentState?.pushNamed('/academics');
    } else if (type == 'exam') {
      developer.log('🧾 Navigating to Exam Schedule'); 
      navigatorKey.currentState?.pushNamed('/exam_schedule');
    } else if (type == 'subscription_warning') {
      clearSubscriptionBadge();
      developer.log('💳 Navigating to Subscription'); 
      navigatorKey.currentState?.pushNamed('/subscription');
    }
    else if (type == 'subscription_expired') {
      clearSubscriptionBadge();
      developer.log('💳 Navigating to Subscription'); 
      navigatorKey.currentState?.pushNamed('/subscription');
    } 
    
    else if (type == 'video_lecture') { // 🆕 Handle video_lecture navigation
      clearVideoLectureBadge();
      developer.log('🎬 Navigating to Video Classes via notification');
      navigatorKey.currentState?.pushNamed('/videos');
    }

    else if (type == 'leave_status') { 
      clearVideoLectureBadge();
      developer.log('🎬 Navigating to leave application via notification');
      navigatorKey.currentState?.pushNamed('/academics');
    }
    
     else {
      developer.log('ℹ️ Unknown notification type: $type'); 
      navigatorKey.currentState?.pushNamed('/home');
    }
  }

  // 🔔 Set badge when notification arrives (foreground)
  static void _updateBadge(RemoteMessage message) {
    final type = message.data['type']?.toString().toLowerCase();
    if (type == 'assignment') {
      final currentBadges = Map<String, bool>.from(badgeNotifier.value);
      currentBadges['hasUnreadAssignments'] = true;
      badgeNotifier.value = currentBadges;
      _saveBadgeState('has_unread_assignments', true);
      developer.log('🆕 Assignment badge activated in foreground'); 
    } else if (type == 'subscription_warning') {
      final currentBadges = Map<String, bool>.from(badgeNotifier.value);
      currentBadges['hasUnreadSubscription'] = true;
      badgeNotifier.value = currentBadges;
      _saveBadgeState('has_unread_subscription', true);
      developer.log('🆕 Subscription badge activated in foreground'); 
    } 
    else if (type == 'subscription_expired') {
      final currentBadges = Map<String, bool>.from(badgeNotifier.value);
      currentBadges['hasUnreadSubscription'] = true;
      badgeNotifier.value = currentBadges;
      _saveBadgeState('has_unread_subscription', true);
      developer.log('🆕 Subscription badge activated in foreground'); 
    } else if (type == 'video_lecture') { // 🆕 Handle video_lecture badge
      final currentBadges = Map<String, bool>.from(badgeNotifier.value);
      currentBadges['hasUnreadVideoLectures'] = true;
      badgeNotifier.value = currentBadges;
      _saveBadgeState('has_unread_video_lectures', true);
      developer.log('🆕 Video lecture badge activated in foreground'); 
    }
  }

  // 🆕 Create HTTP client with custom certificate handling
  static http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // 🆕 Fetch unread notifications from API (similar to home.dart)
  static Future<void> _fetchUnreadNotifications() async {
    try {
      developer.log('📬 Fetching unread notifications from API...'); 
      final prefs = await SharedPreferences.getInstance();
      
      // Get access token for authorization
      String accessToken = await _authService.getAccessToken();
      if (accessToken.isEmpty) {
        developer.log('❌ Access token not available for fetching notifications'); 
        return;
      }

      developer.log('✅ Access token available for fetching notifications'); 

      final client = _createHttpClientWithCustomCert();

      try {
        final url = Uri.parse('${ApiConfig.currentBaseUrl}/api/notifications/unread/');
        developer.log('🌐 Making GET request to: $url'); 

        // Make GET request to fetch unread notifications
        final response = await client.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        ).timeout(const Duration(seconds: 15));

        developer.log('📬 Unread notifications response status: ${response.statusCode}'); 
        developer.log('📬 Unread notifications response body: ${response.body}'); 

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          
          // Store the complete response in SharedPreferences
          await prefs.setString('unread_notifications', json.encode(responseData));
          
          developer.log('✅ Unread notifications stored successfully'); 
          developer.log('📬 Total unread notifications: ${responseData.length}'); 
          
          // Print the stored data for verification
          final storedData = prefs.getString('unread_notifications');
          developer.log('💾 Stored notifications data: $storedData'); 
          
          // Update the notification service with the new data
          _updateNotificationBadgesFromAPI(responseData);
          
        } else if (response.statusCode == 401) {
          developer.log('🔐 Unauthorized - attempting token refresh');
          
          // Try to refresh token and retry
          final newAccessToken = await _authService.refreshAccessToken();
          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            developer.log('🔄 Retrying with refreshed token...');
            await _retryFetchUnreadNotifications(newAccessToken);
          } else {
            developer.log('❌ Token refresh failed'); 
          }
        } else {
          developer.log('❌ Failed to fetch unread notifications: ${response.statusCode}');         }
      } on TimeoutException {
        developer.log('⏰ Unread notifications request timed out'); 
      } on SocketException catch (e) {
        developer.log('🌐 Network error during notifications fetch: $e'); 
      } on HandshakeException catch (e) {
        developer.log('🔒 SSL Handshake error during notifications fetch: $e'); 
      } catch (e) {
        developer.log('❌ Unexpected error during notifications fetch: $e'); 
      } finally {
        client.close();
      }
    } catch (e) {
      developer.log('💥 Error in _fetchUnreadNotifications method: $e'); 
    }
  }

  // 🔄 Retry fetching unread notifications with new token
  static Future<void> _retryFetchUnreadNotifications(String newAccessToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final client = _createHttpClientWithCustomCert();

      try {
        final response = await client.get(
          Uri.parse('${ApiConfig.currentBaseUrl}/api/notifications/unread/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $newAccessToken',
          },
        ).timeout(const Duration(seconds: 15));

        developer.log('🔄 Retry response status: ${response.statusCode}'); 
        developer.log('🔄 Retry response body: ${response.body}'); 

        if (response.statusCode == 200) {
          final List<dynamic> responseData = json.decode(response.body);
          await prefs.setString('unread_notifications', json.encode(responseData));
          developer.log('✅ Unread notifications fetched successfully on retry'); 
          _updateNotificationBadgesFromAPI(responseData);
        } else {
          developer.log('❌ Retry failed: ${response.statusCode}'); 
        }
      } finally {
        client.close();
      }
    } catch (e) {
      developer.log('❌ Error in retry: $e'); 
    }
  }

  // 🆕 Update notification badges based on API response
  static void _updateNotificationBadgesFromAPI(List<dynamic> notifications) {
    bool hasAssignment = false;
    bool hasExam = false;
    bool hasSubscription = false;
    bool hasVideoLecture = false; // 🆕 Track video lectures

    for (var notification in notifications) {
      if (notification['data'] != null) {
        final String type = notification['data']['type']?.toString().toLowerCase() ?? '';
        
        if (type == 'assignment') {
          hasAssignment = true;
        } else if (type == 'exam') {
          hasExam = true;
        } else if (type == 'subscription_warning') {
          hasSubscription = true;
        }
        else if (type == 'subscription_expired') {
          hasSubscription = true;
        }  else if (type == 'video_lecture') { 
          hasVideoLecture = true;
        }
      }
    }

    developer.log('🎯 Notification analysis from API:'); 
    developer.log('   - Assignment: $hasAssignment'); 
    developer.log('   - Exam: $hasExam');
    developer.log('   - Subscription warning: $hasSubscription'); 
    developer.log('   - Subscription expired: $hasSubscription'); 
    developer.log('   - Video Lecture: $hasVideoLecture'); // 🆕 Log video lecture status 

    // Update badges
    updateBadges(
      hasUnreadAssignments: hasAssignment || hasExam,
      hasUnreadSubscription: hasSubscription,
      hasUnreadVideoLectures: hasVideoLecture, // 🆕 Pass video lecture status
    );
  }

  // 🔔 Public method to update badges (called from home.dart)
  static void updateBadges({
    required bool hasUnreadAssignments,
    required bool hasUnreadSubscription,
    bool hasUnreadVideoLectures = false, // 🆕 Added video lectures parameter
  }) {
    final currentBadges = Map<String, bool>.from(badgeNotifier.value);
    currentBadges['hasUnreadAssignments'] = hasUnreadAssignments;
    currentBadges['hasUnreadSubscription'] = hasUnreadSubscription;
    currentBadges['hasUnreadVideoLectures'] = hasUnreadVideoLectures; // 🆕 Set video lectures badge
    badgeNotifier.value = currentBadges;
    
    // Save to SharedPreferences
    _saveBadgeState('has_unread_assignments', hasUnreadAssignments);
    _saveBadgeState('has_unread_subscription', hasUnreadSubscription);
    _saveBadgeState('has_unread_video_lectures', hasUnreadVideoLectures); // 🆕 Save video lectures badge
    
    developer.log('🔔 Badges updated - Assignments: $hasUnreadAssignments, Subscription: $hasUnreadSubscription, Video Lectures: $hasUnreadVideoLectures'); // ✅ Fixed log
  }

  // 🔔 Clear assignment badge when user views assignments
  static void clearAssignmentBadge() {
    final currentBadges = Map<String, bool>.from(badgeNotifier.value);
    currentBadges['hasUnreadAssignments'] = false;
    badgeNotifier.value = currentBadges;
    _saveBadgeState('has_unread_assignments', false);
    developer.log('✅ Assignment badge cleared'); 
  }

  // 🔔 Clear subscription badge when user views subscription
  static void clearSubscriptionBadge() {
    final currentBadges = Map<String, bool>.from(badgeNotifier.value);
    currentBadges['hasUnreadSubscription'] = false;
    badgeNotifier.value = currentBadges;
    _saveBadgeState('has_unread_subscription', false);
    developer.log('✅ Subscription badge cleared'); 
  }

  // 🆕 Clear video lecture badge when user views video classes
  static void clearVideoLectureBadge() {
    final currentBadges = Map<String, bool>.from(badgeNotifier.value);
    currentBadges['hasUnreadVideoLectures'] = false;
    badgeNotifier.value = currentBadges;
    _saveBadgeState('has_unread_video_lectures', false);
    developer.log('✅ Video lecture badge cleared'); 
  }

  // 🔄 Check and reload badge state when app resumes
  static Future<void> checkBadgeStateOnResume() async {
    developer.log('🔄 Checking badge state on app resume'); 
    await _loadBadgeState();
    // Also fetch latest notifications when app resumes
    await _fetchUnreadNotifications();
  }
}