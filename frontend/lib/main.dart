import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart'; // Ensure Firebase is imported
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'package:vayug/features/video/feed/presentation/screens/homescreen.dart';
import 'package:vayug/features/onboarding/presentation/screens/splash_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:device_preview/device_preview.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/managers/hot_ui_state_manager.dart';
import 'package:vayug/core/design/theme.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayug/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayug/features/onboarding/data/services/gallery_permission_service.dart';
import 'package:vayug/features/onboarding/presentation/screens/welcome_onboarding_screen.dart';
import 'package:vayug/features/ads/data/services/ad_impression_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/shared/services/error_logging_service.dart';
import 'package:vayug/shared/services/deep_link_service.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/navigation/app_route_observer.dart';

// Enable on a desktop/web debug run with --dart-define=DEVICE_PREVIEW=true.
const _enableDevicePreview = bool.fromEnvironment('DEVICE_PREVIEW');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable Edge-to-Edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced:
          false, // Prevents Android from adding black background
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  debugRepaintRainbowEnabled = false;

  // **NEW: Ensure Firebase is initialized (if not already handled elsewhere)**
  try {
    await Firebase.initializeApp();

    // **NEW: Crashlytics Integration**
    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  // **OPTIMIZATION: Limit Image Cache for Low-RAM devices**
  // 100MB limit (default is 1000MB which is too high for 3GB RAM phones)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;

  // **NEW: Initialize Ad Impression Service for offline syncing**

  AdImpressionService().initialize();

  // **STAGE 1: BASIC CONFIG (Moved to Splash Screen for Parallelism)**
  // await AppInitializationManager.instance.initializeStage1();

  // **OPTIMIZED: Start app immediately**
  runApp(
    DevicePreview(
      enabled: kDebugMode && _enableDevicePreview,
      builder: (context) => ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) => const MyApp(),
        ),
      ),
    ),
  );
}
// Removed redundant _checkServerConnectivity and _initializeServicesInBackground (moved to Manager)

// _splashPrefetch removed (logic moved to AppInitializationManager)

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ErrorLoggingService.logAppLifecycle('started');

    // Initialize Deep Link Service
    DeepLinkService().initialize();
  }

  @override
  void dispose() {
    DeepLinkService().dispose();
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final mainController = ref.read(mainControllerProvider);
    final hotUIManager = HotUIStateManager();

    switch (state) {
      case AppLifecycleState.resumed:
        ErrorLoggingService.logAppLifecycle('Resumed');
        mainController.setAppInForeground(true);
        hotUIManager.handleAppLifecycleChange(state);

        // **NEW: Proactive Token Refresh on App Resume**
        // This ensures that if the user opens the app after few days,
        // we refresh the token immediately before they see expired data.
        unawaited(AuthService().refreshTokenIfNeeded());
        break;
      case AppLifecycleState.inactive:
        ErrorLoggingService.logAppLifecycle('Inactive');
        // **NEW: Save tab index when app becomes inactive (going to background)**
        mainController.saveStateForBackground();
        // **NEW: Pause all videos when app becomes inactive**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        ref.read(videoProvider).saveStaleVideos();
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.paused:
        ErrorLoggingService.logAppLifecycle('Paused');
        mainController.setAppInForeground(false);
        // **NEW: Save tab index when app is paused (minimized)**
        mainController.saveStateForBackground();
        // **NEW: Pause all videos when app is paused (minimized)**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        try {
          ref.read(videoProvider).saveStaleVideos();
        } catch (_) {}
        // **HOT UI: Preserve state when app goes to background**
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.detached:
        ErrorLoggingService.logAppLifecycle('Detached');
        // **NEW: Pause all videos when app is detached**
        _pauseAllVideosGlobally();
        // **AGGRESSIVE CACHING: Save stale videos for next cold start**
        // Note: Context might be unstable here, but worth a try
        try {
          ref.read(videoProvider).saveStaleVideos();
        } catch (_) {}
        hotUIManager.handleAppLifecycleChange(state);
        break;
      case AppLifecycleState.hidden:
        ErrorLoggingService.logAppLifecycle('Hidden');
        // **NEW: Pause all videos when app is hidden**
        _pauseAllVideosGlobally();
        break;
    }
  }

  /// **NEW: Pause all videos globally regardless of which screen user is on**
  void _pauseAllVideosGlobally() {
    try {
      AppLogger.log('⏸️ MyApp: Pausing and cleaning memory for background');

      // 1. Pause and cleanup VideoControllerManager (singleton)
      try {
        final videoManager = VideoControllerManager();
        videoManager
            .onAppPaused(); // This now calls onAppBackgrounded internally
        AppLogger.log('✅ MyApp: Cleaned VideoControllerManager');
      } catch (e) {
        AppLogger.log('⚠️ MyApp: Error cleaning VideoControllerManager: $e');
      }

      // 2. Pause and cleanup SharedVideoControllerPool (singleton)
      try {
        final sharedPool = SharedVideoControllerPool();
        sharedPool.pauseAllControllers();
        sharedPool.onAppBackgrounded(); // Aggressive cleanup
        AppLogger.log('✅ MyApp: Cleaned SharedVideoControllerPool');
      } catch (e) {
        AppLogger.log('⚠️ MyApp: Error cleaning SharedVideoControllerPool: $e');
      }

      AppLogger.log('✅ MyApp: Background memory optimization completed');
    } catch (e) {
      AppLogger.log('❌ MyApp: Error during background cleanup: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AuthService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vayug',
      theme: AppTheme.lightTheme,
      useInheritedMediaQuery: true,
      locale: DevicePreview.locale(context),
      navigatorObservers: [AppNavigatorObserver(), appRouteObserver],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: DevicePreview.appBuilder(context, child),
        );
      },
      routes: {
        '/home': (context) => const MainScreen(),
        '/video': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;
          final videoId = args?['videoId'] as String?;
          final startAtSeconds = args?['startAtSeconds'] as int?;
          return VideoScreen(
            initialVideoId: videoId,
            startAtSeconds: startAtSeconds,
          );
        },
      },
      home: const SplashScreen(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Start auth check in background (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authController = ref.read(googleSignInProvider);
      authController.checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // **ALWAYS: Show MainScreen directly, skip login screen entirely**
    // Users can access login from settings/profile if needed
    return const MainScreenWithLocationCheck();
  }
}

