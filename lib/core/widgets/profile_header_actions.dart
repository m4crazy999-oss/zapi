import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ProfileHeaderIconPill extends StatelessWidget {
  const ProfileHeaderIconPill({
    super.key,
    required this.icon,
    required this.onDarkBackdrop,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final bool onDarkBackdrop;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bg = onDarkBackdrop
        ? Colors.black.withValues(alpha: 0.34)
        : Colors.white.withValues(alpha: 0.82);
    final fg = onDarkBackdrop ? Colors.white : AppColors.lightTextPrimary;

    final pill = Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: fg, size: 21),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: pill);
    }
    return pill;
  }
}

class ProfileHeaderActionPill extends StatelessWidget {
  const ProfileHeaderActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onDarkBackdrop,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool onDarkBackdrop;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = onDarkBackdrop
        ? Colors.black.withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: 0.86);
    final fg = onDarkBackdrop ? Colors.white : AppColors.lightTextPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
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
