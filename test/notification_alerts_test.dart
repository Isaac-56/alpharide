import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:passengerapp/services/notification_alerts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('alpha/notifications');
  final List<MethodCall> calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('duplicate push and live feed events sound only once', () async {
    for (int i = 0; i < 2; i++) {
      await NotificationAlerts.show(
        eventId: 'ride_offer:test-ride',
        title: 'New ride',
        body: 'Pickup',
        urgent: true,
      );
    }
    expect(calls.length, 1);
    expect((calls.single.arguments as Map<Object?, Object?>)['urgent'], true);
  });

  test('separate news and discounts can each alert', () async {
    for (final String event in <String>['news:test', 'discount:test']) {
      await NotificationAlerts.show(
        eventId: event,
        title: 'Update',
        body: 'Details',
      );
    }
    expect(calls.length, 2);
    expect((calls.first.arguments as Map<Object?, Object?>)['urgent'], false);
  });

  test(
    'permission failure does not block rides and permits a later retry',
    () async {
      int attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (++attempts == 1)
              throw PlatformException(code: 'permission-denied');
            return null;
          });
      await NotificationAlerts.show(
        eventId: 'retry:test',
        title: 'Ride',
        body: 'Pickup',
      );
      await NotificationAlerts.show(
        eventId: 'retry:test',
        title: 'Ride',
        body: 'Pickup',
      );
      expect(attempts, 2);
    },
  );
}
