import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class ProfileBannerPalette {
  const ProfileBannerPalette({
    required this.id,
    required this.colors,
    required this.accent,
    required this.particleColor,
  });

  final String id;
  final List<Color> colors;
  final Color accent;
  final Color particleColor;
}

class ProfileBanner extends StatefulWidget {
  const ProfileBanner({
    super.key,
    required this.preset,
    this.height = 176,
    this.borderRadius,
    this.child,
  });

  final String preset;
  final double height;
  final BorderRadius? borderRadius;
  final Widget? child;

  static ProfileBannerPalette paletteFor(String rawPreset) {
    switch (rawPreset.trim()) {
      case 'constellation':
        return const ProfileBannerPalette(
          id: 'constellation',
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F766E)],
          accent: Color(0xFF38BDF8),
          particleColor: Color(0xFFE0F2FE),
        );
      case 'waves':
        return const ProfileBannerPalette(
          id: 'waves',
          colors: [Color(0xFF075985), Color(0xFF0284C7), Color(0xFF00A884)],
          accent: Color(0xFF7DD3FC),
          particleColor: Color(0xFFE0F2FE),
        );
      case 'embers':
        return const ProfileBannerPalette(
          id: 'embers',
          colors: [Color(0xFF431407), Color(0xFF9A3412), Color(0xFFD97706)],
          accent: Color(0xFFFBBF24),
          particleColor: Color(0xFFFEF3C7),
        );
      case 'mint':
        return const ProfileBannerPalette(
          id: 'mint',
          colors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF34D399)],
          accent: Color(0xFFA7F3D0),
          particleColor: Color(0xFFECFDF5),
        );
      case 'midnight':
        return const ProfileBannerPalette(
          id: 'midnight',
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF0F766E)],
          accent: Color(0xFFA5B4FC),
          particleColor: Color(0xFFE0E7FF),
        );
      case 'aurora':
      default:
        return const ProfileBannerPalette(
          id: AppConstants.defaultBannerPreset,
          colors: [Color(0xFF052E2B), Color(0xFF008F70), Color(0xFF00C897)],
          accent: Color(0xFF5EEAD4),
          particleColor: Color(0xFFCCFBF1),
        );
    }
  }

  @override
  State<ProfileBanner> createState() => _ProfileBannerState();
}

class _ProfileBannerState extends State<ProfileBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ProfileBanner.paletteFor(widget.preset);
    final box = SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ProfileBannerPainter(
                    palette: palette,
                    progress: _controller.value,
                  ),
                );
              },
            ),
          ),
          if (widget.child != null) widget.child!,
        ],
      ),
    );

    if (widget.borderRadius == null) return box;
    return ClipRRect(
      borderRadius: widget.borderRadius!,
      child: box,
    );
  }
}

class _ProfileBannerPainter extends CustomPainter {
  const _ProfileBannerPainter({
    required this.palette,
    required this.progress,
  });

  final ProfileBannerPalette palette;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final t = progress * math.pi * 2;

    // Fundo em gradiente suave
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-0.9 + math.sin(t) * 0.15, -1.0),
        end: Alignment(0.9, 1.0 + math.cos(t) * 0.15),
        colors: palette.colors,
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // Aura difusa animada estilo Telegram
    final orb1Center = Offset(
      size.width * (0.25 + 0.12 * math.sin(t)),
      size.height * (0.36 + 0.10 * math.cos(t)),
    );
    final orb2Center = Offset(
      size.width * (0.76 + 0.10 * math.cos(t * 0.8)),
      size.height * (0.62 + 0.12 * math.sin(t * 0.8)),
    );

    canvas.drawCircle(
      orb1Center,
      size.width * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.accent.withValues(alpha: 0.26),
            palette.accent.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: orb1Center, radius: size.width * 0.34),
        ),
    );

    canvas.drawCircle(
      orb2Center,
      size.width * 0.30,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: orb2Center, radius: size.width * 0.30),
        ),
    );

    // Ondas fluidas discretas
    _drawWave(
      canvas,
      size,
      baseY: size.height * 0.64,
      amplitude: 14,
      phase: t,
      alpha: 0.10,
    );
    _drawWave(
      canvas,
      size,
      baseY: size.height * 0.78,
      amplitude: 10,
      phase: -t + 1.4,
      alpha: 0.08,
    );

    // Partículas sutis cintilantes
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 14; i++) {
      final seed = i * 1.73;
      final px = ((i * 0.073 + 0.06 + math.sin(t * 0.4 + seed) * 0.025) % 1.0) *
          size.width;
      final py = ((i * 0.131 + 0.14 + math.cos(t * 0.5 + seed) * 0.04) % 0.88) *
          size.height;
      final twinkle = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(t * 2 + seed * 2));
      final radius = (i % 3 == 0) ? 2.4 : 1.6;
      particlePaint.color =
          palette.particleColor.withValues(alpha: twinkle * 0.45);
      canvas.drawCircle(Offset(px, py), radius, particlePaint);
    }
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double amplitude,
    required double phase,
    required double alpha,
  }) {
    final path = Path()..moveTo(0, size.height);
    path.lineTo(0, baseY);

    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = (i / steps) * size.width;
      final normX = (i / steps) * math.pi * 2;
      final y = baseY + math.sin(normX + phase) * amplitude;
      path.lineTo(x, y);
    }

    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileBannerPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.palette.id != palette.id;
}
