import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Coordinates playback ownership across every video surface in the app.
///
/// Exactly one surface is "active" at a time. Surfaces never decide this for
/// themselves: they declare where they live (tab, route, lifecycle) and the
/// coordinator derives the winner and tells it to start. A surface that is not
/// active cannot play, cannot pause anyone else, and is not notified of tab
/// switches — which is what stops an off-screen player from silencing the feed
/// the user is actually looking at.
class PlaybackSession {
  PlaybackSession._(this.id, this.source, this.onActivate, this.onDeactivate);

  final int id;
  final String source;

  /// Called when this surface becomes the one allowed to play, and when it
  /// loses that position. These replace the app-wide pause/resume broadcast:
  /// only the winning surface hears about a tab switch.
  final VoidCallback? onActivate;
  final VoidCallback? onDeactivate;

  /// Bottom-navigation tab this surface lives in, when it lives in one.
  ///
  /// A tab switch is not a route push, so `routeActive` alone cannot tell a
  /// dedicated player that it left the screen. Sessions that never bind a tab
  /// keep `tabIndex == null` and are treated as always tab-visible — that is
  /// correct for a route on the root navigator, which covers every tab.
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
  final Map<int, VideoPlayerController> _controllers =
      <int, VideoPlayerController>{};
  int _nextSessionId = 0;
  int? _ownerId;
  bool _appForeground = true;
  int? _activeTabIndex;

  /// The single surface currently entitled to play. Derived, never assigned by
  /// a screen.
  PlaybackSession? _activeSurface;
  bool _isRecomputing = false;

  PlaybackSession register({
    required String source,
    int? tabIndex,
    VoidCallback? onActivate,
    VoidCallback? onDeactivate,
  }) {
    final session =
        PlaybackSession._(++_nextSessionId, source, onActivate, onDeactivate)
          ..appForeground = _appForeground
          ..tabIndex = tabIndex
          ..tabActive = _isTabVisible(tabIndex);
    _sessions[session.id] = session;
    AppLogger.log(
        'PlaybackCoordinator: registered ${session.id} ($source, tab=$tabIndex)');

    // Deferred: a surface registers from `initState`, before its state is ready
    // to be told to play. By the microtask, `didChangeDependencies` has already
    // bound the real tab, so the first activation uses accurate placement.
    scheduleMicrotask(_recomputeActiveSurface);
    return session;
  }

  /// Declares which tab a session lives in.
  ///
  /// Screens resolve this from [TabScope] in `didChangeDependencies`, so it can
  /// arrive after registration and can change if the subtree moves.
  void bindSessionToTab(PlaybackSession session, int? tabIndex) {
    if (!_isLive(session)) return;
    if (session.tabIndex != tabIndex) {
      session.tabIndex = tabIndex;
      _applyTabVisibility(session);
    }
    _recomputeActiveSurface();
  }

