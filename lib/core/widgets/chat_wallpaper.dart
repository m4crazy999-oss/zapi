import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ChatWallpaperPreset {
  const ChatWallpaperPreset({
    required this.id,
    required this.name,
    required this.hasPattern,
    required this.lightGradient,
    required this.darkGradient,
    required this.lightPatternColor,
    required this.darkPatternColor,
    required this.previewAccent,
  });

  final String id;
  final String name;
  final bool hasPattern;
  final List<Color> lightGradient;
  final List<Color> darkGradient;
  final Color lightPatternColor;
  final Color darkPatternColor;
  final Color previewAccent;

  static const ChatWallpaperPreset defaultPattern = ChatWallpaperPreset(
    id: 'default_pattern',
    name: 'Padrão Zapi',
    hasPattern: true,
    lightGradient: [Color(0xFFF3F7F5), Color(0xFFE9F2EE)],
    darkGradient: [Color(0xFF0A1318), Color(0xFF0F1B22)],
    lightPatternColor: Color(0xFF008F70),
    darkPatternColor: Color(0xFF00C897),
    previewAccent: AppColors.emerald,
  );

  static const ChatWallpaperPreset emeraldMist = ChatWallpaperPreset(
    id: 'emerald_mist',
    name: 'Brisa Esmeralda',
    hasPattern: true,
    lightGradient: [Color(0xFFE7F5EE), Color(0xFFD5EDE1)],
    darkGradient: [Color(0xFF091B18), Color(0xFF0D2823)],
    lightPatternColor: Color(0xFF007A5E),
    darkPatternColor: Color(0xFF34D399),
    previewAccent: Color(0xFF10B981),
  );

  static const ChatWallpaperPreset oceanCalm = ChatWallpaperPreset(
    id: 'ocean_calm',
    name: 'Oceano Sereno',
    hasPattern: true,
    lightGradient: [Color(0xFFEBF3FA), Color(0xFFDCE8F5)],
    darkGradient: [Color(0xFF0B1522), Color(0xFF101F32)],
    lightPatternColor: Color(0xFF0284C7),
    darkPatternColor: Color(0xFF38BDF8),
    previewAccent: Color(0xFF0EA5E9),
  );

  static const ChatWallpaperPreset warmSand = ChatWallpaperPreset(
    id: 'warm_sand',
    name: 'Areia Suave',
    hasPattern: true,
    lightGradient: [Color(0xFFF7F2EA), Color(0xFFEFE6D8)],
    darkGradient: [Color(0xFF171411), Color(0xFF211C16)],
    lightPatternColor: Color(0xFF9A6B3F),
    darkPatternColor: Color(0xFFD6A87C),
    previewAccent: Color(0xFFD97706),
  );

  static const ChatWallpaperPreset violetNight = ChatWallpaperPreset(
    id: 'violet_night',
    name: 'Lavanda Sutil',
    hasPattern: true,
    lightGradient: [Color(0xFFF2EFFA), Color(0xFFE5DFF5)],
    darkGradient: [Color(0xFF131120), Color(0xFF1B172C)],
    lightPatternColor: Color(0xFF7C3AED),
    darkPatternColor: Color(0xFFA78BFA),
    previewAccent: Color(0xFF8B5CF6),
  );

  static const ChatWallpaperPreset minimalSolid = ChatWallpaperPreset(
    id: 'minimal_solid',
    name: 'Liso Discreto',
    hasPattern: false,
    lightGradient: [AppColors.lightBackground, AppColors.lightBackground],
    darkGradient: [AppColors.darkBackground, AppColors.darkBackground],
    lightPatternColor: AppColors.lightBorder,
    darkPatternColor: AppColors.darkBorder,
    previewAccent: Color(0xFF64748B),
  );

  static const List<ChatWallpaperPreset> all = [
    defaultPattern,
    emeraldMist,
    oceanCalm,
    warmSand,
    violetNight,
    minimalSolid,
  ];

  static ChatWallpaperPreset fromId(String? id) {
    if (id == null || id.isEmpty) return defaultPattern;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return defaultPattern;
  }
}

