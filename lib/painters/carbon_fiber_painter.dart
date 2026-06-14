import 'package:flutter/material.dart';

class CarbonFiberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Deep black base color
    final bgPaint = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle carbon weave pattern paint
    final Paint patternPaint = Paint()
      ..color = const Color(0xFF141414)
      ..style = PaintingStyle.fill;

    const double sizeUnit = 6.0;

    // Drawing a classic 2x2 diagonal twill weave pattern
    for (double y = 0; y < size.height + sizeUnit; y += sizeUnit) {
      for (double x = 0; x < size.width + sizeUnit; x += sizeUnit) {
        if (((x / sizeUnit).floor() + (y / sizeUnit).floor()) % 4 < 2) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, sizeUnit, sizeUnit),
            patternPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
