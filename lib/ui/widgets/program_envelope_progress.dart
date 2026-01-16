import 'package:flutter/material.dart';
import 'dart:math' as math;

enum EnvelopeLevel { low, mid, high }

class ProgramEnvelopeProgress extends StatelessWidget {
  final double progress; // 0..1
  final double height;
  final EnvelopeLevel level;

  const ProgramEnvelopeProgress({
    super.key,
    required this.progress,
    this.height = 120,
    this.level = EnvelopeLevel.mid,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _EnvelopePainter(
          progress: progress.clamp(0.0, 1.0),
          level: level,
          baseColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
          activeColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
        ),
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  final double progress;
  final EnvelopeLevel level;
  final Color baseColor;
  final Color activeColor;

  _EnvelopePainter({
    required this.progress,
    required this.level,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = 0.0;
    final right = size.width;
    final top = size.height * 0.15;
    final bottom = size.height * 0.85;
    final midY = (top + bottom) / 2;

    final amp = switch (level) {
      EnvelopeLevel.low => 0.35,
      EnvelopeLevel.mid => 0.55,
      EnvelopeLevel.high => 0.75,
    };

    Path buildPath(double frac) {
      final p = Path();
      for (int i = 0; i <= 40; i++) {
        final t = i / 40;
        final x = left + (right - left) * t;
        final env =
            (math.sin(t * math.pi * 2) * 0.5 + 0.5) * amp;
        final y = midY - env * (midY - top);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
        if (t >= frac) break;
      }
      return p;
    }

    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final full = buildPath(1.0);
    final active = buildPath(progress);

    canvas.drawPath(full, basePaint);
    canvas.drawPath(active, activePaint);
  }

  @override
  bool shouldRepaint(covariant _EnvelopePainter old) =>
      old.progress != progress || old.level != level;
}
