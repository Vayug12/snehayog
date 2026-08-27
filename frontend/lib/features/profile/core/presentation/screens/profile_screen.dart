import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/gestures.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/screens/edit_profile_screen.dart';
import 'package:vayug/features/profile/core/presentation/screens/search_discovery_screen.dart';
import 'package:provider/provider.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/features/video/core/data/services/video_cache_proxy_service.dart';
import 'package:vayug/shared/services/profile_screen_logger.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart' as sp;
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_static_views.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/profile/analytics/presentation/screens/creator_revenue_screen.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/help_pill_button.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/features/profile/core/data/services/notification_service.dart';
import 'package:vayug/features/profile/notices/data/services/notice_service.dart';
import 'package:vayug/features/profile/payouts/data/services/payment_setup_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayug/features/auth/presentation/widgets/auth_options_sheet.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_menu_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_tabs_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_header_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/subscribers_bottom_sheet.dart';
import 'package:vayug/features/profile/content/presentation/screens/profile_tabs/yug_grid_tab.dart';
import 'package:vayug/features/profile/content/presentation/screens/profile_tabs/vayu_grid_tab.dart';
import 'package:vayug/features/profile/content/presentation/screens/profile_tabs/about_user_tab.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/auth/presentation/controllers/auth_flow.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();

  static void refreshVideos(GlobalKey<ConsumerState<ProfileScreen>> key) {
    final state = key.currentState;
    if (state != null) {
      (state as _ProfileScreenState)._profileStateManager.refreshVideosOnly();
    }
  }
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  static final Uri _whatsAppGroupUri =
      Uri.parse('https://chat.whatsapp.com/H7eU5xnwm3r2dfpvi7hCJC');

  late ProfileStateManager _profileStateManager;
  ProfileStateManager? _localStateManager; 
  bool _isLocalManager = false; 
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSigningIn = false; 
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

  // **OPTIMIZED: Use ValueNotifiers for granular updates**
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  // Referral tracking
  final ValueNotifier<int> _invitedCount = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedInstalled = ValueNotifier<int>(0);
  final ValueNotifier<int> _verifiedSignedUp = ValueNotifier<int>(0);

  // Local tab state for content section
  // 0 => Your Videos, 1 => Top Creators / Recommendations
  // Navigation & UI State
  late final TabController _tabController;
  final ValueNotifier<int> _activeProfileTabIndex = ValueNotifier<int>(0);

  // null means the server-backed UPI status is still being verified.
  final ValueNotifier<bool?> _hasUpiId = ValueNotifier<bool?>(null);

  bool _isDeleteLoadingDialogVisible = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    ProfileScreenLogger.logProfileScreenInit();
    
    // **UNIQUE CONTAINER STRATEGY: Use local manager for creators to avoid sync bugs**
    final authService = AuthService();
    final myId = authService.currentUserId;
    
    // Check if we are viewing someone else's profile
    if (widget.userId != null && widget.userId != myId?.toString()) {
      AppLogger.log('🚀 ProfileScreen: Initializing LOCAL ProfileStateManager for creator: ${widget.userId}');
      _localStateManager = ProfileStateManager(
        authService: authService,
        videoService: VideoService(),
        userService: UserService(),
        notificationService: NotificationService(),
        noticeService: NoticeService(),
        paymentSetupService: PaymentSetupService(),
      );
      _profileStateManager = _localStateManager!;
      _isLocalManager = true;
    } else {
      AppLogger.log(
          '🚀 ProfileScreen: Using GLOBAL ProfileStateManager for own profile');
      _profileStateManager = ref.read(profileStateManagerProvider);
      _isLocalManager = false;
    }
    
    // **FIX: Always attempt initial load once during init**
    // This ensures data loads on first attempt without double-triggering
    _loadData();
    // Load referral stats
    _loadReferralStats();
    _fetchVerifiedReferralStats();
    // Red dot for subscribers the creator has not looked at yet
    _refreshSubscribersBadge();

    // NO SETSTATE NEEDED: The UI components that need the active tab index 
    // use a ValueListenableBuilder for granular updates.
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      // **FIX: Pause any playing videos before switching tabs to prevent audio leak**
      _pauseAllVideoControllers();
      
      
      _activeProfileTabIndex.value = _tabController.index;
      // Trigger pagination logic if needed when switching tabs
      if (_tabController.index == 0 && _profileStateManager.userVideos.isEmpty) {
         _loadVideos().catchError((e) => AppLogger.log('⚠️ Error loading videos on tab: $e'));
      }
    }
  }

  void onProfileTabSelected() {
    _refreshSubscribersBadge();

    // **OPTIMIZED: Only load if data is completely missing or stale (> 5 minutes)**
    if (_profileStateManager.userData == null || _profileStateManager.isDataPartial) {
      AppLogger.log('📡 ProfileScreen: Initializing data fetch (isDataPartial: ${_profileStateManager.isDataPartial})');
      _loadData(); 
    } else if (_profileStateManager.needsVideoRefresh) {
      AppLogger.log('🚀 ProfileScreen: Refreshing videos as requested by state manager');
      _loadVideos(forceRefresh: true, silent: true).catchError((e) {
        AppLogger.log('⚠️ ProfileScreen: Error in video refresh: $e');
      });
    } else {
      AppLogger.log('✅ ProfileScreen: Data is fresh, skipping redundant refresh');
    }
  }

  // --- Profile Slivers & Body Builders ---

  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      AppLogger.log('🔄 ProfileScreen: Starting data loading (forceRefresh: $forceRefresh)');

      _isLoading.value = true;
      _error.value = null;

      await _profileStateManager.loadUserData(widget.userId, forceRefresh: forceRefresh);
      
      if (!mounted) return;
      _isLoading.value = false;
      
      if (_profileStateManager.userData != null) {
        // Verify billing only after profile state exists. Until then the CTA
        // stays hidden instead of briefly showing incorrect setup UI.
        unawaited(_checkUpiIdStatus());
        if (_profileStateManager.userVideos.isEmpty && !_profileStateManager.isVideosLoading) {
           _loadVideos(forceRefresh: forceRefresh, silent: true).catchError((_) {});
        }
        _refreshEarningsData(forceRefresh: forceRefresh).catchError((e) {});
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading data: $e');
      if (!mounted) return;
      _error.value = _getUserFriendlyError(e);
      _isLoading.value = false;
    }
  }

  /// **NEW: Get user-friendly error message**
  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorString.contains('network') ||
        errorString.contains('socket')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return AppText.get('error_sign_in_again');
    } else if (errorString.contains('not found') ||
        errorString.contains('404')) {
      return AppText.get('error_profile_not_found');
    } else if (errorString.contains('server') || errorString.contains('500')) {
      return AppText.get('error_server');
    } else {
      return AppText.get('error_load_profile_generic');
    }
  }

  /// **NEW: Load videos from server (can run in background)**
  /// **CRITICAL: When forceRefresh=true, COMPLETELY bypass cache and fetch fresh data from server**
  Future<void> _loadVideos(
      {bool forceRefresh = false, bool silent = false}) async {
    try {
      // **FIX: Better handling of null userData with retry**
      if (_profileStateManager.userData == null) {
        AppLogger.log('⚠️ ProfileScreen: User data not ready, waiting...');
        // Wait with exponential backoff
        for (int i = 0; i < 5; i++) {
          await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
          if (_profileStateManager.userData != null) {
            break;
          }
        }

        if (_profileStateManager.userData == null) {
          AppLogger.log(
              '⚠️ ProfileScreen: User data still not ready after waiting, skipping video load');
          // **FIX: Show error instead of silently failing**
          if (mounted) {
            VayuSnackBar.showWarning(context, AppText.get('error_load_videos'));
          }
          return;
        }
      }

      // **FIXED: Prioritize googleId, then id (which contains googleId from backend), then fallback**
      // When viewing another creator, ensure we use the correct googleId for the video endpoint
      final currentUserId = _profileStateManager.userData!['googleId'] ??
          _profileStateManager.userData!['id'] ?? // Backend returns id: user.googleId
          _profileStateManager.userData!['_id'];

      // **FIX: If viewing another creator and widget.userId is provided, use it as fallback**
      // This ensures we use the correct ID format when userData might not have googleId set correctly
      final userIdForVideos = currentUserId ?? widget.userId;

      if (userIdForVideos != null) {
        AppLogger.log(
            '🔄 ProfileScreen: Loading videos for $userIdForVideos (force: $forceRefresh, silent: $silent)');
        await _profileStateManager
            .loadUserVideos(userIdForVideos,
                forceRefresh: forceRefresh, silent: silent)
            .timeout(const Duration(seconds: 30));

        AppLogger.log(
            '✅ ProfileScreen: Loaded ${_profileStateManager.userVideos.length} videos${forceRefresh ? " (fresh from server, not cache)" : ""}');
            
        // **NEW: AGGRESSIVE BACKGROUND LOAD - Load all remaining videos**
        // This ensures the user sees a complete grid quickly without manually scrolling/waiting.
        if (_profileStateManager.hasMoreVideos && !_profileStateManager.isFetchingMore) {
           AppLogger.log('🚀 ProfileScreen: Triggering AGGRESSIVE background load for ALL remaining videos...');
           _profileStateManager.loadAllVideosInBackground(userId: userIdForVideos).catchError((e) {
             AppLogger.log('⚠️ ProfileScreen: Background load all failed: $e');
           });
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading videos: $e');
      // **FIX: Re-throw error so it can be caught and shown to user**
      rethrow;
    }
  }

  Future<void> _refreshData() async {
    AppLogger.log('🔄 ProfileScreen: Manual refresh starting...');
    _error.value = null;

    try {
      // Clear SmartCache first
      try {
        final smartCache = SmartCacheManager();
        await smartCache.initialize();
        if (smartCache.isInitialized) {
          final currentUserId = widget.userId ?? _profileStateManager.userData?['googleId'];
          if (currentUserId != null) {
            await smartCache.clearCacheByPattern('video_profile_$currentUserId');
            await smartCache.clearCacheByPattern('user_profile_$currentUserId');
          }
        }
      } catch (_) {}

      // Unlike initial loading, manual refresh must wait for profile, videos,
      // and earnings so the pull indicator reflects the real fresh state.
      await _profileStateManager.refreshData();

      await Future.wait([
        _loadReferralStats(),
        _fetchVerifiedReferralStats(),
        _checkUpiIdStatus(),
      ]);

      _refreshSubscribersBadge(force: true);

      AppLogger.log('✅ ProfileScreen: Manual refresh completed');
      if (mounted) {
        VayuSnackBar.showSuccess(context, 'Profile refreshed');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error during refresh: $e');
      if (mounted) {
        VayuSnackBar.showError(context, AppText.get('error_refresh_cache'));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }


  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _activeProfileTabIndex.dispose();
    ProfileScreenLogger.logProfileScreenDispose();
    
    // **NEW: Stop all background downloads immediately on exit**
    try {
      AppLogger.log('🛑 ProfileScreen: Exiting profile, stopping all background downloads...');
      final videoCacheProxy = VideoCacheProxyService();
      videoCacheProxy.cancelAllStreamingExcept([]); 
      videoCacheProxy.cancelAllPrefetches();
    } catch (e) {
       AppLogger.log('⚠️ ProfileScreen: Error stopping downloads: $e');
    }

    // **NEW: Ensure local manager is disposed to free memory**
    if (_isLocalManager && _localStateManager != null) {
      AppLogger.log('🧹 ProfileScreen: Disposing local ProfileStateManager');
      _localStateManager!.dispose();
    }

    // **OPTIMIZED: Dispose ValueNotifiers**
    _invitedCount.dispose();
    _verifiedInstalled.dispose();
    _verifiedSignedUp.dispose();
    _hasUpiId.dispose();
    _isLoading.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    try {
      ProfileScreenLogger.logLogout();
      
      // **FIXED: Use centralized LogoutService for unified logout across entire app**
      await LogoutService.performCompleteLogout(ref);
      
      // Ensure local state is cleared immediately so login prompt appears
      _profileStateManager.clearData();

      // **FIX: Only remove session tokens, NOT payment data**
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      if (mounted) {
        VayuSnackBar.showSuccess(context, AppText.get('profile_logout_success'));
      }
      ProfileScreenLogger.logLogoutSuccess();
    } catch (e) {
      ProfileScreenLogger.logLogoutError(e.toString());
      if (mounted) {
        VayuSnackBar.showError(context, '${AppText.get('error_logout')}: $e');
      }
    }
  }

  /// **FIXED: Use GoogleSignInController Provider for unified auth state**
  Future<void> _handleGoogleSignIn() async {
    final authController = ref.read(googleSignInProvider);
    if (_isSigningIn || authController.isLoading) return;

    try {
      ProfileScreenLogger.logGoogleSignIn();

      if (mounted) setState(() => _isSigningIn = true);

      // Single shared flow owns the outcome message, so a failed backend
      // exchange can never surface as a successful sign-in.
      final result = await AuthFlow.signIn(
        context,
        ref,
        successMessage: AppText.get('profile_sign_in_success'),
        onSuccess: () async {
          if (!mounted) return;
          // **OPTIMIZED: Parallel state refresh and pre-fetch**
          final mainController = ref.read(mainControllerProvider);
          await mainController.refreshAppStateAfterSwitch(ref);

          AppLogger.log(
              'ProfileScreen: Sign-in successful, loading own profile data...');

          // Force refresh to ensure final UI consistency
          await _loadData(forceRefresh: true);
        },
      );

      if (result.isSuccess) {
        ProfileScreenLogger.logGoogleSignInSuccess();
      } else if (result.isFailure) {
        ProfileScreenLogger.logGoogleSignInError(result.message ?? 'unknown');
      }
    } catch (e) {
      ProfileScreenLogger.logGoogleSignInError(e.toString());
      if (mounted) {
        VayuSnackBar.showError(context, AppText.get('error_sign_in'));
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handlePhoneSignIn() async {
    final authController = ref.read(googleSignInProvider);
    final userData = await showAuthOptionsSheet(
      context: context,
      authController: authController,
      startWithPhone: true,
    );
    if (!mounted || userData == null) return;

    try {
      setState(() => _isSigningIn = true);
      final mainController = ref.read(mainControllerProvider);
      await mainController.refreshAppStateAfterSwitch(ref);
      await _loadData(forceRefresh: true);
      if (mounted) {
        VayuSnackBar.showSuccess(context, 'Phone verified successfully!');
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Could not refresh profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  /// Share app referral message
  Future<void> _handleReferFriends() async {
    try {
      // Build a referral link with user code if available
      String base = 'https://snehayog.site';
      String referralCode = '';
      final userData = _profileStateManager.getUserData();
      final token = userData?['token'];
      if (token != null) {
        try {
          final uri = Uri.parse('${NetworkHelper.apiBaseUrl}/referrals/code');
          final resp = await httpClientService.get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
            timeout: const Duration(seconds: 6),
          );
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            referralCode = data['code'] ?? '';
          }
        } catch (_) {}
      }
      final String referralLink =
          referralCode.isNotEmpty ? '$base/?ref=$referralCode' : base;
      final String message =
          'Monetize from your content. Enjoy ad-free videos $referralLink';
      // Optimistically increment invite counter immediately on click
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        _invitedCount.value = (prefs.getInt('referral_invite_count') ?? 0) + 1;
      }
      await prefs.setInt('referral_invite_count', _invitedCount.value);

      await sp.SharePlus.instance.share(
        sp.ShareParams(
          text: message,
          subject: 'Vayug – Monetize from your content. Enjoy ad-free videos',
        ),
      );
      // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, AppText.get('error_share'));
      }
    }
  }

  Future<void> _loadReferralStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        _invitedCount.value = prefs.getInt('referral_invite_count') ?? 0;
      }
      // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
    } catch (_) {}
  }

  Future<void> _fetchVerifiedReferralStats() async {
    try {
      final userData = _profileStateManager.getUserData();
      final token = userData?['token'];
      if (token == null) return;
      final uri = Uri.parse('${NetworkHelper.apiBaseUrl}/referrals/stats');
      final resp = await httpClientService.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 6),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        // **BATCHED UPDATE: Update both values**
        _verifiedInstalled.value = data['installed'] ?? 0;
        _verifiedSignedUp.value = data['signedUp'] ?? 0;
        // **REMOVED: No setState needed, ValueNotifier automatically updates listeners**
      }
    } catch (_) {}
  }

  Future<void> _handleEditProfile() async {
    ProfileScreenLogger.logProfileEditStart();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(stateManager: _profileStateManager),
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  Future<void> _handleSaveProfile() async {
    try {
      ProfileScreenLogger.logProfileEditSave();
      final newName = _profileStateManager.nameController.text.trim();
      if (newName.isEmpty) {
        throw 'Name cannot be empty';
      }

      await _profileStateManager.saveProfile();

      await _cacheCurrentProfile();

      if (mounted) {
        VayuSnackBar.showSuccess(context, AppText.get('profile_updated_success'), duration: const Duration(seconds: 2));
      }
      ProfileScreenLogger.logProfileEditSaveSuccess();
    } catch (e) {
      ProfileScreenLogger.logProfileEditSaveError(e.toString());
      if (mounted) {
        VayuSnackBar.showError(context, '${AppText.get('error_update_profile')}: $e');
      }
    }
  }

  Future<void> _handleCancelEdit() async {
    ProfileScreenLogger.logProfileEditCancel();
    _profileStateManager.cancelEditing();
  }

  Future<void> _handleDeleteSelectedVideos() async {
    try {
      final initialCount = _profileStateManager.selectedVideoIds.length;
      ProfileScreenLogger.logVideoDeletion(count: initialCount);
      final shouldDelete = await _showDeleteConfirmationDialog();
      if (!shouldDelete) return;

      // Show loading indicator
      _showLoadingDialog(count: initialCount);

      try {
        await _profileStateManager.deleteSelectedVideos();

        if (mounted) {
          VayuSnackBar.showSuccess(
            context, 
            AppText.get('profile_videos_deleted').replaceAll('{count}', '$initialCount'),
            duration: const Duration(seconds: 3),
          );
        }
        ProfileScreenLogger.logVideoDeletionSuccess(count: initialCount);
      } catch (e) {
        rethrow;
      } finally {
        _hideLoadingDialog();
      }
    } catch (e) {
      ProfileScreenLogger.logVideoDeletionError(e.toString());
      if (mounted) {
        VayuSnackBar.showError(
          context, 
          _profileStateManager.error ?? AppText.get('error_delete_videos'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: AppText.get('btn_retry', fallback: 'Retry'),
            textColor: Colors.white,
            onPressed: () => _handleDeleteSelectedVideos(),
          ),
        );
      }
    }
  }

  void _showLoadingDialog({required int count}) {
    if (_isDeleteLoadingDialogVisible) return;
    _isDeleteLoadingDialogVisible = true;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.surfacePrimary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  count == 1 ? 'Deleting video...' : 'Deleting $count videos...',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Please wait a moment.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isDeleteLoadingDialogVisible = false;
    });
  }

  void _hideLoadingDialog() {
    if (!_isDeleteLoadingDialogVisible || !mounted) return;
    _isDeleteLoadingDialogVisible = false;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowPrimary,
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon with animated background
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02,
                        color: AppColors.error,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      AppText.get('profile_delete_videos_title'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      AppText.get('profile_delete_videos_desc').replaceAll(
                          '{count}',
                          '${_profileStateManager.selectedVideoIds.length}'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            isFullWidth: true,
                            onPressed: () => Navigator.of(context).pop(false),
                            label: AppText.get('btn_cancel'),
                            variant: AppButtonVariant.secondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            isFullWidth: true,
                            onPressed: () => Navigator.of(context).pop(true),
                            label: AppText.get('btn_delete', fallback: 'Delete'),
                            variant: AppButtonVariant.danger,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _handleProfilePhotoChange() async {
    try {
      // **FIX: Pause all video controllers to prevent audio leak**
      AppLogger.log(
          '🔇 ProfileScreen: Pausing all videos before profile photo change');
      _pauseAllVideoControllers();

      ProfileScreenLogger.logProfilePhotoChange();
      final XFile? image = await showDialog<XFile>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppText.get('profile_change_photo')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedCamera01),
                  title: Text(AppText.get('profile_take_photo')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.camera);
                    if (context.mounted) Navigator.pop(context, photo);
                  },
                ),
                ListTile(
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedImage02),
                  title: Text(AppText.get('profile_choose_gallery')),
                  onTap: () async {
                    final XFile? photo = await _imagePicker.pickImage(
                        source: ImageSource.gallery);
                    if (context.mounted) Navigator.pop(context, photo);
                  },
                ),
              ],
            ),
          );
        },
      );

      if (image != null) {
        if (mounted) {
          VayuSnackBar.showInfo(context, AppText.get('profile_photo_uploading'), duration: const Duration(seconds: 1));
        }

        await _profileStateManager.updateProfilePhoto(image.path);

        await _cacheCurrentProfile();

        if (mounted) {
          VayuSnackBar.showSuccess(context, AppText.get('profile_photo_updated'));
        }
        ProfileScreenLogger.logProfilePhotoChangeSuccess();
      }
    } catch (e) {
      ProfileScreenLogger.logProfilePhotoChangeError(e.toString());
      if (mounted) {
        VayuSnackBar.showError(context, '${AppText.get('error_change_photo')}: $e');
      }
    }
  }

  /// **IMPROVED: Pause all video controllers to prevent audio leak (better UX)**
  void _pauseAllVideoControllers() {
    try {
      // Get the main controller from the app
      final mainController = ref.read(mainControllerProvider);
      AppLogger.log('🔇 ProfileScreen: Pausing all videos via MainController');
      mainController.forcePauseVideos();

      // **IMPROVED: Also pause shared pool controllers**
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();

      AppLogger.log(
          '🔇 ProfileScreen: All video controllers paused (kept in memory)');
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Error pausing videos: $e');
    }
  }


  /// **DEBUG: Build a styled debug test button with label and subtitle**
  Widget _buildDebugButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.centerLeft,
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle Add UPI ID button tap
  Future<void> _handleAddUpiId() async {
    await ProfileDialogsWidget.showHowToEarnDialog(
      context,
      stateManager: _profileStateManager,
    );

    if (mounted) {
      _hasUpiId.value = _profileStateManager.hasUpiId;
    }
  }




  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // **RIVERPOD INTEGRATION: Watch global state managers**
    final globalProfileState = ref.watch(profileStateManagerProvider);
    final globalAuthState = ref.watch(googleSignInProvider);

    // If we are using a local manager (for viewing another creator),
    // we use that. Otherwise we use the global watched state.
    final activeManager = _isLocalManager ? _profileStateManager : globalProfileState;

    return ListenableBuilder(
      listenable: activeManager,
      builder: (context, _) {
        // Determine if viewing own profile
        final isViewingOwnProfile =
            _isOwnProfile(activeManager, globalAuthState);

        return PopScope(
          canPop: !activeManager.isSelecting,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && activeManager.isSelecting) {
              activeManager.exitSelectionMode();
            }
          },
          child: p.MultiProvider(
            providers: [
              p.ChangeNotifierProvider<ProfileStateManager>.value(value: activeManager),
            ],
            child: Stack(
            children: [
              Scaffold(
                key: _scaffoldKey,
                backgroundColor: AppColors.backgroundPrimary,
                drawer: isViewingOwnProfile
                    ? ProfileMenuWidget(
                        stateManager: activeManager,
                        userId: widget.userId,
                        onEditProfile: _handleEditProfile,
                        onSaveProfile: _handleSaveProfile,
                        onCancelEdit: _handleCancelEdit,
                        onReportUser: () => _openReportDialog(
                          targetType: 'user',
                          targetId: widget.userId!,
                        ),
                        onShowWhatsApp: _openWhatsAppGroupChat,
                        onShowFAQ: _showFAQDialog,
                        onEnterSelectionMode: () =>
                            activeManager.enterSelectionMode(),
                        onLogout: _handleLogout,
                        onGoogleSignIn: _handleGoogleSignIn,
                        onCheckPaymentSetupStatus: _checkPaymentSetupStatus,
                      )
                    : null,
                body: _buildBody(activeManager, globalAuthState, isViewingOwnProfile),
              ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(ProfileStateManager manager, GoogleSignInController authController, bool isViewingOwnProfile) {
    // **FIXED: Wait for auth initialization to complete before deciding what to show**
    if (!authController.isInitialized) {
      return _wrapWithSliverAppBar(const ProfileSkeleton(), isViewingOwnProfile, manager);
    }

    // Auth initialized — check if user is signed in
    if (widget.userId == null && !authController.isSignedIn) {
      final isSessionExpired = authController.error?.contains('expired') == true;
      return _wrapWithSliverAppBar(
        ProfileSignInView(
          onGoogleSignIn: _handleGoogleSignIn,
          onPhoneSignIn: _handlePhoneSignIn,
          sessionExpired: isSessionExpired,
          isSigningIn: _isSigningIn || authController.isLoading,
        ),
        isViewingOwnProfile,
        manager,
      );
    }

    // **REACTIVE UI: Wrap in ValueListenableBuilders for granular state updates**
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, isLoading, _) {
        if (isLoading || manager.isLoading) {
          return _wrapWithSliverAppBar(const ProfileSkeleton(), isViewingOwnProfile, manager);
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _error,
          builder: (context, error, _) {
            // Show error state
            if (error != null) {
              final bool isAuthError = error == 'No authentication data found' ||
                  error.contains('authentication') ||
                  error.contains('Unauthorized');

              // If viewing own profile and auth error, show proper sign-in
              if (widget.userId == null && isAuthError) {
                final isSessionExpired = error.contains('expired');
                return _wrapWithSliverAppBar(
                  ProfileSignInView(
                    onGoogleSignIn: _handleGoogleSignIn,
                    onPhoneSignIn: _handlePhoneSignIn,
                    sessionExpired: isSessionExpired,
                    isSigningIn: _isSigningIn || authController.isLoading,
                  ),
                  isViewingOwnProfile,
                  manager,
                );
              }
              
              // Otherwise show error with retry
              return _wrapWithSliverAppBar(
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle,
                          size: 64,
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppText.get('error_load_profile'),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        AppButton(
                          onPressed: () => _loadData(forceRefresh: true),
                          icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                          label: AppText.get('btn_retry', fallback: 'Retry'),
                          variant: AppButtonVariant.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                isViewingOwnProfile,
                manager,
              );
            }

            // Check if we have user data
            if (manager.userData == null) {
              // If viewing someone else's profile, we might not have data yet
              if (widget.userId != null) {
                return _wrapWithSliverAppBar(
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppText.get('error_load_profile'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          AppButton(
                            onPressed: () => _loadData(forceRefresh: true),
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                            label: AppText.get('btn_retry', fallback: 'Retry'),
                            variant: AppButtonVariant.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  isViewingOwnProfile,
                  manager,
                );
              }
              return _wrapWithSliverAppBar(
                ProfileSignInView(
                  onGoogleSignIn: _handleGoogleSignIn,
                  onPhoneSignIn: _handlePhoneSignIn,
                  isSigningIn: _isSigningIn || authController.isLoading,
                ),
                isViewingOwnProfile,
                manager,
              );
            }

            // SUCCESS STATE: Show profile data
            return NestedScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  _buildSliverAppBar(isViewingOwnProfile, manager),
                  ..._buildProfileHeaderSlivers(context, manager, authController),
                ];
              },
              body: RefreshIndicator(
                onRefresh: _refreshData,
                notificationPredicate: (notification) => notification.depth >= 0,
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  dragStartBehavior: DragStartBehavior.down,
                  controller: _tabController,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _invitedCount,
                      builder: (context, invitedCount, _) => YugGridTab(
                        manager: manager,
                        onReferFriends: _handleReferFriends,
                        hasReferralBillingUnlock: invitedCount >= 2,
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _invitedCount,
                      builder: (context, invitedCount, _) => VayuGridTab(
                        manager: manager,
                        onReferFriends: _handleReferFriends,
                        hasReferralBillingUnlock: invitedCount >= 2,
                      ),
                    ),
                    AboutUserTab(manager: manager),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  List<Widget> _buildProfileHeaderSlivers(
      BuildContext context, ProfileStateManager manager, GoogleSignInController authController) {
    final List<Widget> slivers = [];

    final isViewingOwnProfile =
        _isOwnProfile(manager, authController);

    // 1. Debug Token Refresh Test (Only in Debug Mode)
    if (kDebugMode) {
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.07),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bug_report, color: Colors.amber, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'AUTH DEBUG TOOLS (debug only)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.amber),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // --- Case 1: Normal Expiry ---
                _buildDebugButton(
                  context,
                  icon: Icons.timer_off_outlined,
                  label: 'Case 1: Expire Access Token',
                  subtitle: 'Refresh token intact → should silently recover',
                  color: Colors.amber[700]!,
                  onPressed: () async {
                    await _authService.debugExpireToken();
                    if (!context.mounted) return;
                    VayuSnackBar.showInfo(context,
                        'Case 1: Access token expired. Watch logs for silent refresh...');
                    _refreshData();
                  },
                ),
                const SizedBox(height: 6),

                // --- Case 2: Full Session Loss ---
                _buildDebugButton(
                  context,
                  icon: Icons.no_encryption_outlined,
                  label: 'Case 2: Full Session Loss',
                  subtitle: 'Both tokens gone → should show "Session Expired" screen',
                  color: Colors.red[700]!,
                  onPressed: () async {
                    await _authService.debugFullSessionLoss();
                    if (!context.mounted) return;
                    VayuSnackBar.showInfo(context,
                        'Case 2: Both tokens deleted. Watch for sign-in screen...');
                    _refreshData();
                  },
                ),
                const SizedBox(height: 6),

                // --- Case 3: Rotation Mismatch ---
                _buildDebugButton(
                  context,
                  icon: Icons.sync_problem_outlined,
                  label: 'Case 3: Rotation Mismatch',
                  subtitle: 'Corrupt refresh token → backend rejects, Google fallback tested',
                  color: Colors.deepOrange[700]!,
                  onPressed: () async {
                    await _authService.debugRotationMismatch();
                    if (!context.mounted) return;
                    VayuSnackBar.showInfo(context,
                        'Case 3: Refresh token corrupted (stale). Watch for Google Silent Sign-In fallback...');
                    _refreshData();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // 2. Profile Header
    slivers.add(
      SliverToBoxAdapter(
        child: ValueListenableBuilder<int>(
          valueListenable: _invitedCount,
          builder: (context, invitedCount, _) {
            return ValueListenableBuilder<bool?>(
              valueListenable: _hasUpiId,
              builder: (context, hasUpiId, _) => ProfileHeaderWidget(
                isViewingOwnProfile: isViewingOwnProfile,
                stateManager: manager,
                hasUpiId: hasUpiId,
                hasReferralBillingUnlock: invitedCount >= 2,
                onProfilePhotoChange: _handleProfilePhotoChange,
                onAddUpiId: _handleAddUpiId,
                onReferFriends: _handleReferFriends,
                onEarningsTap: _handleEarningsTap,
                onSubscribersTap: _handleSubscribersTap,
                onSaveProfile: _handleSaveProfile,
                onCancelEdit: _handleCancelEdit,
              ),
            );
          },
        ),
      ),
    );

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));

    // 3. Content Tabs
    slivers.add(
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: _SliverAppBarDelegate(
            Container(
              color: AppColors.backgroundPrimary,
              padding: const EdgeInsets.only(bottom: 8),
              child: ValueListenableBuilder<int>(
                valueListenable: _activeProfileTabIndex,
                builder: (context, activeIndex, child) {
                  return ProfileTabsWidget(
                    activeIndex: activeIndex,
                    showTopCreators: isViewingOwnProfile,
                    // Drives the underline directly off the swipe offset.
                    animation: _tabController.animation,
                    onSelect: (i) {
                      _tabController.animateTo(i);
                      _activeProfileTabIndex.value = i;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    return slivers;
  }

  bool _isOwnProfile(
    ProfileStateManager manager,
    GoogleSignInController authController,
  ) {
    if (widget.userId == null) return true;

    final signedInUserIds = <String>{
      if (_authService.currentUserId?.trim().isNotEmpty == true)
        _authService.currentUserId!.trim(),
      for (final value in [
        authController.userData?['id'],
        authController.userData?['googleId'],
        authController.userData?['_id'],
      ])
        if (value?.toString().trim().isNotEmpty == true)
          value.toString().trim(),
    };
    final displayedUserIds = <String>{
      if (widget.userId?.trim().isNotEmpty == true) widget.userId!.trim(),
      for (final value in [
        manager.userData?['id'],
        manager.userData?['googleId'],
        manager.userData?['_id'],
      ])
        if (value?.toString().trim().isNotEmpty == true)
          value.toString().trim(),
    };

    return signedInUserIds.intersection(displayedUserIds).isNotEmpty;
  }


  /// Wraps a non-scrollable widget in a CustomScrollView with a SliverAppBar
  /// so the app bar hides on scroll even in loading/error/sign-in states.
  Widget _wrapWithSliverAppBar(Widget child, bool isViewingOwnProfile, ProfileStateManager manager) {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(isViewingOwnProfile, manager),
        SliverFillRemaining(
          hasScrollBody: false,
          child: child,
        ),
      ],
    );
  }

  SliverAppBar _buildSliverAppBar(bool isViewingOwnProfile, ProfileStateManager stateManager) {
    return SliverAppBar(
      backgroundColor: AppColors.backgroundPrimary,
      elevation: 0,
      floating: true,
      snap: true,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leadingWidth: 40,
      title: stateManager.isSelecting &&
              stateManager.selectedVideoIds.isNotEmpty
          ? Text(
              '${stateManager.selectedVideoIds.length}',
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          : (stateManager.isEditing
              ? TextField(
                  controller: stateManager.nameController,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: UnderlineInputBorder(),
                    hintText: 'Enter your name',
                  ),
                  autofocus: true,
                )
              : Text(
                  stateManager.userData?['name'] ??
                      AppText.get('profile_title'),
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                )),
      leading: isViewingOwnProfile
          ? IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01,
                  color: Colors.white, size: 20),
              tooltip: 'Menu',
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            )
          : IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.white, size: 20),
              tooltip: 'Back',
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
      actions: _buildAppBarActions(stateManager, isViewingOwnProfile),
    );
  }


  List<Widget> _buildAppBarActions(ProfileStateManager stateManager, bool isViewingOwnProfile) {
    if (stateManager.isSelecting) {
      return [
        if (stateManager.selectedVideoIds.isNotEmpty)
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02,
                color: Colors.red,
                size: 24,
              ),
            ),
            tooltip: 'Delete Selected Videos',
            onPressed: _handleDeleteSelectedVideos,
          ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01,
              color: Colors.grey,
              size: 24,
            ),
          ),
          tooltip: 'Cancel Selection',
          onPressed: stateManager.exitSelectionMode,
        ),
      ];
    }

    if (isViewingOwnProfile) {
      return [
        HelpPillButton(
          onTap: _showFAQDialog,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        ),
        IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedMoreVertical,
            color: AppColors.iconPrimary,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          splashRadius: 20,
          tooltip: 'More',
          onPressed: _showProfileActionsSheet,
        ),
        const SizedBox(width: 8),
      ];
    }

    return [
      IconButton(
        icon: const HugeIcon(
          icon: HugeIcons.strokeRoundedSearch01,
          color: AppColors.iconPrimary,
          size: 20,
        ),
        tooltip: 'Search',
        onPressed: _openSearch,
      ),
    ];
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchDiscoveryScreen(),
      ),
    );
  }

  Future<void> _showProfileActionsSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfacePrimary,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildProfileActionItem(
                context: sheetContext,
                value: 'search',
                icon: HugeIcons.strokeRoundedSearch01,
                label: 'Search',
              ),
              _buildProfileActionItem(
                context: sheetContext,
                value: 'feedback',
                icon: HugeIcons.strokeRoundedIdea01,
                label: 'Feedback',
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'search':
        _openSearch();
        return;
      case 'feedback':
        _showFeedbackDialog();
        return;
    }
  }

  Widget _buildProfileActionItem({
    required BuildContext context,
    required String value,
    required List<List<dynamic>> icon,
    required String label,
  }) {
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      leading: HugeIcon(
        icon: icon,
        color: AppColors.textSecondary,
        size: 20,
      ),
      title: Text(
        label,
        style: AppTypography.bodyLarge.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _openWhatsAppGroupChat() async {
    try {
      final launched = await launchUrl(
        _whatsAppGroupUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showChatSupportError();
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error opening WhatsApp group: $e');
      if (mounted) {
        _showChatSupportError();
      }
    }
  }

  void _showChatSupportError() {
    VayuSnackBar.showError(context, AppText.get('error_whatsapp'));
  }



  /// **NEW: Feedback Dialog**
  void _showFeedbackDialog() {
    ProfileDialogsWidget.showFeedbackDialog(context);
  }

  /// **NEW: Open Report Dialog**
  void _openReportDialog(
      {required String targetType, required String targetId}) {
    ProfileDialogsWidget.showReportDialog(
      context,
      targetType: targetType,
      targetId: targetId,
    );
  }

  /// **NEW: Show Professional FAQ Dialog**
  void _showFAQDialog() {
    ProfileDialogsWidget.showFAQDialog(context);
  }

  /// Subscriber list sheet. Opening it marks subscribers as seen, which is
  /// what clears the red dot on the Subscribers stat.
  void _handleSubscribersTap() {
    AppLogger.log('👥 ProfileScreen: Subscribers tapped - opening list');
    showSubscribersBottomSheet(context);
  }

  /// Refreshes the unseen-subscriber count for the signed-in creator only.
  /// Repeat calls are debounced inside the manager.
  void _refreshSubscribersBadge({bool force = false}) {
    if (_isLocalManager) return; // viewing someone else's profile
    unawaited(
      ref.read(subscribersBadgeManagerProvider).refresh(force: force),
    );
  }

  /// **NEW: Navigate to Creator Revenue Screen when earnings is tapped**
  void _handleEarningsTap() {
    AppLogger.log(
        '💰 ProfileScreen: Earnings tapped - navigating to CreatorRevenueScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreatorRevenueScreen(),
      ),
    );
  }







  Future<bool> _checkPaymentSetupStatus() async {
    try {
      // **FIX: Check user-specific flag first**
      ProfileScreenLogger.logPaymentSetupCheck();
      final prefs = await SharedPreferences.getInstance();

      // **FIX: Get user ID for user-specific check**
      final userData = _profileStateManager.userData;
      final userId = userData?['googleId'] ?? userData?['id'];

      // **FIX: Check user-specific flag first**
      if (userId != null) {
        final hasUserSpecificSetup =
            prefs.getBool('has_payment_setup_$userId') ?? false;
        if (hasUserSpecificSetup) {
          ProfileScreenLogger.logPaymentSetupFound();
          AppLogger.log(
              '✅ User-specific payment setup found for user: $userId');
          return true;
        }
      }

      // **FALLBACK: Check global flag for backward compatibility**
      final hasPaymentSetup = prefs.getBool('has_payment_setup') ?? false;
      if (hasPaymentSetup) {
        ProfileScreenLogger.logPaymentSetupFound();
        AppLogger.log('✅ Global payment setup flag found');
        return true;
      }

      // **NEW: If no flag, try to load payment setup data from backend**
      if (_profileStateManager.userData != null &&
          _profileStateManager.userData!['_id'] != null) {
        ProfileScreenLogger.logDebugInfo(
            'No payment setup flag found, checking backend data...');
        final hasBackendSetup = await _checkBackendPaymentSetup();
        if (hasBackendSetup) {
          // **FIX: Set both user-specific and global flags**
          if (userId != null) {
            await prefs.setBool('has_payment_setup_$userId', true);
            AppLogger.log(
                '✅ Set user-specific payment setup flag for user: $userId');
          }
          await prefs.setBool('has_payment_setup', true);
          ProfileScreenLogger.logPaymentSetupFound();
          return true;
        }
      }

      ProfileScreenLogger.logPaymentSetupNotFound();
      AppLogger.log('ℹ️ No payment setup found for user');
      return false;
    } catch (e) {
      ProfileScreenLogger.logPaymentSetupCheckError(e.toString());
      return false;
    }
  }

  // **NEW: Method to check payment setup from backend**
  Future<bool> _checkBackendPaymentSetup() async {
    try {
      ProfileScreenLogger.logDebugInfo(
          'Starting backend payment setup check...');
      final userData = _profileStateManager.getUserData();
      final token = userData?['token'];

      if (token == null) {
        ProfileScreenLogger.logError(
            'No token available for backend payment setup check');
        return false;
      }

      ProfileScreenLogger.logApiCall(
          endpoint: 'creator-payouts/profile', method: 'GET');
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      ProfileScreenLogger.logApiResponse(
        endpoint: 'creator-payouts/profile',
        statusCode: response.statusCode,
        body: response.body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final paymentMethod = data['creator']?['preferredPaymentMethod'];
        final paymentDetails = data['paymentDetails'];

        ProfileScreenLogger.logDebugInfo('Payment method: $paymentMethod');
        ProfileScreenLogger.logDebugInfo('Payment details: $paymentDetails');

        // Check if user has completed payment setup
        if (paymentMethod != null &&
            paymentMethod.isNotEmpty &&
            paymentDetails != null) {
          ProfileScreenLogger.logPaymentSetupFound(method: paymentMethod);
          return true;
        } else {
          ProfileScreenLogger.logDebugWarning(
              'Payment setup incomplete - method: $paymentMethod, details: $paymentDetails');
        }
      } else {
        ProfileScreenLogger.logApiError(
          endpoint: 'creator-payouts/profile',
          error: 'API call failed with status ${response.statusCode}',
        );
      }

      return false;
    } catch (e) {
      ProfileScreenLogger.logApiError(
        endpoint: 'creator-payouts/profile',
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> _checkUpiIdStatus() async {
    try {
      if (widget.userId != null) {
        _hasUpiId.value = true;
        return;
      }

      if (_profileStateManager.hasUpiId) {
        _hasUpiId.value = true;
        return;
      }

      // Profile API intentionally excludes auth tokens. Read the token from
      // AuthService before calling the authenticated payout endpoint.
      final authData = await _authService.getUserData();
      final token = authData?['token'];

      if (token == null) {
        AppLogger.log('⚠️ ProfileScreen: Auth token unavailable for UPI check');
        return;
      }

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rawPaymentDetails = data['paymentDetails'];
        final paymentDetails = rawPaymentDetails is Map
            ? Map<String, dynamic>.from(rawPaymentDetails)
            : null;
        final upiId = paymentDetails?['upiId']?.toString().trim() ?? '';

        _profileStateManager.setPaymentDetails(paymentDetails);
        _hasUpiId.value = upiId.isNotEmpty;
      } else {
        AppLogger.log(
            '⚠️ ProfileScreen: UPI check returned ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Error checking UPI ID status: $e');
      if (_profileStateManager.hasUpiId) {
        _hasUpiId.value = true;
      }
    }
  }


  /// **OPTIMIZED: Cache profile data to SmartCacheManager**
  /// **ENHANCED: Uses unified SmartCacheManager (same as ProfileStateManager)**
  /// Cache persists when user navigates back to same profile
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      // NOTE: Hive caching removed to prevent data mismatch bugs.
      // We rely on SmartCacheManager for short-term memory caching.
      final targetUserId = profileData['googleId'] ?? profileData['id'];
      if (targetUserId != null) {
        final smartCache = SmartCacheManager();
        await smartCache.initialize();
        if (smartCache.isInitialized) {
          final cacheKey = 'user_profile_$targetUserId';
          await smartCache.put(cacheKey, profileData, cacheType: 'user_profile');
          AppLogger.log('✅ ProfileScreen: Cached profile data to SmartCache');
        }
      }
    } catch (e) {
      ProfileScreenLogger.logWarning('Error caching profile data: $e');
    }
  }

  Future<void> _cacheCurrentProfile() async {
    if (_profileStateManager.userData != null) {
      await _cacheProfileData(_profileStateManager.userData!);
    }
  }


  /// **SIMPLIFIED: Cache earnings - simple timestamp only**
  Future<void> _cacheEarningsData(Map<String, dynamic> earningsData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _profileStateManager.userData?['googleId'] ??
          _profileStateManager.userData?['id'];

      if (userId == null) {
        return;
      }

      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';

      await prefs.setString(cacheKey, json.encode(earningsData));
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

      AppLogger.log('✅ ProfileScreen: Earnings cached');
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error caching earnings: $e');
    }
  }

  /// **SIMPLIFIED: Fast earnings cache - simple 5-minute check**
  Future<Map<String, dynamic>?> _loadCachedEarningsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _profileStateManager.userData?['googleId'] ??
          _profileStateManager.userData?['id'];

      if (userId == null) {
        return null;
      }

      final cacheKey = 'earnings_cache_$userId';
      final timestampKey = 'earnings_cache_timestamp_$userId';
      final oldMonthKey =
          'earnings_cache_month_$userId'; // **OLD KEY - clean up if exists**

      final cachedDataJson = prefs.getString(cacheKey);
      final cachedTimestamp = prefs.getInt(timestampKey);

      // **CLEANUP: Remove old month key if it exists (from previous code version)**
      if (prefs.containsKey(oldMonthKey)) {
        await prefs.remove(oldMonthKey);
        AppLogger.log('🧹 ProfileScreen: Removed old month key');
      }

      if (cachedTimestamp != null && cachedDataJson != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        final now = DateTime.now();
        final age = now.difference(cacheTime);

        // **MONTH CHECK: If cache is from different month, invalidate it**
        if (cacheTime.month != now.month || cacheTime.year != now.year) {
          AppLogger.log(
              '🔄 ProfileScreen: Earnings cache is from different month (${cacheTime.month}/${cacheTime.year} vs ${now.month}/${now.year}) - invalidating');
          await prefs.remove(cacheKey);
          await prefs.remove(timestampKey);
          return null;
        }

        // **SIMPLE: Check if cache is fresh (5 minutes)**
        if (age < const Duration(minutes: 5)) {
          // Cache is fresh and from current month - use it
          // **OPTIMIZED: Use background isolate for non-blocking JSON decoding**
          final decoded = await compute(_parseJsonData, cachedDataJson);
          return Map<String, dynamic>.from(decoded);
        } else {
          // Cache is stale - clear it
          await prefs.remove(cacheKey);
          await prefs.remove(timestampKey);
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileScreen: Error loading cached earnings: $e');
    }
    return null;
  }

  /// **FIXED: Fast earnings refresh with month reset detection**
  Future<void> _refreshEarningsData({bool forceRefresh = false}) async {
    try {
      // Only refresh earnings for own profile
      if (widget.userId != null) {
        return;
      }

      final userData = await _authService.getUserData();
      if (userData == null) {
        return;
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId ??
          _profileStateManager.userData?['googleId'] ??
          _profileStateManager.userData?['id'];

      // **MONTH RESET: Check if cache is from different month - always force refresh**
      if (userId != null) {
        final timestampKey = 'earnings_cache_timestamp_$userId';
        final cachedTimestamp = prefs.getInt(timestampKey);

        if (cachedTimestamp != null) {
          final cacheTime =
              DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
          // **FIX: Force refresh if month changed (not just day 1)**
          if (cacheTime.month != now.month || cacheTime.year != now.year) {
            AppLogger.log(
                '🔄 ProfileScreen: Month changed - forcing fresh earnings calculation');
            forceRefresh = true;
            // Clear earnings cache when month changes
            await prefs.remove('earnings_cache_$userId');
            await prefs.remove(timestampKey);
            AppLogger.log(
                '🧹 ProfileScreen: Cleared earnings cache (month changed)');
          }
        }
      }

      // **MONTH RESET: Also check if it's the 1st of the month - always force refresh**
      if (now.day == 1) {
        AppLogger.log(
            '🔄 ProfileScreen: Month start detected - forcing fresh earnings calculation');
        forceRefresh = true;
        if (userId != null) {
          await prefs.remove('earnings_cache_$userId');
          await prefs.remove('earnings_cache_timestamp_$userId');
          AppLogger.log(
              '🧹 ProfileScreen: Cleared earnings cache at month start');
        }
      }

      // **SIMPLE CACHE: Check if cache is fresh (5 minutes) - but skip if month start**
      if (!forceRefresh) {
        final cachedEarnings = await _loadCachedEarningsData();
        if (cachedEarnings != null) {
          AppLogger.log('⚡ ProfileScreen: Using cached earnings (fast)');
          return; // Cache is fresh, skip API call
        }
      }

      // **FAST: Load earnings in parallel (non-blocking)**
      AppLogger.log('💰 ProfileScreen: Loading fresh earnings...');
      Future.microtask(() async {
        try {
          final earningsData = await _adService.getCreatorRevenueSummary(forceRefresh: forceRefresh);
          await _cacheEarningsData(earningsData);
          AppLogger.log('✅ ProfileScreen: Earnings loaded (fresh data)');
        } catch (e) {
          AppLogger.log('⚠️ ProfileScreen: Earnings load failed: $e');
          // Silent fail - earnings are optional
        }
      });
    } catch (e) {
      AppLogger.log('⚠️ ProfileScreen: Earnings refresh error: $e');
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._child);

  final Widget _child;

  @override
  double get minExtent => 60.0;
  @override
  double get maxExtent => 60.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _child;
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

/// **TOP-LEVEL: Handle JSON parsing in background isolate to prevent UI thread jank**
Map<String, dynamic> _parseJsonData(String jsonString) {
  return json.decode(jsonString) as Map<String, dynamic>;
}


