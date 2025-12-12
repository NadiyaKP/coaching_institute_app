import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../service/timer_service.dart';
import '../../service/websocket_manager.dart';

class FocusModeEntryScreen extends StatefulWidget {
  const FocusModeEntryScreen({super.key});

  @override
  State<FocusModeEntryScreen> createState() => _FocusModeEntryScreenState();
}

class _FocusModeEntryScreenState extends State<FocusModeEntryScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final TimerService _timerService = TimerService();
  late Future<Duration> _initializationFuture;
  Duration _focusTimeToday = Duration.zero;
  bool _hasOverlayPermission = false;
  bool _isStartingFocusMode = false;
  bool _isRestoredFromDisconnect = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializationFuture = _initializeData();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      debugPrint('📱 AppLifecycleState.detached - App being closed');
    }
  }

  Future<Duration> _initializeData() async {
    try {
      debugPrint('🔄 Starting focus mode entry initialization...');
      
      await _timerService.initialize();
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      debugPrint('📅 Today: $today');
      
      final disconnectTimeStr = prefs.getString(TimerService.websocketDisconnectTimeKey);
      if (disconnectTimeStr != null) {
        final disconnectTime = DateTime.parse(disconnectTimeStr);
        final disconnectDate = disconnectTime.toIso8601String().split('T')[0];
        
        debugPrint('🔌 Found WebSocket disconnect time: $disconnectDate');
        
        if (disconnectDate == today) {
          await _handleWebSocketDisconnectRecovery(prefs, today);
        } else {
          debugPrint('📅 Disconnect was on different day, clearing');
          await prefs.remove(TimerService.websocketDisconnectTimeKey);
          await _handleNormalInitialization(prefs, today);
        }
      } else {
        await _handleNormalInitialization(prefs, today);
      }
      
      _hasOverlayPermission = await _timerService.checkOverlayPermission();
      
      debugPrint('📋 Initialization Summary:');
      debugPrint('   - Focus time today: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Overlay permission: $_hasOverlayPermission');
      debugPrint('   - Restored from disconnect: $_isRestoredFromDisconnect');
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
      
      final lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey) ?? 0;
      final lastStoredDate = prefs.getString(TimerService.lastStoredFocusDateKey);
      final savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      
      debugPrint('   - Last stored time: ${lastStoredTime}s');
      debugPrint('   - Last stored date: $lastStoredDate');
      debugPrint('   - Saved focus time: ${savedFocusTime}s');
      
      int focusSeconds = 0;
      if (lastStoredDate == today) {
        focusSeconds = lastStoredTime > savedFocusTime ? lastStoredTime : savedFocusTime;
        _isRestoredFromDisconnect = true;
        debugPrint('   ✅ Using restored time: ${focusSeconds}s');
      } else {
        focusSeconds = savedFocusTime;
        debugPrint('   ⚠️ Last stored date mismatch, using saved time: ${focusSeconds}s');
      }
      
      _focusTimeToday = Duration(seconds: focusSeconds);
      await prefs.setInt(TimerService.focusKey, focusSeconds);
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      
      final bool wasStoppedByWebSocket = await _timerService.wasFocusStoppedByWebSocket();
      if (wasStoppedByWebSocket) {
        debugPrint('   🧹 Clearing WebSocket disconnect tracking');
      }
      
    } catch (e) {
      debugPrint('❌ Error in WebSocket disconnect recovery: $e');
      await _handleNormalInitialization(prefs, today);
    }
  }

  Future<void> _handleNormalInitialization(SharedPreferences prefs, String today) async {
    final lastDate = prefs.getString(TimerService.lastDateKey);
    
    debugPrint('📅 Normal initialization - Last saved date: $lastDate');
    
    if (lastDate != today) {
      debugPrint('🔄 New day detected! Resetting timer...');
      await _resetTimerForNewDay(prefs, today);
    } else {
      final savedFocusTime = prefs.getInt(TimerService.focusKey) ?? 0;
      final lastStoredTime = prefs.getInt(TimerService.lastStoredFocusTimeKey) ?? 0;
      
      final focusSeconds = savedFocusTime > lastStoredTime ? savedFocusTime : lastStoredTime;
      _focusTimeToday = Duration(seconds: focusSeconds);
      
      debugPrint('📊 Loaded focus time: ${_formatDuration(_focusTimeToday)}');
      debugPrint('   - Saved: ${savedFocusTime}s');
      debugPrint('   - Last stored: ${lastStoredTime}s');
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
    
    _focusTimeToday = Duration.zero;
    _isRestoredFromDisconnect = false;
    debugPrint('✅ Timer reset to 00:00:00 for new day');
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

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastDate = prefs.getString(TimerService.lastDateKey);
      
      if (lastDate != today) {
        debugPrint('⚠️ Date changed during start, resetting timer');
        await prefs.setString(TimerService.lastDateKey, today);
        await prefs.setInt(TimerService.focusKey, 0);
        _focusTimeToday = Duration.zero;
        _isRestoredFromDisconnect = false;
      }

      await _timerService.initialize();
      await prefs.remove(TimerService.websocketDisconnectTimeKey);
      
      final hasPermission = await _timerService.checkOverlayPermission();
      
      if (!hasPermission) {
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
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
        await _actuallyStartFocusMode();
      }
    } catch (e) {
      debugPrint('❌ Error starting focus mode: $e');
      
      if (e.toString().contains('Overlay permission required')) {
        final shouldOpenSettings = await _showPermissionPopup();
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
          await Future.delayed(const Duration(milliseconds: 500));
          final newPermissionStatus = await _timerService.checkOverlayPermission();
          
          if (newPermissionStatus) {
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

  Future<void> _showWebSocketErrorPopup() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Text('Connection Error', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unable to start Focus Mode. The app is not connected to the server.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              Text(
                'Please check your internet connection and try again.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Reconnecting...', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    duration: Duration(seconds: 3),
                  ),
                );
                
                await WebSocketManager.cleanReconnect();
                await Future.delayed(const Duration(milliseconds: 1500));
                
                if (WebSocketManager.isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connected successfully!', style: TextStyle(fontSize: 13)),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reconnection failed. Please check your connection.', style: TextStyle(fontSize: 13)),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('RETRY', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showPermissionPopup() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('Permission Required', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable Focus Mode with distraction blocking, you need to grant "Display over other apps" permission.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              _buildPermissionStep('1. Click "OK" below'),
              _buildPermissionStep('2. Find "Display over other apps" in settings'),
              _buildPermissionStep('3. Enable it for this app'),
              _buildPermissionStep('4. Return to this app'),
              const SizedBox(height: 10),
              const Text(
                'Without this permission, Focus Mode will not block other apps.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white, fontSize: 13)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('Permission Not Granted', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus Mode requires "Display over other apps" permission to block distractions.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 10),
              Text(
                'Please enable it in Settings to use Focus Mode.',
                style: TextStyle(
                  fontSize: 13,
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
              child: const Text('STAY HERE', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
                await Future.delayed(const Duration(milliseconds: 500));
                final hasPermission = await _timerService.checkOverlayPermission();
                if (hasPermission) {
                  await _actuallyStartFocusMode();
                } else {
                  setState(() {
                    _isStartingFocusMode = false;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43E97B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _actuallyStartFocusMode() async {
    try {
      debugPrint('🚀 Starting focus mode with current time: ${_focusTimeToday.inSeconds}s');
      
      _timerService.focusTimeToday.value = _focusTimeToday;
      await _timerService.startFocusMode();
      
      debugPrint('✅ Focus mode started, navigating to home');
      
      _sendFocusStartEvent();
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: FutureBuilder<Duration>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF43E97B)),
              ),
            );
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to Initialize',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initializationFuture = _initializeData();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43E97B),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Retry', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }
          
          final Duration focusTime = snapshot.data ?? Duration.zero;
          
          return SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  
                  // Hero Section with Icon and Title
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF43E97B).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.psychology_rounded, size: 50, color: Colors.white),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  const Text(
                    'Focus Mode',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: -0.5),
                  ),
                  
                  const SizedBox(height: 6),
                  
                  Text(
                    _hasOverlayPermission ? 'Ready to boost productivity' : 'Grant permission to start',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Main Stats Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Timer Display
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF43E97B).withOpacity(0.08),
                                const Color(0xFF38F9D7).withOpacity(0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF43E97B).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.timer_rounded, color: Color(0xFF43E97B), size: 18),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Today\'s Focus Time',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _formatDuration(focusTime),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF43E97B),
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.5,
                                ),
                              ),
                              if (_isRestoredFromDisconnect) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.restore, size: 12, color: Colors.green),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Restored from last session',
                                        style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Permission Status
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _hasOverlayPermission ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _hasOverlayPermission ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _hasOverlayPermission ? Icons.check_circle_rounded : Icons.info_rounded,
                                color: _hasOverlayPermission ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _hasOverlayPermission ? 'Full Protection Enabled' : 'Permission Required',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _hasOverlayPermission ? Colors.green[700] : Colors.orange[700],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _hasOverlayPermission ? 'Distraction blocking is active' : 'Enable overlay for best results',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Features Grid
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What You Get',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                        _buildFeatureItem(
                          icon: Icons.block_rounded,
                          title: 'App Blocking',
                          description: 'Block distracting apps',
                          color: const Color(0xFF43E97B),
                        ),
                        const SizedBox(height: 10),
                        _buildFeatureItem(
                          icon: Icons.analytics_rounded,
                          title: 'Time Tracking',
                          description: 'Monitor focus sessions',
                          color: const Color(0xFF38F9D7),
                        ),
                        const SizedBox(height: 10),
                        _buildFeatureItem(
                          icon: Icons.trending_up_rounded,
                          title: 'Productivity Boost',
                          description: 'Stay focused, achieve more',
                          color: const Color(0xFFF4B400),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Start Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isStartingFocusMode ? null : _startFocusMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43E97B),
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: _isStartingFocusMode ? 0 : 6,
                        shadowColor: const Color(0xFF43E97B).withOpacity(0.4),
                      ),
                      child: _isStartingFocusMode
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Start Focus Session',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                                ),
                              ],
                            ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 1),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
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
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}