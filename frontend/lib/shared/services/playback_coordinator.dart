import 'dart:async';

import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Coordinates playback ownership across every video surface in the app.
///
/// A bottom-navigation tab is not a route. Dedicated players opened from a
/// profile or a deep link therefore use route ownership, while feed screens
/// can additionally update their visibility state.
class PlaybackSession {
  PlaybackSession._(this.id, this.source);

  final int id;
  final String source;

  /// Bottom-navigation tab this surface lives in, when it lives in one.
  ///
  /// A tab switch is not a route push, so `routeActive` alone cannot tell a
  /// dedicated player that it left the screen. Sessions that never bind a tab
  /// keep `tabIndex == null` and are treated as always tab-visible.
  int? tabIndex;

  bool routeActive = true;
  bool tabActive = true;
  bool appForeground = true;
  bool userPaused = false;
  bool released = false;
}

class PlaybackCoordinator {
  PlaybackCoordinator._() {
    SharedVideoControllerPool().setPlaybackGuard(_allowPooledControllerPlay);
    VideoControllerManager().setPlaybackGuard(_allowPooledControllerPlay);
  }

  static final PlaybackCoordinator _instance = PlaybackCoordinator._();
  factory PlaybackCoordinator() => _instance;

  final Map<int, PlaybackSession> _sessions = <int, PlaybackSession>{};
  final Map<int, VideoPlayerController> _controllers = <int, VideoPlayerController>{};
  int _nextSessionId = 0;
  int? _ownerId;
  bool _appForeground = true;
  int? _activeTabIndex;

  PlaybackSession register({required String source, int? tabIndex}) {
    final session = PlaybackSession._(++_nextSessionId, source)
      ..appForeground = _appForeground
      ..tabIndex = tabIndex
      ..tabActive = _isTabVisible(tabIndex);
    _sessions[session.id] = session;
    AppLogger.log(
        'PlaybackCoordinator: registered ${session.id} ($source, tab=$tabIndex)');
    return session;
  }

  /// Declares which tab a session lives in.
  ///
  /// Screens that resolve their tab after `initState` (a pushed player reading
  /// the tab it was launched from) call this once they know it.
  void bindSessionToTab(PlaybackSession session, int? tabIndex) {
    if (!_isLive(session)) return;
    if (session.tabIndex == tabIndex) return;
    session.tabIndex = tabIndex;
    _applyTabVisibility(session);
  }

  /// Single entry point for "the visible tab changed".
  ///
  /// Route ownership cannot observe tab switches, so this is what stops a
  /// player in a background tab from holding the playback slot and pausing the
  /// feed the user is actually looking at.
  void setActiveTab(int index) {
    if (_activeTabIndex == index) return;
    _activeTabIndex = index;
    AppLogger.log('PlaybackCoordinator: active tab -> $index');
    for (final session in _sessions.values.toList()) {
      _applyTabVisibility(session);
    }
  }

  /// A session with no declared tab is never blocked by tab state, and no tab
  /// is considered background until the app reports which one is active.
  bool _isTabVisible(int? tabIndex) =>
      tabIndex == null || _activeTabIndex == null || tabIndex == _activeTabIndex;

  void _applyTabVisibility(PlaybackSession session) {
    final visible = _isTabVisible(session.tabIndex);
    if (session.tabActive == visible) return;
    session.tabActive = visible;
    if (visible) return;

    _pauseController(session);
    if (_ownerId == session.id) _ownerId = null;
    AppLogger.log(
        'PlaybackCoordinator: paused ${session.id} (${session.source}) — '
        'tab ${session.tabIndex} left the screen');
  }

  void attachController(PlaybackSession session, VideoPlayerController controller) {
    if (!_isLive(session)) return;
    _controllers[session.id] = controller;
  }

  void setRouteActive(PlaybackSession session, bool active) {
    if (!_isLive(session)) return;
    session.routeActive = active;
    if (!active && _ownerId == session.id) {
      _pauseController(session);
      _ownerId = null;
    }
  }

  void setUserPaused(PlaybackSession session, bool paused) {
    if (!_isLive(session)) return;
    session.userPaused = paused;
    if (paused && _ownerId == session.id) {
      _pauseController(session);
      _ownerId = null;
    }
  }

  void setAppLifecycle(bool foreground) {
    _appForeground = foreground;
    for (final session in _sessions.values) {
      session.appForeground = foreground;
    }
    if (!foreground) {
      for (final session in _sessions.values) {
        _pauseController(session);
      }
      _ownerId = null;
    }
  }

