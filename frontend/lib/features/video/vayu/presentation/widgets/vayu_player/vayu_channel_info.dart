import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/follow_button_widget.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';

class VayuChannelInfo extends StatelessWidget {
  final VideoModel video;
  final bool isPortrait;

  const VayuChannelInfo({
    super.key,
    required this.video,
    this.isPortrait = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
      child: Row(
        children: [
          InteractiveScaleButton(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => ProfileScreen(userId: video.uploader.id),
              ),
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: video.uploader.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(video.uploader.profilePic)
                  : null,
              backgroundColor: AppColors.backgroundSecondary,
              child: video.uploader.profilePic.isEmpty
                  ? const Icon(Icons.person_rounded, color: Colors.white, size: 21)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.uploader.name,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimary
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                ),
                if (video.uploader.totalVideos != null)
                  Text(
                    '${video.uploader.totalVideos} videos',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondary
                          : Colors.black54,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          FollowButtonWidget(
            uploaderId: video.uploader.id,
            uploaderName: video.uploader.name,
            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
            followingBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
            textColor: AppColors.textSecondary,
            followingTextColor: AppColors.textSecondary,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
            followingBorder: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            borderRadius: 20,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ],
      ),
    );
  }
}
