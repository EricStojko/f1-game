import 'package:flutter/material.dart';

class CheckeredFlagPainter extends CustomPainter {
  final double progress;
  CheckeredFlagPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    const double checkSize = 32.0;
    final double offsetX = progress * size.width;

    for (double y = 0; y < size.height + checkSize; y += checkSize) {
      for (double x = -size.width; x < size.width + checkSize; x += checkSize) {
        final double currentX = x + offsetX;

        if (((x / checkSize).floor() + (y / checkSize).floor()) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(currentX, y, checkSize, checkSize),
            whitePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckeredFlagPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
