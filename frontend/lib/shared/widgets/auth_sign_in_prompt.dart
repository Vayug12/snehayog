import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/auth/presentation/controllers/auth_flow.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// The single sign-in gate for every screen locked behind auth.
///
/// Screens vary only in the icon and the optional copy above it — the button
/// itself (label, variant, width, loading state) is owned here so the same
/// action never shows up in two different shapes across the app.
class AuthSignInPrompt extends ConsumerWidget {
  const AuthSignInPrompt({
    super.key,
    this.icon = Icons.lock_outline,
    this.title,
    this.subtitle,
    this.onSignedIn,
  });

  /// Illustrative icon for the locked surface.
  final IconData icon;

  /// Optional heading. Omit it when the button alone is enough.
  final String? title;

  /// Optional supporting line. Only rendered when [title] is present.
  final String? subtitle;

  /// Runs only after a *successful* sign-in, so a cancelled flow never
  /// triggers a pointless reload. Callers must guard their own `mounted`.
  final Future<void> Function()? onSignedIn;

  Future<void> _handleSignIn(BuildContext context, WidgetRef ref) async {
    // One shared flow owns the outcome message for every locked surface.
    await AuthFlow.signIn(context, ref, onSuccess: onSignedIn);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authController = ref.watch(googleSignInProvider);
    final bool isLoading = authController.isLoading;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.textTertiary),
            if (title != null) ...[
              AppSpacing.vSpace24,
              Text(
                title!,
                style: AppTypography.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                AppSpacing.vSpace8,
                Text(
                  subtitle!,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            AppSpacing.vSpace32,
            AppButton(
              onPressed: isLoading ? null : () => _handleSignIn(context, ref),
              label: AppText.get('btn_sign_in_google'),
              variant: AppButtonVariant.primary,
              isFullWidth: true,
              isLoading: isLoading,
            ),
          ],
        ),
      ),
    );
  }
}
