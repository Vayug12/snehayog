import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// **VideoPositionCacheManager - Caches video positions for seamless resume**
/// Stores video positions in SharedPreferences for persistence across app sessions
class VideoPositionCacheManager {
  static final VideoPositionCacheManager _instance =
      VideoPositionCacheManager._internal();
  factory VideoPositionCacheManager() => _instance;
  VideoPositionCacheManager._internal();

  static const String _positionPrefix = 'video_position_';
  static const String _lastVideoPrefix = 'last_video_';
  static const String _playbackStatePrefix = 'playback_state_';

  // In-memory cache for current session
  final Map<String, Duration> _positionCache = {};
  final Map<String, bool> _playbackStateCache = {};
  final Map<String, Timer> _trackingTimers = {}; // Track active timers
  String? _lastVideoId;
  int? _lastVideoIndex;

  /// **Initialize cache manager**
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load last video info
      _lastVideoId = prefs.getString('${_lastVideoPrefix}id');
      _lastVideoIndex = prefs.getInt('${_lastVideoPrefix}index');

      AppLogger.log(
          '🎬 VideoPositionCacheManager: Initialized - Last video: $_lastVideoId at index $_lastVideoIndex');
    } catch (e) {
      AppLogger.log('❌ VideoPositionCacheManager: Error initializing: $e');
    }
  }

  /// **Save video position**
  Future<void> saveVideoPosition(String videoId, Duration position) async {
    try {
      // Save to memory cache
      _positionCache[videoId] = position;

      // Save to persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_positionPrefix$videoId', position.inMilliseconds);

      AppLogger.log(
          '💾 VideoPositionCacheManager: Saved position for $videoId: ${position.inSeconds}s');
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error saving position for $videoId: $e');
    }
  }

  /// **Get video position**
  Future<Duration?> getVideoPosition(String videoId) async {
    try {
      // Check memory cache first
      if (_positionCache.containsKey(videoId)) {
        return _positionCache[videoId];
      }

      // Load from persistent storage
      final prefs = await SharedPreferences.getInstance();
      final positionMs = prefs.getInt('$_positionPrefix$videoId');

      if (positionMs != null) {
        final position = Duration(milliseconds: positionMs);
        _positionCache[videoId] = position; // Cache in memory
        return position;
      }

      return null;
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error getting position for $videoId: $e');
      return null;
    }
  }

  /// **Save video playback state (playing/paused)**
  Future<void> savePlaybackState(String videoId, bool isPlaying) async {
    try {
      // Save to memory cache
      _playbackStateCache[videoId] = isPlaying;

      // Save to persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_playbackStatePrefix$videoId', isPlaying);

      AppLogger.log(
          '💾 VideoPositionCacheManager: Saved playback state for $videoId: ${isPlaying ? "playing" : "paused"}');
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error saving playback state for $videoId: $e');
    }
  }

  /// **Get video playback state**
  Future<bool?> getPlaybackState(String videoId) async {
    try {
      // Check memory cache first
      if (_playbackStateCache.containsKey(videoId)) {
        return _playbackStateCache[videoId];
      }

      // Load from persistent storage
      final prefs = await SharedPreferences.getInstance();
      final isPlaying = prefs.getBool('$_playbackStatePrefix$videoId');

      if (isPlaying != null) {
        _playbackStateCache[videoId] = isPlaying; // Cache in memory
        return isPlaying;
      }

      return null;
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error getting playback state for $videoId: $e');
      return null;
    }
  }

  /// **Save last video info**
  Future<void> saveLastVideo(String videoId, int index) async {
    try {
      _lastVideoId = videoId;
      _lastVideoIndex = index;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_lastVideoPrefix}id', videoId);
      await prefs.setInt('${_lastVideoPrefix}index', index);

      AppLogger.log(
          '💾 VideoPositionCacheManager: Saved last video: $videoId at index $index');
    } catch (e) {
      AppLogger.log('❌ VideoPositionCacheManager: Error saving last video: $e');
    }
  }

  /// **Get last video info**
  String? get lastVideoId => _lastVideoId;
  int? get lastVideoIndex => _lastVideoIndex;

  /// **Restore video position and state**
  Future<void> restoreVideoState(
      VideoPlayerController controller, String videoId) async {
    try {
      if (!controller.value.isInitialized) {
        AppLogger.log(
            '⚠️ VideoPositionCacheManager: Controller not initialized, skipping restore');
        return;
      }

      // Get saved position
      final savedPosition = await getVideoPosition(videoId);
      if (savedPosition != null && savedPosition.inMilliseconds > 0) {
        // Seek to saved position
        await controller.seekTo(savedPosition);
        AppLogger.log(
            '🎬 VideoPositionCacheManager: Restored position for $videoId: ${savedPosition.inSeconds}s');
      }

      // Get saved playback state
      final savedPlaybackState = await getPlaybackState(videoId);
      if (savedPlaybackState == true) {
        // Resume playback if it was playing
        await PlaybackCoordinator().requestOwnedPlay(
          controller,
          reason: 'position restore',
        );
        AppLogger.log(
            '▶️ VideoPositionCacheManager: Resumed playback for $videoId');
      }
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error restoring video state for $videoId: $e');
    }
  }

  /// **Start position tracking for a video**
  void startPositionTracking(VideoPlayerController controller, String videoId) {
    // Cancel existing timer if any
    stopPositionTracking(controller);

    // Track position every 2 seconds
    final timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!controller.value.isInitialized) {
        timer.cancel();
        _trackingTimers.remove(videoId);
        return;
      }

      final position = controller.value.position;
      final duration = controller.value.duration;

      // Only save if video is not at the end
      if (duration.inMilliseconds > 0 &&
          position < duration - const Duration(seconds: 5)) {
        saveVideoPosition(videoId, position);
        savePlaybackState(videoId, controller.value.isPlaying);
      }
    });

    _trackingTimers[videoId] = timer;
  }

  /// **Stop position tracking for a video**
  void stopPositionTracking(VideoPlayerController controller) {
    // Find and cancel the timer for this controller
    final videoIdToRemove = _trackingTimers.keys.firstWhere(
      (videoId) => _trackingTimers[videoId] != null,
      orElse: () => '',
    );

    if (videoIdToRemove.isNotEmpty) {
      _trackingTimers[videoIdToRemove]?.cancel();
      _trackingTimers.remove(videoIdToRemove);
    }
  }

  /// **Clear video position**
  Future<void> clearVideoPosition(String videoId) async {
    try {
      _positionCache.remove(videoId);
      _playbackStateCache.remove(videoId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_positionPrefix$videoId');
      await prefs.remove('$_playbackStatePrefix$videoId');

      AppLogger.log(
          '🗑️ VideoPositionCacheManager: Cleared position for $videoId');
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error clearing position for $videoId: $e');
    }
  }

  /// **Clear all positions**
  Future<void> clearAllPositions() async {
    try {
      _positionCache.clear();
      _playbackStateCache.clear();
      _lastVideoId = null;
      _lastVideoIndex = null;

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) =>
              key.startsWith(_positionPrefix) ||
              key.startsWith(_playbackStatePrefix) ||
              key.startsWith(_lastVideoPrefix))
          .toList();

      for (final key in keys) {
        await prefs.remove(key);
      }

      AppLogger.log('🗑️ VideoPositionCacheManager: Cleared all positions');
    } catch (e) {
      AppLogger.log(
          '❌ VideoPositionCacheManager: Error clearing all positions: $e');
    }
  }

  /// **Get cache statistics**
  Map<String, dynamic> getCacheStats() {
    return {
      'cachedPositions': _positionCache.length,
      'cachedPlaybackStates': _playbackStateCache.length,
      'activeTrackingTimers': _trackingTimers.length,
      'lastVideoId': _lastVideoId,
      'lastVideoIndex': _lastVideoIndex,
    };
  }

  /// **Dispose and cleanup all resources**
  void dispose() {
    // Cancel all tracking timers
    for (final timer in _trackingTimers.values) {
      timer.cancel();
    }
    _trackingTimers.clear();

    // Clear caches
    _positionCache.clear();
    _playbackStateCache.clear();

    AppLogger.log('🗑️ VideoPositionCacheManager: Disposed all resources');
  }
}
