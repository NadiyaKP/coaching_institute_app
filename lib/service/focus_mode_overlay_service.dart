import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class FocusModeOverlayService {
  static final FocusModeOverlayService _instance = FocusModeOverlayService._internal();
  factory FocusModeOverlayService() => _instance;
  FocusModeOverlayService._internal();

  // Channel for platform-specific overlay implementation
  static const platform = MethodChannel('focus_mode_overlay_channel');
  
  // Stream controllers for overlay events
  final StreamController<bool> _overlayVisibilityController = StreamController<bool>.broadcast();
  final StreamController<void> _returnToStudyController = StreamController<void>.broadcast();
  
  Stream<bool> get overlayVisibilityStream => _overlayVisibilityController.stream;
  Stream<void> get returnToStudyStream => _returnToStudyController.stream;
  
  bool _isOverlayVisible = false;
  bool get isOverlayVisible => _isOverlayVisible;
  
  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;
  
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
      
      // Set up method call handlers
      platform.setMethodCallHandler((call) async {
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
        }
        return null;
      });
      
      debugPrint('✅ FocusModeOverlayService initialized');
      debugPrint('   - Permission granted: $_hasPermission');
    } catch (e) {
      debugPrint('❌ Error initializing FocusModeOverlayService: $e');
    }
  }
  
  // Dispose resources
  void dispose() {
    _overlayVisibilityController.close();
    _returnToStudyController.close();
  }
}