import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:provider/provider.dart' as provider;
import 'package:vayug/shared/utils/app_text.dart';
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

class ProfileVideosWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVideoLongPress;
  final VoidCallback? onVideoSelection;
  final bool showHeader;
  final bool isSliver;
  final String? filterVideoType;
  final VoidCallback? onReferFriends;

  const ProfileVideosWidget({
    super.key,
    required this.stateManager,
    this.onVideoTap,
    this.onVideoLongPress,
    this.onVideoSelection,
    this.showHeader = true,
    this.isSliver = false,
    this.filterVideoType,
    this.onReferFriends,
  });

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

  @override
  Widget build(BuildContext context) {
    if (stateManager.userVideos.isNotEmpty) {
      _preloadVideoThumbnails(context, stateManager.userVideos);
    }

    return provider.Consumer<ProfileStateManager>(
      builder: (context, manager, child) {
        if (manager.isVideosLoading) {
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
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we get everything ready.',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
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

        if (manager.userVideos.isEmpty || filteredVideos.isEmpty) {
          final emptyWidget = RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                children: [
                   // Icon and text section removed for minimalist empty state
                  if (onReferFriends != null && manager.isOwner) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onReferFriends,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.borderPrimary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const HugeIcon(
                              icon: HugeIcons.strokeRoundedShare01,
                              color: AppColors.textPrimary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppText.get('btn_refer_friends'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
          return isSliver
              ? SliverToBoxAdapter(child: emptyWidget)
              : emptyWidget;
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
                    builder: (context) => VayuLongFormPlayerScreen(
                      video: video,
                      relatedVideos: displayVideos,
                      parentTabIndex: 4, // Profile tab index (4)
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
                      parentTabIndex: 4, // Profile tab index (4)
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
            
            Navigator.push(
              parentContext,
              MaterialPageRoute(
                builder: (context) => VayuLongFormPlayerScreen(
                  video: selectedEpisode,
                  relatedVideos: filteredVideos,
                  parentTabIndex: 4, // Profile tab index (4)
                ),
              ),
            );
          } else {
            try {
              final mainController = provider.Provider.of<MainController>(parentContext, listen: false);
              Navigator.push(
                parentContext,
                MaterialPageRoute(
                  builder: (context) => VideoScreen(
                    initialVideos: filteredVideos,
                    initialVideoId: episodeId,
                    parentTabIndex: mainController.currentIndex,
                  ),
                ),
              );
            } catch (e) {
              Navigator.push(
                parentContext,
                MaterialPageRoute(
                  builder: (context) => VideoScreen(
                    initialVideos: filteredVideos,
                    initialVideoId: episodeId,
                    parentTabIndex: 4, // Profile tab index (4)
                  ),
                ),
              );
            }
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
