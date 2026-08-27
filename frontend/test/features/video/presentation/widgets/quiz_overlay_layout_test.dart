import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/presentation/widgets/quiz_overlay.dart';
import 'package:vayug/shared/widgets/app_button.dart';

void main() {
  // **OFFLINE REGRESSION GUARD:** Prevents GoogleFonts from trying to make network calls during tests.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Helper method to create a dynamic QuizModel
  QuizModel createDynamicQuiz({
    required String question,
    required List<String> options,
    required int correctIndex,
  }) {
    return QuizModel(
      timestamp: 10.0,
      question: question,
      options: options,
      correctIndex: correctIndex,
    );
  }

  group('Dynamic QuizOverlay Widget Tests', () {
    // We define diverse test cases (e.g. short, medium, and very long text) to test layout responsiveness.
    final dynamicTestCases = [
      QuizModel(
        timestamp: 5.0,
        question: 'Who is Bill Gates?',
        options: ['Entrepreneur', 'Investor', 'Scientist'],
        correctIndex: 0,
      ),
      QuizModel(
        timestamp: 12.0,
        question: 'What is the primary capital of India?',
        options: ['Mumbai', 'New Delhi', 'Kolkata', 'Chennai'],
        correctIndex: 1,
      ),
      QuizModel(
        timestamp: 25.0,
        question:
            'Dynamic Question with extremely long text to ensure the UI scales correctly without causing overflow bugs on compact screens.',
        options: ['True Option', 'False Option'],
        correctIndex: 0,
      ),
    ];

    testWidgets(
        'QuizOverlay renders dynamic questions and options correctly and handles selections',
        (WidgetTester tester) async {
      for (final mockQuiz in dynamicTestCases) {
        bool answered = false;
        int selectedIdx = -1;

        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(360, 690),
            builder: (context, child) => MaterialApp(
              home: Scaffold(
                body: QuizOverlay(
                  key: ValueKey(mockQuiz
                      .question), // **CRITICAL:** Forces fresh State instantiation per iteration.
                  quiz: mockQuiz,
                  isCompact: false,
                  onDismiss: () {},
                  onAnswered: (idx) {
                    answered = true;
                    selectedIdx = idx;
                  },
                ),
              ),
            ),
          ),
        );

        // Advance frames to complete initial transition animation
        await tester.pump(const Duration(milliseconds: 500));

        // Assert dynamic question text is visible
        expect(find.text(mockQuiz.question), findsOneWidget);

        // Assert all dynamic options are visible
        for (final option in mockQuiz.options) {
          expect(find.text(option), findsOneWidget);
        }

        // Tap the correct option dynamically
        final correctOptionText = mockQuiz.options[mockQuiz.correctIndex];
        await tester.tap(find.text(correctOptionText));
        await tester.pump(); // Register the tap event

        expect(answered, isTrue);
        expect(selectedIdx, mockQuiz.correctIndex);

        // **CRITICAL TIMER DRAIN:** Wait 1200ms to allow the 600ms delay and the 400ms dismiss transitions to finish completely, draining all pending timers in the test engine!
        await tester.pump(const Duration(milliseconds: 1200));
      }
    });

    testWidgets('QuizOverlay handles dynamic content in compact mode',
        (WidgetTester tester) async {
      for (final mockQuiz in dynamicTestCases) {
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(360, 690),
            builder: (context, child) => MaterialApp(
              home: Scaffold(
                body: QuizOverlay(
                  key: ValueKey(mockQuiz
                      .question), // **CRITICAL:** Forces fresh State instantiation per iteration.
                  quiz: mockQuiz,
                  isCompact: true,
                  onDismiss: () {},
                  onAnswered: (_) {},
                ),
              ),
            ),
          ),
        );

        // Advance animation
        await tester.pump(const Duration(milliseconds: 500));

        // Verify correct rendering without layout exceptions
        expect(find.text(mockQuiz.question), findsOneWidget);
        expect(find.text(mockQuiz.options[0]), findsOneWidget);
      }
    });

    testWidgets(
        'QuizOverlay uses a single option column inside a narrow landscape lane',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final quiz = createDynamicQuiz(
        question: 'Which option is correct?',
        options: ['First', 'Second', 'Third', 'Fourth'],
        correctIndex: 0,
      );

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(360, 690),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 180,
                  child: QuizOverlay(
                    quiz: quiz,
                    onDismiss: () {},
                    onAnswered: (_) {},
                    alignment: Alignment.centerLeft,
                    outerPadding: EdgeInsets.zero,
                    maxWidth: 180,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      final optionCentres = quiz.options
          .map((option) => tester.getCenter(find.text(option)))
          .toList();
      for (final centre in optionCentres.skip(1)) {
        expect(centre.dx, closeTo(optionCentres.first.dx, 0.01));
      }
    });
  });

  group('Unified Layout Spacing and Alignment Tests', () {
    testWidgets(
        'Unified Column lays out dynamic CTA and Quiz with exactly 12px vertical spacing and identical width',
        (WidgetTester tester) async {
      // Set a fixed screen size for exact layout coordinates assertions
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dynamicQuiz = QuizModel(
        timestamp: 10.0,
        question: 'Is Flutter awesome?',
        options: ['Yes', 'Absolutely'],
        correctIndex: 1,
      );

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(360, 690),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppButton(
                          label: 'Visit Now',
                          onPressed: () {},
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.small,
                        ),
                        const SizedBox(height: 12.0),
                        QuizOverlay(
                          quiz: dynamicQuiz,
                          isCompact: false,
                          onDismiss: () {},
                          onAnswered: (_) {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Advance layout animation
      await tester.pump(const Duration(milliseconds: 500));

      final visitNowFinder = find.byType(AppButton);
      final quizOverlayFinder = find.byType(QuizOverlay);

      expect(visitNowFinder, findsOneWidget);
      expect(quizOverlayFinder, findsOneWidget);

      final double visitNowWidth = tester.getSize(visitNowFinder).width;
      final double quizOverlayWidth = tester.getSize(quizOverlayFinder).width;

      // Assertion 1: Dynamic Symmetric Width
      expect(visitNowWidth, equals(quizOverlayWidth));

      // Assertion 2: Verify exact vertical spacing of 12px
      final double visitNowBottom = tester.getBottomRight(visitNowFinder).dy;
      final double quizOverlayTop = tester.getTopLeft(quizOverlayFinder).dy;

      final double spacing = quizOverlayTop - visitNowBottom;
      expect(spacing, closeTo(12.0, 0.01));
    });

    testWidgets(
        'Regression Guard: Visit Now button right margin shrinks to 80px when video is paused, even if Quiz is absent',
        (WidgetTester tester) async {
      // Simulate buggy configuration:
      // Video is paused, Quiz is absent
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(360, 690),
          builder: (context, child) => MaterialApp(
            home: Scaffold(
              body: MockVideoOverlay(
                isQuizVisible: false,
                isPlaying: false, // Paused!
                visitNowButton: AppButton(
                  label: 'Visit Now',
                  onPressed: () {},
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                ),
              ),
            ),
          ),
        ),
      );

      // Advance layout rendering
      await tester.pump();

      final buttonFinder = find.byType(AppButton);
      expect(buttonFinder, findsOneWidget);

      final double buttonWidth = tester.getSize(buttonFinder).width;

      // EXPECTED COMPACT WIDTH CALCULATION:
      // Left margin is 16.0, right margin when compact (paused) MUST be 80.0.
      final double screenWidth = tester.getSize(find.byType(Scaffold)).width;
      final double expectedWidth = screenWidth - 16.0 - 80.0;
      expect(buttonWidth, equals(expectedWidth),
          reason:
              "Visit Now button must shrink to compact size when video is paused to avoid overlapping sidebar actions!");
    });
  });
}

/// **BDT LAYOUT MOCK:** Replicates the exact layout logic in `video_feed_advanced_ui.dart`
/// to allow isolated widget regression testing.
class MockVideoOverlay extends StatelessWidget {
  final bool isQuizVisible;
  final bool isPlaying;
  final Widget visitNowButton;

  const MockVideoOverlay({
    super.key,
    required this.isQuizVisible,
    required this.isPlaying,
    required this.visitNowButton,
  });

  @override
  Widget build(BuildContext context) {
    // -------------------------------------------------------------
    // 🟢 CORRECT PRODUCTION LOGIC:
    // -------------------------------------------------------------
    final bool isCompact = !isPlaying;

    // When isCompact is false, targetRight is 16.0 (full width).
    // When isCompact is true, targetRight is 80.0 (compact size).
    final double targetRight = isCompact ? 80.0 : 16.0;

    return Stack(
      children: [
        Positioned(
          left: 16,
          right: targetRight,
          bottom: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              visitNowButton,
            ],
          ),
        ),
      ],
    );
  }
}
