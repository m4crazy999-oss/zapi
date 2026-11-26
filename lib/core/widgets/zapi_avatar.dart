import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ZapiAvatar extends StatelessWidget {
  const ZapiAvatar({
    super.key,
    required this.displayName,
    this.photoBase64,
    this.photoUrl,
    this.radius = 28,
    this.showEditBadge = false,
    this.isLoading = false,
    this.onTap,
  });

  final String displayName;
  final String? photoBase64;
  final String? photoUrl;
  final double radius;
  final bool showEditBadge;
  final bool isLoading;
  final VoidCallback? onTap;

  // Cache em memória dos bytes já decodificados para rolagem fluida sem piscar.
  static final Map<String, Uint8List> _decodedCache = {};

  Uint8List? _decodePhotoBytes() {
    final raw = photoBase64?.trim();
    if (raw == null || raw.isEmpty) return null;

    final cached = _decodedCache[raw];
    if (cached != null) return cached;

    try {
      final clean = raw.contains(',') ? raw.split(',').last : raw;
      final bytes = base64Decode(clean);
      if (bytes.isEmpty) return null;
      if (_decodedCache.length > 150) {
        _decodedCache.clear();
      }
      _decodedCache[raw] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String _extractInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Z';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final photoBytes = _decodePhotoBytes();
    final hasLegacyUrl = photoBytes == null &&
        photoUrl != null &&
        photoUrl!.trim().isNotEmpty;
    final diameter = radius * 2;
    final initials = _extractInitials(displayName);

    Widget inner;
    if (photoBytes != null) {
      inner = Image.memory(
        photoBytes,
        fit: BoxFit.cover,
        width: diameter,
        height: diameter,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            _InitialsContent(initials: initials, radius: radius),
      );
    } else if (hasLegacyUrl) {
      inner = Image.network(
        photoUrl!,
        fit: BoxFit.cover,
        width: diameter,
        height: diameter,
        errorBuilder: (_, __, ___) =>
            _InitialsContent(initials: initials, radius: radius),
      );
    } else {
      inner = _InitialsContent(initials: initials, radius: radius);
    }

    Widget avatarCore = Container(
      width: diameter,
      height: diameter,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.emeraldBright, AppColors.emeraldDark],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    if (isLoading) {
      avatarCore = Stack(
        alignment: Alignment.center,
        children: [
          avatarCore,
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.45),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarCore,
        if (showEditBadge)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(radius * 0.16),
              decoration: BoxDecoration(
                color: AppColors.emerald,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2.5,
                ),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: radius * 0.34,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    if (onTap == null) return content;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: content,
    );
  }
}

class _InitialsContent extends StatelessWidget {
  const _InitialsContent({
    required this.initials,
    required this.radius,
  });

  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.68,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
