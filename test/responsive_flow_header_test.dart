import 'package:passengerapp/core/widgets/alpha_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'flow headers keep titles and actions visible at large text sizes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Center(
                child: SizedBox(
                  width: 280,
                  child: AlphaFlowHeader(
                    title: 'Choose your pickup location',
                    subtitle: 'Confirm where the driver should meet you.',
                    leading: Icon(Icons.location_on_outlined),
                    trailing: Text('Edit'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.text('Choose your pickup location'),
      );
      expect(title.maxLines, isNull);
      expect(
        tester.getTopLeft(find.text('Edit')).dy,
        greaterThan(
          tester.getBottomLeft(find.text('Choose your pickup location')).dy,
        ),
      );
    },
  );
}
