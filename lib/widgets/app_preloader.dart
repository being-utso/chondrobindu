import 'dart:math';
import 'package:flutter/material.dart';

class AppPreloader extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;

  const AppPreloader({
    super.key,
    this.size = 56.0,
    this.strokeWidth = 3.2,
    this.color,
    this.trackColor,
  });

  @override
  State<AppPreloader> createState() => _AppPreloaderState();
}

class _AppPreloaderState extends State<AppPreloader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size * 1.8, widget.size),
            painter: _InfinityLemniscatePainter(
              progress: _controller.value,
              strokeWidth: widget.strokeWidth,
              activeColor: widget.color ?? const Color(0xFFF2B78A),
              trackColor: widget.trackColor ?? const Color(0xFF4A3830).withOpacity(0.35),
            ),
          );
        },
      ),
    );
  }
}

class _InfinityLemniscatePainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color activeColor;
  final Color trackColor;

  _InfinityLemniscatePainter({
    required this.progress,
    required this.strokeWidth,
    required this.activeColor,
    required this.trackColor,
  });

  // Lemniscate of Bernoulli parametric formulation
  Offset _getLemniscatePoint(double t, double a, Offset center) {
    final sinT = sin(t);
    final cosT = cos(t);
    final denom = 1 + sinT * sinT;
    final x = (a * cosT) / denom;
    final y = (a * sinT * cosT) / denom;
    return Offset(center.dx + x, center.dy + y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final a = size.width * 0.44;

    // 1. Draw static faint track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final trackPath = Path();
    const steps = 140;
    for (int i = 0; i <= steps; i++) {
      final t = (i / steps) * 2 * pi;
      final pt = _getLemniscatePoint(t, a, center);
      if (i == 0) {
        trackPath.moveTo(pt.dx, pt.dy);
      } else {
        trackPath.lineTo(pt.dx, pt.dy);
      }
    }
    trackPath.close();
    canvas.drawPath(trackPath, trackPaint);

    // 2. Draw animated moving Ember arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final activePath = Path();
    const arcLength = pi * 0.75; // Length of the moving line
    final currentT = progress * 2 * pi;
    const arcSteps = 45;

    for (int i = 0; i <= arcSteps; i++) {
      final t = currentT - arcLength + (i / arcSteps) * arcLength;
      final pt = _getLemniscatePoint(t, a, center);
      if (i == 0) {
        activePath.moveTo(pt.dx, pt.dy);
      } else {
        activePath.lineTo(pt.dx, pt.dy);
      }
    }

    canvas.drawPath(activePath, activePaint);
  }

  @override
  bool shouldRepaint(covariant _InfinityLemniscatePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
