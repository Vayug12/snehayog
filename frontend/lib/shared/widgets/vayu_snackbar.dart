import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

enum VayuSnackBarType { 
  success, 
  error, 
  info, 
  warning 
}

class VayuSnackBar {
  VayuSnackBar._();

  /// Shows a consistent, orientation-aware SnackBar.
  static void show(
    BuildContext context, 
    String message, {
    VayuSnackBarType type = VayuSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    IconData? icon,
  }) {
    try {
      // **FIX: Robust safety check for async context usage**
      if (context.mounted != true) return;

      final messenger = ScaffoldMessenger.of(context);
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Clear existing snackbars
    messenger.hideCurrentSnackBar();

    // Minimal style: one neutral elevated surface for every type; the status
    // is carried by a small tinted icon, never by a loud background color.
    Color accentColor;
    IconData? defaultIcon;

    switch (type) {
      case VayuSnackBarType.success:
        accentColor = AppColors.success;
        defaultIcon = Icons.check_circle_rounded;
        break;
      case VayuSnackBarType.error:
        accentColor = AppColors.error;
        defaultIcon = Icons.error_outline_rounded;
        break;
      case VayuSnackBarType.warning:
        accentColor = AppColors.warning;
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case VayuSnackBarType.info:
        accentColor = AppColors.textSecondary;
        defaultIcon = Icons.info_outline_rounded;
        break;
    }

    final effectiveIcon = icon ?? defaultIcon;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(effectiveIcon, color: accentColor, size: isLandscape ? 16 : 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: isLandscape ? 13.0 : 14.0,
                  height: 1.35,
                  letterSpacing: -0.1,
                ),
                textAlign: isLandscape ? TextAlign.center : TextAlign.start,
              ),
            ),
          ],
        ),
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.backgroundSecondary.withValues(alpha: 0.98),
        width: isLandscape ? 340.0 : null,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: isLandscape
          ? null
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      ),
    );
    } catch (e) {
      // Gracefully handle context deactivated during snackbar configuration
      debugPrint('⚠️ VayuSnackBar: Error showing snackbar: $e');
    }
  }

  // Helper methods for common types
  static void showSuccess(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.success, duration: duration ?? const Duration(seconds: 3), action: action);
  }

  static void showError(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.error, duration: duration ?? const Duration(seconds: 4), action: action);
  }

  static void showInfo(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.info, duration: duration ?? const Duration(seconds: 3), action: action);
  }

  static void showWarning(BuildContext context, String message, {Duration? duration, SnackBarAction? action}) {
    show(context, message, type: VayuSnackBarType.warning, duration: duration ?? const Duration(seconds: 3), action: action);
  }
}
