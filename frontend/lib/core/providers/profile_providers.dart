import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/managers/subscribers_badge_manager.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/video_providers.dart';
import 'package:vayug/core/providers/user_service_providers.dart';
import 'package:vayug/core/providers/notification_providers.dart';
import 'package:vayug/core/providers/notice_providers.dart';
import 'package:vayug/core/providers/payment_providers.dart';

final profileStateManagerProvider = ChangeNotifierProvider<ProfileStateManager>((ref) {
  final authService = ref.read(authServiceProvider);
  final videoService = ref.read(videoServiceProvider);
  final userService = ref.read(userServiceProvider);
  final notificationService = ref.read(notificationServiceProvider);
  final noticeService = ref.read(noticeServiceProvider);
  final paymentSetupService = ref.read(paymentSetupServiceProvider);
  return ProfileStateManager(
    authService: authService,
    videoService: videoService,
    userService: userService,
    notificationService: notificationService,
    noticeService: noticeService,
    paymentSetupService: paymentSetupService,
  );
});

/// Red-dot state for unseen subscribers on the profile Subscribers stat.
/// Kept app-wide so the badge survives profile screen rebuilds.
final subscribersBadgeManagerProvider =
    ChangeNotifierProvider<SubscribersBadgeManager>((ref) {
  return SubscribersBadgeManager();
});
