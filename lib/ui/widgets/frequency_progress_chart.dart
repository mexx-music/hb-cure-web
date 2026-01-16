import 'dart:math' as math;
import 'package:flutter/material.dart';

class FrequencyProgressChart extends StatelessWidget {
  final List<num> frequenciesHz;
  final int activePoints;
  final double height;

  const FrequencyProgressChart({
    super.key,
    required this.frequenciesHz,
    required this.activePoints,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    // log10 (safe)
    final rawLogs = frequenciesHz.map((f) {
      final v = f.toDouble();
      final safe = v <= 0 ? 1e-6 : v;
      return math.log(safe) / math.ln10;
    }).toList();

    // tiny smoothing (3-point moving average)
    List<double> logs = rawLogs;
    if (rawLogs.length >= 3) {
      final sm = List<double>.filled(rawLogs.length, 0.0);
      for (int i = 0; i < rawLogs.length; i++) {
        final a = rawLogs[(i - 1).clamp(0, rawLogs.length - 1)];
        final b = rawLogs[i];
        final c = rawLogs[(i + 1).clamp(0, rawLogs.length - 1)];
        sm[i] = (a + b + c) / 3.0;
      }
      logs = sm;
    }

    // robust autoscale: 5%/95% quantiles + minRange
    double minV, maxV;
    if (logs.isEmpty) {
      minV = 0.0;
      maxV = 1.0;
    } else if (logs.length < 8) {
      minV = logs.reduce(math.min);
      maxV = logs.reduce(math.max);
    } else {
      final sorted = List<double>.from(logs)..sort();
      double q(double p) {
        final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
        return sorted[idx];
      }

      minV = q(0.05);
      maxV = q(0.95);
    }

    double range = (maxV - minV).abs();
    const double minRange = 0.40;
    if (range < minRange) {
      final mid = (minV + maxV) / 2.0;
      minV = mid - minRange / 2.0;
      maxV = mid + minRange / 2.0;
      range = minRange;
    }

    final normalized = logs.map((v) {
      final n = (v - minV) / range;
      return n.clamp(0.0, 1.0);
    }).toList();

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FreqPainter(
          normalized: normalized,
          activePoints: activePoints,
        ),
      ),
    );
  }
}

class _FreqPainter extends CustomPainter {
  final List<double> normalized; // 0..1
  final int activePoints;

  _FreqPainter({
    required this.normalized,
    required this.activePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (normalized.isEmpty) return;

    final grey = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final black = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    Offset pt(int i) {
      if (normalized.length <= 1) {
        final y = h - (normalized.first.clamp(0.0, 1.0) * h);
        return Offset(0, y);
      }
      final x = (i / (normalized.length - 1)) * w;
      final y = h - (normalized[i].clamp(0.0, 1.0) * h);
      return Offset(x, y);
    }

    Path smoothPath(int lastIndexInclusive) {
      final last = lastIndexInclusive.clamp(0, normalized.length - 1);
      final p = Path();
      p.moveTo(pt(0).dx, pt(0).dy);
      if (last == 0) return p;

      if (last == 1) {
        final p1 = pt(1);
        p.lineTo(p1.dx, p1.dy);
        return p;
      }

      for (int i = 1; i < last; i++) {
        final p1 = pt(i);
        final p2 = pt(i + 1);
        final mid = Offset((p1.dx + p2.dx) / 2.0, (p1.dy + p2.dy) / 2.0);
        p.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      final plast = pt(last);
      p.lineTo(plast.dx, plast.dy);
      return p;
    }

    // grey first
    canvas.drawPath(smoothPath(normalized.length - 1), grey);

    // black progress
    final endIdx = activePoints.clamp(0, normalized.length - 1);
    if (endIdx == 0) {
      canvas.drawCircle(pt(0), 2.0, black);
    } else {
      canvas.drawPath(smoothPath(endIdx), black);
    }
  }

  @override
  bool shouldRepaint(covariant _FreqPainter oldDelegate) {
    return oldDelegate.activePoints != activePoints || oldDelegate.normalized != normalized;
  }
}
