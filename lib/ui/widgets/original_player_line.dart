import 'package:flutter/material.dart';
import 'dart:math' as math;

class OriginalPlayerLine extends StatelessWidget {
  final List<num> values; // echte Frequenzen
  final double progress; // 0..1
  final double height;

  const OriginalPlayerLine({
    super.key,
    required this.values,
    required this.progress,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _OriginalPlayerLinePainter(
          values: values,
          progress: progress.clamp(0.0, 1.0),
          baseColor: Colors.grey.shade400,
          activeColor: Colors.black,
        ),
      ),
    );
  }
}

class _OriginalPlayerLinePainter extends CustomPainter {
  final List<num> values;
  final double progress;
  final Color baseColor;
  final Color activeColor;

  // 🔧 SCHALTER
  static const bool useLogScale = true;

  // absolute Domain (UX-freundlich, unabhängig vom Programm)
  static const double absMin = 1.0;     // 0 vermeiden (log!)
  static const double absMax = 20000.0; // sinnvoller Oberwert

  _OriginalPlayerLinePainter({
    required this.values,
    required this.progress,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 18.0;
    const topPad = 14.0;
    const bottomPad = 14.0;
    const rightPad = 10.0;

    final plotLeft = leftPad;
    final plotRight = size.width - rightPad;
    final plotTop = topPad;
    final plotBottom = size.height - bottomPad;

    final axisPaint = Paint()
      ..color = baseColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    // Achsen
    canvas.drawLine(
      Offset(plotLeft, plotTop),
      Offset(plotLeft, plotBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotLeft, plotBottom),
      Offset(plotRight, plotBottom),
      axisPaint,
    );

    if (values.isEmpty || plotRight <= plotLeft + 1) return;

    final v = _downsampleToMax(values, 240);

    final w = plotRight - plotLeft;
    final h = plotBottom - plotTop;

    // ---- Skalierung vorbereiten
    double mapY(double value) {
      final clamped = value.clamp(absMin, absMax);

      if (useLogScale) {
        // ⭐ LOG-SKALA → 800, 900, 10000 klar unterscheidbar
        final logMin = math.log(absMin);
        final logMax = math.log(absMax);
        final logV = math.log(clamped);
        final yNorm = (logV - logMin) / (logMax - logMin);
        return plotBottom - (yNorm.clamp(0.0, 1.0) * h);
      } else {
        // Linear (Fallback)
        final yNorm = (clamped - absMin) / (absMax - absMin);
        return plotBottom - (yNorm.clamp(0.0, 1.0) * h);
      }
    }

    // ---- Pfad bauen
    final fullPath = Path();
    for (int i = 0; i < v.length; i++) {
      final x = plotLeft + (i / (v.length - 1)) * w;
      final y = mapY(v[i].toDouble());
      if (i == 0) {
        fullPath.moveTo(x, y);
      } else {
        fullPath.lineTo(x, y);
      }
    }

    final grey = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;

    final black = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true;

    canvas.drawPath(fullPath, grey);

    // ---- Progress-Overlay
    final metrics = fullPath.computeMetrics().toList();
    if (metrics.isEmpty) return;

    double totalLen = 0;
    for (final m in metrics) {
      totalLen += m.length;
    }

    final targetLen = totalLen * progress;
    final activePath = Path();
    double drawn = 0;

    for (final m in metrics) {
      final remaining = targetLen - drawn;
      if (remaining <= 0) break;
      final take = remaining.clamp(0.0, m.length);
      activePath.addPath(m.extractPath(0, take), Offset.zero);
      drawn += m.length;
    }

    canvas.drawPath(activePath, black);
  }

  List<double> _downsampleToMax(List<num> input, int maxPoints) {
    if (input.length <= maxPoints) {
      return input.map((e) => e.toDouble()).toList();
    }
    final out = <double>[];
    final step = input.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final idx = (i * step).floor().clamp(0, input.length - 1);
      out.add(input[idx].toDouble());
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _OriginalPlayerLinePainter old) {
    return old.progress != progress || old.values != values;
  }
}