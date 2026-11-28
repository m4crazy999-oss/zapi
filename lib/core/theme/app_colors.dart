import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Cor principal da marca
  static const Color emerald = Color(0xFF00A884);
  static const Color emeraldDark = Color(0xFF008F70);
  static const Color emeraldBright = Color(0xFF00C897);

  // Tema Claro
  static const Color lightBackground = Color(0xFFF3F6F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFE9EFEC);
  static const Color lightBorder = Color(0xFFDCE5E1);
  static const Color lightTextPrimary = Color(0xFF111B21);
  static const Color lightTextSecondary = Color(0xFF54656F);

  // Tema Escuro
  static const Color darkBackground = Color(0xFF0A1115);
  static const Color darkSurface = Color(0xFF131E25);
  static const Color darkSurfaceAlt = Color(0xFF1B2A33);
  static const Color darkBorder = Color(0xFF233642);
  static const Color darkTextPrimary = Color(0xFFE9EDEF);
  static const Color darkTextSecondary = Color(0xFF8696A0);

  // Estados semânticos
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);
  static const Color success = Color(0xFF16A34A);
}

enum AccentPreset {
  esmeralda(
    id: 'esmeralda',
    label: 'Esmeralda',
    primaryLight: Color(0xFF00A884),
    secondaryLight: Color(0xFF008F70),
    primaryDark: Color(0xFF00C897),
    secondaryDark: Color(0xFF00A884),
    onPrimaryDark: Color(0xFF04221B),
  ),
  oceano(
    id: 'oceano',
    label: 'Oceano',
    primaryLight: Color(0xFF0284C7),
    secondaryLight: Color(0xFF0369A1),
    primaryDark: Color(0xFF38BDF8),
    secondaryDark: Color(0xFF0284C7),
    onPrimaryDark: Color(0xFF06202E),
  ),
  violeta(
    id: 'violeta',
    label: 'Violeta',
    primaryLight: Color(0xFF7C3AED),
    secondaryLight: Color(0xFF6D28D9),
    primaryDark: Color(0xFFA78BFA),
    secondaryDark: Color(0xFF7C3AED),
    onPrimaryDark: Color(0xFF1E0B3B),
  ),
  ambar(
    id: 'ambar',
    label: 'Âmbar',
    primaryLight: Color(0xFFD97706),
    secondaryLight: Color(0xFFB45309),
    primaryDark: Color(0xFFFBBF24),
    secondaryDark: Color(0xFFD97706),
    onPrimaryDark: Color(0xFF2B1803),
  ),
  rosa(
    id: 'rosa',
    label: 'Rosa',
    primaryLight: Color(0xFFDB2777),
    secondaryLight: Color(0xFFBE185D),
    primaryDark: Color(0xFFF472B6),
    secondaryDark: Color(0xFFDB2777),
    onPrimaryDark: Color(0xFF330619),
  );

  const AccentPreset({
    required this.id,
    required this.label,
    required this.primaryLight,
    required this.secondaryLight,
    required this.primaryDark,
    required this.secondaryDark,
    required this.onPrimaryDark,
  });

  final String id;
  final String label;
  final Color primaryLight;
  final Color secondaryLight;
  final Color primaryDark;
  final Color secondaryDark;
  final Color onPrimaryDark;

  static AccentPreset fromId(String? id) {
    for (final preset in values) {
      if (preset.id == id) return preset;
    }
    return AccentPreset.esmeralda;
  }
}

