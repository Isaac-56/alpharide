import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/core/theme/alpha_theme.dart';
import 'package:passengerapp/core/widgets/alpha_components.dart';

void main() {
  testWidgets('reference flow components stay readable in light and dark mode', (
    WidgetTester tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[AlphaTheme.light, AlphaTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AlphaMapSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AlphaFlowHeader(
                    title: 'Confirm your ride',
                    subtitle: 'Check the route before ordering.',
                    compact: true,
                  ),
                  SizedBox(height: 12),
                  AlphaSurfaceCard(
                    child: AlphaMetricChip(
                      icon: Icons.route_rounded,
                      label: '8 min',
                      emphasized: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Confirm your ride'), findsOneWidget);
      expect(find.text('8 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
