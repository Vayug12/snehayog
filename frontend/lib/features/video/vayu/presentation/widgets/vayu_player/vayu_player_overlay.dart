import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';

class VayuPlayerOverlay extends StatelessWidget {
  final VideoPlayerController? controller;
  final ValueNotifier<bool> showControlsVN;
  final ValueNotifier<bool> isControlsLockedVN;
  final bool isPortrait;
  final bool isFullScreenManual;
  final VoidCallback onTogglePlay;
  final VoidCallback onMoreOptions;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const VayuPlayerOverlay({
    super.key,
    required this.controller,
    required this.showControlsVN,
    required this.isControlsLockedVN,
    required this.isPortrait,
    required this.isFullScreenManual,
    required this.onTogglePlay,
    required this.onMoreOptions,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();

    final viewPadding = MediaQuery.viewPaddingOf(context);
    // Landscape right offset matches the bottom action buttons (64) so the
    // top ⋮ and bottom controls form one aligned right rail.
    final double rightOffset = isPortrait ? (isFullScreenManual ? 24.0 : 14.0) : 64.0;
    final double topOffset = isPortrait ? 8.0 : viewPadding.top + 16.0;

    return ValueListenableBuilder<bool>(
      valueListenable: showControlsVN,
      builder: (context, showControls, _) {
        return AnimatedOpacity(
          opacity: showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !showControls,
            child: Stack(
              children: [
                // Top rail — single more-options control
                Positioned(
                  top: topOffset,
                  right: rightOffset,
                  child: _circleButton(
                    onTap: onMoreOptions,
                    size: isPortrait ? 36 : 40,
                    icon: Icons.more_vert_rounded,
                    iconSize: isPortrait ? 18 : 20,
                  ),
                ),

                // Center controls — symmetrical previous · play/pause · next.
                // One shared circle treatment; the primary control is simply
                // the largest, which is all the hierarchy this zone needs.
                ValueListenableBuilder<bool>(
                  valueListenable: isControlsLockedVN,
                  builder: (context, isLocked, _) {
                    if (isLocked) return const SizedBox.shrink();
                    final double primarySize = isPortrait ? 56 : 64;
                    return Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isPortrait) ...[
                            _circleButton(
                              onTap: onPrevious,
                              size: 44,
                              icon: Icons.skip_previous_rounded,
                              iconSize: 22,
                            ),
                            const SizedBox(width: 32),
                          ],
                          InteractiveScaleButton(
                            onTap: onTogglePlay,
                            child: Container(
                              width: primarySize,
                              height: primarySize,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSecondary.withValues(alpha: 0.58),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.borderPrimary.withValues(alpha: 0.42),
                                ),
                              ),
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: controller!,
                                builder: (context, value, _) {
                                  return Icon(
                                    value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: isPortrait ? 30 : 34,
                                  );
                                },
                              ),
                            ),
                          ),
                          if (!isPortrait) ...[
                            const SizedBox(width: 32),
                            _circleButton(
                              onTap: onNext,
                              size: 44,
                              icon: Icons.skip_next_rounded,
                              iconSize: 22,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _circleButton({
    required VoidCallback onTap,
    required double size,
    required IconData icon,
    required double iconSize,
  }) {
    return InteractiveScaleButton(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary.withValues(alpha: 0.58),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.borderPrimary.withValues(alpha: 0.42),
          ),
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}
