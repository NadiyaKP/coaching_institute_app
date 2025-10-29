import 'package:flutter/material.dart';
import '../common/theme_color.dart';
import 'dart:math' as math;

class StreakChallengeSheet extends StatefulWidget {
  final int currentStreak;
  final int longestStreak;

  const StreakChallengeSheet({
    Key? key,
    required this.currentStreak,
    required this.longestStreak,
  }) : super(key: key);

  @override
  State<StreakChallengeSheet> createState() => _StreakChallengeSheetState();
}

class _StreakChallengeSheetState extends State<StreakChallengeSheet>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _flameController;
  late AnimationController _particleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _flameController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _particleController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _flameController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool hasStreak = widget.currentStreak > 0;

    return Container(
      height: screenHeight * 0.72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color(0xFFFAFAFA),
          ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Main Flame Illustration
                  AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: _buildFlameScene(hasStreak),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Motivational Message
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildMessageCard(hasStreak),
                  ),

                  const SizedBox(height: 28),

                  // Highest Streak Card
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildHighestStreakCard(),
                  ),

                  const SizedBox(height: 28),

                  // Daily Learning Card
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildDailyLearningCard(),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlameScene(bool hasStreak) {
    return Container(
      height: 280,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: hasStreak
              ? [
                  const Color(0xFF1A237E).withOpacity(0.95),
                  const Color(0xFF283593),
                  const Color(0xFF3949AB),
                ]
              : [
                  const Color(0xFF37474F),
                  const Color(0xFF455A64),
                  const Color(0xFF546E7A),
                ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: hasStreak
                ? const Color(0xFF3949AB).withOpacity(0.4)
                : Colors.black26,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Stars background
          ...List.generate(20, (index) {
            final random = math.Random(index);
            return Positioned(
              left: random.nextDouble() * 300 + 20,
              top: random.nextDouble() * 200 + 20,
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  final offset = ((_particleController.value + index * 0.1) % 1.0);
                  return Opacity(
                    opacity: (math.sin(offset * math.pi * 2) * 0.5 + 0.5) * 0.6,
                    child: Container(
                      width: 2 + random.nextDouble() * 2,
                      height: 2 + random.nextDouble() * 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),

          // Ground/Platform
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1B5E20).withOpacity(0.8),
                    const Color(0xFF2E7D32),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
            ),
          ),

          // Campfire base
          Positioned(
            bottom: 55,
            left: 0,
            right: 0,
            child: Center(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Wood logs
                  Transform.rotate(
                    angle: -0.3,
                    child: Container(
                      width: 60,
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF4E342E),
                            Color(0xFF5D4037),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: 0.3,
                    child: Container(
                      width: 60,
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF5D4037),
                            Color(0xFF6D4C41),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Flame with number - only show if hasStreak
          if (hasStreak)
            Positioned(
              bottom: 58,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _flameController,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(120, 140),
                          painter: RealisticFlamePainter(
                            hasStreak: hasStreak,
                            animationValue: _flameController.value,
                          ),
                        ),
                        // Number inside flame
                        Positioned(
                          bottom: 40,
                          child: Text(
                            '${widget.currentStreak}',
                            style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                              shadows: [
                                Shadow(
                                  color: Color(0xFFFF6B00),
                                  blurRadius: 20,
                                ),
                                Shadow(
                                  color: Color(0xFFFFD54F),
                                  blurRadius: 40,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

          Positioned(
            bottom: 50,
            left: 50,
            child: _buildRealisticStudent(
              hasStreak: hasStreak,
              isLeftSide: true,
            ),
          ),
          Positioned(
            bottom: 50,
            right: 50,
            child: _buildRealisticStudent(
              hasStreak: hasStreak,
              isLeftSide: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealisticStudent({
    required bool hasStreak,
    required bool isLeftSide,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 1200),
      tween: Tween<double>(begin: isLeftSide ? -80.0 : 80.0, end: 0.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(value, 0),
          child: SizedBox(
            width: 50,
            height: 70,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Head
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFE0B2),
                              Color(0xFFFFCC80),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Hair
                            Positioned(
                              top: 2,
                              left: 2,
                              right: 2,
                              child: Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      isLeftSide
                                          ? const Color(0xFF3E2723)
                                          : const Color(0xFF4E342E),
                                      isLeftSide
                                          ? const Color(0xFF4E342E)
                                          : const Color(0xFF5D4037),
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(14),
                                    topRight: Radius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            // Face details
                            Positioned(
                              top: 13,
                              left: 8,
                              child: Row(
                                children: [
                                  // Eyes
                                  Container(
                                    width: 3,
                                    height: 3,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1A237E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 3,
                                    height: 3,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1A237E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Smile
                            Positioned(
                              bottom: 6,
                              left: 9,
                              child: Container(
                                width: 10,
                                height: 5,
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Color(0xFFD84315),
                                      width: 1.5,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 32,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLeftSide
                                ? [
                                    const Color(0xFF1976D2),
                                    const Color(0xFF1565C0),
                                  ]
                                : [
                                    const Color(0xFFD32F2F),
                                    const Color(0xFFC62828),
                                  ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 14,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF424242),
                                  Color(0xFF212121),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 10,
                            height: 14,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF424242),
                                  Color(0xFF212121),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
      
                Positioned(
                  bottom: 20,
                  left: 8,
                  child: Container(
                    width: 18,
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFF9C4),
                          Color(0xFFFFF59D),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: const Color(0xFFFBC02D),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 3,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 1,
                        color: const Color(0xFFF57F17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageCard(bool hasStreak) {

    final bool isMissedStreak = widget.currentStreak == 0 && widget.longestStreak != 0;
    final bool isNewUser = widget.currentStreak == 0 && widget.longestStreak == 0;

    IconData messageIcon;
    String messageText;
    List<Color> gradientColors;

    if (hasStreak) {
      messageIcon = Icons.local_fire_department;
      messageText = "Great job! Keep your streak alive!";
      gradientColors = [
        const Color(0xFFFFD54F),
        const Color(0xFFFFB300),
      ];
    } else if (isMissedStreak) {
      messageIcon = Icons.restart_alt;
      messageText = "Don't give up! You missed your streak. Let's start again.";
      gradientColors = [
        const Color(0xFF90CAF9),
        const Color(0xFF64B5F6),
      ];
    } else {
      // isNewUser
      messageIcon = Icons.rocket_launch;
      messageText = "Start maintaining streak by learning every day";
      gradientColors = [
        const Color(0xFF81C784),
        const Color(0xFF66BB6A),
      ];
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors[1].withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              messageIcon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              messageText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighestStreakCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFFFFA000),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFA000).withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Best Streak',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.longestStreak}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A237E),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyLearningCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8EAF6),
            Color(0xFFC5CAE9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9FA8DA).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF5C6BC0),
                  Color(0xFF3F51B5),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3F51B5).withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.lightbulb,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Come back every day to learn something new and keep your streak alive!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RealisticFlamePainter extends CustomPainter {
  final bool hasStreak;
  final double animationValue;

  RealisticFlamePainter({
    required this.hasStreak,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2 + 20;

    // Flame animation flicker
    final flicker = math.sin(animationValue * math.pi * 2) * 4;
    final flicker2 = math.cos(animationValue * math.pi * 2) * 3;

    if (hasStreak) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD54F).withOpacity(0.3),
            const Color(0xFFFFA726).withOpacity(0.15),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(centerX, centerY + 10),
            radius: 90,
          ),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

      canvas.drawCircle(Offset(centerX, centerY + 10), 90, glowPaint);
    }

    _drawFlameLayer(
      canvas,
      centerX,
      centerY,
      0.9,
      flicker * 0.8,
      hasStreak
          ? [
              const Color(0xFFFF6B00),
              const Color(0xFFFF8F00),
              const Color(0xFFFFA726),
            ]
          : [
              const Color(0xFF616161),
              const Color(0xFF757575),
              const Color(0xFF9E9E9E),
            ],
    );

    _drawFlameLayer(
      canvas,
      centerX,
      centerY,
      0.75,
      flicker2,
      hasStreak
          ? [
              const Color(0xFFFFA726),
              const Color(0xFFFFB74D),
              const Color(0xFFFFD54F),
            ]
          : [
              const Color(0xFF757575),
              const Color(0xFF9E9E9E),
              const Color(0xFFBDBDBD),
            ],
    );

    _drawFlameLayer(
      canvas,
      centerX,
      centerY,
      0.6,
      flicker * 1.2,
      hasStreak
          ? [
              const Color(0xFFFFD54F),
              const Color(0xFFFFE082),
              const Color(0xFFFFECB3),
            ]
          : [
              const Color(0xFF9E9E9E),
              const Color(0xFFBDBDBD),
              const Color(0xFFE0E0E0),
            ],
    );

    if (hasStreak) {
      final tipPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withOpacity(0.9),
            const Color(0xFFFFF59D).withOpacity(0.7),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(centerX, centerY - 55 + flicker),
            radius: 20,
          ),
        );

      canvas.drawCircle(
        Offset(centerX, centerY - 55 + flicker),
        20,
        tipPaint,
      );
    }
  }

  void _drawFlameLayer(
    Canvas canvas,
    double centerX,
    double centerY,
    double scale,
    double flicker,
    List<Color> colors,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(
        Rect.fromLTWH(
          centerX - 80 * scale,
          centerY - 80 * scale,
          160 * scale,
          160 * scale,
        ),
      );

    final path = Path();

    // flame shape
    path.moveTo(centerX, centerY - 60 * scale + flicker);

    path.quadraticBezierTo(
      centerX + 15 * scale + flicker * 0.3,
      centerY - 50 * scale,
      centerX + 30 * scale,
      centerY - 35 * scale,
    );
    path.quadraticBezierTo(
      centerX + 40 * scale,
      centerY - 15 * scale,
      centerX + 35 * scale,
      centerY + 5 * scale,
    );
    path.quadraticBezierTo(
      centerX + 25 * scale,
      centerY + 20 * scale,
      centerX + 12 * scale,
      centerY + 30 * scale,
    );
    path.quadraticBezierTo(
      centerX + 5 * scale,
      centerY + 35 * scale,
      centerX,
      centerY + 38 * scale,
    );

    path.quadraticBezierTo(
      centerX - 5 * scale,
      centerY + 35 * scale,
      centerX - 12 * scale,
      centerY + 30 * scale,
    );
    path.quadraticBezierTo(
      centerX - 25 * scale,
      centerY + 20 * scale,
      centerX - 35 * scale,
      centerY + 5 * scale,
    );
    path.quadraticBezierTo(
      centerX - 40 * scale,
      centerY - 15 * scale,
      centerX - 30 * scale,
      centerY - 35 * scale,
    );
    path.quadraticBezierTo(
      centerX - 15 * scale - flicker * 0.3,
      centerY - 50 * scale,
      centerX,
      centerY - 60 * scale + flicker,
    );

    path.close();

    canvas.drawPath(path, paint);

    if (scale > 0.6) {
      final highlightPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromLTWH(
            centerX - 40 * scale,
            centerY - 60 * scale,
            80 * scale,
            80 * scale,
          ),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      final highlightPath = Path();
      highlightPath.moveTo(centerX, centerY - 50 * scale + flicker);
      highlightPath.quadraticBezierTo(
        centerX + 10 * scale,
        centerY - 40 * scale,
        centerX + 15 * scale,
        centerY - 20 * scale,
      );
      highlightPath.quadraticBezierTo(
        centerX,
        centerY - 10 * scale,
        centerX - 15 * scale,
        centerY - 20 * scale,
      );
      highlightPath.quadraticBezierTo(
        centerX - 10 * scale,
        centerY - 40 * scale,
        centerX,
        centerY - 50 * scale + flicker,
      );
      highlightPath.close();

      canvas.drawPath(highlightPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(RealisticFlamePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.hasStreak != hasStreak;
}