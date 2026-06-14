import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GraphPainter extends CustomPainter {
  final List<int> data;
  GraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // The grid background for the graph
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    
    for (double i = 0; i <= size.height; i += size.height / 3) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    final paint = Paint()
      ..color = const Color(0xFF00FF00).withValues(alpha: 0.9)
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00FF00).withValues(alpha: 0.4),
          const Color(0xFF00FF00).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    double maxData = data.reduce(max).toDouble();
    double minData = data.reduce(min).toDouble();

    // Padding for visual appeal
    maxData += 20;
    minData = max(0, minData - 20);

    final range = maxData - minData == 0 ? 1.0 : maxData - minData;

    final path = Path();
    final fillPath = Path();
    double startX = 0;
    double stepX = size.width / (data.length > 1 ? data.length - 1 : 1);

    for (int i = 0; i < data.length; i++) {
      double normalizedY = (data[i] - minData) / range;
      // Invert Y: lower time (faster) = higher on canvas (visually better)
      double y = size.height * (1.0 - normalizedY);

      if (i == 0) {
        path.moveTo(startX, y);
        fillPath.moveTo(startX, size.height);
        fillPath.lineTo(startX, y);
      } else {
        path.lineTo(startX, y);
        fillPath.lineTo(startX, y);
      }

      if (i == data.length - 1) {
        fillPath.lineTo(startX, size.height);
      }

      startX += stepX;
    }
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
    
    // Draw dots
    startX = 0;
    for (int i = 0; i < data.length; i++) {
      double normalizedY = (data[i] - minData) / range;
      double y = size.height * (1.0 - normalizedY);
      canvas.drawCircle(Offset(startX, y), 4.0, dotPaint);
      startX += stepX;
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return !listEquals(oldDelegate.data, data);
  }
}
