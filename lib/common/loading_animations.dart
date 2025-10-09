import 'package:flutter/material.dart';
import 'package:coaching_institute_app/common/theme_color.dart';

class StaggeredDotsWave extends StatefulWidget {
  final Size size;
  final Color color;

  const StaggeredDotsWave({
    super.key,
    required this.size,
    this.color = AppColors.primaryYellow,
  });

  @override
  State<StaggeredDotsWave> createState() => _StaggeredDotsWaveState();
}

class _StaggeredDotsWaveState extends State<StaggeredDotsWave> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(5, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 1200),
        vsync: this,
      )..repeat(reverse: true);
    });

    _animations = List.generate(5, (index) {
      return Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(
          parent: _controllers[index],
          curve: Interval(
            (index * 0.1).clamp(0.0, 1.0),
            1.0,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(5, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Transform.scale(
                scale: _animations[index].value,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}