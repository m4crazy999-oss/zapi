import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ZapiLogo extends StatelessWidget {
  const ZapiLogo({
    super.key,
    this.size = 64,
    this.showLabel = false,
  });

  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ZapiLogoPainter(),
      ),
    );

    if (!showLabel) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 12),
        Text(
          'Zapi',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
        ),
      ],
    );
  }
}

class _ZapiLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.24),
    );

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.emeraldBright, AppColors.emeraldDark],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRRect(bgRect, bgPaint);

    final bubblePaint = Paint()..color = Colors.white;
    final bubblePath = Path();
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.19, h * 0.21, w * 0.62, h * 0.54),
      Radius.circular(w * 0.22),
    );
    bubblePath.addRRect(bubbleRect);

    // Cauda do balão no canto inferior esquerdo
    final tailPath = Path()
      ..moveTo(w * 0.28, h * 0.68)
      ..lineTo(w * 0.22, h * 0.80)
      ..lineTo(w * 0.42, h * 0.73)
      ..close();
    bubblePath.addPath(tailPath, Offset.zero);
    canvas.drawPath(bubblePath, bubblePaint);

    // Letra Z geométrica em esmeralda
    final zPaint = Paint()
      ..color = AppColors.emerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final zPath = Path()
      ..moveTo(w * 0.37, h * 0.39)
      ..lineTo(w * 0.63, h * 0.39)
      ..lineTo(w * 0.37, h * 0.58)
      ..lineTo(w * 0.63, h * 0.58);

    canvas.drawPath(zPath, zPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
