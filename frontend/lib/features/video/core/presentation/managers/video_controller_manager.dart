import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/managers/video_position_cache_manager.dart';
import 'package:vayug/shared/managers/hot_ui_state_manager.dart';
import 'package:vayug/shared/factories/video_controller_factory.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/video_disposal_utils.dart';
import 'dart:collection';
import 'dart:async';
import 'package:vayug/shared/utils/app_logger.dart';

class VideoControllerManager {
  static final VideoControllerManager _instance =
      VideoControllerManager._internal();
  factory VideoControllerManager() => _instance;
  VideoControllerManager._internal();

  final Map<int, VideoPlayerController> _controllers = {};
  bool Function(VideoPlayerController controller)? _playbackGuard;
  final Queue<int> _order = Queue();
  final Set<int> _pinned = {};
  final Set<int> _intentionallyPaused = {};
  final Map<int, String> _controllerSourceUrl = {};
  final Map<int, String> _controllerVideoIds = {};

  void setPlaybackGuard(bool Function(VideoPlayerController controller)? guard) {
    _playbackGuard = guard;
  }

  final VideoPositionCacheManager _positionCache = VideoPositionCacheManager();
  final HotUIStateManager _hotUIManager = HotUIStateManager();

  final int maxPoolSize = 4; // **PARTITIONED: 4/10 of global budget**

  // **ROUTE-POP HOOK: Called by AppNavigatorObserver when any route is popped**
  // The Yug feed registers a callback here so it can re-validate controllers
  // after the user pops back from a profile-launched video screen.
  void Function()? _onRoutePoppedCallback;

  void registerOnRoutePopped(void Function() callback) {
    _onRoutePoppedCallback = callback;
  }

  void unregisterOnRoutePopped() {
    _onRoutePoppedCallback = null;
  }

  void notifyRoutePopped() {
    _onRoutePoppedCallback?.call();
  }

