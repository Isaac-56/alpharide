import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/account/wallet_screens.dart';
import 'package:passengerapp/home/order_panel.dart';
import 'package:passengerapp/models/ride_option.dart';

void main() {
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
    'collapsed order panel shows the car and route-based fare',
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
              collapsed: true,
              onExpand: () {},
              routeDistanceMeters: 10000,
              routeDuration: const Duration(minutes: 20),
            ),
          ),
        ),
      );

      expect(find.text('Order now'), findsOneWidget);
      expect(find.text('Choose a ride that fits you'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) {
            if (widget is! Image) return false;

            final ImageProvider<Object> provider = widget.image;

            if (provider is AssetImage) {
              return provider.assetName ==
                  'assets/images/vehicles/alpha_standard.png';
            }

            if (provider is ResizeImage &&
                provider.imageProvider is AssetImage) {
              return (provider.imageProvider as AssetImage).assetName ==
                  'assets/images/vehicles/alpha_standard.png';
            }

            return false;
          },
        ),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('~ 17,500 SSP'), findsOneWidget);
      expect(find.text('Alpha Boda'), findsNothing);

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(confirmedRide?.estimatedFare, 17500);

      // Let the OrderPanel confirmation lock timer finish before the test ends.
      await tester.pump(const Duration(milliseconds: 701));
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
