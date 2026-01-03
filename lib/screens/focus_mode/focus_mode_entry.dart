import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import '../../service/timer_service.dart';
import '../../service/websocket_manager.dart';
import '../../service/auth_service.dart';
import '../../service/api_config.dart';
import '../../service/focus_mode_overlay_service.dart';
import '../../screens/focus_mode/focus_overlay_manager.dart';
import 'package:workmanager/workmanager.dart';

class FocusModeEntryScreen extends StatefulWidget {
  const FocusModeEntryScreen({super.key});

  @override
  State<FocusModeEntryScreen> createState() => _FocusModeEntryScreenState();
}

class _FocusModeEntryScreenState extends State<FocusModeEntryScreen> 
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TimerService _timerService = TimerService();
  final AuthService _authService = AuthService();
  late Future<Duration> _initializationFuture;
  Duration _focusTimeToday = Duration.zero;
  bool _hasOverlayPermission = false;
  bool _hasUsageAccessPermission = false; 
  bool _isStartingFocusMode = false;
  bool _isRestoredFromDisconnect = false;
  bool _wasDisconnectedByWebSocket = false;
  bool _isReconnecting = false;
  bool _isLoggingOut = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  StreamSubscription<bool>? _websocketConnectionSubscription;
  Timer? _reconnectionCheckTimer;
  
  bool _hasShownDisconnectionMessage = false;
  bool _hasShownReconnectionMessage = false;
  bool _lastKnownConnectionState = true;

  // NEW: Track permission refresh state
  bool _isRefreshingPermissions = false;

  // NEW: Method channel for Android-specific permissions
  static const MethodChannel _methodChannel = 
      MethodChannel('focus_mode_overlay_channel');

  // NEW: Variables for allowed apps functionality
  static const String _allowedAppsKey = 'allowed_apps_list';
  static const String _allowedAppsDetailsKey = 'allowed_apps_details';
  List<String> _allowedAppsPackageNames = [];
  final FocusModeOverlayService _focusOverlayService = FocusModeOverlayService();
  bool _debugMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializationFuture = _initializeData();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _timerService.setWebSocketDisconnectCallback(() {
      debugPrint('🔄 WebSocket disconnection callback triggered in entry screen');
      _handleWebSocketDisconnectionNavigation();
    });
    
    _startWebSocketMonitoring();
    
    // NEW: Initialize focus overlay service
    _initFocusOverlayService();
  }

  // NEW: Initialize focus overlay service
  Future<void> _initFocusOverlayService() async {
    try {
      await _focusOverlayService.initialize();
      
      if (_debugMode) {
        debugPrint('✅ Focus overlay service initialized in entry screen');
      }
    } catch (e) {
      debugPrint('❌ Error initializing focus overlay service: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.detached) {
      debugPrint('📱 AppLifecycleState.detached - App being closed');
    }
    
    // NEW: Handle app resume to refresh permissions
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed, refreshing permissions...');
      _refreshPermissions();
    }
  }

  // NEW: Refresh permissions method
  Future<void> _refreshPermissions() async {
    if (_isRefreshingPermissions) return;
    
    try {
      setState(() {
        _isRefreshingPermissions = true;
      });
      
      debugPrint('🔄 Refreshing permissions...');
      
      // Check overlay permission
      final bool newOverlayPermission = await _timerService.checkOverlayPermission();
      
      // Check usage access permission
      final bool newUsageAccessPermission = await _checkUsageAccessPermission();
      
      if (mounted) {
        setState(() {
          _hasOverlayPermission = newOverlayPermission;
          _hasUsageAccessPermission = newUsageAccessPermission;
        });
        
        // Show success message if permissions were just granted
        if (newUsageAccessPermission && !_hasUsageAccessPermission) {
          _showSmallSnackbar(
            message: 'Usage Access permission granted!',
            backgroundColor: Colors.green,
            icon: Icons.check_circle,
          );
        }
        
        if (newOverlayPermission && !_hasOverlayPermission) {
          _showSmallSnackbar(
            message: 'Display over other apps permission granted!',
            backgroundColor: Colors.green,
            icon: Icons.check_circle,
          );
        }
      }
      
      debugPrint('📋 Permissions refreshed:');
      debugPrint('   - Overlay permission: $_hasOverlayPermission');
      debugPrint('   - Usage Access permission: $_hasUsageAccessPermission');
    } catch (e) {
      debugPrint('❌ Error refreshing permissions: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingPermissions = false;
        });
      }
    }
  }

  void _handleReconnectionNavigation() {
    if (mounted) {
      setState(() {
        _initializationFuture = _initializeData();
      });
    }
  }

  void _startWebSocketMonitoring() {
    _websocketConnectionSubscription?.cancel();
    _websocketConnectionSubscription = WebSocketManager.connectionStateStream.listen((isConnected) async {
      debugPrint('📡 WebSocket state changed in entry screen: $isConnected');
      
      if (mounted) {
        setState(() {});
      }
      
      // Handle disconnection - show message only once
      if (!isConnected && !WebSocketManager.isConnected && !_hasShownDisconnectionMessage) {
        debugPrint('🔌 WebSocket disconnected detected in entry screen');
        _hasShownDisconnectionMessage = true;
        _hasShownReconnectionMessage = false;
        
        final prefs = await SharedPreferences.getInstance();
        final wasFocusActive = prefs.getBool(TimerService.isFocusModeKey) ?? false;
        if (wasFocusActive && mounted) {
          _showWebSocketDisconnectedNotification();
        }
      } 
      // Handle reconnection - show message only once
      else if (isConnected && mounted && !_hasShownReconnectionMessage) {
        debugPrint('✅ WebSocket reconnected in entry screen');
        _hasShownReconnectionMessage = true;
        _hasShownDisconnectionMessage = false;
        
        if (_isReconnecting) {
          setState(() {
            _isReconnecting = false;
          });
        }
      }
      
      // Update last known state
      _lastKnownConnectionState = isConnected;
    });
  }

  void _handleWebSocketDisconnectionNavigation() {
    if (mounted) {
      _showSmallSnackbar(
        message: 'Focus mode stopped due to connection loss',
        backgroundColor: Colors.orange,
        icon: Icons.wifi_off,
      );
      
      setState(() {
        _wasDisconnectedByWebSocket = true;
        _initializationFuture = _initializeData();
      });
    }
  }

  void _showWebSocketDisconnectedNotification() {
    if (mounted) {
      _showSmallSnackbar(
        message: 'Focus mode was stopped due to connection loss',
        backgroundColor: Colors.orange,
        icon: Icons.wifi_off,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      );
    }
  }

  void _showSmallSnackbar({
    required String message,
    required Color backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 11), 
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          action: action,
        ),
      );
    }
  }

  // NEW: Check Usage Access permission
  Future<bool> _checkUsageAccessPermission() async {
    try {
      if (Platform.isAndroid) {
        // Add a small delay to ensure system has updated
        await Future.delayed(const Duration(milliseconds: 100));
        
        final bool hasPermission = await _methodChannel.invokeMethod('checkUsageStatsPermission');
        debugPrint('📊 Usage Access Permission: $hasPermission');
        return hasPermission;
      }
      // For iOS, return true as this permission is Android-specific
      return true;
    } catch (e) {
      debugPrint('❌ Error checking Usage Access permission: $e');
      return false;
    }
  }

  // NEW: Open Usage Access settings
  Future<void> _openUsageAccessSettings() async {
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('openUsageAccessSettings');
      } else {
        // For iOS, navigate to general settings
        await openAppSettings();
      }
    } catch (e) {
      debugPrint('❌ Error opening Usage Access settings: $e');
      _showSmallSnackbar(
        message: 'Unable to open settings',
        backgroundColor: Colors.red,
        icon: Icons.error,
      );
    }
  }

  // NEW: Show Usage Access permission dialog
  Future<bool?> _showUsageAccessPermissionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue, size: 20),
              SizedBox(width: 6),
              Text('Usage Access Required', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Focus Mode needs "Usage Access" permission to monitor app usage and block distractions effectively.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              _buildUsageAccessStep('1. Click "OPEN SETTINGS" below'),
              _buildUsageAccessStep('2. Find this app in the list'),
              _buildUsageAccessStep('3. Enable "Allow usage tracking"'),
              _buildUsageAccessStep('4. Return to this app - permissions will update automatically'),
              const SizedBox(height: 8),
              const Text(
                'Without this permission, Focus Mode cannot detect when you switch to other apps.',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('NOT NOW', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsageAccessStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 12, color: Colors.blue),
          const SizedBox(width: 3),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // Enhanced permission popup with better instructions
  Future<bool?> _showPermissionPopup() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.layers, color: Colors.orange, size: 20),
              SizedBox(width: 6),
              Text('Display Over Other Apps', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Focus Mode needs "Display over other apps" permission to block distracting apps.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              _buildPermissionStep('1. Click "OPEN SETTINGS" below'),
              _buildPermissionStep('2. Scroll down to "Display over other apps"'),
              _buildPermissionStep('3. Find and select this app from the list'),
              _buildPermissionStep('4. Enable "Allow display over other apps"'),
              _buildPermissionStep('5. Return to this app'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Note: On some Android devices, this setting may be called "Draw over other apps" or "Appear on top"',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Without this, Focus Mode cannot block other apps.',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('NOT NOW', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 12, color: Colors.orange),
          const SizedBox(width: 3),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<Duration> _initializeData() async {
    try {
      debugPrint('🔄 Starting focus mode entry initialization...');
      
      await _timerService.initialize();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String today = DateTime.now().toIso8601String().split('T')[0];
      
      debugPrint('📅 Today: $today');
      
      _wasDisconnectedByWebSocket = await _timerService.wasStoppedByWebSocket();
      if (_wasDisconnectedByWebSocket) {
        debugPrint('🔌 Focus was previously stopped by WebSocket disconnection');
      }
      
      final String? disconnectTimeStr = prefs.getString(TimerService.websocketDisconnectTimeKey);
      if (disconnectTimeStr != null) {
        final DateTime disconnectTime = DateTime.parse(disconnectTimeStr);
        final String disconnectDate = disconnectTime.toIso8601String().split('T')[0];
        
        debugPrint('🔌 Found WebSocket disconnect time: $disconnectDate');
        
        if (disconnectDate == today) {
          await _handleWebSocketDisconnectRecovery(prefs, today);
        } else {
          debugPrint('📅 Disconnect was on different day, clearing');
          await prefs.remove(TimerService.websocketDisconnectTimeKey);
          await prefs.remove(TimerService.wasWebsocketDisconnectedKey);
          await _handleNormalInitialization(prefs, today);
        }
      } else {
        await _handleNormalInitialization(prefs, today);
      }
      
      _hasOverlayPermission = await _timerService.checkOverlayPermission();
      
      // NEW: Check Usage Access permission
      _hasUsageAccessPermission = await _checkUsageAccessPermission();
      
      debugPrint('📋 Initialization Summary:');
      debugPrint('   - Focus time today: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Overlay permission: $_hasOverlayPermission');
      debugPrint('   - Usage Access permission: $_hasUsageAccessPermission');
      debugPrint('   - Restored from disconnect: $_isRestoredFromDisconnect');
      debugPrint('   - Stopped by WebSocket: $_wasDisconnectedByWebSocket');
      debugPrint('   - Date: $today');
      
      return _focusTimeToday;
      
    } catch (e) {
      debugPrint('❌ Error initializing data: $e');
      return Duration.zero;
    }
  }

  Future<void> _handleWebSocketDisconnectRecovery(SharedPreferences prefs, String today) async {
    try {
      debugPrint('🔌 Recovering from WebSocket disconnect...');
      
      final int? lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey);
      final String? lastStoredDate = prefs.getString(TimerService.lastStoredFocusDateKey);
      final int savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      
      debugPrint('   - Last stored time: ${lastStoredTime ?? 0}s');
      debugPrint('   - Last stored date: $lastStoredDate');
      debugPrint('   - Saved focus time: ${savedFocusTime}s');
      
      int focusSeconds = 0;
      if (lastStoredDate == today && lastStoredTime != null) {
        focusSeconds = lastStoredTime > savedFocusTime ? lastStoredTime : savedFocusTime;
        _isRestoredFromDisconnect = true;
        _wasDisconnectedByWebSocket = true;
        debugPrint('   ✅ Using restored time: ${focusSeconds}s');
      } else {
        focusSeconds = savedFocusTime;
        debugPrint('   ⚠️ Last stored date mismatch, using saved time: ${focusSeconds}s');
      }
      
      _focusTimeToday = Duration(seconds: focusSeconds);
      await prefs.setInt(TimerService.focusKey, focusSeconds);
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      await prefs.remove(TimerService.wasWebsocketDisconnectedKey);
      
      final bool wasStoppedByWebSocket = await _timerService.wasStoppedByWebSocket();
      if (wasStoppedByWebSocket) {
        debugPrint('   🧹 Clearing WebSocket disconnect tracking');
      }
      
    } catch (e) {
      debugPrint('❌ Error in WebSocket disconnect recovery: $e');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _handleNormalInitialization(prefs, today);
    }
  }

  Future<void> _handleNormalInitialization(SharedPreferences prefs, String today) async {
    final String? lastDate = prefs.getString(TimerService.lastDateKey);
    
    debugPrint('📅 Normal initialization - Last saved date: $lastDate');
    
    if (lastDate != today) {
      debugPrint('🔄 New day detected! Resetting timer...');
      await _resetTimerForNewDay(prefs, today);
    } else {
      final int savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      final int? lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey);
      
      final int focusSeconds = lastStoredTime != null && savedFocusTime > lastStoredTime 
          ? savedFocusTime 
          : (lastStoredTime ?? savedFocusTime);
      _focusTimeToday = Duration(seconds: focusSeconds);
      
      debugPrint('📊 Loaded focus time: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Saved: ${savedFocusTime}s');
      debugPrint('   - Last stored: ${lastStoredTime ?? savedFocusTime}s');
    }
  }

  Future<void> _resetTimerForNewDay(SharedPreferences prefs, String today) async {
    await prefs.setString(TimerService.lastDateKey, today);
    await prefs.setString(TimerService.heartbeatDateKey, today);
    await prefs.setInt(TimerService.focusKey, 0);
    await prefs.setBool(TimerService.isFocusModeKey, false);
    await prefs.remove(TimerService.focusStartTimeKey);
    await prefs.remove(TimerService.focusElapsedKey);
    await prefs.remove(TimerService.appStateKey);
    await prefs.remove(TimerService.lastHeartbeatKey);
    await prefs.remove(TimerService.lastStoredFocusTimeKey);
    await prefs.remove(TimerService.lastStoredFocusDateKey);
    await prefs.remove(TimerService.websocketDisconnectTimeKey);
    await prefs.remove(TimerService.wasWebsocketDisconnectedKey);
    
    _focusTimeToday = Duration.zero;
    _isRestoredFromDisconnect = false;
    _wasDisconnectedByWebSocket = false;
    debugPrint('✅ Timer reset to 00:00:00 for new day');
  }

  Future<void> _attemptReconnection() async {
    if (_isReconnecting) {
      debugPrint('⏳ Already attempting to reconnect');
      return;
    }
    
    setState(() {
      _isReconnecting = true;
    });

    try {
    
      await WebSocketManager.resetConnectionState();
      await Future.delayed(const Duration(milliseconds: 300));
      
      await WebSocketManager.forceReconnect();
      
      bool connected = false;
      
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        connected = WebSocketManager.isConnected;
        debugPrint('🔍 Connection check ${i + 1}/6: $connected');
        
        if (connected) {
          debugPrint('✅ CONNECTED on attempt ${i + 1}');
          break;
        }
      }
      
      if (mounted) {

        setState(() {
          _isReconnecting = false;
          _initializationFuture = _initializeData();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ RECONNECTION ERROR ❌❌❌');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      
      if (mounted) {

        setState(() => _isReconnecting = false);
      }
    }
  }

  // NEW: Fetch allowed apps from API
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
      
      final response = await http.get(
        url,
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['allowed_apps'] != null) {
          final List<dynamic> allowedAppsList = responseData['allowed_apps'];
          
          final List<String> newAllowedApps = allowedAppsList.map((app) => app.toString()).toList();
          
          if (_debugMode) {
            debugPrint('📱 Received ${newAllowedApps.length} allowed apps from API');
          }
          
          // Since we don't have installed apps here, create basic app data entries
          List<Map<String, dynamic>> appsDetails = [];
          for (var packageName in newAllowedApps) {
            appsDetails.add({
              'appName': packageName,
              'packageName': packageName,
              'versionName': null,
              'systemApp': false,
              'enabled': true,
              'iconBytes': null,
            });
            
            if (_debugMode) {
              debugPrint('📱 App added: $packageName');
            }
          }
          
          await prefs.setStringList(_allowedAppsKey, newAllowedApps);
          await prefs.setString(_allowedAppsDetailsKey, json.encode(appsDetails));
          
          setState(() {
            _allowedAppsPackageNames = newAllowedApps;
          });
          
          if (_debugMode) {
            debugPrint('✅ Allowed apps fetched from API: ${_allowedAppsPackageNames.length} apps');
          }
          
          // Save to overlay
          await _saveAllowedAppsForOverlay(appsDetails);
          
          return;
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

  // NEW: Save allowed apps to overlay
  Future<void> _saveAllowedAppsForOverlay(List<Map<String, dynamic>> apps) async {
    try {
      final List<Map<String, dynamic>> appsData = [];
      
      if (_debugMode) {
        debugPrint('📱 Preparing ${apps.length} apps for overlay at ${DateTime.now()}');
      }
      
      for (var app in apps) {
        String? iconBase64;
        if (app['iconBytes'] != null) {
          try {
            iconBase64 = base64.encode(app['iconBytes']!);
            if (_debugMode && iconBase64.isNotEmpty) {
              debugPrint('📱 App: ${app['appName']}, Icon size: ${iconBase64.length} bytes');
            }
          } catch (e) {
            debugPrint('⚠️ Error encoding icon for ${app['appName']}: $e');
            iconBase64 = null;
          }
        }
        
        appsData.add({
          'appName': app['appName'],
          'packageName': app['packageName'],
          'iconBytes': iconBase64,
          'addedAt': DateTime.now().toIso8601String(),
        });
      }
      
      // Save to overlay service
      final success = await _focusOverlayService.updateAllowedApps(appsData);
      
      if (success) {
        if (_debugMode) {
          debugPrint('✅ Saved ${appsData.length} allowed apps for overlay at ${DateTime.now()}');
        }
      } else {
        debugPrint('❌ Failed to save allowed apps for overlay');
      }
    } catch (e) {
      debugPrint('❌ Error saving allowed apps for overlay: $e');
      if (_debugMode) {
        debugPrint('❌ Stack trace: ${e.toString()}');
      }
    }
  }

  void _startFocusMode() async {
    if (_isStartingFocusMode) return;
    
    setState(() {
      _isStartingFocusMode = true;
    });

    try {
      if (!WebSocketManager.isConnected) {
        await _showWebSocketErrorPopup();
        setState(() {
          _isStartingFocusMode = false;
        });
        return;
      }

      // NEW: Check Usage Access permission before proceeding
      if (!_hasUsageAccessPermission) {
        final bool? shouldOpenSettings = await _showUsageAccessPermissionDialog();
        
        if (shouldOpenSettings == true) {
          await _openUsageAccessSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Re-check permission after returning from settings
          final bool newPermissionStatus = await _checkUsageAccessPermission();
          
          if (newPermissionStatus) {
            setState(() {
              _hasUsageAccessPermission = true;
            });
            // Continue with focus mode start
          } else {
            _showSmallSnackbar(
              message: 'Usage Access permission is still not granted',
              backgroundColor: Colors.orange,
              icon: Icons.warning,
            );
            setState(() {
              _isStartingFocusMode = false;
            });
            return;
          }
        } else {
          setState(() {
            _isStartingFocusMode = false;
          });
          return;
        }
      }

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String today = DateTime.now().toIso8601String().split('T')[0];
      final String? lastDate = prefs.getString(TimerService.lastDateKey);
      
      if (lastDate != today) {
        debugPrint('⚠️ Date changed during start, resetting timer');
        await prefs.setString(TimerService.lastDateKey, today);
        await prefs.setInt(TimerService.focusKey, 0);
        _focusTimeToday = Duration.zero;
        _isRestoredFromDisconnect = false;
        _wasDisconnectedByWebSocket = false;
      }

      await _timerService.initialize();
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      await prefs.remove(TimerService.wasWebsocketDisconnectedKey);
      
      final bool hasPermission = await _timerService.checkOverlayPermission();
      
      if (!hasPermission) {
        final bool? shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final bool newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            // NEW: Fetch allowed apps before starting focus mode
            await _fetchAllowedAppsFromAPI();
            await _actuallyStartFocusMode();
          } else {
            await _showPermissionRequiredPopup();
            setState(() {
              _isStartingFocusMode = false;
            });
            return;
          }
        } else {
          setState(() {
            _isStartingFocusMode = false;
          });
          return;
        }
      } else {
        // NEW: Fetch allowed apps before starting focus mode
        await _fetchAllowedAppsFromAPI();
        await _actuallyStartFocusMode();
      }
    } catch (e) {
      debugPrint('❌ Error starting focus mode: $e');
      
      if (e.toString().contains('Overlay permission required')) {
        final bool? shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final bool newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            // NEW: Fetch allowed apps before starting focus mode
            await _fetchAllowedAppsFromAPI();
            await _actuallyStartFocusMode();
          } else {
            await _showPermissionRequiredPopup();
          }
        }
      } else if (e.toString().contains('WebSocket connection required')) {
        await _showWebSocketErrorPopup();
      } else {
        _showSmallSnackbar(
          message: 'Error starting focus mode',
          backgroundColor: Colors.red,
          icon: Icons.error,
        );
      }
      
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  Future<void> _showWebSocketErrorPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.red, size: 20),
              SizedBox(width: 6),
              Text('Connection Error', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unable to start Focus Mode. The app is not connected to the server.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 8),
              Text(
                'Check your internet connection and try again.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _attemptReconnection();
                
                if (WebSocketManager.isConnected) {
                  await Future.delayed(const Duration(milliseconds: 300));
                  await _actuallyStartFocusMode();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('RETRY', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  // Enhanced permission required popup
  Future<void> _showPermissionRequiredPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 20),
              SizedBox(width: 6),
              Text('Permission Required', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Focus Mode requires "Display over other apps" permission to work properly.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
                ),
                child: const Text(
                  'Without this permission, the app cannot block other applications during focus sessions.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _isStartingFocusMode = false;
                });
              },
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
                // Permission will be refreshed automatically via didChangeAppLifecycleState
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _actuallyStartFocusMode() async {
    try {
      debugPrint('🚀 Starting focus mode with current time: ${_focusTimeToday.inSeconds}s');
      
      _timerService.focusTimeToday.value = _focusTimeToday;
      await _timerService.startFocusMode();
      
      debugPrint('✅ Focus mode started, navigating to home');
      
      _sendFocusStartEvent();
      
      // Navigate immediately without waiting for API calls to complete
      if (mounted) {
        await Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (Route<dynamic> route) => false,
          arguments: {'isFocusMode': true}
        );
      }
      
    } catch (e) {
      debugPrint('❌ Error in actuallyStartFocusMode: $e');
      _showSmallSnackbar(
        message: 'Error starting focus mode',
        backgroundColor: Colors.red,
        icon: Icons.error,
      );
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  void _sendFocusStartEvent() {
    try {
      WebSocketManager.send({"event": "focus_start"});
      debugPrint('📤 WebSocket event sent: {"event": "focus_start"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_start event: $e');
      
      try {
        WebSocketManager.connect();
        debugPrint('🔄 Attempting to reconnect WebSocket...');
        
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            WebSocketManager.send({"event": "focus_start"});
            debugPrint('📤 Retry: WebSocket event sent: {"event": "focus_start"}');
          } catch (retryError) {
            debugPrint('❌ Retry failed: $retryError');
          }
        });
      } catch (connectError) {
        debugPrint('❌ WebSocket reconnection failed: $connectError');
      }
    }
  }

  // ============== LOGOUT FUNCTIONALITY ==============
  
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.red, size: 20),
              SizedBox(width: 6),
              Text('Confirm Logout', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: const Text(
            'Are you sure you want to logout? This will stop any active focus mode timer.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
  String? accessToken;
  
  try {
    setState(() {
      _isLoggingOut = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Logging out...', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );

    debugPrint('🔴 STEP 1: Shutting down TimerService...');
    try {
      final timerService = TimerService();
      await timerService.shutdownForLogout();
      debugPrint('✅ TimerService shutdown complete');
    } catch (e) {
      debugPrint('❌ Error shutting down TimerService: $e');
    }
    
    await Future.delayed(const Duration(seconds: 1));
    
    debugPrint('🔴 STEP 2: Cancelling background tasks...');
    try {
      await Workmanager().cancelAll();
      debugPrint('✅ Background tasks cancelled');
    } catch (e) {
      debugPrint('❌ Error cancelling background tasks: $e');
    }
    
    debugPrint('🔴 STEP 3: Hiding all overlays...');
    await _hideAllOverlaysWithRetries();
    
    debugPrint('🔴 STEP 4: Disconnecting WebSocket...');
    try {
      _sendFocusEndEvent();
      await Future.delayed(const Duration(milliseconds: 300));
      
      final disconnectFuture = WebSocketManager.forceDisconnect();
      final timeoutFuture = Future.delayed(const Duration(seconds: 2));
      await Future.any([disconnectFuture, timeoutFuture]);
      
      debugPrint('✅ WebSocket disconnected');
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('⚠️ Error during WebSocket disconnect: $e');
    }
    
    debugPrint('🔴 STEP 5: Sending attendance...');
    accessToken = await _authService.getAccessToken();
    String endTime = DateTime.now().toIso8601String();
    await _sendAttendanceData(accessToken, endTime);
    
    debugPrint('🔴 STEP 6: Calling logout API...');
    final client = _createHttpClientWithCustomCert();
    
    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.currentBaseUrl}/api/students/student_logout/'),
        headers: {
          ...ApiConfig.commonHeaders,
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 8));

      debugPrint('Logout response status: ${response.statusCode}');
    } finally {
      client.close();
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    debugPrint('🔴 STEP 7: CLEARING SHARED PREFERENCES...');
    await _clearAllSharedPreferences();
    
    debugPrint('🔴 STEP 8: Final cleanup...');
    await _clearOverlayFlags();
    await _clearLogoutData();
    
    await Future.delayed(const Duration(milliseconds: 300));
    await _hideAllOverlaysWithRetries();
    
  } catch (e) {
    debugPrint('❌ Logout error: $e');
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    
    try {
      await Workmanager().cancelAll();
      await WebSocketManager.forceDisconnect();
      await _hideAllOverlaysWithRetries();
      await _clearOverlayFlags();
      await _clearAllSharedPreferences(); // Also clear on error
    } catch (_) {}
    
    await _clearLogoutData();
    
  } finally {
    setState(() {
      _isLoggingOut = false;
    });
    
    try {
      await Workmanager().cancelAll();
      await WebSocketManager.forceDisconnect();
      await _hideAllOverlaysWithRetries();
      await _clearOverlayFlags();
      await _clearAllSharedPreferences(); // Clear in finally block too
    } catch (_) {}
  }
}

// NEW METHOD: Clear all SharedPreferences data including allowed apps
Future<void> _clearAllSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Clear allowed apps data (from AllowAppsScreen)
    await prefs.remove('allowed_apps_list');
    await prefs.remove('allowed_apps_details');
    
    // Clear authentication tokens
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('accessToken'); // If stored with different key
    await prefs.remove('auth_token');
    
    // Clear user data
    await prefs.remove('user_id');
    await prefs.remove('student_id');
    await prefs.remove('user_data');
    await prefs.remove('student_data');
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    
    // Clear session data
    await prefs.remove('last_login');
    await prefs.remove('session_expiry');
    await prefs.remove('login_time');
    
    // Clear focus mode/study session data
    await prefs.remove('focus_mode_active');
    await prefs.remove('study_session_start');
    await prefs.remove('study_session_data');
    await prefs.remove('current_subject');
    await prefs.remove('current_topic');
    
    // Clear timetable cache if exists
    await prefs.remove('timetable_cache');
    await prefs.remove('last_timetable_fetch');
    
    // Clear any overlay/focus related data
    await prefs.remove('overlay_active');
    await prefs.remove('allowed_apps_last_updated');
    await prefs.remove('last_allowed_apps_sync');
    
    // Clear app-specific settings that should reset on logout
    await prefs.remove('notifications_enabled');
    await prefs.remove('study_reminders');
    await prefs.remove('auto_attendance');
    
    debugPrint('✅ All SharedPreferences cleared (including allowed apps)');
  } catch (e) {
    debugPrint('❌ Error clearing SharedPreferences: $e');
  }
}

