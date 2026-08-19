import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

/// Small outlined "Help" pill (icon + label) for app bar corners.
///
/// Shared by the Subscriptions and Profile app bars so the entry point looks
/// identical wherever a guide is offered.
class HelpPillButton extends StatelessWidget {
  const HelpPillButton({
    super.key,
    required this.onTap,
    this.label = 'Help',
    this.icon = Icons.info_outline_rounded,
    this.margin = const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
  });

  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: AppColors.primary.withValues(alpha: 0.1),
          highlightColor: AppColors.primary.withValues(alpha: 0.05),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
                width: 1.2,
              ),
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
