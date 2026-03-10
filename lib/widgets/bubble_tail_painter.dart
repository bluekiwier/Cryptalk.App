import 'package:flutter/material.dart';

enum TailDirection { left, right }

class BubbleTailPainter extends CustomPainter {
  final Color color;
  final TailDirection tailDirection;

  BubbleTailPainter({required this.color, required this.tailDirection});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    const tailWidth = 6.0;
    const tailHeight = 12.0;
    const tailOffset = 4.0;

    if (tailDirection == TailDirection.left) {
      path.moveTo(0, tailOffset);
      path.lineTo(-tailWidth, tailOffset + tailHeight / 2);
      path.lineTo(0, tailOffset + tailHeight);
    } else {
      path.moveTo(size.width, tailOffset);
      path.lineTo(size.width + tailWidth, tailOffset + tailHeight / 2);
      path.lineTo(size.width, tailOffset + tailHeight);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.tailDirection != tailDirection;
  }
}
