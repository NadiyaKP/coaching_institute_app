import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../service/api_config.dart';

class WebSocketManager {
  static WebSocketChannel? _channel;
  static StreamSubscription? _wsSubscription;
  static Timer? _heartbeatTimer;
  static Timer? _reconnectTimer;
  static bool _isConnecting = false;
  static bool _isForceDisconnected = false;
  static bool _isManualReconnect = false;
  static bool _shouldReconnect = true;

  static int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  
  // 🆕 NEW: Add timestamp tracking for accurate pause/resume
  static DateTime? _lastDisconnectTime;
  static DateTime? _lastConnectTime;
  static Duration? _pauseDuration;

  static final StreamController<dynamic> _messageController =
      StreamController.broadcast();
  
  static final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  
  // 🆕 Add reconnected stream controller
  static final StreamController<void> _reconnectedController =
      StreamController<void>.broadcast();
  
  static Function()? _onDisconnectionCallback;
  static Function()? _onReconnectionCallback;
  
  // 🆕 Add timer service reference for focus status
  static Function()? _onFocusStatusRequestCallback;
  
  static Stream<dynamic> get stream => _messageController.stream;
  static Stream<bool> get connectionStateStream => _connectionStateController.stream;
  // 🆕 Add reconnected stream getter
  static Stream<void> get reconnectedStream => _reconnectedController.stream;

  // 🆕 NEW: Get last disconnect time for timer service
  static DateTime? get lastDisconnectTime => _lastDisconnectTime;

  static void registerDisconnectionCallback(Function() callback) {
    _onDisconnectionCallback = callback;
  }
  
  static void registerReconnectionCallback(Function() callback) {
    _onReconnectionCallback = callback;
  }
  
  // 🆕 NEW: Register focus status update callback
  static void registerFocusStatusRequestCallback(Function() callback) {
    _onFocusStatusRequestCallback = callback;
  }
  
  static void removeCallbacks() {
    _onDisconnectionCallback = null;
    _onReconnectionCallback = null;
    _onFocusStatusRequestCallback = null;
  }

  static void sendFocusStatus(bool isFocusing) {
    if (_channel == null) {
      print("⚠️ Cannot send focus status - channel null");
      return;
    }

    try {
      final focusData = jsonEncode({
        "event": "focus_status",
        "is_focusing": isFocusing ? 1 : 0,
        "ts": DateTime.now().toUtc().millisecondsSinceEpoch
      });
      _channel!.sink.add(focusData);
      print("📤 Focus status sent: is_focusing=${isFocusing ? 1 : 0}");
    } catch (e) {
      print("❌ Failed to send focus status: $e");
    }
  }

  // 🆕 NEW: Send heartbeat with focus status
  static void _sendHeartbeatWithFocusStatus() {
    try {
      // Trigger focus status update callback first
      if (_onFocusStatusRequestCallback != null) {
        _onFocusStatusRequestCallback!();
      }
    } catch (e) {
      print("❌ Failed to send heartbeat with focus status: $e");
      if (_shouldReconnect && !_isForceDisconnected && !_isConnecting) {
        _scheduleReconnection();
      }
    }
  }

