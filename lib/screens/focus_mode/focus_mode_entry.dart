import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/timer_service.dart';

class FocusModeEntryScreen extends StatefulWidget {
  const FocusModeEntryScreen({super.key});

  @override
  State<FocusModeEntryScreen> createState() => _FocusModeEntryScreenState();
}

class _FocusModeEntryScreenState extends State<FocusModeEntryScreen> {
  final TimerService _timerService = TimerService();
  late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeData();
  }

  Future<void> _initializeData() async {
    await _timerService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Focus Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF43E97B).withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF43E97B),
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.timer,
                    size: 60,
                    color: Color(0xFF43E97B),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Enter Focus Mode',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Description
                const Text(
                  'Focus on your studies without distractions.\nStart your dedicated study session now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Today's Statistics
                ValueListenableBuilder<Duration>(
                  valueListenable: _timerService.focusTimeToday,
                  builder: (context, focusTime, _) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable: _timerService.breakTimeToday,
                      builder: (context, breakTime, _) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                icon: Icons.timer,
                                value: _formatDuration(focusTime),
                                label: 'Focus Today',
                                color: const Color(0xFF43E97B),
                              ),
                              _buildStatItem(
                                icon: Icons.coffee,
                                value: _formatDuration(breakTime),
                                label: 'Break Today',
                                color: const Color(0xFFF4B400),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                
                const SizedBox(height: 40),
                
                // Start Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _timerService.startFocusMode();
                      // Navigate to home screen with focus mode active
                      if (mounted) {
                        Navigator.pushReplacementNamed(
                          context, 
                          '/home',
                          arguments: {'isFocusMode': true}
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43E97B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF43E97B).withOpacity(0.3),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text(
                          'Start Focus Session',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Skip for now button (for testing)
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context, 
                      '/home',
                      arguments: {'isFocusMode': false}
                    );
                  },
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  void dispose() {
    // CRITICAL: Do NOT dispose the TimerService singleton!
    // It's shared across the entire app and disposing it will break other screens
    // _timerService.dispose(); // ❌ REMOVED THIS LINE
    super.dispose();
  }
}