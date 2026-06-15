import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/utils/format_utils.dart';

enum UnifiedVideoCardType { vayu, yug }

class UnifiedVideoCard extends StatelessWidget {
  final VideoModel video;
  final UnifiedVideoCardType cardType;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  
  // Optional overlays for profile
  final bool isSelected;
  final bool isSelecting;
  final bool showSelectionCheckbox;
  final VoidCallback? onSelect;
  final Widget? topTrailingWidget;

  const UnifiedVideoCard({
    super.key,
    required this.video,
    required this.cardType,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isSelecting = false,
    this.showSelectionCheckbox = false,
    this.onSelect,
    this.topTrailingWidget,
  });

  bool get _isProcessing {
    final status = video.processingStatus.toLowerCase();
    return video.isOptimistic || status == 'queued' || status == 'pending' || status == 'processing';
  }

  Widget _buildCrossPostStatus() {
    if (video.crossPostStatus == null || video.crossPostStatus!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: video.crossPostStatus!.entries.map((entry) {
          final platform = entry.key;
          final status = entry.value.toLowerCase();
          
          IconData icon;
          Color iconColor;
          
          switch (platform) {
            case 'youtube': icon = Icons.play_circle_filled; break;
            case 'instagram': icon = Icons.camera_alt; break;
            case 'facebook': icon = Icons.facebook; break;
            case 'linkedin': icon = Icons.work; break;
            default: icon = Icons.share;
          }

          switch (status) {
            case 'completed': iconColor = Colors.green; break;
            case 'failed': iconColor = Colors.red; break;
            case 'processing': iconColor = Colors.orange; break;
            default: iconColor = Colors.white70;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Icon(icon, size: 12, color: iconColor),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    if (video.isSubscriberOnly) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB300).withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: Color(0xFFFFB300),
            size: 28,
          ),
        ),
      );
    }
    return const Center(
      child: Icon(Icons.lock_outline_rounded, color: Color(0xFF9CA3AF), size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: video.isSubscriberOnly
              ? Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.45), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: video.isSubscriberOnly
                  ? const Color(0xFFFFB300).withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: video.isSubscriberOnly ? 6 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail
              Hero(
                tag: 'video_player_${video.id}',
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: _isProcessing
                      ? AppColors.backgroundSecondary
                      : (video.isSubscriberOnly
                          ? AppColors.backgroundSecondary
                          : const Color(0xFFF3F4F6)),
                  child: video.thumbnailUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: video.thumbnailUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: (context, url, error) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),

              // Processing Overlay
              if (_isProcessing)
                Positioned.fill(
                  child: Container(
                    color: AppColors.backgroundPrimary.withValues(alpha: 0.72),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              value: video.processingProgress.clamp(0, 100) / 100.0,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                              backgroundColor: AppColors.borderPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Processing ${video.processingProgress.clamp(0, 100)}%',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Series Badge
              if (video.seriesId != null)
                Positioned(
                  top: 8,
                  right: topTrailingWidget != null ? 36 : 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.layers, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'SERIES',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (!_isProcessing && video.crossPostStatus != null && !video.isSubscriberOnly)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _buildCrossPostStatus(),
                ),

              // Premium Exclusive Subscriber-Only Badge
              if (video.isSubscriberOnly)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFD54F), // Amber-Gold
                          Color(0xFFFF8F00), // Deep Gold
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20), // Pill shape
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, color: Colors.white, size: 10),
                        SizedBox(width: 3),
                        Text(
                          'EXCLUSIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Top Trailing (Edit Button)
              if (topTrailingWidget != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: topTrailingWidget!,
                ),

              // Selection Overlay
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      border: Border.all(color: const Color(0xFFEF4444), width: 3),
                    ),
                    child: Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),

              // Views Overlay (bottom left)
              if (!_isProcessing)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_outlined, color: Colors.white, size: 12),
                        const SizedBox(width: 2),
                        Text(
                          FormatUtils.formatViews(video.views),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Duration Overlay (for Vayu)
              if (!_isProcessing && cardType == UnifiedVideoCardType.vayu && video.duration.inSeconds > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
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

              // Selection Checkbox
              if (showSelectionCheckbox)
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: onSelect,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEF4444) : Colors.white.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? const Color(0xFFEF4444) : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
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
