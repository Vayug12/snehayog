import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class VideoScreen extends ConsumerStatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType;
  final bool isMainYugTab; // **NEW: Flag to identify the primary Yug feed**
  final int? parentTabIndex; // **NEW: Tab context for autoplay logic**
  final int? startAtSeconds; // Share links: start playback of initialVideoId here
  final int? endAtSeconds; // Share links: pause playback of initialVideoId here

  const VideoScreen({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
    this.videoType,
    this.isMainYugTab = false,
    this.parentTabIndex,
    this.startAtSeconds,
    this.endAtSeconds,
  }) : super(key: key);

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  final GlobalKey _videoFeedKey = GlobalKey();

  /// **PUBLIC: Refresh video list after upload**
  Future<void> refreshVideos() async {
    AppLogger.log('🔄 VideoScreen: refreshVideos() called');
    final videoFeedState = _videoFeedKey.currentState;
    if (videoFeedState != null) {
      // Cast to dynamic to access the refreshVideos method
      await (videoFeedState as dynamic).refreshVideos();
      AppLogger.log('✅ VideoScreen: Video refresh completed');
    } else {
      AppLogger.log('❌ VideoScreen: VideoFeedAdvanced state not found');
    }
  }

  @override
  void initState() {
    super.initState();
    AppLogger.log('🎬 VideoScreen: Initializing VideoScreen');

    // **FIX: Pause all background videos when entering a new VideoScreen**
    // This ensures Yug tab videos pause if this screen is pushed as a full-screen player
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final mainController = ref.read(mainControllerProvider);
        mainController.forcePauseVideos();

        final state = _videoFeedKey.currentState;
        if (state != null) {
          try {
            (state as dynamic).forcePlayCurrent();
          } catch (_) {}
        }
      } catch (e) {
        AppLogger.log('⚠️ VideoScreen: Error pausing background videos: $e');
      }
    });

    // Some devices need a short delay for the first frame to attach
    Future.delayed(const Duration(milliseconds: 120), () {
      final s = _videoFeedKey.currentState;
      if (s != null) {
        try {
          (s as dynamic).forcePlayCurrent();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    AppLogger.log('🗑️ VideoScreen: Disposing VideoScreen');

    // **FIX: Pause all videos when leaving VideoScreen**
    try {
      final mainController = ref.read(mainControllerProvider);
      mainController.forcePauseVideos();

      final videoControllerManager = VideoControllerManager();
      videoControllerManager.forcePauseAllVideosSync(); // Use sync version

      AppLogger.log('🔇 VideoScreen: All videos paused on dispose');
    } catch (e) {
      AppLogger.log('⚠️ VideoScreen: Error pausing videos on dispose: $e');
    }

    // Clean up the video feed if needed
    final videoFeedState = _videoFeedKey.currentState;
    if (videoFeedState != null) {
      try {
        // The VideoFeedAdvanced dispose method will be called automatically
        AppLogger.log(
            '✅ VideoScreen: VideoFeedAdvanced disposal handled automatically');
      } catch (e) {
        AppLogger.log('⚠️ VideoScreen: Error during disposal: $e');
      }
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // **FIXED: Respect passed videoType (e.g. 'vayu') even if initialVideos are present**
    final String videoType = widget.videoType ?? 'yog';

    return VideoFeedAdvanced(
      key: _videoFeedKey,
      initialIndex: widget.initialIndex,
      initialVideos: widget.initialVideos,
      initialVideoId: widget.initialVideoId,
      startAtSeconds: widget.startAtSeconds,
      endAtSeconds: widget.endAtSeconds,
      videoType: videoType,
      isMainYugTab: widget.isMainYugTab,
      parentTabIndex: widget.parentTabIndex ?? ref.read(mainControllerProvider).currentIndex,
    );
  }
}

