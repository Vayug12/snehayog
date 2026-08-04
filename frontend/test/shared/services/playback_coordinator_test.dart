import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';

/// Records every activation handover so a test can assert on the sequence
/// rather than on a final boolean, which would hide a spurious extra call.
class _Surface {
  _Surface(this.name, this.log);

  final String name;
  final List<String> log;

  void activate() => log.add('activate:$name');
  void deactivate() => log.add('deactivate:$name');
}

void main() {
  late PlaybackCoordinator coordinator;
  late List<String> log;

  setUp(() {
    coordinator = PlaybackCoordinator()..resetForTest();
    log = <String>[];
  });

  /// `register` defers its first ownership calculation by a microtask so a
  /// surface is not told to play from inside its own `initState`.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  PlaybackSession registerSurface(String name, {int? tabIndex}) {
    final surface = _Surface(name, log);
    final session = coordinator.register(
      source: name,
      tabIndex: tabIndex,
      onActivate: surface.activate,
      onDeactivate: surface.deactivate,
    );
    return session;
  }

  test('only the visible tab has a surface that may play', () async {
    coordinator.setActiveTab(0);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    final vayu = registerSurface('vayu-feed', tabIndex: 1);
    await settle();

    expect(coordinator.canPlay(feed), isTrue);
    expect(coordinator.canPlay(vayu), isFalse);
    expect(log, <String>['activate:yug-feed']);
  });

  test('a player opened from Profile does not answer the Yug tab switch',
      () async {
    // The exact shape of the reported bug: a player pushed inside the Profile
    // tab stays mounted (IndexedStack keeps hidden tabs alive) while the user
    // watches the Yug feed.
    coordinator.setActiveTab(4);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    final profilePlayer = registerSurface('profile-player', tabIndex: 4);
    await settle();

    expect(coordinator.canPlay(profilePlayer), isTrue);
    expect(coordinator.canPlay(feed), isFalse);

    log.clear();
    coordinator.setActiveTab(0);

    // Exactly one handover: the profile player stands down and the feed takes
    // over. The old broadcast woke every registered feed, and the background
    // one silenced the visible feed on its way to being refused.
    expect(log, <String>['deactivate:profile-player', 'activate:yug-feed']);
    expect(coordinator.canPlay(feed), isTrue);
    expect(coordinator.canPlay(profilePlayer), isFalse);
  });

  test('a still-registered background player cannot claim playback back',
      () async {
    coordinator.setActiveTab(4);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    final profilePlayer = registerSurface('profile-player', tabIndex: 4);
    await settle();
    coordinator.setActiveTab(0);

    // Even asked directly — the resume path a background surface used to reach
    // through its own timers — it is refused.
    expect(coordinator.canPlay(profilePlayer, reason: 'stale resume'), isFalse);
    expect(coordinator.isActiveSurface(feed), isTrue);
  });

  test('a pushed route takes over, and popping hands the screen back',
      () async {
    coordinator.setActiveTab(0);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    await settle();
    log.clear();

    final pushed = registerSurface('pushed-player', tabIndex: 0);
    coordinator.setRouteActive(feed, false); // didPushNext
    await settle();

    expect(log, <String>['deactivate:yug-feed', 'activate:pushed-player']);
    expect(coordinator.canPlay(feed), isFalse);

    log.clear();
    coordinator.setRouteActive(pushed, false); // didPop
    coordinator.setRouteActive(feed, true); // didPopNext
    coordinator.release(pushed);

    expect(coordinator.isActiveSurface(feed), isTrue);
    expect(log, contains('activate:yug-feed'));
  });

  test('backgrounding the app stands every surface down', () async {
    coordinator.setActiveTab(0);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    await settle();
    log.clear();

    coordinator.setAppLifecycle(false);
    expect(log, <String>['deactivate:yug-feed']);
    expect(coordinator.canPlay(feed), isFalse);

    coordinator.setAppLifecycle(true);
    expect(log, <String>['deactivate:yug-feed', 'activate:yug-feed']);
    expect(coordinator.canPlay(feed), isTrue);
  });

  test('a surface the user paused keeps the screen but may not play', () async {
    coordinator.setActiveTab(0);
    final feed = registerSurface('yug-feed', tabIndex: 0);
    registerSurface('vayu-feed', tabIndex: 1);
    await settle();

    coordinator.setUserPaused(feed, true);

    // Still the active surface — otherwise a hidden tab would inherit the slot
    // just because the user tapped pause.
    expect(coordinator.isActiveSurface(feed), isTrue);
    expect(coordinator.canPlay(feed), isFalse);

    coordinator.setUserPaused(feed, false);
    expect(coordinator.canPlay(feed), isTrue);
  });

  test('a session with no tab is never blocked by tab state', () async {
    // A route on the root navigator covers every tab, so it has no tab to be
    // hidden by.
    coordinator.setActiveTab(2);
    final fullscreen = registerSurface('deep-link-player');
    await settle();

    expect(coordinator.canPlay(fullscreen), isTrue);
    coordinator.setActiveTab(3);
    expect(coordinator.canPlay(fullscreen), isTrue);
  });
}
