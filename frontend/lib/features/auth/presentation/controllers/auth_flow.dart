import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/auth/domain/entities/auth_result.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// The single sign-in entry point for every screen.
///
/// Screens used to each decide what "success" meant, which is how a failed
/// backend exchange could still end in a success snackbar. Here the message is
/// derived from [AuthResult] alone, so all surfaces report the same truth:
/// success only after a real session, a neutral note on cancel, and the actual
/// reason on failure.
class AuthFlow {
  const AuthFlow._();

  /// Runs Google sign-in through [GoogleSignInController] and reports the
  /// outcome to the user.
  ///
  /// [onSuccess] runs only after a real session exists, and before the success
  /// message, so the screen is already refreshed when the user reads it.
  /// Returns the result so callers can navigate/gate on it.
  static Future<AuthResult> signIn(
    BuildContext context,
    WidgetRef ref, {
    Future<void> Function()? onSuccess,
    String? successMessage,
    bool showFeedback = true,
  }) async {
    final controller = ref.read(googleSignInProvider);
    final result = await controller.signIn();

    if (result.isSuccess) {
      try {
        await onSuccess?.call();
      } catch (e) {
        // A post-sign-in refresh failure is not a sign-in failure, but the user
        // must not be told everything is fine either.
        AppLogger.log('⚠️ AuthFlow: post sign-in refresh failed: $e');
        if (showFeedback && context.mounted) {
          VayuSnackBar.showWarning(
            context,
            AppText.get('error_sign_in_partial'),
          );
        }
        return result;
      }
    }

    if (!showFeedback || !context.mounted) return result;

    switch (result.outcome) {
      case AuthOutcome.success:
        VayuSnackBar.showSuccess(
          context,
          successMessage ?? AppText.get('profile_sign_in_success'),
          duration: const Duration(seconds: 2),
        );
        break;
      case AuthOutcome.cancelled:
        VayuSnackBar.showInfo(
          context,
          AppText.get('auth_sign_in_cancelled'),
          duration: const Duration(seconds: 2),
        );
        break;
      case AuthOutcome.failed:
        VayuSnackBar.showError(
          context,
          result.message ?? AppText.get('error_sign_in'),
        );
        break;
    }

    return result;
  }
}
