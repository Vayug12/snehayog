import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/subscription_providers.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/widgets/auth_sign_in_prompt.dart';
import 'package:vayug/shared/widgets/unified_video_card.dart';
import 'package:vayug/shared/widgets/vayu_video_card.dart';
import 'package:vayug/features/video/subscriptions/presentation/managers/subscription_state_manager.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  bool? _wasSignedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(subscriptionStateManagerProvider).loadSubscriberContent();
    });
  }

  void _navigateToVideo(VideoModel video, List<VideoModel> allVideos) {
    if (video.videoType == 'vayu') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VayuLongFormPlayerScreen(
            video: video,
            relatedVideos:
                allVideos.where((v) => v.videoType == 'vayu').toList(),
          ),
        ),
      );
    } else {
      final yugVideos = allVideos.where((v) => v.videoType != 'vayu').toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoScreen(
            initialVideos: yugVideos,
            initialIndex: yugVideos
                .indexWhere((v) => v.id == video.id)
                .clamp(0, yugVideos.length),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;
    final state = ref.watch(subscriptionStateManagerProvider);

    // React to Auth Changes
    if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
      _wasSignedIn = isSignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (isSignedIn) {
            ref
                .read(subscriptionStateManagerProvider)
                .loadSubscriberContent(refresh: true);
          } else {
            ref.read(subscriptionStateManagerProvider).reset();
          }
        }
      });
    }
    _wasSignedIn = isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(subscriptionStateManagerProvider)
            .loadSubscriberContent(refresh: true),
        color: Colors.white,
        backgroundColor: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(),
            if (isSignedIn && state.allVideos.isNotEmpty) ...[
              if (state.exclusiveVideos.isNotEmpty) _buildExclusiveShelf(state),
              ..._buildFeedSlivers(state),
            ] else
              ..._buildBodySlivers(isSignedIn, state),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.backgroundPrimary,
      floating: true,
      snap: true,
      elevation: 0,
      title: Text(
        'Subscriptions',
        style: AppTypography.titleLarge
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      actions: [
        _buildGuideButton(context),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildExclusiveShelf(SubscriptionStateManager state) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: state.exclusiveVideos.length,
              itemBuilder: (context, index) {
                final video = state.exclusiveVideos[index];
                final isVayu = video.videoType == 'vayu';
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: SizedBox(
                    width: isVayu ? 280 : 100,
                    child: UnifiedVideoCard(
                      video: video,
                      cardType: isVayu ? UnifiedVideoCardType.vayu : UnifiedVideoCardType.yug,
                      onTap: () => _navigateToVideo(video, state.allVideos),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }



  List<Widget> _buildFeedSlivers(SubscriptionStateManager state) {
    final List<Widget> slivers = [];
    final videos = state.feedVideos;
    if (videos.isEmpty) return slivers;

    int i = 0;
    while (i < videos.length) {
      final video = videos[i];
      if (video.videoType == 'vayu') {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: VayuVideoCard(
                video: video,
                onTap: () => _navigateToVideo(video, state.allVideos),
              ),
            ),
          ),
        );
        i++;
      } else {
        final List<VideoModel> yugGroup = [];
        while (i < videos.length && videos[i].videoType != 'vayu') {
          yugGroup.add(videos[i]);
          i++;
        }

        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final yugVideo = yugGroup[index];
                  return UnifiedVideoCard(
                    video: yugVideo,
                    cardType: UnifiedVideoCardType.yug,
                    onTap: () => _navigateToVideo(yugVideo, state.allVideos),
                  );
                },
                childCount: yugGroup.length,
              ),
            ),
          ),
        );
      }
    }

    return slivers;
  }

  List<Widget> _buildBodySlivers(
      bool isSignedIn, SubscriptionStateManager state) {
    if (!isSignedIn) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildSignInPrompt())
      ];
    }
    if (state.isLoading && state.allVideos.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildShimmerList())
      ];
    }
    if (state.status == SubscriptionStatus.error && state.allVideos.isEmpty) {
      return [
        SliverFillRemaining(
            hasScrollBody: false, child: _buildErrorView(state.errorMessage))
      ];
    }
    if (state.allVideos.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
      ];
    }

    return _buildFeedSlivers(state);
  }

  /// The screen already reloads on an auth change, so no post-sign-in
  /// callback is needed here.
  Widget _buildSignInPrompt() {
    // The title names what is behind the gate; the button names the action.
    return const AuthSignInPrompt(
      icon: Icons.people_outline,
      title: 'Subscriber-only videos',
    );
  }

  Widget _buildErrorView(String? message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.textSecondary, size: 60),
          const SizedBox(height: 16),
          Text(message ?? 'Unknown error', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => ref
                .read(subscriptionStateManagerProvider)
                .loadSubscriberContent(refresh: true),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text('No subscriber content yet'));
  }

  // Note: _buildVideoCard was removed as it is replaced by the unified VayuVideoCard widget

  Widget _buildShimmerList() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildGuideButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: AppColors.primary.withValues(alpha: 0.1),
          highlightColor: AppColors.primary.withValues(alpha: 0.05),
        ),
        child: InkWell(
          onTap: () => _showGuideDialog(context),
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
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primaryLight,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Help',
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

  void _showGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primaryLight,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Exclusive Videos',
                    style: AppTypography.titleLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Ye exclusive videos hain jo creators ne specially aapke liye publish kiye hain. Isko aapke alawa aur koi nahi dekh sakta.',
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Samajh Gaya',
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
