import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/presentation/widgets/quiz_overlay.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_video_progress_bar.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum GestureType { none, horizontal, vertical, scale }

class VayuFeedItem extends ConsumerStatefulWidget {
  final int index;
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool hasControllerLoadError;
  final bool isCurrent;
  final bool isFullScreenManual;
  final ValueNotifier<bool> showControlsVN;
  final ValueNotifier<bool> isControlsLockedVN;
  final ValueNotifier<bool> showScrubbingOverlayVN;
  final ValueNotifier<bool>? isSeekingBufferingVN;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onOpenExternalPlayer;
  final GlobalKey? pictureInPictureSourceKey;
  final VoidCallback onHandleTap;
  final void Function(TapDownDetails) onDoubleTapToSeek;
  final VoidCallback onHorizontalDragEnd;
  final void Function(double, Offset) onVerticalDragUpdate;
  final VoidCallback onVerticalDragEnd;
  final void Function(double) onUnifiedHorizontalDrag;
  final void Function(String) onShowSnackBar;
  final Widget Function(int) buildAdSection;
  final Widget Function(int) buildVideoInfo; // Legacy support or direct call
  final Widget Function(int) buildChannelRow; // Legacy support or direct call
  final Widget Function() buildScrubbingOverlay;
  final Widget Function(int)
      buildCustomControls; // Legacy support or direct call
  final Widget Function(int)
      buildDubbingProgress; // Legacy support or direct call
  final String Function(Duration) formatDuration;
  final QuizModel? activeQuiz;
  final VoidCallback onQuizDismiss;
  final VoidCallback? onQuizBack;
  final Future<void> Function() onResumeAfterSeek;

  // New component-based callbacks/widgets passed from parent
  final Widget metadataSection;
  final Widget channelInfo;
  final Widget playerOverlay;
  final Widget dubbingOverlay;

  const VayuFeedItem({
    super.key,
    required this.index,
    required this.video,
    this.controller,
    this.hasControllerLoadError = false,
    required this.isCurrent,
    required this.isFullScreenManual,
    required this.showControlsVN,
    required this.isControlsLockedVN,
    required this.showScrubbingOverlayVN,
    this.isSeekingBufferingVN,
    required this.onToggleFullScreen,
    this.pictureInPictureSourceKey,
    required this.onHandleTap,
    required this.onDoubleTapToSeek,
    required this.onHorizontalDragEnd,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onUnifiedHorizontalDrag,
    required this.onShowSnackBar,
    required this.buildAdSection,
    required this.buildVideoInfo,
    required this.buildChannelRow,
    required this.buildScrubbingOverlay,
    required this.buildCustomControls,
    required this.buildDubbingProgress,
    required this.formatDuration,
    required this.onOpenExternalPlayer,
    this.activeQuiz,
    this.onQuizBack,
    required this.onQuizDismiss,
    required this.onResumeAfterSeek,
    required this.metadataSection,
    required this.channelInfo,
    required this.playerOverlay,
    required this.dubbingOverlay,
  });

  @override
  ConsumerState<VayuFeedItem> createState() => _VayuFeedItemState();
}

