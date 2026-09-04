import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/format_utils.dart';

class VayuMetadataSection extends StatelessWidget {
  final VideoModel video;
  final bool isPortrait;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onVisitLink;
  final VoidCallback onMoreOptions;
  final VoidCallback onEpisodes;
  final VoidCallback onSuggestion;
  final Function(String) onShowError;

  const VayuMetadataSection({
    super.key,
    required this.video,
    this.isPortrait = true,
    required this.onShare,
    required this.onSave,
    required this.onVisitLink,
    required this.onMoreOptions,
    required this.onEpisodes,
    required this.onSuggestion,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            video.videoName,
            style: AppTypography.bodyLarge.copyWith(
              color: isDark ? AppColors.textPrimary : Colors.black87,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: AppSpacing.spacing1),
          Text(
            '${FormatUtils.formatViews(video.views)} views • ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: isPortrait ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (video.tags != null && video.tags!.isNotEmpty) ...[
            SizedBox(height: AppSpacing.spacing2),
            Wrap(
              spacing: AppSpacing.spacing1,
              runSpacing: AppSpacing.spacing1,
              children: video.tags!
                  .map((tag) => Text(
                        '#$tag',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ))
                  .toList(),
            ),
          ],
          SizedBox(height: AppSpacing.spacing3),
          // ── ACTION BAR (Horizontally scrollable with Icons + Text) ──────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  context,
                  icon: Icon(
                    video.isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: video.isSaved
                        ? AppColors.primary
                        : (isDark ? Colors.white70 : Colors.black87),
                    size: 18,
                  ),
                  onPressed: onSave,
                  label: video.isSaved ? 'Saved' : 'Save',
                  labelColor: video.isSaved ? AppColors.primary : null,
                ),
                SizedBox(width: AppSpacing.spacing2),
                _buildActionButton(
                  context,
                  icon: Icon(
                    Icons.share_outlined,
                    color: isDark ? Colors.white70 : Colors.black87,
                    size: 18,
                  ),
                  onPressed: onShare,
                  label: 'Share',
                ),
                if (video.episodes != null && video.episodes!.isNotEmpty) ...[
                  SizedBox(width: AppSpacing.spacing2),
                  _buildActionButton(
                    context,
                    icon: Icon(
                      Icons.playlist_play_rounded,
                      color: isDark ? Colors.white70 : Colors.black87,
                      size: 18,
                    ),
                    onPressed: onEpisodes,
                    label: 'Episodes',
                  ),
                ],
                SizedBox(width: AppSpacing.spacing2),
                _buildActionButton(
                  context,
                  icon: Icon(
                    Icons.tips_and_updates_outlined,
                    color: isDark ? Colors.white70 : Colors.black87,
                    size: 18,
                  ),
                  onPressed: onSuggestion,
                  label: 'Suggest',
                ),
                if (video.link?.isNotEmpty == true) ...[
                  SizedBox(width: AppSpacing.spacing2),
                  _buildActionButton(
                    context,
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      color: isDark ? Colors.white70 : Colors.black87,
                      size: 18,
                    ),
                    onPressed: onVisitLink,
                    label: 'Visit',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required Widget icon,
    required VoidCallback onPressed,
    required String label,
    Color? labelColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.spacing3,
                vertical: AppSpacing.spacing2,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  SizedBox(width: AppSpacing.spacing1 + 2),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      color: labelColor ??
                          (isDark ? Colors.white70 : Colors.black87),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
