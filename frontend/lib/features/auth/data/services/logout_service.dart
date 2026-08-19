import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/core/providers/user_data_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/core/providers/profile_providers.dart';

/// **FIXED: Centralized logout service to coordinate all state managers**
class LogoutService {
  static final LogoutService _instance = LogoutService._internal();
  factory LogoutService() => _instance;
  LogoutService._internal();

  // Removed static _readProvider as we use ref now

  /// **FIXED: Perform complete logout across all state managers**
  static Future<void> performCompleteLogout(WidgetRef ref) async {
    try {
      print('🚪 LogoutService: Starting complete logout process...');

      final authController = ref.read(googleSignInProvider);
      final mainController = ref.read(mainControllerProvider);
      final userProv = ref.read(userProvider);
      final videoProv = ref.read(videoProvider);
      final profileStateManager = ref.read(profileStateManagerProvider);
      final subscribersBadge = ref.read(subscribersBadgeManagerProvider);

      // **OPTIMIZED: parallelized logout for speed**
      await Future.wait([
        // Step 1: Sign out via controller
        (() async {
          print('🚪 LogoutService: Signing out via GoogleSignInController...');
          await authController.signOut();
        })(),

        // Step 2: Reset MainController navigation state
        (() async {
          print('🚪 LogoutService: Clearing MainController...');
          await mainController.performLogout(resetIndex: false);
        })(),

        Future.microtask(() {
          print('🚪 LogoutService: Clearing UserProvider...');
          userProv.clearAllCaches();
        }),

        Future.microtask(() {
          print('🚪 LogoutService: Clearing VideoProvider...');
          videoProv.clearAllVideos();
        }),

        Future.microtask(() {
          print('🚪 LogoutService: Clearing ProfileStateManager...');
          profileStateManager.clearData();
        }),

        // Badge counts are per-creator: never carry them into the next session
        Future.microtask(() {
          print('🚪 LogoutService: Clearing subscribers badge...');
          subscribersBadge.reset();
        }),
      ]);

      // **NEW: Invalidate pure providers to ensure fresh state everywhere**
      ref.invalidate(authServiceProvider);
      // ref.invalidate(...) other state if needed

      print('✅ LogoutService: Complete logout successful - All state cleared');
    } catch (e) {
      print('❌ LogoutService: Error during complete logout: $e');
      rethrow;
    }
  }

  /// **FIXED: Force refresh all state after account switch**
  static Future<void> refreshAllState(WidgetRef ref) async {
    try {
      print('🔄 LogoutService: Refreshing all state after account switch...');

      final authController = ref.read(googleSignInProvider);
      final userProv = ref.read(userProvider);
      final videoProv = ref.read(videoProvider);
      final profileStateManager = ref.read(profileStateManagerProvider);
      final subscribersBadge = ref.read(subscribersBadgeManagerProvider);

      // **OPTIMIZED: parallelized refresh for speed**
      await Future.wait([
        (() async {
          print('🔄 LogoutService: Refreshing authentication state...');
          await authController.refreshAuthState();
        })(),

        Future.microtask(() {
          print('🔄 LogoutService: Refreshing user caches...');
          userProv.clearAllCaches();
        }),

        Future.microtask(() {
          print('🔄 LogoutService: Refreshing video state...');
          videoProv.clearAllVideos();
        }),

        Future.microtask(() {
          print('🔄 LogoutService: Resetting ProfileStateManager cached data...');
          profileStateManager.clearData();
        }),

        // Next account re-fetches its own unseen count
        Future.microtask(() {
          print('🔄 LogoutService: Resetting subscribers badge...');
          subscribersBadge.reset();
        }),
      ]);

      print('✅ LogoutService: All state refreshed successfully');
    } catch (e) {
      print('❌ LogoutService: Error refreshing state: $e');
      rethrow;
    }
  }
}