Future<void> _clearAllPreferencesCompletely() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // This will remove EVERYTHING
    debugPrint('✅ All SharedPreferences cleared completely');
  } catch (e) {
    debugPrint('❌ Error clearing all preferences: $e');
  }
}

  Future<void> _hideAllOverlaysWithRetries() async {
    debugPrint('🎯 Hiding all overlays with retries...');
    
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint('🔄 Overlay hide attempt $attempt/3');
        
        try {
          final focusModeService = FocusModeOverlayService();
          await focusModeService.hideOverlay();
          debugPrint('✅ FocusModeOverlayService: Hidden');
        } catch (e) {
          debugPrint('⚠️ FocusModeOverlayService error: $e');
        }
        
        try {
          final overlayManager = FocusOverlayManager();
          await overlayManager.initialize();
          await overlayManager.hideOverlay();
          debugPrint('✅ FocusOverlayManager: Hidden');
        } catch (e) {
          debugPrint('⚠️ FocusOverlayManager error: $e');
        }
        
        try {
          const platform = MethodChannel('focus_mode_overlay_channel');
          await platform.invokeMethod('hideOverlay');
          await Future.delayed(const Duration(milliseconds: 100));
          
          try {
            await platform.invokeMethod('forceHideOverlay');
          } catch (_) {}
          
          debugPrint('✅ Direct method channel: Hidden');
        } catch (e) {
          debugPrint('⚠️ Direct method channel error: $e');
        }
        
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
        
      } catch (e) {
        debugPrint('⚠️ Attempt $attempt error: $e');
      }
    }
    
    debugPrint('✅ All overlay hide attempts completed');
  }

  void _sendFocusEndEvent() {
    try {
      WebSocketManager.send({"event": "focus_end"});
      debugPrint('📤 WebSocket event sent: {"event": "focus_end"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_end event: $e');
      
      try {
        WebSocketManager.connect();
        debugPrint('🔄 Attempting to reconnect WebSocket...');
        
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            WebSocketManager.send({"event": "focus_end"});
            debugPrint('📤 Retry: WebSocket event sent: {"event": "focus_end"}');
          } catch (retryError) {
            debugPrint('❌ Retry failed: $retryError');
          }
        });
      } catch (connectError) {
        debugPrint('❌ WebSocket reconnection failed: $connectError');
      }
    }
  }

  Future<void> _clearOverlayFlags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setBool('is_focus_mode', false);
      await prefs.remove('focus_mode_start_time');
      await prefs.remove('focus_time_today');
      await prefs.remove('focus_elapsed_time');
      await prefs.remove('overlay_visible');
      await prefs.remove('overlay_permission_granted');
      
      debugPrint('✅ Overlay flags cleared');
    } catch (e) {
      debugPrint('❌ Error clearing overlay flags: $e');
    }
  }

  Future<void> _sendAttendanceData(String? accessToken, String endTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final studentType = prefs.getString('profile_student_type') ?? '';
      final bool isOnlineStudent = studentType.toUpperCase() == 'ONLINE';
      
      if (!isOnlineStudent) {
        debugPrint('🎯 Skipping attendance data for non-online student');
        return;
      }
      
      String? startTime = prefs.getString('start_time');

      if (startTime != null && accessToken != null && accessToken.isNotEmpty) {
        String cleanStart = startTime.split('.')[0].replaceFirst('T', ' ');
        String cleanEnd = endTime.split('.')[0].replaceFirst('T', ' ');

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
          ).timeout(const Duration(seconds: 8));

          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('✅ Attendance sent successfully');
          } else {
            debugPrint('⚠️ Error sending attendance: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('❌ Exception while sending attendance: $e');
        }
      } else {
        debugPrint('⚠️ Missing attendance data');
      }
    } catch (e) {
      debugPrint('❌ Error in _sendAttendanceData: $e');
    }
  }

  Future<void> _clearLogoutData() async {
    try {
      WebSocketManager.logConnectionState();
      
      await _authService.logout();
      await _clearCachedProfileData();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('start_time');
      await prefs.remove('end_time');
      await prefs.remove('last_active_time');
      
      await prefs.remove('is_focus_mode');
      await prefs.remove('focus_mode_start_time');
      await prefs.remove('focus_time_today');
      
      debugPrint('🗑️ SharedPreferences data cleared');
      
      WebSocketManager.logConnectionState();

      if (mounted) {
        _showSmallSnackbar(
          message: 'Logged out successfully!',
          backgroundColor: Colors.green,
          icon: Icons.check_circle,
        );
        
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Error in _clearLogoutData: $e');
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signup',
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  Future<void> _clearCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final profileKeys = [
        'profile_name',
        'profile_email',
        'profile_phone',
        'profile_course',
        'profile_subcourse',
        'profile_student_type',
        'profile_completed',
        'profile_cache_time',
        'fcm_token',
        'device_token_registered',
        'subjects_data',
        'cached_subcourse_id',
        'first_login_subjects_fetched',
        'unread_notifications',
        'device_registered_for_session',
      ];
      
      for (String key in profileKeys) {
        await prefs.remove(key);
      }
      
      debugPrint('✅ Cached profile data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing cached profile data: $e');
    }
  }

  http.Client _createHttpClientWithCustomCert() {
    final client = ApiConfig.createHttpClient();
    return IOClient(client);
  }

  // NEW: Helper method to determine button text
  String _getStartButtonText() {
    if (!WebSocketManager.isConnected) return 'Connection Required';
    if (!_hasOverlayPermission) return 'Display Permission Required';
    if (!_hasUsageAccessPermission) return 'Usage Access Required';
    return 'Start Focus Session';
  }

  @override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final screenWidth = MediaQuery.of(context).size.width;
  final isSmallScreen = screenHeight < 700;

  return WillPopScope(
    onWillPop: () async {
      final shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.exit_to_app, color: Colors.orange, size: 20),
                SizedBox(width: 6),
                Text('Exit App', style: TextStyle(fontSize: 15)),
              ],
            ),
            content: const Text(
              'Are you sure you want to exit the application?',
              style: TextStyle(fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('EXIT', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          );
        },
      );
      
      if (shouldExit == true) {
        if (Platform.isAndroid) {
          SystemNavigator.pop();
        } else if (Platform.isIOS) {
          exit(0);
        }
      }
      
      return false;
    },
    child: Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: FutureBuilder<Duration>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF43E97B)),
                ),
              ),
            );
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline, size: 36, color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Failed to Initialize',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString().length > 60 
                          ? '${snapshot.error.toString().substring(0, 60)}...' 
                          : snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initializationFuture = _initializeData();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43E97B),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Get the focus time from snapshot
          final Duration focusTime = snapshot.data ?? Duration.zero;
          
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Header with Logout Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: _isLoggingOut 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.logout_rounded, size: 20),
                              onPressed: _isLoggingOut ? null : _showLogoutDialog,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              tooltip: 'Logout',
                              color: Colors.grey[700],
                            ),
                            const Spacer(),
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: isSmallScreen ? 70 : 80,
                                height: isSmallScreen ? 70 : 80,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF43E97B).withOpacity(0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.psychology_rounded, size: isSmallScreen ? 35 : 40, color: Colors.white),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 40),
                          ],
                        ),
                        
                        SizedBox(height: isSmallScreen ? 8 : 12),
                        
                        const Text(
                          'Focus Mode',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        
                        const SizedBox(height: 4),
                        
                        Text(
                          _hasOverlayPermission && _hasUsageAccessPermission 
                              ? 'Ready to boost productivity' 
                              : 'Grant permissions to start',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                        
                        SizedBox(height: isSmallScreen ? 12 : 16),
                    
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Timer Display
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(0xFF43E97B).withOpacity(0.08),
                                      const Color(0xFF38F9D7).withOpacity(0.08),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF43E97B).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Icon(Icons.timer_rounded, color: Color(0xFF43E97B), size: 16),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Today\'s Focus Time',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _formatDuration(focusTime), 
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF43E97B),
                                        fontFamily: 'monospace',
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    if (_isRestoredFromDisconnect) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.restore, size: 10, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Restored from last session',
                                              style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Overlay Permission Status - MODIFIED: Clickable
                              GestureDetector(
                                onTap: () async {
                                  if (!_hasOverlayPermission && !_isRefreshingPermissions) {
                                    final bool? shouldOpenSettings = await _showPermissionPopup();
                                    if (shouldOpenSettings == true) {
                                      await openAppSettings();
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _hasOverlayPermission ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _hasOverlayPermission ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      _isRefreshingPermissions
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                              ),
                                            )
                                          : Icon(
                                              _hasOverlayPermission ? Icons.check_circle_rounded : Icons.info_rounded,
                                              color: _hasOverlayPermission ? Colors.green : Colors.orange,
                                              size: 18,
                                            ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _hasOverlayPermission ? 'Display Over Apps Enabled' : 'Display Permission Required',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _hasOverlayPermission ? Colors.green[700] : Colors.orange[700],
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              _hasOverlayPermission ? 'Can show overlay on other apps' : 'Tap to enable overlay permission',
                                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!_hasOverlayPermission && !_isRefreshingPermissions) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Enable',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              
                              // Usage Access Permission Status - MODIFIED: Clickable
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () async {
                                  if (!_hasUsageAccessPermission && !_isRefreshingPermissions) {
                                    final bool? shouldOpenSettings = await _showUsageAccessPermissionDialog();
                                    if (shouldOpenSettings == true) {
                                      await _openUsageAccessSettings();
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _hasUsageAccessPermission ? Colors.green.withOpacity(0.08) : Colors.blue.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _hasUsageAccessPermission ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      _isRefreshingPermissions
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                              ),
                                            )
                                          : Icon(
                                              _hasUsageAccessPermission ? Icons.check_circle_rounded : Icons.analytics,
                                              color: _hasUsageAccessPermission ? Colors.green : Colors.blue,
                                              size: 18,
                                            ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _hasUsageAccessPermission ? 'Usage Access Enabled' : 'Usage Access Required',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _hasUsageAccessPermission ? Colors.green[700] : Colors.blue[700],
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              _hasUsageAccessPermission 
                                                  ? 'Can monitor app usage for blocking' 
                                                  : 'Tap to enable usage access permission',
                                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!_hasUsageAccessPermission && !_isRefreshingPermissions) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Enable',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              
                              // WebSocket Connection Status
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: WebSocketManager.isConnected 
                                      ? Colors.green.withOpacity(0.08) 
                                      : Colors.orange.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: WebSocketManager.isConnected 
                                        ? Colors.green.withOpacity(0.2) 
                                        : Colors.orange.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      WebSocketManager.isConnected ? Icons.wifi : Icons.wifi_off,
                                      color: WebSocketManager.isConnected ? Colors.green : Colors.orange,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            WebSocketManager.isConnected ? 'Server Connected' : 'Server Disconnected',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: WebSocketManager.isConnected ? Colors.green[700] : Colors.orange[700],
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            WebSocketManager.isConnected 
                                                ? 'Ready for focus sessions' 
                                                : 'Focus mode requires connection',
                                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!WebSocketManager.isConnected) ...[
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: _isReconnecting ? null : _attemptReconnection,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _isReconnecting ? Colors.grey : const Color(0xFF43E97B),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: _isReconnecting
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 1.5,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  'Reconnect',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: isSmallScreen ? 20 : 28),
                        
                        // Features Grid (Compact)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'What You Get',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 10),
                              _buildFeatureItem(
                                icon: Icons.block_rounded,
                                title: 'App Blocking',
                                description: 'Block distracting apps',
                                color: const Color(0xFF43E97B),
                                isSmallScreen: isSmallScreen,
                              ),
                              const SizedBox(height: 8),
                              _buildFeatureItem(
                                icon: Icons.analytics_rounded,
                                title: 'Time Tracking',
                                description: 'Monitor focus sessions',
                                color: const Color(0xFF38F9D7),
                                isSmallScreen: isSmallScreen,
                              ),
                              const SizedBox(height: 8),
                              _buildFeatureItem(
                                icon: Icons.trending_up_rounded,
                                title: 'Productivity Boost',
                                description: 'Stay focused, achieve more',
                                color: const Color(0xFFF4B400),
                                isSmallScreen: isSmallScreen,
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20), 
                        
                        // Start Button - Modified to check all permissions
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (!_isStartingFocusMode && 
                                       !_isReconnecting && 
                                       WebSocketManager.isConnected &&
                                       _hasOverlayPermission &&
                                       _hasUsageAccessPermission) 
                                ? _startFocusMode 
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (WebSocketManager.isConnected && 
                                              _hasOverlayPermission && 
                                              _hasUsageAccessPermission)
                                  ? const Color(0xFF43E97B) 
                                  : Colors.grey[400],
                              disabledBackgroundColor: Colors.grey[300],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: (_isStartingFocusMode || _isReconnecting) ? 0 : 4,
                              shadowColor: (WebSocketManager.isConnected && 
                                          _hasOverlayPermission && 
                                          _hasUsageAccessPermission)
                                  ? const Color(0xFF43E97B).withOpacity(0.3) 
                                  : Colors.grey,
                            ),
                            child: (_isStartingFocusMode || _isReconnecting)
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(
                                            (WebSocketManager.isConnected && 
                                             _hasOverlayPermission && 
                                             _hasUsageAccessPermission) ? 0.2 : 0.1
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          (WebSocketManager.isConnected && 
                                           _hasOverlayPermission && 
                                           _hasUsageAccessPermission) 
                                              ? Icons.play_arrow_rounded 
                                              : Icons.warning,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getStartButtonText(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 8), 
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isSmallScreen,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final String hours = duration.inHours.toString().padLeft(2, '0');
    final String minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    _websocketConnectionSubscription?.cancel();
    _reconnectionCheckTimer?.cancel();
    _timerService.setWebSocketDisconnectCallback(() {});
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}