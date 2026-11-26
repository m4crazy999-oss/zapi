import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

enum AttachmentAction {
  camera,
  gallery,
}

class AttachmentSheet extends StatelessWidget {
  const AttachmentSheet({super.key});

  static Future<AttachmentAction?> show(BuildContext context) {
    return showModalBottomSheet<AttachmentAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => const AttachmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enviar na conversa',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Câmera',
                  color: AppColors.emerald,
                  isDark: isDark,
                  onTap: () => Navigator.pop(context, AttachmentAction.camera),
                ),
                _AttachmentOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Galeria',
                  color: const Color(0xFF0284C7),
                  isDark: isDark,
                  onTap: () => Navigator.pop(context, AttachmentAction.gallery),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
