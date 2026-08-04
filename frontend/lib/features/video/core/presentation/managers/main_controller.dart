import 'package:flutter/material.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'dart:async';
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

  // Video pause/resume observers used to live here as an app-wide broadcast:
  // every registered feed heard every tab switch, including feeds sitting in a
  // background tab that `IndexedStack` keeps mounted. Those feeds then paused
  // whatever was actually on screen. Playback ownership now belongs to
  // `PlaybackCoordinator`, which notifies exactly one surface — screens pass
  // `onActivate`/`onDeactivate` to `PlaybackCoordinator.register` instead.

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

    // Hand ownership to the new tab BEFORE any preload runs. A player in the
    // tab being left keeps `routeActive == true` (a tab switch is not a route
    // pop), so without this it would re-claim the playback slot and pause the
    // feed the user just switched to.
    //
    // This single call both pauses the tab being left and resumes the surface
    // in the tab being entered: the coordinator pauses every session whose tab
    // went away, then activates the one that is now on screen. There is no
    // longer a broadcast that a background feed can answer.
    PlaybackCoordinator().setActiveTab(index);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_pendingTabIndex != index) return;
      // Update the current index
      _currentIndex = index;
      _pendingTabIndex = null;

      // Persistently saving tab state is now disabled per user request
      notifyListeners();
    });
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

  /// Silence every video surface, e.g. before navigating somewhere that is not
  /// a video. Ownership is untouched, so the surface resumes when it is next
  /// activated.
  void forcePauseVideos() {
    AppLogger.log('🔇 MainController: forcePauseVideos()');
    PlaybackCoordinator().pauseAll();
  }

  /// Resume videos (called when app comes back to foreground).
  ///
  /// Resuming is the coordinator's decision: it activates the one surface that
  /// is on screen. Asking every feed to resume is what used to let a
  /// background player take the audio.
  void resumeVideos() {
    PlaybackCoordinator().setAppLifecycle(true);
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
    PlaybackCoordinator().pauseAll();
  }

  /// **NEW: Handle app backgrounding with immediate pause**
  void handleAppBackgrounded() {
    _isAppInForeground = false;
    // Order matters: marking the app backgrounded makes every session
    // ineligible, so nothing can re-claim playback behind the sweep.
    PlaybackCoordinator().setAppLifecycle(false);
    PlaybackCoordinator().pauseAll();
    notifyListeners();
  }

  /// **NEW: Handle app foregrounding**
  void handleAppForegrounded() {
    _isAppInForeground = true;
    notifyListeners();
    // Which surface resumes is the coordinator's call — restricting this to
    // tab 0 left a Vayu or profile player silent after every task switch.
    PlaybackCoordinator().setAppLifecycle(true);
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
