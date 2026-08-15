import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:vayug/features/video/upload/presentation/screens/upload_screen.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_screen.dart';
import 'package:vayug/features/video/subscriptions/presentation/screens/subscriptions_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/profile/core/data/services/background_profile_preloader.dart';
import 'package:vayug/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/onboarding/presentation/managers/app_initialization_manager.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/navigation/app_route_observer.dart';
import 'package:vayug/shared/services/deep_link_service.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/shared/widgets/tab_scope.dart';
import 'package:vayug/features/profile/core/presentation/screens/edit_profile_screen.dart';
import 'package:vayug/features/profile/core/presentation/screens/settings_screen.dart';
import 'package:vayug/features/profile/core/presentation/screens/saved_videos_screen.dart';
import 'package:vayug/features/profile/analytics/presentation/screens/creator_revenue_screen.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/providers/profile_providers.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _videoScreenKey = GlobalKey();
  final _vayuScreenKey = GlobalKey<VayuScreenState>();
  final _profileScreenKey = GlobalKey<State<ProfileScreen>>();
  final AuthService _authService = AuthService();

  // **NESTED NAVIGATION: Navigator keys for each tab**
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // Index 0: Yug
    GlobalKey<NavigatorState>(), // Index 1: Vayu
    GlobalKey<NavigatorState>(), // Index 2: Upload
    GlobalKey<NavigatorState>(), // Index 3: Subscriptions
    GlobalKey<NavigatorState>(), // Index 4: Profile
  ];

  // Route events inside a tab (creator profile, dedicated player) happen on the
  // nested navigator, which the root observer never sees. Each tab forwards its
  // own events so players can tell when a route covers them.
  final List<AppRouteObserverForwarder> _tabRouteObservers =
      List<AppRouteObserverForwarder>.generate(
    5,
    (_) => AppRouteObserverForwarder(),
  );

  // **NEW: Track refresh state for visual feedback**
  bool _isRefreshing = false;

  // **NEW: Animation controller for refresh icon**
  late AnimationController _refreshAnimationController;

  // **BACKGROUND PRELOADING: Preload profile data when user is on video feed**
  final BackgroundProfilePreloader _profilePreloader =
      BackgroundProfilePreloader();
  bool _hasCheckedForUpdates = false;

  // **LAZY TAB RESTORATION: Track which tabs have been restored**
  final Set<int> _restoredTabs = {};
  bool? _wasSignedIn;

  Future<void> _refreshVideoList() async {
    try {
      // Refresh the video screen
      final videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState != null) {
        // Cast to access the public method and await completion
        await (videoScreenState as dynamic).refreshVideos();
      } else {
        AppLogger.log('❌ MainScreen: VideoScreen state not found');
      }

      // **NEW: Also refresh the Vayu screen videos**
      try {
        VayuScreen.refresh(_vayuScreenKey);
      } catch (e) {
        AppLogger.log('❌ MainScreen: Error refreshing Vayu videos: $e');
      }

      // Navigate to video tab ONLY if user is still on upload tab (index 2)
      final mainController = ref.read(mainControllerProvider);
      if (mainController.currentIndex == 2) {
        AppLogger.log(
            '🔄 MainScreen: Still on upload tab, navigating to video tab');
        mainController.changeIndex(0);
      }
    } catch (e) {
      AppLogger.log('❌ MainScreen: Error in _refreshVideoList: $e');
    }
  }

  /// **NEW: Handle double-tap refresh with visual feedback and error handling**
  Future<void> _handleYugTabDoubleTap() async {
    if (_isRefreshing) {
      print('🔄 MainScreen: Already refreshing, ignoring double-tap');
      return;
    }

    try {
      // Haptic feedback to indicate action
      HapticFeedback.mediumImpact();

      // Set refreshing state and start animation
      setState(() {
        _isRefreshing = true;
      });

      // Start refresh animation
      _refreshAnimationController.repeat();

      print('🔄 MainScreen: Double-tap on Yug tab detected - starting refresh');

      // Get the video screen state
      State? videoScreenState = _videoScreenKey.currentState;
      if (videoScreenState == null) {
        await Future.delayed(const Duration(milliseconds: 32));
        videoScreenState = _videoScreenKey.currentState;
      }
      if (videoScreenState != null) {
        // Call refresh method with await
        await (videoScreenState as dynamic).refreshVideos();
        print('✅ MainScreen: Video refresh completed via Yug tab double-tap');

        // Show success feedback
        if (mounted) {
          VayuSnackBar.showSuccess(context, 'Videos refreshed!',
              duration: const Duration(seconds: 2));
        }
      } else {
        AppLogger.log('❌ MainScreen: VideoScreen state not found');
        if (mounted) {
          VayuSnackBar.showError(context, 'Failed to refresh videos',
              duration: const Duration(seconds: 2));
        }
      }
    } catch (e) {
      AppLogger.log('❌ MainScreen: Error in double-tap refresh: $e');
      if (mounted) {
        VayuSnackBar.showError(context, 'Failed to refresh videos',
            duration: const Duration(seconds: 2));
      }
    } finally {
      // Reset refreshing state and stop animation
      if (mounted) {
        _refreshAnimationController.stop();
        _refreshAnimationController.reset();
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// **IN-APP UPDATE: Check for Google Play updates (flexible preferred)**
  Future<void> _checkForAppUpdates() async {
    if (_hasCheckedForUpdates || !mounted) return;
    if (!Platform.isAndroid) {
      _hasCheckedForUpdates = true;
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      _hasCheckedForUpdates = true;

      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.completeFlexibleUpdate();
        return;
      }

      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.success) {
            await InAppUpdate.completeFlexibleUpdate();
            if (!mounted) return;
            VayuSnackBar.showSuccess(context, 'Update installed, restarting...',
                duration: const Duration(seconds: 2));
          }
        }
      }
    } catch (e) {
      debugPrint('In-app update check failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // **NEW: Initialize refresh animation controller**
    _refreshAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _checkTokenValidity();

    // **NEW: Initialize session expiration callback**
    HttpClientService.instance.onSessionExpired = () {
      if (mounted) {
        AppLogger.log(
            '🚨 MainScreen: Global session expiration triggered, refreshing auth state...');
        ref.read(googleSignInProvider).refreshAuthState();
      }
    };

    // **NEW: Restore last tab index when app starts**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLastTabIndex();

      // **DEEP LINK FIX: Home UI is mounted — safe to navigate now.**
      // Any video link that arrived during splash/cold start is flushed here.
      DeepLinkService().markAppReady();
    });

    // **BACKGROUND PRELOADING: Start preloading profile data when app opens (user starts on Yug tab)**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.log(
          '🚀 MainScreen: Starting background profile preloading on app start');
      _profilePreloader.startBackgroundPreloading();

      // **LOCATION ONBOARDING: Check and show location permission request**
      _checkAndShowLocationOnboarding();

      // **ACTIVITY RECOVERY: Check for recoverable activity (Upload, etc.)**
      _checkActivityRecovery();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdates();
    });

    // **STAGE 3: BACKGROUND SDK INITIALIZATION (Firebase, AdMob, etc.)**
    // Delay initialization to prevent stutter during initial screen mount
    // **DEBUG OPTIMIZATION: Longer delay in debug mode to prevent ANR**
    const stage3Delay =
        kDebugMode ? Duration(seconds: 15) : Duration(seconds: 5);
    Future.delayed(stage3Delay, () {
      if (mounted) {
        AppLogger.log('🚀 MainScreen: Triggering Stage 3 Initialization');
        AppInitializationManager.instance.initializeStage3();
      }
    });
  }

  /// **NEW: Start with a clean session for the home tab**
  Future<void> _restoreLastTabIndex() async {
    try {
      final mainController = ref.read(mainControllerProvider);

      // Always restore to home tab (0) for a fresh start as requested
      await mainController.restoreLastTabIndex();

      AppLogger.log(
          '🚀 MainScreen: Fresh start initiated (persistence disabled)');
    } catch (e) {
      AppLogger.log('❌ MainScreen: Error resetting tab index: $e');
    }
  }

  /// **NEW: Restore a specific sub-route for a tab**
  void _restoreSubRoute(
      int tabIndex, String routeName, Map<String, String>? args) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navState = _navigatorKeys[tabIndex].currentState;
      if (navState == null) return;
      AppLogger.log(
          '🔙 MainScreen: Attempting to restore sub-route $routeName for tab $tabIndex');

      Widget? screen;
      if (routeName == 'profile') {
        final userId = args?['userId'];
        if (userId != null) screen = ProfileScreen(userId: userId);
      } else if (routeName == 'edit_profile') {
        screen = EditProfileScreen(
            stateManager: ref.read(profileStateManagerProvider));
      } else if (routeName == 'settings') {
        screen = const SettingsScreen();
      } else if (routeName == 'saved_videos') {
        screen = const SavedVideosScreen();
      } else if (routeName == 'creator_revenue') {
        screen = const CreatorRevenueScreen();
      } else if (routeName == 'vayu_player') {
        // Landing on Vayu root is safer if we don't have the full video object
        // But Index persistence within Vayu player will handle the position
        return;
      }

      if (screen != null) {
        navState.push(MaterialPageRoute(
          settings: RouteSettings(name: routeName, arguments: args),
          builder: (_) => screen!,
        ));
      }
    });
  }

  /// **NEW: Check for activity recovery without changing tab (for other cases)**
  Future<void> _checkActivityRecovery() async {
    // This can handle other activity types that don't need a tab switch
    // but might need global management.
  }

  /// Check if JWT token is valid and handle expired tokens
  Future<void> _checkTokenValidity() async {
    try {
      // **DISABLED: Always skip login screen, never redirect to login**
      // Users can access login from settings/profile if needed
      final needsReLogin = await _authService.needsReLogin();
      if (needsReLogin) {
        // Don't "logout" automatically. First try to recover silently.
        final refreshed = await _authService.refreshAccessToken();
        if (refreshed == null) {
          // Mark that we should show a sign-in CTA (instead of empty state)
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('auth_needs_login', true);
            // Remove only the JWT to avoid 401 loops; keep fallback_user for UI.
            await prefs.remove('jwt_token');
          } catch (_) {}

          // Trigger auth controller refresh so Profile screen shows sign-in view
          try {
            if (mounted) {
              await ref.read(googleSignInProvider).refreshAuthState();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('❌ MainScreen: Error checking token validity: $e');
    }
  }

  /// Check and show location onboarding if needed
  Future<void> _checkAndShowLocationOnboarding() async {
    try {
      print('📍 MainScreen: Checking location onboarding status...');

      // Wait a bit to ensure the app is fully loaded
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();

      if (shouldShow) {
        final result =
            await LocationOnboardingService.showLocationOnboarding(context);

        if (result) {
          print('✅ MainScreen: Location permission granted successfully');
          // You can add additional logic here, like getting current location
          // or updating user preferences
        } else {
          print('❌ MainScreen: Location permission not granted');
        }
      } else {
        print('📍 MainScreen: Location onboarding not needed');
      }
    } catch (e) {
      print('❌ MainScreen: Error in location onboarding: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // **NEW: Dispose animation controller**

    _refreshAnimationController.dispose();
    // **BACKGROUND PRELOADING: Dispose preloader**
    _profilePreloader.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final mainController = ref.read(mainControllerProvider);

    // **FIXED: Use dedicated methods for better audio leak prevention**
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      mainController.handleAppBackgrounded();
      // **NEW: Save navigation state when app goes to background**
      mainController.saveStateForBackground();
    } else if (state == AppLifecycleState.resumed) {
      mainController.handleAppForegrounded();
    }
  }

  /// Handle back button press with proper navigation lifecycle
  Future<void> _handleBackPress(MainController mainController) async {
    // **NEW: Check nested navigator first**
    final currentKey = _navigatorKeys[mainController.currentIndex];
    if (await currentKey.currentState!.maybePop()) {
      print('🔙 MainScreen: Nested pop occurred');
      return;
    }

    // Use MainController's back button handling logic
    final shouldExit = mainController.handleBackPress();

    if (shouldExit) {
      // If we're on home tab, directly exit the app
      print('🔙 MainScreen: Back button pressed on home tab, closing app');
      SystemNavigator.pop();
    }
  }

  // Method to handle navigation taps
  void _handleNavTap(int index, MainController mainController) {
    if (index != mainController.currentIndex) {
      print(
          'Homescreen: Switching from index ${mainController.currentIndex} to $index');

      // **FIX: Pause all videos regardless of source tab to prevent audio leak**
      mainController.forcePauseVideos();

      // **BACKGROUND PRELOADING: Stop preloading when leaving Yug tab (index 0)**
      if (mainController.currentIndex == 0) {
        _profilePreloader.stopBackgroundPreloading();
      }

      // **BACKGROUND PRELOADING: Start preloading when switching TO Yug tab**
      if (index == 0) {
        print(
            '🚀 MainScreen: Starting background profile preloading (switching to Yug tab)');
        _profilePreloader.startBackgroundPreloading();
      }

      // **VAYU TAB AUTO-LOAD: Trigger refresh if Vayu tab is selected and empty**
      if (index == 1) {
        print(
            '🔄 MainScreen: Switching to Vayu tab - checking if refresh is needed');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final vayuState = _vayuScreenKey.currentState;
          if (vayuState != null && vayuState.mounted) {
            // Access videos via public getter
            final videos = vayuState.videos;
            if (videos.isEmpty) {
              vayuState.refreshVideos();
            }
          }
        });
      }

      // If switching to profile tab, ensure profile data is loaded
      // If switching to profile tab, ensure profile data is loaded
      if (index == 4) {
        // Profile is now index 4
        // Force immediate data load when profile tab is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final profileScreenState = _profileScreenKey.currentState;
          if (profileScreenState != null && mounted) {
            try {
              // Call the public method through dynamic to avoid type casting issues
              (profileScreenState as dynamic).onProfileTabSelected();
            } catch (e) {
              print('⚠️ Homescreen: Error calling onProfileTabSelected: $e');
            }
          }
        });
      }

      // **LAZY TAB RESTORATION: Restore sub-route on first visit if not already done**
      if (!_restoredTabs.contains(index)) {
        AppLogger.log(
            '🔄 MainScreen: First visit to tab $index, checking for sub-route restoration');
        unawaited(mainController.getPersistedSubRoute(index).then((savedRoute) {
          if (savedRoute != null) {
            final routeName = savedRoute['routeName'] as String;
            final args = savedRoute['args'] as Map<String, String>?;
            _restoreSubRoute(index, routeName, args);
          }
        }));
        _restoredTabs.add(index);
      }

      // Change index - MainController will handle additional video control
      mainController.changeIndex(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainController = ref.watch(mainControllerProvider);
    final authController = ref.watch(googleSignInProvider);
    final bool isSignedIn = authController.isSignedIn;

    // **SYNC: Trigger global refresh when auth state changes (Login/Logout)**
    if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
      _wasSignedIn = isSignedIn;
      AppLogger.log(
          '🔐 MainScreen: Auth transition detected (signedIn: $isSignedIn). Triggering feed refresh.');

      // Clear the initialization cache so fresh personalized videos are fetched
      AppInitializationManager.instance.clearCache();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshVideoList();
        }
      });
    } else {
      _wasSignedIn = isSignedIn;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: false, // Prevent default back behavior
        onPopInvokedWithResult: (didPop, result) async {
          await _handleBackPress(mainController);
        },
        child: Scaffold(
          extendBody: !mainController
              .isBottomNavVisible, // Allow content to flow under the bottom bar only when hidden
          backgroundColor: AppColors.backgroundPrimary,
          floatingActionButton: kDebugMode
              ? FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.8),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TalkerScreen(
                          talker: AppLogger.talker,
                          theme: const TalkerScreenTheme(
                            backgroundColor: Color(0xFF1A1A2E),
                            cardColor: Color(0xFF16213E),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Icon(Icons.bug_report,
                      color: Colors.white, size: 20),
                )
              : null,
          body: IndexedStack(
            index: mainController.currentIndex,
            children: [
              // No parentTabIndex: the enclosing TabScope supplies it.
              _buildTabNavigator(
                  0,
                  VideoScreen(
                    key: _videoScreenKey,
                    initialVideos:
                        AppInitializationManager.instance.initialVideos,
                    isMainYugTab:
                        true, // **NEW: Mark as main feed for tab-active enforcement**
                  )),
              _buildTabNavigator(1, VayuScreen(key: _vayuScreenKey)),
              _buildTabNavigator(
                  2,
                  UploadScreen(
                    key: const PageStorageKey('uploadScreen'),
                    onVideoUploaded: _refreshVideoList,
                  )),
              _buildTabNavigator(3, const SubscriptionsScreen()),
              _buildTabNavigator(
                  4,
                  ProfileScreen(
                    key: _profileScreenKey,
                  )),
            ],
          ),
          bottomNavigationBar: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: mainController.isBottomNavVisible
                ? RepaintBoundary(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary,
                        border: const Border(
                          top: BorderSide(
                              color: AppColors.borderPrimary, width: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, -4),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Container(
                        height: 52 + MediaQuery.viewPaddingOf(context).bottom,
                        padding: EdgeInsets.only(
                          left: 4,
                          right: 4,
                          top: 0,
                          bottom: math.max(
                            2.0,
                            MediaQuery.viewPaddingOf(context).bottom,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNavItem(
                              index: 0,
                              currentIndex: mainController.currentIndex,
                              icon: HugeIcons.strokeRoundedPlayCircle02,
                              activeIcon: HugeIcons.strokeRoundedPlayCircle02,
                              label: 'Yug',
                              onTap: () => _handleNavTap(0, mainController),
                              mainController: mainController,
                            ),
                            _buildNavItem(
                              index: 1,
                              currentIndex: mainController.currentIndex,
                              icon: HugeIcons.strokeRoundedVideo01,
                              activeIcon: HugeIcons.strokeRoundedVideo01,
                              label: 'Vayu',
                              onTap: () => _handleNavTap(1, mainController),
                              mainController: mainController,
                            ),
                            _buildNavItem(
                              index: 2,
                              currentIndex: mainController.currentIndex,
                              icon: HugeIcons.strokeRoundedAddCircleHalfDot,
                              activeIcon:
                                  HugeIcons.strokeRoundedAddCircleHalfDot,
                              label: 'Upload',
                              onTap: () => _handleNavTap(2, mainController),
                              mainController: mainController,
                            ),
                            _buildNavItem(
                              index: 3,
                              currentIndex: mainController.currentIndex,
                              icon: HugeIcons.strokeRoundedUserMultiple02,
                              activeIcon: HugeIcons.strokeRoundedUserMultiple02,
                              label: 'Subs',
                              onTap: () => _handleNavTap(3, mainController),
                              mainController: mainController,
                            ),
                            _buildNavItem(
                              index: 4,
                              currentIndex: mainController.currentIndex,
                              icon: HugeIcons.strokeRoundedUser,
                              activeIcon: HugeIcons.strokeRoundedUser,
                              label: 'Account',
                              onTap: () => _handleNavTap(4, mainController),
                              mainController: mainController,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(height: 0, width: double.infinity),
          ),
        ),
      ),
    );
  }

  /// Build navigation item with double-tap support for Yug tab
  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required dynamic icon,
    required dynamic activeIcon,
    required String label,
    required VoidCallback onTap,
    required MainController mainController,
  }) {
    final isSelected = currentIndex == index;
    final isYugTab = index == 0; // Yug tab is at index 0
    final isRefreshingYug = isYugTab && _isRefreshing;

    return Expanded(
      child: Semantics(
        identifier: 'nav_${label.toLowerCase()}',
        label: label,
        button: true,
        selected: isSelected,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          onDoubleTap: isYugTab ? _handleYugTabDoubleTap : null,
          behavior:
              HitTestBehavior.opaque, // **FIX: Make entire area tappable**
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(
                horizontal: 2, // Reduced from 4 to 2
                vertical: 0), // Reduced from 1 to 0 for tighter spacing
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isRefreshingYug)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: RotationTransition(
                      turns: _refreshAnimationController,
                      child: Container(
                        width: 42,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.refresh,
                          size: 24,
                          color: isSelected
                              ? AppColors.backgroundPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: HugeIcon(
                      icon: isSelected ? activeIcon : icon,
                      size: 26.0,
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),

                const SizedBox(height: 4), // Added small gap for clarity

                // Label always visible below icon
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    letterSpacing: 0.1,
                  ),
                  child: Text(isRefreshingYug ? 'Refreshing...' : label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **NEW: Nested Tab Navigator Builder**
  ///
  /// [TabScope] sits above the tab's `Navigator`, so every route pushed inside
  /// this tab — at any depth — can read which tab it lives in instead of
  /// guessing. A player that guesses wrong keeps claiming playback from a
  /// background tab.
  Widget _buildTabNavigator(int index, Widget child) {
    const screenIds = [
      'screen_yug',
      'screen_vayu',
      'screen_upload',
      'screen_subscriptions',
      'screen_account',
    ];

    return Semantics(
      identifier: screenIds[index],
      container: true,
      child: TabScope(
        index: index,
        child: Navigator(
          key: _navigatorKeys[index],
          observers: [
            TabNavigatorObserver(index, ref),
            _tabRouteObservers[index],
          ],
          onGenerateRoute: (routeSettings) {
            return MaterialPageRoute(
              builder: (context) => child,
            );
          },
        ),
      ),
    );
  }
}

/// **NEW: NavigatorObserver to track and persist sub-navigation for each tab**
class TabNavigatorObserver extends NavigatorObserver {
  final int tabIndex;
  final WidgetRef ref;

  TabNavigatorObserver(this.tabIndex, this.ref);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updatePersistence(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updatePersistence(previousRoute);
  }

  void _updatePersistence(Route<dynamic>? route) {
    if (route == null) return;

    final mainController = ref.read(mainControllerProvider);
    final routeName = route.settings.name;
    final args = route.settings.arguments;

    if (routeName == null || routeName == '/') {
      // We are at the root of the tab
      mainController.clearSubRoute(tabIndex);
      return;
    }

    // Persist if it's a known resumable route
    Map<String, String>? serializableArgs;
    if (args is Map<String, String>) {
      serializableArgs = args;
    } else if (args is String) {
      // Handle cases where only an ID is passed as argument
      serializableArgs = {'id': args};
    }

    mainController.persistSubRoute(tabIndex, routeName, args: serializableArgs);
  }
}
