import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class ApiConfig {
  // --- Base URLs ---
  static const String _coremicronUrl = 'http://192.168.20.102';
  static const String _defaultUrl = 'http://117.241.73.134';

  // Current runtime base URL (auto-determined)
  static String _currentBaseUrl = _coremicronUrl;

  // 🔵 --------------------------------------------------------------
  // 🔵 WEBSOCKET SECTION (NEW)
  // 🔵 --------------------------------------------------------------

  // Local & external WebSocket base URLs
  static const String _localWsBase = 'ws://192.168.20.102';
  static const String _externalWsBase = 'ws://117.241.73.134';

  // Getter: Auto-switch WebSocket base URL
  static String get websocketBase =>
      _currentBaseUrl == _coremicronUrl ? _localWsBase : _externalWsBase;

  // Build any WebSocket endpoint
  static String buildWebSocketUrl(String endpoint, {String? token}) {
    final base = websocketBase; // auto-selected
    final url = "$base$endpoint";
    return token != null ? "$url?token=$token" : url;
  }

  // Example WebSocket channel for monitoring
  static String get monitoringChannel => "/ws/monitoring/";

  // Usage Example:
  // WebSocketChannel.connect(
  //   Uri.parse(ApiConfig.buildWebSocketUrl(ApiConfig.monitoringChannel, token: "XYZ")),
  // );
  // 🔵 --------------------------------------------------------------

  // --- API Paths ---
  static const String _studentsPath = '/api/students';
  static const String _studentLoginPath = '/student_login/';

  // --- Public Getters ---
  static String get baseUrl => _currentBaseUrl;
  static String get studentLoginUrl =>
      '$_currentBaseUrl$_studentsPath$_studentLoginPath';
  static String get studentRegistrationUrl =>
      '$_currentBaseUrl$_studentsPath/register_student/';
  static String get otpVerificationUrl =>
      '$_currentBaseUrl$_studentsPath/verify_registration/';
  static String get loginOtpVerificationUrl =>
      '$_currentBaseUrl$_studentsPath/verify_login/';
  static String get emailLoginScreenUrl =>
      '$_currentBaseUrl$_studentsPath/student_login/';
  static String get profileUrl => '$_currentBaseUrl$_studentsPath/profile/';

  // --- Common Headers ---
  static Map<String, String> get commonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        'User-Agent': 'Flutter App',
      };

  static const Duration requestTimeout = Duration(seconds: 30);

  // --- Callbacks for UI notifications ---
  static void Function(String message, String apiUrl)? onApiSwitch;
  static void Function()? onLocationRequired;

  // NEW: Show snackbars for errors
  static void Function(String message, {bool isError})? onShowSnackbar;

  // --- Coremicron Wi-Fi status ---
  static bool _isOnCoremicronWifi = false;
  static bool get isOnCoremicronWifi => _isOnCoremicronWifi;

  // --- HttpClient ---
  static HttpClient createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return host.contains('devtunnels.ms') ||
            host.contains('ngrok') ||
            host.contains('ngrok-free.app');
      };
    return httpClient;
  }

  // ------ ERROR HANDLER CODE (unchanged) ------
  static void handleError(String errorMessage) async {
    debugPrint('🔍 ApiConfig.handleError called with: $errorMessage');

    if (errorMessage.contains('Invalid request method')) {
      debugPrint('⚠️ Detected "Invalid request method" error');

      final locationStatus = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!locationStatus.isGranted || !serviceEnabled) {
        onShowSnackbar?.call(
          'Make sure your location is ON. Turn on Location Services to continue.',
          isError: true,
        );
        onLocationRequired?.call();
      } else {
        onShowSnackbar?.call(
          'Make sure your location is ON. Turn on Location to continue.',
          isError: true,
        );
      }
      return;
    }

    final isConnectionError = errorMessage.contains('ClientException') ||
        errorMessage.contains('SocketException') ||
        errorMessage.contains('Connection') ||
        errorMessage.contains('Failed host lookup');

    if (isConnectionError) {
      final locationStatus = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (_isOnCoremicronWifi &&
          (!locationStatus.isGranted || !serviceEnabled)) {
        onShowSnackbar?.call(
          'Connection failed! Make sure your Location is ON and try again.',
          isError: true,
        );
        onLocationRequired?.call();
      } else {
        onShowSnackbar?.call(
          'Connection error: ${_extractShortError(errorMessage)}',
          isError: true,
        );
      }
    }
  }

  static String _extractShortError(String fullError) {
    if (fullError.contains('Invalid request method')) {
      return 'Invalid request - Location may be OFF';
    } else if (fullError.contains('ClientException')) {
      return 'Network request failed';
    } else if (fullError.contains('SocketException')) {
      return 'Cannot reach server';
    } else if (fullError.contains('TimeoutException')) {
      return 'Request timed out';
    } else {
      return 'Network error occurred';
    }
  }

  // -------------------------------------------------------------------
  // initializeBaseUrl (UNCHANGED)
  // -------------------------------------------------------------------
  static Future<void> initializeBaseUrl({bool printLogs = true}) async {
    try {
      final previousUrl = _currentBaseUrl;
      final results = await Connectivity().checkConnectivity();

      ConnectivityResult? activeConnection;
      if (results.isNotEmpty) {
        activeConnection = results.first;
      }

      if (activeConnection == ConnectivityResult.wifi) {
        final info = NetworkInfo();
        String? wifiName;

        try {
          wifiName = await info.getWifiName();
          if (wifiName != null &&
              wifiName.startsWith('"') &&
              wifiName.endsWith('"')) {
            wifiName = wifiName.substring(1, wifiName.length - 1);
          }
        } catch (_) {}

        if (wifiName != null &&
            wifiName.toLowerCase().contains('coremicron')) {
          _isOnCoremicronWifi = true;

          final locationStatus = await Permission.locationWhenInUse.status;
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

          if (!locationStatus.isGranted || !serviceEnabled) {
            _currentBaseUrl = _defaultUrl;
            onLocationRequired?.call();
            if (previousUrl != _currentBaseUrl) {
              _notifyApiSwitch('external API (location disabled)', _currentBaseUrl);
            }
            return;
          }

          _currentBaseUrl = _coremicronUrl;
          if (previousUrl != _currentBaseUrl) {
            _notifyApiSwitch('local Coremicron API', _currentBaseUrl);
          }

          _checkCoremicronReachability(previousUrl);
        } else {
          _isOnCoremicronWifi = false;
          _currentBaseUrl = _defaultUrl;
          if (previousUrl != _currentBaseUrl) {
            _notifyApiSwitch('external API', _currentBaseUrl);
          }
        }
      } else if (activeConnection == ConnectivityResult.mobile) {
        _isOnCoremicronWifi = false;
        _currentBaseUrl = _defaultUrl;
        if (previousUrl != _currentBaseUrl) {
          _notifyApiSwitch('external API (mobile data)', _currentBaseUrl);
        }
      } else {
        _isOnCoremicronWifi = false;
        _currentBaseUrl = _defaultUrl;
        if (previousUrl != _currentBaseUrl) {
          _notifyApiSwitch('external API (fallback)', _currentBaseUrl);
        }
      }
    } catch (e) {
      final previousUrl = _currentBaseUrl;
      _isOnCoremicronWifi = false;
      _currentBaseUrl = _defaultUrl;
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (error fallback)', _currentBaseUrl);
      }
    }
  }

  // -------------------------------------------------------------------
  // Check API reachability (UNCHANGED)
  // -------------------------------------------------------------------
  static Future<void> _checkCoremicronReachability(String previousUrl) async {
    try {
      final uri = Uri.parse('$_coremicronUrl/api/ping/');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'ok') return;
      }

      _currentBaseUrl = _defaultUrl;
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (local unreachable)', _currentBaseUrl);
      }
    } catch (e) {
      _currentBaseUrl = _defaultUrl;
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (ping failed)', _currentBaseUrl);
      }
    }
  }

  // -------------------------------------------------------------------
  // Notify API switch
  // -------------------------------------------------------------------
  static void _notifyApiSwitch(String apiName, String apiUrl) {
    onApiSwitch?.call('Switching to $apiName', apiUrl);
  }

  // -------------------------------------------------------------------
  // Auto Listener
  // -------------------------------------------------------------------
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static void startAutoListen({bool updateImmediately = true}) {
    if (_connectivitySub != null) return;

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((result) async {
      await initializeBaseUrl(printLogs: true);
    });

    if (updateImmediately) {
      initializeBaseUrl();
    }
  }

  static void stopAutoListen() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  // -------------------------------------------------------------------
  // Utils
  // -------------------------------------------------------------------
  static void forceBaseUrl(String url) {
    _currentBaseUrl = url;
  }

  static String get currentBaseUrl => _currentBaseUrl;

  static bool get isDevelopment => _currentBaseUrl == _coremicronUrl;

  static String buildUrl(String endpoint) =>
      '$_currentBaseUrl$endpoint';
}
