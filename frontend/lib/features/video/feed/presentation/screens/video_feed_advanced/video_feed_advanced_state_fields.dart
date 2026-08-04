part of '../video_feed_advanced.dart';

mixin VideoFeedStateFieldsMixin on ConsumerState<VideoFeedAdvanced> {
  /// Called by the coordinator when this feed becomes / stops being the one
  /// surface allowed to play. Implemented by the state class.
  void onPlaybackActivated();
  void onPlaybackDeactivated();

  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();
  late final PlaybackSession _playbackSession = _playbackCoordinator.register(
    source: 'video-feed',
    onActivate: onPlaybackActivated,
    onDeactivate: onPlaybackDeactivated,
  );
  ModalRoute<dynamic>? _playbackRoute;

  /// Tab this subtree lives in, read from the enclosing [TabScope] in
  /// `didChangeDependencies`. Null outside a tab (root route, tests).
  int? _tabScopeIndex;

  // Core state - **OPTIMIZED: Using ValueNotifiers for granular updates**
  List<VideoModel> _videos = [];
  final ValueNotifier<bool> _isLoadingVN = ValueNotifier<bool>(true);
  bool get _isLoading => _isLoadingVN.value;
  set _isLoading(bool value) => _isLoadingVN.value = value;

  String? _currentUserId;
  // Remove unused _currentUserObjectId
  int _previousIndex = 0;
  final ValueNotifier<int> _currentIndexVN = ValueNotifier<int>(0);
  int get _currentIndex => _currentIndexVN.value;
  set _currentIndex(int value) {
    _previousIndex = _currentIndexVN.value;
    _currentIndexVN.value = value;
  }
  int _currentPage = 1;
  String? _nextCursor; // **NEW: Cursor for the next page of videos**

  // Share links: the initial seek must run exactly once, on the shared video only
  bool _hasAppliedInitialStartSeek = false;

  // final Set<String> _followingUsers = {}; // **REMOVED: Now using global UserProvider**
  final Set<String> _seenVideoKeys = <String>{};
  final ValueNotifier<String?> _errorMessageVN = ValueNotifier<String?>(null);
  String? get _errorMessage => _errorMessageVN.value;
  set _errorMessage(String? value) => _errorMessageVN.value = value;

  final ValueNotifier<bool> _isRefreshingVN = ValueNotifier<bool>(false);
  bool get _isRefreshing => _isRefreshingVN.value;
  set _isRefreshing(bool value) => _isRefreshingVN.value = value;

  // Services
  late VideoService _videoService;
  late AuthService _authService;
  late CarouselAdManager _carouselAdManager;
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();

  // Cached providers & media query
  MainController? _mainController;
  double? _screenWidth;

  // Decoder priming
  int get _decoderPrimeBudget => 3;
  int _primedStartIndex = -1;

  // Ad and analytics services
  late final IAdService _activeAdsService;
  final VideoViewTracker _viewTracker = VideoViewTracker();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();
  final BackgroundProfilePreloader _profilePreloader =
      BackgroundProfilePreloader();
  final AdImpressionService _adImpressionService = AdImpressionService();
  StreamSubscription? _adRefreshSubscription;

  // Dubbing State
  late final IDubbingService _dubbingService;
  final Map<String, ValueNotifier<DubbingResult>> _dubbingResultsVN = {};
  final Map<String, StreamSubscription> _dubbingSubscriptions = {};
  final Map<String, String> _selectedAudioLanguage = {};
  final Map<String, String> _dubbingTargetLanguage = {};

  // Cache status tracking

  // Cache status tracking
  final int _cacheHits = 0;
  final int _cacheMisses = 0;
  final _preloadHits = 0;
  final int _totalRequests = 0;

  // Ad state - **OPTIMIZED: Using ValueNotifiers for granular updates**
  final ValueNotifier<List<Map<String, dynamic>>> _bannerAdsVN =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  List<Map<String, dynamic>> get _bannerAds => _bannerAdsVN.value;
  set _bannerAds(List<Map<String, dynamic>> value) =>
      _bannerAdsVN.value = value;

  final Map<String, Map<String, dynamic>> _lockedBannerAdByVideoId = {};
  final ValueNotifier<bool> _adsLoadedVN = ValueNotifier<bool>(false);
  bool get _adsLoaded => _adsLoadedVN.value;
  set _adsLoaded(bool value) => _adsLoadedVN.value = value;

  // Page controller
  late PageController _pageController;
  final bool _autoScrollEnabled = true;
  bool _isAnimatingPage = false;
  final Set<int> _autoAdvancedForIndex = {};

  // Controller pools
  final Map<String, VideoPlayerController> _controllerPool = {};
  final Map<String, bool> _controllerStates = {};
  final int _maxPoolSize = 7;
  final Map<String, bool> _userPaused = {};
  // **OPTIMIZED: ValueNotifier for user paused state to avoid full rebuilds**
  final Map<String, ValueNotifier<bool>> _userPausedVN = {};
  
  final Map<String, bool> _isBuffering = {};
  final Set<String> _togglingVideos = {};
  final Map<String, ValueNotifier<bool>> _isBufferingVN = {};
  final Map<String, ValueNotifier<bool>> _isSlowConnectionVN = {};
  final Map<String, Timer> _bufferingTimers = {};
  
  // **NEW: Connectivity UI Throttling**
  int _slowConnectionShownCount = 0;
  final int _maxSlowConnectionShows = 2;
  
  // **NEW: Offline Banner Control**
  final ValueNotifier<bool> _showOfflineBannerVN = ValueNotifier<bool>(false);
  bool _hasShownOfflineBanner = false;
  StreamSubscription? _connectivitySubscription;

  // LRU tracking
  final Map<String, DateTime> _lastAccessedLocal = {};
  final Map<String, VoidCallback> _bufferingListeners = {};
  final Map<String, VoidCallback> _videoEndListeners = {};
  // **NEW: Track Quiz Listeners**
  final Map<String, VoidCallback> _quizListeners = {};
  // **NEW: Track Error Listeners explicitly for cleanup**
  final Map<String, VoidCallback> _errorListeners = {};

  final ValueNotifier<QuizModel?> _activeQuizVN = ValueNotifier<QuizModel?>(null);
  late final IQuizEngine _quizEngine;


  // Resume tracking
  final Map<String, bool> _wasPlayingBeforeNavigation = {};

  // Preloading state
  final Set<String> _preloadedVideos = {};
  final Set<String> _loadingVideos = {};
  final Set<String> _initializingVideos = {};
  // **OPTIMIZED: Reduced to 1 for maximum performance**
  // Focus all resources on current video for smoothest playback
  int get _maxConcurrentInitializations => 1;
  
  // **NEW: Adaptive Network State**
  bool _isLowBandwidthMode = false;
  bool _isLowEndDevice = false; // **NEW: Track device capabilities**
  int _consecutiveSmoothPlays = 0;
  
  
  final Map<String, int> _preloadRetryCount = {};
  Timer? _preloadTimer;
  Timer? _pageChangeTimer;
  Timer? _preloadDebounceTimer;
  // **NEW: Individual debounce timers for each video ID**
  final Map<String, Timer> _preloadDebounceTimers = {};
  DateTime _lastPageChangeTime = DateTime.now();
  bool _wasLastScrollFast = false;

  // First-frame tracking



  // Disposal subscription
  StreamSubscription<String>? _poolDisposalSubscription;

  // Retained controllers for refresh

  // Infinite scrollingtrollers for refresh

  // Infinite scrolling
  // **OPTIMIZED: Increased to 20 for earlier loading - next batch loads when 20 videos from end**
  final ValueNotifier<bool> _isLoadingMoreVN = ValueNotifier<bool>(false);
  bool get _isLoadingMore => _isLoadingMoreVN.value;
  set _isLoadingMore(bool value) => _isLoadingMoreVN.value = value;

  // **OPTIMIZED: Constant 15 videos per page to prevent offset/skipping bugs**
  // Variable page size (5 then 15) caused backend to skip videos 5-15.
  int get _videosPerPage => 15;
  int _consecutiveEmptyBatches = 0;

  final ValueNotifier<bool> _hasMoreVN = ValueNotifier<bool>(true);
  bool get _hasMore => _hasMoreVN.value;
  set _hasMore(bool value) => _hasMoreVN.value = value;


  // **NEW: Video Error Tracking**
  // Stores error messages for videos that failed to load or play
  final Map<String, String> _videoErrors = {};

  /// Tracks videos currently in E2EE prebuffer phase —
  /// key is registered, prefetch is running, waiting for enough bytes on disk
  /// before creating VideoPlayerController.
  final Set<String> _e2eeDecryptingVideos = {};

  // Playback StateMANAGEMENT: Limit videos in memory to prevent memory issues**
  // Keep max 300 videos (15 pages) - removes old videos automatically
  // Each VideoModel ~5-10KB, so 300 videos = ~1.5-3MB (safe)
  // For 5000+ videos, this prevents 50MB+ memory usage
  static const int _maxVideosInMemory =
      300; // **SCALABLE: Adjust based on device memory**
  static const int _videosCleanupThreshold =
      250; // Start cleanup when reaching this
  static const int _videosKeepRange = 100; // Keep current ± 100 videos

  // Carousel ads - **REFACTORED: Now using _carouselAdManager directly**

  final Map<String, ValueNotifier<int>> _currentHorizontalPage = {};
  final Map<String, PageController> _horizontalControllers = {};

  // **Long-press ad overlay state**
  final ValueNotifier<bool> _showLongPressAdOverlayVN = ValueNotifier<bool>(false);
  Timer? _longPressAdAutoHideTimer;

  // **Pause-triggered ad overlay state (no auto-hide — hides when video plays)**
  // Per-video map so the ad is attached to and scrolls with its specific video.
  final Map<String, ValueNotifier<bool>> _showPauseAdOverlayPerVideoVN = {};

  // Screen visibility
  bool _isScreenVisible =
      false; // **FIX: Start as false, only set true when Yug tab is actually visible**
  bool _lifecyclePaused = false;

  // Double tap animations
  final Map<String, ValueNotifier<bool>> _showHeartAnimation = {};

  // **NEW: Force-show overlay after double-tap like for confirmation**
  final Map<String, ValueNotifier<bool>> _forceShowOverlayVN = {};
  final Map<String, Timer> _forceShowOverlayTimers = {};

  // **NEW: Granular Like State Notifiers (Keyed by Video ID)**
  final Map<String, ValueNotifier<bool>> _isLikedVN = {};
  final Map<String, ValueNotifier<int>> _likeCountVN = {};

  // Earnings cache


  // Persisted state keys
  String get _kSavedFeedIndexKey => 'video_feed_saved_index';
  String get _kSavedFeedTypeKey => 'video_feed_saved_type';
  String get _kSavedVideoIdKey => 'video_feed_saved_video_id';
  String get _kSavedPageKey => 'video_feed_saved_page';
  String get _kSavedStateTimestampKey => 'video_feed_saved_timestamp';
  String get _kSeenVideoKeysKey => 'video_feed_seen_video_keys';

  // Cold start tracking
  bool _isColdStart = true;
  bool _isInitialDataLoaded = false;

  // Screen wake lock
  bool _wakelockEnabled = false;
  bool _wasSignedIn = false;
  bool _pendingAutoplayAfterLogin = false;
  bool _isGoogleSignInInProgress = false;

  // **NEW: Track when screen was first opened to delay sign-in prompts**
  DateTime? _lastPausedAt;

  // Background page preload logic
  bool _hasStartedBackgroundPreload = false;




  // **STATE RESTORATION: Native OS-managed properties**
  // These are automatically deleted by the OS if the user manually swipes the app away.

  String videoIdentityKey(VideoModel video) {
    if (video.id.isNotEmpty) return video.id;
    if (video.videoUrl.isNotEmpty) return video.videoUrl;
    if (video.videoName.isNotEmpty) return video.videoName;
    return '${video.hashCode}';
  }
}