class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    super.key,
    required this.preset,
    required this.child,
  });

  final ChatWallpaperPreset preset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? preset.darkGradient : preset.lightGradient;
    final patternColor =
        isDark ? preset.darkPatternColor : preset.lightPatternColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: preset.hasPattern
          ? CustomPaint(
              painter: _ZapiWallpaperPainter(
                patternColor: patternColor,
                isDark: isDark,
              ),
              child: child,
            )
          : child,
    );
  }
}

class ChatWallpaperSwatch extends StatelessWidget {
  const ChatWallpaperSwatch({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ChatWallpaperPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? AppColors.emerald
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 82,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: selected ? 2.4 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ChatWallpaperBackground(
              preset: preset,
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    top: 12,
                    child: Container(
                      width: 34,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 30,
                    child: Container(
                      width: 40,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF005C4B)
                            : const Color(0xFFD9FDD3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      right: 6,
                      bottom: 6,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: AppColors.emerald,
                        child: Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? (isDark ? AppColors.emeraldBright : AppColors.emeraldDark)
                  : (isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZapiWallpaperPainter extends CustomPainter {
  const _ZapiWallpaperPainter({
    required this.patternColor,
    required this.isDark,
  });

  final Color patternColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = patternColor.withValues(alpha: isDark ? 0.055 : 0.065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = patternColor.withValues(alpha: isDark ? 0.055 : 0.065)
      ..style = PaintingStyle.fill;

    const tile = 92.0;
    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final offsetX = col * tile + (row.isOdd ? tile * 0.45 : 0.0);
        final offsetY = row * tile;
        final kind = (row * 3 + col * 5) % 4;

        switch (kind) {
          case 0:
            // Balão de conversa minimalista
            final rect = RRect.fromRectAndRadius(
              Rect.fromLTWH(offsetX + 14, offsetY + 18, 22, 16),
              const Radius.circular(6),
            );
            canvas.drawRRect(rect, strokePaint);
            final tail = Path()
              ..moveTo(offsetX + 19, offsetY + 34)
              ..lineTo(offsetX + 16, offsetY + 39)
              ..lineTo(offsetX + 25, offsetY + 34);
            canvas.drawPath(tail, strokePaint);
          case 1:
            // Brilho de 4 pontas (estrela geométrica)
            final cx = offsetX + 46;
            final cy = offsetY + 28;
            const r = 8.0;
            final star = Path()
              ..moveTo(cx, cy - r)
              ..quadraticBezierTo(cx, cy, cx + r, cy)
              ..quadraticBezierTo(cx, cy, cx, cy + r)
              ..quadraticBezierTo(cx, cy, cx - r, cy)
              ..quadraticBezierTo(cx, cy, cx, cy - r);
            canvas.drawPath(star, strokePaint);
          case 2:
            // Onda sonora curta (3 barrinhas)
            final baseX = offsetX + 26;
            final cy = offsetY + 56;
            canvas.drawLine(
              Offset(baseX, cy - 4),
              Offset(baseX, cy + 4),
              strokePaint,
            );
            canvas.drawLine(
              Offset(baseX + 6, cy - 8),
              Offset(baseX + 6, cy + 8),
              strokePaint,
            );
            canvas.drawLine(
              Offset(baseX + 12, cy - 5),
              Offset(baseX + 12, cy + 5),
              strokePaint,
            );
          case 3:
            // Arco suave + ponto
            canvas.drawArc(
              Rect.fromCircle(
                center: Offset(offsetX + 58, offsetY + 60),
                radius: 9,
              ),
              -math.pi * 0.8,
              math.pi * 1.15,
              false,
              strokePaint,
            );
        }

        canvas.drawCircle(
          Offset(offsetX + 74, offsetY + 14),
          1.7,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZapiWallpaperPainter oldDelegate) {
    return oldDelegate.patternColor != patternColor ||
        oldDelegate.isDark != isDark;
  }
}
