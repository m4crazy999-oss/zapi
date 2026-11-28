import 'package:flutter/material.dart';

import 'editor_models.dart';

class EditorStrokesPainter extends CustomPainter {
  const EditorStrokesPainter({
    required this.strokes,
    required this.activeStroke,
  });

  final List<DrawStroke> strokes;
  final DrawStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [
      ...strokes,
      if (activeStroke != null) activeStroke!,
    ];

    for (final stroke in all) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = (stroke.widthFraction * size.width).clamp(2.0, 22.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        final pt = Offset(
          stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height,
        );
        canvas.drawCircle(
          pt,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()
          ..moveTo(
            stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height,
          );
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(
            stroke.points[i].dx * size.width,
            stroke.points[i].dy * size.height,
          );
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant EditorStrokesPainter oldDelegate) => true;
}

class EditorTrashZone extends StatelessWidget {
  const EditorTrashZone({
    super.key,
    required this.overTrash,
    required this.isText,
  });

  final bool overTrash;
  final bool isText;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: overTrash
                ? const Color(0xFFDC2626)
                : Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: overTrash ? Colors.white : Colors.white38,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.delete_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                overTrash
                    ? 'Solte para apagar'
                    : (isText
                        ? 'Arraste aqui para apagar texto'
                        : 'Arraste aqui para apagar'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