  /// Choose a playback URL, preferring backend HLS over a raw source URL.
  String _selectPlaybackUrl(VideoModel video) {

    // Prefer explicit HLS URLs if present (served by backend/CDN)
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      AppLogger.log('✅ SELECTED: HLS Master Playlist');
      return video.hlsMasterPlaylistUrl!;
    }
    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      AppLogger.log('✅ SELECTED: HLS Playlist');
      return video.hlsPlaylistUrl!;
    }

    // Prefer lowQualityUrl if it's Cloudflare/CDN
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      final lower = video.lowQualityUrl!.toLowerCase();
      if (lower.contains('cdn.snehayog.site') ||
          lower.contains('cdn.snehayog.com') ||
          lower.contains('r2.cloudflarestorage.com')) {
        AppLogger.log('✅ SELECTED: Low Quality URL (CDN/R2)');
        return video.lowQualityUrl!;
      }
    }

    // No HLS playlist: use the original URL when it is already CDN-served.
    final origLower = video.videoUrl.toLowerCase();
    final isCdn = origLower.contains('cdn.snehayog.site') ||
        origLower.contains('cdn.snehayog.com') ||
        origLower.contains('r2.cloudflarestorage.com') ||
        origLower.contains('/hls/');
    if (isCdn) {
      AppLogger.log('✅ SELECTED: Original Video URL (CDN/R2/HLS)');
      return video.videoUrl;
    }

    // Fallback: use lowQualityUrl even if not CDN, else original
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      AppLogger.log('⚠️ FALLBACK: Low Quality URL');
      return video.lowQualityUrl!;
    }

    AppLogger.log('⚠️ FALLBACK: Original Video URL');
    return video.videoUrl;
  }

 
  Future<VideoPlayerController> getController(
      int index, VideoModel video) async {
    // Decide the final URL up front (prefer HLS, then CDN).
    String finalUrl = _selectPlaybackUrl(video);
    // AppLogger.log('🎯 VideoControllerManager: Selected playback URL: $finalUrl');

    // **CRITICAL FIX: Check if existing controller is valid**
    if (_controllers.containsKey(index)) {
      final existingController = _controllers[index];
      if (existingController != null && _isControllerValid(index)) {
        AppLogger.log(
            '♻️ VideoControllerManager: Reusing existing valid controller $index');
        return existingController;
      } else {
        // **CRITICAL FIX: Controller is invalid/disposed - completely remove it**
        AppLogger.log(
            '🔄 VideoControllerManager: Found invalid/disposed controller $index - removing for reinitialization');
        if (existingController != null) {
          // Stop position tracking before removal
          final videoId = _controllerVideoIds[index];
          if (videoId != null) {
            _positionCache.stopPositionTracking(existingController);
          }
          // Dispose if not already disposed
          try {
            // Try to pause and dispose - if it throws, controller is already disposed
            existingController.pause();
            existingController.setVolume(0.0);
            existingController.dispose();
          } catch (e) {
            AppLogger.log(
                '⚠️ VideoControllerManager: Controller $index already disposed or error: $e');
          }
        }
        // **CRITICAL: Completely remove from tracking**
        _removeControllerFromTracking(index);
      }
    }

    // **MEMORY MANAGEMENT: Only dispose controllers that are far from current index**
    final currentIndex = index;
    final controllersToRemove = <int>[];

    for (final key in _controllers.keys) {
      // **ADJUSTED: Keep within +/- 2 for 4-controller limit**
      if (key != currentIndex && (key - currentIndex).abs() > 2) {
        controllersToRemove.add(key);
      }
    }

    for (final key in controllersToRemove) {
      AppLogger.log(
          '🗑️ VideoControllerManager: Disposing distant controller $key');
      _disposeController(key);
    }

    // Create video model with signed URL if needed
    final videoWithSignedUrl =
        finalUrl != video.videoUrl ? video.copyWith(videoUrl: finalUrl) : video;

    // Use VideoControllerFactory to create optimized controller
    final controller =
        await VideoControllerFactory.createController(videoWithSignedUrl);

      try {
      // **WEB FIX: Web video player initialization may need longer timeout or different handling**
     const timeoutDuration =
          kIsWeb ? Duration(seconds: 15) : Duration(seconds: 10);
      await controller.initialize().timeout(
        timeoutDuration,
        onTimeout: () {
          throw TimeoutException(
              'Video initialization timeout', timeoutDuration);
        },
      ).catchError((error) {
        // **WEB FIX: Catch platform channel errors on web**
        AppLogger.log(
          '⚠️ VideoControllerManager: Video initialization error (may be web-specific): $error',
          isError: true,
        );
        // Re-throw to let caller handle
        throw error;
      });

      // **DIAGNOSTIC: Log player error state after successful init**
      if (controller.value.hasError) {
        AppLogger.log(
          '🔴 EXO-DIAG: Post-init error detected! '
          'hasError=${controller.value.hasError}, '
          'errorDescription=${controller.value.errorDescription}, '
          'videoId=${video.id}, url=$finalUrl',
          isError: true,
        );
      }

      controller.setLooping(true);

      // **DIAGNOSTIC: Add error listener for full ExoPlayer exception logging**
      controller.addListener(() {
        if (controller.value.hasError) {
          AppLogger.log(
            '🔴 EXO-ERROR: Player error during playback! '
            'videoId=${video.id}, '
            'index=$index, '
            'errorDescription=${controller.value.errorDescription}, '
            'position=${controller.value.position}, '
            'duration=${controller.value.duration}, '
            'isInitialized=${controller.value.isInitialized}, '
            'isPlaying=${controller.value.isPlaying}, '
            'url=$finalUrl',
            isError: true,
          );
        }
      });

      _controllers[index] = controller;
      _controllerSourceUrl[index] = finalUrl;
      _controllerVideoIds[index] =
          video.id; // Store video ID for position caching
      _order.addLast(index);
      _warmNetwork(finalUrl);
      _evictIfNeeded();

      // **POSITION CACHING: Restore video position and state**
      await _positionCache.restoreVideoState(controller, video.id);

      // **POSITION CACHING: Start tracking position for this video**
      _positionCache.startPositionTracking(controller, video.id);

      AppLogger.log(
          '✅ VideoControllerManager: Successfully created controller using VideoControllerFactory for ${video.videoName} with position caching');
      return controller;
    } catch (e, stack) {
      AppLogger.log(
        '🔴 EXO-DIAG: Controller initialization FAILED for ${video.videoName}: '
        'videoId=${video.id}, url=$finalUrl, '
        'errorType=${e.runtimeType}, error=$e',
        isError: true,
      );
      AppLogger.log('🔴 EXO-DIAG: Stack trace: $stack', isError: true);

      rethrow;
    }
  }

  /// Get controller for video index with URL (legacy method for backward compatibility)
  Future<VideoPlayerController> getControllerWithUrl(
      int index, String url) async {
    // Create a minimal VideoModel for backward compatibility
    final video = VideoModel(
      id: 'legacy_$index',
      videoName: 'Legacy Video $index',
      videoUrl: url,
      thumbnailUrl: '',
      likes: 0,
      views: 0,
      shares: 0,
      uploader: Uploader(id: 'legacy', name: 'Legacy', profilePic: ''),
      uploadedAt: DateTime.now(),
      likedBy: [],
      videoType: 'reel',
      aspectRatio: 9 / 16,
      duration: const Duration(seconds: 0),
    );

    return getController(index, video);
  }

  /// Preload controller but don't play yet using VideoModel
  Future<void> preloadController(int index, VideoModel video) async {
    try {
      AppLogger.log(
          '🚀 VideoControllerManager: Preloading controller $index for ${video.videoName}');

      // **SIMPLIFIED: Direct video controller creation for 480p videos**
      AppLogger.log(
          '🎬 VideoControllerManager: Preloading 480p video for ${video.videoName}');

      await getController(index, video);
      _warmNetwork(video.videoUrl);
    } catch (e) {
      AppLogger.log(
          '❌ VideoControllerManager: Error preloading controller $index: $e');
    }
  }

  /// Preload controller with URL (legacy method for backward compatibility)
  Future<void> preloadControllerWithUrl(int index, String url) async {
    // Create a minimal VideoModel for backward compatibility
    final video = VideoModel(
      id: 'legacy_$index',
      videoName: 'Legacy Video $index',
      videoUrl: url,
      thumbnailUrl: '',
      likes: 0,
      views: 0,
      shares: 0,
      uploader: Uploader(id: 'legacy', name: 'Legacy', profilePic: ''),
      uploadedAt: DateTime.now(),
      likedBy: [],
      videoType: 'yog',
      aspectRatio: 9 / 16,
      duration: const Duration(seconds: 0),
    );

    await preloadController(index, video);
  }

  /// Play controller instantly (already initialized)
  Future<void> playController(int index) async {
    if (_controllers.containsKey(index)) {
      final controller = _controllers[index]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        // **AUDIO FIX: Pause/mute all other videos before playing to prevent overlap**
        for (final entry in _controllers.entries) {
          if (entry.key != index) {
            try {
              await entry.value.pause();
              entry.value.setVolume(0.0);
              _intentionallyPaused.add(entry.key);
            } catch (_) {}
          }
        }

        // If the video is at the end (or very close), reset to start before playing
        final duration = controller.value.duration;
        final position = controller.value.position;
        if (duration.inMilliseconds > 0 &&
            (position >= duration - const Duration(milliseconds: 300))) {
          try {
            await controller.seekTo(Duration.zero);
          } catch (_) {}
        }
        try {
          controller.setVolume(1.0);
        } catch (_) {}
        if (_playbackGuard?.call(controller) == false) return;
        await controller.play();
        _intentionallyPaused.remove(index);

        // **POSITION CACHING: Save last video info**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          await _positionCache.saveLastVideo(videoId, index);
        }
      }
    }
  }

  /// Pause controller
  Future<void> pauseController(int index) async {
    if (_controllers.containsKey(index)) {
      await _controllers[index]!.pause();
      _intentionallyPaused.add(index);
    }
  }

  /// Play active video (for compatibility)
  Future<void> playActiveVideo() async {
    if (_controllers.isNotEmpty) {
      final activeIndex = _order.isNotEmpty ? _order.last : 0;
      await playController(activeIndex);
    }
  }

  /// **IMPROVED: Pause all videos but keep controllers in memory (better UX)**
  Future<void> pauseAllVideos() async {
    AppLogger.log(
        '⏸️ VideoControllerManager: Pausing all videos (keeping controllers)');

    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null &&
            controller.value.isInitialized &&
            controller.value.isPlaying) {
          await controller.pause();
          _intentionallyPaused.add(index);
          AppLogger.log(
              '⏸️ VideoControllerManager: Paused video at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error pausing video $index: $e');
      }
    }

    AppLogger.log(
        '✅ VideoControllerManager: All videos paused (controllers kept in memory)');
  }

  /// **LEGACY: Force pause all videos with volume muting (for critical situations)**
  Future<void> forcePauseAllVideos() async {
    AppLogger.log(
        '🛑 VideoControllerManager: Force pausing all videos and clearing audio');

    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null) {
          // **FIX: Force pause and mute immediately**
          await controller.pause();
          controller.setVolume(0.0);
          _intentionallyPaused.add(index);
          AppLogger.log(
              '🔇 VideoControllerManager: Paused and muted controller at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error pausing controller at index $index: $e');
      }
    }

    // **FIX: Clear all controller states to prevent audio overlap**
    _intentionallyPaused.clear();
    AppLogger.log(
        '✅ VideoControllerManager: All videos paused and states cleared');
  }

  /// **ENHANCED: Force clear all controllers to ensure single video playback**
  Future<void> forceClearAllControllers() async {
    AppLogger.log(
        '🧹 VideoControllerManager: Force clearing all controllers for single video playback');

    // **CRITICAL: Pause and dispose all controllers immediately**
    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null) {
          // **ENHANCED: Force pause and mute before disposal**
          await controller.pause();
          controller.setVolume(0.0);
          await controller.dispose();
          AppLogger.log(
              '🗑️ VideoControllerManager: Disposed and muted controller at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error disposing controller at index $index: $e');
      }
    }

    // **CRITICAL: Clear all maps and sets to prevent any video overlap**
    _controllers.clear();
    _order.clear();
    _pinned.clear();
    _intentionallyPaused.clear();
    _controllerSourceUrl.clear();
    _controllerVideoIds.clear();

    AppLogger.log(
        '✅ VideoControllerManager: All controllers cleared - single video playback ensured');
  }

  /// Check if video is intentionally paused
  bool isVideoIntentionallyPaused(int index) {
    return _intentionallyPaused.contains(index);
  }

  /// Get controller count
  int get controllerCount => _controllers.length;

  /// Pin indices to prevent eviction
  void pinIndices(Set<int> indices) {
    _pinned.addAll(indices);
  }

  /// Unpin indices
  void unpinIndices(Set<int> indices) {
    _pinned.removeAll(indices);
  }

  /// Optimize controllers (dispose old ones)
  void optimizeControllers() {
    // Dispose controllers that are not pinned and are old
    final toDispose = <int>[];
    for (final index in _controllers.keys) {
      // **ADJUSTED: Keep more controllers in memory (up to maxPoolSize)**
      if (!_pinned.contains(index) && _order.length > maxPoolSize) {
        toDispose.add(index);
      }
    }

    for (final index in toDispose) {
      _disposeController(index);
    }
  }

  /// Dispose all controllers
  void disposeAllControllers() {
    AppLogger.log('🗑️ VideoControllerManager: Disposing all controllers');
    for (final index in List<int>.from(_controllers.keys)) {
      _disposeController(index);
    }
  }

  /// Dispose specific controller with proper cleanup
  void _disposeController(int index) {
    if (_controllers.containsKey(index)) {
      try {
        final controller = _controllers[index]!;

        // **CRITICAL: Pause and stop before disposing**
        try {
          if (controller.value.isInitialized) {
            controller.pause();
            controller.setVolume(0.0);
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoControllerManager: Controller $index already paused/stopped: $e');
        }

        // **POSITION CACHING: Stop tracking position for this video**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          _positionCache.stopPositionTracking(controller);
        }

        // **CRITICAL FIX: Always dispose and remove controller from tracking**
        // Don't cache disposed controllers - they can't be reused
        try {
          controller.dispose();
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoControllerManager: Controller $index already disposed or error during disposal: $e');
        }

        // **CRITICAL: Completely remove from all tracking maps**
        _removeControllerFromTracking(index);

        AppLogger.log(
            '🗑️ VideoControllerManager: Fully disposed and removed controller $index from tracking');

        // **FORCE: Small delay to ensure MediaCodec cleanup**
        Future.delayed(const Duration(milliseconds: 50), () {
          AppLogger.log(
              '✅ VideoControllerManager: MediaCodec cleanup completed for controller $index');
        });
      } catch (e) {
        AppLogger.log(
            '❌ VideoControllerManager: Error disposing controller $index: $e');
        // **CRITICAL: Even on error, remove from tracking**
        _removeControllerFromTracking(index);
      }
    }
  }

  /// Evict controllers if pool is too large
  void _evictIfNeeded() {
    while (_controllers.length > maxPoolSize) {
      // Find victim (oldest non-pinned)
      int? victim;
      for (final index in _order) {
        if (!_pinned.contains(index)) {
          victim = index;
          break;
        }
      }

      if (victim == null) break;
      _order.removeWhere((i) => i == victim);
      _disposeController(victim);
    }
  }

  void _warmNetwork(String url) {
    // Network warming removed since VideoCacheManager was deleted
    // Videos now load directly through VideoPlayer for 480p content
    AppLogger.log(
        '🌐 VideoControllerManager: Network warming for 480p video: $url');
  }

  /// Clear all with proper MediaCodec cleanup
  void clear() {
    AppLogger.log(
        '🗑️ VideoControllerManager: Clearing all controllers and freeing MediaCodec memory');

    for (final entry in _controllers.entries) {
      try {
        final controller = entry.value;
        final index = entry.key;

        // **POSITION CACHING: Stop tracking position for this video**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          _positionCache.stopPositionTracking(controller);
        }

        // Use the disposal utility for proper cleanup
        VideoDisposalUtils.disposeController(controller,
            identifier: 'manager_index_$index');
      } catch (e) {
        AppLogger.log(
            '❌ VideoControllerManager: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllers.clear();
    _order.clear();
    _pinned.clear();
    _intentionallyPaused.clear();
    _controllerSourceUrl.clear();
    _controllerVideoIds.clear();

    // **FORCE: Delay to ensure MediaCodec cleanup completes**
    Future.delayed(const Duration(milliseconds: 100), () {
      AppLogger.log('✅ VideoControllerManager: All MediaCodec resources freed');
    });
  }

  /// **NEW: Handle app lifecycle changes**
  void onAppPaused() {
    AppLogger.log('⏸️ VideoControllerManager: App paused');
    onAppBackgrounded();
  }

  /// **App backgrounded: Perform aggressive cleanup to free memory**
  void onAppBackgrounded() {
    AppLogger.log('🧹 VideoControllerManager: App backgrounded - releasing non-active controllers');
    
    // 1. Identify the most recently used controller index
    int? currentIndex;
    if (_order.isNotEmpty) {
      currentIndex = _order.last;
    }

    // 2. Dispose all controllers except the current one
    if (currentIndex != null) {
      AppLogger.log('🛡️ VideoControllerManager: Keeping active controller at index $currentIndex, clearing neighbors');
      
      // Pause current
      final controller = _controllers[currentIndex];
      if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }

      // Dispose others
      final otherIndices = _controllers.keys.where((i) => i != currentIndex).toList();
      for (final index in otherIndices) {
        _disposeController(index);
      }
    } else {
      clear();
    }
  }

  void onAppResumed() {
    AppLogger.log('▶️ VideoControllerManager: App resumed');
    // Don't auto-resume videos - let user decide
  }

  void onAppDetached() {
    AppLogger.log(
        '🔌 VideoControllerManager: App detached - disposing all controllers');
    clear();
  }

  /// **NEW: Comprehensive dispose method for complete cleanup**
  void dispose() {
    AppLogger.log(
        '🗑️ VideoControllerManager: Starting comprehensive disposal...');

    // Clear all controllers
    clear();

    // Dispose position cache manager
    _positionCache.dispose();

    // Dispose hot UI state manager
    _hotUIManager.dispose();

    AppLogger.log('✅ VideoControllerManager: Comprehensive disposal completed');
  }

  // **COMPATIBILITY METHODS** - For existing code
  Future<void> initController(int index, dynamic video) async {
    await getController(index, video.videoUrl);
  }

  VideoPlayerController? getControllerByIndex(int index) {
    return _controllers[index];
  }

  Future<void> playVideo(int index) async {
    await playController(index);
  }

  Future<void> pauseVideo(int index) async {
    await pauseController(index);
  }

  Future<void> disposeController(int index) async {
    _disposeController(index);
  }

  /// Check if controller is cached and valid
  bool isControllerCached(int index) {
    return _isControllerValid(index);
  }

  /// Get cached controller count
  int get cachedControllerCount => _controllers.length;

  /// **CRITICAL FIX: Check if controller is valid and initialized**
  bool _isControllerValid(int index) {
    if (!_controllers.containsKey(index)) return false;
    final controller = _controllers[index]!;
    try {
      // Check if controller is initialized and has no errors
      // If controller is disposed, accessing .value will throw
      return controller.value.isInitialized && 
             !controller.value.hasError;
    } catch (e) {
      // If we can't access the value, it's disposed/invalid
      AppLogger.log(
          '⚠️ VideoControllerManager: Controller $index is invalid (access error: $e)');
      return false;
    }
  }

  /// **CRITICAL FIX: Completely remove controller from all tracking maps**
  void _removeControllerFromTracking(int index) {
    _controllers.remove(index);
    _order.removeWhere((i) => i == index);
    _intentionallyPaused.remove(index);
    _pinned.remove(index);
    _controllerSourceUrl.remove(index);
    _controllerVideoIds.remove(index);
  }

  /// Cleanup all controllers
  void cleanup() {
    clear();
  }

  /// **TAB CHANGE DETECTION: Pause all videos when user switches tabs**
  Future<void> pauseAllVideosOnTabChange({String? exceptVideoId}) async {
    final bool isSpecificExclusion = exceptVideoId != null;
    AppLogger.log(isSpecificExclusion
        ? '⏸️ VideoControllerManager: Selective global pause (excluding $exceptVideoId)'
        : '⏸️ VideoControllerManager: Tab change detected - pausing all videos');

    for (final index in _controllers.keys) {
      // **FIX: If this is the current video, don't pause it**
      if (isSpecificExclusion && _controllerVideoIds[index] == exceptVideoId) {
        continue;
      }

      final controller = _controllers[index];
      if (controller != null) {
        try {
          if (controller.value.isInitialized && controller.value.isPlaying) {
            await controller.pause();
            _intentionallyPaused.add(index);
            AppLogger.log(
                '⏸️ VideoControllerManager: Paused video at index $index');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoControllerManager: Error handling controller at index $index: $e');
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Resume videos when returning to video tab**
  Future<void> resumeVideosOnTabReturn() async {
    AppLogger.log(
        '▶️ VideoControllerManager: Returning to video tab - resuming videos');

    // Only resume the current active video, not all videos
    if (_controllers.isNotEmpty) {
      final activeIndex =
          _order.isNotEmpty ? _order.last : _controllers.keys.first;
      if (_controllers.containsKey(activeIndex)) {
        final controller = _controllers[activeIndex]!;
        if (controller.value.isInitialized &&
            !controller.value.hasError &&
            !controller.value.isPlaying) {
          try {
            if (_playbackGuard?.call(controller) == false) return;
            await controller.play();
            _intentionallyPaused.remove(activeIndex);
            AppLogger.log(
                '▶️ VideoControllerManager: Resumed video at index $activeIndex');
          } catch (e) {
            AppLogger.log(
                '❌ VideoControllerManager: Error resuming video at index $activeIndex: $e');
          }
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Force pause all videos immediately (for critical situations)**
  void forcePauseAllVideosSync({String? exceptVideoId}) {
    AppLogger.log(
        '🛑 VideoControllerManager: Force pausing all videos immediately${exceptVideoId != null ? ' (excluding $exceptVideoId)' : ''}');

    for (final index in _controllers.keys) {
      // **FIX: Exclusion check**
      if (exceptVideoId != null && _controllerVideoIds[index] == exceptVideoId) {
        continue;
      }

      final controller = _controllers[index];
      if (controller != null && controller.value.isInitialized) {
        try {
          controller.pause();
          _intentionallyPaused.add(index);
        } catch (e) {
          AppLogger.log(
              '❌ VideoControllerManager: Error force pausing video at index $index: $e');
        }
      }
    }
  }

  void saveUIStateForBackground(
      int currentIndex, double scrollPosition, Map<int, VideoModel> videos) {
    AppLogger.log('💾 VideoControllerManager: Saving UI state for background');

    _hotUIManager.saveUIState(
      currentIndex: currentIndex,
      scrollPosition: scrollPosition,
      controllers: _controllers,
      videos: videos,
    );
  }

  /// **HOT UI: Restore state when app comes to foreground**
  Map<String, dynamic>? restoreUIStateFromBackground() {
    AppLogger.log(
        '🔄 VideoControllerManager: Restoring UI state from background');

    if (_hotUIManager.isStateRestored) {
      final restoredState = _hotUIManager.restoreUIState();

      // Restore controllers from preserved state
      final preservedControllers = restoredState['preservedControllers']
          as Map<int, VideoPlayerController>?;
      if (preservedControllers != null) {
        _controllers.addAll(preservedControllers);
      }

      return restoredState;
    }

    return null;
  }

  /// **HOT UI: Check if we have preserved state**
  bool get hasPreservedState => _hotUIManager.isStateRestored;

  /// **HOT UI: Get state summary for debugging**
  Map<String, dynamic> getHotUIStateSummary() {
    return _hotUIManager.getStateSummary();
  }
}

