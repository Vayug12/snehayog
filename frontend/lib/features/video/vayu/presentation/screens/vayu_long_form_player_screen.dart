import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/models/video_url_resolver.dart';
import 'package:vayug/features/video/core/data/services/video_cache_proxy_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/core/interfaces/i_dubbing_service.dart';
import 'package:vayug/features/video/dubbing/data/services/on_device_dubbing_service.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/core/interfaces/i_quiz_engine.dart';
import 'package:vayug/features/video/quiz/data/services/standard_quiz_engine.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:vayug/features/video/core/data/services/video_view_tracker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_feed_item.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_metadata_section.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_channel_info.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_player_overlay.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_dubbing_status_overlay.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_player_gestures_mixin.dart';
import 'package:vayug/features/video/core/data/services/picture_in_picture_service.dart';
import 'package:vayug/shared/widgets/share_options_sheet.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/shared/navigation/app_route_observer.dart';
import 'package:vayug/shared/widgets/tab_scope.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';
import 'package:vayug/shared/services/install_attribution_service.dart';

class VayuLongFormPlayerScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final List<VideoModel> relatedVideos;
  final int? parentTabIndex;
  final IDubbingService? dubbingService;
  final IAdService? adService;
  final IQuizEngine? quizEngine;
  final Duration? initialPosition;
  final Duration? sectionEnd;

  const VayuLongFormPlayerScreen({
    super.key,
    required this.video,
    this.relatedVideos = const [],
    this.parentTabIndex,
    this.dubbingService,
    this.adService,
    this.quizEngine,
    this.initialPosition,
    this.sectionEnd,
  });

  @override
  ConsumerState<VayuLongFormPlayerScreen> createState() =>
      _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState
    extends ConsumerState<VayuLongFormPlayerScreen>
    with WidgetsBindingObserver, RouteAware, VayuPlayerGesturesMixin {
  // The player draws its own subtle protection behind the system bars. The
  // explicit transparent values cover pre-Android-15 devices; Android 15+
  // keeps the same result through edge-to-edge mode.
  static const _playerSystemUiOverlayStyle = SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  VideoPlayerController? get currentVideoController =>
      _controllers[_currentIndex];

  // Video Feed State
  final List<VideoModel> _videos = [];
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, VoidCallback> _positionListeners = {};

  /// In-flight controller creations, keyed by **video id**.
  ///
  /// Preloading a neighbour and swiping onto it both ask for the same video's
  /// controller. Without a shared entry point each built its own, so one video
  /// downloaded twice, the pool disposed whichever lost the race, and the
  /// surviving controller failed the `identical` playback check and paused
  /// itself — the video then buffered forever until the page was revisited.
  /// Keyed by id rather than index because pagination shifts indices.
  final Map<String, Future<VideoPlayerController?>> _controllerRequests = {};

  /// Defers the expensive part of a page change until the scroll settles.
  Timer? _pageChangeDebounce;

  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  final VideoService _videoService = VideoService();

  // Unified Controller Management
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();
  final SharedVideoControllerPool _controllerPool = SharedVideoControllerPool();
  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();
  late final PlaybackSession _playbackSession = _playbackCoordinator.register(
    source: 'vayu-long-form',
    onActivate: _resumeCurrentVideo,
    onDeactivate: _pauseAllPlayback,
  );
  MainController? _mainController;
  bool _lifecyclePaused = false;
  ModalRoute<dynamic>? _observedRoute;

  // System picture-in-picture state. The existing controller stays alive while
  // the Activity shrinks, preserving the stream and current seek position.
  final PictureInPictureService _pictureInPictureService =
      PictureInPictureService.instance;
  late final String _pictureInPictureOwnerId = 'vayu-${identityHashCode(this)}';
  final GlobalKey _pictureInPictureSourceKey = GlobalKey();
  StreamSubscription<PictureInPictureModeEvent>?
      _pictureInPictureModeSubscription;
  StreamSubscription<PictureInPicturePlaybackEvent>?
      _pictureInPicturePlaybackSubscription;
  StreamSubscription<String>? _pictureInPicturePreparationSubscription;
  bool _isPictureInPictureSupported = false;
  bool _isInPictureInPicture = false;
  bool? _lastPictureInPicturePlayingState;
  double? _lastPictureInPictureAspectRatio;

  // Banner Ad State. Fetched once for the whole session: the per-index fetch
  // this replaced ran a server health probe plus an ad request on every single
  // swipe, competing with the video stream for bandwidth.
  late final IAdService _activeAdsService;
  List<Map<String, dynamic>> _bannerAds = const [];
  late final IQuizEngine _quizEngine;

  SharedPreferences? _prefs;
  String? _currentUserId;

  bool _isSaving = false;
  double _playbackSpeed = 1.0;
  final List<double> _playbackSpeedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0
  ];

  bool _wakelockEnabled = false;
  bool _isFullScreenManual = false;
  // Last orientation for which system chrome (bottom nav + system bars) was
  // applied. Lets didChangeMetrics react to physical rotation exactly once
  // and skip rotations already handled by _toggleFullScreen.
  Orientation? _lastChromeOrientation;

  // Scroll hint
  bool _hasSeenScrollHint = true;
  bool _showScrollHintOverlay = false;

  // Dubbing State
  late final IDubbingService _dubbingService;
  final Map<String, ValueNotifier<DubbingResult>> _dubbingResultsVN = {};
  final Map<String, StreamSubscription> _dubbingSubscriptions = {};
  final Map<String, String> _selectedAudioLanguage = {};
  bool _isDubbingProgressVisible = true;

  // Revenue Tracking
  late final VideoViewTracker _viewTracker;

  final Map<int, Timer> _viewUITimers = {};
  final Map<int, Duration> _lastKnownPositions = {};
  DateTime? _lastPositionSaveAt;
  bool _hasAppliedInitialSharePosition = false;
  bool _sharedSectionFinished = false;

  // Quiz State
  QuizModel? _activeQuiz;
  StreamSubscription<String>? _poolDisposalSubscription;
  final Map<int, VoidCallback> _errorListeners = {};

  @override
  void initState() {
    super.initState();
    _mainController = ref.read(mainControllerProvider);
    // The tab is resolved from TabScope in didChangeDependencies: this player
    // is a pushed route and never receives didPushNext when the user switches
    // tabs, so declaring its tab is what lets the coordinator drop its playback
    // claim instead of leaving it playing behind another tab.
    _dubbingService = widget.dubbingService ?? OnDeviceDubbingServiceImpl();
    _activeAdsService = widget.adService ?? ActiveAdsService();
    _quizEngine = widget.quizEngine ?? StandardQuizEngine();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_playerSystemUiOverlayStyle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SystemChrome.setSystemUIOverlayStyle(_playerSystemUiOverlayStyle);
      }
    });

    _videos.add(widget.video);
    if (widget.relatedVideos.isNotEmpty) {
      final otherVideos = List<VideoModel>.from(widget.relatedVideos);
      otherVideos.shuffle();
      _videos.addAll(otherVideos);
    }
    _pageController = PageController(initialPage: 0);

    _initPrefs();
    _viewTracker = VideoViewTracker();
    // _adImpressionService = AdImpressionService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startViewTracking(_currentIndex);
    });

    _videoControllerManager.registerOnRoutePopped(() {
      if (mounted) _validateAndRestoreControllers();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final initialIdx = _videos.indexWhere((v) => v.id == widget.video.id);
        if (initialIdx >= 0) {
          _currentIndex = initialIdx;
          _pageController.jumpToPage(initialIdx);
        } else {
          final mainController = ref.read(mainControllerProvider);
          final lastIndex = await mainController.getLastViewedVideoIndex(1);
          if (!mounted) return;
          if (lastIndex > 0 && lastIndex < _videos.length) {
            _currentIndex = lastIndex;
            _pageController.jumpToPage(lastIndex);
          } else {
            _currentIndex = 0;
          }
        }
        // Pin BEFORE anything preloads. Preloading a neighbour refreshes that
        // neighbour's LRU timestamp, so an unpinned current video becomes the
        // pool's eviction candidate — and evicting it fires the disposal
        // stream, which re-initialises it, which evicts it again.
        _pinCurrentVideo();
        _initializePlayer(_currentIndex);
        _preloadNearbyVideos();
        _reprimeWindowIfNeeded(_currentIndex);
      }
    });

    unawaited(_loadBannerAds());

    if (_videos.length < 3) {
      _loadMoreVideos();
    }

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mainController = ref.read(mainControllerProvider);
        // Competing surfaces are silenced by the coordinator's handover when
        // this route becomes the active one. Pausing globally from here also
        // hit this player's own controller, moments before it tried to start.
        // Apply chrome for the entry orientation once, instead of on every
        // build. Rotations are handled by _toggleFullScreen/didChangeMetrics.
        final orientation = MediaQuery.orientationOf(context);
        _lastChromeOrientation = orientation;
        final isLandscape = orientation == Orientation.landscape;
        _applyPlayerChrome(
          fullscreen: isLandscape || _isFullScreenManual,
          immersive: isLandscape,
        );
      }
    });

    _poolDisposalSubscription =
        _controllerPool.disposalStream.listen((videoId) {
      if (!mounted) return;
      final index = _videos.indexWhere((v) => v.id == videoId);
      if (index == -1) return;
      final held = _controllers[index];
      if (held == null) return;
      // The pool emits a disposal when a controller is REPLACED in place too,
      // and the stream is delivered asynchronously — so by the time this runs,
      // the map may already hold the healthy replacement. Tearing that down
      // would restart the very controller that just became ready, which is how
      // a page ends up reloading forever. Only react to the instance that
      // actually went away.
      if (!_controllerPool.isControllerDisposed(held)) return;

      _detachControllerListeners(index);
      setState(() => _controllers.remove(index));
      if (index == _currentIndex) _initializePlayer(index);
    });

    isSeekingBufferingVN.addListener(_onSeekingBufferingChanged);
    unawaited(_initializePictureInPicture());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      if (_observedRoute != null) appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    // An explicit parentTabIndex wins; otherwise the enclosing TabScope answers
    // it correctly however deeply this player was pushed.
    _playbackCoordinator.bindSessionToTab(
      _playbackSession,
      widget.parentTabIndex ?? TabScope.maybeOf(context),
    );
    _mainController = ref.watch(mainControllerProvider);
    final authController = ref.watch(googleSignInProvider);
    if (authController.isSignedIn && authController.userData != null) {
      final userId = authController.userData!['googleId'] ??
          authController.userData!['id'];
      if (_currentUserId != userId) {
        setState(() => _currentUserId = userId);
      }
    } else if (!authController.isSignedIn && _currentUserId != null) {
      setState(() => _currentUserId = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_isInPictureInPicture) {
          _lifecyclePaused = false;
          _playbackCoordinator.setAppLifecycle(true);
          break;
        }
        _playbackCoordinator.setAppLifecycle(false);
        _handleAppMovedToBackground();
        break;
      case AppLifecycleState.resumed:
        _playbackCoordinator.setAppLifecycle(true);
        _handleAppResumed();
        break;
      case AppLifecycleState.detached:
        _videoControllerManager.disposeAllControllers();
        break;
      default:
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    // Physical rotation: apply the final chrome (bottom nav + system bars) as
    // soon as the metrics flip, so the rotation animation lands on the final
    // layout. Button-triggered toggles already set _lastChromeOrientation and
    // are skipped here.
    final physicalSize =
        WidgetsBinding.instance.platformDispatcher.implicitView?.physicalSize;
    if (physicalSize == null || physicalSize.isEmpty) return;
    final orientation = physicalSize.width > physicalSize.height
        ? Orientation.landscape
        : Orientation.portrait;
    if (orientation == _lastChromeOrientation) return;
    _lastChromeOrientation = orientation;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) return;
    final isLandscape = orientation == Orientation.landscape;
    _applyPlayerChrome(
      fullscreen: isLandscape || _isFullScreenManual,
      immersive: isLandscape,
    );
    _syncPictureInPictureState(force: true);
  }

  Future<void> _initializePictureInPicture() async {
    _pictureInPictureModeSubscription =
        _pictureInPictureService.modeChanges.listen((event) {
      if (event.ownerId == _pictureInPictureOwnerId) {
        _onPictureInPictureModeChanged(event.isActive);
      }
    });
    _pictureInPicturePlaybackSubscription =
        _pictureInPictureService.playbackRequests.listen((event) {
      if (event.ownerId == _pictureInPictureOwnerId) {
        unawaited(_onPictureInPicturePlaybackRequested(event.shouldPlay));
      }
    });
    _pictureInPicturePreparationSubscription =
        _pictureInPictureService.preparationRequests.listen((ownerId) {
      if (ownerId == _pictureInPictureOwnerId) {
        _preparePictureInPictureSurface();
      }
    });
    final isSupported = await _pictureInPictureService.initialize();
    if (!mounted) return;
    setState(() => _isPictureInPictureSupported = isSupported);
    if (isSupported) _syncPictureInPictureState(force: true);
  }

  void _preparePictureInPictureSurface() {
    if (!mounted || _isInPictureInPicture) return;
    setState(() => _isInPictureInPicture = true);
    _lifecyclePaused = false;
    _playbackCoordinator.setAppLifecycle(true);
  }

  void _onPictureInPictureModeChanged(bool isActive) {
    if (!mounted) return;
    setState(() => _isInPictureInPicture = isActive);
    if (isActive) {
      _lifecyclePaused = false;
      _playbackCoordinator.setAppLifecycle(true);
      _resumeCurrentVideo();
      return;
    }

    final isResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (isResumed) {
      _playbackCoordinator.setAppLifecycle(true);
      _handleAppResumed();
    } else {
      _playbackCoordinator.setAppLifecycle(false);
      _handleAppMovedToBackground();
    }
  }

  Future<void> _onPictureInPicturePlaybackRequested(bool shouldPlay) async {
    final controller = currentVideoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (shouldPlay) {
      onUserPlaybackChanged(true);
      await _playIfAllowed(_currentIndex, controller);
    } else {
      onUserPlaybackChanged(false);
      await controller.pause();
    }
    await _syncPictureInPictureState(force: true);
  }

  Future<void> _syncPictureInPictureState({bool force = false}) async {
    if (!_isPictureInPictureSupported) return;
    final controller = currentVideoController;
    final isPlaying =
        controller?.value.isInitialized == true && controller!.value.isPlaying;
    final aspectRatio =
        controller == null ? 16 / 9 : _pictureInPictureAspectRatio(controller);
    if (!force &&
        _lastPictureInPicturePlayingState == isPlaying &&
        _lastPictureInPictureAspectRatio == aspectRatio) {
      return;
    }
    _lastPictureInPicturePlayingState = isPlaying;
    _lastPictureInPictureAspectRatio = aspectRatio;
    await _pictureInPictureService.update(
      ownerId: _pictureInPictureOwnerId,
      aspectRatio: aspectRatio,
      isPlaying: isPlaying,
      autoEnterEnabled: isPlaying && !_isInPictureInPicture,
      sourceRect: _pictureInPictureSourceRect(),
    );
  }

  double _pictureInPictureAspectRatio(VideoPlayerController controller) {
    final ratio = controller.value.aspectRatio;
    return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
  }

  List<double>? _pictureInPictureSourceRect() {
    final sourceContext = _pictureInPictureSourceKey.currentContext;
    final renderBox = sourceContext?.findRenderObject();
    if (sourceContext == null || renderBox is! RenderBox || !renderBox.hasSize) {
      return null;
    }
    final origin = renderBox.localToGlobal(Offset.zero);
    final pixelRatio = View.of(sourceContext).devicePixelRatio;
    return <double>[
      origin.dx * pixelRatio,
      origin.dy * pixelRatio,
      (origin.dx + renderBox.size.width) * pixelRatio,
      (origin.dy + renderBox.size.height) * pixelRatio,
    ];
  }

  void _handleAppMovedToBackground() {
    _lifecyclePaused = true;
    _pauseAllPlayback();
  }

  void _handleAppResumed() {
    _lifecyclePaused = false;
    _resumeCurrentVideo();
  }

  /// Silences this player's own controllers. Deliberately local: pausing the
  /// shared pool from here also stopped whatever surface was taking over.
  void _pauseAllPlayback() {
    _playbackCoordinator.pause(_playbackSession);
    for (final controller in _controllers.values) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
        }
      } catch (_) {}
    }
    _disableWakelock();
  }

  /// Whether this player may start [controller] for [index].
  ///
  /// Placement — route, tab, app lifecycle — comes from the coordinator, which
  /// is the only thing that knows about the other surfaces. `_isParentTabActive`
  /// used to answer "is my tab visible?" with "am I the current route?", which
  /// is always true for a pushed player and let it play from a hidden tab.
  bool _canPlayCurrentVideo(int index, VideoPlayerController controller) {
    return mounted &&
        !_lifecyclePaused &&
        index == _currentIndex &&
        identical(_controllers[index], controller) &&
        _playbackCoordinator.canPlay(_playbackSession, reason: 'vayu $index');
  }

  Future<bool> _playIfAllowed(
    int index,
    VideoPlayerController controller,
  ) async {
    if (!_canPlayCurrentVideo(index, controller)) {
      try {
        if (controller.value.isPlaying) await controller.pause();
      } catch (_) {}
      return false;
    }

    final didPlay = await _playbackCoordinator.requestPlay(
      _playbackSession,
      controller,
      reason: 'vayu index $index',
    );
    if (!didPlay || !_canPlayCurrentVideo(index, controller)) {
      _playbackCoordinator.pause(_playbackSession);
      return false;
    }

    _enableWakelock();
    return true;
  }

  @override
  Future<void> playCurrentVideo() async {
    final controller = currentVideoController;
    if (controller != null) {
      await _playIfAllowed(_currentIndex, controller);
    }
  }

  @override
  void onUserPlaybackChanged(bool isPlaying) {
    _playbackCoordinator.setUserPaused(_playbackSession, !isPlaying);
  }

  @override
  void didPushNext() {
    _playbackCoordinator.setRouteActive(_playbackSession, false);
    _pauseAllPlayback();
  }

  @override
  void didPopNext() {
    _playbackCoordinator.setRouteActive(_playbackSession, true);
    _resumeCurrentVideo();
  }

  /// This route was popped. Its widget lives until the transition finishes, so
  /// without giving the slot up here it stays the top-most eligible surface for
  /// the length of the animation and keeps the screen underneath silent.
  @override
  void didPop() {
    _playbackCoordinator.setRouteActive(_playbackSession, false);
    _pauseAllPlayback();
  }

  void _resumeCurrentVideo() {
    if (!mounted || _lifecyclePaused) return;
    _validateAndRestoreControllers();
    final controller = _controllers[_currentIndex];
    if (controller != null && controller.value.isInitialized) {
      _playIfAllowed(_currentIndex, controller);
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final hasSeenHint =
        _prefs!.getBool('has_seen_vayu_long_form_scroll_hint') ?? false;
    if (mounted) setState(() => _hasSeenScrollHint = hasSeenHint);
    if (!hasSeenHint) _handleFirstTimeScrollHint(_prefs!);
  }

  Future<void> _handleFirstTimeScrollHint(SharedPreferences prefs) async {
    if (_videos.length > 1 && widget.relatedVideos.isNotEmpty) return;
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || _currentIndex != 0 || _videos.length <= 1) return;
    setState(() => _showScrollHintOverlay = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final targetOffset = screenHeight * 0.30;
    try {
      await _pageController.animateTo(targetOffset,
          duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;
      await _pageController.animateTo(0,
          duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
    } catch (e) {
      AppLogger.log('Error scroll hint: $e');
    }
    if (!mounted) return;
    setState(() => _showScrollHintOverlay = false);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _hasSeenScrollHint = true);
    await prefs.setBool('has_seen_vayu_long_form_scroll_hint', true);
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final response = await _videoService.getVideos(
          page: _currentPage,
          videoType: 'vayu',
          clearSession: false,
          random: true);
      List<VideoModel> newVideos = [];
      final List? videosList = response['videos'] ?? response['data'];
      if (videosList != null) {
        newVideos = videosList
            .map((v) => VideoModel.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        newVideos.shuffle();
      }
      if (newVideos.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        final existingIds = _videos.map((v) => v.id).toSet();
        newVideos.removeWhere((v) => existingIds.contains(v.id));
        if (mounted) {
          setState(() {
            _videos.addAll(newVideos);
            _currentPage++;
            _hasMore = response['hasMore'] as bool? ?? true;
          });
          if (_currentIndex + 1 < _videos.length) _preloadNearbyVideos();
        }
      }
    } catch (e) {
      AppLogger.log('Error loading more: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// The video a controller should actually stream, honouring the audio
  /// language the user picked for it.
  VideoModel _effectiveVideo(VideoModel video) {
    final selectedLang = _selectedAudioLanguage[video.id] ?? 'default';
    if (selectedLang == 'default') return video;
    final dubbedUrl = video.dubbedUrls?[selectedLang];
    if (dubbedUrl == null || dubbedUrl.isEmpty) return video;
    return video.copyWith(videoUrl: dubbedUrl);
  }

  /// Returns the one controller for [index]'s video, creating it only if
  /// nobody else already is.
  ///
  /// Every path that needs a controller — playback and speculative preload
  /// alike — goes through here. Previously they each built their own, so a
  /// preload still in flight when the user swiped onto that page produced a
  /// second controller for the same video: two downloads of one stream, and
  /// whichever lost the race left the winner failing `_canPlayCurrentVideo`'s
  /// identity check, so it paused itself and the page buffered indefinitely.
  Future<VideoPlayerController?> _acquireController(
    int index, {
    bool highPriority = false,
  }) {
    if (index < 0 || index >= _videos.length) return Future.value(null);
    final video = _videos[index];

    final pooled = _controllerPool.getController(video.id);
    if (pooled != null && pooled.value.isInitialized) {
      return Future.value(pooled);
    }

    final inFlight = _controllerRequests[video.id];
    if (inFlight != null) return inFlight;

    final request = _createControllerFor(index, video, highPriority)
        .whenComplete(() => _controllerRequests.remove(video.id));
    _controllerRequests[video.id] = request;
    return request;
  }

  /// True once [index] has drifted outside the live window, or this screen is
  /// gone. Checked after every await so a controller for a page the user has
  /// already scrolled past is torn down instead of published.
  bool _isStaleRequest(int index) =>
      !mounted || (index - _currentIndex).abs() > 1;

  Future<VideoPlayerController?> _createControllerFor(
    int index,
    VideoModel video,
    bool highPriority,
  ) async {
    VideoPlayerController? controller;
    try {
      // Admission control BEFORE allocating: a refused speculative preload is
      // the point — it must not take the decoder out from under the video
      // that is actually on screen.
      final admitted = await _controllerPool.makeRoomForNewController(
        forVideoId: video.id,
        highPriority: highPriority,
      );
      if (!admitted || _isStaleRequest(index)) return null;

      controller =
          await VideoControllerFactory.createController(_effectiveVideo(video));
      if (_isStaleRequest(index)) {
        await controller.dispose();
        return null;
      }

      await controller.initialize().timeout(const Duration(seconds: 15));
      if (_isStaleRequest(index)) {
        await controller.dispose();
        return null;
      }

      await controller.setPlaybackSpeed(_playbackSpeed);
      // Autoplay is never the controller's decision: playback only starts
      // through _playIfAllowed, which the coordinator gates.
      await controller.pause();

      _controllerPool.addController(video.id, controller);
      return controller;
    } catch (e) {
      AppLogger.log('Failed to init controller for ${video.id}: $e');
      try {
        await controller?.dispose();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _initializePlayer([int? requestedIndex]) async {
    final index = requestedIndex ?? _currentIndex;
    if (index < 0 || index >= _videos.length) return;

    final controller = await _acquireController(index, highPriority: true);
    // The request may have been served after the user moved on.
    if (controller == null || _isStaleRequest(index)) return;

    if (!identical(_controllers[index], controller)) {
      _detachControllerListeners(index);
      setState(() => _controllers[index] = controller);
    }
    _setupLateInitialization(index, controller);
  }

  /// Removes this screen's listeners from whatever controller currently sits
  /// at [index], without touching the controller itself — the pool owns its
  /// lifetime.
  void _detachControllerListeners(int index) {
    final existing = _controllers[index];
    final position = _positionListeners.remove(index);
    final error = _errorListeners.remove(index);
    if (existing == null) return;
    try {
      if (position != null) existing.removeListener(position);
      if (error != null) existing.removeListener(error);
    } catch (_) {}
  }

  bool _isCurrentPlaybackTarget(int index, VideoPlayerController controller) {
    return _canPlayCurrentVideo(index, controller);
  }

  Future<void> _setupLateInitialization(
    int index,
    VideoPlayerController controller,
  ) async {
    if (index == _currentIndex) {
      _playbackCoordinator.attachController(_playbackSession, controller);
    }
    // One listener, not two. Every VideoPlayerValue update ran both the
    // position and the error callback, doubling the per-tick cost for each
    // live controller; error state is just another field on that same value.
    final previousPositionListener = _positionListeners.remove(index);
    if (previousPositionListener != null) {
      controller.removeListener(previousPositionListener);
    }
    final previousErrorListener = _errorListeners.remove(index);
    if (previousErrorListener != null) {
      controller.removeListener(previousErrorListener);
    }
    void positionListener() =>
        _handleControllerPositionChanged(index, controller);
    _positionListeners[index] = positionListener;
    controller.addListener(positionListener);
    if (!_isCurrentPlaybackTarget(index, controller)) {
      await controller.pause();
      return;
    }

    final didApplySharedPosition =
        await _applyInitialSharePosition(index, controller);
    if (!_isCurrentPlaybackTarget(index, controller)) {
      await controller.pause();
      return;
    }
    if (!didApplySharedPosition) {
      await _resumePlayback(index);
    }
    if (!_isCurrentPlaybackTarget(index, controller)) {
      await controller.pause();
      return;
    }

    if (!await _playIfAllowed(index, controller)) return;
    if (showControls) startHideControlsTimer(MediaQuery.orientationOf(context));
    try {
      brightnessValue = await ScreenBrightness().application;
      final vol = await FlutterVolumeController.getVolume();
      if (vol != null) volumeValue = vol;
    } catch (_) {}
  }

  void _handleControllerPositionChanged(
    int index,
    VideoPlayerController controller,
  ) {
    if (!mounted) return;
    if (_handleVideoError(index, controller)) return;
    if (!_isCurrentPlaybackTarget(index, controller)) {
      if (controller.value.isPlaying) {
        unawaited(controller.pause());
      }
      return;
    }
    if (isSeekingBufferingVN.value && controller.value.isPlaying) {
      isSeekingBufferingVN.value = false;
    }
    unawaited(_syncPictureInPictureState());
    _onPositionChanged();
  }

  Future<bool> _applyInitialSharePosition(
    int index,
    VideoPlayerController controller,
  ) async {
    final initialPosition = widget.initialPosition;
    if (index != 0 ||
        initialPosition == null ||
        _hasAppliedInitialSharePosition ||
        !_isCurrentPlaybackTarget(index, controller)) {
      return false;
    }

    final duration = controller.value.duration;
    if (duration <= Duration.zero) return false;
    final safePosition = initialPosition < duration
        ? initialPosition
        : Duration(milliseconds: duration.inMilliseconds - 1);
    await controller.seekTo(safePosition);
    _lastKnownPositions[index] = safePosition;
    _hasAppliedInitialSharePosition = true;
    return true;
  }

  /// Returns true when [controller] is in an error state, so the caller can
  /// skip the rest of the tick.
  bool _handleVideoError(int index, VideoPlayerController controller) {
    try {
      if (_controllerPool.isControllerDisposed(controller)) return true;
      if (!controller.value.hasError) return false;
      if (index == _currentIndex) {
        // Drop the failed controller first: leaving it pooled means
        // _acquireController hands the same broken instance straight back.
        _detachControllerListeners(index);
        _controllers.remove(index);
        _controllerPool.disposeController(_videos[index].id);
        _initializePlayer(index);
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final controller = _controllers[_currentIndex];
    if (controller == null) return;
    final currentPos = controller.value.position;
    final lastPos = _lastKnownPositions[_currentIndex] ?? Duration.zero;
    if (currentPos < lastPos && lastPos.inSeconds > 1) {
      _stopViewTracking(_currentIndex);
      _startViewTracking(_currentIndex);
    }
    _lastKnownPositions[_currentIndex] = currentPos;
    _pauseAtSharedSectionEnd(controller, currentPos);
    // Throttled on wall-clock, not on the position value: the controller ticks
    // several times inside the same second, so `position.inSeconds % 5` fired
    // a SharedPreferences write on each of them.
    if (controller.value.isPlaying) {
      final now = DateTime.now();
      final last = _lastPositionSaveAt;
      if (last == null || now.difference(last) >= const Duration(seconds: 5)) {
        _lastPositionSaveAt = now;
        _savePlaybackPosition(_currentIndex);
      }
    }
    _checkAndTriggerQuiz(controller);
  }

  void _pauseAtSharedSectionEnd(
    VideoPlayerController controller,
    Duration currentPosition,
  ) {
    final end = widget.sectionEnd;
    if (_currentIndex != 0 || end == null || _sharedSectionFinished) return;
    if (currentPosition >= end) {
      _sharedSectionFinished = true;
      controller.pause();
      _showSnackBar('Shared section finished');
    }
  }

  void _checkAndTriggerQuiz(VideoPlayerController controller) {
    if (_activeQuiz != null) return;
    final video = _videos[_currentIndex];
    final quizzes = video.quizzes;
    if (quizzes == null || quizzes.isEmpty) return;
    final quiz = _quizEngine.evaluatePosition(
      videoId: video.id,
      currentPosition: controller.value.position,
      quizzes: quizzes,
    );
    if (quiz != null) {
      _quizEngine.markShown(video.id, quiz);
      setState(() {
        _activeQuiz = quiz;
      });
    }
  }

  @override
  void dispose() {
    _pictureInPictureModeSubscription?.cancel();
    _pictureInPicturePlaybackSubscription?.cancel();
    _pictureInPicturePreparationSubscription?.cancel();
    unawaited(_pictureInPictureService.release(_pictureInPictureOwnerId));
    // Also drops this session's pool pin — see PlaybackCoordinator.release.
    _playbackCoordinator.release(_playbackSession);
    _pageChangeDebounce?.cancel();
    _disableWakelock();
    appRouteObserver.unsubscribe(this);
    _seekingBufferingTimeout?.cancel();
    isSeekingBufferingVN.removeListener(_onSeekingBufferingChanged);
    disposeGestures();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _savePlaybackPosition(_currentIndex);

    // Only this player's own controllers are silenced. A blanket pause would
    // also hit the surface underneath, which the coordinator reactivates as
    // this route goes away.
    _videoControllerManager.pauseAllVideos();

    _controllers.forEach((index, c) {
      try {
        final position = _positionListeners.remove(index);
        if (position != null) c.removeListener(position);
        final error = _errorListeners.remove(index);
        if (error != null) c.removeListener(error);
        c.pause();
        c.setVolume(0.0);
      } catch (_) {}
    });
    controlsTimer?.cancel();
    overlayTimer?.cancel();
    _seekingBufferingTimeout?.cancel();
    _stopViewTracking(_currentIndex);
    _poolDisposalSubscription?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Future.microtask(() {
      if (context.mounted) {
        ref.read(mainControllerProvider).setBottomNavVisibility(true);
      }
    });
    super.dispose();
  }

  void _startViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    _viewTracker.startViewTracking(video.id,
        videoUploaderId: video.uploader.id, videoHash: video.videoHash);
    _viewUITimers[index]?.cancel();
    _viewUITimers[index] = Timer(const Duration(seconds: 3), () {
      if (mounted && _currentIndex == index) {
        setState(() {
          _videos[index] =
              _videos[index].copyWith(views: _videos[index].views + 1);
        });
      }
    });
  }

  void _stopViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    _viewUITimers[index]?.cancel();
    _viewUITimers.remove(index);
    _viewTracker.stopViewTracking(_videos[index].id);
  }

  void _savePlaybackPosition(int index) async {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt('video_pos_${_videos[index].id}',
          controller.value.position.inSeconds);
    }
  }

  Future<void> _resumePlayback(int index) async {
    final controller = _controllers[index];
    if (controller == null) return;

    // First try memory-cached position (for smooth orientation/tab switches)
    final memoryPos = _lastKnownPositions[index];
    if (memoryPos != null && memoryPos > Duration.zero) {
      if (memoryPos < controller.value.duration) {
        await controller.seekTo(memoryPos);
        return;
      }
    }

    // Fallback to persisted SharedPreferences (for app restarts)
    _prefs ??= await SharedPreferences.getInstance();
    final savedSeconds = _prefs!.getInt('video_pos_${_videos[index].id}');
    if (savedSeconds != null && savedSeconds > 0) {
      final pos = Duration(seconds: savedSeconds);
      if (pos < controller.value.duration) {
        await controller.seekTo(pos);
      }
    }
  }

  void _showSnackBar(String message,
      {Duration? duration, VayuSnackBarType type = VayuSnackBarType.info}) {
    if (!mounted) return;
    VayuSnackBar.show(context, message,
        duration: duration ?? const Duration(seconds: 3), type: type);
  }

  void _showEpisodeList(BuildContext context, VideoModel video) {
    if (video.episodes == null || video.episodes!.isEmpty) return;
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Episodes',
      padding: EdgeInsets.zero,
      builder: (context, scrollController) {
        return ListView.separated(
          shrinkWrap: true,
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: video.episodes!.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final ep = video.episodes![index];
            final isCurrent = ep['id'] == video.id || ep['_id'] == video.id;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 100,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: ep['thumbnailUrl'] != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(ep['thumbnailUrl']),
                          fit: BoxFit.cover)
                      : null,
                  color: AppColors.textTertiary.withValues(alpha: 0.05),
                ),
                child: isCurrent
                    ? Container(
                        decoration: BoxDecoration(
                            color: AppColors.overlayDark,
                            borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.play_circle_fill_rounded,
                            color: AppColors.primary, size: 28))
                    : null,
              ),
              title: Text(ep['videoName'] ?? 'Episode ${index + 1}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.textPrimary)),
              subtitle: ep['duration'] != null
                  ? Text(
                      _formatDuration(
                          Duration(seconds: (ep['duration'] as num).toInt())),
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary))
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (!isCurrent) {
                  final epId = ep['id'] ?? ep['_id'];
                  if (epId != null) {
                    final targetIndex = _videos.indexWhere((v) => v.id == epId);
                    if (targetIndex != -1) {
                      _pageController.animateToPage(targetIndex,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    }
                  }
                }
              },
            );
          },
        );
      },
    );
  }

  void _showShareOptions(VideoModel video) {
    ShareOptionsSheet.show(
      context,
      video: video,
      controller: _controllers[_currentIndex],
    );
  }

  void _showShareSuggestionBottomSheet(VideoModel video) async {
    final TextEditingController controller = TextEditingController();
    final authState = ref.read(googleSignInProvider);
    final userEmail = authState.userData?['email'] ?? 'anonymous@vayug.com';
    final userId = authState.userData?['googleId'] ??
        authState.userData?['id'] ??
        'anonymous';

    VayuBottomSheet.show<void>(
      context: context,
      title: 'Share Suggestion',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'Did you face any problem while watching this video? share with us',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText: 'Type here...',
                    filled: true,
                    fillColor: AppColors.backgroundSecondary,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 20),
            AppButton(
                onPressed: () async {
                  final suggestionText = controller.text.trim();
                  if (suggestionText.isEmpty) {
                    _showSnackBar('Please type something',
                        type: VayuSnackBarType.error);
                    return;
                  }

                  Navigator.pop(context);
                  _showSnackBar('Submitting suggestion...');

                  try {
                    final attribution = await InstallAttributionService.instance
                        .getAttributionPayload();
                    final payload = <String, dynamic>{
                      'type': 'suggestion',
                      'comments': suggestionText,
                      'userEmail': userEmail,
                      'userId': userId,
                      'videoId': video.id,
                      'rating': 5,
                    };

                    if (attribution.isNotEmpty) {
                      payload['attribution'] = attribution;
                    }

                    final response = await _videoService.httpClientService.post(
                      Uri.parse('${NetworkHelper.apiBaseUrl}/feedback/submit'),
                      body: payload,
                    );

                    if (response.statusCode == 201) {
                      _showSnackBar('Suggestion shared! Thank you.',
                          type: VayuSnackBarType.success);
                    } else {
                      _showSnackBar('Failed to share suggestion',
                          type: VayuSnackBarType.error);
                    }
                  } catch (e) {
                    AppLogger.error('Error submitting suggestion', e);
                    _showSnackBar('Network error. Try again later.',
                        type: VayuSnackBarType.error);
                  }
                },
                label: 'Share Suggestion'),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExternalPlayer(VideoModel video) async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final intent = AndroidIntent(
          action: 'action_view',
          data: video.videoUrl,
          type: 'video/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK]);
      try {
        await intent.launch();
      } catch (e) {
        _showSnackBar('No external player found', type: VayuSnackBarType.error);
      }
    } else {
      final url = Uri.parse(video.videoUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _handleToggleSave([int? requestedIndex]) async {
    if (_isSaving) return;
    final index = requestedIndex ?? _currentIndex;
    final video = _videos[index];
    try {
      setState(() => _isSaving = true);
      HapticFeedback.lightImpact();
      final isSaved = await _videoService.toggleSave(video.id);
      setState(() {
        video.isSaved = isSaved;
        _isSaving = false;
      });
      _showSnackBar(isSaved ? 'Saved' : 'Removed',
          type: isSaved ? VayuSnackBarType.success : VayuSnackBarType.info);
    } catch (e) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (_playbackSpeed == speed) return;
    try {
      final controller = _controllers[_currentIndex];
      if (controller != null) await controller.setPlaybackSpeed(speed);
      setState(() => _playbackSpeed = speed);
    } catch (e) {
      AppLogger.error('Error setting playback speed', e);
    }
  }

  void _nextVideo() {
    if (_currentIndex < _videos.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _previousVideo() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  /// Applies system bars + app bottom nav for the target mode in one place,
  /// BEFORE a rotation starts, so the OS rotation animation lands directly on
  /// the final layout instead of reflowing a second time afterwards.
  void _applyPlayerChrome({required bool fullscreen, required bool immersive}) {
    _mainController?.setBottomNavVisibility(!fullscreen);
    if (immersive) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(_playerSystemUiOverlayStyle);
    }
  }

  Timer? _seekingBufferingTimeout;
  void _onSeekingBufferingChanged() {
    _seekingBufferingTimeout?.cancel();
    if (isSeekingBufferingVN.value) {
      _seekingBufferingTimeout = Timer(const Duration(seconds: 5), () {
        if (mounted) isSeekingBufferingVN.value = false;
      });
    }
  }

  void _toggleFullScreen() {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final controller = _controllers[_currentIndex];

    // Capture exact position before orientation change
    if (controller != null) {
      _lastKnownPositions[_currentIndex] = controller.value.position;
    }

    final aspectRatio = controller?.value.aspectRatio ?? 1.0;
    if (aspectRatio < 1.0) {
      // Vertical video: manual fullscreen, no rotation involved.
      setState(() => _isFullScreenManual = !_isFullScreenManual);
      _applyPlayerChrome(fullscreen: _isFullScreenManual, immersive: false);
      showControlsVN.value = true;
      startHideControlsTimer(Orientation.portrait);
    } else {
      final goingLandscape = isPortrait;
      _isFullScreenManual = false;
      _lastChromeOrientation =
          goingLandscape ? Orientation.landscape : Orientation.portrait;
      _applyPlayerChrome(fullscreen: goingLandscape, immersive: goingLandscape);
      // ValueNotifier update — no setState here. The orientation change itself
      // drives the single rebuild; an extra setState now would paint an
      // intermediate frame with the new state but the old orientation.
      showControlsVN.value = true;
      SystemChrome.setPreferredOrientations(goingLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
      startHideControlsTimer(
          goingLandscape ? Orientation.landscape : Orientation.portrait);
    }
  }

  Future<void> _showMoreOptions() async {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    VayuBottomSheet.show<void>(
      context: context,
      title: 'More Options',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
              dense: true,
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Playback Speed'),
              trailing: Text('${_playbackSpeed}x'),
              onTap: () {
                Navigator.pop(context);
                _showPlaybackSpeedOptions();
              }),
          if (_currentIndex < _videos.length)
            ListTile(
                dense: true,
                leading: const Icon(Icons.language_rounded),
                title: const Text('Audio Language'),
                onTap: () {
                  Navigator.pop(context);
                  _showLanguageSelector(context, _videos[_currentIndex]);
                }),
          ListTile(
              dense: true,
              leading: Icon(isControlsLockedVN.value
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded),
              title: Text(isControlsLockedVN.value ? 'Unlock' : 'Lock'),
              onTap: () {
                Navigator.pop(context);
                isControlsLockedVN.value = !isControlsLockedVN.value;
              }),
          ListTile(
              dense: true,
              leading: const Icon(Icons.report_problem_rounded),
              title: const Text('Report'),
              onTap: () {
                Navigator.pop(context);
                _openReportDialog();
              }),
        ],
      ),
    );
  }

  void _openReportDialog() {
    VayuBottomSheet.show(
        context: context,
        title: 'Report',
        child: ReportDialogWidget(
            targetType: 'video', targetId: _videos[_currentIndex].id));
  }

  Future<void> _showPlaybackSpeedOptions() async {
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Speed',
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _playbackSpeedOptions
              .map((s) => ListTile(
                  title: Text('${s}x',
                      style: AppTypography.bodyMedium.copyWith(
                          color: s == _playbackSpeed
                              ? AppColors.primary
                              : AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(context);
                    _setPlaybackSpeed(s);
                  }))
              .toList()),
    );
  }

  /// Only the work the new page cannot be shown without runs synchronously
  /// here; everything else waits for the scroll to settle.
  ///
  /// This used to tear down controllers, start two preloads, initialise a
  /// third controller and fire two network requests inside the settle
  /// animation of every swipe — with three controller creations racing each
  /// other on the UI isolate. That is the scroll jank.
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    final oldVideoId = _videos[_currentIndex].id;
    _quizEngine.reset(oldVideoId);
    // Stop this player's own controllers before switching the active index.
    // This covers a controller that finished buffering after the previous swipe.
    _pauseAllPlayback();
    _stopViewTracking(_currentIndex);
    setState(() {
      _currentIndex = index;
      _activeQuiz = null;
    });
    // Pin before any preload runs: preloading a neighbour refreshes that
    // neighbour's LRU timestamp, which would otherwise make the video the user
    // is watching the pool's next eviction candidate.
    _pinCurrentVideo();
    ref
        .read(mainControllerProvider)
        .updateCurrentVideoIndex(index, tabIndex: 1);
    _initializePlayer(index);

    _pageChangeDebounce?.cancel();
    _pageChangeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || index != _currentIndex) return;
      _startViewTracking(index);
      _reprimeWindowIfNeeded(index);
      _controllerPool.retainOnly(_keepAliveVideoIds(index - 1, index + 1));
      _cancelOffWindowPrefetches(index);
      _preloadNearbyVideos();
      if (_videos.length - index < 3) _loadMoreVideos();
    });
  }

  void _pinCurrentVideo() {
    if (_currentIndex < 0 || _currentIndex >= _videos.length) return;
    _controllerPool.pinVideo(
      _videos[_currentIndex].id,
      sessionId: _playbackSession.id,
    );
  }

  /// Video ids occupying positions [start, end] in the CURRENT list.
  ///
  /// Recomputed on every call: pagination and reordering invalidate stored
  /// positions, so the pool must never be handed cached indices.
  Set<String> _keepAliveVideoIds(int start, int end) {
    final ids = <String>{};
    for (int i = start; i <= end; i++) {
      if (i >= 0 && i < _videos.length) ids.add(_videos[i].id);
    }
    return ids;
  }

  /// Stops background downloads for everything outside the live window.
  ///
  /// Without this, prefetches started by the feed the user came from keep
  /// running and steal bandwidth from the video actually on screen — which is
  /// what makes a playing video buffer even though it is the only thing the
  /// user is watching.
  void _cancelOffWindowPrefetches(int index) {
    final keep = <String>{};
    for (int i = index - 1; i <= index + 1; i++) {
      if (i < 0 || i >= _videos.length) continue;
      final video = _videos[i];
      keep.addAll(cacheKeyUrlsFor(
        video,
        selectedLanguage: _selectedAudioLanguage[video.id],
      ));
    }
    try {
      videoCacheProxy.cancelAllPrefetchesExcept(keep.toList());
    } catch (e) {
      AppLogger.log('Prefetch cancellation skipped: $e');
    }
  }

  void _reprimeWindowIfNeeded(int current) {
    final keys =
        _controllers.keys.where((i) => (i - current).abs() > 1).toList();
    for (final i in keys) {
      _savePlaybackPosition(i);
      _detachControllerListeners(i);
      _controllerPool.disposeController(_videos[i].id);
      _controllers.remove(i);
    }
  }

  void _validateAndRestoreControllers() {
    if (_videos.isEmpty || !mounted) return;
    final indices = {
      _currentIndex,
      if (_currentIndex + 1 < _videos.length) _currentIndex + 1,
      if (_currentIndex - 1 >= 0) _currentIndex - 1
    };
    for (final idx in indices) {
      if (!_controllers.containsKey(idx) ||
          SharedVideoControllerPool().isControllerDisposed(_controllers[idx])) {
        _initializePlayer(idx);
      }
    }
  }

  void _preloadNearbyVideos() {
    if (_currentIndex + 1 < _videos.length) _preloadVideo(_currentIndex + 1);
    if (_currentIndex - 1 >= 0) _preloadVideo(_currentIndex - 1);
  }

  Future<void> _preloadVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;
    if (_controllers.containsKey(index)) return;

    final controller = await _acquireController(index);
    if (controller == null || !mounted) return;
    if (_isStaleRequest(index)) return;
    if (identical(_controllers[index], controller)) return;

    // The result has to reach the widget tree. Assigning the map without a
    // rebuild left the page rendering its loading state over a controller
    // that was ready — the "video keeps loading" symptom.
    setState(() => _controllers[index] = controller);
  }

  void _enableWakelock() {
    if (!_wakelockEnabled) {
      WakelockPlus.enable();
      _wakelockEnabled = true;
    }
  }

  void _disableWakelock() {
    if (_wakelockEnabled) {
      WakelockPlus.disable();
      _wakelockEnabled = false;
    }
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
        : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  /// Fetched once per screen. The per-index version this replaced hit a server
  /// health probe plus an ad request on every swipe.
  Future<void> _loadBannerAds() async {
    try {
      final ads = await _activeAdsService.fetchActiveAds();
      final List? banner = ads['banner'] as List?;
      if (!mounted || banner == null || banner.isEmpty) return;
      setState(() {
        _bannerAds = banner
            .map((ad) => Map<String, dynamic>.from(ad as Map))
            .toList(growable: false);
      });
    } catch (e) {
      AppLogger.log('Failed to load banner ads: $e');
    }
  }

  void _onLocalSmartDubTap(VideoModel video,
      [String targetLang = 'hindi']) async {
    setState(() => _isDubbingProgressVisible = true);
    final resultVN = _getOrCreateNotifier<DubbingResult>(_dubbingResultsVN,
        video.id, const DubbingResult(status: DubbingStatus.checking));
    _dubbingSubscriptions[video.id]?.cancel();
    _dubbingSubscriptions[video.id] = _dubbingService
        .dubVideo(video.id, video.videoUrl, targetLang: targetLang)
        .listen((r) {
      if (!mounted) return;
      resultVN.value = r;
      if (r.status == DubbingStatus.completed && r.dubbedUrl != null) {
        final vIdx = _videos.indexWhere((v) => v.id == video.id);
        if (vIdx != -1) {
          final dubbed =
              Map<String, String>.from(_videos[vIdx].dubbedUrls ?? {});
          dubbed[r.language ?? targetLang] = r.dubbedUrl!;
          final isCurrent = vIdx == _currentIndex;
          setState(() {
            _videos[vIdx] = _videos[vIdx].copyWith(dubbedUrls: dubbed);
            if (isCurrent) {
              _selectedAudioLanguage[video.id] = r.language ?? targetLang;
            }
          });
          if (isCurrent) _rebuildControllerForSource(video.id);
        }
      }
    });
  }

  ValueNotifier<T> _getOrCreateNotifier<T>(
      Map<String, ValueNotifier<T>> map, String key, T initial) {
    return map.putIfAbsent(key, () => ValueNotifier<T>(initial));
  }

  void _showLanguageSelector(BuildContext context, VideoModel video) {
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Audio',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildLanguageOption(context, video, 'Default', 'default'),
        _buildLanguageOption(context, video, 'English', 'english',
            available: video.dubbedUrls?.containsKey('english') ?? false),
        _buildLanguageOption(context, video, 'Hindi', 'hindi',
            available: video.dubbedUrls?.containsKey('hindi') ?? false),
      ]),
    );
  }

  Widget _buildLanguageOption(
      BuildContext context, VideoModel video, String title, String code,
      {bool available = true}) {
    final selected = _selectedAudioLanguage[video.id] ?? 'default';
    return ListTile(
      title: Text(title,
          style: AppTypography.bodyMedium.copyWith(
              color: selected == code
                  ? AppColors.primary
                  : AppColors.textPrimary)),
      trailing: selected == code
          ? const Icon(Icons.check, color: AppColors.primary)
          : (!available
              ? const Icon(Icons.psychology_outlined, size: 16)
              : null),
      onTap: () {
        Navigator.pop(context);
        if (available || code == 'default') {
          _handleLanguageSelection(video, code);
        } else {
          _onLocalSmartDubTap(video, code);
        }
      },
    );
  }

  void _handleLanguageSelection(VideoModel video, String code) {
    if (_selectedAudioLanguage[video.id] == code) return;
    setState(() => _selectedAudioLanguage[video.id] = code);
    _rebuildControllerForSource(video.id);
  }

  /// Rebuilds the controller for [videoId] against its current audio source.
  ///
  /// Switching language changes the URL, so the pooled controller and any
  /// in-flight request for it are both stale — dropping the request matters
  /// because `_acquireController` would otherwise hand back the request that
  /// is still fetching the previous language.
  void _rebuildControllerForSource(String videoId) {
    _controllerRequests.remove(videoId);
    _controllerPool.disposeController(videoId);
    final index = _videos.indexWhere((v) => v.id == videoId);
    if (index == -1) return;
    _detachControllerListeners(index);
    setState(() => _controllers.remove(index));
    if (index == _currentIndex) _initializePlayer(index);
  }

  void _showCancelDubbingDialog(String videoId) {
    VayuBottomSheet.show(
        context: context,
        title: 'Cancel Dubbing?',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Aap dubbing cancel karna chahte hain?'),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: AppButton(
                    onPressed: () => Navigator.pop(context),
                    label: 'Nahi',
                    variant: AppButtonVariant.secondary)),
            const SizedBox(width: 12),
            Expanded(
                child: AppButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final video = _videos.firstWhere((v) => v.id == videoId);
                      _dubbingService.cancelDubbing(videoId, video.videoUrl);
                      _dubbingSubscriptions[videoId]?.cancel();
                      _dubbingResultsVN[videoId]?.value =
                          const DubbingResult(status: DubbingStatus.idle);
                    },
                    label: 'Haan')),
          ]),
        ]));
  }

  Widget _buildScrubbingOverlay() {
    return ValueListenableBuilder<Duration>(
      valueListenable: scrubbingDeltaVN,
      builder: (context, delta, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: scrubbingTargetTimeVN,
          builder: (context, targetTime, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: isForwardVN,
              builder: (context, forward, _) {
                final seconds = delta.inSeconds.abs();
                final icon = forward
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded;
                return Align(
                  alignment:
                      forward ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            AppColors.surfaceSecondary.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon,
                                    color: AppColors.textPrimary, size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  '${seconds}s',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: AppTypography.weightSemiBold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDuration(targetTime),
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _sanitizeUrl(String url) {
    if (url.isEmpty) return url;
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) {
      return const AnnotatedRegion<SystemUiOverlayStyle>(
        value: _playerSystemUiOverlayStyle,
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: AppColors.backgroundPrimary,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }
    if (_isInPictureInPicture) return _buildPictureInPicturePlayer();
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final navigationBarInset = MediaQuery.viewPaddingOf(context).bottom;
    // Bottom nav visibility is applied BEFORE rotations start (see
    // _applyPlayerChrome) so the rotation animation lands on the final layout.
    // This flag only mirrors that state for the in-tree gradient below.
    final showBottomNav = !isLandscape && !_isFullScreenManual;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _playerSystemUiOverlayStyle,
      child: PopScope(
        canPop: !isLandscape,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && isLandscape) {
            _toggleFullScreen();
          } else if (didPop) {
            ref.read(mainControllerProvider).setBottomNavVisibility(true);
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Stack(children: [
            PageView.builder(
              controller: _pageController,
              physics: isScrollingLocked
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _videos.length,
              itemBuilder: (context, index) => _buildFeedItem(index),
            ),
            // Android draws its three-button controls over this area. A soft
            // gradient preserves icon contrast without looking like a separate
            // solid navigation bar, even while a bright frame is on screen.
            // Skipped when the app's bottom nav is visible — it provides the
            // bottom edge and the body no longer reaches the system inset.
            if (navigationBarInset > 0 && !showBottomNav)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: navigationBarInset + 28,
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x66000000),
                          Color(0xB3000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_hasSeenScrollHint)
              Positioned(
                  bottom: isLandscape ? 80 : 140,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                      child: AnimatedOpacity(
                          opacity: _showScrollHintOverlay ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 500),
                          child: Center(
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                      color: AppColors.overlayDark,
                                      borderRadius: BorderRadius.circular(30)),
                                  child: Text('Swipe up to watch more',
                                      style: AppTypography.titleLarge.copyWith(
                                          color: AppColors.textPrimary))))))),
          ]),
        ),
      ),
    );
  }

  Widget _buildFeedItem(int index) {
    final v = _videos[index];
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isPortrait = !isLandscape;

    return SafeArea(
        top: isPortrait,
        bottom: false,
        left: false,
        right: false,
        child: VayuFeedItem(
          key: ValueKey(v.id),
          index: index,
          video: v,
          controller: _controllers[index],
          isCurrent: index == _currentIndex,
          isFullScreenManual: _isFullScreenManual,
          showControlsVN: showControlsVN,
          isControlsLockedVN: isControlsLockedVN,
          showScrubbingOverlayVN: showScrubbingOverlayVN,
          isSeekingBufferingVN: isSeekingBufferingVN,
          onToggleFullScreen: _toggleFullScreen,
          pictureInPictureSourceKey:
              index == _currentIndex ? _pictureInPictureSourceKey : null,
          onOpenExternalPlayer: () => _openInExternalPlayer(v),
          onHandleTap: () => handleTap(MediaQuery.orientationOf(context)),
          onDoubleTapToSeek: (details) => handleDoubleTapToSeek(details,
              MediaQuery.sizeOf(context), MediaQuery.orientationOf(context)),
          onHorizontalDragEnd: handleHorizontalDragEnd,
          onVerticalDragUpdate: (dy, lp) =>
              handleVerticalDragUpdate(dy, lp, MediaQuery.sizeOf(context)),
          onVerticalDragEnd: () {},
          onUnifiedHorizontalDrag: handleUnifiedHorizontalDrag,
          onScrollingLock: (l) => isScrollingLockedVN.value = l,
          onShowSnackBar: _showSnackBar,
          buildAdSection: _buildAdSection,
          buildVideoInfo: (_) => const SizedBox.shrink(),
          buildChannelRow: (_) => const SizedBox.shrink(),
          buildScrubbingOverlay: _buildScrubbingOverlay,
          buildCustomControls: (_) => const SizedBox.shrink(),
          buildDubbingProgress: (_) => const SizedBox.shrink(),
          formatDuration: _formatDuration,
          onQuizDismiss: () => setState(() => _activeQuiz = null),
          activeQuiz: index == _currentIndex ? _activeQuiz : null,
          onResumeAfterSeek: () async {
            final controller = _controllers[index];
            if (controller != null) await _playIfAllowed(index, controller);
          },
          metadataSection: VayuMetadataSection(
              video: v,
              isPortrait: isPortrait,
              isLoading: _controllers[index] == null ||
                  !_controllers[index]!.value.isInitialized,
              onShare: () => _showShareOptions(v),
              onSave: () => _handleToggleSave(index),
              onVisitLink: () async {
                final enrichedUrl = UrlUtils.enrichUrl(_sanitizeUrl(v.link!),
                    medium: 'long_form_player', campaign: 'creator_visit');
                final u = Uri.parse(enrichedUrl);
                if (await canLaunchUrl(u)) {
                  launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              onMoreOptions: _showMoreOptions,
              onEpisodes: () => _showEpisodeList(context, v),
              onSuggestion: () => _showShareSuggestionBottomSheet(v),
              onShowError: (m) =>
                  _showSnackBar(m, type: VayuSnackBarType.error)),
          channelInfo: VayuChannelInfo(
            video: v,
            isPortrait: isPortrait,
            onProfileTap: () => _openUploaderProfile(v),
          ),
          playerOverlay: VayuPlayerOverlay(
              controller: _controllers[index],
              showControlsVN: showControlsVN,
              isControlsLockedVN: isControlsLockedVN,
              isPortrait: isPortrait,
              isFullScreenManual: _isFullScreenManual,
              onTogglePlay: togglePlay,
              onMoreOptions: _showMoreOptions,
              onNext: _nextVideo,
              onPrevious: _previousVideo),
          dubbingOverlay: _buildDubbingOverlay(index),
        ));
  }

  Widget _buildPictureInPicturePlayer() {
    final controller = currentVideoController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: controller != null && controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                  aspectRatio: _pictureInPictureAspectRatio(controller),
                  child: VideoPlayer(controller)))
          : const ColoredBox(color: Colors.black),
    );
  }

  Widget _buildDubbingOverlay(int index) {
    if (!_isDubbingProgressVisible) return const SizedBox.shrink();
    return ValueListenableBuilder<DubbingResult>(
      valueListenable: _getOrCreateNotifier(_dubbingResultsVN,
          _videos[index].id, const DubbingResult(status: DubbingStatus.idle)),
      builder: (context, r, _) => VayuDubbingStatusOverlay(
          result: r,
          isVisible: _isDubbingProgressVisible,
          onCancel: () => _showCancelDubbingDialog(_videos[index].id),
          onHide: () => setState(() => _isDubbingProgressVisible = false)),
    );
  }

  Widget _buildAdSection(int index) {
    if (_bannerAds.isEmpty) return const SizedBox.shrink();
    final ad = _bannerAds[index % _bannerAds.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: BannerAdSection(
        adData: {
          ...ad,
          'creatorId': _videos[index].uploader.id,
          'videoId': _videos[index].id,
        },
        adService: _activeAdsService,
        onVideoPause: () => _controllers[index]?.pause(),
        onVideoResume: () {
          final controller = _controllers[index];
          if (controller != null) {
            _playIfAllowed(index, controller);
          }
        },
        onImpression: () async {},
      ),
    );
  }

  Future<void> _openUploaderProfile(VideoModel video) async {
    _pauseAllPlayback();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: video.uploader.id),
      ),
    );
  }
}