  static Future<void> connect({bool isManual = false}) async {
    // 🎯 DEBUG: Track entry
    print("🎯🎯🎯 CONNECT ENTERED - isManual param: $isManual, _isManualReconnect: $_isManualReconnect, _isConnecting: $_isConnecting");
    
    // If manual reconnect requested, set flag
    if (isManual) {
      print("🔵 Manual reconnect requested via parameter - setting flag");
      _isManualReconnect = true;
      _isForceDisconnected = false; // Override force disconnect
    }
    
    // 🔥 FIX: For manual reconnects, always proceed even if "connected"
    if (isConnected && !_isManualReconnect) {
      print("✅ Already connected to WebSocket (not manual)");
      return;
    }
    
    // 🔥 FIX: For manual reconnects, override "already connecting" state
    if (_isConnecting) {
      if (_isManualReconnect) {
        print("🔄 Manual reconnect overriding existing connection attempt");
        // Cancel current attempt and proceed
        await _forceDisconnectForReconnect();
        _isConnecting = false;
      } else {
        print("⏳ Already attempting to connect...");
        return;
      }
    }
    
    // Check force disconnect flag (but allow manual overrides)
    if (_isForceDisconnected && !_isManualReconnect) {
      print("⛔ Force disconnected - skipping connection");
      return;
    }
    
    _isConnecting = true;
    print("🔄🔄🔄 NEW CONNECTION ATTEMPT ${_reconnectAttempt + 1} - manual flag: $_isManualReconnect 🔄🔄🔄");
    
    // 🆕 NEW: Store connect time
    _lastConnectTime = DateTime.now();
    print("⏱️ Connection attempt started at: $_lastConnectTime");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken') ?? '';
      
      if (token.isEmpty) {
        print("❌ No token found. Cannot connect WebSocket.");
        _isConnecting = false;
        _isManualReconnect = false;
        return;
      }
      
      // Add unique timestamp to prevent caching
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = "${ApiConfig.websocketBase}/ws/monitoring/?token=$token&_t=$timestamp&manual=$_isManualReconnect";
      print("🔗 Connecting WebSocket to: ${url.split('token=')[0]}...");
      
      // 🔥 FIX: Always create new channel
      print("📡 Creating new WebSocket channel...");
      _channel = WebSocketChannel.connect(
        Uri.parse(url),
      );
      
      bool firstMessageReceived = false;
      final completer = Completer<bool>();
      
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        print("⏰⏰⏰ CONNECTION TIMEOUT after 15 seconds ⏰⏰⏰");
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });
      
      _wsSubscription = _channel!.stream.listen(
        (event) {
          print("📩 WebSocket Received: ${event.toString().length > 100 ? '${event.toString().substring(0, 100)}...' : event}");
          
          if (!firstMessageReceived) {
            firstMessageReceived = true;
            timeoutTimer.cancel();
            
            print("✅✅✅ FIRST MESSAGE RECEIVED - Connection established! ✅✅✅");
            
            // Reset reconnect attempt on successful connection
            _reconnectAttempt = 0;
            _isManualReconnect = false;
            _shouldReconnect = true;
            
            if (!completer.isCompleted) {
              completer.complete(true);
            }
            
            _connectionStateController.add(true);
            
            // 🆕 CRITICAL: Notify reconnection
            _reconnectedController.add(null);
            
            if (_onReconnectionCallback != null) {
              _onReconnectionCallback!();
            }
            
            // 🆕 NEW: Notify focus status update callback to send current status
            if (_onFocusStatusRequestCallback != null) {
              print("🔔 Notifying focus status update callback on connection");
              _onFocusStatusRequestCallback!();
            }
          }
          
          _messageController.add(event);
        },
        onError: (error) {
          print("❌❌❌ WEB SOCKET ERROR: $error ❌❌❌");
          
          timeoutTimer.cancel();
          
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          
          _messageController.addError(error);
          _connectionStateController.add(false);
          
          if (_onDisconnectionCallback != null) {
            _onDisconnectionCallback!();
          }
          
          // Reset flags
          _isConnecting = false;
          
          if (_shouldReconnect && !_isForceDisconnected) {
            _scheduleReconnection();
          }
        },
        onDone: () {
          final closeCode = _channel?.closeCode;
          final closeReason = _channel?.closeReason;
          print("🔌🔌🔌 WEB SOCKET CLOSED - Code: $closeCode, Reason: $closeReason 🔌🔌🔌");
          
          timeoutTimer.cancel();
          
          // 🆕 Store disconnect time for accurate pause duration
          _lastDisconnectTime = DateTime.now();
          print("⏱️ WebSocket disconnect time recorded: $_lastDisconnectTime");
          
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          
          _connectionStateController.add(false);
          
          if (_onDisconnectionCallback != null) {
            _onDisconnectionCallback!();
          }
          
          // Reset connecting flag
          _isConnecting = false;
          
          // Only reconnect if not a clean close (1000) and not force disconnected
          if (_shouldReconnect && closeCode != 1000 && !_isForceDisconnected) {
            _scheduleReconnection();
          }
        },
        cancelOnError: true,
      );
      
      print("📡 Sending probe heartbeat...");
      _sendProbeHeartbeat();
      
      final verified = await completer.future;
      
      // Always cancel timer
      timeoutTimer.cancel();
      
      if (!verified) {
        print("❌❌❌ WEB SOCKET CONNECTION FAILED - No response from server ❌❌❌");
        await _forceDisconnectForReconnect();
        
        _isConnecting = false;
        _connectionStateController.add(false);
        
        if (_onDisconnectionCallback != null) {
          _onDisconnectionCallback!();
        }
        
        if (_shouldReconnect && !_isForceDisconnected) {
          _scheduleReconnection();
        }
        return;
      }
      
      print("✅ WebSocket Connection Verified");
      _startHeartbeat();
      print("✨✨✨ WEB SOCKET CONNECTED SUCCESSFULLY ✨✨✨");
      
      _isConnecting = false;
      
    } catch (e, stack) {
      print("❌❌❌ WEB SOCKET EXCEPTION ❌❌❌");
      print("Error: $e");
      print("Stack: $stack");
      
      // Always reset connecting flag on exception
      _isConnecting = false;
      _connectionStateController.add(false);
      
      if (_onDisconnectionCallback != null) {
        _onDisconnectionCallback!();
      }
      
      if (_shouldReconnect && !_isForceDisconnected) {
        _scheduleReconnection();
      }
    }
  }

  // Safe disconnect method
  static Future<void> _safeDisconnect({int closeCode = 1000}) async {
    print("🔧 SAFE DISCONNECT called with code: $closeCode");
    
    try {
      _stopHeartbeat();
      
      // Cancel subscription first
      if (_wsSubscription != null) {
        print("📝 Cancelling subscription...");
        await _wsSubscription?.cancel();
        _wsSubscription = null;
        print("✅ Subscription cancelled");
      }

      // Then close channel
      if (_channel != null) {
        print("📝 Closing channel...");
        try {
          await _channel?.sink.close(closeCode, _isManualReconnect ? "Manual reconnect" : "Disconnecting");
          print("✅ Channel sink closed");
        } catch (e) {
          print("⚠️ Error closing channel sink: $e");
        }
        _channel = null;
        print("✅ Channel nullified");
      }
    } catch (e) {
      print("⚠️ Error in safe disconnect: $e");
    } finally {
      // Always ensure connecting flag is false
      _isConnecting = false;
      print("🔧 Safe disconnect completed");
    }
  }

  // Send probe heartbeat
  static void _sendProbeHeartbeat() {
    try {
      if (_channel != null && _channel!.closeCode == null) {
        final probeData = jsonEncode({"event": "heartbeat", "probe": true, "manual": _isManualReconnect});
        _channel!.sink.add(probeData);
        print("📤 Probe heartbeat sent (manual: $_isManualReconnect)");
      } else {
        print("⚠️ Cannot send probe - channel: ${_channel != null}, closeCode: ${_channel?.closeCode}");
      }
    } catch (e) {
      print("❌ Failed to send probe heartbeat: $e");
    }
  }

  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) {
        _sendHeartbeatWithFocusStatus();
      },
    );
    print("💓 Heartbeat timer started (with focus status)");
  }

  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    print("💓 Heartbeat timer stopped");
  }

  static void send(dynamic data) {
    if (_channel == null) {
      print("⚠️ Cannot send WS message - channel null");
      return;
    }

    try {
      final jsonData = (data is String) ? data : jsonEncode(data);
      _channel!.sink.add(jsonData);
      print("📤 WebSocket Sent: ${jsonData.length > 100 ? '${jsonData.substring(0, 100)}...' : jsonData}");
    } catch (e) {
      print("❌ Failed to send WS message: $e");
      if (_shouldReconnect && !_isForceDisconnected && !_isConnecting) {
        _scheduleReconnection();
      }
    }
  }

  static void sendCombinedHeartbeat(bool isFocusing) {
    if (_channel == null) {
      print("⚠️ Cannot send combined heartbeat - channel null");
      return;
    }

    try {
      final heartbeatData = jsonEncode({
        "event": "heartbeat",
        "ts": DateTime.now().toUtc().millisecondsSinceEpoch,
        "is_focusing": isFocusing ? 1 : 0
      });
      _channel!.sink.add(heartbeatData);
      print("📤 WebSocket Sent: ${heartbeatData.length > 100 ? '${heartbeatData.substring(0, 100)}...' : heartbeatData}");
      print("💓 Heartbeat sent (is_focusing: ${isFocusing ? 1 : 0})");
    } catch (e) {
      print("❌ Failed to send combined heartbeat: $e");
      if (_shouldReconnect && !_isForceDisconnected && !_isConnecting) {
        _scheduleReconnection();
      }
    }
  }
  
  static Future<void> resetConnectionState() async {
    print('🔄🔄🔄 RESETTING CONNECTION STATE 🔄🔄🔄');
    
    // Cancel all timers
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    // Reset connection flags
    _isConnecting = false;
    _isForceDisconnected = false;
    _isManualReconnect = false;
    _shouldReconnect = true;
    _reconnectAttempt = 0;
    _lastDisconnectTime = null;
    _lastConnectTime = null;
    _pauseDuration = null;
    
    print("✅ Flags reset");
    
    // Clean up existing connections
    await _safeDisconnect();
    
    print('✅ WebSocket connection state reset complete');
  }

  static Future<void> disconnect() async {
    print("🔌🔌🔌 DISCONNECT CALLED 🔌🔌🔌");
    
    // Stop reconnection attempts
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _isConnecting = false;
    _isManualReconnect = false;
    _lastDisconnectTime = DateTime.now();
    
    await _safeDisconnect();
    
    _connectionStateController.add(false);
    print("🔌 WebSocket Disconnected Successfully");
  }

  static Future<void> forceDisconnect() async {
    print("🚨🚨🚨 FORCE DISCONNECT CALLED 🚨🚨🚨");
    
    _isForceDisconnected = true;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _isConnecting = false;
    _isManualReconnect = false;
    _lastDisconnectTime = DateTime.now();
    
    await _safeDisconnect();
    
    _connectionStateController.add(false);
    print("🚨 WebSocket Force Disconnected");
  }

  static void resetForceDisconnect() {
    print("🔄 Resetting force disconnect flag");
    _isForceDisconnected = false;
    _shouldReconnect = true;
  }

  static void _scheduleReconnection() {
    print("⏰ _scheduleReconnection called");
    
    // Don't schedule if already scheduled or shouldn't reconnect
    if (!_shouldReconnect || _isForceDisconnected) {
      print("⛔ Reconnection disabled - shouldReconnect: $_shouldReconnect, isForceDisconnected: $_isForceDisconnected");
      return;
    }
    
    if (_reconnectTimer != null) {
      print("⏳ Reconnection already scheduled, cancelling previous");
      _reconnectTimer?.cancel();
    }
    
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      print("⛔ Max reconnect attempts reached ($_reconnectAttempt/$_maxReconnectAttempts)");
      Timer(const Duration(seconds: 30), () {
        _reconnectAttempt = 0;
        _shouldReconnect = true;
        print("🔄 Reset reconnect attempts after cooldown");
      });
      return;
    }

    _reconnectAttempt++;

    // Exponential backoff with jitter
    final delay = _calculateReconnectDelay(_reconnectAttempt);
    
    print("⏰⏰⏰ SCHEDULING RECONNECTION in ${delay.inSeconds}s (attempt $_reconnectAttempt) ⏰⏰⏰");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      print("🔄🔄🔄 RECONNECTION TIMER FIRED - Attempt $_reconnectAttempt 🔄🔄🔄");
      connect();
    });
  }

  static Duration _calculateReconnectDelay(int attempt) {
    final baseDelay = pow(2, min(attempt - 1, 5)).toInt();
    final jitter = Random().nextInt(3);
    final totalSeconds = min(baseDelay + jitter, 30);
    print("📊 Reconnect delay calculation: base=$baseDelay, jitter=$jitter, total=$totalSeconds");
    return Duration(seconds: totalSeconds);
  }

  static bool get isConnected =>
      _channel != null &&
      _wsSubscription != null &&
      (_channel?.closeCode == null) &&
      !_isForceDisconnected &&
      !_isConnecting;

  static String get connectionStatus {
    if (_isForceDisconnected) return "force_disconnected";
    if (_isConnecting) return "connecting";
    if (isConnected) return "connected";
    return "disconnected";
  }

  static void logConnectionState() {
    print("""
📊📊📊 WEB SOCKET CONNECTION STATE 📊📊📊
  Channel: ${_channel != null ? "Exists (closeCode: ${_channel?.closeCode})" : "Null"}
  Subscription: ${_wsSubscription != null ? "Exists" : "Null"}
  Heartbeat Timer: ${_heartbeatTimer != null ? "Active" : "Inactive"}
  Reconnect Timer: ${_reconnectTimer != null ? "Active" : "Inactive"}
  Is Connecting: $_isConnecting
  Is Force Disconnected: $_isForceDisconnected
  Is Manual Reconnect: $_isManualReconnect
  Should Reconnect: $_shouldReconnect
  Reconnect Attempt: $_reconnectAttempt
  Last Disconnect Time: $_lastDisconnectTime
  Last Connect Time: $_lastConnectTime
  Connection Status: $connectionStatus
📊📊📊 END STATE 📊📊📊
""");
  }

  static Future<void> cleanReconnect() async {
    print("🔄 Performing clean reconnect...");
    resetForceDisconnect();
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connect();
  }

  static Future<void> forceReconnect() async {
    print('🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄');
    print('🔄         FORCE RECONNECT        🔄');
    print('🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄🔄');
    
    // Cancel any pending reconnection timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    // 🔥 CRITICAL FIX: Set ALL flags BEFORE any async operations
    print("🔄 Setting flags for force reconnect...");
    _isManualReconnect = true;
    _isForceDisconnected = false;
    _shouldReconnect = true;
    _reconnectAttempt = 0;
    _isConnecting = false;
    
    print("✅✅✅ Flags set: _isManualReconnect=$_isManualReconnect, _isConnecting=$_isConnecting ✅✅✅");
    
    // Log current state before disconnect
    print("📊 State before disconnect:");
    logConnectionState();
    
    try {
      // 🔥 FIX: Use different disconnect method that doesn't reset our flags
      await _forceDisconnectForReconnect();
      
      // 🔥 CRITICAL: Small delay to ensure clean state
      print("⏱️ Waiting for clean state...");
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 🔥 FIX: Double-check flags are still correct
      print("🔍 Checking flags after disconnect:");
      print("  _isManualReconnect: $_isManualReconnect");
      print("  _isConnecting: $_isConnecting");
      print("  _isForceDisconnected: $_isForceDisconnected");
      
      // Now connect with manual flag
      print("🔗🔗🔗 CALLING connect(isManual: true) 🔗🔗🔗");
      await connect(isManual: true);
      
    } catch (e) {
      print("❌❌❌ Error in forceReconnect: $e ❌❌❌");
      // Reset flags on error
      _isConnecting = false;
      _isManualReconnect = false;
      throw e;
    }
  }

  // 🔥 NEW: Special disconnect method for force reconnection
  static Future<void> _forceDisconnectForReconnect() async {
    print("🔧 _forceDisconnectForReconnect called");
    
    try {
      // Stop heartbeat but don't reset our manual flag
      if (_heartbeatTimer != null) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        print("💓 Heartbeat timer stopped");
      }
      
      // Cancel subscription
      if (_wsSubscription != null) {
        print("📝 Cancelling subscription...");
        await _wsSubscription?.cancel();
        _wsSubscription = null;
        print("✅ Subscription cancelled");
      }
      
      // Close channel with manual reconnect code
      if (_channel != null) {
        print("📝 Closing channel with code 1001 (manual reconnect)...");
        try {
          await _channel?.sink.close(1001, "Manual reconnect");
          print("✅ Channel sink closed");
        } catch (e) {
          print("⚠️ Error closing channel: $e");
        }
        _channel = null;
        print("✅ Channel nullified");
      }
      
      print("✅ _forceDisconnectForReconnect completed");
    } catch (e) {
      print("❌ Error in _forceDisconnectForReconnect: $e");
      // Even if error, ensure channel is null
      _channel = null;
      _wsSubscription = null;
    }
  }

  static void dispose() {
    print("🗑️ Disposing WebSocketManager...");
    removeCallbacks();
    _shouldReconnect = false;
    disconnect();
    _messageController.close();
    _connectionStateController.close();
    _reconnectedController.close(); // 🆕 Close reconnected controller
    print("🗑️ WS Manager disposed");
  }
}