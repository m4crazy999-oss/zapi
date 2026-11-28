import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

enum ZapiMascotMood {
  happy,
  waiting,
  speaking,
  resting,
  excited,
}

/// Mascote oficial do Zapi (**Zapinho**) em formato de nuvem-conversa esmeralda
/// sem bordas, com o "Z" da marca, braços e pernas pretos cartunescos e gestos em 60fps.
class ZapiMascot extends StatefulWidget {
  const ZapiMascot({
    super.key,
    this.mood = ZapiMascotMood.happy,
    this.size = 112,
    this.animate = true,
    this.onTap,
  });

  final ZapiMascotMood mood;
  final double size;
  final bool animate;
  final VoidCallback? onTap;

  @override
  State<ZapiMascot> createState() => _ZapiMascotState();
}

class _ZapiMascotState extends State<ZapiMascot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _tapScale = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.animate && widget.mood != ZapiMascotMood.resting) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    )..repeat();
  }

  void _stopAnimation() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void didUpdateWidget(covariant ZapiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate = widget.animate && widget.mood != ZapiMascotMood.resting;
    if (shouldAnimate && _controller == null) {
      _startAnimation();
    } else if (!shouldAnimate && _controller != null) {
      _stopAnimation();
    }
  }

  @override
  void dispose() {
    _stopAnimation();
    super.dispose();
  }

  void _handleTap() {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _tapScale = 1.1);
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _tapScale = 1.0);
    });
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = _controller;

    final painted = RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          isComplex: false,
          willChange: ctrl != null,
          painter: _ZapinhoCloudPainter(
            animation: ctrl,
            mood: widget.mood,
            isDark: isDark,
          ),
        ),
      ),
    );

    if (widget.onTap == null) return painted;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _tapScale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: painted,
      ),
    );
  }
}

