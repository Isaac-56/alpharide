import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/order_panel.dart';

void main() {
  testWidgets('Standard can be confirmed without first tapping a vehicle', (tester) async {
    String? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: OrderPanel(
        pickupAddress: 'Pickup', destinationAddress: 'Destination',
        onPickupTap: () {}, onDestinationTap: () {},
        onConfirmRide: (ride, payment) => chosen = ride.id,
        collapsed: false, onExpand: () {},
        routeDistanceMeters: 1000, routeDuration: const Duration(minutes: 3),
      ),
    ))));
    final button = find.textContaining('Continue').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(chosen, 'standard');
  });
}
