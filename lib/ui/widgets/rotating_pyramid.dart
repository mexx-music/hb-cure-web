import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_colors.dart';

/// A widget that renders a simple 3D-looking standing pyramid and rotates it around Y.
class RotatingPyramid extends StatelessWidget {
  final Animation<double> rotation; // normalized 0..1
  final double size;

  const RotatingPyramid({super.key, required this.rotation, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: rotation,
      builder: (context, child) {
        final angle = rotation.value * 2.0 * math.pi;
        // build a perspective transform: slight tilt on X so pyramid stands, rotate around Y
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective
          ..rotateX(-0.35)
          ..rotateY(angle);

        return Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _PyramidPainter(angle),
            ),
          ),
        );
      },
    );
  }
}

class _PyramidPainter extends CustomPainter {
  final double angle;
  _PyramidPainter(this.angle);

  Color _shade(Color base, double f) {
    final hsl = HSLColor.fromColor(base);
    final light = (hsl.lightness * f).clamp(0.0, 1.0);
    return hsl.withLightness(light).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Equilateral triangle points (front-facing base triangle)
    final top = Offset(size.width * 0.5, size.height * 0.15);
    final left = Offset(size.width * 0.12, size.height * 0.78);
    final right = Offset(size.width * 0.88, size.height * 0.78);

    // We'll draw three triangular faces (as if a tetrahedron seen from front/above):
    // Face A (front) - top, left, right
    // Face B (left) - top, left, center (slightly inset)
    // Face C (right) - top, right, center

    // compute simple brightness factors based on angle
    final fFront = 0.7 + 0.3 * math.cos(angle - 0.0);
    final fLeft = 0.6 + 0.35 * math.cos(angle + 2.0);
    final fRight = 0.6 + 0.35 * math.cos(angle + 1.0);

    final base = AppColors.warmAccent;
    final colorFront = _shade(base, fFront);
    final colorLeft = _shade(base.withOpacity(0.95), fLeft);
    final colorRight = _shade(base.withOpacity(0.9), fRight);

    // Draw left face (slightly behind) - use a midpoint to simulate depth
    final center = Offset(size.width * 0.5, size.height * 0.5);

    // Left face polygon
    final leftPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    paint.color = colorLeft;
    canvas.drawPath(leftPath, paint);

    // Right face polygon
    final rightPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    paint.color = colorRight;
    canvas.drawPath(rightPath, paint);

    // Front face polygon (on top)
    final frontPath = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    paint.color = colorFront;
    canvas.drawPath(frontPath, paint);

    // subtle rim / stroke for separation
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width * 0.006)
      ..color = AppColors.borderSubtle.withOpacity(0.6);
    canvas.drawPath(frontPath, stroke);
    canvas.drawPath(leftPath, stroke);
    canvas.drawPath(rightPath, stroke);
  }

  @override
  bool shouldRepaint(covariant _PyramidPainter oldDelegate) => (oldDelegate.angle != angle);
}
