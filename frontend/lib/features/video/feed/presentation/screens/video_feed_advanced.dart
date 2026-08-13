import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/shared/di/dependency_injection.dart';

import 'package:vayug/core/providers/user_data_providers.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/managers/carousel_ad_manager.dart';
import 'package:like_button/like_button.dart';
import 'package:vayug/shared/constants/app_constants.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/spacing.dart';

import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/video/core/data/services/video_view_tracker.dart';
import 'package:vayug/features/ads/data/services/ad_refresh_notifier.dart';
import 'package:vayug/features/profile/core/data/services/background_profile_preloader.dart';
import 'package:vayug/features/profile/core/data/services/profile_preloader.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/video_aspect_surface.dart';

import 'package:vayug/features/ads/data/services/ad_impression_service.dart';
import 'package:vayug/features/ads/presentation/widgets/carousel_ad_widget.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/heart_animation.dart';
import 'package:vayug/shared/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/shared/widgets/share_options_sheet.dart';
import 'package:vayug/shared/widgets/episode_grid_widget.dart';
import 'video_feed_advanced/widgets/throttled_progress_bar.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:vayug/features/video/feed/presentation/widgets/video_feed_skeleton.dart';

import 'package:vayug/features/video/core/data/services/video_cache_proxy_service.dart';
import 'package:vayug/shared/services/local_gallery_service.dart';
import 'package:vayug/shared/services/deep_link_playback_gate.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';
import 'package:vayug/shared/widgets/tab_scope.dart';
import 'package:vayug/shared/navigation/app_route_observer.dart';
import 'package:vayug/features/video/edit/presentation/screens/edit_video_details.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/auth_sign_in_prompt.dart';
import 'package:vayug/core/interfaces/i_dubbing_service.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/features/video/dubbing/data/services/on_device_dubbing_service.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/video/core/presentation/widgets/quiz_overlay.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/core/interfaces/i_quiz_engine.dart';
import 'package:vayug/features/video/quiz/data/services/standard_quiz_engine.dart';

part 'video_feed_advanced/video_feed_advanced_state_fields.dart';
part 'video_feed_advanced/video_feed_advanced_playback.dart';
part 'video_feed_advanced/video_feed_advanced_persistence.dart';
part 'video_feed_advanced/video_feed_advanced_initialization.dart';
part 'video_feed_advanced/video_feed_advanced_data.dart';
part 'video_feed_advanced/video_feed_advanced_preload.dart';
part 'video_feed_advanced/video_feed_advanced_ui.dart';

// Debug logging helper for instrumentation
Future<void> _debugLog(String location, String message,
    Map<String, dynamic> data, String hypothesisId) async {
  // **OPTIMIZATION: Disabled filesystem logging in debug mode to prevent UI hangs**
  return;
}
// #endregion

class VideoFeedAdvanced extends ConsumerStatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType;
  final bool isMainYugTab; // **NEW: Flag to identify the primary Yug feed**
  final int?
      parentTabIndex; // **NEW: Tab index where this feed resides (0 for Yug, 1 for Vayu, etc.)**
  final int?
      startAtSeconds; // Share links: start playback of initialVideoId here
  final int? endAtSeconds; // Share links: pause playback of initialVideoId here
  final IDubbingService? dubbingService;
  final IAdService? adService;
  final IQuizEngine? quizEngine;

  const VideoFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
    this.videoType,
    this.isMainYugTab = false,
    this.parentTabIndex,
    this.startAtSeconds,
    this.endAtSeconds,
    this.dubbingService,
    this.adService,
    this.quizEngine,
  }) : super(key: key);

  @override
  ConsumerState<VideoFeedAdvanced> createState() => _VideoFeedAdvancedState();
}

