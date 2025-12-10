import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../common/theme_color.dart';
import '../../service/api_config.dart';
import '../../service/http_interceptor.dart';
import '../../service/websocket_manager.dart';
import '../../service/focus_mode_overlay_service.dart';

class AllowAppsScreen extends StatefulWidget {
  const AllowAppsScreen({Key? key}) : super(key: key);

  @override
  State<AllowAppsScreen> createState() => _AllowAppsScreenState();
}

class _AllowAppsScreenState extends State<AllowAppsScreen> with SingleTickerProviderStateMixin {
  List<Application> _installedApps = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  List<Application> _filteredApps = [];
  
  // New variables for allowed apps functionality
  List<String> _allowedAppsPackageNames = [];
  List<_AppData> _allowedAppDetails = [];
  TabController? _tabController;
  int _currentTabIndex = 0;
  
  // WebSocket subscription
  StreamSubscription<dynamic>? _webSocketSubscription;
  
  // SharedPreferences keys
  static const String _allowedAppsKey = 'allowed_apps_list';
  static const String _allowedAppsDetailsKey = 'allowed_apps_details';
  
  // Local notifications
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  bool _notificationsInitialized = false;
  
  // Focus mode overlay service
  final FocusModeOverlayService _focusOverlayService = FocusModeOverlayService();
  
  // Debug mode
  bool _debugMode = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(_handleTabChange);
    
    // Initialize in proper order
    _initFocusOverlayService().then((_) {
      // Set up listeners
      _setupAppLaunchListener();
      
      // Fetch data
      _fetchAllowedApps().then((_) {
        // Fetch installed apps
        _fetchInstalledApps();
      });
    });
    
    _initNotifications();
    _searchController.addListener(_filterApps);
    _setupWebSocketListener();
    
