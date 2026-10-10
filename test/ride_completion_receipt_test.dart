import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:passengerapp/home/driver_search_screen.dart';
import 'package:passengerapp/models/ride_backend.dart';

void main() {
  for (final double scale in <double>[1, 1.8]) {
    testWidgets('receipt fits a small screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 640),
                textScaler: TextScaler.linear(scale),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RideCompletionReceipt(
                  state: const RideLiveState(
                    rideId: 'ride',
                    status: 'completed',
                    driverId: null,
                    driver: null,
                    estimatedFare: 20000,
                    finalFare: 10300,
                    currencyCode: 'SSP',
                    waitingCharge: 300,
                  ),
                  pickupAddress: 'A long pickup address near Imperial Plaza Hotel, Juba, Central Equatoria',
                  destinationAddress: 'Customer-selected drop-off near Grand Hotel, Juba, Central Equatoria',
                  onDone: () => closed = true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('10,300 SSP'), findsOneWidget);
      expect(find.text('10,000 SSP'), findsOneWidget);
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Done'));
      expect(closed, isTrue);
    });
  }
}
