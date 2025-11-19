import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'api_config.dart';

/// Global HTTP client that intercepts all errors
class InterceptedHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      debugPrint('🌐 HTTP Request: ${request.method} ${request.url}');
      
      final response = await _inner.send(request);
      
      debugPrint('📥 HTTP Response: ${response.statusCode} ${request.url}');
      
      return response;
    } on http.ClientException catch (e) {
      // ✅ THIS CATCHES "Invalid request method" errors
      debugPrint('❌ ClientException caught: $e');
      
      // Extract the error message
      final errorMessage = e.toString();
      
      // ✅ Check specifically for "Invalid request method" error
      if (errorMessage.contains('Invalid request method')) {
        debugPrint('⚠️ Detected "Invalid request method" - Calling ApiConfig.handleError');
        
        // Call ApiConfig error handler (which will show snackbar)
        ApiConfig.handleError(errorMessage);
      } else {
        // Handle other ClientExceptions
        ApiConfig.handleError(errorMessage);
      }
      
      // Re-throw the error so your app can still handle it
      rethrow;
    } on SocketException catch (e) {
      debugPrint('❌ SocketException caught: $e');
      ApiConfig.handleError('SocketException: ${e.message}');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('❌ TimeoutException caught: $e');
      ApiConfig.handleError('TimeoutException: Request timed out');
      rethrow;
    } catch (e) {
      debugPrint('❌ Unexpected HTTP error: $e');
      ApiConfig.handleError(e.toString());
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Global HTTP instance to use throughout the app
final http.Client globalHttpClient = InterceptedHttpClient();