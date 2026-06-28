import 'dart:math';
import 'package:flutter/material.dart';

/// Paints a subtle racing track perspective horizon.
/// Creates a sense of depth and motorsport atmosphere in the lower portion
/// of the screen without distracting from the gantry gameplay element.
class TrackHorizonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    // Horizon sits at 55% of the screen height
    final horizonY = size.height * 0.55;
    final bottomY = size.height;

    // --- Tarmac gradient: dark ground fading in from horizon ---
    final groundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000), // fully transparent at horizon line
          Color(0x55101010), // dim tarmac tone at bottom
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, bottomY - horizonY));
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, size.width, bottomY - horizonY),
      groundPaint,
    );

    // --- Outer track boundary lines ---
    final boundaryPaint = Paint()
      ..color = const Color(0xFF383838)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Left outer boundary
    canvas.drawLine(Offset(centerX, horizonY), Offset(-size.width * 0.12, bottomY), boundaryPaint);
    // Right outer boundary
    canvas.drawLine(Offset(centerX, horizonY), Offset(size.width * 1.12, bottomY), boundaryPaint);

    // --- Inner red track lines (kerb lines) ---
    final kerbPaint = Paint()
      ..color = const Color(0xFFE10600).withValues(alpha: 0.13)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(centerX, horizonY), Offset(centerX - size.width * 0.32, bottomY), kerbPaint);
    canvas.drawLine(Offset(centerX, horizonY), Offset(centerX + size.width * 0.32, bottomY), kerbPaint);

    // --- Dashed centre line receding into distance ---
    const int numDashes = 7;
    for (int i = 1; i <= numDashes; i++) {
      final t = i / numDashes; // 0 = horizon, 1 = bottom
      final y = horizonY + (bottomY - horizonY) * t;
      final dashHalfWidth = max(2.0, size.width * 0.025 * t);
      final opacity = 0.03 + t * 0.07;

      final dashPaint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..strokeWidth = max(0.5, 1.8 * t)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(centerX - dashHalfWidth, y),
        Offset(centerX + dashHalfWidth, y),
        dashPaint,
      );
    }

    // --- Horizon glow line ---
    final horizonGlowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFE10600).withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, 1));
    canvas.drawLine(Offset(0, horizonY), Offset(size.width, horizonY), horizonGlowPaint);
  }

  @override
  bool shouldRepaint(covariant TrackHorizonPainter oldDelegate) => false;
}
