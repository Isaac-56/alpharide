import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/home_back_scope.dart';

void main() {
  testWidgets('booking back is consumed before double-back exit', (tester) async {
    var steps = 1;
    var exits = 0;
    await tester.pumpWidget(MaterialApp(home: HomeBackScope(
      onBackStep: () { if (steps > 0) { steps--; return true; } return false; },
      onExit: () => exits++, child: const Scaffold(body: Text('Home')),
    )));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(steps, 0);
    expect(find.text('Press back again to exit'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    expect(find.text('Press back again to exit'), findsOneWidget);
    await tester.binding.handlePopRoute();
    expect(exits, 1);
  });

  testWidgets('expired exit window requires another two presses', (tester) async {
    var exits = 0;
    await tester.pumpWidget(MaterialApp(home: HomeBackScope(
      onBackStep: () => false, onExit: () => exits++,
      child: const Scaffold(body: Text('Home')),
    )));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    expect(exits, 1);
  });

  testWidgets('a pushed page returns home without arming exit', (tester) async {
    var exits = 0;
    await tester.pumpWidget(MaterialApp(home: HomeBackScope(
      onBackStep: () => false, onExit: () => exits++,
      child: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Details')))),
        child: const Text('Open'),
      ))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
  });
}