/// **NEW: MainScreen with background location check**
class MainScreenWithLocationCheck extends ConsumerStatefulWidget {
  const MainScreenWithLocationCheck({super.key});

  @override
  ConsumerState<MainScreenWithLocationCheck> createState() =>
      _MainScreenWithLocationCheckState();
}

class _MainScreenWithLocationCheckState
    extends ConsumerState<MainScreenWithLocationCheck> {
  bool _hasCheckedLocation = false;
  bool _hasCheckedGallery = false;
  bool _hasCheckedWelcome = false;
  bool _shouldShowWelcome = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // **CHECK: Check if welcome onboarding should be shown FIRST**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkWelcomeOnboarding();
    });
  }

  /// **Check if welcome onboarding should be shown**
  Future<void> _checkWelcomeOnboarding() async {
    if (_hasCheckedWelcome) return;
    _hasCheckedWelcome = true;

    try {
      // **NEW CHECK**: If the user is already logged in, do NOT show the welcome onboarding screen
      final loggedIn = await ref.read(authServiceProvider).isLoggedIn();
      if (loggedIn) {
        // Quietly mark it as shown so we don't evaluate/check it again in the future
        await WelcomeOnboardingService.markWelcomeOnboardingShown();
        if (mounted) {
          setState(() {
            _shouldShowWelcome = false;
            _isLoading = false;
          });
          _checkLocationInBackground();
          _checkGalleryInBackground();
        }
        return;
      }

      final shouldShow =
          await WelcomeOnboardingService.shouldShowWelcomeOnboarding();

      if (mounted) {
        setState(() {
          _shouldShowWelcome = shouldShow;
          _isLoading = false;
        });

        // If not showing welcome, check permissions in background
        if (!shouldShow) {
          _checkLocationInBackground();
          _checkGalleryInBackground();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shouldShowWelcome = false;
          _isLoading = false;
        });
        _checkLocationInBackground();
      }
    }
  }

  /// **Handle Get Started button click**
  void _handleGetStarted() async {
    // **FIX: Mark onboarding as shown FIRST and await it to ensure persistence**
    await WelcomeOnboardingService.markWelcomeOnboardingShown();

    if (mounted) {
      setState(() {
        _shouldShowWelcome = false;
      });

      // Check permissions in background after welcome screen
      _checkLocationInBackground();
      _checkGalleryInBackground();
    }
  }

  /// **Check location permission in background without blocking UI**
  Future<void> _checkLocationInBackground() async {
    if (_hasCheckedLocation) return;
    _hasCheckedLocation = true;

    try {
      // Check if we should show location onboarding
      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();

      // If we should show the native permission dialog, show it after a delay
      if (shouldShow && mounted) {
        // Wait a bit so user sees the main screen first
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            LocationOnboardingService.showLocationOnboarding(context);
          }
        });
      }
    } catch (e) {}
  }

  /// **Check gallery permission in background**
  Future<void> _checkGalleryInBackground() async {
    if (_hasCheckedGallery) return;
    _hasCheckedGallery = true;

    try {
      final shouldShow =
          await GalleryPermissionService.shouldShowGalleryOnboarding();

      if (shouldShow && mounted) {
        // Wait 2 seconds (1s after location potentially starts)
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            GalleryPermissionService.requestGalleryPermission();
          }
        });
      }
    } catch (e) {
      AppLogger.log('❌ Main: Error checking gallery permission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // **SHOW: Welcome onboarding screen if user hasn't seen it yet**
    if (_isLoading) {
      // Show MainScreen while checking (brief moment)
      return const MainScreen();
    }

    if (_shouldShowWelcome) {
      return WelcomeOnboardingScreen(
        onGetStarted: _handleGetStarted,
      );
    }

    // **INSTANT: Show MainScreen, location check happens in background**
    return const MainScreen();
  }
}

class AppNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final String? routeName = route.settings.name;
    httpClientService.setActiveScreen(routeName);
    AppLogger.log(
        '🚀 NAV: Pushed $routeName (Previous: ${previousRoute?.settings.name})');

    if (routeName == null) {
      AppLogger.log(
          '🔍 [NAV DIAGNOSTIC] Anonymous (null) route pushed. WHO CALLED THIS? StackTrace:');
      AppLogger.log(
          StackTrace.current.toString().split('\n').take(10).join('\n'));
    }

    if (routeName == '/') {
      AppLogger.log('⚠️ NAV ALERT: Pushed root (Splash?) route! StackTrace:');
      AppLogger.log(
          StackTrace.current.toString().split('\n').take(10).join('\n'));
    }

    // **AUTO-PAUSE: Pause all playing videos whenever a new named route is pushed**
    // We skip null routes (dialogs/overlays) to prevent accidental pausing during feed active state
    if (previousRoute != null && routeName != null) {
      AppLogger.log('⏸️ NAV: Named route pushed - pausing videos');
      _pauseAllVideos();
    } else if (previousRoute != null && routeName == null) {
      AppLogger.log(
          'ℹ️ NAV: Anonymous route pushed - NOT pausing videos by default');
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    httpClientService.setActiveScreen(newRoute?.settings.name);
    AppLogger.log(
        '🚀 NAV: Replaced ${oldRoute?.settings.name} with ${newRoute?.settings.name}');
    if (newRoute?.settings.name == '/') {
      AppLogger.log(
          '⚠️ NAV ALERT: Replaced with root (Splash?) route! StackTrace:');
      AppLogger.log(
          StackTrace.current.toString().split('\n').take(10).join('\n'));
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    httpClientService.setActiveScreen(previousRoute?.settings.name);
    AppLogger.log(
        '🚀 NAV: Popped ${route.settings.name} (Now on: ${previousRoute?.settings.name})');
    // **ROUTE-POP FIX: Notify the Yug feed to re-validate its video controllers.**
    // When a profile-launched VideoFeedAdvanced is popped, it fully disposes its
    // controllers. The Yug feed still has stale references → "Bad state: No active
    // player with ID N". This triggers _validateAndRestoreControllers() on the Yug feed.
    try {
      VideoControllerManager().notifyRoutePopped();
    } catch (_) {}
  }

  /// Pause all videos using singleton controllers (no BuildContext needed)
  void _pauseAllVideos() {
    try {
      SharedVideoControllerPool().pauseAllControllers();
      VideoControllerManager().forcePauseAllVideosSync();
    } catch (_) {}
  }
}
