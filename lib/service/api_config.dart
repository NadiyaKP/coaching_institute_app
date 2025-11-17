import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  // --- Base URLs ---
  static const String _coremicronUrl = 'http://192.168.20.4';
  static const String _defaultUrl = 'http://117.241.73.134';

  // Current runtime base URL (auto-determined)
  static String _currentBaseUrl = _coremicronUrl;

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

  // --- HttpClient ---
  static HttpClient createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Allow devtunnels/ngrok certificates (for development only)
        return host.contains('devtunnels.ms') ||
            host.contains('ngrok') ||
            host.contains('ngrok-free.app');
      };
    return httpClient;
  }

 
  static Future<void> initializeBaseUrl({bool printLogs = true}) async {
    try {
      // Request permission (needed to read Wi-Fi SSID)
      try {
        await Permission.locationWhenInUse.request();
      } catch (_) {}

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
              wifiName.length >= 2 &&
              wifiName.startsWith('"') &&
              wifiName.endsWith('"')) {
            wifiName = wifiName.substring(1, wifiName.length - 1);
          }
        } catch (e) {
          if (printLogs) print('ApiConfig: failed to read wifi name: $e');
          wifiName = null;
        }

        if (printLogs) print('ApiConfig: connected Wi-Fi SSID => $wifiName');

        // ✅ If connected to institution Wi-Fi, use local URL
        if (wifiName != null && wifiName.toLowerCase().contains('coremicron')) {
          _currentBaseUrl = _coremicronUrl;
          if (printLogs) {
            print('ApiConfig: trying Coremicron local URL => $_currentBaseUrl');
          }

          // 🔹 Test reachability of local API asynchronously
          _checkCoremicronReachability();
        } else {
          _currentBaseUrl = _defaultUrl;
          if (printLogs) {
            print('ApiConfig: using default external URL => $_currentBaseUrl');
          }
        }
      } else if (activeConnection == ConnectivityResult.mobile) {
        _currentBaseUrl = _defaultUrl;
        if (printLogs) {
          print('ApiConfig: mobile data detected, using default external URL => $_currentBaseUrl');
        }
      } else {
        _currentBaseUrl = _defaultUrl;
        if (printLogs) {
          print('ApiConfig: no connectivity (fallback) => $_currentBaseUrl');
        }
      }
    } catch (e) {
      _currentBaseUrl = _defaultUrl;
      if (printLogs) print('ApiConfig: initialization error -> $e');
    }
  }

  // -------------------------------------------------------------------
  // ✅ Check local server reachability asynchronously
  // -------------------------------------------------------------------
  static Future<void> _checkCoremicronReachability() async {
    try {
      final uri = Uri.parse('$_coremicronUrl/api/ping/');
      final stopwatch = Stopwatch()..start();

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 20), onTimeout: () {
        throw TimeoutException("Ping timeout");
      });

      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'ok') {
          print(
              '✅ Local Coremicron API reachable (${stopwatch.elapsedMilliseconds} ms)');
          return; // Stay on local URL
        }
      }

      // ❌ Invalid response, switch to default
      print('⚠️ Invalid ping response, switching to default URL');
      _currentBaseUrl = _defaultUrl;
    } on TimeoutException {
      print('⏳ Ping timed out (>20s) → Switching to default URL');
      _currentBaseUrl = _defaultUrl;
    } catch (e) {
      print('❌ Error pinging Coremicron API → switching to default URL: $e');
      _currentBaseUrl = _defaultUrl;
    }
  }

  // -------------------------------------------------------------------
  // AUTO LISTENER
  // -------------------------------------------------------------------
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static void startAutoListen({bool updateImmediately = true}) {
    if (_connectivitySub != null) return;

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
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
  // UTILITIES
  // -------------------------------------------------------------------
  static void forceBaseUrl(String url) {
    _currentBaseUrl = url;
  }

  static String get currentBaseUrl => _currentBaseUrl;

  static bool get isDevelopment => _currentBaseUrl == _coremicronUrl;

  static String buildUrl(String endpoint) => '$_currentBaseUrl$endpoint';
}
