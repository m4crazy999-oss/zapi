import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum PhotoFilterPreset {
  original('original', 'Original'),
  claro('claro', 'Claro'),
  quente('quente', 'Quente'),
  frio('frio', 'Frio'),
  pb('pb', 'P&B');

  const PhotoFilterPreset(this.id, this.label);

  final String id;
  final String label;

  static ui.ColorFilter? buildColorFilter(
    PhotoFilterPreset preset,
    double brightness,
  ) {
    final safeB = brightness.clamp(-0.35, 0.35);
    if (preset == PhotoFilterPreset.original && safeB.abs() < 0.01) {
      return null;
    }

    final base = switch (preset) {
      PhotoFilterPreset.original => <double>[
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ],
      PhotoFilterPreset.claro => <double>[
          1.08, 0, 0, 0, 14,
          0, 1.08, 0, 0, 14,
          0, 0, 1.08, 0, 14,
          0, 0, 0, 1, 0,
        ],
      PhotoFilterPreset.quente => <double>[
          1.12, 0.04, 0, 0, 8,
          0.02, 1.03, 0, 0, 2,
          0, 0, 0.88, 0, -6,
          0, 0, 0, 1, 0,
        ],
      PhotoFilterPreset.frio => <double>[
          0.90, 0, 0, 0, -4,
          0, 1.02, 0.04, 0, 2,
          0, 0.05, 1.15, 0, 10,
          0, 0, 0, 1, 0,
        ],
      PhotoFilterPreset.pb => <double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ],
    };

    final offset = safeB * 255.0;
    final combined = List<double>.from(base);
    combined[4] = combined[4] + offset;
    combined[9] = combined[9] + offset;
    combined[14] = combined[14] + offset;
    return ui.ColorFilter.matrix(combined);
  }
}

class DrawStroke {
  DrawStroke({
    required this.points,
    required this.color,
    required this.widthFraction,
  });

  final List<Offset> points;
  final Color color;
  final double widthFraction;
}

class TextOverlayItem {
  TextOverlayItem({
    required this.id,
    required this.text,
    required this.color,
    required this.fontKey,
    required this.withPill,
    this.nx = 0.5,
    this.ny = 0.45,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final String id;
  String text;
  Color color;
  String fontKey; // 'sans' | 'serif' | 'mono' | 'display'
  bool withPill;
  double nx;
  double ny;
  double scale;
  double rotation;
}

class StickerOverlayItem {
  StickerOverlayItem({
    required this.id,
    this.emoji,
    this.stickerImage,
    this.stickerBytes,
    this.nx = 0.5,
    this.ny = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final String id;
  final String? emoji;
  final ui.Image? stickerImage;
  final Uint8List? stickerBytes;
  double nx;
  double ny;
  double scale;
  double rotation;
}

TextStyle buildEditorOverlayTextStyle({
  required String fontKey,
  required Color color,
  required double fontSize,
  bool withShadow = true,
  bool isBold = true,
  bool isItalic = false,
}) {
  final shadow = withShadow
      ? [
          Shadow(
            color: Colors.black.withValues(alpha: 0.48),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ]
      : null;

  final weight = isBold ? FontWeight.w700 : FontWeight.w500;
  final style = isItalic ? FontStyle.italic : FontStyle.normal;

  return switch (fontKey) {
    'serif' => TextStyle(
        fontFamily: 'serif',
        fontSize: fontSize,
        fontWeight: weight,
        fontStyle: style,
        color: color,
        shadows: shadow,
      ),
    'mono' => TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: weight,
        fontStyle: style,
        color: color,
        shadows: shadow,
      ),
    'display' => TextStyle(
        fontSize: fontSize + 2,
        fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
        fontStyle: style,
        letterSpacing: -0.6,
        color: color,
        shadows: shadow,
      ),
    'handwriting' => TextStyle(
        fontFamily: 'cursive',
        fontSize: fontSize + 3,
        fontWeight: weight,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        color: color,
        shadows: shadow,
      ),
    'condensed' => TextStyle(
        fontFamily: 'sans-serif-condensed',
        fontSize: fontSize,
        fontWeight: weight,
        fontStyle: style,
        letterSpacing: -0.3,
        color: color,
        shadows: shadow,
      ),
    _ => TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        fontStyle: style,
        color: color,
        shadows: shadow,
      ),
  };
}