  /// Single entry point for "the visible tab changed".
  void setActiveTab(int index) {
    if (_activeTabIndex == index) return;
    _activeTabIndex = index;
    AppLogger.log('PlaybackCoordinator: active tab -> $index');
    for (final session in _sessions.values.toList()) {
      _applyTabVisibility(session);
    }
    _recomputeActiveSurface();
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

  /// A surface may play when it is on screen. `userPaused` is deliberately not
  /// part of this: a surface the user paused still owns the screen, and must
  /// not hand activation to a hidden one.
  bool _isEligible(PlaybackSession session) =>
      !session.released &&
      session.routeActive &&
      session.tabActive &&
      session.appForeground &&
      _appForeground;

  /// Picks the on-screen surface and notifies the handover.
  ///
  /// Ties are broken by registration order: a later session was pushed on top
  /// of an earlier one, so it is the one the user is looking at.
  void _recomputeActiveSurface() {
    if (_isRecomputing) return;
    _isRecomputing = true;
    try {
      PlaybackSession? next;
      for (final session in _sessions.values) {
        if (!_isEligible(session)) continue;
        if (next == null || session.id > next.id) next = session;
      }

      final previous = _activeSurface;
      if (identical(previous, next)) return;
      _activeSurface = next;
      // Whose pinned controllers outrank everyone else's follows the screen,
      // not the play call — otherwise the incoming surface's video is evictable
      // during the gap before it claims playback.
      SharedVideoControllerPool().setActivePinSession(next?.id);
      AppLogger.log(
          'PlaybackCoordinator: active surface ${previous?.id} (${previous?.source}) '
          '-> ${next?.id} (${next?.source})');

      if (previous != null && !previous.released) {
        try {
          previous.onDeactivate?.call();
        } catch (e) {
          AppLogger.log('PlaybackCoordinator: onDeactivate failed: $e');
        }
      }
      try {
        next?.onActivate?.call();
      } catch (e) {
        AppLogger.log('PlaybackCoordinator: onActivate failed: $e');
      }
    } finally {
      _isRecomputing = false;
    }
  }

  void attachController(
      PlaybackSession session, VideoPlayerController controller) {
    if (!_isLive(session)) return;
    _controllers[session.id] = controller;
  }

  void setRouteActive(PlaybackSession session, bool active) {
    if (!_isLive(session)) return;
    if (session.routeActive == active) return;
    session.routeActive = active;
    if (!active && _ownerId == session.id) {
      _pauseController(session);
      _ownerId = null;
    }
    _recomputeActiveSurface();
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
    if (_appForeground == foreground) return;
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
    _recomputeActiveSurface();
  }

  /// Silences every surface without changing who owns the screen, so the next
  /// activation replays normally. Used when the app leaves the foreground or a
  /// screen hands off to something that is not a video.
  void pauseAll() {
    for (final session in _sessions.values) {
      _pauseController(session);
    }
    _ownerId = null;
    // The pin is deliberately left alone: pausing does not mean the surface
    // stopped owning the screen, and un-protecting its controller here would
    // let a preload evict the video the user is about to resume.
    try {
      SharedVideoControllerPool().pauseAllControllers();
      VideoControllerManager().forcePauseAllVideosSync();
    } catch (e) {
      AppLogger.log('PlaybackCoordinator: pauseAll sweep failed: $e');
    }
  }

  bool canPlay(PlaybackSession session, {String reason = 'unknown'}) {
    // Being the active surface already means on-screen, foregrounded, and
    // route-current — the derivation is the guard, so there is no second,
    // divergent copy of it for a screen to get wrong.
    final allowed = _isLive(session) &&
        identical(_activeSurface, session) &&
        !session.userPaused;
    if (!allowed) {
      AppLogger.log(
        'PlaybackCoordinator: blocked $reason '
        '(session=${session.id}, active=${_activeSurface?.id}, '
        'route=${session.routeActive}, tabActive=${session.tabActive}, '
        'tab=${session.tabIndex}, foreground=${session.appForeground}, '
        'userPaused=${session.userPaused})',
      );
    }
    return allowed;
  }

  /// True when [session] is the surface the user is looking at, regardless of
  /// whether playback is currently permitted. Lets a screen decide whether to
  /// spend resources (preload, controller restore) without implying a play.
  bool isActiveSurface(PlaybackSession session) =>
      identical(_activeSurface, session);

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
    _takeOwnership(session, controller);
    try {
      await controller.play();
    } catch (error) {
      if (_ownerId == session.id) _ownerId = null;
      AppLogger.log(
          'PlaybackCoordinator: play failed for ${session.id}: $error');
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
      AppLogger.log(
          'PlaybackCoordinator: blocked $reason (no owning session)');
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
    _takeOwnership(session, controller);
    return true;
  }

  void _takeOwnership(
      PlaybackSession session, VideoPlayerController controller) {
    _controllers[session.id] = controller;
    _pauseOtherSessions(session);
    _ownerId = session.id;
    // Only the owner's pinned controllers are protected from eviction; a
    // background surface's preloads must not outrank what is on screen.
    SharedVideoControllerPool().setActivePinSession(session.id);
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
    if (identical(_activeSurface, session)) _activeSurface = null;
    session.released = true;
    SharedVideoControllerPool().releasePins(session.id);
    // The surface underneath this one is now on screen and must be told.
    _recomputeActiveSurface();
  }

  /// Drops all ownership state. The coordinator is a singleton, so tests need
  /// this to stay independent of each other.
  @visibleForTesting
  void resetForTest() {
    _sessions.clear();
    _controllers.clear();
    _nextSessionId = 0;
    _ownerId = null;
    _appForeground = true;
    _activeTabIndex = null;
    _activeSurface = null;
    _isRecomputing = false;
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
    // session. Both managers share one audio output, so both are swept here —
    // this is the single place that silences competing surfaces, which is why
    // screens no longer need (or are allowed) to do it themselves.
    final exceptVideoId = _controllerVideoId(current);
    SharedVideoControllerPool().pauseAllControllers(exceptVideoId: exceptVideoId);
    VideoControllerManager().forcePauseAllVideosSync(exceptVideoId: exceptVideoId);
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
