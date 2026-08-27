import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_header_widget.dart';
import 'package:vayug/shared/widgets/follow_button_widget.dart';
import 'package:vayug/shared/widgets/subscribe_button_widget.dart';

class MockProfileStateManager extends Mock implements ProfileStateManager {}

class MockAuthService extends Mock implements IAuthService {}

void main() {
  late MockProfileStateManager stateManager;
  late MockAuthService authService;

  setUp(() {
    stateManager = MockProfileStateManager();
    authService = MockAuthService();
    when(() => authService.currentUserId).thenReturn(null);
    when(
      () => authService.getUserData(
        skipTokenRefresh: any(named: 'skipTokenRefresh'),
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer((_) async => null);
    when(() => stateManager.userData).thenReturn(<String, dynamic>{
      'followersCount': 0,
    });
    when(() => stateManager.totalVideoCount).thenReturn(2);
    when(() => stateManager.isEditing).thenReturn(false);
    when(() => stateManager.isEarningsLoading).thenReturn(false);
    when(() => stateManager.isVideosLoading).thenReturn(false);
    when(() => stateManager.cachedEarnings).thenReturn(0);
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    required bool? hasUpiId,
    bool isViewingOwnProfile = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: ProfileHeaderWidget(
                isViewingOwnProfile: isViewingOwnProfile,
                stateManager: stateManager,
                hasUpiId: hasUpiId,
                onAddUpiId: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('hides Setup Billing when the user already has a UPI ID',
      (tester) async {
    await pumpHeader(tester, hasUpiId: true);

    expect(
      find.byKey(const Key('profile_setup_billing_button')),
      findsNothing,
    );
  });

  testWidgets('shows Setup Billing when billing is unlocked without a UPI ID',
      (tester) async {
    await pumpHeader(tester, hasUpiId: false);

    expect(
      find.byKey(const Key('profile_setup_billing_button')),
      findsOneWidget,
    );

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('profile_setup_billing_button')),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.primary,
    );
  });

  testWidgets('hides Setup Billing while UPI status is being verified',
      (tester) async {
    await pumpHeader(tester, hasUpiId: null);

    expect(
      find.byKey(const Key('profile_setup_billing_button')),
      findsNothing,
    );
  });

  testWidgets('shows Subscribe action on another creator profile',
      (tester) async {
    when(() => stateManager.userData).thenReturn(<String, dynamic>{
      'googleId': 'creator-google-id',
      'name': 'Test Creator',
      'followersCount': 0,
    });

    await pumpHeader(
      tester,
      hasUpiId: null,
      isViewingOwnProfile: false,
    );

    expect(
      find.byKey(const Key('profile_subscribe_button')),
      findsOneWidget,
    );
    final subscribeButton = tester.widget<FollowButtonWidget>(
      find.byKey(const Key('profile_subscribe_button')),
    );
    expect(subscribeButton.uploaderId, 'creator-google-id');
    expect(find.byType(SubscribeButtonWidget), findsOneWidget);
  });

  testWidgets('does not show Subscribe action on the current user profile',
      (tester) async {
    await pumpHeader(tester, hasUpiId: true);

    expect(
      find.byKey(const Key('profile_subscribe_button')),
      findsNothing,
    );
  });
}
