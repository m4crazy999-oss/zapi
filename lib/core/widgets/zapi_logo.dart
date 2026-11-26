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
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _ZapiLogoPainter(),
        ),
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
    final side = size.shortestSide;
    if (side <= 0) return;

    final offsetX = (size.width - side) / 2;
    final offsetY = (size.height - side) / 2;
    final s = side / 1024.0;

    canvas.save();
    canvas.translate(offsetX, offsetY);

    final bounds = Rect.fromLTWH(0, 0, side, side);
    final bgRect = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(224.0 * s),
    );
    canvas.clipRRect(bgRect);

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.emeraldBright, AppColors.emeraldDark],
      ).createShader(bounds);

    canvas.drawRect(bounds, bgPaint);

    // Balão em contorno único contínuo (sem sobreposição de subpaths ou inversão de winding)
    final bubblePath = Path()
      ..moveTo(512.0 * s, 222.0 * s)
      ..cubicTo(340.79 * s, 222.0 * s, 202.0 * s, 346.29 * s, 202.0 * s, 499.6 * s)
      ..cubicTo(202.0 * s, 567.7 * s, 229.4 * s, 630.05 * s, 274.88 * s, 678.2 * s)
      ..lineTo(232.0 * s, 798.0 * s)
      ..lineTo(361.4 * s, 756.7 * s)
      ..cubicTo(407.4 * s, 770.1 * s, 458.5 * s, 777.2 * s, 512.0 * s, 777.2 * s)
      ..cubicTo(683.21 * s, 777.2 * s, 822.0 * s, 652.91 * s, 822.0 * s, 499.6 * s)
      ..cubicTo(822.0 * s, 346.29 * s, 683.21 * s, 222.0 * s, 512.0 * s, 222.0 * s)
      ..close();

    final bubblePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(bubblePath, bubblePaint);

    // Letra Z desenhada em 3 segmentos independentes com extremidades arredondadas
    final zPaint = Paint()
      ..color = AppColors.emerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = 68.0 * s
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final topLeft = Offset(394.0 * s, 400.0 * s);
    final topRight = Offset(630.0 * s, 400.0 * s);
    final bottomLeft = Offset(394.0 * s, 600.0 * s);
    final bottomRight = Offset(630.0 * s, 600.0 * s);

    canvas.drawLine(topLeft, topRight, zPaint);
    canvas.drawLine(topRight, bottomLeft, zPaint);
    canvas.drawLine(bottomLeft, bottomRight, zPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
