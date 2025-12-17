import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';

class FocusModeOverlayService {
  static final FocusModeOverlayService _instance = FocusModeOverlayService._internal();
  factory FocusModeOverlayService() => _instance;
  FocusModeOverlayService._internal();

  // Channel for platform-specific overlay implementation
  static const platform = MethodChannel('focus_mode_overlay_channel');
  static FocusModeOverlayService get instance => _instance;
  
  // Stream controllers for overlay events
  final StreamController<bool> _overlayVisibilityController = StreamController<bool>.broadcast();
  final StreamController<void> _returnToStudyController = StreamController<void>.broadcast();
  final StreamController<Map<String, dynamic>> _appLaunchController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<bool> get overlayVisibilityStream => _overlayVisibilityController.stream;
  Stream<void> get returnToStudyStream => _returnToStudyController.stream;
  Stream<Map<String, dynamic>> get appLaunchStream => _appLaunchController.stream;
  
  bool _isOverlayVisible = false;
  bool get isOverlayVisible => _isOverlayVisible;
  
  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;
  
  List<Map<String, dynamic>> _allowedApps = [];
  List<Map<String, dynamic>> get allowedApps => _allowedApps;
  
  // SharedPreferences keys
  static const String _allowedAppsOverlayKey = 'overlay_allowed_apps';
  static const String _mainAllowedAppsKey = 'allowed_apps_list'; // 🆕 Main allowed apps key
  
  // Check if overlay permission is granted
  Future<bool> checkOverlayPermission() async {
    try {
      if (await Permission.systemAlertWindow.isGranted) {
        _hasPermission = true;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }
  
  // Request overlay permission
  Future<bool> requestOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.request();
      _hasPermission = status.isGranted;
      
      if (_hasPermission) {
        debugPrint('✅ Overlay permission granted');
        return true;
      } else {
        debugPrint('❌ Overlay permission denied');
        return false;
      }
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
      return false;
    }
  }
  