// Deliberately NOT an AutomaticKeepAliveClient. A kept-alive page stays in the
// element tree forever, and SliverMultiBoxAdaptorElement rebuilds keep-alive
// children too — so every page the user had ever visited was rebuilt on every
// swipe, which is why scrolling got progressively slower the longer the session
// ran. The feed screen itself is kept alive for tab switches; individual pages
// are cheap to rebuild from the video model and the pooled controller.
class _VayuFeedItemState extends ConsumerState<VayuFeedItem> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  int _pointers = 0;
  bool _isScaling = false;

  // Gesture tracking
  GestureType _activeGesture = GestureType.none;
  double _dragHorizontalDeltaAccumulated = 0;
  double _dragVerticalDeltaAccumulated = 0;
  static const double _gestureThreshold = 12.0;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final isFull =
        orientation == Orientation.landscape || widget.isFullScreenManual;
    final lateralPadding = orientation == Orientation.landscape ? 60.0 : 14.0;

    // We use a Stack as the root to maintain widget tree stability across orientation changes
    return Stack(
      children: [
        // ── LAYER 1: Ambient blurred thumbnail (Portrait & Landscape) ──────────
        // A tiny decode stretched full-screen looks like a gaussian blur but
        // costs almost nothing to paint — a live ImageFiltered blur here
        // repaints on every frame of a rotation and drops frames.
        if (widget.video.thumbnailUrl.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: CachedNetworkImage(
                imageUrl: widget.video.thumbnailUrl,
                fit: BoxFit.cover,
                memCacheWidth: 24,
                filterQuality: FilterQuality.low,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Colors.transparent),
              ),
            ),
          )
        else
          const Positioned.fill(child: ColoredBox(color: Colors.transparent)),

        // ── LAYER 2: Dark / Gradient overlay — keeps foreground content readable ──────────
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: isFull
                  ? const LinearGradient(
                      colors: [
                        Color.fromRGBO(0, 0, 0, 0.4),
                        Color.fromRGBO(0, 0, 0, 0.6)
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    )
                  : LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.8),
                        Colors.black,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 0.7],
                    ),
            ),
          ),
        ),

        // Stable Video + Metadata Column
        Column(
          children: [
            _buildVideoSection(orientation),
            if (!isFull)
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        widget.buildAdSection(widget.index),
                        widget.metadataSection,
                        widget.channelInfo,
                        if (widget.activeQuiz != null)
                          Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.spacing3),
                            child: QuizOverlay(
                              quiz: widget.activeQuiz!,
                              onDismiss: widget.onQuizDismiss,
                              onBack: (widget.onQuizBack != null)
                                  ? widget.onQuizBack
                                  : null,
                              onAnswered: (idx) {},
                            ),
                          ),
                        widget.dubbingOverlay,
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Overlays that appear in BOTH modes (landscape specific positions)
        if (isFull) ...[
          if (widget.activeQuiz != null)
            Positioned(
              bottom: 80,
              left: lateralPadding,
              right: lateralPadding,
              child: QuizOverlay(
                quiz: widget.activeQuiz!,
                onDismiss: widget.onQuizDismiss,
                onBack: widget.onQuizBack,
                onAnswered: (idx) {},
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: widget.dubbingOverlay,
          ),
        ],
      ],
    );
  }

  // Shared circular treatment for the bottom action buttons so they match
  // the overlay's compact control rail.
  Widget _bottomCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPortrait,
  }) {
    final double size = isPortrait ? 36 : 40;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        constraints: const BoxConstraints(),
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: isPortrait ? 18 : 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.46),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _buildVideoSection(Orientation orientation) {
    final size = MediaQuery.sizeOf(context);
    final controller = widget.controller;

    bool controllerIsHealthy = false;
    bool isPlaying = false;
    bool hasVideoError = widget.hasControllerLoadError;
    try {
      if (controller != null) {
        controllerIsHealthy = controller.value.isInitialized;
        isPlaying = controller.value.isPlaying;
        hasVideoError = hasVideoError || controller.value.hasError;
      }
    } catch (_) {
      controllerIsHealthy = false;
    }

    final isFull =
        orientation == Orientation.landscape || widget.isFullScreenManual;
    final isPortrait = orientation == Orientation.portrait;
    // Asymmetric offsets for landscape to clear system navigation buttons while staying compact on the left
    final leftPadding = orientation == Orientation.landscape ? 24.0 : 14.0;
    final rightPadding = orientation == Orientation.landscape ? 64.0 : 14.0;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Background handled at the root build level.
          // Layer 3: Actual video container + all overlays
          SizedBox(
            key: widget.pictureInPictureSourceKey,
            width: size.width,
            height: isFull ? size.height : size.width * (9 / 16),
            child: Stack(
              children: [
                // 1. THUMBNAIL PLACEHOLDER (Visible until video starts)
                // Wrapped in AspectRatio to prevent it from covering the blurred background on the sides in full-screen
                Positioned.fill(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: widget.video.thumbnailUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),

                // 1b. LOADING SHIMMER / ERROR STATE over the poster while the
                // video is not ready. Uses the same shimmer treatment as
                // VayuMetadataSection so loading looks consistent app-wide.
                // Guarded by isCurrent so kept-alive neighbour pages don't
                // run offscreen shimmer animations.
                if (widget.isCurrent && !controllerIsHealthy)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: hasVideoError
                              ? Container(
                                  color: Colors.black54,
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error_outline_rounded,
                                          color: Colors.white70, size: 32),
                                      SizedBox(height: 8),
                                      Text(
                                        "Couldn't load video. Tap to retry.",
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : Shimmer.fromColors(
                                  baseColor: Colors.white12,
                                  highlightColor: Colors.white24,
                                  child: Container(color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                  ),

                // 2. VIDEO LAYER
                // Rendered directly rather than through Chewie: this player
                // draws its own controls, poster and progress bar, so Chewie
                // was an extra widget layer plus its own per-tick listeners
                // around a plain VideoPlayer.
                if (controllerIsHealthy)
                  Positioned.fill(
                    child: Center(
                      child: ClipRect(
                        child: Transform.translate(
                          offset: _offset,
                          child: Transform.scale(
                            scale: _scale,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: VideoPlayer(
                                controller!,
                                key: ValueKey(controller),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Single overlay provides contrast while controls are visible.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                      valueListenable: widget.showControlsVN,
                      builder: (context, showControls, _) {
                        return IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: showControls ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        );
                      }),
                ),

                // 2. GESTURE LAYER
                Positioned.fill(
                  child: Listener(
                    onPointerDown: (event) => _pointers++,
                    onPointerUp: (event) {
                      _pointers--;
                      if (_pointers <= 0) {
                        _pointers = 0;
                        if (_isScaling) {
                          setState(() {
                            _isScaling = false;
                            _scale = 1.0;
                            _offset = Offset.zero;
                          });
                        }
                        if (_activeGesture == GestureType.horizontal) {
                          widget.onHorizontalDragEnd();
                        }
                        if (_activeGesture == GestureType.vertical) {
                          widget.onVerticalDragEnd();
                        }
                        _activeGesture = GestureType.none;
                        _dragHorizontalDeltaAccumulated = 0;
                        _dragVerticalDeltaAccumulated = 0;
                      }
                    },
                    onPointerCancel: (event) {
                      _pointers = 0;
                      if (_isScaling) {
                        setState(() {
                          _isScaling = false;
                          _scale = 1.0;
                          _offset = Offset.zero;
                        });
                      }
                      if (_activeGesture == GestureType.horizontal) {
                        widget.onHorizontalDragEnd();
                      }
                      if (_activeGesture == GestureType.vertical) {
                        widget.onVerticalDragEnd();
                      }
                      _activeGesture = GestureType.none;
                      _dragHorizontalDeltaAccumulated = 0;
                      _dragVerticalDeltaAccumulated = 0;
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onHandleTap,
                      onDoubleTapDown: widget.onDoubleTapToSeek,
                      onVerticalDragStart: (_) {
                        _activeGesture = GestureType.vertical;
                      },
                      onVerticalDragUpdate: (details) {
                        widget.onVerticalDragUpdate(
                            details.delta.dy, details.localPosition);
                      },
                      onVerticalDragEnd: (_) {
                        _activeGesture = GestureType.none;
                        widget.onVerticalDragEnd();
                      },
                      onScaleStart: (details) {
                        if (_pointers >= 2) {
                          _isScaling = true;
                          _baseScale = _scale;
                        }
                      },
                      onScaleUpdate: (details) {
                        if (_isScaling) {
                          setState(() {
                            _scale =
                                (_baseScale * details.scale).clamp(1.0, 4.0);
                          });
                          return;
                        }

                        if (_activeGesture == GestureType.none) {
                          _dragHorizontalDeltaAccumulated +=
                              details.focalPointDelta.dx;
                          // Vertical is handled by onVerticalDragUpdate now
                          if (_dragHorizontalDeltaAccumulated.abs() >
                              _gestureThreshold) {
                            _activeGesture = GestureType.horizontal;
                          }
                        }

                        if (_activeGesture == GestureType.horizontal) {
                          widget.onUnifiedHorizontalDrag(
                              details.focalPointDelta.dx);
                        }
                      },
                      onScaleEnd: (details) {
                        if (_activeGesture == GestureType.horizontal) {
                          widget.onHorizontalDragEnd();
                        }
                        _activeGesture = GestureType.none;
                        _dragHorizontalDeltaAccumulated = 0;
                        _dragVerticalDeltaAccumulated = 0;
                      },
                    ),
                  ),
                ),

                // 3. OVERLAYS (Controls, Scrubbing)
                if (widget.isCurrent) ...[
                  widget.playerOverlay,
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.showScrubbingOverlayVN,
                    builder: (context, showScrubbing, _) {
                      if (!showScrubbing) return const SizedBox.shrink();
                      return widget.buildScrubbingOverlay();
                    },
                  ),
                  if (widget.isSeekingBufferingVN != null)
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.isSeekingBufferingVN!,
                      builder: (context, isSeeking, _) {
                        return AnimatedOpacity(
                          opacity: isSeeking ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: isSeeking
                              ? const IgnorePointer(
                                  child: Center(
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0x66000000),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(11),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
                ],

                // 4. SECONDARY CONTROLS & PROGRESS BAR
                if (controllerIsHealthy && widget.isCurrent)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Duration and Action Buttons Row
                        ValueListenableBuilder<bool>(
                            valueListenable: widget.showControlsVN,
                            builder: (context, showControls, _) {
                              return AnimatedOpacity(
                                opacity: showControls ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: IgnorePointer(
                                  ignoring: !showControls,
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        leftPadding, 0, rightPadding, 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Duration Text (Instant Frost + Tabular Figures)
                                        if (controller != null)
                                          ValueListenableBuilder<
                                                  VideoPlayerValue>(
                                              valueListenable: controller,
                                              builder: (context, value, _) {
                                                return Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black45,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20),
                                                  ),
                                                  child: Text(
                                                    '${widget.formatDuration(value.position)} / ${widget.formatDuration(value.duration)}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontFeatures: [
                                                        FontFeature
                                                            .tabularFigures()
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),

                                        // Action Buttons (Play/External & Fullscreen)
                                        ValueListenableBuilder<bool>(
                                            valueListenable:
                                                widget.isControlsLockedVN,
                                            builder: (context, isLocked, _) {
                                              if (isLocked) {
                                                return const SizedBox.shrink();
                                              }
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _bottomCircleButton(
                                                    icon: Icons
                                                        .play_circle_outline_rounded,
                                                    onPressed: widget
                                                        .onOpenExternalPlayer,
                                                    isPortrait: isPortrait,
                                                  ),
                                                  AppSpacing.hSpace12,
                                                  _bottomCircleButton(
                                                    icon: isPortrait
                                                        ? Icons
                                                            .fullscreen_rounded
                                                        : Icons
                                                            .fullscreen_exit_rounded,
                                                    onPressed: widget
                                                        .onToggleFullScreen,
                                                    isPortrait: isPortrait,
                                                  ),
                                                ],
                                              );
                                            }),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                        // Progress Bar (Auto-hide in landscape)
                        ValueListenableBuilder<bool>(
                            valueListenable: widget.showControlsVN,
                            builder: (context, showControls, _) {
                              return AnimatedOpacity(
                                opacity:
                                    isFull ? (showControls ? 1.0 : 0.0) : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: IgnorePointer(
                                  ignoring: isFull && !showControls,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: isFull ? leftPadding : 0,
                                      right: isFull ? rightPadding : 0,
                                    ),
                                    child: VayuVideoProgressBar(
                                      controller: controller!,
                                      height: isFull ? 20 : 12,
                                      barHeight: isFull ? 4 : 2,
                                      activeBarHeight: isFull ? 10 : 4,
                                      thumbRadius: isFull ? 8 : 0,
                                      barCenterOffset: isFull ? null : 10,
                                      onResumeAfterSeek:
                                          widget.onResumeAfterSeek,
                                      onSeekStarted:
                                          widget.isSeekingBufferingVN != null
                                              ? () => widget
                                                  .isSeekingBufferingVN!
                                                  .value = true
                                              : null,
                                    ),
                                  ),
                                ),
                              );
                            }),
                        // Fixed 32px clearance in landscape for stable placement
                        if (isFull) const SizedBox(height: 32),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
