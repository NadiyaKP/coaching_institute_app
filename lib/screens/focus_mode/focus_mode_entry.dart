import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../service/timer_service.dart';
import '../../service/websocket_manager.dart'; // Import the WebSocket manager
import '../home.dart';

class FocusModeEntryScreen extends StatefulWidget {
  const FocusModeEntryScreen({super.key});

  @override
  State<FocusModeEntryScreen> createState() => _FocusModeEntryScreenState();
}

class _FocusModeEntryScreenState extends State<FocusModeEntryScreen> {
  final TimerService _timerService = TimerService();
  late Future<Duration> _initializationFuture;
  Duration _focusTimeToday = Duration.zero;
  bool _hasOverlayPermission = false;
  bool _isStartingFocusMode = false;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeData();
  }

  Future<Duration> _initializeData() async {
    // Initialize timer service
    await _timerService.initialize();
    
    // Check overlay permission using TimerService
    _hasOverlayPermission = await _timerService.checkOverlayPermission();
    
    // Get today's focus time
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(TimerService.focusKey) ?? 0;
    _focusTimeToday = Duration(seconds: seconds);
    
    debugPrint('📊 Loaded focus time: ${_formatDuration(_focusTimeToday)}');
    debugPrint('🎯 Overlay permission: $_hasOverlayPermission');
    
    return _focusTimeToday;
  }

  void _startFocusMode() async {
    if (_isStartingFocusMode) return;
    
    setState(() {
      _isStartingFocusMode = true;
    });

    try {
      // Ensure timer service is initialized
      await _timerService.initialize();
      
      // Check overlay permission using TimerService
      final hasPermission = await _timerService.checkOverlayPermission();
      
      if (!hasPermission) {
        // Show popup asking for permission
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          // User clicked OK - open settings
          await openAppSettings();
          
          // After returning from settings, check permission again
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            // Permission granted, start focus mode
            await _actuallyStartFocusMode();
          } else {
            // User still hasn't granted permission
            // Show another popup explaining they need it
            await _showPermissionRequiredPopup();
            setState(() {
              _isStartingFocusMode = false;
            });
            return;
          }
        } else {
          // User clicked Cancel, stay on this page
          setState(() {
            _isStartingFocusMode = false;
          });
          return;
        }
      } else {
        // Already have permission, start focus mode
        await _actuallyStartFocusMode();
      }
    } catch (e) {
      debugPrint('❌ Error starting focus mode: $e');
      
      // Check if error is about overlay permission
      if (e.toString().contains('Overlay permission required')) {
        // Show permission popup
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
            // Try again with permission granted
            await _timerService.startFocusMode(skipPermissionCheck: true);
            await _actuallyStartFocusMode();
          } else {
            await _showPermissionRequiredPopup();
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start focus mode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  Future<bool?> _showPermissionPopup() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Permission Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable Focus Mode with distraction blocking, you need to grant "Display over other apps" permission.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              _buildPermissionStep('1. Click "OK" below'),
              _buildPermissionStep('2. Find "Display over other apps" in settings'),
              _buildPermissionStep('3. Enable it for this app'),
              _buildPermissionStep('4. Return to this app'),
              const SizedBox(height: 12),
              const Text(
                'Without this permission, Focus Mode will not block other apps.',
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
                Navigator.of(context).pop(false); // Cancel
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true); // OK
              },
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPermissionRequiredPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Permission Not Granted'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus Mode requires "Display over other apps" permission to block distractions.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Please enable it in Settings to use Focus Mode.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
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
              child: const Text(
                'STAY HERE',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
                // Check permission again after returning
                await Future.delayed(const Duration(milliseconds: 500));
                final hasPermission = await _timerService.checkOverlayPermission();
                if (hasPermission) {
                  // Start focus mode if permission granted
                  await _actuallyStartFocusMode();
                } else {
                  setState(() {
                    _isStartingFocusMode = false;
                  });
                }
              },
              child: const Text(
                'OPEN SETTINGS',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 16, color: Colors.grey),
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

  Future<void> _actuallyStartFocusMode() async {
    try {
      // Start focus mode
      await _timerService.startFocusMode();
      
      debugPrint('✅ Focus mode started, navigating to home');
      
      // Send WebSocket event for focus start
      _sendFocusStartEvent();
      
      // Navigate to home screen with focus mode active
      Navigator.pushReplacementNamed(
        context, 
        '/home',
        arguments: {'isFocusMode': true}
      );
      
    } catch (e) {
      debugPrint('❌ Error in actuallyStartFocusMode: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start focus mode: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isStartingFocusMode = false;
      });
    }
  }

  // Method to send focus_start event via WebSocket
  void _sendFocusStartEvent() {
    try {
      // Always try to send the event directly
      WebSocketManager.send({"event": "focus_start"});
      debugPrint('📤 WebSocket event sent: {"event": "focus_start"}');
    } catch (e) {
      debugPrint('❌ Error sending focus_start event: $e');
      
      // Try to reconnect WebSocket if sending failed
      try {
        WebSocketManager.connect();
        debugPrint('🔄 Attempting to reconnect WebSocket...');
        
        // Try sending again after a short delay
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Duration>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Focus Icon
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
                    Icons.timer,
                    size: 60,
                    color: Color(0xFF43E97B),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Enter Focus Mode',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Description
                Text(
                  _hasOverlayPermission 
                    ? 'Full distraction blocking is enabled. Stay focused!'
                    : 'Grant permission to block distractions and maximize focus.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Today's Focus Time Statistics
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      _buildStatItem(
                        icon: Icons.timer,
                        value: _formatDuration(snapshot.data ?? Duration.zero),
                        label: 'Focus Today',
                        color: const Color(0xFF43E97B),
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionStatus(),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Start Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isStartingFocusMode ? null : _startFocusMode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43E97B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF43E97B).withOpacity(0.3),
                    ),
                    child: _isStartingFocusMode
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: Colors.white),
                              SizedBox(width: 10),
                              Text(
                                'Start Focus Session',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Skip for now button
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context, 
                      '/home',
                      arguments: {'isFocusMode': false}
                    );
                  },
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _hasOverlayPermission ? Icons.check_circle : Icons.warning,
          color: _hasOverlayPermission ? Colors.green : Colors.orange,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          _hasOverlayPermission 
            ? 'Permission granted'
            : 'Permission required for full features',
          style: TextStyle(
            fontSize: 12,
            color: _hasOverlayPermission ? Colors.green : Colors.orange,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void dispose() {
    super.dispose();
  }
}