  bool canPlay(PlaybackSession session, {String reason = 'unknown'}) {
    final allowed = _isLive(session) &&
        session.routeActive &&
        session.tabActive &&
        session.appForeground &&
        !session.userPaused &&
        _appForeground;
    if (!allowed) {
      AppLogger.log(
        'PlaybackCoordinator: blocked $reason '
        '(session=${session.id}, active=${session.routeActive}, '
        'tabActive=${session.tabActive}, tab=${session.tabIndex}, '
        'foreground=${session.appForeground}, userPaused=${session.userPaused})',
      );
    }
    return allowed;
  }

  /// Claims the global playback slot and starts [controller].
  ///
  /// The second validation after the platform call prevents a route/session
  /// change during startup from leaving audio playing in the background.
  Future<bool> requestPlay(
    PlaybackSession session,
    VideoPlayerController controller, {
    String reason = 'play',
  }) async {
    if (!canPlay(session, reason: reason)) return false;
    _controllers[session.id] = controller;
    _pauseOtherSessions(session);
    _ownerId = session.id;
    try {
      await controller.play();
    } catch (error) {
      if (_ownerId == session.id) _ownerId = null;
      AppLogger.log('PlaybackCoordinator: play failed for ${session.id}: $error');
      return false;
    }
    if (!canPlay(session, reason: '$reason after start')) {
      await _pauseControllerAsync(session);
      if (_ownerId == session.id) _ownerId = null;
      return false;
    }
    return true;
  }

  /// Lets infrastructure such as position restoration request playback only
  /// for the session that already owns the controller. It cannot create a new
  /// playback owner from a background callback.
  Future<bool> requestOwnedPlay(
    VideoPlayerController controller, {
    String reason = 'owned resume',
  }) async {
    final ownerId = _ownerId;
    final owner = ownerId == null ? null : _sessions[ownerId];
    if (owner == null || !identical(_controllers[owner.id], controller)) {
      AppLogger.log('PlaybackCoordinator: blocked $reason (no owning session)');
      return false;
    }
    return requestPlay(owner, controller, reason: reason);
  }

  /// Synchronous policy gate for existing fire-and-forget feed code.
  /// It claims ownership before the platform call, so competing players are
  /// still paused even when the caller cannot await playback.
  bool claimForPlay(
    PlaybackSession session,
    VideoPlayerController controller, {
    String reason = 'play',
  }) {
    if (!canPlay(session, reason: reason)) return false;
    _controllers[session.id] = controller;
    _pauseOtherSessions(session);
    _ownerId = session.id;
    return true;
  }

  void pause(PlaybackSession session, {bool userInitiated = false}) {
    if (!_isLive(session)) return;
    if (userInitiated) session.userPaused = true;
    _pauseController(session);
    if (_ownerId == session.id) _ownerId = null;
  }

  void release(PlaybackSession session) {
    if (!_isLive(session)) return;
    _pauseController(session);
    _sessions.remove(session.id);
    _controllers.remove(session.id);
    if (_ownerId == session.id) _ownerId = null;
    session.released = true;
  }

  bool _isLive(PlaybackSession session) =>
      identical(_sessions[session.id], session) && !session.released;

  bool _allowPooledControllerPlay(VideoPlayerController controller) {
    final ownerId = _ownerId;
    final owner = ownerId == null ? null : _sessions[ownerId];
    return owner != null &&
        identical(_controllers[owner.id], controller) &&
        canPlay(owner, reason: 'manager resume');
  }

  void _pauseOtherSessions(PlaybackSession current) {
    for (final session in _sessions.values) {
      if (session.id != current.id) _pauseController(session);
    }
    // Controllers pre-dating this coordinator may not be attached to a
    // session. The shared pool remains the final global audio guard.
    SharedVideoControllerPool().pauseAllControllers(
      exceptVideoId: _controllerVideoId(current),
    );
  }

  String? _controllerVideoId(PlaybackSession session) {
    final controller = _controllers[session.id];
    if (controller == null) return null;
    return SharedVideoControllerPool().videoIdForController(controller);
  }

  void _pauseController(PlaybackSession session) {
    final controller = _controllers[session.id];
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        unawaited(controller.pause());
      }
    } catch (_) {}
  }

  Future<void> _pauseControllerAsync(PlaybackSession session) async {
    final controller = _controllers[session.id];
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause();
      }
    } catch (_) {}
  }
}
