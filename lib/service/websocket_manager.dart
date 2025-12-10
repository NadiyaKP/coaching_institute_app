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

  static int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);

  static final StreamController<dynamic> _messageController =
      StreamController.broadcast();
  
  // 🆕 NEW: Connection state stream
  static final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  
  static Stream<dynamic> get stream => _messageController.stream;
  static Stream<bool> get connectionStateStream => _connectionStateController.stream; // 🆕 NEW

  static Future<void> connect() async {
    if (_isConnecting || _isForceDisconnected) {
      print("⏳ Already connecting or force disconnected...");
      return;
    }

    _isConnecting = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken') ?? '';

      if (token.isEmpty) {
        print("❌ No token found. Cannot connect WebSocket.");
        _isConnecting = false;
        return;
      }

      final url = "${ApiConfig.websocketBase}/ws/monitoring/?token=$token";
      print("🔗 Connecting WebSocket to: $url");

      await disconnect();

      _channel = WebSocketChannel.connect(Uri.parse(url));

      bool firstMessageReceived = false;
      final completer = Completer<bool>();

      final timeoutTimer = Timer(const Duration(seconds: 8), () {
        if (!completer.isCompleted) {
          print("⏰ Timeout - No response from server");
          completer.complete(false);
        }
      });

      _wsSubscription = _channel!.stream.listen(
        (event) {
          print("📩 WebSocket Received: $event");

          if (!firstMessageReceived) {
            firstMessageReceived = true;
            timeoutTimer.cancel();
            completer.complete(true);
            
            // 🆕 NEW: Notify connection established
            _connectionStateController.add(true);
          }

          _messageController.add(event);
          _reconnectAttempt = 0;
        },
        onError: (error) {
          print("❌ WebSocket Error: $error");

          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(false);
          }

          _messageController.addError(error);
          
          // 🆕 NEW: Notify connection lost
          _connectionStateController.add(false);
          
          if (!_isForceDisconnected) _scheduleReconnection();
        },
        onDone: () {
          print("🔌 WebSocket Closed");

          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(false);
          }

          // 🆕 NEW: Notify connection closed
          _connectionStateController.add(false);
          
          if (_channel?.closeCode != 1000 && !_isForceDisconnected) {
            _scheduleReconnection();
          }
        },
        cancelOnError: true,
      );

      print("📡 Sending probe heartbeat...");
      send({"event": "heartbeat", "probe": true});

      final verified = await completer.future;

      if (!verified) {
        print("❌❌❌ WEB SOCKET CONNECTION FAILED");

        await _wsSubscription?.cancel();
        _wsSubscription = null;

        try {
          await _channel?.sink.close();
        } catch (_) {}

        _channel = null;
        _isConnecting = false;
        
        // 🆕 NEW: Notify connection failed
        _connectionStateController.add(false);

        if (!_isForceDisconnected) _scheduleReconnection();
        return;
      }

      print("✅ WebSocket Connection Verified");

      _startHeartbeat();

      print("✨ WebSocket Connected Successfully");
      _isConnecting = false;
    } catch (e, stack) {
      print("❌ WebSocket exception: $e");
      print(stack);

      _isConnecting = false;
      // 🆕 NEW: Notify connection error
      _connectionStateController.add(false);
      if (!_isForceDisconnected) _scheduleReconnection();
    }
  }

  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) {
        try {
          send({"event": "heartbeat"});
          print("💓 Heartbeat sent");
        } catch (e) {
          print("❌ Heartbeat failed: $e");
        }
      },
    );
  }

  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  static void send(dynamic data) {
    if (_channel == null) {
      print("⚠️ Cannot send WS message - channel null");
      return;
    }

    try {
      final jsonData = (data is String) ? data : jsonEncode(data);
      _channel!.sink.add(jsonData);
      print("📤 WebSocket Sent: $jsonData");
    } catch (e) {
      print("❌ Failed to send WS message: $e");
      if (!_isForceDisconnected) _scheduleReconnection();
    }
  }

  static Future<void> disconnect() async {
    print("🔌 Starting WebSocket disconnect process...");
    
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _isConnecting = false;

    if (_wsSubscription != null) {
      try {
        await _wsSubscription?.cancel();
        print("✅ WebSocket subscription cancelled");
      } catch (e) {
        print("⚠️ Error cancelling subscription: $e");
      }
      _wsSubscription = null;
    }

    if (_channel != null) {
      try {
        if (_channel?.sink != null) {
          await _channel?.sink.close(1000, "Normal disconnect");
        }
        print("✅ WebSocket channel closed");
      } catch (e) {
        print("⚠️ Error closing channel: $e");
        try {
          _channel = null;
        } catch (_) {}
      }
      _channel = null;
    }
    
    // 🆕 NEW: Notify disconnection
    _connectionStateController.add(false);

    print("🔌 WebSocket Disconnected Successfully");
  }

  static Future<void> forceDisconnect() async {
    print("🚨 Force disconnecting WebSocket...");
    
    _isForceDisconnected = true;
    
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _isConnecting = false;
    
    try {
      _wsSubscription?.cancel();
      _wsSubscription = null;
      print("✅ Subscription forcefully cancelled");
    } catch (e) {
      print("⚠️ Error forcefully cancelling subscription: $e");
    }
    
    if (_channel != null) {
      try {
        await _channel?.sink.close(1000, "User logout");
        print("✅ Channel forcefully closed");
      } catch (e) {
        print("⚠️ Error forcefully closing channel: $e");
      }
      _channel = null;
    }
    
    // 🆕 NEW: Notify force disconnection
    _connectionStateController.add(false);
    
    print("🚨 WebSocket Force Disconnected");
  }

  static void resetForceDisconnect() {
    _isForceDisconnected = false;
    print("🔄 Force disconnect flag reset");
  }

  static void _scheduleReconnection() {
    if (_isForceDisconnected) {
      print("⛔ Force disconnected - no reconnection");
      return;
    }
    
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      print("⛔ Max reconnect attempts reached");
      return;
    }

    _reconnectAttempt++;

    final baseDelay = _initialReconnectDelay * (1 << (_reconnectAttempt - 1));
    final jitter = Duration(seconds: Random().nextInt(2));
    final delay = baseDelay + jitter;

    print("⏰ Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  static bool get isConnected =>
      _channel != null &&
      _wsSubscription != null &&
      (_channel?.closeCode == null) &&
      !_isForceDisconnected;

  static String get connectionStatus {
    if (_isForceDisconnected) return "force_disconnected";
    if (_isConnecting) return "connecting";
    if (isConnected) return "connected";
    return "disconnected";
  }

  static void logConnectionState() {
    print("""
  📊 WebSocket Connection State:
    Channel: ${_channel != null ? "Exists" : "Null"}
    Subscription: ${_wsSubscription != null ? "Exists" : "Null"}
    Heartbeat Timer: ${_heartbeatTimer != null ? "Active" : "Inactive"}
    Reconnect Timer: ${_reconnectTimer != null ? "Active" : "Inactive"}
    Is Connecting: $_isConnecting
    Is Force Disconnected: $_isForceDisconnected
    Reconnect Attempt: $_reconnectAttempt
    Connection Status: $connectionStatus
  """);
  }

  static Future<void> cleanReconnect() async {
    print("🔄 Performing clean reconnect...");
    resetForceDisconnect();
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connect();
  }

  static void dispose() {
    disconnect();
    _messageController.close();
    _connectionStateController.close(); // 🆕 NEW: Close connection state stream
    print("🗑️ WS Manager disposed");
  }
}