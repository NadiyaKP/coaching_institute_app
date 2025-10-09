
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLifecycleManager extends StatefulWidget {
  final Widget child;
  final Future<void> Function(String startTime, String endTime) onSessionTimeout;
  final VoidCallback onForceLogout;

  const AppLifecycleManager({
    super.key,
    required this.child,
    required this.onSessionTimeout,
    required this.onForceLogout,
  });

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager> with WidgetsBindingObserver {
  Timer? _timer;
  static const int timeoutMinutes = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _saveTimestamp(String key, DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, time.toIso8601String());
  }

  Future<DateTime?> _getTimestamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<void> _clearTimestamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      // App minimized or locked
      final now = DateTime.now();
      await _saveTimestamp('session_end_time', now);
      debugPrint('⏸ App minimized. End time: $now');

      // Start 2-minute timer
      _timer?.cancel();
      _timer = Timer(const Duration(minutes: timeoutMinutes), () async {
        final startTime = await _getTimestamp('session_start_time');
        final endTime = await _getTimestamp('session_end_time');
        if (startTime != null && endTime != null) {
          await widget.onSessionTimeout(startTime.toIso8601String(), endTime.toIso8601String());
          widget.onForceLogout();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      // App resumed
      final endTime = await _getTimestamp('session_end_time');
      if (endTime != null) {
        final now = DateTime.now();
        final diff = now.difference(endTime).inMinutes;

        if (diff < timeoutMinutes) {
          // User returned before timeout
          _showContinueDialog(context);
        } else {
          // User returned after timeout — logout
          final startTime = await _getTimestamp('session_start_time');
          if (startTime != null) {
            await widget.onSessionTimeout(startTime.toIso8601String(), endTime.toIso8601String());
          }
          widget.onForceLogout();
        }
      }
    }
  }

  void _showContinueDialog(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Continue to the app?"),
          content: const Text("Do you want to continue using the app?"),
          actions: [
            TextButton(
              onPressed: () async {
                await _clearTimestamp('session_end_time');
                Navigator.of(ctx).pop();
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
