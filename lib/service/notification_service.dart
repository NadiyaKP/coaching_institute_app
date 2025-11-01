import 'dart:convert';
import 'dart:developer';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static late GlobalKey<NavigatorState> navigatorKey;

  // 🟢 ValueNotifier to track unread assignments
  static final ValueNotifier<bool> hasUnreadAssignments = ValueNotifier<bool>(false);

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
      log('✅ Notification permission granted');

      // Save FCM token
      String? token = await _messaging.getToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
        log('🔑 Token saved: $token');
      }

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        log('📩 Foreground message: ${message.data}');
        _showLocalNotification(message);
        _updateBadge(message);
      });

      // When user taps notification (app in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        log('🚀 Notification tapped (background): ${message.data}');
        _handleNavigation(message.data);
      });

      // When app is launched via notification (terminated)
      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        log('🧊 App launched via notification (terminated): ${initialMessage.data}');
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
      bool hasUnread = prefs.getBool('has_unread_assignments') ?? false;
      hasUnreadAssignments.value = hasUnread;
      log('📱 Loaded badge state: $hasUnread');
    } catch (e) {
      log('❌ Error loading badge state: $e');
    }
  }

  // 💾 Save badge state to shared preferences
  static Future<void> _saveBadgeState(bool hasUnread) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_unread_assignments', hasUnread);
      log('💾 Saved badge state: $hasUnread');
    } catch (e) {
      log('❌ Error saving badge state: $e');
    }
  }

  // 🌐 Background message handler - This runs when app is in background
  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    log('📩 Background FCM Data: ${message.data}');
    
    // Update badge state in background
    await _updateBadgeFromBackground(message);
    
    // Show local notification
    await _showLocalNotification(message);
  }

  // 🔔 Update badge from background (without ValueNotifier)
  static Future<void> _updateBadgeFromBackground(RemoteMessage message) async {
    final type = message.data['type']?.toString().toLowerCase();
    if (type == 'assignment') {
      log('🆕 Setting badge from background for assignment');
      // Save to SharedPreferences - this will be loaded when app resumes
      await _saveBadgeState(true);
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
    
    log('📲 Local notification shown: $title');
  }

  // 🧭 Navigation handler based on notification type
  static void _handleNavigation(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      log('⚠️ No navigator context available for navigation.');
      return;
    }

    final type = data['type']?.toString().toLowerCase();

    if (type == 'assignment') {
      // Clear badge when user navigates to academics via notification
      clearAssignmentBadge();
      log('📘 Navigating to Academics Screen via notification');
      navigatorKey.currentState?.pushNamed('/academics');
    } else if (type == 'exam') {
      log('🧾 Navigating to Exam Schedule');
      navigatorKey.currentState?.pushNamed('/exam_schedule');
    } else if (type == 'subscription') {
      log('💳 Navigating to Subscription');
      navigatorKey.currentState?.pushNamed('/subscription');
    } else {
      log('ℹ️ Unknown notification type: $type');
      navigatorKey.currentState?.pushNamed('/home');
    }
  }

  // 🔔 Set badge when assignment notification arrives (foreground)
  static void _updateBadge(RemoteMessage message) {
    final type = message.data['type']?.toString().toLowerCase();
    if (type == 'assignment') {
      hasUnreadAssignments.value = true;
      _saveBadgeState(true);
      log('🆕 Assignment badge activated in foreground');
    }
  }

  // 🔔 Clear badge when user views assignments
  static void clearAssignmentBadge() {
    hasUnreadAssignments.value = false;
    _saveBadgeState(false);
    log('✅ Assignment badge cleared');
  }

  // 🔄 Check and reload badge state when app resumes
  static Future<void> checkBadgeStateOnResume() async {
    log('🔄 Checking badge state on app resume');
    await _loadBadgeState();
  }

  // 🔍 Get current badge state
  static bool get hasUnreadAssignment => hasUnreadAssignments.value;
}