import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as provider;
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/features/video/edit/presentation/screens/edit_video_details.dart';
import 'package:vayug/shared/widgets/episode_grid_widget.dart';
import 'package:vayug/shared/widgets/unified_video_card.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/shared/utils/format_utils.dart';

class ProfileVideosWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVideoLongPress;
  final VoidCallback? onVideoSelection;
  final bool showHeader;
  final bool isSliver;
  final bool useListLayout;
  final String? filterVideoType;
  final VoidCallback? onReferFriends;
  final bool hasReferralBillingUnlock;

  const ProfileVideosWidget({
    super.key,
    required this.stateManager,
    this.onVideoTap,
    this.onVideoLongPress,
    this.onVideoSelection,
    this.showHeader = true,
    this.isSliver = false,
    this.useListLayout = false,
    this.filterVideoType,
    this.onReferFriends,
    this.hasReferralBillingUnlock = false,
  });

  static Widget buildRefreshNotice(
    BuildContext context,
    ProfileStateManager manager,
  ) {
    final isRetrying = manager.isVideosLoading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          border: Border.all(color: AppColors.borderPrimary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Couldn\'t refresh. Showing saved videos.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              onPressed: isRetrying ? null : () => manager.refreshVideosOnly(),
              child: Text(isRetrying ? 'Trying...' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _preloadVideoThumbnails(BuildContext context, List<VideoModel> videos) {
    Future.microtask(() async {
      for (final video in videos.take(5)) {
        if (video.thumbnailUrl.isNotEmpty) {
          try {
            await precacheImage(NetworkImage(video.thumbnailUrl), context);
          } catch (e) {
            AppLogger.log(
                '⚠️ ProfileVideosWidget: Failed to preload thumbnail: $e');
          }
        }
      }
    });
  }

  bool _isVideoProcessing(VideoModel video) {
    final status = video.processingStatus.toLowerCase();
    return video.isOptimistic ||
        status == 'queued' ||
        status == 'pending' ||
        status == 'processing';
  }

  String _normalizedVideoType(VideoModel video) {
    if (video.aspectRatio > 1.1) return 'vayu';
    if (video.aspectRatio < 0.9) return 'yog';

    final normalized = video.videoType.trim().toLowerCase();
    if (normalized == 'long' ||
        normalized == 'longform' ||
        normalized == 'long_form' ||
        normalized == 'long-form') {
      return 'vayu';
    }
    if (normalized == 'short' ||
        normalized == 'shortform' ||
        normalized == 'short_form' ||
        normalized == 'short-form' ||
        normalized == 'reel') {
      return 'yog';
    }
    if (normalized == 'vayu' || normalized == 'yog') {
      return normalized;
    }
    return normalized;
  }

  bool _matchesFilter(VideoModel video) {
    if (filterVideoType == null || filterVideoType!.isEmpty) return true;
    
    final normalizedType = _normalizedVideoType(video);
    return normalizedType == filterVideoType!.toLowerCase();
  }

  Widget _asSliver(Widget child) =>
      isSliver ? SliverToBoxAdapter(child: child) : child;

  Widget _buildVideoLoadError(BuildContext context, ProfileStateManager manager) {
    final isRetrying = manager.isVideosLoading;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 14),
            const Text(
              'Couldn\'t load videos',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: isRetrying
                  ? null
                  : () => manager.refreshVideosOnly(),
              icon: isRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(isRetrying ? 'Trying again...' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmedEmptyState(ProfileStateManager manager) {
    if (!hasReferralBillingUnlock) {
      return const SizedBox.shrink();
    }
    return const RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 34, 24, 34),
        child: Column(
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 40,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: 12),
            Text(
              'You haven\'t uploaded any videos yet.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    final label = filterVideoType?.toLowerCase() == 'vayu' ? 'Vayu' : 'Yug';
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 42, 24, 42),
        child: Column(
          children: [
            const Icon(Icons.video_library_outlined,
                size: 38, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No $label videos yet.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (stateManager.userVideos.isNotEmpty) {
      _preloadVideoThumbnails(context, stateManager.userVideos);
    }

    return provider.Consumer<ProfileStateManager>(
      builder: (context, manager, child) {
        if (manager.isVideosLoading && manager.userVideos.isEmpty) {
          final loadingWidget = RepaintBoundary(
            child: SizedBox(
              height: 200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.shade500,
                      ),
                      backgroundColor: Colors.green.shade100,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fetching your videos...',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
          return isSliver
              ? SliverToBoxAdapter(child: loadingWidget)
              : loadingWidget;
        }

        final List<VideoModel> filteredVideos =
            manager.userVideos.where(_matchesFilter).toList(growable: false);

        if (manager.error != null && manager.userVideos.isEmpty) {
          return _asSliver(_buildVideoLoadError(context, manager));
        }

        if (manager.userVideos.isEmpty) {
          final isConfirmedEmpty =
              manager.hasLoadedVideosSuccessfully && manager.totalVideoCount == 0;
          return _asSliver(
            isConfirmedEmpty
                ? _buildConfirmedEmptyState(manager)
                : _buildVideoLoadError(context, manager),
          );
        }

        if (filteredVideos.isEmpty) {
          return _asSliver(_buildFilteredEmptyState());
        }

        final List<VideoModel> displayVideos = [];
        final Set<String> processedSeriesIds = {};

        for (final video in filteredVideos) {
          if (video.seriesId != null) {
            if (!processedSeriesIds.contains(video.seriesId)) {
              processedSeriesIds.add(video.seriesId!);
              displayVideos.add(video);
            }
          } else {
            displayVideos.add(video);
          }
        }

        final bool isVayu = filterVideoType?.toLowerCase() == 'vayu';

        if (useListLayout && isVayu) {
          if (isSliver) {
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return const SizedBox(height: 12);

                    final videoIndex = index ~/ 2;
                    return _buildVideoItem(
                      context,
                      manager,
                      displayVideos,
                      displayVideos[videoIndex],
                      videoIndex,
                    );
                  },
                  childCount:
                      displayVideos.isEmpty ? 0 : displayVideos.length * 2 - 1,
                ),
              ),
            );
          }

          return RepaintBoundary(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: displayVideos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildVideoItem(
                context,
                manager,
                displayVideos,
                displayVideos[index],
                index,
              ),
            ),
          );
        }

        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isVayu ? 2 : 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: isVayu ? (16 / 9) : 0.5,
        );

        if (isSliver) {
          return SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: displayVideos.length,
            itemBuilder: (context, index) => _buildVideoItem(
                context, manager, displayVideos, displayVideos[index], index),
          );
        }

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Your Videos',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: gridDelegate,
                  itemCount: displayVideos.length,
                  itemBuilder: (context, index) => _buildVideoItem(context,
                      manager, displayVideos, displayVideos[index], index),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoItem(BuildContext context, ProfileStateManager manager,
      List<VideoModel> displayVideos, VideoModel video, int index) {
    final isSelected = manager.selectedVideoIds.contains(video.id);
    final bool isSeries = video.seriesId != null;
    final bool isProcessing = _isVideoProcessing(video);
    final canSelectVideo =
        manager.isSelecting && manager.isOwner && manager.userData != null;

    if (useListLayout && _normalizedVideoType(video) == 'vayu') {
      return _buildVayuListVideoItem(
        context,
        manager,
        displayVideos,
        video,
        isSelected: isSelected,
        isSeries: isSeries,
        isProcessing: isProcessing,
        canSelectVideo: canSelectVideo,
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        child: UnifiedVideoCard(
          video: video,
          cardType: _normalizedVideoType(video) == 'vayu' ? UnifiedVideoCardType.vayu : UnifiedVideoCardType.yug,
          onTap: () async {
            if (isProcessing && !manager.isSelecting) {
              VayuSnackBar.showInfo(context,
                  'Video is still processing. It will be playable shortly.',
                  duration: const Duration(seconds: 2));
              return;
            }

            if (isSeries && video.episodes != null && video.episodes!.isNotEmpty && !manager.isSelecting) {
              AppLogger.log('🎬 ProfileVideosWidget: Series detected: ${video.id}. Opening episode list.');
              _showEpisodeList(context, video);
              return;
            }

            if (!manager.isSelecting) {
              final sharedPool = SharedVideoControllerPool();
              sharedPool.pauseAllControllers();

              if (_normalizedVideoType(video) == 'vayu') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // No parentTabIndex: this profile can be a pushed route
                    // inside ANY tab. Hardcoding 4 bound the player to the
                    // Profile tab, so the coordinator saw it as living in a
                    // background tab and blocked every play.
                    builder: (context) => VayuLongFormPlayerScreen(
                      video: video,
                      relatedVideos: displayVideos,
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // See above: the tab is resolved from the live navigation
                    // state instead of being assumed to be the Profile tab.
                    builder: (context) => VideoScreen(
                      initialVideos: displayVideos,
                      initialVideoId: video.id,
                    ),
                  ),
                );
              }
            } else if (manager.isSelecting && canSelectVideo) {
              manager.toggleVideoSelection(video.id);
            }
          },
          onLongPress: () {
            if (manager.isOwner && manager.userData != null && !manager.isSelecting) {
              manager.enterSelectionMode();
              manager.toggleVideoSelection(video.id);
            }
          },
          isSelected: isSelected,
          isSelecting: manager.isSelecting,
          showSelectionCheckbox: manager.isSelecting && canSelectVideo,
          onSelect: () => stateManager.toggleVideoSelection(video.id),
          topTrailingWidget: (manager.isOwner && !manager.isSelecting && _normalizedVideoType(video) == 'vayu') 
            ? GestureDetector(
                onTap: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditVideoDetails(video: video),
                    ),
                  );
                  if (result != null) {
                    manager.refreshData();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ) 
            : null,
        ),
      ),
    );
  }

  Widget _buildVayuListVideoItem(
    BuildContext context,
    ProfileStateManager manager,
    List<VideoModel> displayVideos,
    VideoModel video, {
    required bool isSelected,
    required bool isSeries,
    required bool isProcessing,
    required bool canSelectVideo,
  }) {
    final title = video.videoName.trim().isEmpty ? 'Untitled Video' : video.videoName.trim();
    final hasDescription = video.description?.trim().isNotEmpty == true;
    final metaText = [
      '${FormatUtils.formatViews(video.views)} views',
      '${FormatUtils.formatViews(video.likes)} likes',
      FormatUtils.formatTimeAgo(video.uploadedAt),
      if (isSeries && video.episodes?.isNotEmpty == true)
        '${video.episodes!.length} episodes',
    ].join(' • ');

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleVideoTap(context, manager, displayVideos, video, isProcessing, isSeries, canSelectVideo),
          onLongPress: () => _handleVideoLongPress(manager, video),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.backgroundSecondary.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.65)
                    : AppColors.borderPrimary.withValues(alpha: 0.45),
                width: isSelected ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 138,
                        height: 78,
                        color: AppColors.backgroundPrimary,
                        child: video.thumbnailUrl.isNotEmpty
                            ? Image.network(
                                video.thumbnailUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.play_circle_outline_rounded,
                                  color: AppColors.textTertiary,
                                  size: 30,
                                ),
                              )
                            : const Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.textTertiary,
                                size: 30,
                              ),
                      ),
                    ),
                    if (video.duration.inSeconds > 0)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            FormatUtils.formatDuration(video.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (isProcessing)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                height: 1.22,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (manager.isOwner && !manager.isSelecting)
                            _buildInlineEditButton(context, manager, video),
                          if (manager.isSelecting && canSelectVideo)
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => manager.toggleVideoSelection(video.id),
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(color: AppColors.textTertiary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metaText,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasDescription) ...[
                        const SizedBox(height: 6),
                        Text(
                          video.description!.trim(),
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditButton(
    BuildContext context,
    ProfileStateManager manager,
    VideoModel video,
  ) {
    return IconButton(
      onPressed: () async {
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (context) => EditVideoDetails(video: video),
          ),
        );
        if (result != null) {
          manager.refreshData();
        }
      },
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      tooltip: 'Edit video',
    );
  }

  void _handleVideoTap(
    BuildContext context,
    ProfileStateManager manager,
    List<VideoModel> displayVideos,
    VideoModel video,
    bool isProcessing,
    bool isSeries,
    bool canSelectVideo,
  ) {
    if (isProcessing && !manager.isSelecting) {
      VayuSnackBar.showInfo(
        context,
        'Video is still processing. It will be playable shortly.',
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (isSeries &&
        video.episodes != null &&
        video.episodes!.isNotEmpty &&
        !manager.isSelecting) {
      AppLogger.log('🎬 ProfileVideosWidget: Series detected: ${video.id}. Opening episode list.');
      _showEpisodeList(context, video);
      return;
    }

    if (!manager.isSelecting) {
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();

      if (_normalizedVideoType(video) == 'vayu') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VayuLongFormPlayerScreen(
              video: video,
              relatedVideos: displayVideos,
            ),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoScreen(
              initialVideos: displayVideos,
              initialVideoId: video.id,
            ),
          ),
        );
      }
    } else if (manager.isSelecting && canSelectVideo) {
      manager.toggleVideoSelection(video.id);
    }
  }

  void _handleVideoLongPress(ProfileStateManager manager, VideoModel video) {
    if (manager.isOwner && manager.userData != null && !manager.isSelecting) {
      manager.enterSelectionMode();
      manager.toggleVideoSelection(video.id);
    }
  }

  void _showEpisodeList(BuildContext context, VideoModel video) {
    if (video.episodes == null || video.episodes!.isEmpty) return;
    final BuildContext parentContext = context;

    AppLogger.log('🎬 ProfileVideosWidget: Showing episode list for series: ${video.seriesId}');
    VayuBottomSheet.show(
      context: context,
      title: 'Episodes',
      child: EpisodeGridWidget(
        episodes: video.episodes!,
        currentVideoId: video.id,
        onEpisodeTap: (episodeData, index) {
          final String episodeId = (episodeData['_id'] ?? episodeData['id'])?.toString() ?? '';
          Navigator.pop(context);

          final parentType = _normalizedVideoType(video);
          final filteredVideos = stateManager.userVideos
              .where((item) => _normalizedVideoType(item) == parentType)
              .toList(growable: false);

          if (parentType == 'vayu') {
            final selectedEpisodeIndex = filteredVideos.indexWhere((item) => item.id == episodeId);
            final selectedEpisode = selectedEpisodeIndex >= 0 ? filteredVideos[selectedEpisodeIndex] : video;
            
            // No parentTabIndex, here or below: this profile can be a pushed
            // route inside ANY tab, so hardcoding 4 bound the player to the
            // Profile tab and the coordinator blocked every play. The player
            // resolves its real tab from the enclosing TabScope.
            Navigator.push(
              parentContext,
              MaterialPageRoute(
                builder: (context) => VayuLongFormPlayerScreen(
                  video: selectedEpisode,
                  relatedVideos: filteredVideos,
                ),
              ),
            );
          } else {
            Navigator.push(
              parentContext,
              MaterialPageRoute(
                builder: (context) => VideoScreen(
                  initialVideos: filteredVideos,
                  initialVideoId: episodeId,
                ),
              ),
            );
          }
        },
        onLongPressEpisode: (episodeData, index) {
          final String episodeId = (episodeData['_id'] ?? episodeData['id'])?.toString() ?? '';
          _showEpisodeActionSheet(context, episodeId, stateManager);
        },
      ),
    );
  }

  void _showEpisodeActionSheet(BuildContext context, String episodeId, ProfileStateManager stateManager) {
    VayuBottomSheet.show(
      context: context,
      title: 'Episode Options',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text('Delete Episode', style: TextStyle(color: AppColors.error)),
            onTap: () async {
              Navigator.pop(context); // Close action sheet
              if (context.mounted) {
                final confirm = await ProfileDialogsWidget.showDeleteConfirmationDialog(
                  context,
                  title: 'Delete Episode?',
                  message: 'Are you sure you want to delete this episode?',
                );

                if (confirm == true) {
                  final success = await stateManager.deleteSingleVideo(episodeId);
                  if (success && context.mounted) {
                    Navigator.pop(context); // Close the episode list bottom sheet too
                  }
                }
              }
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