    if (_debugMode) {
      debugPrint('✅ AllowAppsScreen initialized');
    }
  }

  Future<void> _initFocusOverlayService() async {
    try {
      await _focusOverlayService.initialize();
      
      if (_debugMode) {
        debugPrint('✅ Focus overlay service initialized');
      }
      
      // Listen to overlay visibility changes
      _focusOverlayService.overlayVisibilityStream.listen((isVisible) {
        if (_debugMode) {
          debugPrint('📱 Overlay visibility changed: $isVisible');
        }
        if (mounted) {
          setState(() {});
        }
      });
      
      // Listen to app launch requests from overlay
      _focusOverlayService.appLaunchStream.listen((appData) {
        if (_debugMode) {
          debugPrint('🎯 App launch requested from overlay: ${appData['appName']}');
        }
        
        // Open the app
        if (appData.containsKey('packageName')) {
          _openApp(appData['packageName']);
        }
      });
      
      // Listen to return to study events
      _focusOverlayService.returnToStudyStream.listen((_) {
        if (_debugMode) {
          debugPrint('🔙 Return to study requested from overlay');
        }
        // Handle returning to app if needed
      });
      
    } catch (e) {
      debugPrint('❌ Error initializing focus overlay service: $e');
    }
  }
  
  void _setupAppLaunchListener() {
    // Already set up in _initFocusOverlayService
  }

  Future<void> _initNotifications() async {
    try {
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('app_icon');
      
      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );
      
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
          debugPrint('Notification tapped: ${notificationResponse.id}');
        },
      );
      
      await _createNotificationChannel();
      
      setState(() {
        _notificationsInitialized = true;
      });
      
      if (_debugMode) {
        debugPrint('✅ Notifications initialized successfully');
      }
    } catch (e) {
      debugPrint('❌ Error initializing notifications: $e');
    }
  }

  Future<void> _createNotificationChannel() async {
    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'app_permission_channel',
        'App Permission Notifications',
        description: 'Notifications for app permission requests',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      
      if (_debugMode) {
        debugPrint('✅ Notification channel created');
      }
    } catch (e) {
      debugPrint('❌ Error creating notification channel: $e');
    }
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      if (!_notificationsInitialized) {
        debugPrint('⚠️ Notifications not initialized yet');
        return;
      }
      
      const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
        'app_permission_channel',
        'App Permission Notifications',
        channelDescription: 'Notifications for app permission requests',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'App Permission Update',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(''),
      );
      
      const DarwinNotificationDetails darwinNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );
      
      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
      );
      
      if (_debugMode) {
        debugPrint('📱 Notification shown: $title - $body');
      }
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
    }
  }

  void _setupWebSocketListener() {
    _webSocketSubscription?.cancel();
    _webSocketSubscription = WebSocketManager.stream.listen(
      _handleWebSocketMessage,
      onError: (error) {
        debugPrint('❌ WebSocket stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    _searchController.dispose();
    _webSocketSubscription?.cancel();
    _focusOverlayService.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    setState(() {
      _currentTabIndex = _tabController!.index;
    });
  }

  Future<void> _fetchAllowedApps() async {
    try {
      if (_debugMode) {
        debugPrint('🔄 Fetching allowed apps...');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final savedAllowedApps = prefs.getStringList(_allowedAppsKey) ?? [];
      
      if (_debugMode) {
        debugPrint('📱 Found ${savedAllowedApps.length} saved allowed apps in SharedPreferences');
      }
      
      final savedAppsDetailsJson = prefs.getString(_allowedAppsDetailsKey) ?? '[]';
      final List<dynamic> appsDetailsList = json.decode(savedAppsDetailsJson);
      
      List<_AppData> allowedAppsDetails = [];
      for (var appData in appsDetailsList) {
        try {
          allowedAppsDetails.add(_AppData.fromJson(appData));
        } catch (e) {
          debugPrint('❌ Error parsing app data: $e');
        }
      }
      
      setState(() {
        _allowedAppsPackageNames = savedAllowedApps;
        _allowedAppDetails = allowedAppsDetails;
      });

      if (_debugMode) {
        debugPrint('✅ Loaded ${_allowedAppDetails.length} allowed app details');
      }
      
      // Also fetch from API to get latest
      await _fetchAllowedAppsFromAPI();
    } catch (e) {
      debugPrint('❌ Error fetching allowed apps from SharedPreferences: $e');
    }
  }

  Future<void> _fetchAllowedAppsFromAPI() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('accessToken');
      
      if (accessToken == null || accessToken.isEmpty) {
        debugPrint('⚠️ No access token found');
        return;
      }

      final url = Uri.parse('${ApiConfig.currentBaseUrl}/api/batch/allowed-apps/');
      
      if (_debugMode) {
        debugPrint('🌐 Fetching allowed apps from API: $url');
      }
      
      final response = await globalHttpClient.get(
        url,
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['allowed_apps'] != null) {
          final List<dynamic> allowedAppsList = responseData['allowed_apps'];
          
          final List<String> newAllowedApps = allowedAppsList.map((app) => app.toString()).toList();
          
          if (_debugMode) {
            debugPrint('📱 Received ${newAllowedApps.length} allowed apps from API');
          }
          
          // Get app details for allowed apps
          List<Map<String, dynamic>> appsDetails = [];
          for (var packageName in newAllowedApps) {
            Application? foundApp;
            for (var app in _installedApps) {
              if (app.packageName == packageName) {
                foundApp = app;
                break;
              }
            }
            
            if (foundApp != null) {
              appsDetails.add(_appToData(foundApp));
              if (_debugMode) {
                debugPrint('✅ Found app: ${foundApp.appName} ($packageName)');
              }
            } else {
              // Create a simple app data entry
              appsDetails.add({
                'appName': packageName,
                'packageName': packageName,
                'versionName': null,
                'systemApp': false,
                'enabled': true,
                'iconBytes': null,
              });
              if (_debugMode) {
                debugPrint('⚠️ App not installed: $packageName');
              }
            }
          }
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(_allowedAppsKey, newAllowedApps);
          await prefs.setString(_allowedAppsDetailsKey, json.encode(appsDetails));
          
          setState(() {
            _allowedAppsPackageNames = newAllowedApps;
            _allowedAppDetails = appsDetails.map((data) => _AppData.fromJson(data)).toList();
          });
          
          if (_debugMode) {
            debugPrint('✅ Allowed apps fetched from API: ${_allowedAppsPackageNames.length} apps');
          }
          
          // Save to overlay
          await _saveAllowedAppsForOverlay(_allowedAppDetails);
        } else {
          if (_debugMode) {
            debugPrint('⚠️ No allowed_apps field in API response');
          }
        }
      } else if (response.statusCode == 401) {
        debugPrint('⚠️ Unauthorized - token might be expired');
      } else {
        debugPrint('❌ Failed to fetch allowed apps: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching allowed apps from API: $e');
    }
  }

  Map<String, dynamic> _appToData(Application app) {
    Map<String, dynamic> data = {
      'appName': app.appName,
      'packageName': app.packageName,
      'versionName': app.versionName,
      'systemApp': app.systemApp,
      'enabled': true, // Default to true
    };
    
    if (app is ApplicationWithIcon && app.icon != null) {
      data['iconBytes'] = base64.encode(app.icon!);
      if (_debugMode) {
        debugPrint('📱 Icon for ${app.appName}: ${app.icon!.length} bytes');
      }
    }
    
    return data;
  }

  Future<void> _saveAllowedAppsToPrefs(List<String> allowedApps, List<_AppData> appDetails) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_allowedAppsKey, allowedApps);
      
      List<Map<String, dynamic>> appsDetailsData = [];
      for (var app in appDetails) {
        appsDetailsData.add(app.toJson());
      }
      await prefs.setString(_allowedAppsDetailsKey, json.encode(appsDetailsData));
      
      if (_debugMode) {
        debugPrint('✅ Allowed apps saved to SharedPreferences: ${allowedApps.length} apps');
      }
      
      // Save to overlay
      await _saveAllowedAppsForOverlay(appDetails);
    } catch (e) {
      debugPrint('❌ Error saving allowed apps to SharedPreferences: $e');
    }
  }
  
  // UPDATED: Method to save allowed apps for overlay
  Future<void> _saveAllowedAppsForOverlay(List<_AppData> apps) async {
    try {
      final List<Map<String, dynamic>> appsData = [];
      
      if (_debugMode) {
        debugPrint('📱 Preparing ${apps.length} apps for overlay');
      }
      
      for (var app in apps) {
        String? iconBase64;
        if (app.iconBytes != null) {
          try {
            iconBase64 = base64.encode(app.iconBytes!);
            if (_debugMode) {
              debugPrint('📱 App: ${app.appName}, Has icon: ${iconBase64.length > 0}');
            }
          } catch (e) {
            debugPrint('⚠️ Error encoding icon for ${app.appName}: $e');
            iconBase64 = null;
          }
        }
        
        appsData.add({
          'appName': app.appName,
          'packageName': app.packageName,
          'iconBytes': iconBase64,
        });
        
        if (_debugMode) {
          debugPrint('📱 Added app to overlay data: ${app.appName} (${app.packageName})');
        }
      }
      
      // Save to overlay service
      final success = await _focusOverlayService.updateAllowedApps(appsData);
      
      if (success) {
        if (_debugMode) {
          debugPrint('✅ Saved ${appsData.length} allowed apps for overlay');
        }
        
        // Refresh overlay if it's showing
        await _focusOverlayService.refreshAllowedAppsInOverlay();
        
        // Verify data was saved
        try {
          final savedData = await _focusOverlayService.getAllowedApps();
          if (_debugMode) {
            debugPrint('📱 Verified saved data: ${savedData.length} apps');
          }
        } catch (e) {
          debugPrint('⚠️ Could not verify saved data: $e');
        }
      } else {
        debugPrint('❌ Failed to save allowed apps for overlay');
      }
    } catch (e) {
      debugPrint('❌ Error saving allowed apps for overlay: $e');
      debugPrint('❌ Stack trace: ${e.toString()}');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (_debugMode) {
      debugPrint('📩 WebSocket message received in AllowAppsScreen: $message');
    }
    
    try {
      dynamic parsedMessage;
      if (message is String) {
        parsedMessage = json.decode(message);
      } else {
        parsedMessage = message;
      }

      if (parsedMessage is Map<String, dynamic>) {
        if (parsedMessage['type'] == 'app_permission') {
          final data = parsedMessage['data'] as Map<String, dynamic>;
          final appPackage = data['app'] as String;
          final isAllowed = data['allowed'] as bool;
          
          Application? targetApp;
          String appName = appPackage;
          Uint8List? iconBytes;
          
          for (var app in _installedApps) {
            if (app.packageName == appPackage) {
              targetApp = app;
              appName = app.appName;
              if (app is ApplicationWithIcon) {
                iconBytes = app.icon;
              }
              break;
            }
          }
          
          if (isAllowed) {
            final appData = _AppData(
              appName: appName,
              packageName: appPackage,
              versionName: targetApp?.versionName,
              systemApp: targetApp?.systemApp ?? false,
              enabled: true,
              iconBytes: iconBytes,
            );
            
            _addAppToAllowed(appPackage, appData);
            
            _showNotification(
              'App Permission Granted ✅',
              'Your request for allowing $appName got granted',
            );
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: AppColors.white, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your request for allowing $appName got granted',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.successGreen,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            _removeAppFromAllowed(appPackage);
            
            _showNotification(
              'App Permission Denied ❌',
              'Your request for allowing $appName was not granted',
            );
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.error, color: AppColors.white, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your request for allowing $appName was not granted',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: AppColors.warningOrange,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error handling WebSocket message: $e');
    }
  }

  void _addAppToAllowed(String appPackage, _AppData appData) {
    if (!_allowedAppsPackageNames.contains(appPackage)) {
      setState(() {
        _allowedAppsPackageNames.add(appPackage);
        _allowedAppDetails.add(appData);
        _saveAllowedAppsToPrefs(_allowedAppsPackageNames, _allowedAppDetails);
      });
      
      if (_debugMode) {
        debugPrint('✅ Added $appPackage to allowed apps');
      }
    }
  }

  void _removeAppFromAllowed(String appPackage) {
    if (_allowedAppsPackageNames.contains(appPackage)) {
      setState(() {
        _allowedAppsPackageNames.remove(appPackage);
        _allowedAppDetails.removeWhere((app) => app.packageName == appPackage);
        _saveAllowedAppsToPrefs(_allowedAppsPackageNames, _allowedAppDetails);
      });
      
      if (_debugMode) {
        debugPrint('❌ Removed $appPackage from allowed apps');
      }
    }
  }

  Future<void> _fetchInstalledApps() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      if (_debugMode) {
        debugPrint('🔄 Fetching installed apps...');
      }

      final apps = await DeviceApps.getInstalledApplications(
        includeSystemApps: true,
        includeAppIcons: true,
      );

      List<Application> launchableApps = [];
      for (var app in apps) {
        if (app is ApplicationWithIcon) {
          bool isLaunchable = await DeviceApps.isAppInstalled(app.packageName);
          if (isLaunchable) {
            launchableApps.add(app);
          }
        }
      }

      launchableApps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

      setState(() {
        _installedApps = launchableApps;
        _filteredApps = List.from(_installedApps);
        _isLoading = false;
      });
      
      if (_debugMode) {
        debugPrint('✅ Found ${_installedApps.length} launchable apps');
      }
      
      _updateAllowedAppDetails();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to fetch apps: $e\n\n'
                       'Note: On Android 11+, you might see fewer apps '
                       'due to privacy restrictions.';
        _isLoading = false;
      });
      debugPrint('❌ Error fetching installed apps: $e');
    }
  }

  void _updateAllowedAppDetails() async {
    if (_debugMode) {
      debugPrint('🔄 Updating allowed app details...');
    }
    
    List<_AppData> updatedDetails = [];
    for (var packageName in _allowedAppsPackageNames) {
      Application? foundApp;
      for (var app in _installedApps) {
        if (app.packageName == packageName) {
          foundApp = app;
          break;
        }
      }
      
      if (foundApp != null) {
        Uint8List? iconBytes;
        if (foundApp is ApplicationWithIcon) {
          iconBytes = foundApp.icon;
          if (_debugMode) {
            debugPrint('📱 Found icon for ${foundApp.appName}: ${iconBytes?.length ?? 0} bytes');
          }
        }
        
        updatedDetails.add(_AppData(
          appName: foundApp.appName,
          packageName: foundApp.packageName,
          versionName: foundApp.versionName,
          systemApp: foundApp.systemApp,
          enabled: true,
          iconBytes: iconBytes,
        ));
        
        if (_debugMode) {
          debugPrint('📱 Updated details for: ${foundApp.appName}');
        }
      } else {
        updatedDetails.add(_AppData(
          appName: packageName,
          packageName: packageName,
          versionName: null,
          systemApp: false,
          enabled: true,
          iconBytes: null,
        ));
        
        if (_debugMode) {
          debugPrint('⚠️ App not found in installed apps: $packageName');
        }
      }
    }
    
    setState(() {
      _allowedAppDetails = updatedDetails;
    });
    
    if (_debugMode) {
      debugPrint('📱 Total updated app details: ${updatedDetails.length}');
    }
    
    // Save to preferences AND overlay
    await _saveAllowedAppsToPrefs(_allowedAppsPackageNames, _allowedAppDetails);
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredApps = List.from(_installedApps);
      });
    } else {
      setState(() {
        _filteredApps = _installedApps.where((app) {
          return app.appName.toLowerCase().contains(query) ||
                 app.packageName.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  void _showPermissionDialog(Application app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.primaryBlue),
            SizedBox(width: 8),
            Text('Ask Permission'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (app is ApplicationWithIcon && app.icon != null)
              Container(
                width: 60,
                height: 60,
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.backgroundGrey,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(app.icon!, fit: BoxFit.cover),
                ),
              ),
            Text(
              'Ask permission to allow',
              style: TextStyle(fontSize: 14, color: AppColors.grey600),
            ),
            SizedBox(height: 4),
            Text(
              '"${app.appName}"',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlue,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'to use?',
              style: TextStyle(fontSize: 14, color: AppColors.grey600),
            ),
            SizedBox(height: 16),
            Text(
              'Your mentor will review your request',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.grey500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.grey500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _sendPermissionRequest(app);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Ask Permission'),
          ),
        ],
      ),
    );
  }

  void _sendPermissionRequest(Application app) {
    try {
      final eventData = {
        "event": "request_app_permission",
        "app": app.packageName,
      };
      
      WebSocketManager.send(eventData);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your request for permission sends successfully, Your mentor will allow it for you',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.successGreen,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      if (_debugMode) {
        debugPrint('📤 WebSocket event sent: ${json.encode(eventData)}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Failed to send permission request: $e',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.errorRed,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      debugPrint('❌ Error sending WebSocket event: $e');
    }
  }

  Future<void> _openApp(String packageName) async {
    try {
      bool opened = await DeviceApps.openApp(packageName);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open app'),
            backgroundColor: AppColors.warningOrange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening app: $e'),
            backgroundColor: AppColors.errorRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleAppTap(Application app) {
    if (_allowedAppsPackageNames.contains(app.packageName)) {
      _openApp(app.packageName);
    } else {
      _showPermissionDialog(app);
    }
  }

  void _handleAllowedAppTap(_AppData app) {
    _openApp(app.packageName);
  }

  List<dynamic> _getCurrentTabApps() {
    if (_currentTabIndex == 0) {
      return _filteredApps;
    } else {
      return _allowedAppDetails;
    }
  }
  
  // Toggle overlay visibility
  Future<void> _toggleOverlay() async {
    try {
      if (_focusOverlayService.isOverlayVisible) {
        await _focusOverlayService.hideOverlay();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Overlay hidden'),
              backgroundColor: AppColors.successGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        await _testOverlayWithApps();
      }
    } catch (e) {
      debugPrint('❌ Error toggling overlay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }
  
  // NEW: Method to refresh overlay data immediately
  Future<void> _refreshOverlayData() async {
    try {
      if (_debugMode) {
        debugPrint('🔄 Refreshing overlay data...');
      }
      
      // Make sure we have the latest allowed apps
      await _fetchAllowedAppsFromAPI();
      
      // Update overlay with current data
      await _saveAllowedAppsForOverlay(_allowedAppDetails);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Overlay data refreshed with ${_allowedAppDetails.length} apps'),
            backgroundColor: AppColors.successGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error refreshing overlay data: $e');
    }
  }
  
  // NEW: Test overlay data flow
  Future<void> _testOverlayDataFlow() async {
    try {
      if (_debugMode) {
        debugPrint('🧪 Testing overlay data flow...');
      }
      
      // 1. Check current allowed apps
      debugPrint('📱 Current allowed apps count: ${_allowedAppDetails.length}');
      
      // 2. Check if overlay has data
      final overlayData = await _focusOverlayService.getAllowedApps();
      debugPrint('📱 Overlay data count: ${overlayData.length}');
      
      // 3. Send test data
      if (_allowedAppDetails.isNotEmpty) {
        debugPrint('📱 Sending first app to overlay: ${_allowedAppDetails.first.appName}');
        await _saveAllowedAppsForOverlay([_allowedAppDetails.first]);
      }
      
      // 4. Verify
      final newOverlayData = await _focusOverlayService.getAllowedApps();
      debugPrint('📱 After update - Overlay data count: ${newOverlayData.length}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test complete. Overlay data: ${newOverlayData.length} apps'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error testing overlay data flow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test failed: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }
  
  // NEW: Test overlay functionality
  Future<void> _testOverlayWithApps() async {
    try {
      // First, ensure we have permission
      if (!_focusOverlayService.hasPermission) {
        final granted = await _focusOverlayService.requestOverlayPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Overlay permission required'),
                backgroundColor: AppColors.errorRed,
              ),
            );
          }
          return;
        }
      }
      
      // Update overlay with current allowed apps
      await _saveAllowedAppsForOverlay(_allowedAppDetails);
      
      // Show overlay
      await _focusOverlayService.showOverlay();
      
      if (_debugMode) {
        debugPrint('✅ Overlay shown with ${_allowedAppDetails.length} allowed apps');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Overlay shown with ${_allowedAppDetails.length} allowed apps'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
      
    } catch (e) {
      debugPrint('❌ Error showing overlay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }
  
  // NEW: Clear overlay data
  Future<void> _clearOverlayData() async {
    try {
      await _focusOverlayService.clearAllowedApps();
      if (_debugMode) {
        debugPrint('🗑️ Cleared overlay data');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared overlay data'),
            backgroundColor: AppColors.warningOrange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error clearing overlay data: $e');
    }
  }
  
  // NEW: Check overlay status
  Future<void> _checkOverlayStatus() async {
    try {
      final isShowing = await _focusOverlayService.isOverlayShowing();
      final hasPerm = await _focusOverlayService.checkOverlayPermission();
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Overlay Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overlay Showing: ${isShowing ? "Yes" : "No"}'),
              Text('Permission Granted: ${hasPerm ? "Yes" : "No"}'),
              Text('Allowed Apps: ${_allowedAppDetails.length}'),
              SizedBox(height: 8),
              Text('Overlay Service Initialized: ✅'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('❌ Error checking overlay status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Installed Apps',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryBlue,
          ),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryBlue),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primaryBlue,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: AppColors.grey500,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'All Apps'),
                Tab(text: 'Allowed Apps'),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              if (_currentTabIndex == 0) {
                _fetchInstalledApps();
              } else {
                _fetchAllowedAppsFromAPI();
              }
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(_focusOverlayService.isOverlayVisible 
                ? Icons.visibility_off 
                : Icons.visibility),
            onPressed: _toggleOverlay,
            tooltip: _focusOverlayService.isOverlayVisible 
                ? 'Hide Overlay' 
                : 'Show Overlay',
          ),
          // Add test overlay button
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'test_data_flow') {
                _testOverlayDataFlow();
              } else if (value == 'clear_data') {
                _clearOverlayData();
              } else if (value == 'debug_info') {
                _showDebugInfo();
              } else if (value == 'overlay_status') {
                _checkOverlayStatus();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'test_data_flow',
                child: Row(
                  children: [
                    Icon(Icons.architecture, size: 20),
                    SizedBox(width: 8),
                    Text('Test Data Flow'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_data',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 20),
                    SizedBox(width: 8),
                    Text('Clear Overlay Data'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'overlay_status',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Check Overlay Status'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'debug_info',
                child: Row(
                  children: [
                    Icon(Icons.bug_report, size: 20),
                    SizedBox(width: 8),
                    Text('Debug Info'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: AppColors.backgroundGrey,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowGrey,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search apps...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.grey500),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.grey500),
                          onPressed: () {
                            _searchController.clear();
                            _filterApps();
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _currentTabIndex == 0 ? Icons.apps_rounded : Icons.check_circle_rounded,
                        color: AppColors.primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentTabIndex == 0
                            ? 'Total Apps: ${_filteredApps.length}'
                            : 'Allowed Apps: ${_allowedAppDetails.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primaryBlueDark,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _currentTabIndex == 0 ? 'All Launchable Apps' : 'Permission Granted',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.grey500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _hasError
                    ? _buildErrorState()
                    : _buildAppsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryYellow,
          ),
          SizedBox(height: 16),
          Text(
            'Loading installed apps...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: AppColors.errorRed.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load apps',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.grey600,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_currentTabIndex == 0) {
                  _fetchInstalledApps();
                } else {
                  _fetchAllowedAppsFromAPI();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppsList() {
    final currentApps = _getCurrentTabApps();
    
    if (currentApps.isEmpty) {
      return _buildEmptyState();
    }
    
    return RefreshIndicator(
      color: AppColors.primaryYellow,
      backgroundColor: AppColors.white,
      onRefresh: () async {
        if (_currentTabIndex == 0) {
          await _fetchInstalledApps();
        } else {
          await _fetchAllowedAppsFromAPI();
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: currentApps.length,
        itemBuilder: (context, index) {
          if (_currentTabIndex == 0) {
            final app = currentApps[index] as Application;
            return _buildAppItem(app);
          } else {
            final app = currentApps[index] as _AppData;
            return _buildAllowedAppItem(app);
          }
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _currentTabIndex == 0 ? Icons.apps_outlined : Icons.check_circle_outline_rounded,
              size: 60,
              color: AppColors.grey400,
            ),
            const SizedBox(height: 16),
            Text(
              _currentTabIndex == 0
                  ? 'No launchable apps found'
                  : 'No allowed apps found',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.grey600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isEmpty
                  ? _currentTabIndex == 0
                      ? 'Try updating your device or check app permissions'
                      : 'Ask permission to use apps from the "All Apps" tab'
                  : 'No apps match your search',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.grey500,
              ),
            ),
            if (_currentTabIndex == 1) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _tabController?.animateTo(0);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Browse All Apps'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppItem(Application app) {
    bool hasIcon = app is ApplicationWithIcon;
    bool isAllowed = _allowedAppsPackageNames.contains(app.packageName);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: hasIcon && (app as ApplicationWithIcon).icon != null
            ? Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.backgroundGrey,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    (app as ApplicationWithIcon).icon!,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.primaryBlue.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.apps_rounded,
                  size: 20,
                  color: isAllowed ? AppColors.successGreen : AppColors.primaryBlue,
                ),
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.appName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAllowed) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.successGreen,
                size: 16,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              app.packageName.length > 30 
                ? '${app.packageName.substring(0, 30)}...' 
                : app.packageName,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.grey500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (app.versionName != null) ...[
              const SizedBox(height: 2),
              Text(
                'v${app.versionName}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.grey400,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            isAllowed ? Icons.open_in_new_rounded : Icons.lock_outline_rounded,
            size: 18,
          ),
          color: isAllowed ? AppColors.primaryBlue : AppColors.grey500,
          onPressed: () => _handleAppTap(app),
          tooltip: isAllowed ? 'Open app' : 'Request permission',
        ),
        onTap: () => _handleAppTap(app),
      ),
    );
  }

  Widget _buildAllowedAppItem(_AppData app) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        leading: app.iconBytes != null
            ? Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.backgroundGrey,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    app.iconBytes!,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.primaryBlue.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.apps_rounded,
                  size: 20,
                  color: AppColors.successGreen,
                ),
              ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                app.appName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.successGreen,
              size: 16,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              app.packageName.length > 30 
                ? '${app.packageName.substring(0, 30)}...' 
                : app.packageName,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.grey500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (app.versionName != null) ...[
              const SizedBox(height: 2),
              Text(
                'v${app.versionName}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.grey400,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(
            Icons.open_in_new_rounded,
            size: 18,
          ),
          color: AppColors.primaryBlue,
          onPressed: () => _handleAllowedAppTap(app),
          tooltip: 'Open app',
        ),
        onTap: () => _handleAllowedAppTap(app),
      ),
    );
  }
  
  // NEW: Show debug info
  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Debug Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current Tab: ${_currentTabIndex == 0 ? "All Apps" : "Allowed Apps"}'),
              SizedBox(height: 8),
              Text('Installed Apps: ${_installedApps.length}'),
              Text('Filtered Apps: ${_filteredApps.length}'),
              SizedBox(height: 8),
              Text('Allowed Package Names: ${_allowedAppsPackageNames.length}'),
              Text('Allowed App Details: ${_allowedAppDetails.length}'),
              SizedBox(height: 8),
              Text('Overlay Visible: ${_focusOverlayService.isOverlayVisible}'),
              Text('Has Overlay Permission: ${_focusOverlayService.hasPermission}'),
              SizedBox(height: 16),
              if (_allowedAppDetails.isNotEmpty) ...[
                Text('Allowed Apps List:', style: TextStyle(fontWeight: FontWeight.bold)),
                for (var app in _allowedAppDetails.take(5))
                  Text('  • ${app.appName} (${app.packageName})'),
                if (_allowedAppDetails.length > 5)
                  Text('  ... and ${_allowedAppDetails.length - 5} more'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Helper class to store app data
class _AppData {
  final String appName;
  final String packageName;
  final String? versionName;
  final bool systemApp;
  final bool enabled;
  final Uint8List? iconBytes;
  
  _AppData({
    required this.appName,
    required this.packageName,
    this.versionName,
    this.systemApp = false,
    this.enabled = true,
    this.iconBytes,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'appName': appName,
      'packageName': packageName,
      'versionName': versionName,
      'systemApp': systemApp,
      'enabled': enabled,
      'iconBytes': iconBytes != null ? base64.encode(iconBytes!) : null,
    };
  }
  
  factory _AppData.fromJson(Map<String, dynamic> json) {
    return _AppData(
      appName: json['appName'] ?? 'Unknown App',
      packageName: json['packageName'] ?? '',
      versionName: json['versionName'],
      systemApp: json['systemApp'] ?? false,
      enabled: json['enabled'] ?? true,
      iconBytes: json['iconBytes'] != null ? base64.decode(json['iconBytes']) : null,
    );
  }
}