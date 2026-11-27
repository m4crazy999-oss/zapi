import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum ZapiMascotMood {
  happy,
  waiting,
  resting,
  excited,
}

class ZapiMascot extends StatefulWidget {
  const ZapiMascot({
    super.key,
    this.mood = ZapiMascotMood.happy,
    this.size = 112,
    this.animate = true,
  });

  final ZapiMascotMood mood;
  final double size;
  final bool animate;

  @override
  State<ZapiMascot> createState() => _ZapiMascotState();
}

class _ZapiMascotState extends State<ZapiMascot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ZapiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate && _controller == null) {
        _controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2400),
        )..repeat(reverse: true);
      } else if (!widget.animate && _controller != null) {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final painter = _ZapiMascotPainter(
      mood: widget.mood,
      isDark: isDark,
    );

    final painted = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(painter: painter),
    );

    final controller = _controller;
    if (controller == null) return painted;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final dy = (Curves.easeInOut.transform(controller.value) - 0.5) * 6.0;
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: painted,
    );
  }
}

class _ZapiMascotPainter extends CustomPainter {
  const _ZapiMascotPainter({
    required this.mood,
    required this.isDark,
  });

  final ZapiMascotMood mood;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 160.0;
    final dx = (size.width - 160.0 * s) / 2;
    final dy = (size.height - 160.0 * s) / 2;

    canvas.save();
    canvas.translate(dx, dy);