  // Update allowed apps list
  Future<bool> updateAllowedApps(List<Map<String, dynamic>> apps) async {
    try {
      debugPrint('📱 Updating allowed apps in overlay service: ${apps.length} apps');
      
      _allowedApps = apps;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_allowedAppsOverlayKey, json.encode(apps));
      
      // Also send to Android platform for immediate use
      try {
        final result = await platform.invokeMethod('updateAllowedApps', {
          'apps': json.encode(apps),
        });
        
        debugPrint('📱 Platform update result: $result');
      } on PlatformException catch (e) {
        debugPrint('⚠️ Could not update platform, but saved locally: ${e.message}');
      }
      
      debugPrint('✅ Updated overlay allowed apps: ${apps.length} apps');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating allowed apps: $e');
      return false;
    }
  }
  
  // 🆕 NEW: Refresh allowed apps in overlay
  Future<bool> refreshAllowedAppsInOverlay() async {
    try {
      debugPrint('🔄 Refreshing allowed apps in overlay');
      
      final result = await platform.invokeMethod('refreshAllowedAppsInOverlay');
      
      debugPrint('📱 Refresh result: $result');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('❌ Platform exception refreshing apps: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ Error refreshing allowed apps in overlay: $e');
      return false;
    }
  }
  
  // 🆕 NEW: Get allowed apps from platform
  Future<List<Map<String, dynamic>>> getAllowedApps() async {
    try {
      debugPrint('📱 Getting allowed apps from platform...');
      
      // First, try to get from platform
      final result = await platform.invokeMethod('getAllowedApps');
      
      if (result != null) {
        try {
          final List<dynamic> appsList = json.decode(result.toString());
          final List<Map<String, dynamic>> platformApps = appsList.map((app) => 
            app as Map<String, dynamic>).toList();
          
          debugPrint('📱 Retrieved ${platformApps.length} apps from platform');
          return platformApps;
        } catch (e) {
          debugPrint('⚠️ Error parsing platform apps: $e');
        }
      }
      
      // If platform fails, return from local cache
      debugPrint('📱 Returning ${_allowedApps.length} apps from local cache');
      return _allowedApps;
    } on PlatformException catch (e) {
      debugPrint('❌ Platform exception in getAllowedApps: ${e.message}');
      return _allowedApps;
    } catch (e) {
      debugPrint('❌ Error in getAllowedApps: $e');
      return _allowedApps;
    }
  }

  // 🆕 UPDATED: Handle app permission updates from WebSocket
  Future<void> handleAppPermissionUpdate(String packageName, bool isAllowed) async {
    try {
      debugPrint('🔥 [GLOBAL] Handling app permission update for overlay: $packageName -> allowed: $isAllowed');
      
      // Get current allowed apps
      await loadAllowedApps();
      
      if (isAllowed) {
        // Check if app is already in allowed list
        final existingApp = _allowedApps.firstWhere(
          (app) => app['packageName'] == packageName,
          orElse: () => {},
        );
        
        if (existingApp.isEmpty) {
          String appName = _getReadableAppName(packageName);
          String? iconBase64;
          
          // Try to get app details if possible
          try {
            final app = await DeviceApps.getApp(packageName);
            
            if (app is Application) {
              appName = app.appName ?? appName;
              
              if (app is ApplicationWithIcon) {
                try {
                  final iconBytes = app.icon;
                  if (iconBytes != null) {
                    iconBase64 = base64.encode(iconBytes);
                  }
                } catch (e) {
                  debugPrint('⚠️ Could not encode icon for $packageName: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ Could not get app details for $packageName: $e');
          }
          
          // Add to allowed apps
          final newApp = {
            'appName': appName,
            'packageName': packageName,
            'iconBytes': iconBase64,
            'addedFromWebSocket': true,
            'timestamp': DateTime.now().toIso8601String(),
          };
          
          _allowedApps.add(newApp);
          debugPrint('✅ [GLOBAL] Added $appName ($packageName) to overlay allowed apps');
          
        } else {
          debugPrint('⚠️ [GLOBAL] App $packageName already in allowed apps');
        }
      } else {
        // 🆕 CRITICAL: Remove app from allowed list when allowed: false
        final initialCount = _allowedApps.length;
        _allowedApps.removeWhere((app) => app['packageName'] == packageName);
        
        if (_allowedApps.length < initialCount) {
          debugPrint('❌ [GLOBAL] Removed $packageName from overlay allowed apps');
        } else {
          debugPrint('⚠️ [GLOBAL] App $packageName not found in allowed apps');
        }
      }
      
      // 🔥 CRITICAL: Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_allowedAppsOverlayKey, json.encode(_allowedApps));
      
      // 🆕 Also update main allowed apps list
      await _updateMainAllowedAppsList(packageName, isAllowed);
      
      // 🔥 CRITICAL: Update platform immediately
      await _updatePlatformImmediately();
      
      // 🔥 CRITICAL: Refresh overlay if visible
      if (_isOverlayVisible) {
        await refreshAllowedAppsInOverlay();
        debugPrint('🔄 [GLOBAL] Overlay refreshed in real-time');
      }
      
    } catch (e) {
      debugPrint('❌ [GLOBAL] Error handling app permission update: $e');
      debugPrint('❌ Stack trace: ${e.toString()}');
    }
  }

  // 🆕 NEW: Update main allowed apps list in SharedPreferences
  Future<void> _updateMainAllowedAppsList(String packageName, bool isAllowed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAllowedApps = prefs.getStringList(_mainAllowedAppsKey) ?? [];
      
      if (isAllowed) {
        // Add if not already present
        if (!savedAllowedApps.contains(packageName)) {
          savedAllowedApps.add(packageName);
          await prefs.setStringList(_mainAllowedAppsKey, savedAllowedApps);
          debugPrint('✅ Updated main allowed apps list: Added $packageName');
        }
      } else {
        // Remove if present
        if (savedAllowedApps.contains(packageName)) {
          savedAllowedApps.remove(packageName);
          await prefs.setStringList(_mainAllowedAppsKey, savedAllowedApps);
          debugPrint('✅ Updated main allowed apps list: Removed $packageName');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error updating main allowed apps list: $e');
    }
  }

  // 🆕 NEW: Immediate platform update with better error handling
  Future<void> _updatePlatformImmediately() async {
    try {
      debugPrint('🔥 [GLOBAL] Updating platform immediately with ${_allowedApps.length} apps');
      
      if (_allowedApps.isEmpty) {
        debugPrint('📱 No apps to update, sending empty list');
      }
      
      final result = await platform.invokeMethod('updateAllowedApps', {
        'apps': json.encode(_allowedApps),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isImmediateUpdate': true,
      });
      
      if (result == true) {
        debugPrint('✅ [GLOBAL] Platform updated successfully');
      } else {
        debugPrint('⚠️ [GLOBAL] Platform update returned: $result');
        
        // Try alternative method
        try {
          await platform.invokeMethod('setAllowedApps', {
            'apps': json.encode(_allowedApps),
          });
          debugPrint('✅ Used alternative setAllowedApps method');
        } catch (e) {
          debugPrint('⚠️ Alternative method also failed: $e');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('❌ [GLOBAL] Platform exception: ${e.message}');
      debugPrint('❌ Platform details: ${e.details}');
      
      // Try to recover by reloading and retrying
      if (e.message?.contains('overlay') == true) {
        debugPrint('🔄 Attempting to recover from overlay error...');
        await Future.delayed(Duration(milliseconds: 300));
        await loadAllowedApps(); // Reload
      }
    } catch (e) {
      debugPrint('❌ [GLOBAL] Error updating platform: $e');
    }
  }

  // 🆕 NEW: Force immediate overlay refresh with current data
  Future<void> forceRefreshOverlay() async {
    try {
      debugPrint('🔥 [GLOBAL] Force refreshing overlay');
      
      // First ensure we have latest data
      await loadAllowedApps();
      
      // Update platform
      await _updatePlatformImmediately();
      
      // Refresh overlay UI if visible
      if (_isOverlayVisible) {
        await refreshAllowedAppsInOverlay();
      }
      
      debugPrint('✅ [GLOBAL] Overlay force refreshed');
    } catch (e) {
      debugPrint('❌ [GLOBAL] Error force refreshing overlay: $e');
    }
  }
  
  // Helper to convert package name to readable app name
  String _getReadableAppName(String packageName) {
    // Common app package names mapping
    final appNameMap = {
      'com.whatsapp': 'WhatsApp',
      'com.instagram.android': 'Instagram',
      'com.facebook.katana': 'Facebook',
      'com.google.android.youtube': 'YouTube',
      'com.google.android.gm': 'Gmail',
      'com.android.chrome': 'Chrome',
      'com.google.android.apps.maps': 'Google Maps',
      'com.android.vending': 'Google Play Store',
      'com.google.android.apps.photos': 'Google Photos',
      'com.google.android.calendar': 'Google Calendar',
      'com.google.android.contacts': 'Contacts',
      'com.android.dialer': 'Phone',
      'com.android.mms': 'Messages',
      'com.android.camera2': 'Camera',
      'com.android.gallery3d': 'Gallery',
      'com.google.android.apps.docs': 'Google Docs',
      'com.google.android.apps.messaging': 'Messages',
      'com.android.email': 'Email',
      'com.android.calculator2': 'Calculator',
      'com.android.settings': 'Settings',
    };
    
    // Check if package exists in map
    if (appNameMap.containsKey(packageName)) {
      return appNameMap[packageName]!;
    }
    
    // Try to extract and format the last part of package name
    try {
      final parts = packageName.split('.');
      if (parts.isNotEmpty) {
        String lastPart = parts.last;
        
        // Clean up the name
        lastPart = lastPart
            .replaceAll('_', ' ')
            .replaceAll('-', ' ');
        
        // Convert to title case
        if (lastPart.isNotEmpty) {
          return lastPart.split(' ').map((word) {
            if (word.isEmpty) return '';
            return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
          }).join(' ');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error formatting app name for $packageName: $e');
    }
    
    // Final fallback: return the original package name
    return packageName;
  }
  
  // 🆕 NEW: Clear allowed apps
  Future<bool> clearAllowedApps() async {
    try {
      debugPrint('🗑️ Clearing allowed apps in overlay service');
      
      _allowedApps = [];
      
      // Clear from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_allowedAppsOverlayKey);
      
      // Also clear from Android platform
      try {
        await platform.invokeMethod('clearAllowedApps');
      } on PlatformException catch (e) {
        debugPrint('⚠️ Could not clear platform apps: ${e.message}');
      }
      
      debugPrint('✅ Cleared overlay allowed apps');
      return true;
    } catch (e) {
      debugPrint('❌ Error clearing allowed apps: $e');
      return false;
    }
  }
  
  // Load allowed apps from SharedPreferences
  Future<void> loadAllowedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAppsJson = prefs.getString(_allowedAppsOverlayKey) ?? '[]';
      final List<dynamic> appsList = json.decode(savedAppsJson);
      
      _allowedApps = appsList.map((app) => app as Map<String, dynamic>).toList();
      debugPrint('✅ Loaded ${_allowedApps.length} allowed apps for overlay from SharedPreferences');
      
      // Also send to platform after loading
      if (_allowedApps.isNotEmpty) {
        try {
          await platform.invokeMethod('updateAllowedApps', {
            'apps': savedAppsJson,
          });
          debugPrint('📱 Sent loaded apps to platform');
        } on PlatformException catch (e) {
          debugPrint('⚠️ Could not send loaded apps to platform: ${e.message}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading allowed apps: $e');
    }
  }
  
  // Show overlay (blocks app exit)
  Future<void> showOverlay({String? message}) async {
    try {
      if (!_hasPermission && !await checkOverlayPermission()) {
        debugPrint('Cannot show overlay - permission not granted');
        return;
      }
      
      final result = await platform.invokeMethod('showOverlay', {
        'message': message ?? 'You are in focus mode, focus on studies',
      });
      
      if (result == true) {
        _isOverlayVisible = true;
        _overlayVisibilityController.add(true);
        debugPrint('✅ Focus mode overlay shown');
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to show overlay: ${e.message}');
    }
  }
  
  // Hide overlay
  Future<void> hideOverlay() async {
    try {
      if (_isOverlayVisible) {
        final result = await platform.invokeMethod('hideOverlay');
        
        if (result == true) {
          _isOverlayVisible = false;
          _overlayVisibilityController.add(false);
          debugPrint('✅ Focus mode overlay hidden');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to hide overlay: ${e.message}');
    }
  }
  
  // Force hide overlay (aggressive cleanup)
  Future<bool> forceHideOverlay() async {
    try {
      debugPrint('🔴 Force hiding overlay');
      
      final result = await platform.invokeMethod('forceHideOverlay');
      
      if (result == true) {
        _isOverlayVisible = false;
        _overlayVisibilityController.add(false);
        debugPrint('✅ Focus mode overlay force hidden');
      }
      
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to force hide overlay: ${e.message}');
      return false;
    }
  }
  
  // Check if overlay is currently showing
  Future<bool> isOverlayShowing() async {
    try {
      final result = await platform.invokeMethod('isOverlayShowing');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Error checking overlay status: ${e.message}');
      return _isOverlayVisible;
    }
  }
  
  // Show permission dialog with explanation
  Future<bool> showPermissionDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Focus Mode Requires Permission',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable the Focus Mode feature that prevents distractions, '
                'we need permission to display an overlay screen over other apps.\n\n'
                'This will allow the app to:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildPermissionItem('• Show a reminder when you try to leave the app'),
              _buildPermissionItem('• Block navigation to other apps during study'),
              _buildPermissionItem('• Help you stay focused on your studies'),
              const SizedBox(height: 12),
              const Text(
                'This permission is essential for the Focus Mode to work properly.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'DENY',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(true);
              },
              child: const Text(
                'ALLOW PERMISSION',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        );
      },
    ) ?? false;
  }
  
  Widget _buildPermissionItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
  
  // Initialize the overlay service
  Future<void> initialize() async {
    try {
      // Check permission status
      _hasPermission = await checkOverlayPermission();
      
      // Load allowed apps
      await loadAllowedApps();
      
      // Set up method call handlers
      platform.setMethodCallHandler((call) async {
        debugPrint('📱 Method call received: ${call.method}');
        
        switch (call.method) {
          case 'onReturnToStudy':
            _returnToStudyController.add(null);
            return true;
          case 'onOverlayShown':
            _isOverlayVisible = true;
            _overlayVisibilityController.add(true);
            return true;
          case 'onOverlayHidden':
            _isOverlayVisible = false;
            _overlayVisibilityController.add(false);
            return true;
          case 'onAppLaunch':
            try {
              final appData = call.arguments as Map<dynamic, dynamic>;
              final Map<String, dynamic> convertedData = {
                'appName': appData['appName']?.toString() ?? 'Unknown App',
                'packageName': appData['packageName']?.toString() ?? '',
              };
              _appLaunchController.add(convertedData);
              debugPrint('🎯 App launch requested from overlay: ${convertedData['packageName']}');
            } catch (e) {
              debugPrint('❌ Error parsing app launch data: $e');
            }
            return true;
          case 'onPermissionRequired':
            debugPrint('🔒 Overlay permission required');
            return true;
          case 'onOverlayError':
            debugPrint('❌ Overlay error: ${call.arguments}');
            return true;
        }
        return null;
      });
      
      debugPrint('✅ FocusModeOverlayService initialized');
      debugPrint('   - Permission granted: $_hasPermission');
      debugPrint('   - Allowed apps loaded: ${_allowedApps.length}');
    } catch (e) {
      debugPrint('❌ Error initializing FocusModeOverlayService: $e');
    }
  }
  
  // Dispose resources
  void dispose() {
    _overlayVisibilityController.close();
    _returnToStudyController.close();
    _appLaunchController.close();
  }
}