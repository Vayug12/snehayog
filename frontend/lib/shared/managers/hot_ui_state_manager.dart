import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// **WhatsApp-Style Hot UI State Manager**
/// Maintains UI state during background/foreground transitions
/// Prevents heavy dispose/init operations like WhatsApp/Instagram
class HotUIStateManager {
  static final HotUIStateManager _instance = HotUIStateManager._internal();
  factory HotUIStateManager() => _instance;
  HotUIStateManager._internal();

  // **State Restoration**
  final Map<String, dynamic> _cachedState = {};
  final Map<int, VideoPlayerController> _preservedControllers = {};
  final Map<int, VideoModel> _preservedVideos = {};

  // **Lifecycle State**
  bool _isInBackground = false;
  bool _isStateRestored = false;
  int _lastActiveIndex = 0;
  double _lastScrollPosition = 0.0;

  // **Performance Optimization**
  Timer? _backgroundCleanupTimer;
  static const Duration _backgroundCleanupDelay = Duration(minutes: 5);

  /// **Save current UI state before going to background**
  void saveUIState({
    required int currentIndex,
    required double scrollPosition,
    required Map<int, VideoPlayerController> controllers,
    required Map<int, VideoModel> videos,
  }) {
    AppLogger.log('💾 HotUIStateManager: Saving UI state before background');

    _lastActiveIndex = currentIndex;
    _lastScrollPosition = scrollPosition;

    // **Preserve controllers instead of disposing**
    _preservedControllers.clear();
    _preservedControllers.addAll(controllers);

    // **Preserve video data**
    _preservedVideos.clear();
    _preservedVideos.addAll(videos);

    // **Save additional state**
    _cachedState['lastActiveIndex'] = currentIndex;
    _cachedState['lastScrollPosition'] = scrollPosition;
    _cachedState['timestamp'] = DateTime.now().millisecondsSinceEpoch;

    _isInBackground = true;
    _isStateRestored = false;

    // **Schedule background cleanup after delay**
    _scheduleBackgroundCleanup();
  }

  /// **Restore UI state when coming to foreground**
  Map<String, dynamic> restoreUIState() {
    AppLogger.log('🔄 HotUIStateManager: Restoring UI state from background');

    _isInBackground = false;
    _isStateRestored = true;

    // **Cancel background cleanup if app resumed quickly**
    _backgroundCleanupTimer?.cancel();

    return {
      'lastActiveIndex': _lastActiveIndex,
      'lastScrollPosition': _lastScrollPosition,
      'preservedControllers':
          Map<int, VideoPlayerController>.from(_preservedControllers),
      'preservedVideos': Map<int, VideoModel>.from(_preservedVideos),
      'isStateRestored': _isStateRestored,
    };
  }

  /// **Get preserved controller for index**
  VideoPlayerController? getPreservedController(int index) {
    return _preservedControllers[index];
  }

  /// **Get preserved video for index**
  VideoModel? getPreservedVideo(int index) {
    return _preservedVideos[index];
  }

  /// **Check if state is restored**
  bool get isStateRestored => _isStateRestored;

  /// **Check if in background**
  bool get isInBackground => _isInBackground;

  /// **Pause all preserved controllers (WhatsApp-style)**
  Future<void> pausePreservedControllers() async {
    AppLogger.log(
        '⏸️ HotUIStateManager: Pausing preserved controllers (WhatsApp-style)');

    for (final controller in _preservedControllers.values) {
      try {
        if (controller.value.isInitialized && !controller.value.hasError) {
          // **WhatsApp-style: Just pause, don't dispose**
          await controller.pause();
          controller.setVolume(0.0); // Mute audio
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ HotUIStateManager: Error pausing preserved controller: $e');
      }
    }
  }

  /// **Resume preserved controllers (WhatsApp-style)**
  Future<void> resumePreservedControllers() async {
    AppLogger.log(
        '▶️ HotUIStateManager: Resuming preserved controllers (WhatsApp-style)');

    for (final controller in _preservedControllers.values) {
      try {
        if (controller.value.isInitialized && !controller.value.hasError) {
          // **WhatsApp-style: Just resume, no re-init needed**
          await PlaybackCoordinator().requestOwnedPlay(
            controller,
            reason: 'hot UI resume',
          );
          controller.setVolume(1.0); // Restore audio
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ HotUIStateManager: Error resuming preserved controller: $e');
      }
    }
  }

  /// **Schedule background cleanup (like WhatsApp)**
  void _scheduleBackgroundCleanup() {
    _backgroundCleanupTimer?.cancel();
    _backgroundCleanupTimer = Timer(_backgroundCleanupDelay, () {
      if (_isInBackground) {
        AppLogger.log(
            '🧹 HotUIStateManager: Performing background cleanup after delay');
        _performBackgroundCleanup();
      }
    });
  }

  /// **Perform background cleanup (like WhatsApp)**
  void _performBackgroundCleanup() {
    AppLogger.log('🧹 HotUIStateManager: Cleaning up background resources');

    // **Clean up old controllers (keep only active one)**
    final activeIndex = _lastActiveIndex;
    final toRemove = <int>[];

    for (final index in _preservedControllers.keys) {
      if (index != activeIndex &&
          index != activeIndex - 1 &&
          index != activeIndex + 1) {
        toRemove.add(index);
      }
    }

    for (final index in toRemove) {
      _preservedControllers[index]?.dispose();
      _preservedControllers.remove(index);
      _preservedVideos.remove(index);
    }

    // **Clear cached state**
    _cachedState.clear();
  }

  /// **Handle app lifecycle changes (WhatsApp-style)**
  void handleAppLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        AppLogger.log(
            '📱 HotUIStateManager: App going to background - preserving state');
        pausePreservedControllers();
        break;
      case AppLifecycleState.resumed:
        AppLogger.log('📱 HotUIStateManager: App resuming - restoring state');
        resumePreservedControllers();
        break;
      case AppLifecycleState.detached:
        AppLogger.log('📱 HotUIStateManager: App detached - cleaning up');
        _performBackgroundCleanup();
        break;
      default:
        break;
    }
  }

  /// **Clear all preserved state**
  void clearPreservedState() {
    AppLogger.log('🧹 HotUIStateManager: Clearing all preserved state');

    for (final controller in _preservedControllers.values) {
      controller.dispose();
    }

    _preservedControllers.clear();
    _preservedVideos.clear();
    _cachedState.clear();
    _isStateRestored = false;
    _isInBackground = false;

    _backgroundCleanupTimer?.cancel();
  }

  /// **Get state summary for debugging**
  Map<String, dynamic> getStateSummary() {
    return {
      'isInBackground': _isInBackground,
      'isStateRestored': _isStateRestored,
      'lastActiveIndex': _lastActiveIndex,
      'lastScrollPosition': _lastScrollPosition,
      'preservedControllersCount': _preservedControllers.length,
      'preservedVideosCount': _preservedVideos.length,
      'cachedStateKeys': _cachedState.keys.toList(),
    };
  }

  /// **Dispose and cleanup all resources**
  void dispose() {
    AppLogger.log('🗑️ HotUIStateManager: Disposing all resources');
    clearPreservedState();
  }
}

