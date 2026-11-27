import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Capa simples e minimalista no topo do perfil, sem desfoque nem bordas artificiais.
class ProfileBanner extends StatefulWidget {
  const ProfileBanner({
    super.key,
    this.bannerBase64,
    this.height = 200,
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
    final emptyBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE7EEEC);

    final bannerBox = SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Image.memory(
              _cachedBytes!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => ColoredBox(color: emptyBg),
            )
          else
            ColoredBox(color: emptyBg),
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
