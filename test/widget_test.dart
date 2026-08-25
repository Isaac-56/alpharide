import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/account/wallet_screens.dart';
import 'package:passengerapp/home/order_panel.dart';

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
    'collapsed order panel shows a generic order prompt',
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

      expect(find.text('Order now'), findsOneWidget);
      expect(find.text('Choose a ride that fits you'), findsOneWidget);
      expect(find.byIcon(Icons.local_taxi_rounded), findsOneWidget);
      expect(find.text('Set pick-up point'), findsOneWidget);
      expect(find.text('Alpha Boda'), findsNothing);
    },
  );
}
