import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/providers/profile_providers.dart';

/// Red dot marking subscribers the creator has not looked at yet.
///
/// Watches only the badge flag, so a count change never rebuilds the profile
/// header around it. Renders nothing when there is nothing new.
class NewSubscribersDot extends ConsumerWidget {
  const NewSubscribersDot({
    super.key,
    this.size = 8,
    this.enabled = true,
  });

  final double size;

  /// Own profile only — nobody sees another creator's unseen state.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) return const SizedBox.shrink();

    final hasNewSubscribers = ref.watch(
      subscribersBadgeManagerProvider.select((m) => m.hasNewSubscribers),
    );
    if (!hasNewSubscribers) return const SizedBox.shrink();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.error,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.45),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
