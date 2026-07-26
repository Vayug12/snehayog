import 'package:flutter/material.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/services/profile_screen_logger.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/user_data_providers.dart';

class ProfileStatsWidget extends ConsumerWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final bool isVideosLoaded;
  final bool isFollowersLoaded;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onEarningsTap;
  final int? refreshKey;

  const ProfileStatsWidget({
    super.key,
    required this.stateManager,
    this.userId,
    required this.isVideosLoaded,
    required this.isFollowersLoaded,
    this.onFollowersTap,
    this.onEarningsTap,
    this.refreshKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileStateManager = ref.watch(profileStateManagerProvider);

    final videosLoading = profileStateManager.isVideosLoading;
    final videoCountValue = videosLoading
        ? '...'
        : (profileStateManager.totalVideoCount > 0
            ? profileStateManager.totalVideoCount
            : profileStateManager.userVideos.length);

    final bool shouldShowLoading = profileStateManager.isEarningsLoading ||
        (profileStateManager.isVideosLoading &&
            profileStateManager.cachedEarnings == 0);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowPrimary,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _buildStatColumn(
                context,
                'Videos',
                videoCountValue,
                isLoading: videosLoading,
              ),
            ),
            Container(width: 1, height: 40, color: AppColors.borderPrimary),
            Expanded(
              child: _buildStatColumn(
                context,
                'Subscribers',
                isFollowersLoaded ? _getFollowersCount(context, ref) : '...',
                isLoading: !isFollowersLoaded,
                onTap: onFollowersTap,
              ),
            ),
            Container(width: 1, height: 40, color: AppColors.borderPrimary),
            Expanded(
              child: _buildStatColumn(
                context,
                AppText.get('profile_stat_earnings'),
                shouldShowLoading
                    ? 'Loading...'
                    : profileStateManager.cachedEarnings,
                isEarnings: true,
                isLoading: shouldShowLoading,
                loadingText: 'Loading...',
                onTap: onEarningsTap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String label,
    dynamic value, {
    bool isEarnings = false,
    VoidCallback? onTap,
    bool isLoading = false,
    String? loadingText,
  }) {
    return RepaintBoundary(
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: isEarnings && onTap != null
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: Text(
                isLoading
                    ? (loadingText ?? '...')
                    : (isEarnings
                        ? (value is double
                                ? value
                                : double.tryParse(value.toString()) ?? 0.0)
                            .toStringAsFixed(2)
                        : value.toString()),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  int _getFollowersCount(BuildContext context, WidgetRef ref) {
    ProfileScreenLogger.logDebugInfo('=== GETTING FOLLOWERS COUNT ===');
    ProfileScreenLogger.logDebugInfo('userId: $userId');

    if (stateManager.userData != null) {
      final followersCount = stateManager.userData!['followersCount'] ??
          stateManager.userData!['followers'];

      if (followersCount != null && followersCount != 0) {
        ProfileScreenLogger.logDebugInfo(
          '✅ Using followers count from ProfileStateManager: $followersCount',
        );
        return followersCount is int
            ? followersCount
            : (int.tryParse(followersCount.toString()) ?? 0);
      }
    }

    final List<String> idsToTry = <String?>[
      userId,
      stateManager.userData?['googleId'],
      stateManager.userData?['_id'] ?? stateManager.userData?['id'],
    ]
        .where((e) => e != null && (e).isNotEmpty)
        .map((e) => e as String)
        .toList()
        .toSet()
        .toList();

    if (idsToTry.isNotEmpty) {
      final userProviderRef = ref.read(userProvider);
      for (final candidateId in idsToTry) {
        final userModel = userProviderRef.getUserData(candidateId);
        if (userModel?.followersCount != null &&
            userModel!.followersCount > 0) {
          ProfileScreenLogger.logDebugInfo(
            '✅ Using followers count from UserProvider for $candidateId: ${userModel.followersCount}',
          );
          return userModel.followersCount;
        }
      }
    }

    ProfileScreenLogger.logDebugInfo(
      '⚠️ No followers count available, using default: 0',
    );
    return 0;
  }
}
