import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/authentication/auth_flow_navigation.dart';
import 'package:passengerapp/home/cancel_reason_screen.dart';

void main() {
  testWidgets('sign out returns to the authentication root route', (
    WidgetTester tester,
  ) async {
    bool signedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Column(
              children: <Widget>[
                const Text('Authentication root'),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext pageContext) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () =>
                              AuthFlowNavigation.signOutAndReturnToRoot(
                                pageContext,
                                () async => signedOut = true,
                              ),
                          child: const Text('Sign out safely'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open account page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open account page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out safely'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
    expect(find.text('Authentication root'), findsOneWidget);
    expect(find.text('Sign out safely'), findsNothing);
  });

  testWidgets('custom cancellation reason returns the typed explanation', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<String> selectedReason = ValueNotifier<String>('');
    addTearDown(selectedReason.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: selectedReason,
              builder: (BuildContext context, String reason, Widget? child) {
                return Column(
                  children: <Widget>[
                    Text('Selected: $reason'),
                    ElevatedButton(
                      onPressed: () async {
                        final String? result = await Navigator.of(context)
                            .push<String>(
                              MaterialPageRoute<String>(
                                builder: (_) => const CancelReasonScreen(),
                              ),
                            );
                        if (result != null) selectedReason.value = result;
                      },
                      child: const Text('Open cancellation'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open cancellation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom reason'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('customCancellationReasonField')),
      'The pickup point is unsafe',
    );
    await tester.pump();
    await tester.tap(find.text('Continue cancellation'));
    await tester.pumpAndSettle();

    expect(find.text('Selected: The pickup point is unsafe'), findsOneWidget);
    expect(find.byType(CancelReasonScreen), findsNothing);
  });
}
