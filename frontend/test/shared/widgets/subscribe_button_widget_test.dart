import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayug/shared/widgets/subscribe_button_widget.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required bool isSubscribed,
    bool isLoading = false,
    VoidCallback? onPressed,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => Scaffold(
            body: SubscribeButtonWidget(
              isSubscribed: isSubscribed,
              isLoading: isLoading,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the canonical label for each subscription state',
      (tester) async {
    await pumpButton(
      tester,
      isSubscribed: false,
      onPressed: () {},
    );
    expect(find.text('Subscribe'), findsOneWidget);

    await pumpButton(
      tester,
      isSubscribed: true,
      onPressed: () {},
    );
    expect(find.text('Subscribed'), findsOneWidget);
  });

  testWidgets('invokes its callback only while enabled', (tester) async {
    var tapCount = 0;
    await pumpButton(
      tester,
      isSubscribed: false,
      onPressed: () => tapCount++,
    );

    await tester.tap(find.byType(SubscribeButtonWidget));
    expect(tapCount, 1);

    await pumpButton(
      tester,
      isSubscribed: false,
      isLoading: true,
      onPressed: () => tapCount++,
    );
    await tester.tap(find.byType(SubscribeButtonWidget));

    expect(tapCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
