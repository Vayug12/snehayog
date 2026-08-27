import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/constants/app_constants.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/shared/widgets/follow_button_widget.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/profile/core/data/services/profile_preloader.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/url_utils.dart';

class VideoInfoWidget extends StatefulWidget {
  final VideoModel video;

  const VideoInfoWidget({
    Key? key,
    required this.video,
  }) : super(key: key);

  @override
  State<VideoInfoWidget> createState() => _VideoInfoWidgetState();
}

class _VideoInfoWidgetState extends State<VideoInfoWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Check if title is long enough to need truncation (reduced threshold for better UX)
    final isLongTitle = widget.video.videoName.length > 20;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video title with "view more" functionality
          GestureDetector(
            onTap: isLongTitle
                ? () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  }
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.videoName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textInverse,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: _isExpanded ? null : 1,
                  overflow: _isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
                // Show "view more" / "view less" text if title is long
                if (isLongTitle)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _isExpanded ? 'view less' : 'view more',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textInverse.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor:
                                AppColors.textInverse.withValues(alpha: 0.9),
                          ),
                    ),
                  ),
              ],
            ),
          ),
          // **REDUCED spacing from 4 to 2**
          const SizedBox(height: 2),

          // **REDUCED spacing from 8 to 4**
          const SizedBox(height: 2),

          // Uploader information (tappable to go to profile)
          _UploaderInfoSection(video: widget.video),

          // Visit Now button below uploader info (if video has a link)
          // **DEBUG: Add logging to check link status**
          Builder(
            builder: (context) {
              if (widget.video.link != null && widget.video.link!.isNotEmpty) {
                return Column(
                  children: [
                    const SizedBox(height: 2),
                    _VisitNowButton(link: widget.video.link!),
                  ],
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
    );
  }
}

// Lightweight uploader info section widget
class _UploaderInfoSection extends StatelessWidget {
  final VideoModel video;

  const _UploaderInfoSection({required this.video});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Uploader avatar and name (tappable)
        Expanded(
          child: GestureDetector(
            onTap: () async {
              // **NEW: Pause video before navigation**
              try {
                final sharedPool = SharedVideoControllerPool();
                sharedPool.pauseAllControllers();

                // Also pause VideoControllerManager videos if available
                try {
                  final videoControllerManager = VideoControllerManager();
                  videoControllerManager.pauseAllVideos();
                } catch (e) {
                  // VideoControllerManager might not be available, ignore
                }
              } catch (e) {
                // Ignore errors - video pause is best effort
              }

              // **NEW: Preload profile before navigation for instant opening**
              if (video.uploader.id.isNotEmpty &&
                  video.uploader.id != 'unknown') {
                final profilePreloader = ProfilePreloader();
                await profilePreloader.preloadProfileOnTap(video.uploader.id);
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ProfileScreen(userId: video.uploader.id),
                ),
              );
            },
            child: Row(
              children: [
                _UploaderAvatar(uploader: video.uploader),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    video.uploader.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textInverse,
                          fontWeight: FontWeight.w500,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Follow button
        const SizedBox(width: 4),
        FollowButtonWidget(
          uploaderId: (video.uploader.googleId?.trim().isNotEmpty == true)
              ? video.uploader.googleId!.trim()
              : video.uploader.id,
          uploaderName: video.uploader.name,
          onFollowChanged: () {
            // Optionally refresh video data or update UI
            AppLogger.log('Follow status changed for ${video.uploader.name}');
          },
        ),
      ],
    );
  }
}

// Lightweight uploader avatar widget
class _UploaderAvatar extends StatelessWidget {
  final Uploader uploader;

  const _UploaderAvatar({required this.uploader});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: AppConstants.avatarRadius,
      backgroundColor: Colors.grey,
      child: uploader.profilePic.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: uploader.profilePic,
                width: AppConstants.avatarRadius * 2,
                height: AppConstants.avatarRadius * 2,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                maxWidthDiskCache: 96,
                errorWidget: (context, url, error) {
                  print('🖼️ _UploaderAvatar: Image.network error: $error');
                  return _buildInitialsAvatar(context);
                },
                placeholder: (context, url) {
                  return const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  );
                },
              ),
            )
          : _buildInitialsAvatar(context),
    );
  }

  Widget _buildInitialsAvatar(BuildContext context) {
    // Get initials from the user's name
    final initials = uploader.name.isNotEmpty
        ? uploader.name
            .split(' ')
            .map((n) => n.isNotEmpty ? n[0] : '')
            .take(2)
            .join('')
            .toUpperCase()
        : '?';

    return Container(
      width: AppConstants.avatarRadius * 2,
      height: AppConstants.avatarRadius * 2,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textInverse,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}

// Visit Now button widget
class _VisitNowButton extends StatelessWidget {
  final String link;

  const _VisitNowButton({required this.link});

  @override
  Widget build(BuildContext context) {
    return Container(
      // **UPDATED: Increased width significantly while keeping height same**
      width: MediaQuery.of(context).size.width * 0.75, // 60% of screen width
      margin: const EdgeInsets.only(right: 8),
      child: AppButton(
        onPressed: () async {
          final enrichedUrl = UrlUtils.enrichUrl(
            link,
            medium: 'video_link',
            campaign: 'creator_visit',
          );
          final Uri uri = Uri.parse(enrichedUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (context.mounted) {
            VayuSnackBar.showError(context, 'Could not open link: $link');
          }
        },
        icon: const Icon(Icons.open_in_new, size: 14),
        label: 'Visit Now',
        variant: AppButtonVariant.primary,
        isFullWidth: true,
      ),
    );
  }
}