    // Sombra suave no chão
    final shadowPaint = Paint()
      ..color = AppColors.emerald.withValues(alpha: isDark ? 0.16 : 0.14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(80 * s, 145 * s),
        width: 78 * s,
        height: 14 * s,
      ),
      shadowPaint,
    );

    // Crista em raiozinho no topo (tema Zapi)
    final sparkPath = Path()
      ..moveTo(85 * s, 10 * s)
      ..lineTo(72 * s, 27 * s)
      ..lineTo(83 * s, 27 * s)
      ..lineTo(76 * s, 40 * s)
      ..lineTo(95 * s, 21 * s)
      ..lineTo(84 * s, 21 * s)
      ..close();

    final sparkPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF34D399), AppColors.emerald],
      ).createShader(Rect.fromLTWH(70 * s, 10 * s, 28 * s, 30 * s))
      ..style = PaintingStyle.fill;
    canvas.drawPath(sparkPath, sparkPaint);

    // Corpo principal em formato de balão amigável com cauda inferior esquerda
    final bodyRect = Rect.fromLTWH(24 * s, 32 * s, 112 * s, 96 * s);
    final bodyPath = Path()
      ..moveTo(80 * s, 32 * s)
      ..cubicTo(45 * s, 32 * s, 24 * s, 51 * s, 24 * s, 80 * s)
      ..cubicTo(24 * s, 96 * s, 31 * s, 109 * s, 41 * s, 117 * s)
      ..lineTo(31 * s, 136 * s)
      ..lineTo(54 * s, 125 * s)
      ..cubicTo(62 * s, 127 * s, 71 * s, 128 * s, 80 * s, 128 * s)
      ..cubicTo(115 * s, 128 * s, 136 * s, 109 * s, 136 * s, 80 * s)
      ..cubicTo(136 * s, 51 * s, 115 * s, 32 * s, 80 * s, 32 * s)
      ..close();

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.emeraldBright, AppColors.emerald, AppColors.emeraldDark],
      ).createShader(bodyRect);
    canvas.drawPath(bodyPath, bodyPaint);

    // Brilho sutil superior no corpo
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(64 * s, 43 * s),
        width: 44 * s,
        height: 11 * s,
      ),
      highlightPaint,
    );

    // Visor branco arredondado do rosto
    final faceRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(80 * s, 80 * s),
        width: 82 * s,
        height: 58 * s,
      ),
      Radius.circular(24 * s),
    );
    final facePaint = Paint()..color = const Color(0xFFF6FFFC);
    canvas.drawRRect(faceRect, facePaint);

    // Bochechas rosadas suaves
    final blushPaint = Paint()
      ..color = const Color(0xFFFF8BA7).withValues(alpha: 0.36);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(53 * s, 90 * s),
        width: 12 * s,
        height: 7 * s,
      ),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(107 * s, 90 * s),
        width: 12 * s,
        height: 7 * s,
      ),
      blushPaint,
    );

    final featureColor = const Color(0xFF0F241D);
    final eyePaint = Paint()
      ..color = featureColor
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = featureColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Expressões faciais
    switch (mood) {
      case ZapiMascotMood.happy:
        _drawOpenEye(canvas, Offset(62 * s, 74 * s), s, eyePaint);
        _drawOpenEye(canvas, Offset(98 * s, 74 * s), s, eyePaint);
        final smile = Path()
          ..moveTo(71 * s, 88 * s)
          ..quadraticBezierTo(80 * s, 97 * s, 89 * s, 88 * s);
        canvas.drawPath(smile, strokePaint);
      case ZapiMascotMood.waiting:
        _drawOpenEye(canvas, Offset(63 * s, 73 * s), s * 1.04, eyePaint,
            pupilShift: Offset(1.5 * s, -0.5 * s));
        _drawOpenEye(canvas, Offset(99 * s, 73 * s), s * 1.04, eyePaint,
            pupilShift: Offset(1.5 * s, -0.5 * s));
        final mouth = Path()
          ..moveTo(74 * s, 90 * s)
          ..quadraticBezierTo(80 * s, 93 * s, 86 * s, 90 * s);
        canvas.drawPath(mouth, strokePaint);
      case ZapiMascotMood.resting:
        // Olhos fechados tranquilos (arcos suaves)
        final leftClosed = Path()
          ..moveTo(55 * s, 76 * s)
          ..quadraticBezierTo(62 * s, 81 * s, 69 * s, 76 * s);
        final rightClosed = Path()
          ..moveTo(91 * s, 76 * s)
          ..quadraticBezierTo(98 * s, 81 * s, 105 * s, 76 * s);
        canvas.drawPath(leftClosed, strokePaint);
        canvas.drawPath(rightClosed, strokePaint);
        final calmMouth = Path()
          ..moveTo(75 * s, 90 * s)
          ..quadraticBezierTo(80 * s, 94 * s, 85 * s, 90 * s);
        canvas.drawPath(calmMouth, strokePaint);
        // Pequenos círculos flutuantes de repouso
        final restDotPaint = Paint()
          ..color = AppColors.emeraldBright.withValues(alpha: 0.7);
        canvas.drawCircle(Offset(132 * s, 32 * s), 3.2 * s, restDotPaint);
        canvas.drawCircle(Offset(141 * s, 21 * s), 4.4 * s, restDotPaint);
      case ZapiMascotMood.excited:
        // Olhos felizes em arco ^ ^
        final leftHappy = Path()
          ..moveTo(55 * s, 78 * s)
          ..quadraticBezierTo(62 * s, 69 * s, 69 * s, 78 * s);
        final rightHappy = Path()
          ..moveTo(91 * s, 78 * s)
          ..quadraticBezierTo(98 * s, 69 * s, 105 * s, 78 * s);
        canvas.drawPath(leftHappy, strokePaint);
        canvas.drawPath(rightHappy, strokePaint);
        final bigSmile = Path()
          ..moveTo(69 * s, 86 * s)
          ..quadraticBezierTo(80 * s, 99 * s, 91 * s, 86 * s)
          ..close();
        canvas.drawPath(bigSmile, eyePaint);
        // Estrelinha de brilho lateral
        final starPaint = Paint()..color = const Color(0xFF34D399);
        _drawMiniStar(canvas, Offset(136 * s, 44 * s), 6 * s, starPaint);
        _drawMiniStar(canvas, Offset(22 * s, 48 * s), 4.5 * s, starPaint);
    }

    canvas.restore();
  }

  void _drawOpenEye(
    Canvas canvas,
    Offset center,
    double s,
    Paint paint, {
    Offset pupilShift = Offset.zero,
  }) {
    canvas.drawCircle(center + pupilShift, 5.6 * s, paint);
    final catchlight = Paint()..color = Colors.white;
    canvas.drawCircle(
      center + pupilShift + Offset(-1.7 * s, -1.9 * s),
      1.9 * s,
      catchlight,
    );
  }

  void _drawMiniStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + r, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + r)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - r, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ZapiMascotPainter oldDelegate) {
    return oldDelegate.mood != mood || oldDelegate.isDark != isDark;
  }
}
