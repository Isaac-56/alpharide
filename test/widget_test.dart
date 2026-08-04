import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/account/wallet_screens.dart';

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
}
