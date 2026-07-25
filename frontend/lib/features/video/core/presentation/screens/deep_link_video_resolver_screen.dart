import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/shared/services/deep_link_playback_gate.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// Resolves a shared video before choosing a player.
///
/// A Vayu video must never fall back to the Yug player if metadata is slow or
/// unavailable, so this screen stays in a recoverable loading/error state
/// until the content type is known.
class DeepLinkVideoResolverScreen extends StatefulWidget {
  final String videoId;
  final Duration? initialPosition;
  final Duration? sectionEnd;
  final int requestId;

  const DeepLinkVideoResolverScreen({
    super.key,
    required this.videoId,
    required this.requestId,
    this.initialPosition,
    this.sectionEnd,
  });

  @override
  State<DeepLinkVideoResolverScreen> createState() =>
      _DeepLinkVideoResolverScreenState();
}

class _DeepLinkVideoResolverScreenState
    extends State<DeepLinkVideoResolverScreen> {
  bool _isLoading = true;
  bool _isOpeningTarget = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolveVideo();
  }

  @override
  void dispose() {
    if (!_isOpeningTarget) {
      DeepLinkPlaybackGate.release(widget.requestId);
    }
    super.dispose();
  }

  Future<void> _resolveVideo() async {
    if (!DeepLinkPlaybackGate.isCurrent(widget.requestId)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final video = await _fetchVideoWithRetry();
      if (!mounted || !DeepLinkPlaybackGate.isCurrent(widget.requestId)) {
        return;
      }
      await _openTypedPlayer(video);
    } catch (error) {
      if (!mounted || !DeepLinkPlaybackGate.isCurrent(widget.requestId)) {
        return;
      }
      AppLogger.log(
        'DeepLinkResolver: Could not resolve ${widget.videoId}: $error',
      );
      setState(() {
        _isLoading = false;
        _errorMessage =
            'We could not load this shared video. Check your connection and try again.';
      });
    }
  }

  Future<VideoModel> _fetchVideoWithRetry() async {
    Object? lastError;
    final videoService = VideoService();

    // VideoService already uses a 15-second network timeout. Retrying here
    // supports slow connections without ever guessing the player type.
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (!DeepLinkPlaybackGate.isCurrent(widget.requestId)) {
        throw StateError('A newer shared link is being resolved');
      }
      try {
        return await videoService.getVideoById(widget.videoId);
      } catch (error) {
        lastError = error;
        AppLogger.log(
          'DeepLinkResolver: Metadata attempt $attempt failed for ${widget.videoId}: $error',
        );
      }
    }

    throw lastError ?? StateError('Video metadata was unavailable');
  }

  Future<void> _openTypedPlayer(VideoModel video) async {
    if (video.videoType != 'vayu' && video.videoType != 'yog') {
      throw StateError('Unsupported video type: ${video.videoType}');
    }

    _isOpeningTarget = true;
    DeepLinkPlaybackGate.pauseAllPlayback();

    final Route<void> targetRoute;
    if (video.videoType == 'vayu') {
      targetRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/vayu_video'),
        builder: (_) => VayuLongFormPlayerScreen(
          video: video,
          initialPosition: widget.initialPosition,
          sectionEnd: widget.sectionEnd,
        ),
      );
    } else {
      targetRoute = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/yug_video'),
        builder: (_) => VideoScreen(
          initialVideos: [video],
          initialVideoId: video.id,
          videoType: 'yog',
          startAtSeconds: widget.initialPosition?.inSeconds,
          endAtSeconds: widget.sectionEnd?.inSeconds,
        ),
      );
    }

    AppLogger.log(
      'DeepLinkResolver: Opening ${video.videoType} player for ${video.id}',
    );

    await Navigator.of(context).push(targetRoute);
    DeepLinkPlaybackGate.release(widget.requestId);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _close() {
    DeepLinkPlaybackGate.release(widget.requestId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _isLoading ? _buildLoadingState() : _buildErrorState(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Semantics(
      label: 'Loading shared video',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 10,
            width: 140,
            decoration: BoxDecoration(
              color: AppColors.backgroundTertiary,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 10,
            width: 220,
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          const LinearProgressIndicator(
            minHeight: 3,
            color: AppColors.primary,
            backgroundColor: AppColors.backgroundTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Opening shared video...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.link_off_rounded,
          color: AppColors.textSecondary,
          size: 44,
        ),
        const SizedBox(height: 16),
        const Text(
          'Unable to open video',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Please try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Try again',
          onPressed: _resolveVideo,
          isFullWidth: true,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _close,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
