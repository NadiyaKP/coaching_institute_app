import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

class FocusOverlayManager {
  static final FocusOverlayManager _instance = FocusOverlayManager._internal();
  factory FocusOverlayManager() => _instance;
  FocusOverlayManager._internal();

  static const MethodChannel _channel = MethodChannel('focus_mode_overlay_channel');
  
  bool _isOverlayVisible = false;
  bool _isInitialized = false;
  
  // Stream for overlay events
  final StreamController<bool> _overlayStreamController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _appLaunchStreamController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<bool> get overlayStream => _overlayStreamController.stream;
  Stream<Map<String, dynamic>> get appLaunchStream => _appLaunchStreamController.stream;
  
  // Initialize the manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onOverlayShown':
          _isOverlayVisible = true;
          _overlayStreamController.add(true);
          debugPrint('🎯 Overlay shown (from native)');
          return true;
        case 'onOverlayHidden':
          _isOverlayVisible = false;
          _overlayStreamController.add(false);
          debugPrint('🎯 Overlay hidden (from native)');
          return true;
        case 'onReturnToStudy':
          debugPrint('🎯 Return to study triggered from overlay');
          return true;
        case 'onAppLaunch':
          final appData = call.arguments as Map<String, dynamic>;
          _appLaunchStreamController.add(appData);
          debugPrint('🎯 App launch requested: ${appData['packageName']}');
          return true;
        case 'onPermissionRequired':
          debugPrint('🎯 Overlay permission required');
          return true;
        case 'onOverlayError':
          debugPrint('❌ Overlay error: ${call.arguments}');
          return true;
      }
      return null;
    });
    
    _isInitialized = true;
    debugPrint('✅ FocusOverlayManager initialized');
  }
  
  // Show overlay
  Future<void> showOverlay({String? message, List<Map<String, dynamic>>? allowedApps}) async {
    try {
      final result = await _channel.invokeMethod('showOverlay', {
        'message': message ?? 'You are in focus mode, focus on studies',
        'allowedApps': allowedApps ?? [],
      });
      
      if (result == true) {
        _isOverlayVisible = true;
        _overlayStreamController.add(true);
        debugPrint('✅ Overlay shown with ${allowedApps?.length ?? 0} allowed apps');
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Failed to show overlay: ${e.message}');
    }
  }
  
  // Hide overlay
  Future<void> hideOverlay() async {
    try {
      if (_isOverlayVisible) {
        final result = await _channel.invokeMethod('hideOverlay');
        
        if (result == true) {
          _isOverlayVisible = false;
          _overlayStreamController.add(false);
          debugPrint('✅ Overlay hidden');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('❌ Failed to hide overlay: ${e.message}');
    }
  }
  
  // Update allowed apps in overlay
  Future<void> updateAllowedApps(List<Map<String, dynamic>> allowedApps) async {
    try {
      await _channel.invokeMethod('updateAllowedApps', {
        'allowedApps': allowedApps,
      });
      debugPrint('✅ Updated overlay with ${allowedApps.length} allowed apps');
    } on PlatformException catch (e) {
      debugPrint('❌ Failed to update allowed apps: ${e.message}');
    }
  }
  
  // Check if overlay is visible
  bool get isOverlayVisible => _isOverlayVisible;
  
  // Check permission
  Future<bool> checkOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod('checkOverlayPermission');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('❌ Failed to check overlay permission: ${e.message}');
      return false;
    }
  }
  
  // Dispose
  void dispose() {
    _overlayStreamController.close();
    _appLaunchStreamController.close();
  }
}