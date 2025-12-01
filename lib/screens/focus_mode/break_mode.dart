import 'package:flutter/material.dart';
import '../../service/timer_service.dart';

class BreakModeScreen extends StatefulWidget {
  const BreakModeScreen({super.key});

  @override
  State<BreakModeScreen> createState() => _BreakModeScreenState();
}

class _BreakModeScreenState extends State<BreakModeScreen> {
  // Get the singleton instance instead of creating a new one
  late final TimerService _timerService;
  
  @override
  void initState() {
    super.initState();
    // Initialize the timer service (use singleton pattern if available)
    // For example: _timerService = TimerService.instance;
    // Or if you're using Provider/GetIt: _timerService = context.read<TimerService>();
    _timerService = TimerService(); // Replace with proper singleton access
    _startTimer();
  }

  void _startTimer() {
    // UI updates are handled by the timer service's ValueNotifier
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4B400),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Break Icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 4,
                  ),
                ),
                child: const Icon(
                  Icons.coffee,
                  size: 70,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Break Time',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Description
              const Text(
                'Take a well-deserved break.\nRelax and recharge before your next focus session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Timer Display
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ValueListenableBuilder<Duration>(
                  valueListenable: _timerService.breakTimeToday,
                  builder: (context, breakTime, _) {
                    return Column(
                      children: [
                        const Text(
                          'Break Duration',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _formatDuration(breakTime),
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 40),
              
              // End Break Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    await _timerService.resumeFocusMode();
                    // Navigate back to home with focus mode active
                    if (mounted) {
                      Navigator.pushReplacementNamed(
                        context, 
                        '/home',
                        arguments: {'isFocusMode': true}
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'End Break & Resume Focus',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF4B400),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // View Stats Button
              TextButton(
                onPressed: () {
                  _showTodayStats();
                },
                child: const Text(
                  'View Today\'s Statistics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTodayStats() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Today\'s Statistics'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow(
                'Focus Time',
                _formatDuration(_timerService.focusTimeToday.value),
                const Color(0xFF43E97B),
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                'Break Time',
                _formatDuration(_timerService.breakTimeToday.value),
                const Color(0xFFF4B400),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
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
    // DO NOT dispose the timer service here if it's a singleton
    // Only dispose if you own the instance
    super.dispose();
  }
}