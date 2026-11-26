import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Banner de perfil estilo Telegram: exibe a imagem ou GIF enviado pelo usuário
/// (ou um degradê ambiente sutil quando não há banner) com desfoque progressivo
/// e dissolução pura por canal alfa até 100% transparente antes da borda,
/// garantindo transição invisível sobre qualquer fundo sem linha de corte.
class ProfileBanner extends StatefulWidget {
  const ProfileBanner({
    super.key,
    this.bannerBase64,
    this.height = 248,
    this.borderRadius,
    this.child,
  });

  final String? bannerBase64;
  final double height;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  State<ProfileBanner> createState() => _ProfileBannerState();
}

class _ProfileBannerState extends State<ProfileBanner> {
  String? _cachedRaw;
  Uint8List? _cachedBytes;

  @override
  void initState() {
    super.initState();
    _syncBytes();
  }

  @override
  void didUpdateWidget(covariant ProfileBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bannerBase64 != widget.bannerBase64) {
      _syncBytes();
    }
  }

  void _syncBytes() {
    final raw = widget.bannerBase64?.trim();
    if (raw == _cachedRaw) return;
    _cachedRaw = raw;
    if (raw == null || raw.isEmpty) {
      _cachedBytes = null;
      return;
    }
    try {
      _cachedBytes = base64Decode(raw);
    } catch (_) {
      _cachedBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = _cachedBytes != null && _cachedBytes!.isNotEmpty;

    final Widget baseVisual = hasImage
        ? SizedBox.expand(
            child: Image.memory(
              _cachedBytes!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) =>
                  _FallbackAmbientBanner(isDark: isDark),
            ),
          )
        : SizedBox.expand(
            child: _FallbackAmbientBanner(isDark: isDark),
          );

    // Rampa progressiva contínua de desfoque (0 -> sigma 8 -> sigma 22)
    final progressiveBlurredVisual = Stack(
      fit: StackFit.expand,
      children: [
        baseVisual,
        if (hasImage)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.26),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.32],
                ),
              ),
            ),
          ),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.white.withValues(alpha: 0.48),
              Colors.white,
              Colors.white,
            ],
            stops: const [0.0, 0.22, 0.38, 0.56, 1.0],
          ).createShader(bounds),
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 8,
                sigmaY: 8,
                tileMode: TileMode.clamp,
              ),
              child: baseVisual,
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.white.withValues(alpha: 0.45),
              Colors.white,
              Colors.white,
            ],
            stops: const [0.0, 0.36, 0.54, 0.72, 1.0],
          ).createShader(bounds),
          child: ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 22,
                sigmaY: 22,
                tileMode: TileMode.clamp,
              ),
              child: baseVisual,
            ),
          ),
        ),
      ],
    );

    // Dissolução pura por canal alfa: chega em 0% de opacidade em 0.86,
    // deixando os últimos 14% totalmente vazios para o fundo real aparecer
    // sem diferença de cor nem linha de borda.
    final dissolvedBanner = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white,
          Colors.white,
          Colors.white.withValues(alpha: 0.94),
          Colors.white.withValues(alpha: 0.78),
          Colors.white.withValues(alpha: 0.54),
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.13),
          Colors.white.withValues(alpha: 0.04),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [
          0.0,
          0.26,
          0.36,
          0.46,
          0.56,
          0.65,
          0.74,
          0.81,
          0.87,
          1.0,
        ],
      ).createShader(bounds),
      child: progressiveBlurredVisual,
    );

    final bannerBox = SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          dissolvedBanner,
          if (widget.child != null) widget.child!,
        ],
      ),
    );

    if (widget.borderRadius == null) return bannerBox;
    return ClipRRect(
      borderRadius: widget.borderRadius!,
      child: bannerBox,
    );
  }
}

class _FallbackAmbientBanner extends StatelessWidget {
  const _FallbackAmbientBanner({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.4),
          radius: 1.15,
          colors: isDark
              ? [
                  AppColors.emerald.withValues(alpha: 0.44),
                  const Color(0xFF103133),
                  const Color(0xFF0C1D24),
                ]
              : [
                  AppColors.emerald.withValues(alpha: 0.34),
                  const Color(0xFFC5ECE1),
                  const Color(0xFFE7F5F1),
                ],
        ),
      ),
    );
  }
}
