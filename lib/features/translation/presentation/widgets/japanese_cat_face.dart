import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Minimalist Japanese Maneki-neko cat face emblem for the bottom dock,
/// styled in the Sumi (#1A1817), Cinnabar (#C33A2B), and Washi (#FAF7F2) palette.
class JapaneseCatFace extends StatefulWidget {
  final double size;
  final String? tooltip;

  const JapaneseCatFace({
    super.key,
    this.size = 38,
    this.tooltip,
  });

  @override
  State<JapaneseCatFace> createState() => _JapaneseCatFaceState();
}

class _JapaneseCatFaceState extends State<JapaneseCatFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: ScaleTransition(
          scale: _scale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _ManekiNekoPainter(),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

class _ManekiNekoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final inkStroke = Paint()
      ..color = AppTheme.sumi
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.052
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final faceFill = Paint()
      ..color = AppTheme.washi
      ..style = PaintingStyle.fill;

    final cinnabarPaint = Paint()
      ..color = AppTheme.cinnabar
      ..style = PaintingStyle.fill;

    final calicoInkPaint = Paint()
      ..color = AppTheme.sumi.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;

    final goldBellPaint = Paint()
      ..color = const Color(0xFFD99B26)
      ..style = PaintingStyle.fill;

    // 1. Head + Pointed Cat Ears silhouette
    final headPath = Path()
      // Left base cheek -> left ear
      ..moveTo(w * 0.14, h * 0.56)
      ..quadraticBezierTo(w * 0.11, h * 0.36, w * 0.17, h * 0.14)
      ..quadraticBezierTo(w * 0.28, h * 0.18, w * 0.37, h * 0.28)
      // Forehead crown
      ..quadraticBezierTo(w * 0.50, h * 0.24, w * 0.63, h * 0.28)
      // Right ear -> right cheek
      ..quadraticBezierTo(w * 0.72, h * 0.18, w * 0.83, h * 0.14)
      ..quadraticBezierTo(w * 0.89, h * 0.36, w * 0.86, h * 0.56)
      // Rounded chin
      ..quadraticBezierTo(w * 0.86, h * 0.82, w * 0.50, h * 0.85)
      ..quadraticBezierTo(w * 0.14, h * 0.82, w * 0.14, h * 0.56)
      ..close();

    canvas.drawPath(headPath, faceFill);

    // 2. Signature Calico (Mi-ke) left/right ear patches clipped inside head
    canvas.save();
    canvas.clipPath(headPath);
    canvas.drawCircle(Offset(w * 0.20, h * 0.26), w * 0.18, cinnabarPaint);
    canvas.drawCircle(Offset(w * 0.80, h * 0.26), w * 0.18, calicoInkPaint);
    // Warm rosy cheeks
    final blushPaint = Paint()
      ..color = AppTheme.cinnabar.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.27, h * 0.61),
        width: w * 0.13,
        height: h * 0.08,
      ),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.73, h * 0.61),
        width: w * 0.13,
        height: h * 0.08,
      ),
      blushPaint,
    );
    canvas.restore();

    // Inner ear triangles
    final leftInnerEar = Path()
      ..moveTo(w * 0.19, h * 0.33)
      ..lineTo(w * 0.21, h * 0.20)
      ..lineTo(w * 0.31, h * 0.28)
      ..close();
    final rightInnerEar = Path()
      ..moveTo(w * 0.81, h * 0.33)
      ..lineTo(w * 0.79, h * 0.20)
      ..lineTo(w * 0.69, h * 0.28)
      ..close();
    canvas.drawPath(leftInnerEar, faceFill);
    canvas.drawPath(rightInnerEar, cinnabarPaint);

    // Outer Sumi contour
    canvas.drawPath(headPath, inkStroke);

    // 3. Peaceful curved Maneki-neko happy eyes
    final eyePaint = Paint()
      ..color = AppTheme.sumi
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;

    final leftEye = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..quadraticBezierTo(w * 0.36, h * 0.45, w * 0.42, h * 0.52);
    final rightEye = Path()
      ..moveTo(w * 0.58, h * 0.52)
      ..quadraticBezierTo(w * 0.64, h * 0.45, w * 0.70, h * 0.52);
    canvas.drawPath(leftEye, eyePaint);
    canvas.drawPath(rightEye, eyePaint);

    // 4. Tiny Cinnabar nose & subtle cat `w` mouth
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.59),
        width: w * 0.08,
        height: h * 0.055,
      ),
      cinnabarPaint,
    );

    final mouthPaint = Paint()
      ..color = AppTheme.sumi
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path()
      ..moveTo(w * 0.42, h * 0.67)
      ..quadraticBezierTo(w * 0.46, h * 0.70, w * 0.50, h * 0.64)
      ..quadraticBezierTo(w * 0.54, h * 0.70, w * 0.58, h * 0.67);
    canvas.drawPath(mouthPath, mouthPaint);

    // 5. Delicate Sumi whiskers (left & right)
    final whiskerPaint = Paint()
      ..color = AppTheme.sumi.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    // Left whiskers
    canvas.drawLine(
      Offset(w * 0.11, h * 0.55),
      Offset(w * 0.23, h * 0.57),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(w * 0.11, h * 0.64),
      Offset(w * 0.23, h * 0.63),
      whiskerPaint,
    );
    // Right whiskers
    canvas.drawLine(
      Offset(w * 0.89, h * 0.55),
      Offset(w * 0.77, h * 0.57),
      whiskerPaint,
    );
    canvas.drawLine(
      Offset(w * 0.89, h * 0.64),
      Offset(w * 0.77, h * 0.63),
      whiskerPaint,
    );

    // 6. Cinnabar collar ribbon + little golden Suzu bell at chin base
    final collarPaint = Paint()
      ..color = AppTheme.cinnabar
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.34, h * 0.84),
      Offset(w * 0.66, h * 0.84),
      collarPaint,
    );
    canvas.drawCircle(Offset(w * 0.50, h * 0.88), w * 0.085, goldBellPaint);
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.88),
      w * 0.085,
      Paint()
        ..color = AppTheme.sumi
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.036,
    );
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.88),
      w * 0.022,
      Paint()..color = AppTheme.sumi,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
