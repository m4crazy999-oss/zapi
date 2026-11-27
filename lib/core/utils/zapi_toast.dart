import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ZapiToast {
  ZapiToast._();

  static void showError(
    BuildContext context,
    String message, {
    double bottomOffset = 16,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomOffset),
        duration: const Duration(milliseconds: 2600),
        elevation: 2,
        backgroundColor: isDark ? const Color(0xFF5C1D24) : AppColors.errorLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    double bottomOffset = 16,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomOffset),
        duration: const Duration(milliseconds: 2400),
        elevation: 2,
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : AppColors.lightTextPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndo(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    double bottomOffset = 16,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomOffset),
        duration: duration,
        elevation: 2,
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : AppColors.lightTextPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        action: SnackBarAction(
          label: 'Desfazer',
          textColor: AppColors.emeraldBright,
          onPressed: onUndo,
        ),
      ),
    );
  }
}
