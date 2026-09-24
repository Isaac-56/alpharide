import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/account/wallet_screens.dart';
import 'package:passengerapp/home/home_screen.dart';
import 'package:passengerapp/home/order_panel.dart';
import 'package:passengerapp/models/ride_option.dart';

void main() {
  test('ride options expand as soon as a destination exists', () {
    expect(
      shouldExpandRideOptionsAfterLocationSelection(hasDestination: true),
      isTrue,
    );
    expect(
      shouldExpandRideOptionsAfterLocationSelection(hasDestination: false),
      isFalse,
    );
  });

  testWidgets(
    'wallet payment methods keep cash active and digital methods disabled',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WalletPaymentMethodsScreen(),
        ),
      );

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Wallet'), findsOneWidget);
      expect(find.text('Coming soon'), findsNWidgets(2));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'order panel requires an explicit ride choice before continuing',
    (WidgetTester tester) async {
      RideOption? confirmedRide;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPanel(
              pickupAddress: 'Current location',
              destinationAddress: 'Gudele, Juba',
              onPickupTap: () {},
              onDestinationTap: () {},
              onConfirmRide: (RideOption ride, _) {
                confirmedRide = ride;
              },
              collapsed: false,
              onExpand: () {},
              routeDistanceMeters: 10000,
              routeDuration: const Duration(minutes: 20),
            ),
          ),
        ),
      );

      expect(find.text('Choose your ride'), findsOneWidget);
      expect(find.text('Boda'), findsOneWidget);
      expect(find.text('Rickshaw'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Choose a ride above'), findsOneWidget);
      expect(find.text('Select ride'), findsOneWidget);
      expect(confirmedRide, isNull);

      await tester.tap(find.text('Boda'));
      await tester.pump();

      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('~ 17,500 SSP'), findsNWidgets(2));

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(confirmedRide?.estimatedFare, 17500);

      // Let the OrderPanel confirmation lock timer finish before the test ends.
      await tester.pump(const Duration(milliseconds: 701));
    },
  );

  testWidgets(
    'collapsed order panel opens ride choices instead of defaulting to Boda',
    (WidgetTester tester) async {
      bool expanded = false;
      RideOption? confirmedRide;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPanel(
              pickupAddress: 'Airport Road, Juba',
              destinationAddress: 'Gudele, Juba',
              onPickupTap: () {},
              onDestinationTap: () {},
              onConfirmRide: (RideOption ride, _) => confirmedRide = ride,
              collapsed: true,
              onExpand: () => expanded = true,
              routeDistanceMeters: 10000,
              routeDuration: const Duration(minutes: 20),
            ),
          ),
        ),
      );

      expect(find.text('View ride options'), findsOneWidget);
      expect(find.text('Select ride'), findsOneWidget);

      await tester.tap(find.text('View ride options'));
      await tester.pump();

      expect(expanded, true);
      expect(confirmedRide, isNull);
    },
  );

  testWidgets(
    'order panel hides placeholder fares until a destination is priced',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPanel(
              pickupAddress: 'Current location',
              destinationAddress: '',
              onPickupTap: () {},
              onDestinationTap: () {},
              onConfirmRide: (_, __) {},
              collapsed: true,
              onExpand: () {},
            ),
          ),
        ),
      );

      expect(find.text('Choose destination'), findsOneWidget);
      expect(find.text('Fare after destination'), findsOneWidget);
      expect(find.textContaining('68,000'), findsNothing);
      expect(find.textContaining('10,500'), findsNothing);
    },
  );

  testWidgets('slow fare calculation can be cancelled and retried', (
    WidgetTester tester,
  ) async {
    int cancellations = 0;
    int retries = 0;

    Future<void> pumpPanel({
      required bool calculating,
      String? error,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPanel(
              pickupAddress: 'Airport Road, Juba',
              destinationAddress: 'Gudele, Juba',
              onPickupTap: () {},
              onDestinationTap: () {},
              onConfirmRide: (_, __) {},
              collapsed: false,
              onExpand: () {},
              isCalculatingFare: calculating,
              fareCalculationError: error,
              onCancelFareCalculation: () => cancellations++,
              onRetryFareCalculation: () => retries++,
            ),
          ),
        ),
      );
    }

    await pumpPanel(calculating: true);

    expect(find.text('Cancel fare calculation'), findsOneWidget);
    await tester.tap(find.text('Cancel fare calculation'));
    await tester.pump();
    expect(cancellations, 1);

    await pumpPanel(
      calculating: false,
      error: 'Fare calculation took too long. Please try again.',
    );

    expect(find.text('Calculate fare'), findsOneWidget);
    expect(
      find.text('Fare calculation took too long. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Calculate fare'));
    await tester.pump();
    expect(retries, 1);
  });

  test('ride fare applies minimums and SSP rounding', () {
    final RideOption boda = RideOption.options.firstWhere(
      (RideOption ride) => ride.id == 'boda',
    );
    final RideOption standard = RideOption.options.firstWhere(
      (RideOption ride) => ride.id == 'standard',
    );

    expect(
      boda.calculateFare(
        distanceKilometers: 0,
      ),
      boda.minimumFare,
    );
    expect(
      boda.calculateFare(
        distanceKilometers: 1,
      ),
      4000,
    );
    expect(
      standard.calculateFare(
        distanceKilometers: 10,
      ),
      42000,
    );
  });
}
