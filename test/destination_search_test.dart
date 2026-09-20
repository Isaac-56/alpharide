import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/destination_search.dart';
import 'package:passengerapp/models/location_selection.dart';

void main() {
  testWidgets('pickup search offers an automatic current-location choice', (
    WidgetTester tester,
  ) async {
    LocationSelection? selection;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    selection = await Navigator.push<LocationSelection>(
                      context,
                      MaterialPageRoute<LocationSelection>(
                        builder: (_) => const DestinationSearch(
                          latitude: 4.8517,
                          longitude: 31.5825,
                          pickupAddress: 'Airport Road, Juba',
                          initialAddress: 'Airport Road, Juba',
                          currentLatitude: 4.8517,
                          currentLongitude: 31.5825,
                          currentAddress: 'Airport Road, Juba',
                          isPickup: true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Choose pickup'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Choose pickup'));
    await tester.pumpAndSettle();

    expect(find.text('Set pickup point on map'), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
    expect(find.text('Updates automatically as you move'), findsOneWidget);

    await tester.tap(find.text('Use my current location'));
    await tester.pumpAndSettle();

    expect(selection?.isCurrentLocation, true);
    expect(selection?.displayName, 'Airport Road, Juba');
    expect(selection?.latitude, 4.8517);
    expect(selection?.longitude, 31.5825);
  });
}