class _ZapinhoCloudPainter extends CustomPainter {
  _ZapinhoCloudPainter({
    required this.animation,
    required this.mood,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double>? animation;
  final ZapiMascotMood mood;
  final bool isDark;

  static const Color _inkColor = Color(0xFF111B21);

  double _pulse(double t, double start, double end) {
    if (t < start || t > end) return 0.0;
    final norm = (t - start) / (end - start);
    return math.sin(norm * math.pi);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 160.0;
    final dx = (size.width - 160.0 * s) / 2;
    final dy = (size.height - 160.0 * s) / 2;

    final t = animation?.value ?? 0.0;
    final rad = t * math.pi * 2;

    double floatY = 0.0;
    double bodyTilt = 0.0;
    double breathScaleX = 1.0;
    double breathScaleY = 1.0;

    if (mood == ZapiMascotMood.speaking) {
      floatY = math.sin(rad * 10) * 3.2 * s;
      bodyTilt = math.sin(rad * 5) * 0.032;
      breathScaleX = 1.0 + math.sin(rad * 10) * 0.018;
      breathScaleY = 1.0 - math.sin(rad * 10) * 0.018;
    } else if (mood == ZapiMascotMood.waiting) {
      floatY = math.sin(rad * 3) * 3.0 * s;
      bodyTilt = math.sin(rad * 2) * 0.024;
    } else if (mood == ZapiMascotMood.excited) {
      floatY = -math.sin(rad * 6).abs() * 5.2 * s;
      bodyTilt = math.sin(rad * 6) * 0.04;
    } else if (mood == ZapiMascotMood.happy) {
      final hop = _pulse(t, 0.64, 0.82);
      floatY = (math.sin(rad * 2) * 2.8 - hop * 5.0) * s;
      bodyTilt =
          (math.sin(rad) * 0.022) + _pulse(t, 0.34, 0.60) * 0.045;
      breathScaleX = 1.0 + math.cos(rad * 2) * 0.016 - hop * 0.02;
      breathScaleY = 1.0 - math.cos(rad * 2) * 0.016 + hop * 0.025;
    }

    canvas.save();
    canvas.translate(dx, dy);

    final shadowFactor = (1.0 - (-floatY / (16.0 * s)).clamp(-0.15, 0.25));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(80 * s, 146 * s),
        width: 58 * s * shadowFactor,
        height: 9 * s,
      ),
      Paint()
        ..color = AppColors.emerald.withValues(alpha: isDark ? 0.24 : 0.18),
    );

    canvas.translate(80 * s, 88 * s + floatY);
    canvas.rotate(bodyTilt);
    canvas.scale(breathScaleX, breathScaleY);
    canvas.translate(-80 * s, -88 * s);

    final limbPaint = Paint()
      ..color = _inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final limbFill = Paint()
      ..color = _inkColor
      ..style = PaintingStyle.fill;

    double leftArmAngle = 0.0;
    double rightArmAngle = 0.0;
    double leftLegAngle = 0.0;
    double rightLegAngle = 0.0;

    switch (mood) {
      case ZapiMascotMood.happy:
        final waveEnvelope = _pulse(t, 0.33, 0.62);
        final waveOsc = math.sin(t * math.pi * 16) * 0.24;
        rightArmAngle = -waveEnvelope * (0.82 + waveOsc) +
            math.sin(rad * 2) * 0.06;
        leftArmAngle = math.sin(rad * 2) * 0.12 +
            _pulse(t, 0.65, 0.85) * 0.2;
        leftLegAngle = _pulse(t, 0.66, 0.82) * 0.18;
        rightLegAngle = -_pulse(t, 0.68, 0.84) * 0.16;
      case ZapiMascotMood.speaking:
        leftArmAngle = math.sin(rad * 9) * 0.32 + 0.14;
        rightArmAngle = -math.cos(rad * 11) * 0.38 - 0.3;
        leftLegAngle = math.sin(rad * 9) * 0.06;
        rightLegAngle = -math.sin(rad * 9) * 0.06;
      case ZapiMascotMood.waiting:
        rightArmAngle = -0.88 + math.sin(rad * 4) * 0.07;
        leftArmAngle = math.sin(rad * 2) * 0.07;
      case ZapiMascotMood.excited:
        leftArmAngle = 0.56 + math.sin(rad * 6) * 0.16;
        rightArmAngle = -0.74 - math.sin(rad * 6) * 0.16;
        leftLegAngle = math.sin(rad * 6) * 0.16;
        rightLegAngle = -math.sin(rad * 6) * 0.16;
      case ZapiMascotMood.resting:
        break;
    }

    // Capa de super-herói (tema Firebase) atrás do corpo
    final capeScaleX = mood == ZapiMascotMood.speaking ||
            mood == ZapiMascotMood.excited
        ? 1.04 + math.sin(rad * 10) * 0.03
        : 1.02 + math.sin(rad * 2) * 0.02;
    canvas.save();
    canvas.translate(80 * s, 70 * s);
    canvas.scale(capeScaleX, 1.0);
    canvas.translate(-80 * s, -70 * s);
    final capePath = Path()
      ..moveTo(44 * s, 70 * s)
      ..cubicTo(31 * s, 86 * s, 24 * s, 103 * s, 24 * s, 120 * s)
      ..quadraticBezierTo(52 * s, 114 * s, 80 * s, 118 * s)
      ..quadraticBezierTo(108 * s, 114 * s, 136 * s, 120 * s)
      ..cubicTo(136 * s, 103 * s, 129 * s, 86 * s, 116 * s, 70 * s)
      ..close();
    canvas.drawPath(
      capePath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4511E), Color(0xFFBF360C)],
        ).createShader(Rect.fromLTWH(24 * s, 70 * s, 112 * s, 50 * s)),
    );
    canvas.restore();

    // Perna esquerda minimalista
    canvas.save();
    canvas.translate(66 * s, 111 * s);
    canvas.rotate(leftLegAngle);
    final leftLeg = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-2 * s, 11 * s, -2 * s, 23 * s);
    canvas.drawPath(leftLeg, limbPaint);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-6.5 * s, 24.5 * s),
        width: 14 * s,
        height: 8 * s,
      ),
      limbFill,
    );
    canvas.restore();

    // Perna direita minimalista
    canvas.save();
    canvas.translate(94 * s, 111 * s);
    canvas.rotate(rightLegAngle);
    final rightLeg = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(2 * s, 11 * s, 2 * s, 23 * s);
    canvas.drawPath(rightLeg, limbPaint);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(6.5 * s, 24.5 * s),
        width: 14 * s,
        height: 8 * s,
      ),
      limbFill,
    );
    canvas.restore();

    // Braço esquerdo minimalista
    canvas.save();
    canvas.translate(31 * s, 81 * s);
    canvas.rotate(leftArmAngle);
    final leftArm = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-10 * s, 4.5 * s, -11.5 * s, 18 * s);
    canvas.drawPath(leftArm, limbPaint);
    canvas.drawCircle(Offset(-11 * s, 19 * s), 4.2 * s, limbFill);
    canvas.restore();

    // Braço direito minimalista
    canvas.save();
    canvas.translate(129 * s, 81 * s);
    canvas.rotate(rightArmAngle);
    final rightArm = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(10 * s, 4.5 * s, 11.5 * s, 18 * s);
    canvas.drawPath(rightArm, limbPaint);
    canvas.drawCircle(Offset(11 * s, 19 * s), 4.2 * s, limbFill);
    canvas.restore();

    // Corpo nuvem esmeralda minimalista (sem bordas e sem Z na testa)
    final cloudPath = Path()
      ..moveTo(80 * s, 25 * s)
      ..cubicTo(96 * s, 25 * s, 108 * s, 36 * s, 112 * s, 55 * s)
      ..cubicTo(125 * s, 58 * s, 134 * s, 70 * s, 133 * s, 86 * s)
      ..cubicTo(132 * s, 103 * s, 122 * s, 114 * s, 104 * s, 114 * s)
      ..quadraticBezierTo(80 * s, 116 * s, 56 * s, 114 * s)
      ..cubicTo(38 * s, 114 * s, 28 * s, 103 * s, 27 * s, 86 * s)
      ..cubicTo(26 * s, 70 * s, 35 * s, 58 * s, 48 * s, 55 * s)
      ..cubicTo(52 * s, 36 * s, 64 * s, 25 * s, 80 * s, 25 * s)
      ..close();

    final cloudBounds = Rect.fromLTWH(26 * s, 25 * s, 108 * s, 91 * s);
    canvas.drawPath(
      cloudPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF32EEB6),
            Color(0xFF00BE91),
            Color(0xFF009070),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(cloudBounds),
    );

    // Roupa de super-herói estilo Superman com tema Firebase
    canvas.save();
    canvas.clipPath(cloudPath);
    final suitPath = Path()
      ..moveTo(24 * s, 84 * s)
      ..quadraticBezierTo(56 * s, 81 * s, 80 * s, 86 * s)
      ..quadraticBezierTo(104 * s, 81 * s, 136 * s, 84 * s)
      ..lineTo(136 * s, 118 * s)
      ..lineTo(24 * s, 118 * s)
      ..close();
    canvas.drawPath(
      suitPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF9100),
            Color(0xFFF4511E),
            Color(0xFFDD2C00),
          ],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(24 * s, 80 * s, 112 * s, 38 * s)),
    );
    canvas.drawRect(
      Rect.fromLTWH(26 * s, 105 * s, 108 * s, 4.5 * s),
      Paint()..color = const Color(0xFFFFCA28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(74 * s, 104.2 * s, 12 * s, 6 * s),
        Radius.circular(2.4 * s),
      ),
      Paint()..color = const Color(0xFFFFE082),
    );
    canvas.restore();

    // Escudo estilo Superman no peito com o Z do Zapi
    final shieldPath = Path()
      ..moveTo(80 * s, 84.5 * s)
      ..lineTo(90.8 * s, 88.4 * s)
      ..lineTo(88.1 * s, 96.6 * s)
      ..lineTo(80 * s, 102.6 * s)
      ..lineTo(71.9 * s, 96.6 * s)
      ..lineTo(69.2 * s, 88.4 * s)
      ..close();
    canvas.drawPath(
      shieldPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE082),
            Color(0xFFFFCA28),
            Color(0xFFFFA000),
          ],
          stops: [0.0, 0.48, 1.0],
        ).createShader(Rect.fromLTWH(69 * s, 84.5 * s, 22 * s, 18.5 * s)),
    );

    final zCrestPath = Path()
      ..moveTo(75.4 * s, 89.8 * s)
      ..lineTo(84.6 * s, 89.8 * s)
      ..cubicTo(85.2 * s, 89.8 * s, 85.7 * s, 90.3 * s, 85.7 * s, 90.9 * s)
      ..cubicTo(85.7 * s, 91.3 * s, 85.5 * s, 91.7 * s, 85.1 * s, 91.9 * s)
      ..lineTo(78.4 * s, 96.2 * s)
      ..lineTo(84.6 * s, 96.2 * s)
      ..cubicTo(85.2 * s, 96.2 * s, 85.7 * s, 96.7 * s, 85.7 * s, 97.3 * s)
      ..cubicTo(85.7 * s, 97.9 * s, 85.2 * s, 98.4 * s, 84.6 * s, 98.4 * s)
      ..lineTo(75.4 * s, 98.4 * s)
      ..cubicTo(74.8 * s, 98.4 * s, 74.3 * s, 97.9 * s, 74.3 * s, 97.3 * s)
      ..cubicTo(74.3 * s, 96.9 * s, 74.5 * s, 96.5 * s, 74.9 * s, 96.3 * s)
      ..lineTo(81.6 * s, 92 * s)
      ..lineTo(75.4 * s, 92 * s)
      ..cubicTo(74.8 * s, 92 * s, 74.3 * s, 91.5 * s, 74.3 * s, 90.9 * s)
      ..cubicTo(74.3 * s, 90.3 * s, 74.8 * s, 89.8 * s, 75.4 * s, 89.8 * s)
      ..close();
    canvas.drawPath(
      zCrestPath,
      Paint()..color = const Color(0xFFD82E00),
    );

    final inkStroke = Paint()
      ..color = _inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final blink = math.max(
      _pulse(t, 0.24, 0.27),
      _pulse(t, 0.76, 0.79),
    );
    final eyeScaleY = (1.0 - blink * 0.9).clamp(0.1, 1.0);

    // Olhos minimalistas e proporcionais
    if (mood == ZapiMascotMood.resting) {
      final leftClosed = Path()
        ..moveTo(58 * s, 57 * s)
        ..quadraticBezierTo(65 * s, 61.5 * s, 72 * s, 57 * s);
      final rightClosed = Path()
        ..moveTo(88 * s, 57 * s)
        ..quadraticBezierTo(95 * s, 61.5 * s, 102 * s, 57 * s);
      canvas.drawPath(leftClosed, inkStroke);
      canvas.drawPath(rightClosed, inkStroke);
    } else if (mood == ZapiMascotMood.excited) {
      final leftHappy = Path()
        ..moveTo(57.5 * s, 59 * s)
        ..quadraticBezierTo(65 * s, 50.5 * s, 72.5 * s, 59 * s);
      final rightHappy = Path()
        ..moveTo(87.5 * s, 59 * s)
        ..quadraticBezierTo(95 * s, 50.5 * s, 102.5 * s, 59 * s);
      canvas.drawPath(leftHappy, inkStroke..strokeWidth = 3.2 * s);
      canvas.drawPath(rightHappy, inkStroke);
    } else {
      final gazeX = mood == ZapiMascotMood.waiting
          ? math.sin(rad * 4) * 1.8 * s
          : 0.0;
      final gazeY = mood == ZapiMascotMood.waiting ? -0.8 * s : 0.0;
      _drawCartoonEye(
        canvas,
        Offset(65 * s, 56 * s),
        Offset(0.4 * s + gazeX, 0.5 * s + gazeY),
        s,
        eyeScaleY,
        whiteFill,
        limbFill,
      );
      _drawCartoonEye(
        canvas,
        Offset(95 * s, 56 * s),
        Offset(-0.4 * s + gazeX, 0.5 * s + gazeY),
        s,
        eyeScaleY,
        whiteFill,
        limbFill,
      );
    }

    // Boca minimalista e proporcional
    if (mood == ZapiMascotMood.speaking) {
      final talkOpen = 0.42 + 0.64 * math.sin(rad * 16).abs();
      canvas.save();
      canvas.translate(80 * s, 72 * s);
      canvas.scale(1.0 + (talkOpen - 0.5) * 0.08, talkOpen);
      final mouthOval = Rect.fromCenter(
        center: Offset.zero,
        width: 12.8 * s,
        height: 9.6 * s,
      );
      canvas.clipPath(Path()..addOval(mouthOval));
      canvas.drawOval(mouthOval, limbFill);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, 3.2 * s),
          width: 8.4 * s,
          height: 5.0 * s,
        ),
        Paint()..color = const Color(0xFFFF7A9A),
      );
      canvas.restore();
    } else if (mood == ZapiMascotMood.waiting ||
        mood == ZapiMascotMood.resting) {
      final calmMouth = Path()
        ..moveTo(76 * s, 72 * s)
        ..quadraticBezierTo(80 * s, 70.5 * s, 84 * s, 72 * s);
      canvas.drawPath(calmMouth, inkStroke..strokeWidth = 2.8 * s);
    } else if (mood == ZapiMascotMood.excited) {
      final bigSmile = Path()
        ..moveTo(72.5 * s, 69.5 * s)
        ..quadraticBezierTo(80 * s, 70.6 * s, 87.5 * s, 69.5 * s)
        ..quadraticBezierTo(86.6 * s, 77 * s, 80 * s, 77 * s)
        ..quadraticBezierTo(73.4 * s, 77 * s, 72.5 * s, 69.5 * s)
        ..close();
      canvas.save();
      canvas.clipPath(bigSmile);
      canvas.drawPath(bigSmile, limbFill);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(80 * s, 75.2 * s),
          width: 7.2 * s,
          height: 3.6 * s,
        ),
        Paint()..color = const Color(0xFFFF7A9A),
      );
      canvas.restore();
    } else {
      final smile = Path()
        ..moveTo(73.5 * s, 70.5 * s)
        ..quadraticBezierTo(80 * s, 76.5 * s, 86.5 * s, 70.5 * s);
      canvas.drawPath(smile, inkStroke);
    }

    canvas.restore();
  }

  void _drawCartoonEye(
    Canvas canvas,
    Offset center,
    Offset pupilOffset,
    double s,
    double scaleY,
    Paint scleraPaint,
    Paint pupilPaint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, scaleY);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 15.2 * s, height: 17.2 * s),
      scleraPaint,
    );
    if (scaleY > 0.4) {
      canvas.drawCircle(pupilOffset, 4.3 * s, pupilPaint);
      canvas.drawCircle(
        pupilOffset + Offset(-1.5 * s, -1.8 * s),
        1.6 * s,
        scleraPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ZapinhoCloudPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.isDark != isDark ||
        oldDelegate.animation != animation;
  }
}

class ZapiSpeechBubble extends StatelessWidget {
  const ZapiSpeechBubble({
    super.key,
    required this.message,
    this.tailBottomCenter = true,
    this.maxWidth = 290,
  });

  final String message;
  final bool tailBottomCenter;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface;
    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                message,
                key: ValueKey(message),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: textColor,
                ),
              ),
            ),
          ),
          if (tailBottomCenter)
            CustomPaint(
              size: const Size(16, 8),
              painter: _BubbleTailPainter(color: bubbleColor),
            ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class ZapiMascotWithBubble extends StatelessWidget {
  const ZapiMascotWithBubble({
    super.key,
    required this.message,
    this.mood = ZapiMascotMood.happy,
    this.mascotSize = 104,
    this.maxBubbleWidth = 280,
    this.onMascotTap,
  });

  final String message;
  final ZapiMascotMood mood;
  final double mascotSize;
  final double maxBubbleWidth;
  final VoidCallback? onMascotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZapiSpeechBubble(
          message: message,
          maxWidth: maxBubbleWidth,
        ),
        const SizedBox(height: 6),
        ZapiMascot(
          mood: mood,
          size: mascotSize,
          onTap: onMascotTap,
        ),
      ],
    );
  }
}
