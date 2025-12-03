import 'package:flutter/material.dart';
import 'package:coaching_institute_app/service/focus_mode_overlay_service.dart';
import 'package:permission_handler/permission_handler.dart'; 


class FocusModePermissionScreen extends StatefulWidget {
  final VoidCallback onPermissionGranted;
  final VoidCallback onPermissionDenied;
  
  const FocusModePermissionScreen({
    super.key,
    required this.onPermissionGranted,
    required this.onPermissionDenied,
  });

  @override
  State<FocusModePermissionScreen> createState() => _FocusModePermissionScreenState();
}

class _FocusModePermissionScreenState extends State<FocusModePermissionScreen> {
  final FocusModeOverlayService _overlayService = FocusModeOverlayService();
  bool _isRequesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingPermission();
  }

  Future<void> _checkExistingPermission() async {
    final hasPermission = await _overlayService.checkOverlayPermission();
    if (hasPermission) {
      widget.onPermissionGranted();
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      // First show explanation dialog
      final shouldRequest = await _overlayService.showPermissionDialog(context);
      
      if (!shouldRequest) {
        setState(() {
          _isRequesting = false;
        });
        widget.onPermissionDenied();
        return;
      }

      // Request permission from system
      final granted = await _overlayService.requestOverlayPermission();
      
      setState(() {
        _isRequesting = false;
      });

      if (granted) {
        widget.onPermissionGranted();
      } else {
        _showPermissionDeniedDialog();
      }
    } catch (e) {
      setState(() {
        _isRequesting = false;
        _errorMessage = 'Failed to request permission: $e';
      });
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text(
            'Focus Mode requires the "Display over other apps" permission '
            'to function properly. Without this permission, you cannot use '
            'the Focus Mode feature.\n\n'
            'Please grant the permission in Settings to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPermissionDenied();
              },
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
                // Re-check permission after returning from settings
                await _checkExistingPermission();
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Focus Mode Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onPermissionDenied,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF43E97B).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF43E97B),
                  width: 3,
                ),
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 60,
                color: Color(0xFF43E97B),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Title
            const Text(
              'Enable Focus Mode',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Description
            const Text(
              'To prevent distractions during your study session, '
              'Focus Mode needs permission to display a reminder screen '
              'when you try to leave the app.\n\n'
              'This helps you stay focused and achieve your study goals.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Permission Details Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPermissionDetail(
                    icon: Icons.visibility,
                    title: 'Display Over Other Apps',
                    description: 'Shows a reminder when you try to switch apps',
                  ),
                  const SizedBox(height: 16),
                  _buildPermissionDetail(
                    icon: Icons.block,
                    title: 'Block Distractions',
                    description: 'Prevents navigation to other apps during study',
                  ),
                  const SizedBox(height: 16),
                  _buildPermissionDetail(
                    icon: Icons.school,
                    title: 'Study Focus',
                    description: 'Helps you maintain concentration on studies',
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            
            // Request Permission Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isRequesting ? null : _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43E97B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: _isRequesting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'GRANT PERMISSION',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Skip button
            TextButton(
              onPressed: widget.onPermissionDenied,
              child: const Text(
                'Skip for now (Focus Mode will not work)',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDetail({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF43E97B), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}