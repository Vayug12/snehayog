import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_player_layout.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_player_overlay.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    required Size viewport,
    required bool isPortrait,
    bool isSeekingBuffering = false,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(360, 690),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: VayuPlayerOverlay(
              controller: controller,
              showControlsVN: ValueNotifier(true),
              isControlsLockedVN: ValueNotifier(false),
              isSeekingBufferingVN: ValueNotifier(isSeekingBuffering),
              isPortrait: isPortrait,
              isFullScreenManual: false,
              onTogglePlay: () {},
              onMoreOptions: () {},
              onNext: () {},
              onPrevious: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('portrait uses compact utility and primary control sizing',
      (tester) async {
    await pumpOverlay(
      tester,
      viewport: const Size(360, 690),
      isPortrait: true,
    );

    expect(tester.widget<Icon>(find.byIcon(Icons.more_vert_rounded)).size, 20);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).size,
      30,
    );

    final moreButton = find.ancestor(
      of: find.byIcon(Icons.more_vert_rounded),
      matching: find.byType(InteractiveScaleButton),
    );
    final playButton = find.ancestor(
      of: find.byIcon(Icons.play_arrow_rounded),
      matching: find.byType(InteractiveScaleButton),
    );

    expect(tester.getSize(moreButton), const Size.square(36));
    expect(tester.getSize(playButton), const Size.square(48));
    expect(tester.getCenter(playButton).dx, closeTo(180, 0.01));
  });

  testWidgets('landscape gives play control hierarchy and balanced spacing',
      (tester) async {
    await pumpOverlay(
      tester,
      viewport: const Size(690, 360),
      isPortrait: false,
    );

    expect(tester.widget<Icon>(find.byIcon(Icons.more_vert_rounded)).size, 20);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.skip_previous_rounded)).size,
      26,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).size,
      40,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.skip_next_rounded)).size, 26);

    final previousButton = find.ancestor(
      of: find.byIcon(Icons.skip_previous_rounded),
      matching: find.byType(InteractiveScaleButton),
    );
    final playButton = find.ancestor(
      of: find.byIcon(Icons.play_arrow_rounded),
      matching: find.byType(InteractiveScaleButton),
    );
    final nextButton = find.ancestor(
      of: find.byIcon(Icons.skip_next_rounded),
      matching: find.byType(InteractiveScaleButton),
    );

    expect(tester.getSize(previousButton), const Size.square(44));
    expect(tester.getSize(playButton), const Size.square(64));
    expect(tester.getSize(nextButton), const Size.square(44));
    expect(tester.getCenter(playButton).dx, closeTo(345, 0.01));

    final leadingGap = tester.getTopLeft(playButton).dx -
        tester.getTopRight(previousButton).dx;
    final trailingGap =
        tester.getTopLeft(nextButton).dx - tester.getTopRight(playButton).dx;
    expect(leadingGap, closeTo(VayuPlayerLayout.transportGap, 0.01));
    expect(trailingGap, closeTo(leadingGap, 0.01));
  });

  testWidgets('seek buffering hides the play pause control', (tester) async {
    await pumpOverlay(
      tester,
      viewport: const Size(360, 690),
      isPortrait: true,
      isSeekingBuffering: true,
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  test('utility sizing keeps landscape actions visually consistent', () {
    expect(VayuPlayerLayout.utilityIconSize(isPortrait: false), 20);
    expect(VayuPlayerLayout.utilityControlSize(isPortrait: false), 40);
    expect(VayuPlayerLayout.compactIconPadding, 2);
    expect(VayuPlayerLayout.compactSurfaceSize(20), 24);
  });
}
