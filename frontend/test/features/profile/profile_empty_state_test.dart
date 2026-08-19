import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart' as provider;
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_videos_widget.dart';

class MockProfileStateManager extends Mock implements ProfileStateManager {}

/// A creator with zero uploads used to get a completely blank tab: the empty
/// state was suppressed unless the referral unlock had already been earned,
/// which is exactly the user who has earned nothing yet.
void main() {
  late MockProfileStateManager manager;

  setUp(() {
    manager = MockProfileStateManager();
    when(() => manager.userVideos).thenReturn(const []);
    when(() => manager.isVideosLoading).thenReturn(false);
    when(() => manager.hasLoadedVideosSuccessfully).thenReturn(true);
    when(() => manager.totalVideoCount).thenReturn(0);
    when(() => manager.error).thenReturn(null);
    when(() => manager.isOwner).thenReturn(true);
  });

  Future<void> pumpEmptyState(
    WidgetTester tester, {
    required bool hasReferralBillingUnlock,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: provider.ChangeNotifierProvider<ProfileStateManager>.value(
            value: manager,
            child: ProfileVideosWidget(
              stateManager: manager,
              filterVideoType: 'yog',
              showHeader: false,
              hasReferralBillingUnlock: hasReferralBillingUnlock,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a new user with no uploads sees the empty state, not a blank tab',
      (tester) async {
    await pumpEmptyState(tester, hasReferralBillingUnlock: false);

    expect(find.text("You haven't uploaded any videos yet."), findsOneWidget);
  });

  testWidgets('the empty state does not depend on the referral unlock',
      (tester) async {
    await pumpEmptyState(tester, hasReferralBillingUnlock: true);

    expect(find.text("You haven't uploaded any videos yet."), findsOneWidget);
  });
}
