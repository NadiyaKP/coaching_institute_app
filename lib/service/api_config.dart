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
  static const String _coremicronUrl = 'http://192.168.20.99';
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

  // --- Callbacks for UI notifications ---
  static void Function(String message, String apiUrl)? onApiSwitch;
  static void Function()? onLocationRequired;
  
  // ✅ NEW: Callback for showing error snackbars
  static void Function(String message, {bool isError})? onShowSnackbar;

  // --- Track if we're on Coremicron Wi-Fi ---
  static bool _isOnCoremicronWifi = false;
  static bool get isOnCoremicronWifi => _isOnCoremicronWifi;

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

 // ✅ ENHANCED: Public method to handle errors (called from HttpService)
static void handleError(String errorMessage) async {
  debugPrint('🔍 ApiConfig.handleError called with: $errorMessage');
  
  // Check if error is the specific "Invalid request method" error
  if (errorMessage.contains('Invalid request method')) {
    debugPrint('⚠️ Detected "Invalid request method" error');
    
    // Check if we're on Coremicron Wi-Fi
    if (_isOnCoremicronWifi) {
      // Check location status
      final locationStatus = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!locationStatus.isGranted || !serviceEnabled) {
        debugPrint('❌ Location is disabled - showing error message');
        
        // Show specific location error message
        onShowSnackbar?.call(
          'Make sure your location is ON. Turn on Location Services to continue.',
          isError: true,
        );
        
        // Also trigger the location required dialog
        onLocationRequired?.call();
      } else {
        // Location is enabled but still getting this error
        onShowSnackbar?.call(
          'Make sure your location is ON. Turn on Location to continue.',
          isError: true,
        );
      }
    } else {
      // ✅ FIXED: Not on Coremicron Wi-Fi but still getting "Invalid request method"
      // This is likely a location issue too
      onShowSnackbar?.call(
        'Make sure your location is ON. Turn on Location to continue.',
        isError: true,
      );
      
      // Also trigger the location required callback
      onLocationRequired?.call();
    }
    return; // Exit early after handling specific error
  }
  
  // Handle other connection errors
  final isConnectionError = errorMessage.contains('ClientException') ||
      errorMessage.contains('SocketException') ||
      errorMessage.contains('Connection') ||
      errorMessage.contains('Failed host lookup');

  if (isConnectionError) {
    // Check if we're on Coremicron Wi-Fi
    if (_isOnCoremicronWifi) {
      // Check location status
      final locationStatus = await Permission.locationWhenInUse.status;
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!locationStatus.isGranted || !serviceEnabled) {
        // Location is disabled - show specific message
        onShowSnackbar?.call(
          'Connection failed! Make sure your Location is ON and try again.',
          isError: true,
        );
        
        // Also trigger the location required callback
        onLocationRequired?.call();
      } else {
        // Location is enabled but still connection error
        onShowSnackbar?.call(
          'Connection error: ${_extractShortError(errorMessage)}',
          isError: true,
        );
      }
    } else {
      // Not on Coremicron Wi-Fi - show general error
      onShowSnackbar?.call(
        'Connection error: ${_extractShortError(errorMessage)}',
        isError: true,
      );
    }
  }
}

