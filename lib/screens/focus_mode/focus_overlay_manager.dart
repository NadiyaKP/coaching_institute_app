import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class FocusOverlayManager {
  static final FocusOverlayManager _instance = FocusOverlayManager._internal();
  factory FocusOverlayManager() => _instance;
  FocusOverlayManager._internal();

  static const MethodChannel _channel = MethodChannel('focus_mode_overlay_channel');
  
  bool _isOverlayVisible = false;
  bool _isInitialized = false;
  
  // Stream for overlay events
  final StreamController<bool> _overlayStreamController = StreamController<bool>.broadcast();
  Stream<bool> get overlayStream => _overlayStreamController.stream;
  
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
          // This can be listened to in your main app
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
  Future<void> showOverlay({String? message}) async {
    try {
      final result = await _channel.invokeMethod('showOverlay', {
        'message': message ?? 'You are in focus mode, focus on studies',
      });
      
      if (result == true) {
        _isOverlayVisible = true;
        _overlayStreamController.add(true);
        debugPrint('✅ Overlay shown');
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
  }
}