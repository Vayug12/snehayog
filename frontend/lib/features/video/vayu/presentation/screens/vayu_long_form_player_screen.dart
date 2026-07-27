import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
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
import 'package:vayug/shared/widgets/share_options_sheet.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/shared/navigation/app_route_observer.dart';
import 'package:vayug/shared/services/playback_coordinator.dart';

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
  ConsumerState<VayuLongFormPlayerScreen> createState() => _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState extends ConsumerState<VayuLongFormPlayerScreen> with WidgetsBindingObserver, RouteAware, VayuPlayerGesturesMixin {

  static const _playerSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    // The player draws its own subtle protection behind this transparent bar.
    // This keeps the navigation buttons integrated with the current screen.
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  );

    @override
  VideoPlayerController? get currentVideoController => _controllers[_currentIndex];

  // Video Feed State
  final List<VideoModel> _videos = [];
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, ChewieController?> _chewieControllers = {};
  final Map<int, VoidCallback> _positionListeners = {};
  final Set<int> _preloadingIndices = {};

  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  final VideoService _videoService = VideoService();

  // Unified Controller Management
  final VideoControllerManager _videoControllerManager = VideoControllerManager();
  final SharedVideoControllerPool _controllerPool = SharedVideoControllerPool();
  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();
  late final PlaybackSession _playbackSession =
      _playbackCoordinator.register(source: 'vayu-long-form');
  MainController? _mainController;
  bool _lifecyclePaused = false;
  int? _resolvedParentTabIndex;
  ModalRoute<dynamic>? _observedRoute;

  // Banner Ad State
  late final IAdService _activeAdsService;
  final Map<int, Map<String, dynamic>> _bannerAdsByIndex = {};
  late final IQuizEngine _quizEngine;


  SharedPreferences? _prefs;
  String? _currentUserId;

  bool _isSaving = false;
  double _playbackSpeed = 1.0;
  final List<double> _playbackSpeedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  
  bool _wakelockEnabled = false;
  bool _isFullScreenManual = false;
  final ValueNotifier<bool> _suppressTransientPauseOverlayVN = ValueNotifier<bool>(false);
  Timer? _orientationSettleTimer;
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
    _resolvedParentTabIndex =
        widget.parentTabIndex ?? _mainController?.playbackActiveTabIndex;
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
          _initializePlayer(initialIdx);
        } else {
          final mainController = ref.read(mainControllerProvider);
          final lastIndex = await mainController.getLastViewedVideoIndex(1);
          if (lastIndex > 0 && lastIndex < _videos.length) {
            _currentIndex = lastIndex;
            _pageController.jumpToPage(lastIndex);
            _initializePlayer(lastIndex);
          } else {
            _initializePlayer(0);
          }
        }
        _preloadNearbyVideos();
        _reprimeWindowIfNeeded(_currentIndex);
      }
    });

    if (_videos.length < 3) {
      _loadMoreVideos();
    }

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mainController = ref.read(mainControllerProvider);
        _mainController?.registerVideoObserver(
          onPause: _pauseCurrentVideo,
          onResume: _resumeCurrentVideo,
        );
        _mainController?.forcePauseVideos();
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

    _poolDisposalSubscription = SharedVideoControllerPool().disposalStream.listen((videoId) {
      if (mounted) {
        final index = _videos.indexWhere((v) => v.id == videoId);
        if (index != -1 && _controllers.containsKey(index)) {
          final oldC = _controllers[index];
          if (oldC != null) {
            final listener = _positionListeners.remove(index);
            if (listener != null) {
              try { oldC.removeListener(listener); } catch (_) {}
            }
          }
          setState(() {
            _controllers.remove(index);
            _chewieControllers.remove(index)?.dispose();
          });
          if (index == _currentIndex) {
            _initializePlayer(index);
          }
        }
      }
    });

    isSeekingBufferingVN.addListener(_onSeekingBufferingChanged);
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
    _mainController = ref.watch(mainControllerProvider);
    final authController = ref.watch(googleSignInProvider);
    if (authController.isSignedIn && authController.userData != null) {
      final userId = authController.userData!['googleId'] ?? authController.userData!['id'];
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
    final physicalSize = WidgetsBinding.instance.platformDispatcher.implicitView?.physicalSize;
    if (physicalSize == null || physicalSize.isEmpty) return;
    final orientation = physicalSize.width > physicalSize.height ? Orientation.landscape : Orientation.portrait;
    if (orientation == _lastChromeOrientation) return;
    _lastChromeOrientation = orientation;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) return;
    final isLandscape = orientation == Orientation.landscape;
    _markOrientationTransition();
    _applyPlayerChrome(
      fullscreen: isLandscape || _isFullScreenManual,
      immersive: isLandscape,
    );
  }

  void _handleAppMovedToBackground() {
    _lifecyclePaused = true;
    _pauseAllPlayback();
  }

  void _handleAppResumed() {
    _lifecyclePaused = false;
    _resumeCurrentVideo();
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final controller = _controllers[_currentIndex];
      if (controller != null) {
        try { if (controller.value.isPlaying) controller.pause(); } catch (_) {}
      }
    }
  }

  void _pauseAllPlayback() {
    _playbackCoordinator.pause(_playbackSession);
    _pauseCurrentVideo();
    _videoControllerManager.pauseAllVideos();
    _controllerPool.pauseAllControllers();
    _disableWakelock();
  }

  bool _isPlayerRouteActive() => ModalRoute.of(context)?.isCurrent ?? false;

  bool _isParentTabActive() {
    // A pushed player is owned by its route. The originating bottom-tab index
    // is metadata only and must not block profile/search/deep-link playback.
    return _isPlayerRouteActive();
  }

  /// This is the sole permission check for starting Vayu playback.
  bool _canPlayCurrentVideo(int index, VideoPlayerController controller) {
    return mounted &&
        !_lifecyclePaused &&
        _isPlayerRouteActive() &&
        _isParentTabActive() &&
        index == _currentIndex &&
        identical(_controllers[index], controller);
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
    final hasSeenHint = _prefs!.getBool('has_seen_vayu_long_form_scroll_hint') ?? false;
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
      await _pageController.animateTo(targetOffset, duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;
      await _pageController.animateTo(0, duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
    } catch (e) { AppLogger.log('Error scroll hint: $e'); }
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
      final response = await _videoService.getVideos(page: _currentPage, videoType: 'vayu', clearSession: false, random: true);
      List<VideoModel> newVideos = [];
      final List? videosList = response['videos'] ?? response['data'];
      if (videosList != null) {
        newVideos = videosList.map((v) => VideoModel.fromJson(Map<String, dynamic>.from(v))).toList();
        newVideos.shuffle();
      }
      if (newVideos.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        final existingIds = _videos.map((v) => v.id).toSet();
        newVideos.removeWhere((v) => existingIds.contains(v.id));
        if (mounted) {
          setState(() { _videos.addAll(newVideos); _currentPage++; _hasMore = response['hasMore'] as bool? ?? true; });
          if (_currentIndex + 1 < _videos.length) _preloadNearbyVideos();
        }
      }
    } catch (e) { AppLogger.log('Error loading more: $e'); }
    finally { if (mounted) setState(() => _isLoadingMore = false); }
  }

  Future<void> _initializePlayer([int? requestedIndex]) async {
    final index = requestedIndex ?? _currentIndex;
    if (index >= _videos.length) return;
    final videoToPlay = _videos[index];
    VideoPlayerController? existing = _controllerPool.getController(videoToPlay.id);

    if (existing != null && existing.value.isInitialized) {
      if (mounted) {
        setState(() {
          _controllers[index] = existing;
          _chewieControllers[index]?.dispose();
          _chewieControllers[index] = _createChewieController(existing, videoToPlay);
        });
        _setupLateInitialization(index, existing);
      }
      return;
    }
    if (_controllers.containsKey(index)) {
      final c = _controllers.remove(index);
      final ch = _chewieControllers.remove(index);
      ch?.dispose();
      if (c != null) {
        final listener = _positionListeners.remove(index);
        if (listener != null) c.removeListener(listener);
        _controllerPool.disposeController(videoToPlay.id);
      }
    }
    _disableWakelock();
    try {
      final selectedLang = _selectedAudioLanguage[videoToPlay.id] ?? 'default';
      VideoModel effectiveVideo = videoToPlay;
      if (selectedLang != 'default') {
        final dubbedUrl = videoToPlay.dubbedUrls?[selectedLang];
        if (dubbedUrl != null) effectiveVideo = videoToPlay.copyWith(videoUrl: dubbedUrl);
      }
      await _controllerPool.makeRoomForNewController();
      final newController = await VideoControllerFactory.createController(effectiveVideo);
      await newController.initialize().timeout(const Duration(seconds: 15));
      await newController.setPlaybackSpeed(_playbackSpeed);
      // Chewie must never own autoplay: its delayed play callback can fire
      // after the user has already scrolled to a different page.
      await newController.pause();
      if (mounted) {
        final chewie = _createChewieController(newController, effectiveVideo);
        setState(() { _controllers[index] = newController; _chewieControllers[index] = chewie; });
        _playbackCoordinator.attachController(_playbackSession, newController);
        _controllerPool.addController(videoToPlay.id, newController, index: index);
        _setupLateInitialization(index, newController);
      } else {
        newController.dispose();
      }
    } catch (e) { AppLogger.log('Failed to init: $e'); }
  }

  ChewieController _createChewieController(VideoPlayerController controller, VideoModel video) {
    return ChewieController(
      videoPlayerController: controller,
      aspectRatio: 16 / 9,
      autoPlay: false,
      showControls: false,
      customControls: const SizedBox.shrink(),
      materialProgressColors: ChewieProgressColors(playedColor: AppColors.primary, handleColor: AppColors.primary, backgroundColor: AppColors.borderPrimary, bufferedColor: AppColors.textTertiary),
      placeholder: video.thumbnailUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: video.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(color: AppColors.backgroundPrimary),
            )
          : Container(color: AppColors.backgroundPrimary),
    );
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
    final previousPositionListener = _positionListeners.remove(index);
    if (previousPositionListener != null) {
      controller.removeListener(previousPositionListener);
    }
    void positionListener() => _handleControllerPositionChanged(index, controller);
    _positionListeners[index] = positionListener;
    controller.addListener(positionListener);
    if (_errorListeners.containsKey(index)) controller.removeListener(_errorListeners[index]!);
    _errorListeners[index] = () => _handleVideoError(index, controller);
    controller.addListener(_errorListeners[index]!);
    if (!_isCurrentPlaybackTarget(index, controller)) {
      await controller.pause();
      return;
    }

    final didApplySharedPosition = await _applyInitialSharePosition(index, controller);
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
    try { brightnessValue = await ScreenBrightness().application; final vol = await FlutterVolumeController.getVolume(); if (vol != null) volumeValue = vol; } catch (_) {}
  }

  void _handleControllerPositionChanged(
    int index,
    VideoPlayerController controller,
  ) {
    if (!_isCurrentPlaybackTarget(index, controller)) {
      if (controller.value.isPlaying) {
        unawaited(controller.pause());
      }
      return;
    }
    if (isSeekingBufferingVN.value && controller.value.isPlaying) {
      isSeekingBufferingVN.value = false;
    }
    _onPositionChanged();
  }

  Future<bool> _applyInitialSharePosition(
    int index,
    VideoPlayerController controller,
  ) async {
    final initialPosition = widget.initialPosition;
    if (index != 0 || initialPosition == null || _hasAppliedInitialSharePosition || !_isCurrentPlaybackTarget(index, controller)) {
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

  void _handleVideoError(int index, VideoPlayerController controller) {
    if (!mounted) return;
    try {
      if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
      if (controller.value.hasError) {
        if (index == _currentIndex) _initializePlayer(index);
      }
    } catch (_) {}
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final controller = _controllers[_currentIndex];
    if (controller == null) return;
    final currentPos = controller.value.position;
    final lastPos = _lastKnownPositions[_currentIndex] ?? Duration.zero;
    if (currentPos < lastPos && lastPos.inSeconds > 1) {
      _stopViewTracking(_currentIndex); _startViewTracking(_currentIndex);
    }
    _lastKnownPositions[_currentIndex] = currentPos;
    _pauseAtSharedSectionEnd(controller, currentPos);
    if (controller.value.isPlaying && currentPos.inSeconds % 5 == 0) _savePlaybackPosition(_currentIndex);
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
    _playbackCoordinator.release(_playbackSession);
    _disableWakelock();
    appRouteObserver.unsubscribe(this);
    _seekingBufferingTimeout?.cancel();
    isSeekingBufferingVN.removeListener(_onSeekingBufferingChanged);
    disposeGestures();
    _suppressTransientPauseOverlayVN.dispose();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mainController?.unregisterVideoObserver(onPause: _pauseCurrentVideo, onResume: _resumeCurrentVideo);
    try { _mainController?.unregisterCallbacks(); } catch (_) {}
    _savePlaybackPosition(_currentIndex);
    
    // **CRITICAL FIX**: Explicitly tell the shared pool to pause all videos before we lose references.
    _controllerPool.pauseAllControllers();
    _videoControllerManager.pauseAllVideos();
    
    _controllers.forEach((index, c) {
      try {
        final listener = _positionListeners.remove(index);
        if (listener != null) c.removeListener(listener);
        c.pause();
        c.setVolume(0.0);
      } catch (_) {}
    });
    _chewieControllers.forEach((index, c) => c?.dispose());
    controlsTimer?.cancel(); overlayTimer?.cancel(); _orientationSettleTimer?.cancel(); _seekingBufferingTimeout?.cancel();
    _stopViewTracking(_currentIndex); _poolDisposalSubscription?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Future.microtask(() { if (context.mounted) ref.read(mainControllerProvider).setBottomNavVisibility(true); });
    super.dispose();
  }

  void _startViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    _viewTracker.startViewTracking(video.id, videoUploaderId: video.uploader.id, videoHash: video.videoHash);
    _viewUITimers[index]?.cancel();
    _viewUITimers[index] = Timer(const Duration(seconds: 3), () {
      if (mounted && _currentIndex == index) {
        setState(() { _videos[index] = _videos[index].copyWith(views: _videos[index].views + 1); });
      }
    });
  }

  void _stopViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    _viewUITimers[index]?.cancel(); _viewUITimers.remove(index);
    _viewTracker.stopViewTracking(_videos[index].id);
  }



  void _savePlaybackPosition(int index) async {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt('video_pos_${_videos[index].id}', controller.value.position.inSeconds);
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



  void _showSnackBar(String message, {Duration? duration, VayuSnackBarType type = VayuSnackBarType.info}) {
    if (!mounted) return;
    VayuSnackBar.show(context, message, duration: duration ?? const Duration(seconds: 3), type: type);
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
                width: 100, height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: ep['thumbnailUrl'] != null 
                    ? DecorationImage(image: CachedNetworkImageProvider(ep['thumbnailUrl']), fit: BoxFit.cover) 
                    : null,
                  color: AppColors.textTertiary.withValues(alpha: 0.05),
                ),
                child: isCurrent 
                  ? Container(
                      decoration: BoxDecoration(color: AppColors.overlayDark, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 28)
                    ) 
                  : null,
              ),
              title: Text(
                ep['videoName'] ?? 'Episode ${index + 1}', 
                maxLines: 2, 
                overflow: TextOverflow.ellipsis, 
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, 
                  color: isCurrent ? AppColors.primary : AppColors.textPrimary
                )
              ),
              subtitle: ep['duration'] != null 
                ? Text(_formatDuration(Duration(seconds: (ep['duration'] as num).toInt())), style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)) 
                : null,
              onTap: () {
                Navigator.pop(context);
                if (!isCurrent) {
                  final epId = ep['id'] ?? ep['_id'];
                  if (epId != null) {
                    final targetIndex = _videos.indexWhere((v) => v.id == epId);
                    if (targetIndex != -1) _pageController.animateToPage(targetIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
    final userId = authState.userData?['googleId'] ?? authState.userData?['id'] ?? 'anonymous';

    VayuBottomSheet.show<void>(
      context: context, 
      title: 'Share Suggestion',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Did you face any problem while watching this video? share with us', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller, 
              maxLines: 4, 
              decoration: InputDecoration(
                hintText: 'Type here...', 
                filled: true, 
                fillColor: AppColors.backgroundSecondary, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
              )
            ),
            const SizedBox(height: 20),
            AppButton(
              onPressed: () async {
                final suggestionText = controller.text.trim();
                if (suggestionText.isEmpty) {
                  _showSnackBar('Please type something', type: VayuSnackBarType.error);
                  return;
                }
                
                Navigator.pop(context);
                _showSnackBar('Submitting suggestion...');

                try {
                  final response = await _videoService.httpClientService.post(
                    Uri.parse('${NetworkHelper.apiBaseUrl}/feedback/submit'),
                    body: {
                      'type': 'suggestion',
                      'comments': suggestionText,
                      'userEmail': userEmail,
                      'userId': userId,
                      'videoId': video.id,
                      'rating': 5, // Default rating for suggestions
                    },
                  );

                  if (response.statusCode == 201) {
                    _showSnackBar('Suggestion shared! Thank you.', type: VayuSnackBarType.success);
                  } else {
                    _showSnackBar('Failed to share suggestion', type: VayuSnackBarType.error);
                  }
                } catch (e) {
                  AppLogger.error('Error submitting suggestion', e);
                  _showSnackBar('Network error. Try again later.', type: VayuSnackBarType.error);
                }
              }, 
              label: 'Share Suggestion'
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExternalPlayer(VideoModel video) async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final intent = AndroidIntent(action: 'action_view', data: video.videoUrl, type: 'video/*', flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK]);
      try { await intent.launch(); } catch (e) { _showSnackBar('No external player found', type: VayuSnackBarType.error); }
    } else {
      final url = Uri.parse(video.videoUrl);
      if (await canLaunchUrl(url)) { await launchUrl(url, mode: LaunchMode.externalApplication); }
    }
  }

  Future<void> _handleToggleSave([int? requestedIndex]) async {
    if (_isSaving) return;
    final index = requestedIndex ?? _currentIndex;
    final video = _videos[index];
    try {
      setState(() => _isSaving = true); HapticFeedback.lightImpact();
      final isSaved = await _videoService.toggleSave(video.id);
      setState(() { video.isSaved = isSaved; _isSaving = false; });
      _showSnackBar(isSaved ? 'Saved' : 'Removed', type: isSaved ? VayuSnackBarType.success : VayuSnackBarType.info);
    } catch (e) { setState(() => _isSaving = false); }
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

  void _nextVideo() { if (_currentIndex < _videos.length - 1) _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }
  void _previousVideo() { if (_currentIndex > 0) _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }

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

  void _markOrientationTransition() {
    _orientationSettleTimer?.cancel();
    _suppressTransientPauseOverlayVN.value = true;
    _orientationSettleTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _suppressTransientPauseOverlayVN.value = false;
    });
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
    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final controller = _controllers[_currentIndex];

    // Capture exact position before orientation change
    if (controller != null) {
      _lastKnownPositions[_currentIndex] = controller.value.position;
    }

    final aspectRatio = controller?.value.aspectRatio ?? 1.0;
    if (aspectRatio < 1.0) {
      // Vertical video: manual fullscreen, no rotation involved.
      _markOrientationTransition();
      setState(() => _isFullScreenManual = !_isFullScreenManual);
      _applyPlayerChrome(fullscreen: _isFullScreenManual, immersive: false);
      showControlsVN.value = true;
      startHideControlsTimer(Orientation.portrait);
    } else {
      final goingLandscape = isPortrait;
      _markOrientationTransition();
      _isFullScreenManual = false;
      _lastChromeOrientation = goingLandscape ? Orientation.landscape : Orientation.portrait;
      _applyPlayerChrome(fullscreen: goingLandscape, immersive: goingLandscape);
      // ValueNotifier update — no setState here. The orientation change itself
      // drives the single rebuild; an extra setState now would paint an
      // intermediate frame with the new state but the old orientation.
      showControlsVN.value = true;
      SystemChrome.setPreferredOrientations(goingLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
      startHideControlsTimer(goingLandscape ? Orientation.landscape : Orientation.portrait);
    }
  }

  Future<void> _showMoreOptions() async {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    VayuBottomSheet.show<void>(
      context: context, title: 'More Options',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(dense: true, leading: const Icon(Icons.speed_rounded), title: const Text('Playback Speed'), trailing: Text('${_playbackSpeed}x'), onTap: () { Navigator.pop(context); _showPlaybackSpeedOptions(); }),
          if (_currentIndex < _videos.length) ListTile(dense: true, leading: const Icon(Icons.language_rounded), title: const Text('Audio Language'), onTap: () { Navigator.pop(context); _showLanguageSelector(context, _videos[_currentIndex]); }),
          ListTile(dense: true, leading: Icon(isControlsLockedVN.value ? Icons.lock_rounded : Icons.lock_open_rounded), title: Text(isControlsLockedVN.value ? 'Unlock' : 'Lock'), onTap: () { Navigator.pop(context); isControlsLockedVN.value = !isControlsLockedVN.value; }),
          ListTile(dense: true, leading: const Icon(Icons.report_problem_rounded), title: const Text('Report'), onTap: () { Navigator.pop(context); _openReportDialog(); }),
        ],
      ),
    );
  }

  void _openReportDialog() {
    VayuBottomSheet.show(context: context, title: 'Report', child: ReportDialogWidget(targetType: 'video', targetId: _videos[_currentIndex].id));
  }

  Future<void> _showPlaybackSpeedOptions() async {
    VayuBottomSheet.show<void>(
      context: context, title: 'Speed',
      child: Column(mainAxisSize: MainAxisSize.min, children: _playbackSpeedOptions.map((s) => ListTile(title: Text('${s}x', style: AppTypography.bodyMedium.copyWith(color: s == _playbackSpeed ? AppColors.primary : AppColors.textPrimary)), onTap: () { Navigator.pop(context); _setPlaybackSpeed(s); })).toList()),
    );
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    final oldVideoId = _videos[_currentIndex].id;
    _quizEngine.reset(oldVideoId);
    // Stop every pooled controller before switching the active index. This
    // covers a controller that finished buffering after the previous swipe.
    _controllerPool.pauseAllControllers();
    _pauseCurrentVideo(); _reprimeWindowIfNeeded(index); _stopViewTracking(_currentIndex);
    setState(() {
      _currentIndex = index;
      _activeQuiz = null;
    });
    ref.read(mainControllerProvider).updateCurrentVideoIndex(index, tabIndex: 1);
    _startViewTracking(index); _preloadNearbyVideos(); _initializePlayer(index); _loadBannerAd(index);
    if (_videos.length - index < 3) _loadMoreVideos();
  }

  void _reprimeWindowIfNeeded(int current) {
    final keys = _controllers.keys.where((i) => (i - current).abs() > 1).toList();
    for (final i in keys) { _savePlaybackPosition(i); _controllerPool.disposeController(_videos[i].id); _controllers.remove(i); _chewieControllers.remove(i)?.dispose(); }
  }

  void _validateAndRestoreControllers() {
    if (_videos.isEmpty || !mounted) return;
    final indices = {_currentIndex, if (_currentIndex + 1 < _videos.length) _currentIndex + 1, if (_currentIndex - 1 >= 0) _currentIndex - 1};
    for (final idx in indices) { if (!_controllers.containsKey(idx) || SharedVideoControllerPool().isControllerDisposed(_controllers[idx])) _initializePlayer(idx); }
  }

  void _preloadNearbyVideos() {
    if (_currentIndex + 1 < _videos.length) _preloadVideo(_currentIndex + 1);
    if (_currentIndex - 1 >= 0) _preloadVideo(_currentIndex - 1);
  }

  Future<void> _preloadVideo(int index) async {
    if (index < 0 || index >= _videos.length || _controllers.containsKey(index) || _preloadingIndices.contains(index)) return;
    
    _preloadingIndices.add(index);
    try {
      final c = await VideoControllerFactory.createController(_videos[index]);
      await c.initialize();
      await c.pause();
      _controllers[index] = c;
      _controllerPool.addController(_videos[index].id, c, index: index);
    } catch (_) {
    } finally {
      _preloadingIndices.remove(index);
    }
  }

  void _enableWakelock() { if (!_wakelockEnabled) { WakelockPlus.enable(); _wakelockEnabled = true; } }
  void _disableWakelock() { if (_wakelockEnabled) { WakelockPlus.disable(); _wakelockEnabled = false; } }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}' : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  Future<void> _loadBannerAd(int index) async {
    if (_bannerAdsByIndex.containsKey(index)) return;
    try {
      final ads = await _activeAdsService.fetchActiveAds();
      final List? banner = ads['banner'] as List?;
      if (mounted && banner != null && banner.isNotEmpty) {
        setState(() => _bannerAdsByIndex[index] = Map<String, dynamic>.from(banner[index % banner.length]));
      }
    } catch (_) {}
  }

  void _onLocalSmartDubTap(VideoModel video, [String targetLang = 'hindi']) async {
    setState(() => _isDubbingProgressVisible = true);
    final resultVN = _getOrCreateNotifier<DubbingResult>(_dubbingResultsVN, video.id, const DubbingResult(status: DubbingStatus.checking));
    _dubbingSubscriptions[video.id]?.cancel();
    _dubbingSubscriptions[video.id] = _dubbingService.dubVideo(video.id, video.videoUrl, targetLang: targetLang).listen((r) {
      if (!mounted) return;
      resultVN.value = r;
      if (r.status == DubbingStatus.completed && r.dubbedUrl != null) {
        final vIdx = _videos.indexWhere((v) => v.id == video.id);
        if (vIdx != -1) {
          final dubbed = Map<String, String>.from(_videos[vIdx].dubbedUrls ?? {});
          dubbed[r.language ?? targetLang] = r.dubbedUrl!;
          setState(() { _videos[vIdx] = _videos[vIdx].copyWith(dubbedUrls: dubbed); if (vIdx == _currentIndex) { _selectedAudioLanguage[video.id] = r.language ?? targetLang; _controllerPool.disposeController(video.id); _initializePlayer(_currentIndex); } });
        }
      }
    });
  }

  ValueNotifier<T> _getOrCreateNotifier<T>(Map<String, ValueNotifier<T>> map, String key, T initial) {
    return map.putIfAbsent(key, () => ValueNotifier<T>(initial));
  }

  void _showLanguageSelector(BuildContext context, VideoModel video) {
    VayuBottomSheet.show<void>(
      context: context, title: 'Audio',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildLanguageOption(context, video, 'Default', 'default'),
        _buildLanguageOption(context, video, 'English', 'english', available: video.dubbedUrls?.containsKey('english') ?? false),
        _buildLanguageOption(context, video, 'Hindi', 'hindi', available: video.dubbedUrls?.containsKey('hindi') ?? false),
      ]),
    );
  }

  Widget _buildLanguageOption(BuildContext context, VideoModel video, String title, String code, {bool available = true}) {
    final selected = _selectedAudioLanguage[video.id] ?? 'default';
    return ListTile(
      title: Text(title, style: AppTypography.bodyMedium.copyWith(color: selected == code ? AppColors.primary : AppColors.textPrimary)),
      trailing: selected == code ? const Icon(Icons.check, color: AppColors.primary) : (!available ? const Icon(Icons.psychology_outlined, size: 16) : null),
      onTap: () { Navigator.pop(context); if (available || code == 'default') { _handleLanguageSelection(video, code); } else { _onLocalSmartDubTap(video, code); } },
    );
  }

  void _handleLanguageSelection(VideoModel video, String code) {
    if (_selectedAudioLanguage[video.id] == code) return;
    _controllerPool.disposeController(video.id);
    setState(() { _selectedAudioLanguage[video.id] = code; _initializePlayer(_currentIndex); });
  }

  void _showCancelDubbingDialog(String videoId) {
    VayuBottomSheet.show(context: context, title: 'Cancel Dubbing?', child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Aap dubbing cancel karna chahte hain?'),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: AppButton(onPressed: () => Navigator.pop(context), label: 'Nahi', variant: AppButtonVariant.secondary)),
        const SizedBox(width: 12),
        Expanded(child: AppButton(onPressed: () {
          Navigator.pop(context);
          final video = _videos.firstWhere((v) => v.id == videoId);
          _dubbingService.cancelDubbing(videoId, video.videoUrl);
          _dubbingSubscriptions[videoId]?.cancel();
          _dubbingResultsVN[videoId]?.value = const DubbingResult(status: DubbingStatus.idle);
        }, label: 'Haan')),
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
                  alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSecondary.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.borderPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, color: AppColors.textPrimary, size: 18),
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
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
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
          if (!didPop && isLandscape) { _toggleFullScreen(); }
          else if (didPop) { ref.read(mainControllerProvider).setBottomNavVisibility(true); }
        },
        child: Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: Stack(children: [
            PageView.builder(
              controller: _pageController,
              physics: isScrollingLocked ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
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
            if (!_hasSeenScrollHint) Positioned(bottom: isLandscape ? 80 : 140, left: 0, right: 0, child: IgnorePointer(child: AnimatedOpacity(opacity: _showScrollHintOverlay ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: AppColors.overlayDark, borderRadius: BorderRadius.circular(30)), child: Text('Swipe up to watch more', style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary))))))),
          ]),
        ),
      ),
    );
  }

  Widget _buildFeedItem(int index) {
    final v = _videos[index];
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final isPortrait = !isLandscape;

    return SafeArea(
      top: isPortrait, bottom: false, left: false, right: false,
      child: VayuFeedItem(
      key: ValueKey(v.id),
      index: index, video: v, controller: _controllers[index], chewie: _chewieControllers[index], isCurrent: index == _currentIndex, isFullScreenManual: _isFullScreenManual, suppressTransientPauseOverlayVN: _suppressTransientPauseOverlayVN, showControlsVN: showControlsVN, isControlsLockedVN: isControlsLockedVN, showScrubbingOverlayVN: showScrubbingOverlayVN, isSeekingBufferingVN: isSeekingBufferingVN,
      onToggleFullScreen: _toggleFullScreen, onOpenExternalPlayer: () => _openInExternalPlayer(v), onHandleTap: () => handleTap(MediaQuery.orientationOf(context)), onDoubleTapToSeek: (details) => handleDoubleTapToSeek(details, MediaQuery.sizeOf(context), MediaQuery.orientationOf(context)), onHorizontalDragEnd: handleHorizontalDragEnd, onVerticalDragUpdate: (dy, lp) => handleVerticalDragUpdate(dy, lp, MediaQuery.sizeOf(context)), onVerticalDragEnd: () {}, onUnifiedHorizontalDrag: handleUnifiedHorizontalDrag,
      onScrollingLock: (l) => isScrollingLockedVN.value = l, onShowSnackBar: _showSnackBar, buildAdSection: _buildAdSection, buildVideoInfo: (_) => const SizedBox.shrink(), buildChannelRow: (_) => const SizedBox.shrink(), buildScrubbingOverlay: _buildScrubbingOverlay, buildCustomControls: (_) => const SizedBox.shrink(), buildDubbingProgress: (_) => const SizedBox.shrink(), formatDuration: _formatDuration, onQuizDismiss: () => setState(() => _activeQuiz = null), activeQuiz: index == _currentIndex ? _activeQuiz : null,
      onResumeAfterSeek: () async {
        final controller = _controllers[index];
        if (controller != null) await _playIfAllowed(index, controller);
      },
      metadataSection: VayuMetadataSection(video: v, isPortrait: isPortrait, isLoading: _controllers[index] == null || !_controllers[index]!.value.isInitialized, onShare: () => _showShareOptions(v), onSave: () => _handleToggleSave(index), onVisitLink: () async { final enrichedUrl = UrlUtils.enrichUrl(_sanitizeUrl(v.link!), medium: 'long_form_player', campaign: 'creator_visit'); final u = Uri.parse(enrichedUrl); if (await canLaunchUrl(u)) launchUrl(u, mode: LaunchMode.externalApplication); }, onMoreOptions: _showMoreOptions, onEpisodes: () => _showEpisodeList(context, v), onSuggestion: () => _showShareSuggestionBottomSheet(v), onShowError: (m) => _showSnackBar(m, type: VayuSnackBarType.error)),
      channelInfo: VayuChannelInfo(
        video: v,
        isPortrait: isPortrait,
        onProfileTap: () => _openUploaderProfile(v),
      ),
      playerOverlay: VayuPlayerOverlay(controller: _controllers[index], showControlsVN: showControlsVN, isControlsLockedVN: isControlsLockedVN, isPortrait: isPortrait, isFullScreenManual: _isFullScreenManual, onTogglePlay: togglePlay, onMoreOptions: _showMoreOptions, onNext: _nextVideo, onPrevious: _previousVideo),
      dubbingOverlay: _buildDubbingOverlay(index),
    ));
  }

  Widget _buildDubbingOverlay(int index) {
    if (!_isDubbingProgressVisible) return const SizedBox.shrink();
    return ValueListenableBuilder<DubbingResult>(
      valueListenable: _getOrCreateNotifier(_dubbingResultsVN, _videos[index].id, const DubbingResult(status: DubbingStatus.idle)),
      builder: (context, r, _) => VayuDubbingStatusOverlay(result: r, isVisible: _isDubbingProgressVisible, onCancel: () => _showCancelDubbingDialog(_videos[index].id), onHide: () => setState(() => _isDubbingProgressVisible = false)),
    );
  }

  Widget _buildAdSection(int index) {
    final ad = _bannerAdsByIndex[index];
    if (ad == null) return const SizedBox.shrink();
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
