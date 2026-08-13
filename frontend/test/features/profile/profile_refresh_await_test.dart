import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/core/interfaces/i_payment_setup_service.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

class MockAuthService extends Mock implements IAuthService {}

class MockUserService extends Mock implements IUserService {}

class MockVideoService extends Mock implements IVideoService {}

class MockPaymentSetupService extends Mock implements IPaymentSetupService {}

class MockNoticeService extends Mock implements INoticeService {}

class MockNotificationService extends Mock implements INotificationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual refresh waits for fresh videos before completing', () async {
    final authService = MockAuthService();
    final userService = MockUserService();
    final videoService = MockVideoService();
    final profileResponse = Completer<Map<String, dynamic>>();
    final videoResponse = Completer<List<VideoModel>>();

    when(() => authService.currentUserId).thenReturn(null);
    when(() => authService.getUserData()).thenAnswer(
      (_) async => <String, dynamic>{
        'id': 'user-1',
        'googleId': 'user-1',
      },
    );
    when(() => userService.getUserById('user-1'))
        .thenAnswer((_) => profileResponse.future);
    when(
      () => videoService.getUserVideos(
        'user-1',
        forceRefresh: true,
        page: 1,
        limit: 1000,
      ),
    ).thenAnswer((_) => videoResponse.future);

    final manager = ProfileStateManager(
      videoService: videoService,
      authService: authService,
      userService: userService,
      paymentSetupService: MockPaymentSetupService(),
      noticeService: MockNoticeService(),
      notificationService: MockNotificationService(),
    );

    var refreshCompleted = false;
    final refresh = manager.refreshData().then((_) {
      refreshCompleted = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(refreshCompleted, isFalse);

    profileResponse.complete(<String, dynamic>{
      'id': 'user-1',
      'googleId': 'user-1',
      'name': 'Test User',
    });
    await Future<void>.delayed(Duration.zero);

    expect(refreshCompleted, isFalse);

    videoResponse.complete(<VideoModel>[]);
    await refresh;

    expect(refreshCompleted, isTrue);
    manager.dispose();
  });
}
