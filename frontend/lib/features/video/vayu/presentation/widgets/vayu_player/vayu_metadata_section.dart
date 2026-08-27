import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:shimmer/shimmer.dart';

class VayuMetadataSection extends StatefulWidget {
  final VideoModel video;
  final bool isPortrait;
  final bool isLoading;
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
    this.isLoading = false,
    required this.onShare,
    required this.onSave,
    required this.onVisitLink,
    required this.onMoreOptions,
    required this.onEpisodes,
    required this.onSuggestion,
    required this.onShowError,
  });

  @override
  State<VayuMetadataSection> createState() => _VayuMetadataSectionState();
}

class _VayuMetadataSectionState extends State<VayuMetadataSection>
    with SingleTickerProviderStateMixin {
  int? _expandedIndex;
  late final AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    if (!widget.isLoading) {
      _fadeController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant VayuMetadataSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _expandedIndex = null;
    }
    if (oldWidget.isLoading && !widget.isLoading) {
      _fadeController.forward(from: 0.0);
    } else if (!oldWidget.isLoading && widget.isLoading) {
      _fadeController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && _fadeController.isCompleted) {
      _fadeController.value = 0.0;
    }
    if (widget.isLoading) {
      return _buildShimmer(context);
    }
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: child,
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(
            widget.video.videoName,
            style: AppTypography.bodyLarge.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textPrimary
                  : Colors.black87,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: AppSpacing.spacing1),
          Text(
            '${FormatUtils.formatViews(widget.video.views)} views • ${FormatUtils.formatTimeAgo(widget.video.uploadedAt)}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            fontSize: widget.isPortrait ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (widget.video.tags != null && widget.video.tags!.isNotEmpty) ...[
            SizedBox(height: AppSpacing.spacing2),
            Wrap(
              spacing: AppSpacing.spacing1,
              runSpacing: AppSpacing.spacing1,
              children: widget.video.tags!
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
          // ── ACTION BAR (Expanding Active Tab) ──────────
          GestureDetector(
            onTap: () => setState(() => _expandedIndex = null),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    context,
                    index: 0,
                    icon: Icon(
                      widget.video.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                      color: widget.video.isSaved ? AppColors.primary : Colors.white70,
                      size: 18,
                    ),
                    onPressed: widget.onSave,
                    label: widget.video.isSaved ? 'Saved' : 'Save',
                  ),
                  SizedBox(width: AppSpacing.spacing2),
                  _buildActionButton(
                    context,
                    index: 1,
                    icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 18),
                    onPressed: widget.onShare,
                    label: 'Share',
                  ),
                  if (widget.video.episodes != null && widget.video.episodes!.isNotEmpty) ...[
                    SizedBox(width: AppSpacing.spacing2),
                    _buildActionButton(
                      context,
                      index: 2,
                      icon: const Icon(Icons.playlist_play_rounded, color: Colors.white70, size: 18),
                      onPressed: widget.onEpisodes,
                      label: 'Episodes',
                    ),
                  ],
                  SizedBox(width: AppSpacing.spacing2),
                  _buildActionButton(
                    context,
                    index: 3,
                    icon: const Icon(Icons.tips_and_updates_outlined, color: Colors.white70, size: 18),
                    onPressed: widget.onSuggestion,
                    label: 'Suggest',
                  ),
                  if (widget.video.link?.isNotEmpty == true) ...[
                    SizedBox(width: AppSpacing.spacing2),
                    _buildActionButton(
                      context,
                      index: 4,
                      icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
                      onPressed: widget.onVisitLink,
                      label: 'Visit',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white12 : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.white24 : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 200, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            SizedBox(height: AppSpacing.spacing2),
            Row(children: [
              Container(width: 60, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
              SizedBox(width: AppSpacing.spacing2),
              Container(width: 80, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            ]),
            const SizedBox(height: 16),
            Row(
              children: List.generate(4, (index) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(width: 80, height: 32, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required int index,
    required Widget icon,
    required VoidCallback onPressed,
    required String label,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpanded = _expandedIndex == index;
    return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _expandedIndex = isExpanded ? null : index;
                });
                onPressed();
              },
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(
                  horizontal: isExpanded ? AppSpacing.spacing3 : AppSpacing.spacing2,
                  vertical: AppSpacing.spacing2,
                ),
                decoration: BoxDecoration(
                  color: isExpanded
                      ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08))
                      : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isExpanded
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: isExpanded
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: AppSpacing.spacing1),
                                Text(
                                  label,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
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
