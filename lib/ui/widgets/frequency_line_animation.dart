import 'package:flutter/material.dart';
import 'dart:math' as math;

class FrequencyLineAnimation extends StatelessWidget {
  final List<num> frequenciesHz;
  final double progress; // 0..1
  final double height;

  const FrequencyLineAnimation({
    super.key,
    required this.frequenciesHz,
    required this.progress,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wenn kein vertikaler Platzlimit angegeben ist, benutze die Wunschhöhe.
        final availableMax = constraints.maxHeight.isFinite ? constraints.maxHeight : double.infinity;
        final useHeight = math.min(height, availableMax);

        return SizedBox(
          height: useHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _AnimatedFreqPainter(
              freqs: frequenciesHz,
              progress: progress,
              baseColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              activeColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedFreqPainter extends CustomPainter {
  final List<num> freqs;
  final double progress;
  final Color baseColor;
  final Color activeColor;

  _AnimatedFreqPainter({
    required this.freqs,
    required this.progress,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (freqs.isEmpty) return;

    final logs = freqs.map((f) => math.log((f is num ? f.toDouble() : 0.0) <= 0 ? 1 : (f as num).toDouble()) / math.ln10).toList();
    final minV = logs.reduce(math.min);
    final maxV = logs.reduce(math.max);
    final range = (maxV - minV).abs() < 0.3 ? 0.3 : (maxV - minV);

    Path buildPath(int maxIndex) {
      final p = Path();
      for (int i = 0; i <= maxIndex && i < logs.length; i++) {
        final t = logs.length == 1 ? 0.5 : i / (logs.length - 1);
        final x = size.width * t;
        final norm = (logs[i] - minV) / range;
        final y = size.height * (0.8 - norm * 0.6);
        if (i == 0) p.moveTo(x, y);
        else p.lineTo(x, y);
      }
      return p;
    }

    final fullPath = buildPath(logs.length - 1);
    final activeCount = (logs.length * progress).round();
    final activePath = buildPath(activeCount);

    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    canvas.drawPath(fullPath, basePaint);
    canvas.drawPath(activePath, activePaint);
  }

  @override
  bool shouldRepaint(covariant _AnimatedFreqPainter old) => old.progress != progress || old.freqs != freqs;
}
