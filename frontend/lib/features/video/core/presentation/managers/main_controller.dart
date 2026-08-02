import 'package:flutter/material.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'dart:async';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  int? _pendingTabIndex;
  final List<String> _routes = ['/yug', '/vayu', '/upload', '/subscriptions', '/profile'];
  bool _isAppInForeground = true;
  bool _isMediaPickerActive = false;
  DateTime? _lastPickerReturnAt;

  // Persistence keys (Legacy - Persistence disabled per user request)
  // static const String _lastSubRouteKey = 'last_sub_route_tab_';
  // static const String _lastSubRouteArgsKey = 'last_sub_route_args_tab_';
  // static const String _lastVideoIndexKey = 'last_video_index_tab_';

  // **NAVIGATION VISIBILITY: Single state for bottom nav**
  bool _isBottomNavVisible = true;
  bool get isBottomNavVisible => _isBottomNavVisible;

  void setBottomNavVisibility(bool visible) {
    if (_isBottomNavVisible == visible) return;
    _isBottomNavVisible = visible;
    notifyListeners();
  }

  // **OBSERVER PATTERN: Support multiple video feeds in the stack**
  final List<VoidCallback> _pauseObservers = [];
  final List<VoidCallback> _resumeObservers = [];

  /// **NEW: Register a video feed observer**
  void registerVideoObserver({
    required VoidCallback onPause,
    required VoidCallback onResume,
  }) {
    if (!_pauseObservers.contains(onPause)) {
      _pauseObservers.add(onPause);
    }
    if (!_resumeObservers.contains(onResume)) {
      _resumeObservers.add(onResume);
    }
    AppLogger.log('🎬 MainController: Registered video observer (Total: ${_pauseObservers.length})');
  }

  /// **NEW: Unregister a video feed observer**
  void unregisterVideoObserver({
    required VoidCallback onPause,
    required VoidCallback onResume,
  }) {
    _pauseObservers.remove(onPause);
    _resumeObservers.remove(onResume);
    AppLogger.log('🎬 MainController: Unregistered video observer (Remaining: ${_pauseObservers.length})');
  }

  // Deprecated single callbacks - keeping for compatibility during migration
  VoidCallback? _pauseVideosCallback;
  VoidCallback? _resumeVideosCallback;

  /// **LEGACY: Register video pause callback (migrating to registerVideoObserver)**
  void registerVideoPauseCallback(VoidCallback callback) {
    _pauseVideosCallback = callback;
    if (!_pauseObservers.contains(callback)) {
      _pauseObservers.add(callback);
    }
  }

  /// **LEGACY: Register video resume callback (migrating to registerVideoObserver)**
  void registerVideoResumeCallback(VoidCallback callback) {
    _resumeVideosCallback = callback;
    if (!_resumeObservers.contains(callback)) {
      _resumeObservers.add(callback);
    }
  }

  int get currentIndex => _currentIndex;
  /// The tab that should be considered active by media immediately, even while
  /// the visible tab transition is waiting to complete.
  int get playbackActiveTabIndex => _pendingTabIndex ?? _currentIndex;
  String get currentRoute => _routes[_currentIndex];
  bool get isAppInForeground => _isAppInForeground;
  bool get isMediaPickerActive => _isMediaPickerActive;

  /// Change the current index and handle video control
  void changeIndex(int index) {
    if (_currentIndex == index && _pendingTabIndex == null) return;
    if (_pendingTabIndex == index) return;

    _pendingTabIndex = index;

    // Hand ownership to the new tab BEFORE any pause observer or preload runs.
    // A player in the tab being left keeps `routeActive == true` (a tab switch
    // is not a route pop), so without this it would re-claim the playback slot
    // and pause the feed the user just switched to.
    PlaybackCoordinator().setActiveTab(index);

    _handleIndexChangeFallback(index);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_pendingTabIndex != index) return;
      // Update the current index
      _currentIndex = index;
      _pendingTabIndex = null;

      // Persistently saving tab state is now disabled per user request
      notifyListeners();
    });
  }

  /// **NEW: Fallback method for when VideoManager is not available**
  void _handleIndexChangeFallback(int index) {
    // ALWAYS pause videos when switching tabs to prevent audio leak from Yug, Vayu, or Profile
    // IMMEDIATE video pause for ALL observers
    for (final callback in _pauseObservers) {
      try {
        callback();
      } catch (e) {
        AppLogger.log('⚠️ MainController: Error in pause observer: $e');
      }
    }
    _pauseVideosCallback?.call();

    // SINGLE safety delay to ensure videos are paused after state transition
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_currentIndex != index) {
        for (final callback in _pauseObservers) {
          try {
            callback();
          } catch (_) {}
        }
        _pauseVideosCallback?.call();
      }
    });

    // If we're entering the video tab (Yug), resume videos
    if (index == 0 && isAppInForeground) {
      // Notify all observers to resume
      for (final callback in _resumeObservers) {
        try {
          callback();
        } catch (_) {}
      }
      _resumeVideosCallback?.call();
    }
  }

  void navigateToProfile() {
    _currentIndex = 4; // Profile index
    PlaybackCoordinator().setActiveTab(_currentIndex);
    notifyListeners();
  }

  /// Mark media picker active/inactive and record return time
  void setMediaPickerActive(bool active) {
    _isMediaPickerActive = active;
    if (!active) {
      _lastPickerReturnAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Cooldown check after picker returns to avoid autoplay leak
  bool get recentlyReturnedFromPicker {
    if (_lastPickerReturnAt == null) return false;
    return DateTime.now().difference(_lastPickerReturnAt!).inMilliseconds < 1200;
  }

  void setAppInForeground(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      notifyListeners();
    }
  }

  /// Check if the current screen is the video screen
  bool get isVideoScreen => _currentIndex == 0;

  /// Check if videos should be playing based on current state
  bool get shouldPlayVideos => _isAppInForeground && isVideoScreen;

  /// **SIMPLIFIED: Video tracking info (VideoManager removed)**
  Map<String, dynamic>? getVideoTrackingInfo() {
    return null; // VideoManager was removed
  }

  /// **SIMPLIFIED: Current visible video index (VideoManager removed)**
  int get currentVisibleVideoIndex {
    return 0; // VideoManager was removed
  }

  /// Register callback to pause videos (Legacy)
  void registerPauseVideosCallback(VoidCallback callback) {
    registerVideoPauseCallback(callback);
  }

  /// Register callback to resume videos (Legacy)
  void registerResumeVideosCallback(VoidCallback callback) {
    registerVideoResumeCallback(callback);
  }

  /// Unregister callbacks
  void unregisterCallbacks() {
    _pauseVideosCallback = null;
    _resumeVideosCallback = null;
    // Note: This doesn't clear the List observers to prevent accidental clearing
    // of background observers when a foreground one disposes.
  }

  /// Force pause all videos (called from external sources)
  void forcePauseVideos() {
    AppLogger.log('🔇 MainController: forcePauseVideos() triggered for ${_pauseObservers.length} observers');
    try {
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();
      
      // ALSO pause VideoControllerManager (used by legacy components or direct feed)
      VideoControllerManager().forcePauseAllVideosSync();
    } catch (e) {
      // Ignore errors during pause
    }

    // Notify ALL registered observers
    for (final callback in _pauseObservers) {
      try {
        callback();
      } catch (e) {
        AppLogger.log('⚠️ MainController: Error calling pause observer: $e');
      }
    }
    
    _pauseVideosCallback?.call();
  }

  /// Resume videos (called when app comes back to foreground)
  void resumeVideos() {
    for (final callback in _resumeObservers) {
      try {
        callback();
      } catch (_) {}
    }
    _resumeVideosCallback?.call();
  }

  /// Check if videos should be paused based on current state
  bool get shouldPauseVideos => !isVideoScreen || !isAppInForeground;

  /// **NEW: Handle back button press with proper navigation lifecycle**
  /// Returns true if app should exit, false if navigation should continue
  bool handleBackPress() {
    // If we're not on the home tab (index 0), navigate back to home tab
    if (_currentIndex != 0) {
      changeIndex(0);
      return false; // Don't exit the app
    }

    return true; // Exit the app
  }

  /// **NEW: Check if we're on the home tab (where app can exit)**
  bool get isOnHomeTab => _currentIndex == 0;

  /// Emergency stop all videos (for critical situations)
  void emergencyStopVideos() {
    _pauseVideosCallback?.call();

    // Multiple safety calls to ensure videos are stopped
    Future.delayed(const Duration(milliseconds: 50), () {
      _pauseVideosCallback?.call();
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      _pauseVideosCallback?.call();
    });
  }

  /// **NEW: Handle app backgrounding with immediate pause**
  void handleAppBackgrounded() {
    _isAppInForeground = false;
    forcePauseVideos();
    notifyListeners();
  }

  /// **NEW: Handle app foregrounding with delayed resume**
  void handleAppForegrounded() {
    _isAppInForeground = true;
    notifyListeners();

    // Only resume if on video tab
    if (isVideoScreen) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isAppInForeground && isVideoScreen) {
          resumeVideos();
        }
      });
    }
  }

  /// **SIMPLIFIED: Get comprehensive video state info (VideoManager removed)**
  Map<String, dynamic> getComprehensiveVideoState() {
    return <String, dynamic>{
      'currentIndex': _currentIndex,
      'isVideoScreen': isVideoScreen,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'shouldPauseVideos': shouldPauseVideos,
      'hasVideoManager': false, // VideoManager was removed
    };
  }

  /// **FIXED: Centralized logout method to clear all state**
  Future<void> performLogout({bool resetIndex = true}) async {
    try {
      // **FIXED: Reset main controller state**
      if (resetIndex) {
        _currentIndex = 0;
        PlaybackCoordinator().setActiveTab(_currentIndex);
      }
      _isAppInForeground = true;
      _pauseVideosCallback = null;
      _resumeVideosCallback = null;

      notifyListeners();
    } catch (e) {
      AppLogger.log('Error during logout state clear: $e');
    }
  }

  /// **RESTORED: Always return home tab (0) on app start**
  Future<int> restoreLastTabIndex() async {
    _currentIndex = 0;
    // Also seeds the coordinator's active tab on cold start, so tab ownership
    // is accurate before the user's first tab switch.
    PlaybackCoordinator().setActiveTab(_currentIndex);
    return 0;
  }

  /// **NAVIGATION PERSISTENCE: Disabled per user request**
  Future<void> updateCurrentVideoIndex(int videoIndex, {int? tabIndex}) async {
    // Disabled
  }

  Future<int> getLastViewedVideoIndex(int tabIndex) async {
    return 0; // Always start videos at the beginning
  }

  Future<void> persistSubRoute(int tabIndex, String routeName, {Map<String, String>? args}) async {
    // Disabled
  }

  Future<void> clearSubRoute(int tabIndex) async {
    // Disabled
  }

  Future<Map<String, dynamic>?> getPersistedSubRoute(int tabIndex) async {
    return null; // Never restore sub-routes
  }

  /// **NEW: Save tab index when app goes to background**
  Future<void> saveStateForBackground() async {
    // Disabled
  }

  /// **NEW: Public method to save current tab index (can be called from anywhere)**
  Future<void> saveCurrentTabIndex() async {
    // Disabled
  }

  /// **NEW: Optimized state refresh and pre-fetch after account switch**
  Future<void> refreshAppStateAfterSwitch(WidgetRef ref) async {
    try {
      AppLogger.log('🚀 MainController: Starting parallel state refresh and pre-fetch...');
      
      // 1. Refresh all state providers (clears stale data)
      await LogoutService.refreshAllState(ref);

      // 2. Parallel pre-fetch for immediate UI readiness
      unawaited(Future.wait<void>([
        ref.read(profileStateManagerProvider)
            .loadUserData(null, forceRefresh: true, silent: true),
        ref.read(videoProvider).refreshVideos(),
      ]).then((_) {
        AppLogger.log('✅ MainController: Parallel pre-fetch completed');
      }).catchError((e) {
        AppLogger.log('⚠️ MainController: Pre-fetch encounterd errors: $e');
      }));

      AppLogger.log('✅ MainController: State refresh initiated');
    } catch (e) {
      AppLogger.log('❌ MainController: Error during state refresh: $e');
    }
  }
}
