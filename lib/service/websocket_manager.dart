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
  
  static DateTime? _lastDisconnectTime;
  static DateTime? _lastConnectTime;

  static final StreamController<dynamic> _messageController =
      StreamController.broadcast();
  
  static final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  
  static final StreamController<void> _reconnectedController =
      StreamController<void>.broadcast();
  
  static Function()? _onDisconnectionCallback;
  static Function()? _onReconnectionCallback;
  static Function()? _onFocusStatusRequestCallback;
  
  static Stream<dynamic> get stream => _messageController.stream;
  static Stream<bool> get connectionStateStream => _connectionStateController.stream;
  static Stream<void> get reconnectedStream => _reconnectedController.stream;

  static DateTime? get lastDisconnectTime => _lastDisconnectTime;

  static void registerDisconnectionCallback(Function() callback) {
    _onDisconnectionCallback = callback;
  }
  
  static void registerReconnectionCallback(Function() callback) {
    _onReconnectionCallback = callback;
  }
  
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

  static void _sendHeartbeatWithFocusStatus() {
    try {
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
    print("🎯 CONNECT ENTERED - isManual: $isManual, _isManualReconnect: $_isManualReconnect, _isConnecting: $_isConnecting");
    
    if (isManual) {
      print("🔵 Manual reconnect requested - setting flag");
      _isManualReconnect = true;
      _isForceDisconnected = false;
    }
    
    if (isConnected && !_isManualReconnect) {
      print("✅ Already connected to WebSocket");
      return;
    }
    
    if (_isConnecting) {
      if (_isManualReconnect) {
        print("🔄 Manual reconnect overriding existing connection attempt");
        await _forceDisconnectForReconnect();
        _isConnecting = false;
      } else {
        print("⏳ Already attempting to connect...");
        return;
      }
    }
    
    if (_isForceDisconnected && !_isManualReconnect) {
      print("⛔ Force disconnected - skipping connection");
      return;
    }
    
    _isConnecting = true;
    print("🔄 NEW CONNECTION ATTEMPT ${_reconnectAttempt + 1} - manual: $_isManualReconnect");
    
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
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = "${ApiConfig.websocketBase}/ws/monitoring/?token=$token&_t=$timestamp&manual=$_isManualReconnect";
      print("🔗 Connecting WebSocket...");
      
      print("📡 Creating new WebSocket channel...");
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      bool firstMessageReceived = false;
      final completer = Completer<bool>();
      
      final timeoutTimer = Timer(const Duration(seconds: 15), () {
        print("⏰ CONNECTION TIMEOUT after 15 seconds");
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
            
            print("✅ FIRST MESSAGE RECEIVED - Connection established!");
            
            _reconnectAttempt = 0;
            _isManualReconnect = false;
            _shouldReconnect = true;
            
            if (!completer.isCompleted) {
              completer.complete(true);
            }
            
            _connectionStateController.add(true);
            _reconnectedController.add(null);
            
            if (_onReconnectionCallback != null) {
              _onReconnectionCallback!();
            }
            
            if (_onFocusStatusRequestCallback != null) {
              print("🔔 Notifying focus status update callback on connection");
              _onFocusStatusRequestCallback!();
            }
          }
          
          _messageController.add(event);
        },
        onError: (error) {
          print("❌ WEB SOCKET ERROR: $error");
          
          timeoutTimer.cancel();
          
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          
          _messageController.addError(error);
          _connectionStateController.add(false);
          
          if (_onDisconnectionCallback != null) {
            _onDisconnectionCallback!();
          }
          
          _isConnecting = false;
          
          if (_shouldReconnect && !_isForceDisconnected) {
            _scheduleReconnection();
          }
        },
        onDone: () {
          final closeCode = _channel?.closeCode;
          final closeReason = _channel?.closeReason;
          print("🔌 WEB SOCKET CLOSED - Code: $closeCode, Reason: $closeReason");
          
          timeoutTimer.cancel();
          
          _lastDisconnectTime = DateTime.now();
          print("⏱️ WebSocket disconnect time recorded: $_lastDisconnectTime");
          
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          
          _connectionStateController.add(false);
          
          if (_onDisconnectionCallback != null) {
            _onDisconnectionCallback!();
          }
          
          _isConnecting = false;
          
          if (_shouldReconnect && closeCode != 1000 && !_isForceDisconnected) {
            _scheduleReconnection();
          }
        },
        cancelOnError: true,
      );
      
      print("📡 Sending probe heartbeat...");
      _sendProbeHeartbeat();
      
      final verified = await completer.future;
      
      timeoutTimer.cancel();
      
      if (!verified) {
        print("❌ WEB SOCKET CONNECTION FAILED - No response from server");
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
      print("✨ WEB SOCKET CONNECTED SUCCESSFULLY");
      
      _isConnecting = false;
      
    } catch (e, stack) {
      print("❌ WEB SOCKET EXCEPTION");
      print("Error: $e");
      print("Stack: $stack");
      
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

  static Future<void> _safeDisconnect({int closeCode = 1000}) async {
    print("🔧 SAFE DISCONNECT called with code: $closeCode");
    
    try {
      _stopHeartbeat();
      
      if (_wsSubscription != null) {
        print("📝 Cancelling subscription...");
        await _wsSubscription?.cancel();
        _wsSubscription = null;
        print("✅ Subscription cancelled");
      }

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
      _isConnecting = false;
      print("🔧 Safe disconnect completed");
    }
  }

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
    print('🔄 RESETTING CONNECTION STATE');
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _isConnecting = false;
    _isForceDisconnected = false;
    _isManualReconnect = false;
    _shouldReconnect = true;
    _reconnectAttempt = 0;
    _lastDisconnectTime = null;
    _lastConnectTime = null;
    
    print("✅ Flags reset");
    
    await _safeDisconnect();
    
    print('✅ WebSocket connection state reset complete');
  }

  static Future<void> disconnect() async {
    print("🔌 DISCONNECT CALLED");
    
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
    print("🚨 FORCE DISCONNECT CALLED");
    
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

    final delay = _calculateReconnectDelay(_reconnectAttempt);
    
    print("⏰ SCHEDULING RECONNECTION in ${delay.inSeconds}s (attempt $_reconnectAttempt)");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      print("🔄 RECONNECTION TIMER FIRED - Attempt $_reconnectAttempt");
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
📊 WEB SOCKET CONNECTION STATE
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
📊 END STATE
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
    print('🔄 FORCE RECONNECT');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    print("🔄 Setting flags for force reconnect...");
    _isManualReconnect = true;
    _isForceDisconnected = false;
    _shouldReconnect = true;
    _reconnectAttempt = 0;
    _isConnecting = false;
    
    print("✅ Flags set: _isManualReconnect=$_isManualReconnect, _isConnecting=$_isConnecting");
    
    print("📊 State before disconnect:");
    logConnectionState();
    
    try {
      await _forceDisconnectForReconnect();
      
      print("⏱️ Waiting for clean state...");
      await Future.delayed(const Duration(milliseconds: 800));
      
      print("🔍 Checking flags after disconnect:");
      print("  _isManualReconnect: $_isManualReconnect");
      print("  _isConnecting: $_isConnecting");
      print("  _isForceDisconnected: $_isForceDisconnected");
      
      print("🔗 CALLING connect(isManual: true)");
      await connect(isManual: true);
      
    } catch (e) {
      print("❌ Error in forceReconnect: $e");
      _isConnecting = false;
      _isManualReconnect = false;
      throw e;
    }
  }

  static Future<void> _forceDisconnectForReconnect() async {
    print("🔧 _forceDisconnectForReconnect called");
    
    try {
      if (_heartbeatTimer != null) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        print("💓 Heartbeat timer stopped");
      }
      
      if (_wsSubscription != null) {
        print("📝 Cancelling subscription...");
        await _wsSubscription?.cancel();
        _wsSubscription = null;
        print("✅ Subscription cancelled");
      }
      
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
    _reconnectedController.close();
    print("🗑️ WS Manager disposed");
  }
}