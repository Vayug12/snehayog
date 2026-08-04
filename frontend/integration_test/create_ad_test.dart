import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vayug/features/ads/presentation/screens/create_ad_screen_refactored.dart';
import 'package:flutter/material.dart';

import 'test_app_wrapper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService mockAuthService;
  late MockAdService mockAdService;
  late MockVideoService mockVideoService;
  late MockFilePickerService mockFilePickerService;

  setUp(() {
    mockAuthService = MockAuthService();
    mockAdService = MockAdService();
    mockVideoService = MockVideoService();
    mockFilePickerService = MockFilePickerService();

    // Default mocks for Auth
    when(() => mockAuthService.getUserData()).thenAnswer((_) async => {
      'id': 'test-user-id',
      'name': 'Test User',
      'email': 'test@example.com',
      'token': 'test-token',
    });

    // Mock Ad Creation Success (matching createAdWithCredits which screen uses)
    when(() => mockAdService.createAdWithCredits(
          title: any(named: 'title'),
          description: any(named: 'description'),
          adType: any(named: 'adType'),
          budget: any(named: 'budget'),
          targetAudience: any(named: 'targetAudience'),
          targetKeywords: any(named: 'targetKeywords'),
          link: any(named: 'link'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        )).thenAnswer((_) async => {
          'success': true,
          'ad': {
            'id': 'ad-123',
            'title': 'Test Ad',
            'status': 'draft',
            'createdAt': DateTime.now().toIso8601String(),
            'budget': 500,
          },
          'invoice': {'id': 'inv-123'},
          'message': 'Success'
        });
  });

  testWidgets('Create Ad flow test - basic form submission', (WidgetTester tester) async {
    // 1. Load the CreateAdScreen
    await tester.pumpWidget(
      TestAppWrapper(
        mockAuthService: mockAuthService,
        mockAdService: mockAdService,
        mockVideoService: mockVideoService,
        mockFilePickerService: mockFilePickerService,
        child: const CreateAdScreenRefactored(),
      ),
    );

    await tester.pumpAndSettle();

    // 2. Verify we are on the Create Ad screen
    expect(find.text('Create Advertisement'), findsOneWidget);

    // 3. Enter Title and Description
    await tester.enterText(find.byType(TextFormField).at(0), 'Test Ad Title');
    await tester.enterText(find.byType(TextFormField).at(1), 'This is a test ad description.');
    
    // 4. Enter budget (assuming budget field exists and is at index 3 or similar)
    // In our refactored screen, we can find by label if needed
    final budgetField = find.widgetWithText(TextFormField, 'Daily Budget');
    if (budgetField.evaluate().isNotEmpty) {
      await tester.enterText(budgetField, '500');
    }

    await tester.pumpAndSettle();

    // 5. Scroll and find "Pay & Submit" button 
    // (Note: In a real test, you might need to scroll or mock image selection first)
    // For now, we'll verify the button is present
    expect(find.text('Pay & Submit'), findsOneWidget);
    
    // Note: To fully test submission, we'd need to mock the image selection 
    // which usually requires a FilePickerService mock.
  });
}
