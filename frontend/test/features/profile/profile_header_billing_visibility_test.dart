import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_header_widget.dart';

class MockProfileStateManager extends Mock implements ProfileStateManager {}

void main() {
  late MockProfileStateManager stateManager;

  setUp(() {
    stateManager = MockProfileStateManager();
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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              body: ProfileHeaderWidget(
                isViewingOwnProfile: true,
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
}
