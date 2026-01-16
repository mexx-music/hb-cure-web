import 'package:flutter/material.dart';
import 'dart:math' as math;

class OriginalFrequencyLine extends StatelessWidget {
  final List<num> frequenciesHz;
  final double height;

  const OriginalFrequencyLine({
    super.key,
    required this.frequenciesHz,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _OriginalFreqPainter(
          freqs: frequenciesHz,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}

class _OriginalFreqPainter extends CustomPainter {
  final List<num> freqs;
  final Color color;

  _OriginalFreqPainter({
    required this.freqs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (freqs.isEmpty) return;

    final logs = freqs.map((f) => math.log(f <= 0 ? 1 : f) / ln10).toList();
    final minV = logs.reduce(math.min);
    final maxV = logs.reduce(math.max);
    final range = (maxV - minV).abs() < 0.3 ? 0.3 : (maxV - minV);

    final path = Path();
    for (int i = 0; i < logs.length; i++) {
      final t = logs.length == 1 ? 0.5 : i / (logs.length - 1);
      final x = size.width * t;
      final norm = (logs[i] - minV) / range;
      final y = size.height * (0.8 - norm * 0.6);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OriginalFreqPainter old) =>
      old.freqs != freqs;
}
