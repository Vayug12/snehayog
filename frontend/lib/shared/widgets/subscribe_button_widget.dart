import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/app_text.dart';

/// Canonical subscribe action used by every creator surface.
///
/// Relationship state stays with the caller; this widget owns the shared
/// visuals, labels, loading behavior, and tap affordance.
class SubscribeButtonWidget extends StatelessWidget {
  final bool isSubscribed;
  final bool isLoading;
  final VoidCallback? onPressed;
  final bool isFullWidth;

  const SubscribeButtonWidget({
    super.key,
    required this.isSubscribed,
    required this.onPressed,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;
    final label = AppText.get(
      isSubscribed ? 'btn_subscribed' : 'btn_subscribe',
    );

    final button = Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isEnabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          constraints: const BoxConstraints(
            minWidth: 96,
            minHeight: 32,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.spacing3,
            vertical: AppSpacing.spacing1,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSubscribed
                ? AppColors.backgroundTertiary
                : AppColors.backgroundSecondary.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: AppTypography.weightBold,
                  ),
                ),
        ),
      ),
    );

    return isFullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