class _VideoFeedAdvancedState extends ConsumerState<VideoFeedAdvanced>
    with
        WidgetsBindingObserver,
        RouteAware,
        AutomaticKeepAliveClientMixin,
        VideoFeedStateFieldsMixin {
  final Map<String, bool> _likeInProgress = {};
  Timer?
      _pageChangeDebounceTimer; // **NEW: Timer for debouncing page rapid scrolls**

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _playbackCoordinator.setRouteActive(_playbackSession, true);
    // The tab is bound in didChangeDependencies: TabScope is an inherited
    // widget and cannot be read here.
    // Removed redundant PageController and _loadVideos initialization.
    // These are now handled exclusively in _initializeServices() to prevent race conditions.

    // **NEW: Restore last viewed video index (Main Feed only)**
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // **FIX: Only restore if NOT opened with specific initial videos/index from Profile/Search**
      if (widget.initialVideos == null &&
          widget.initialIndex == null &&
          widget.initialVideoId == null &&
          mounted) {
        final mainController = ref.read(mainControllerProvider);
        final savedIndex =
            await mainController.getLastViewedVideoIndex(0); // Yug is tab 0
        if (savedIndex > 0 && mounted) {
          AppLogger.log(
              '🚀 VideoFeed: Resuming at video index $savedIndex (Main Feed)');
          if (_pageController.hasClients) {
            _pageController.jumpToPage(savedIndex);
          }
        }
      }
    });

    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // **ROUTE-POP FIX: Register controller re-validation callback for the main Yug feed.**
    // When a profile-launched VideoFeedAdvanced is popped, it fully disposes its controllers.
    // The Yug feed's local _controllerPool still holds the (now-disposed) references.
    // AppNavigatorObserver.didPop calls VideoControllerManager().notifyRoutePopped() which
    // triggers _validateAndRestoreControllers() here, re-initializing stale controllers
    // before _tryAutoplayCurrent() to prevent "Bad state: No active player with ID N".
    if (!_openedFromProfile) {
      _videoControllerManager.registerOnRoutePopped(() {
        if (mounted && !_openedFromProfile) {
          _validateAndRestoreControllers();
        }
      });
    }

    // Initialize services
    _initializeServices();
    _checkDeviceCapabilities();

    // **FIX: Immediately mark screen as visible if opened as a dedicated player (Profile/DeepLink)**
    // This allows forcePlayCurrent to work immediately without waiting for VisibilityDetector.
    if (_openedFromProfile || _openedFromDeepLink) {
      _isScreenVisible = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route != null && route != _playbackRoute) {
      if (_playbackRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _playbackRoute = route;
      appRouteObserver.subscribe(this, route);
    }

    // **PERFORMANCE: Cache MainController to avoid repeated ref.read() calls**
    _mainController = ref.watch(mainControllerProvider);

    // Declare where this feed lives. Doing it here rather than in initState
    // means a feed pushed from any screen, at any nesting depth, reports its
    // real tab instead of guessing — and the coordinator can therefore tell it
    // apart from the feed the user is actually looking at.
    _tabScopeIndex = TabScope.maybeOf(context);
    _playbackCoordinator.bindSessionToTab(_playbackSession, _feedTabIndex);
  }

  @override
  void onPlaybackActivated() => _resumeCurrentVideo();

  @override
  void onPlaybackDeactivated() => _pauseCurrentVideo();

  void _resumeCurrentVideo() {
    if (!mounted) return;
    // **RECOVERY: Re-initialize if evicted/disposed while in the background.**
    // Gated on being the active surface so a background feed cannot spend
    // decoders restoring controllers it is not allowed to play.
    if (!_playbackCoordinator.isActiveSurface(_playbackSession)) return;
    _validateAndRestoreControllers();
    _tryAutoplayCurrent();
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final video = _videos[_currentIndex];
      _viewTracker.stopViewTracking(video.id);
      final controller = _controllerPool[video.id];
      if (controller != null) {
        try {
          if (SharedVideoControllerPool().isControllerDisposed(controller)) {
            _controllerPool.remove(video.id);
            _controllerStates.remove(video.id);
          } else if (controller.value.isInitialized) {
            // Always call pause to override/cancel any pending or buffering play states
            controller.pause();
            _controllerStates[video.id] = false;
            _ensureWakelockForVisibility();
            AppLogger.log(
                '⏸️ VideoFeedAdvanced: Paused current video at index $_currentIndex');
          }
        } catch (e) {
          _controllerPool.remove(video.id);
          _controllerStates.remove(video.id);
          AppLogger.log(
              '⚠️ VideoFeedAdvanced: Error pausing current video: $e');
        }
      }
    }

    // Hand the global playback slot back. The next play re-claims it, and
    // without this the coordinator keeps pointing at a controller that is no
    // longer playing.
    _playbackCoordinator.pause(_playbackSession);
  }

  /// Silences every controller this feed can reach, without claiming anything
  /// about visibility or route state.
  void _pauseAllPooledVideos() {
    _pauseCurrentVideo();

    for (final entry in _controllerPool.entries.toList()) {
      try {
        if (SharedVideoControllerPool().isControllerDisposed(entry.value)) {
          continue;
        }
        if (entry.value.value.isInitialized && entry.value.value.isPlaying) {
          entry.value.pause();
          _controllerStates[entry.key] = false;
        }
      } catch (_) {}
    }
  }

  void _pauseAllVideosOnTabSwitch() {
    AppLogger.log('🔇 VideoFeedAdvanced: Pausing all videos for tab switch');
    _pauseAllPooledVideos();
    _isScreenVisible = false;
    _ensureWakelockForVisibility();
  }

  /// Silences this feed's *own* neighbours before it starts [activeId].
  ///
  /// Deliberately local. Silencing other surfaces is the coordinator's job and
  /// happens inside `claimForPlay`, which only a surface that is allowed to
  /// play ever reaches — a background feed doing it directly is exactly how a
  /// hidden player used to mute the visible one.
  void _pauseOtherLocalVideos(String activeId) {
    for (final entry in _controllerPool.entries.toList()) {
      if (entry.key != activeId) {
        try {
          if (entry.value.value.isPlaying) {
            entry.value.pause();
            _controllerStates[entry.key] = false;
          }
        } catch (_) {}
      }
    }

    _ensureWakelockForVisibility();
  }

  /// **Helper to allow extensions to call setState safely**
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  /// **Helper to get or create a ValueNotifier in a map without replacing the object**
  ValueNotifier<T> _getOrCreateNotifier<T>(
    Map<String, ValueNotifier<T>> map,
    String key,
    T initialValue,
  ) {
    if (map.containsKey(key)) {
      return map[key]!;
    } else {
      final notifier = ValueNotifier<T>(initialValue);
      map[key] = notifier;
      return notifier;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        _playbackCoordinator.setAppLifecycle(false);
        _handleAppMovedToBackground(state);
        break;
      case AppLifecycleState.inactive:
        _playbackCoordinator.setAppLifecycle(false);
        _handleAppMovedToBackground(state);
        break;
      case AppLifecycleState.resumed:
        _playbackCoordinator.setAppLifecycle(true);
        _videoControllerManager.onAppResumed();
        _retryBannerAdsNow(resetAttempts: true);
        // **FIX: Stop setting _isScreenVisible = true unconditionally**
        // Relying on VisibilityDetector and MainController index instead
        // to prevent audio leak when resuming on a different tab.
        _ensureWakelockForVisibility();
        _lifecyclePaused = false;

        // **FIX: Removed arbitrary 30-minute forced refresh**
        // Let the OS manage memory. If app is still alive, resume where we left off.
        // If OS killed it, proper state restoration (coming next) will handle it.
        _lastPausedAt = null; // Clear after use

        // Try restoring state after resume
        _restoreBackgroundStateIfAny().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            // **FIX: Only resume if THIS route is current (not obscured by Settings, etc.)**
            final bool isCurrentRoute =
                ModalRoute.of(context)?.isCurrent ?? true;
            if (!isCurrentRoute) {
              AppLogger.log(
                  '⏸️ Resume skipped: route is not current (obscured).');
              return;
            }

            if (_lifecyclePaused) {
              AppLogger.log(
                '⏸️ Resume detected but autoplay blocked until user interaction.',
              );
              return;
            }

            // Whether this feed is the one on screen is the coordinator's
            // answer, checked inside _tryAutoplayCurrent. Only the picker
            // cooldown is local knowledge worth keeping here.
            final mainController = _mainController;
            if (mainController != null &&
                (mainController.isMediaPickerActive ||
                    mainController.recentlyReturnedFromPicker)) {
              return;
            }
            _tryAutoplayCurrent();
          });
        });
        break;
      case AppLifecycleState.detached:
        _videoControllerManager.disposeAllControllers();
        _videoControllerManager.onAppDetached();
        _ensureWakelockForVisibility();
        break;
      case AppLifecycleState.hidden:
        _handleAppMovedToBackground(state);
        break;
      default:
        break;
    }
  }

  void _handleAppMovedToBackground(AppLifecycleState state) {
    // restoration logic removed

    _pauseAllVideosOnTabSwitch();
    _videoControllerManager.pauseAllVideos();
    _videoControllerManager.onAppPaused();
    SharedVideoControllerPool().pauseAllControllers();
    _lifecyclePaused = true;
    _pendingAutoplayAfterLogin = false;
    _ensureWakelockForVisibility();
    AppLogger.log(
      '📱 VideoFeedAdvanced: Lifecycle state $state triggered background handling; current video buffering initiated.',
    );
  }

  void _tryAutoplayCurrent() {
    if (_videos.isEmpty || _isLoading) return;
    if (!_shouldAutoplayForContext('tryAutoplayCurrent')) return;
    _autoAdvancedForIndex.remove(_currentIndex);

    // Check if current video is preloaded
    final video = _videos[_currentIndex];
    final controller = _controllerPool[video.id];

    if (controller != null) {
      final sharedPool = SharedVideoControllerPool();
      if (sharedPool.isControllerDisposed(controller)) {
        _controllerPool.remove(video.id);
        _controllerStates.remove(video.id);
      } else {
        try {
          if (!controller.value.isInitialized) {
            throw StateError('not initialized');
          }

          if (controller.value.isPlaying) {
            return;
          }

          if (_userPaused[video.id] == true) {
            /* AppLogger.log(
              '⏸️ Autoplay suppressed: user has manually paused video at index $_currentIndex',
            ); */
            return;
          }

          try {
            controller.setVolume(1.0);
          } catch (_) {}
          if (!_shouldAutoplayForContext('autoplay current immediate')) return;
          _pauseOtherLocalVideos(_videos[_currentIndex].id);
          _maybeApplyInitialStartSeek(video.id, controller);
          _playWithPolicy(controller, 'feed autoplay immediate');
          _ensureWakelockForVisibility();
          _controllerStates[video.id] = true;
          _userPaused[video.id] = false;
          _pendingAutoplayAfterLogin = false;

          // **NEW: Start view tracking with videoHash**
          if (_currentIndex < _videos.length) {
            final currentVideo = _videos[_currentIndex];
            _viewTracker.startViewTracking(
              currentVideo.id,
              videoUploaderId: currentVideo.uploader.id,
              videoHash: currentVideo.videoHash,
            );
          }

          // AppLogger.log('✅ VideoFeedAdvanced: Current video autoplay started');
          return;
        } catch (e) {
          _controllerPool.remove(video.id);
          _controllerStates.remove(video.id);
        }
      }
    }

    // Video not preloaded, preload it and play when ready
    /* AppLogger.log(
      '🔄 VideoFeedAdvanced: Current video not preloaded, preloading...',
    ); */
    final indexToPlay = _currentIndex;
    final videoToPlay = _videos[indexToPlay];
    _preloadVideo(indexToPlay).then((_) {
      if (mounted &&
          _currentIndex == indexToPlay &&
          _controllerPool.containsKey(videoToPlay.id)) {
        final pController = _controllerPool[videoToPlay.id];
        if (pController != null && pController.value.isInitialized) {
          // **FIX: Don't autoplay if user has manually paused the video**
          if (_userPaused[videoToPlay.id] == true) {
            AppLogger.log(
              '⏸️ Autoplay suppressed after preload: user has manually paused video at index $indexToPlay',
            );
            return;
          }
          if (!_shouldAutoplayForContext('autoplay current after preload')) {
            return;
          }

          try {
            pController.setVolume(1.0);
          } catch (_) {}
          _pauseOtherLocalVideos(_videos[indexToPlay].id);
          _playWithPolicy(pController, 'feed autoplay after preload');
          _ensureWakelockForVisibility();
          _controllerStates[videoToPlay.id] = true;
          _userPaused[videoToPlay.id] = false;
          _pendingAutoplayAfterLogin = false;

          // **NEW: Start view tracking with videoHash**
          if (indexToPlay < _videos.length) {
            final currentVideo = _videos[indexToPlay];
            _viewTracker.startViewTracking(
              currentVideo.id,
              videoUploaderId: currentVideo.uploader.id,
              videoHash: currentVideo.videoHash,
            );
          }

          /* AppLogger.log(
            '✅ VideoFeedAdvanced: Current video autoplay started after preloading',
          ); */
        }
      }
    });
  }

  // (Reverted: removed _autoplayWhenReady helper)

  /// **HANDLE VISIBILITY CHANGES: Pause/resume videos based on tab visibility**
  void _handleVisibilityChange(bool isVisible) {
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;
      // Route ownership is not derived from tab visibility any more: every tab
      // navigator now reports to appRouteObserver, so didPushNext/didPopNext
      // are the single source for `routeActive`. Deriving it here used to
      // strand the session with routeActive == false, which blocked autoplay
      // AND manual taps until the screen was rebuilt from scratch.
      // Tab visibility itself is owned by PlaybackCoordinator.setActiveTab().

      if (isVisible) {
        // Returning to Yug tab - ensure current video autoplays (no audio overlap)
        // 1) Mark first frame ready if controller already initialized
        if (_currentIndex < _videos.length) {
          final video = _videos[_currentIndex];
          final controller = _controllerPool[video.id];
          if (controller != null) {
            final sharedPool = SharedVideoControllerPool();
            if (sharedPool.isControllerDisposed(controller)) {
              _controllerPool.remove(video.id);
              _controllerStates.remove(video.id);
            } else {
              try {
                if (controller.value.isInitialized) {
                  // Controller is ready
                }
              } catch (e) {
                _controllerPool.remove(video.id);
                _controllerStates.remove(video.id);
              }
            }
          }
        }

        // 2) Pause everything else to avoid audio overlap. This must not touch
        // visibility state — we are becoming visible, not leaving.
        _pauseAllPooledVideos();
        _ensureWakelockForVisibility();

        // 3) Autoplay the current video
        /* AppLogger.log(
          '▶️ VideoFeedAdvanced: Yug tab visible - trying autoplay',
        ); */
        _tryAutoplayCurrent();

        // 4) Start background profile preloading
        _profilePreloader.startBackgroundPreloading();
      } else {
        // Screen became hidden - pause current video
        _pauseCurrentVideo();

        // **BANDWIDTH FIX: Cancel all prefetches to prioritize Profile screen (except active E2EE downloads)**
        videoCacheProxy.cancelAllPrefetchesExcept([]);

        // **NEW: Stop background profile preloading**
        _profilePreloader.stopBackgroundPreloading();
        _ensureWakelockForVisibility();
      }
    }

    // **NEW: RE-INITIALIZATION CHECK**
    // When becoming visible, validate controllers to ensure they weren't disposed externally
    if (isVisible) {
      _validateAndRestoreControllers();
    }
  }

  /// **NEW: Validate and restore disposed controllers**
  void _validateAndRestoreControllers() {
    if (_videos.isEmpty) return;

    final sharedPool = SharedVideoControllerPool();
    final List<int> indicesToRestore = [];

    // Check current and adjacent videos (priority range)
    final indicesToCheck = {
      _currentIndex,
      if (_currentIndex + 1 < _videos.length) _currentIndex + 1,
      if (_currentIndex - 1 >= 0) _currentIndex - 1
    };

    for (final index in indicesToCheck) {
      final video = _videos[index];
      bool needsRestore = false;

      // 1. Check local pool for disposal
      if (_controllerPool.containsKey(video.id)) {
        final controller = _controllerPool[video.id];
        if (sharedPool.isControllerDisposed(controller)) {
          AppLogger.log(
              '⚠️ VideoFeedAdvanced: Controller for ${video.id} is DISPOSED (local). Marking for restore.');
          _controllerPool.remove(video.id);
          _controllerStates.remove(video.id);
          _preloadedVideos.remove(video.id);
          needsRestore = true;
        }
      } else {
        // 2. Not in local pool - check if shared pool has a valid one we can adopt
        final sharedController = sharedPool.getController(video.id);
        if (sharedController != null &&
            !sharedPool.isControllerDisposed(sharedController)) {
          AppLogger.log(
              '♻️ VideoFeedAdvanced: Adopting valid controller from shared pool for ${video.id}');
          _controllerPool[video.id] = sharedController;
          _controllerStates[video.id] = false;
          _preloadedVideos.add(video.id);

          // Attach listeners to this adopted controller
          _attachEndListenerIfNeeded(sharedController, index);
          _attachBufferingListenerIfNeeded(sharedController, index);
        } else {
          // If it's the CURRENT video, we definitely need it
          if (index == _currentIndex) {
            needsRestore = true;
          }
        }
      }

      if (needsRestore) {
        indicesToRestore.add(index);
      }
    }

    // Restore missing/disposed controllers
    for (final index in indicesToRestore) {
      if (index == _currentIndex) {
        AppLogger.log(
            '🔄 VideoFeedAdvanced: Restoring controller for index $index (Current Video)');
      }

      _preloadVideo(index).then((_) {
        if (mounted && index == _currentIndex && _isScreenVisible) {
          // If we restored the current video and screen is visible, try playing
          _tryAutoplayCurrent();
        }
      });
    }
  }

  /// **NEW: Handle automatic recovery when a child detects a disposed controller**
  void _handleControllerInvalid(int index) {
    if (!mounted || index < 0 || index >= _videos.length) return;

    final video = _videos[index];
    final videoId = video.id;

    AppLogger.log(
        '🩹 SELF-HEAL: Detected disposed controller for $videoId at index $index. Re-initializing...');

    // 1. Synchronous Immediate Cleanup: Ensure next build sees \'null\'
    _controllerPool.remove(videoId);
    _controllerStates.remove(videoId);
    _preloadedVideos.remove(videoId);

    // 2. Refresh the UI to show loading state immediately
    safeSetState(() {});

    // 3. Trigger async recovery
    _preloadVideo(index).then((_) {
      if (mounted) {
        AppLogger.log('✅ SELF-HEAL: Controller restored for $videoId');
        safeSetState(() {});
      }
    });
  }

  void _enableWakelock() {
    if (_wakelockEnabled) return;
    WakelockPlus.enable();
    _wakelockEnabled = true;
  }

  void _disableWakelock() {
    if (!_wakelockEnabled) return;
    WakelockPlus.disable();
    _wakelockEnabled = false;
  }

  bool _hasActivePlayback() {
    // Controllers in _controllerPool may have been disposed by other screens
    // (for example, ProfileScreen). Accessing controller.value on a disposed
    // controller throws "A VideoPlayerController was used after being disposed".
    // We defensively catch that here and clean up local references.
    for (final entry in _controllerPool.entries.toList()) {
      final videoId = entry.key;
      final controller = entry.value;

      try {
        final value = controller.value;
        if (value.isInitialized && value.isPlaying) {
          return true;
        }
      } catch (e) {
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Detected disposed controller for $videoId in _hasActivePlayback, cleaning up: $e',
        );
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    }

    return SharedVideoControllerPool().hasActivePlayback();
  }

  /// The tab this feed lives in, or `null` when it is not tied to one.
  ///
  /// An explicit `parentTabIndex` wins so a caller can override; otherwise the
  /// enclosing [TabScope] answers it, which is correct however deeply this feed
  /// was pushed.
  int? get _feedTabIndex => widget.parentTabIndex ?? _tabScopeIndex;

  /// True only for a player pushed as its own route (profile grid, search).
  ///
  /// The main Yug tab also receives `initialVideos` for a warm start, so
  /// inferring "dedicated player" from that list alone made the background feed
  /// claim playback from whatever the user was actually watching — and it did
  /// so only when the startup prefetch happened to win the race.
  bool get _openedFromProfile =>
      !widget.isMainYugTab &&
      widget.initialVideos != null &&
      widget.initialVideos!.isNotEmpty;

  bool get _openedFromDeepLink =>
      widget.initialVideoId != null && widget.initialVideos == null;

  /// Whether this feed may start a video right now.
  ///
  /// Placement — tab, route, app lifecycle — is answered exclusively by the
  /// coordinator. This used to re-derive it here, with an escape hatch for
  /// feeds opened from a profile or a deep link that skipped the tab check
  /// entirely; a feed sitting in a background tab therefore believed it should
  /// play, silenced every other surface on its way to being refused, and left
  /// the visible feed paused. What remains here is only what the coordinator
  /// cannot see: this widget's own readiness.
  bool _shouldAutoplayForContext(String reason) {
    if (widget.isMainYugTab && DeepLinkPlaybackGate.isActive) {
      AppLogger.log('AUTOPLAY[$reason]: Shared video link is resolving');
      return false;
    }

    if (!_playbackCoordinator.canPlay(_playbackSession, reason: reason)) {
      return false;
    }

    // Lifecycle Guard: covers the window before the coordinator is told the app
    // left the foreground.
    if (!_allowAutoplay(reason)) {
      AppLogger.log('🚫 AUTOPLAY[$reason]: blocked by app lifecycle');
      return false;
    }

    // Auth Loading Guard
    if (ref.read(googleSignInProvider).isLoading) {
      AppLogger.log('🚫 AUTOPLAY[$reason]: Auth is loading');
      return false;
    }

    // Component Visibility Guard: this widget can be scrolled off inside an
    // otherwise-active route, which no route or tab state reflects.
    if (!_isScreenVisible) {
      AppLogger.log(
          '🚫 AUTOPLAY[$reason]: component hidden (_isScreenVisible=false)');
      return false;
    }

    return true;
  }

  void _scheduleAutoplayAfterLogin() {
    if (!_pendingAutoplayAfterLogin) return;

    // Use postFrameCallback instead of delay for faster autoplay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!_shouldAutoplayForContext('autoplay after login')) {
        AppLogger.log(
          '⏸️ Autoplay deferred (login): Yug tab not active or screen hidden',
        );
        return;
      }

      _pendingAutoplayAfterLogin = false;
      AppLogger.log('🚀 Triggering autoplay after login');
      forcePlayCurrent();
    });
  }

  void _ensureWakelockForVisibility() {
    final bool shouldKeepAwake =
        (_isScreenVisible && !_lifecyclePaused) || _hasActivePlayback();
    if (shouldKeepAwake) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }
  }

  bool _allowAutoplay(String reason) {
    if (_lifecyclePaused) {
      AppLogger.log('⏸️ Autoplay blocked ($reason) due to lifecycle pause.');
      return false;
    }

    // **FIX: Extra safeguard - check auth loading state**
    if (ref.read(googleSignInProvider).isLoading) {
      return false;
    }

    // **FIX: Extra safeguard - check actual system lifecycle state**
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      AppLogger.log(
          '⏸️ Autoplay blocked ($reason): System state is ${WidgetsBinding.instance.lifecycleState}');
      return false;
    }
    return true;
  }

  /// **NEW: Pause videos before navigating away (e.g., to creator profile)**
  void _pauseVideosForProfileNavigation() {
    try {
      AppLogger.log(
          '⏸️ VideoFeedAdvanced: Pausing current video before navigation');

      // Navigating away is not a user pause. Marking it as one used to survive
      // the trip and suppress autoplay after the pop, leaving the feed frozen.
      // A late autoplay from a still-loading video is now blocked by the
      // coordinator instead: the pushed route flips routeActive to false.
      final video = _videos[_currentIndex];
      _controllerStates[video.id] = false;

      _pauseCurrentVideo();
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error pausing current video: $e');
    }

    try {
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();
    } catch (e) {
      AppLogger.log(
          '⚠️ VideoFeedAdvanced: Error pausing SharedVideoControllerPool: $e');
    }

    try {
      _videoControllerManager.pauseAllVideosOnTabChange();
    } catch (e) {
      AppLogger.log(
          '⚠️ VideoFeedAdvanced: Error pausing VideoControllerManager: $e');
    }
  }

  // Duplicate methods removed to use video_feed_advanced_preload.dart implementation

  /// **GET OR CREATE CONTROLLER: Unified shared pool strategy**
  VideoPlayerController? _getController(int index) {
    if (index >= _videos.length) return null;

    final videoId = _videos[index].id;
    final sharedPool = SharedVideoControllerPool();

    // **PRIORITY 1: Check existing local reference with ATOMIC VALIDATION**
    VideoPlayerController? controller = _controllerPool[videoId];
    if (controller != null) {
      if (!sharedPool.isControllerValid(controller)) {
        AppLogger.log(
            '⚠️ VideoFeed: Local controller for $videoId is STALE. Evicting.');
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
        _preloadedVideos.remove(videoId);
        _lastAccessedLocal.remove(videoId);
        controller = null;
      } else {
        _lastAccessedLocal[videoId] = DateTime.now();
        return controller;
      }
    }

    // **PRIORITY 2: Try to get/adopt from Shared Pool (Global)**
    controller = sharedPool.getControllerForInstantPlay(videoId);
    if (!sharedPool.isControllerValid(controller)) {
      controller = sharedPool.getController(videoId);
    }

    // **PRIORITY 3: If valid, adopt into local state**
    if (sharedPool.isControllerValid(controller)) {
      AppLogger.log(
          '⚡ VideoFeed: Adopting controller for $videoId from global pool');
      _controllerPool[videoId] = controller!;
      _controllerStates[videoId] = false;
      _preloadedVideos.add(videoId);
      _lastAccessedLocal[videoId] = DateTime.now();
      return controller;
    }

    return null;
  }

  /// **HANDLE PAGE CHANGES** - Unified with debouncing and persistence
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    // 1. Pause current video before moving to next
    _pauseCurrentVideo();

    // The coordinator's pause intent is per session, not per video, so a tap
    // pause on the previous video would otherwise keep blocking every autoplay
    // that follows an auto-scroll. Per-video intent lives in _userPaused.
    _playbackCoordinator.setUserPaused(_playbackSession, false);

    // 2. Persist current video index for state restoration - **FIX: Always check bounds**
    if (index >= 0 && index < _videos.length) {
      ref
          .read(mainControllerProvider)
          .updateCurrentVideoIndex(index, tabIndex: 0);
    }

    // 3. Update local state
    setState(() {
      _currentIndex = index;
      _activeQuizVN.value = null;
    });

    // 3b. PIN the new current video immediately, before any preload runs.
    // Preloading a neighbour refreshes that neighbour's LRU timestamp, so
    // without this the video on screen can become the eviction candidate.
    if (index >= 0 && index < _videos.length) {
      SharedVideoControllerPool()
          .pinVideo(_videos[index].id, sessionId: _playbackSession.id);
    }

    // 4. Handle preloading and resource protection (debounced)
    // We wait 300ms for the page to "snap" before triggering heavy autoplay logic
    _pageChangeDebounceTimer?.cancel();
    _pageChangeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && index == _currentIndex) {
        _handlePageChange(index);
      }
    });

    // 5. IMMEDIATE PRELOAD: Start loading the target video as soon as swipe starts
    // This reduces the 'black screen' time when the debounce finishes.
    _preloadVideo(index);

    // 5. Scroll Velocity Detection
    final currentTime = DateTime.now();
    final scrollDelta =
        currentTime.difference(_lastPageChangeTime).inMilliseconds;
    _lastPageChangeTime = currentTime;
    _wasLastScrollFast = scrollDelta < 300;

    // 6. RESOURCE PROTECTION: Cancel irrelevant loads
    _cancelIrrelevantPreloads(index);
  }

  /// **Video ids occupying positions [start, end] in the CURRENT list.**
  ///
  /// Recomputed on every call on purpose: the pool must never cache positions,
  /// because pagination and refresh invalidate them.
  Set<String> _keepAliveVideoIds(int start, int end) {
    final ids = <String>{};
    for (int i = start; i <= end; i++) {
      if (i >= 0 && i < _videos.length) {
        ids.add(_videos[i].id);
      }
    }
    return ids;
  }

  /// **CANCELLATION HELPER: Discard work for videos the user skipped**
  void _cancelIrrelevantPreloads(int currentIndex) {
    // 1. Cancel all debounce timers except for the one we might be about to start
    _preloadDebounceTimers.forEach((videoId, timer) {
      // If videoId doesn't belong to index or index±1, kill it
      bool isRelevant = false;
      for (int i = currentIndex - 1; i <= currentIndex + 1; i++) {
        if (i >= 0 && i < _videos.length && _videos[i].id == videoId) {
          isRelevant = true;
          break;
        }
      }
      if (!isRelevant) {
        timer.cancel();
      }
    });

    // 2. Clear loading/initializing flags for far-away videos
    // This allows Relevancy Checkpoints in _preloadVideo to trigger correctly
    _loadingVideos.removeWhere((videoId) {
      bool isRelevant = false;
      for (int i = currentIndex - 1; i <= currentIndex + 1; i++) {
        if (i >= 0 && i < _videos.length && _videos[i].id == videoId) {
          isRelevant = true;
          break;
        }
      }
      return !isRelevant;
    });

    // 3. Ruthless Disposal: Kill controllers that are definitely not needed
    // This frees hardware decoders instantly during fast scroll.
    // The pinned (playing) video survives this regardless of the keep set.
    SharedVideoControllerPool()
        .retainOnly(_keepAliveVideoIds(currentIndex - 1, currentIndex + 1));
  }

  /// **PAGE CHANGE HANDLER**
  void _handlePageChange(int index) {
    if (!mounted || index != _currentIndex) return;

    AppLogger.log(
        '📱 Page changed to index $index. Triggering SNAP autoplay...');

    // 1. Trigger autoplay for the now-centered video
    _tryAutoplayCurrent();

    // 2. Refresh the pre-warm window based on new position
    _preloadNearbyVideos();

    // 3. Mark as seen
    _markCurrentVideoAsSeen();
  }

  /// **NEW: Atomic safety helper for getting a valid controller**
  VideoPlayerController? _getValidController(int index) {
    if (index < 0 || index >= _videos.length) return null;
    final videoId = _videos[index].id;
    final controller = _controllerPool[videoId];

    if (controller == null) return null;

    // **CRITICAL SAFETY CHECK: Global -> Local Sync**
    final sharedPool = SharedVideoControllerPool();
    if (!sharedPool.isControllerValid(controller)) {
      AppLogger.log(
          '⚠️ VideoFeed: Detected stale local reference for video $videoId. Evicting local entry.');
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _preloadedVideos.remove(videoId);
      _lastAccessedLocal.remove(videoId);
      return null;
    }

    return controller;
  }

  /// **DEBOUNCED PRELOAD: Avoid too many preloads during fast scrolling**
  void _preloadNearbyVideosDebounced() {
    _preloadDebounceTimer?.cancel();
    _preloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _preloadNearbyVideos();
    });
  }

  void _openReportDialog(String videoId) {
    if (videoId.isEmpty) return;
    VayuBottomSheet.show(
      context: context,
      title: 'Report Content',
      icon: Icons.report_problem_outlined,
      child: ReportDialogWidget(targetType: 'video', targetId: videoId),
    );
  }

  void _seekToPosition(VideoPlayerController controller, dynamic details) {
    if (!controller.value.isInitialized) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final screenWidth = _screenWidth ?? MediaQuery.of(context).size.width;
    final seekPosition = (localPosition.dx / screenWidth).clamp(0.0, 1.0);

    final duration = controller.value.duration;
    final newPosition = duration * seekPosition;

    controller.seekTo(newPosition);
  }

  // Quality indicator methods removed per requirement

  void _togglePlayPause(int index) {
    Vibration.vibrate(duration: 50, amplitude: 128);
    if (index >= _videos.length) return;
    final video = _videos[index];
    final String videoId = video.id;

    // **FIX: Prevent multiple simultaneous toggles on the same video (race condition fix)**
    if (_togglingVideos.contains(videoId)) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Already toggling video $videoId, ignoring duplicate tap',
      );
      return;
    }
    final controller = _controllerPool[video.id];
    if (controller == null || !controller.value.isInitialized) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Controller not available or not initialized for index $index, preloading...',
      );

      // Preload video and then play it
      _preloadVideo(index).then((_) {
        if (!mounted) return;
        final c = _controllerPool[videoId];
        if (c != null && c.value.isInitialized) {
          try {
            _pauseOtherLocalVideos(videoId);
            _autoAdvancedForIndex.remove(index);
            _playWithPolicy(c, 'feed tap after preload');
            // **OPTIMIZED: Use ValueNotifier - NO setState**
            _controllerStates[videoId] = true;
            _userPaused[videoId] = false;
            _userPausedVN[videoId]?.value = false;

            AppLogger.log(
              '▶️ Successfully played video at index $index after preload',
            );

            // Start view tracking
            if (index < _videos.length) {
              final currentVideo = _videos[index];
              _viewTracker.startViewTracking(
                currentVideo.id,
                videoUploaderId: currentVideo.uploader.id,
              );
              AppLogger.log(
                '▶️ User played video: ${currentVideo.id}, started view tracking',
              );
            }
          } catch (e) {
            AppLogger.log(
              '❌ Error playing video after preload at index $index: $e',
            );
          }
        }
      }).catchError((e) {
        AppLogger.log(
          '❌ Error preloading video for play/pause at index $index: $e',
        );
      });
      return;
    }

    // **FIX: Add lock to prevent concurrent toggles**
    _togglingVideos.add(videoId);

    // **FIX: Check actual controller state instead of relying on _controllerStates map**
    // This ensures we always have the correct state, even if map is out of sync
    final isCurrentlyPlaying = controller.value.isPlaying;

    AppLogger.log(
      '🔄 _togglePlayPause: Video $index - Current state: ${isCurrentlyPlaying ? "playing" : "paused"}',
    );

    if (isCurrentlyPlaying) {
      // **FIX: Video is playing, so pause it - update state immediately before pause**
      try {
        // **CRITICAL: Update state FIRST, then pause - this ensures UI responds immediately**
        // **OPTIMIZED: Use ValueNotifier for granular updates - NO setState**
        _controllerStates[videoId] = false;
        _userPaused[videoId] = true;
        _userPausedVN[videoId]?.value = true;
        _playbackCoordinator.setUserPaused(_playbackSession, true);

        // Now pause the controller
        controller.pause();
        _ensureWakelockForVisibility();

        AppLogger.log('⏸️ Successfully paused video at index $index');

        // **NEW: Trigger popup ad on pause for Yug tab (separate from long-press)**
        if (widget.videoType == 'yog') {
          _showPauseAd(index);
        }

        // **NEW: Stop view tracking when user pauses**
        if (index < _videos.length) {
          final currentVideo = _videos[index];
          _viewTracker.stopViewTracking(currentVideo.id);
          AppLogger.log(
            '⏸️ User paused video: ${currentVideo.id}, stopped view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error pausing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(videoId);
        return;
      }
    } else {
      // **FIX: Video is paused, so play it - update state immediately before play**
      try {
        _pauseOtherLocalVideos(videoId);

        // **CRITICAL: Update state FIRST, then play - this ensures UI responds immediately**
        // **OPTIMIZED: Use ValueNotifier for granular updates - NO setState**
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false; // hide when playing
        _userPausedVN[videoId]?.value = false;
        _playbackCoordinator.setUserPaused(_playbackSession, false);
        _hideLongPressAdOverlay();
        _hidePauseAdOverlay(
            videoId: videoId); // **NEW: Hide pause ad when video plays**

        _lifecyclePaused = false;

        // Now play the controller
        _autoAdvancedForIndex.remove(index);
        _playWithPolicy(controller, 'feed tap play');
        _ensureWakelockForVisibility();

        AppLogger.log('▶️ Successfully played video at index $index');

        // **NEW: Start view tracking when user plays**
        if (index < _videos.length) {
          final currentVideo = _videos[index];
          _viewTracker.startViewTracking(
            currentVideo.id,
            videoUploaderId: currentVideo.uploader.id,
          );
          AppLogger.log(
            '▶️ User played video: ${currentVideo.id}, started view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error playing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(videoId);
        return;
      }
    }

    // **FIX: Remove lock after a short delay to allow state to settle**
    // This prevents rapid taps from causing race conditions
    Future.delayed(const Duration(milliseconds: 200), () {
      _togglingVideos.remove(videoId);
    });
  }

  /// **BUILD CAROUSEL AD PAGE: Full-screen carousel ad within horizontal PageView**
  // Method removed to use optimized implementation in video_feed_advanced_preload.dart extension

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    final videoId = _videos[index].id;
    final existing = _bufferingListeners[videoId];
    if (existing != null) {
      SharedVideoControllerPool().detachListener(videoId, existing);
    }
    void listener() {
      if (!mounted) return;
      final bool next =
          controller.value.isInitialized && controller.value.isBuffering;
      final bool current = _isBuffering[videoId] ?? false;
      if (current != next) {
        // Update map (for any legacy reads)
        _isBuffering[videoId] = next;
        // Update ValueNotifier to avoid rebuilding the whole Stack
        (_isBufferingVN[videoId] ??= ValueNotifier<bool>(false)).value = next;
      }
    }

    SharedVideoControllerPool().attachListener(videoId, listener);
    _bufferingListeners[videoId] = listener;

    // (Removed first-frame tracking listener per revert)
  }

  void _applyLoopingBehavior(VideoPlayerController controller) {
    controller.setLooping(!_autoScrollEnabled);
  }

  /// **GET USER-FRIENDLY ERROR MESSAGE: Convert technical errors to user-friendly messages**
  String _getUserFriendlyErrorMessage(dynamic error) {
    // Use ConnectivityService for network error detection
    if (ConnectivityService.isNetworkError(error)) {
      return ConnectivityService.getNetworkErrorMessage(error);
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('device_key_changed') ||
        errorString.contains('device_key_missing')) {
      return 'This device cannot decrypt this video. Please use the original device or contact support.';
    }
    if (errorString.contains('authentication_required') ||
        errorString.contains('please sign in again') ||
        errorString.contains('please sign in to watch this encrypted video')) {
      return 'Please sign in to watch this encrypted video.';
    }
    if (errorString.contains('access_denied')) {
      return 'You do not have access to this encrypted video.';
    }

    if (errorString.contains('decoding error') ||
        errorString.contains('e2ee') ||
        errorString.contains('decrypt') ||
        errorString.contains('symmetric key') ||
        errorString.contains('video-key')) {
      return "You can't access this video. It is End-to-End Encrypted (E2EE).";
    }

    // E2EE source error — video was still downloading when player tried to play
    if (errorString.contains('e2ee_error') ||
        (errorString.contains('source') && errorString.contains('error'))) {
      return 'Secure video is still loading. Please wait a moment and try again.';
    }

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your internet connection.';
    } else if (errorString.contains('404')) {
      return 'Videos not found';
    } else if (errorString.contains('500')) {
      return 'Server error. Please try again later.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return 'Authentication required. Please sign in again.';
    } else if (errorString.contains('403')) {
      return 'Access denied. You may not have permission for this action.';
    } else {
      return 'Unable to load videos. Please try again.';
    }
  }

  /// **HANDLE DOUBLE TAP LIKE: Show animation and like**
  Future<void> _handleDoubleTapLike(VideoModel video) async {
    // Show heart animation
    _showHeartAnimation[video.id] ??= ValueNotifier<bool>(false);
    _showHeartAnimation[video.id]!.value = true;

    // Hide animation after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      _showHeartAnimation[video.id]?.value = false;
    });

    // **NEW: Force-show overlay (action buttons) for confirmation**
    _forceShowOverlayVN[video.id] ??= ValueNotifier<bool>(false);
    _forceShowOverlayVN[video.id]!.value = true;
    // Cancel any existing timer for this video
    _forceShowOverlayTimers[video.id]?.cancel();
    // Auto-hide overlay after 2 seconds
    _forceShowOverlayTimers[video.id] = Timer(const Duration(seconds: 2), () {
      _forceShowOverlayVN[video.id]?.value = false;
    });

    // If the video is already liked by the current user, only show animation
    // Check our specific notifier first for most up-to-date state
    final isLikedNotifier = _isLikedVN.putIfAbsent(
        video.id, () => ValueNotifier<bool>(video.isLiked));

    if (isLikedNotifier.value) {
      AppLogger.log(
        '🔴 DoubleTap Like: Video already liked by current user – showing animation only',
      );
      return;
    }

    // Handle the like
    await _handleLike(video);
  }

  /// **HANDLE LIKE: With API integration (Optimized - No SetState)**
  Future<void> _handleLike(VideoModel video) async {
    // Helper to get or create notifiers ensuring they are synced with model initially
    ValueNotifier<bool> getLikedNotifier() {
      return _isLikedVN.putIfAbsent(
          video.id, () => ValueNotifier<bool>(video.isLiked));
    }

    ValueNotifier<int> getCountNotifier() {
      return _likeCountVN.putIfAbsent(
          video.id, () => ValueNotifier<int>(video.likes));
    }

    AppLogger.log('🔴 ========== LIKE BUTTON CLICKED (Optimized) ==========');
    AppLogger.log('🔴 Video ID: ${video.id}');

    // Guard against multiple rapid taps
    if (_likeInProgress[video.id] == true) {
      return;
    }

    // Authenticate before the optimistic update so guest taps never flash a
    // false like count while the sign-in UI is open.
    final authController = ref.read(googleSignInProvider);
    if (!authController.isSignedIn) {
      final signedIn = await _triggerSignInOptions();
      if (!signedIn) return;
    }

    // **FIX: Proceed to VideoService even if local _currentUserId is null**
    // If we have a token, VideoService will handle it. We only prompt sign-in
    // if we are sure there's no user session at all.
    if (_currentUserId == null) {
      AppLogger.log(
          '🔍 _handleLike: Local _currentUserId is null, relying on service-level token check.');
    }

    // Get notifiers
    final likedVN = getLikedNotifier();
    final countVN = getCountNotifier();

    // **OPTIMISTIC UPDATE: Update Notifiers immediately (No setState)**
    final wasLiked = likedVN.value;
    final originalLikes = countVN.value;

    // 1. Update Notifiers (Drives UI)
    likedVN.value = !wasLiked;
    countVN.value = wasLiked
        ? (originalLikes - 1).clamp(0, double.infinity).toInt()
        : originalLikes + 1;

    // 2. Update Model (Keeps data consistent if we scroll away)
    // We update isLiked field instead of manual likedBy mutation
    video.isLiked = !wasLiked;
    video.likes = countVN.value;

    AppLogger.log(
        '🔴 Like Handler: Optimistic Update - Liked: ${likedVN.value}, Count: ${countVN.value}');

    try {
      _likeInProgress[video.id] = true;

      // **SYNC WITH BACKEND**
      VideoModel updatedVideo = await _videoService.toggleLike(video.id);

      AppLogger.log('✅ Successfully toggled like for video ${video.id}');

      // **CRITICAL: Sync Notifiers & Model with Backend Response**
      // We don't replace the object in the list (which requires setState or complex listeners),
      // we just update its properties and the notifiers.

      // Update Model properties
      video.likes = updatedVideo.likes;
      // Use the injected isLiked from backend
      video.isLiked = updatedVideo.isLiked;

      // Update Notifiers with authoritative backend values
      countVN.value = updatedVideo.likes;
      likedVN.value = updatedVideo.isLiked;
    } catch (e) {
      AppLogger.log('❌ Error handling like: $e');

      // **REVERT: If backend fails, revert optimistic update**
      AppLogger.log(
          '🔴 Like Handler: Reverting optimistic update due to error');

      // Revert Notifiers
      likedVN.value = wasLiked;
      countVN.value = originalLikes;

      // Revert Model
      video.isLiked = wasLiked;
      video.likes = originalLikes;

      // Show error
      String errorMessage = 'Failed to like video';
      final errorString = e.toString();
      if (errorString.contains('sign in') ||
          errorString.contains('authenticated')) {
        errorMessage = 'Please sign in again to like videos';
        Future.delayed(
            const Duration(milliseconds: 500), _triggerSignInOptions);
      }
      _showSnackBar(errorMessage, isError: true);
    } finally {
      _likeInProgress[video.id] = false;
    }
  }

  /// **NEW: Trigger Google Sign-In directly (shows account picker popup)**
  Future<bool> _triggerSignInOptions() async {
    if (_isGoogleSignInInProgress) return false;

    try {
      final authController = ref.read(googleSignInProvider);
      if (authController.isSignedIn) return true;
      if (mounted) {
        setState(() => _isGoogleSignInInProgress = true);
        VayuSnackBar.showInfo(
          context,
          'Opening Google sign-in...',
          duration: const Duration(seconds: 2),
        );
      }

      final user = await authController.signIn();
      if (user != null) {
        AppLogger.log('✅ Sign-in successful after like/comment action');
        final userId =
            (user['googleId'] ?? user['id'] ?? user['_id'])?.toString();
        if (userId != null && userId.isNotEmpty && mounted) {
          setState(() => _currentUserId = userId);
        }
        if (mounted) {
          VayuSnackBar.showSuccess(
            context,
            'Signed in successfully',
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        AppLogger.log('ℹ️ User cancelled sign-in');
      }
      if (user == null && mounted) {
        VayuSnackBar.showInfo(
          context,
          'Google sign-in was cancelled',
          duration: const Duration(seconds: 2),
        );
      }
      return user != null;
    } catch (e) {
      AppLogger.log('❌ Error triggering sign-in: $e');
      _showSnackBar('Failed to sign in. Please try again.', isError: true);
      return false;
    } finally {
      if (mounted) {
        setState(() => _isGoogleSignInInProgress = false);
      }
    }
  }

  @override
  void didPushNext() {
    _playbackCoordinator.setRouteActive(_playbackSession, false);
    _pauseCurrentVideo();
  }

  @override
  void didPopNext() {
    _playbackCoordinator.setRouteActive(_playbackSession, true);
    _tryAutoplayCurrent();
  }

  /// This route was popped. Its widget is not disposed until the transition
  /// finishes, so without giving the slot up here it stays the top-most
  /// eligible surface for the length of the animation and keeps the screen
  /// underneath silent.
  @override
  void didPop() {
    _playbackCoordinator.setRouteActive(_playbackSession, false);
    _pauseCurrentVideo();
  }

  /// **HANDLE SHARE: Same timestamp sheet as the Vayu long-form player**
  Future<void> _handleShare(VideoModel video) async {
    try {
      final index = _videos.indexWhere((v) => v.id == video.id);
      ShareOptionsSheet.show(
        context,
        video: video,
        controller: index != -1 ? _getController(index) : null,
      );
    } catch (e) {
      AppLogger.log('❌ Error showing share options: $e');
      _showSnackBar('Failed to share video', isError: true);
    }
  }

  /// **HANDLE VISIT NOW: Open link in browser**
  Future<void> _handleVisitNow(VideoModel video) async {
    if (video.link?.isNotEmpty != true) return;
    await _launchExternalUrl(video.link!);
  }

  /// **LAUNCH EXTERNAL URL: Helper method for ads and video links**
  Future<void> _launchExternalUrl(String urlString) async {
    try {
      // Enrich with UTM params so website owners can attribute traffic to vayug
      final enrichedUrl = UrlUtils.enrichUrl(
        urlString,
        medium: 'video_feed',
        campaign: 'creator_visit',
      );
      final Uri? uri = Uri.tryParse(enrichedUrl);
      if (uri != null) {
        // Use url_launcher to open the link
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        } else {
          _showSnackBar('Could not open link', isError: true);
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error opening link: $e');
      _showSnackBar('Failed to open link', isError: true);
    }
  }

  /// **SHOW SNACKBAR: Helper method**
  void _showSnackBar(String message, {bool isError = false}) {
    if (isError) {
      VayuSnackBar.showError(context, message);
    } else {
      VayuSnackBar.showSuccess(context, message);
    }
  }

  /// **HANDLE FOLLOW/UNFOLLOW: With API integration**
  Future<void> _handleFollow(VideoModel video) async {
    if (_currentUserId == null) return;
    if (video.uploader.id == _currentUserId) return;

    try {
      final userProviderRef = ref.read(userProvider);
      final trimmedUploaderId = video.uploader.id.trim();

      if (trimmedUploaderId.isEmpty || trimmedUploaderId == 'unknown') {
        AppLogger.log('⚠️ Cannot follow: Invalid uploader ID');
        return;
      }

      // **SYNC: toggleFollow handles both optimistic update and API call**
      final success = await userProviderRef.toggleFollow(trimmedUploaderId);

      if (!success) {
        AppLogger.log('❌ Failed to toggle follow for $trimmedUploaderId');
      }
    } catch (e) {
      AppLogger.log('❌ Error in _handleFollow: $e');
    }
  }

  /// **NAVIGATE TO CREATOR PROFILE: Navigate to user profile screen**
  void _navigateToCreatorProfile(VideoModel video) {
    final candidateIds = <String>[
      if (video.uploader.googleId != null) video.uploader.googleId!.trim(),
      if (video.uploader.id.isNotEmpty) video.uploader.id.trim(),
    ]
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id.toLowerCase() != 'unknown')
        .toList();

    AppLogger.log('🔗 Creator profile candidate IDs: $candidateIds');

    final targetUserId = candidateIds.isNotEmpty ? candidateIds.first : '';

    if (targetUserId.isEmpty) {
      _showSnackBar('User profile not available', isError: true);
      return;
    }

    AppLogger.log('🔗 Navigating to creator profile: $targetUserId');
    _pauseVideosForProfileNavigation();

    // Preload profile data before navigation (non-blocking) for instant load
    ProfilePreloader().preloadProfileOnTap(targetUserId);

    // Navigate to profile screen
    Navigator.push(
      context,
      MaterialPageRoute(
        settings:
            RouteSettings(name: 'profile', arguments: {'userId': targetUserId}),
        builder: (context) => ProfileScreen(userId: targetUserId),
      ),
    ).catchError((error) {
      AppLogger.log('❌ Error navigating to profile: $error');
      _showSnackBar('Failed to open profile', isError: true);
      return null; // Return null to satisfy the return type
    });
  }

  /// **TEST API CONNECTION: Test if the API is reachable**
  Future<void> _testApiConnection() async {
    try {
      AppLogger.log('🔍 VideoFeedAdvanced: Testing API connection...');

      // Show loading state
      if (mounted) {
        VayuSnackBar.showInfo(
          context,
          'Testing connection...',
          duration: const Duration(seconds: 2),
        );
      }

      // Try to make a simple API call
      await _videoService.getVideos(page: 1, limit: 1);

      if (mounted) {
        VayuSnackBar.showSuccess(context, 'Connection successful!',
            duration: const Duration(seconds: 2));

        // Clear error and try to refresh
        setState(() {
          _errorMessage = null;
        });
        await refreshVideos();
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: API connection test failed: $e');

      if (mounted) {
        VayuSnackBar.showError(
          context,
          'Connection failed: ${_getUserFriendlyErrorMessage(e)}',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;

    if (isSignedIn != _wasSignedIn) {
      _wasSignedIn = isSignedIn;
      if (isSignedIn) {
        _pendingAutoplayAfterLogin = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scheduleAutoplayAfterLogin();
          }
        });
      } else {
        _pendingAutoplayAfterLogin = false;
      }
    }

    // **FIXED: Listen to auth state changes and update user ID**
    // **FIX: Prioritize googleId over id to match backend likedBy array**
    if (isSignedIn && authController.userData != null) {
      final userId = authController.userData!['googleId'] ??
          authController.userData!['id'];
      if (userId != null && _currentUserId != userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentUserId = userId;
            });
            AppLogger.log(
              '✅ VideoFeedAdvanced: User ID synced from auth: $userId',
            );
          }
        });
      }
    } else if (!isSignedIn && _currentUserId != null) {
      // User signed out - clear user ID
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentUserId = null;
          });
          AppLogger.log(
            '✅ VideoFeedAdvanced: User ID cleared (signed out)',
          );
        }
      });
    }

    final mainController = ref.watch(mainControllerProvider);
    // Visibility means "is MY tab on screen", not "is tab 0 on screen". A
    // player pushed from the Profile tab used to be told it was hidden the
    // moment it started, which paused it a few frames after the first play.
    final feedTabIndex = _feedTabIndex;
    final isOwnTabActive =
        feedTabIndex == null || mainController.currentIndex == feedTabIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleVisibilityChange(isOwnTabActive);
    });

    // #region agent log
    _debugLog(
        'video_feed_advanced.dart:2207',
        'UI build condition check',
        {
          'isLoading': _isLoading,
          'errorMessage': _errorMessage,
          'videosLength': _videos.length,
          'willShowEmpty':
              !_isLoading && _errorMessage == null && _videos.isEmpty,
        },
        'E');
    // #endregion

    // **ACCELERATED BOOT: Determine if we should show the initial skeleton**
    // We show it if:
    // 1. We are still fetching the initial batch of videos
    // 2. OR we have videos, but the first one isn't ready to play yet (No Partial Loading)
    Widget buildBody() {
      if (_isLoading && _videos.isEmpty) {
        return const VideoFeedSkeleton();
      }

      if (_videos.isEmpty && _errorMessage != null) {
        return RefreshIndicator(
          onRefresh: refreshVideos,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              child: _buildErrorState(),
            ),
          ),
        );
      }

      if (_videos.isEmpty) {
        return RefreshIndicator(
          onRefresh: refreshVideos,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              child: _buildEmptyState(),
            ),
          ),
        );
      }

      // We have videos! Now handle the "No Partial Loading" transition.
      return _buildVideoFeed();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          buildBody(),
          // **OFFLINE INDICATOR: Show when no internet connection**
          _buildOfflineIndicator(),
          if (_isGoogleSignInInProgress) _buildGoogleSignInProgressOverlay(),
        ],
      ),
    );
  }

  Widget _buildGoogleSignInProgressOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.42),
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 248,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171717).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Opening Google sign-in',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose your account to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    // Releasing the session drops this feed's pins and hands the screen back to
    // the surface underneath, which the coordinator then reactivates.
    _playbackCoordinator.release(_playbackSession);

    if (!_openedFromProfile) {
      _videoControllerManager.unregisterOnRoutePopped();
    }

    WidgetsBinding.instance.removeObserver(this);

    // **2. CANCEL ALL SUBSCRIPTIONS & TIMERS IMMEDIATELY**
    _pageChangeDebounceTimer?.cancel();
    _pageChangeTimer?.cancel();
    _preloadTimer?.cancel();
    _preloadDebounceTimer?.cancel();
    _adRefreshSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _bannerAdRetryTimer?.cancel();
    _poolDisposalSubscription?.cancel();
    _longPressAdAutoHideTimer?.cancel();

    for (var s in _dubbingSubscriptions.values) {
      s.cancel();
    }
    for (var timer in _preloadDebounceTimers.values) {
      timer.cancel();
    }
    for (var timer in _bufferingTimers.values) {
      timer.cancel();
    }
    for (var timer in _forceShowOverlayTimers.values) {
      timer.cancel();
    }

    // **3. STOP & DISPOSE TRACKERS & MANAGERS**
    _viewTracker.dispose();
    _profilePreloader.dispose();
    _videoControllerManager.dispose();
    AppLogger.log('🎯 VideoFeedAdvanced: Disposed Trackers and Managers');

    // **4. SAVE/STOP VIDEO CONTROLLERS**
    final sharedPool = SharedVideoControllerPool();
    final bool openedFromProfile = _openedFromProfile;
    int savedControllers = 0;

    // This screen is going away, so nothing here is "the video being watched".
    // Leaving a stale pin would make that controller un-evictable forever.
    // Only this session's pin is dropped — another surface's stays protected.
    sharedPool.pinVideo(null, sessionId: _playbackSession.id);

    // Create a copy of the pool to avoid modification during iteration
    final controllersToDispose =
        Map<String, VideoPlayerController>.from(_controllerPool);

    controllersToDispose.forEach((videoId, controller) {
      try {
        // Remove listeners to avoid memory leaks. Routing through the pool
        // detaches ALL registered listeners, not just these two — the error
        // and quiz listeners used to survive here and keep ticking.
        sharedPool.removeListener(videoId);

        if (openedFromProfile) {
          // PROFILE FLOW: Fully dispose controllers to free decoder resources.
          // **SINGLE OWNER: hand it to the pool rather than removing the pool's
          // record and disposing behind its back.**
          if (sharedPool.isPooled(videoId)) {
            sharedPool.disposeController(videoId);
          } else {
            try {
              if (controller.value.isInitialized) {
                if (controller.value.isPlaying) {
                  controller.pause();
                }
                controller.setVolume(0.0);
              }
              controller.dispose();
            } catch (e) {
              AppLogger.log(
                  '⚠️ VideoFeedAdvanced: Error disposing unpooled controller: $e');
            }
          }
        } else {
          // TAB FLOW: Preserve controller in shared pool for quick resume
          if (controller.value.isInitialized && controller.value.isPlaying) {
            controller.pause();
            _controllerStates[videoId] = false;
          }
          sharedPool.addController(videoId, controller, skipDisposeOld: true);
          savedControllers++;
        }
      } catch (e) {
        AppLogger.log('⚠️ Error saving controller for video $videoId: $e');
        try {
          controller.dispose();
        } catch (_) {}
      }
    });

    AppLogger.log(
        '💾 VideoFeedAdvanced: Saved $savedControllers controllers to shared pool');

    // Manage memory for standard flow
    if (savedControllers > 2) {
      sharedPool.disposeControllersForMemoryManagement();
    }

    // **5. CLEAR LOCAL MAPS**
    _controllerPool.clear();
    _controllerStates.clear();
    _isBuffering.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();
    _errorListeners.clear();
    _quizListeners.clear();
    _wasPlayingBeforeNavigation.clear();
    _loadingVideos.clear();
    _initializingVideos.clear();
    _preloadRetryCount.clear();
    _preloadedVideos.clear();

    // **6. DISPOSE VALUENOTIFIERS & UI CONTROLLERS**
    for (final notifier in _showHeartAnimation.values) {
      notifier.dispose();
    }
    _showHeartAnimation.clear();

    for (final notifier in _currentHorizontalPage.values) {
      notifier.dispose();
    }
    _currentHorizontalPage.clear();

    for (final notifier in _isBufferingVN.values) {
      notifier.dispose();
    }
    _isBufferingVN.clear();

    for (final notifier in _userPausedVN.values) {
      notifier.dispose();
    }
    _userPausedVN.clear();

    for (final notifier in _forceShowOverlayVN.values) {
      notifier.dispose();
    }
    _forceShowOverlayVN.clear();

    _showLongPressAdOverlayVN.dispose();

    for (final notifier in _showPauseAdOverlayPerVideoVN.values) {
      notifier.dispose();
    }
    _showPauseAdOverlayPerVideoVN.clear();

    // DISPOSE PAGE CONTROLLERS LAST
    _pageController.dispose();

    for (final controller in _horizontalControllers.values) {
      controller.dispose();
    }
    _horizontalControllers.clear();

    _disableWakelock();
    super.dispose();
  }

  /// **GET DETAILED CACHE INFO: Comprehensive cache information**
  Map<String, dynamic> _getDetailedCacheInfo() {
    final cacheStats = {};

    return {
      'videoControllerPool': {
        'totalControllers': _controllerPool.length,
        'controllerKeys': _controllerPool.keys.toList(),
        'controllerStates': _controllerStates,
        'preloadedVideos': _preloadedVideos.toList(),
        'loadingVideos': _loadingVideos.toList(),
      },
      'cacheStatistics': {
        'cacheHits': _cacheHits,
        'cacheMisses': _cacheMisses,
        'preloadHits': _preloadHits,
        'totalRequests': _totalRequests,
        'hitRate': _totalRequests > 0
            ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
            : '0.00',
      },
      'smartCacheManager': cacheStats,
      'videoLoadingStatus': {
        'currentIndex': _currentIndex,
        'totalVideos': _videos.length,
        'maxPoolSize': _maxPoolSize,
        'isLoading': _isLoading,
        'isScreenVisible': _isScreenVisible,
      },
      'memoryUsage': {
        'controllerPoolSize': _controllerPool.length,
        'preloadedVideosCount': _preloadedVideos.length,
        'loadingVideosCount': _loadingVideos.length,
      },
    };
  }

  /// **PRINT DETAILED CACHE INFO: For debugging purposes**
  void _printDetailedCacheInfo() {
    final info = _getDetailedCacheInfo();

    final poolInfo = info['videoControllerPool'] as Map<String, dynamic>;
    poolInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('📈 Cache Statistics:');
    final statsInfo = info['cacheStatistics'] as Map<String, dynamic>;
    statsInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🧠 Smart Cache Manager:');
    final smartCacheInfo = info['smartCacheManager'] as Map<String, dynamic>;
    smartCacheInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🎥 Video Loading Status:');
    final loadingInfo = info['videoLoadingStatus'] as Map<String, dynamic>;
    loadingInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('💾 Memory Usage:');
    final memoryInfo = info['memoryUsage'] as Map<String, dynamic>;
    memoryInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });
  }

  /// **MANUAL CACHE STATUS CHECK: Call this method to check cache status**
  void checkCacheStatus() {
    AppLogger.log('🔍 Manual Cache Status Check Triggered');
    _printDetailedCacheInfo();
  }

  /// **GET CACHE SUMMARY: Quick cache overview**
  Map<String, dynamic> getCacheSummary() {
    return {
      'totalVideos': _videos.length,
      'preloadedVideos': _preloadedVideos.length,
      'loadingVideos': _loadingVideos.length,
      'controllerPoolSize': _controllerPool.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': _totalRequests > 0
          ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
          : '0.00',
      'currentIndex': _currentIndex,
      'isLoading': _isLoading,
    };
  }

  void _onAudioDubTap(VideoModel video) async {
    final videoId = video.id;
    final resultVN = _getOrCreateNotifier<DubbingResult>(
      _dubbingResultsVN,
      videoId,
      const DubbingResult(status: DubbingStatus.idle),
    );

    final currentResult = resultVN.value;
    if (!currentResult.isDone && currentResult.status != DubbingStatus.idle) {
      final bool? cancel = await VayuBottomSheet.show<bool>(
        context: context,
        title: 'Dubbing in progress',
        icon: Icons.multitrack_audio_rounded,
        iconColor: AppColors.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_audioLanguageTitle(_dubbingTargetLanguage[videoId] ?? currentResult.language ?? 'hindi')} audio is being prepared.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppTypography.fontSizeSM,
                height: 1.35,
              ),
            ),
            AppSpacing.vSpace16,
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: currentResult.progress > 0
                    ? (currentResult.progress / 100).clamp(0.0, 1.0)
                    : null,
                minHeight: 4,
                backgroundColor: AppColors.backgroundSecondary,
                color: AppColors.primary,
              ),
            ),
            AppSpacing.vSpace12,
            Text(
              currentResult.statusLabel,
              style: TextStyle(
                color: AppColors.white,
                fontSize: AppTypography.fontSizeSM,
                fontWeight: AppTypography.weightSemiBold,
              ),
            ),
            AppSpacing.vSpace24,
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Keep Dubbing',
                    onPressed: () => Navigator.pop(context, false),
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                  ),
                ),
                AppSpacing.hSpace12,
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(context, true),
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (cancel == true) {
        _dubbingService.cancelDubbing(video.id, video.videoUrl);
        _dubbingSubscriptions[videoId]?.cancel();
        _dubbingSubscriptions.remove(videoId);
        _dubbingTargetLanguage.remove(videoId);
        resultVN.value = const DubbingResult(status: DubbingStatus.idle);
        if (mounted) VayuSnackBar.showInfo(context, 'Dubbing cancelled.');
      }
      return;
    }

    _showAudioLanguageSelector(context, video);
  }

  void _startAudioDub(VideoModel video, String targetLang) {
    final videoId = video.id;
    final resultVN = _getOrCreateNotifier<DubbingResult>(
      _dubbingResultsVN,
      videoId,
      const DubbingResult(status: DubbingStatus.idle),
    );

    _dubbingTargetLanguage[videoId] = targetLang;
    VayuSnackBar.showInfo(
      context,
      'Preparing ${_audioLanguageTitle(targetLang)} audio...',
    );

    final sub = _dubbingService
        .dubVideo(video.id, video.videoUrl, targetLang: targetLang)
        .listen((result) {
      if (!mounted) return;
      resultVN.value = result;

      if (result.status == DubbingStatus.completed) {
        _dubbingTargetLanguage.remove(videoId);
        if (result.dubbedUrl != null) {
          final vIndex = _videos.indexWhere((v) => v.id == videoId);
          if (vIndex != -1) {
            final currentDubbedUrls =
                Map<String, String>.from(_videos[vIndex].dubbedUrls ?? {});
            final String lang = result.language ?? targetLang;
            currentDubbedUrls[lang] = result.dubbedUrl!;
            setState(() {
              _videos[vIndex] =
                  _videos[vIndex].copyWith(dubbedUrls: currentDubbedUrls);

              // NEW: Auto-play the dubbed video instantly and safely recreate the player
              // This prevents "No active player with ID" caused by FFmpeg memory spikes
              if (vIndex == _currentIndex && mounted) {
                _selectedAudioLanguage[videoId] = lang;

                // **CRASH-PROOF: Safely dispose and reset local pool state**
                if (_controllerPool.containsKey(videoId)) {
                  final ctrl = _controllerPool[videoId];
                  if (ctrl != null) {
                    // 1. Clear local state first to prevent UI from finding the old controller
                    _controllerPool.remove(videoId);
                    _controllerStates.remove(videoId);
                    _preloadedVideos.remove(videoId);
                    // 2. Use SharedPool for authoritative disposal (removes from shared maps + disposes)
                    SharedVideoControllerPool().disposeController(videoId);

                    AppLogger.log(
                        '🗑️ VideoFeed: Safely disposed old controller for $videoId during auto-swap');
                  }
                }

                // 3. Delay re-preload to next frame to allow "null controller" build to complete
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _preloadVideo(vIndex);
                  }
                });
              }
            });
          }
          VayuSnackBar.showSuccess(
            context,
            '${_audioLanguageTitle(targetLang)} audio is ready.',
          );
        }
      } else if (result.status == DubbingStatus.notSuitable) {
        _dubbingTargetLanguage.remove(videoId);
        VayuSnackBar.showInfo(
          context,
          'Audio cannot be dubbed: ${result.reason ?? "No vocal detected"}',
        );
      } else if (result.status == DubbingStatus.failed) {
        _dubbingTargetLanguage.remove(videoId);
        if (mounted && result.error?.contains('Cancelled') != true) {
          VayuSnackBar.showError(
            context,
            'Dubbing failed: ${result.error ?? "Unknown error"}',
          );
        }
      }
    });

    _dubbingSubscriptions[videoId] = sub;
  }

  void _showAudioLanguageSelector(BuildContext context, VideoModel video) {
    final hasEnglishDub = video.dubbedUrls?.containsKey('english') ?? false;
    final hasHindiDub = video.dubbedUrls?.containsKey('hindi') ?? false;
    final String detectedSource =
        hasEnglishDub ? 'Hindi' : (hasHindiDub ? 'English' : 'Original');

    VayuBottomSheet.show<void>(
      context: context,
      title: 'Listen in',
      icon: Icons.volume_up_rounded,
      iconColor: AppColors.primary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the audio language for this video.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypography.fontSizeSM,
              height: 1.35,
            ),
          ),
          AppSpacing.vSpace16,
          _buildAudioLanguageOption(
            context,
            video,
            '$detectedSource (Original)',
            'default',
            badge: 'Original',
            icon: Icons.graphic_eq_rounded,
          ),
          AppSpacing.vSpace8,
          _buildAudioLanguageOption(
            context,
            video,
            'English',
            'english',
            badge: hasEnglishDub ? 'Dubbed' : null,
            available: hasEnglishDub,
            icon: Icons.translate_rounded,
          ),
          AppSpacing.vSpace8,
          _buildAudioLanguageOption(
            context,
            video,
            'Hindi',
            'hindi',
            badge: hasHindiDub ? 'Dubbed' : null,
            available: hasHindiDub,
            icon: Icons.translate_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioLanguageOption(
    BuildContext context,
    VideoModel video,
    String title,
    String langCode, {
    String? badge,
    bool available = true,
    IconData icon = Icons.volume_up_rounded,
  }) {
    final String currentSelected =
        _selectedAudioLanguage[video.id] ?? 'default';
    final bool isSelected = currentSelected == langCode;
    final bool canStartDub = langCode != 'default' && !available;
    final String actionLabel = isSelected
        ? 'Playing now'
        : available
            ? 'Switch audio'
            : 'Dub audio';

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        if (canStartDub) {
          _startAudioDub(video, langCode);
        } else {
          _handleAudioLanguageSelection(video, langCode);
        }
      },
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.backgroundSecondary.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.white,
                size: 18,
              ),
            ),
            AppSpacing.hSpace12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: AppTypography.fontSizeBase,
                            fontWeight: isSelected
                                ? AppTypography.weightSemiBold
                                : AppTypography.weightMedium,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        AppSpacing.hSpace8,
                        _buildAudioBadge(badge),
                      ],
                    ],
                  ),
                  AppSpacing.vSpace4,
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: AppTypography.fontSizeXS,
                      fontWeight: AppTypography.weightMedium,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : canStartDub
                      ? Icons.auto_awesome_rounded
                      : Icons.chevron_right_rounded,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: AppTypography.fontSizeXS,
          fontWeight: AppTypography.weightSemiBold,
        ),
      ),
    );
  }

  String _audioLanguageTitle(String langCode) {
    switch (langCode) {
      case 'english':
        return 'English';
      case 'hindi':
        return 'Hindi';
      default:
        return 'Original';
    }
  }

  void _handleAudioLanguageSelection(VideoModel video, String langCode) {
    if (_selectedAudioLanguage[video.id] == langCode) return;

    final String videoId = video.id;
    AppLogger.log('🎙️ Yug Language Switch: [$videoId] -> $langCode');

    setState(() {
      _selectedAudioLanguage[videoId] = langCode;

      // **CRASH-PROOF: Safely dispose current controller and clear pools**
      if (_controllerPool.containsKey(videoId)) {
        final ctrl = _controllerPool[videoId];
        if (ctrl != null) {
          // 1. Clear local state FIRST (synchronous) so rebuild sees null controller
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
          _preloadedVideos.remove(videoId);

          // 2. Use SharedPool for safe disposal (manages listeners and avoids double-dispose)
          SharedVideoControllerPool().disposeController(videoId);

          AppLogger.log(
              '🗑️ VideoFeed: Disposed old controller for $videoId during manual language switch');
        }
      }

      // 3. Re-preload and play in NEXT frame after UI has cleared the old player
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _preloadVideo(index);
          }
        });
      }
    });
  }
}