// ✅ ENHANCED: Extract short error message from full error
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

  static Future<void> initializeBaseUrl({bool printLogs = true}) async {
    try {
      // Store previous URL to detect changes
      final previousUrl = _currentBaseUrl;
      final previousIsOnCoremicron = _isOnCoremicronWifi;

      final results = await Connectivity().checkConnectivity();

      ConnectivityResult? activeConnection;
      if (results.isNotEmpty) {
        activeConnection = results.first;
      }

      if (printLogs) print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

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

        if (printLogs) print('ApiConfig: Connected Wi-Fi SSID => "$wifiName"');

        // ✅ Check if connected to Coremicron Wi-Fi
        if (wifiName != null && wifiName.toLowerCase().contains('coremicron')) {
          _isOnCoremicronWifi = true;

          // Check both permission AND location services using Geolocator
          PermissionStatus locationStatus = await Permission.locationWhenInUse.status;
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

          if (printLogs) {
            print('ApiConfig: ✅ Coremicron Wi-Fi detected!');
            print('ApiConfig: Location permission => $locationStatus');
            print('ApiConfig: Location services => ${serviceEnabled ? "ENABLED" : "DISABLED"}');
          }

          // If location permission not granted OR location services disabled
          if (!locationStatus.isGranted || !serviceEnabled) {
            if (printLogs) {
              if (!locationStatus.isGranted) {
                print('ApiConfig: ⚠️ Location permission NOT granted');
              }
              if (!serviceEnabled) {
                print('ApiConfig: ⚠️ Location services DISABLED on device');
              }
              print('ApiConfig: 🔀 Switching to EXTERNAL API');
            }
            
            _currentBaseUrl = _defaultUrl;
            
            // Trigger location required callback only if we're on Coremicron
            onLocationRequired?.call();

            // Notify if URL changed
            if (previousUrl != _currentBaseUrl) {
              _notifyApiSwitch('external API (location disabled)', _currentBaseUrl);
            }
            
            if (printLogs) print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return; // Exit early, don't try local API
          }

          // Both permission granted AND location services enabled
          _currentBaseUrl = _coremicronUrl;
          if (printLogs) {
            print('ApiConfig: ✅ Location fully enabled');
            print('ApiConfig: 🔀 Switching to LOCAL Coremicron API');
            print('ApiConfig: Using => $_currentBaseUrl');
          }

          // Notify if URL changed
          if (previousUrl != _currentBaseUrl) {
            _notifyApiSwitch('local Coremicron API', _currentBaseUrl);
          }

          // 🔹 Test reachability of local API asynchronously
          _checkCoremicronReachability(previousUrl);
        } else {
          // Not on Coremicron Wi-Fi
          _isOnCoremicronWifi = false;
          _currentBaseUrl = _defaultUrl;
          if (printLogs) {
            print('ApiConfig: ℹ️ Not on Coremicron Wi-Fi');
            print('ApiConfig: 🔀 Using EXTERNAL API');
            print('ApiConfig: Using => $_currentBaseUrl');
          }

          // Notify if URL changed
          if (previousUrl != _currentBaseUrl) {
            _notifyApiSwitch('external API', _currentBaseUrl);
          }
        }
      } else if (activeConnection == ConnectivityResult.mobile) {
        _isOnCoremicronWifi = false;
        _currentBaseUrl = _defaultUrl;
        if (printLogs) {
          print('ApiConfig: 📱 Mobile data detected');
          print('ApiConfig: 🔀 Using EXTERNAL API');
          print('ApiConfig: Using => $_currentBaseUrl');
        }

        // Notify if URL changed
        if (previousUrl != _currentBaseUrl) {
          _notifyApiSwitch('external API (mobile data)', _currentBaseUrl);
        }
      } else {
        _isOnCoremicronWifi = false;
        _currentBaseUrl = _defaultUrl;
        if (printLogs) {
          print('ApiConfig: ⚠️ No connectivity detected (fallback)');
          print('ApiConfig: Using => $_currentBaseUrl');
        }

        // Notify if URL changed
        if (previousUrl != _currentBaseUrl) {
          _notifyApiSwitch('external API (fallback)', _currentBaseUrl);
        }
      }

      if (printLogs) print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      final previousUrl = _currentBaseUrl;
      _isOnCoremicronWifi = false;
      _currentBaseUrl = _defaultUrl;
      if (printLogs) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('ApiConfig: ❌ Initialization error -> $e');
        print('ApiConfig: Using fallback => $_currentBaseUrl');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      // Notify if URL changed
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (error fallback)', _currentBaseUrl);
      }
    }
  }

  // -------------------------------------------------------------------
  // ✅ Check local server reachability asynchronously
  // -------------------------------------------------------------------
  static Future<void> _checkCoremicronReachability(String previousUrl) async {
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
      
      // Notify URL change
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (local unreachable)', _currentBaseUrl);
      }
    } on TimeoutException {
      print('⏳ Ping timed out (>20s) → Switching to default URL');
      _currentBaseUrl = _defaultUrl;
      
      // Notify URL change
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (timeout)', _currentBaseUrl);
      }
    } catch (e) {
      print('❌ Error pinging Coremicron API → switching to default URL: $e');
      _currentBaseUrl = _defaultUrl;
      
      // Notify URL change
      if (previousUrl != _currentBaseUrl) {
        _notifyApiSwitch('external API (ping failed)', _currentBaseUrl);
      }
    }
  }

  // -------------------------------------------------------------------
  // Notify API Switch
  // -------------------------------------------------------------------
  static void _notifyApiSwitch(String apiName, String apiUrl) {
    onApiSwitch?.call('Switching to $apiName', apiUrl);
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