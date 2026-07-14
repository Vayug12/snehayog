import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:video_player/video_player.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:visibility_detector/visibility_detector.dart';

class OnboardingVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool loop;
  final Function(double)? onProgress;
  final double? maxHeight;

  const OnboardingVideoPlayer({
    Key? key,
    required this.videoUrl,
    this.autoPlay = true,
    this.loop = true,
    this.onProgress,
    this.maxHeight,
  }) : super(key: key);

  @override
  State<OnboardingVideoPlayer> createState() => _OnboardingVideoPlayerState();
}

class _OnboardingVideoPlayerState extends State<OnboardingVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  double get _placeholderHeight => math.min(widget.maxHeight ?? 200, 200);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        if (widget.autoPlay) {
          _controller.play();
        }
        _controller.setLooping(widget.loop);
        
        _controller.addListener(() {
          if (_controller.value.isInitialized && _controller.value.duration.inMilliseconds > 0) {
            final progress = _controller.value.position.inMilliseconds / 
                             _controller.value.duration.inMilliseconds;
            widget.onProgress?.call(progress);
          }
        });
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: _placeholderHeight,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 48),
              SizedBox(height: 16),
              Text(
                'Video load nahi ho payi',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        height: _placeholderHeight,
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const hintHeight = 28.0;
        final availableHeight = widget.maxHeight;
        final showHint = availableHeight == null || availableHeight >= hintHeight;
        final maxVideoHeight = availableHeight == null
            ? double.infinity
            : math.max(0.0, availableHeight - (showHint ? hintHeight : 0));
        final reportedAspectRatio = _controller.value.aspectRatio;
        final aspectRatio = reportedAspectRatio.isFinite && reportedAspectRatio > 0
            ? reportedAspectRatio
            : 16 / 9;
        final videoWidth = math.min(
          constraints.maxWidth,
          maxVideoHeight.isFinite
              ? maxVideoHeight * aspectRatio
              : constraints.maxWidth,
        );
        final videoHeight = videoWidth / aspectRatio;

        return VisibilityDetector(
          key: Key(widget.videoUrl),
          onVisibilityChanged: (info) {
            if (info.visibleFraction == 0) {
              _controller.pause();
            } else if (info.visibleFraction > 0.5 && widget.autoPlay) {
              _controller.play();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      GestureDetector(
                        onTap: _togglePlay,
                        child: AnimatedOpacity(
                          opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: AppColors.primary,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showHint) ...[
                const SizedBox(height: 12),
                Text(
                  _controller.value.isPlaying ? 'Tap to pause' : 'Tap to play',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
