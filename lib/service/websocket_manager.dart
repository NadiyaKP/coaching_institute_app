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

  static int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);

  static final StreamController<dynamic> _messageController =
      StreamController.broadcast();

  static Stream<dynamic> get stream => _messageController.stream;

  // =============================
  // CONNECT
  // =============================
  static Future<void> connect() async {
    if (_isConnecting) {
      print("⏳ Already connecting...");
      return;
    }

    _isConnecting = true;

    try {
      // -----------------------------------
      // FETCH TOKEN
      // -----------------------------------
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('accessToken') ?? '';

      if (token.isEmpty) {
        print("❌ No token found. Cannot connect WebSocket.");
        _isConnecting = false;
        return;
      }

      final url = "${ApiConfig.websocketBase}/ws/monitoring/?token=$token";
      print("🔗 Connecting WebSocket to: $url");

      // -----------------------------------
      // CLOSE PREVIOUS CONNECTION
      // -----------------------------------
      await disconnect();

      // -----------------------------------
      // CREATE CHANNEL
      // -----------------------------------
      _channel = WebSocketChannel.connect(Uri.parse(url));

      // -----------------------------------
      // START CONNECTION VERIFICATION
      // -----------------------------------
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
          _scheduleReconnection();
        },
        onDone: () {
          print("🔌 WebSocket Closed");

          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(false);
          }

          if (_channel?.closeCode != 1000) {
            _scheduleReconnection();
          }
        },
        cancelOnError: true,
      );

      // -----------------------------------
      // SEND PROBE
      // -----------------------------------
      print("📡 Sending probe heartbeat...");
      send({"event": "heartbeat", "probe": true});

      // -----------------------------------
      // WAIT FOR VERIFICATION
      // -----------------------------------
      final verified = await completer.future;

      if (!verified) {
        print("❌❌❌ WEB SOCKET CONNECTION FAILED - CANNOT RECEIVE MESSAGES");

        await _wsSubscription?.cancel();
        _wsSubscription = null;

        try {
          await _channel?.sink.close();
        } catch (_) {}

        _channel = null;
        _isConnecting = false;

        _scheduleReconnection();
        return;
      }

      print("✅ WebSocket Connection Verified");

      // -----------------------------------
      // START HEARTBEAT TIMER
      // -----------------------------------
      _startHeartbeat();

      print("✨ WebSocket Connected Successfully");
      _isConnecting = false;
    } catch (e, stack) {
      print("❌ WebSocket exception: $e");
      print(stack);

      _isConnecting = false;
      _scheduleReconnection();
    }
  }

  // =============================
  // HEARTBEAT
  // =============================
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

  // =============================
  // SEND MESSAGE
  // =============================
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
      _scheduleReconnection();
    }
  }

  // =============================
  // DISCONNECT
  // =============================
  static Future<void> disconnect() async {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      await _wsSubscription?.cancel();
      _wsSubscription = null;
    } catch (_) {}

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _isConnecting = false;

    print("🔌 WS Disconnected");
  }

  // =============================
  // RECONNECTION LOGIC
  // =============================
  static void _scheduleReconnection() {
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

  // =============================
  // STATUS HELPERS
  // =============================
  static bool get isConnected =>
      _channel != null &&
      _wsSubscription != null &&
      (_channel?.closeCode == null);

  static String get connectionStatus {
    if (_isConnecting) return "connecting";
    if (isConnected) return "connected";
    return "disconnected";
  }

  // =============================
  // DISPOSE
  // =============================
  static void dispose() {
    disconnect();
    _messageController.close();
    print("🗑️ WS Manager disposed");
  }
}