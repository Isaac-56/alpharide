import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/core/widgets/app_startup.dart';
import 'package:passengerapp/core/widgets/visible_clock.dart';
import 'package:passengerapp/services/ride_photo_provider.dart';

void main() {
  testWidgets('startup paints before readiness and does not restart on rebuild', (tester) async {
    final ready = Completer<void>();
    var initializations = 0;
    var appBuilds = 0;
    Widget app() => AppStartup(
      initialize: () { initializations++; return ready.future; },
      builder: (_) { appBuilds++; return const MaterialApp(home: Text('Ready')); },
    );
    await tester.pumpWidget(app());
    expect(find.text('Opening Alpha…'), findsOneWidget);
    expect(appBuilds, 0);
    await tester.pumpWidget(app());
    expect(initializations, 1);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(appBuilds, 1);
  });

  testWidgets('failed startup keeps protected app closed and retries once', (tester) async {
    var attempts = 0;
    var built = false;
    final retry = Completer<void>();
    await tester.pumpWidget(AppStartup(
      initialize: () { attempts++; return attempts == 1
          ? Future<void>.error(StateError('private SDK details')) : retry.future; },
      builder: (_) { built = true; return const MaterialApp(home: Text('Ready')); },
    ));
    await tester.pumpAndSettle();
    expect(built, isFalse);
    expect(find.textContaining('private SDK'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
    expect(built, isFalse);
    retry.complete();
    await tester.pumpAndSettle();
    expect(built, isTrue);
  });

  testWidgets('startup completion after disposal does not build app', (tester) async {
    final ready = Completer<void>();
    var builds = 0;
    await tester.pumpWidget(AppStartup(initialize: () => ready.future,
      builder: (_) { builds++; return const SizedBox(); }));
    await tester.pumpWidget(const SizedBox());
    ready.complete();
    await tester.pump();
    expect(builds, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting clock pauses when hidden and in background', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var builds = 0;
    Widget app(bool visible) => MaterialApp(home: TickerMode(enabled: visible,
      child: VisibleClock(builder: (_, now) { builds++; return Text('$now'); })));
    await tester.pumpWidget(app(true));
    final initial = builds;
    await tester.pump(const Duration(seconds: 1));
    expect(builds, initial + 1);
    await tester.pumpWidget(app(false));
    final hidden = builds;
    await tester.pump(const Duration(seconds: 5));
    expect(builds, hidden);
    await tester.pumpWidget(app(true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = builds;
    await tester.pump(const Duration(seconds: 5));
    expect(builds, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(builds, greaterThan(paused));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent rebuild does not reset waiting tick deadline', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var builds = 0;
    Widget app() => MaterialApp(home: VisibleClock(builder: (_, now) {
      builds++; return Text('$now');
    }));
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(app());
    final beforeTick = builds;
    await tester.pump(const Duration(milliseconds: 400));
    expect(builds, beforeTick + 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('remote avatars have bounded decode size and reuse providers', () {
    const url = 'https://example.com/avatar-performance.jpg';
    final provider = ridePhotoProvider(url);
    expect(provider, isA<ResizeImage>());
    expect((provider! as ResizeImage).width, 256);
    expect(identical(provider, ridePhotoProvider(url)), isTrue);
    for (var i = 0; i < 5; i++) {
      ridePhotoProvider('https://example.com/avatar-$i.jpg');
    }
    expect(identical(provider, ridePhotoProvider(url)), isFalse);
    expect(ridePhotoProvider('http://example.com/photo.jpg'), isNull);
    expect(ridePhotoProvider('data:text/plain;base64,WA=='), isNull);
  });
}
