import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/account/activity_screens.dart';
import 'package:passengerapp/services/firestore_service.dart';

class _Data extends FirestoreService {
  int historySubscriptions = 0;
  final history = StreamController<List<Map<String, dynamic>>>.broadcast();
  final readWrite = Completer<void>();
  @override
  Stream<List<Map<String, dynamic>>> watchOrders(String phone) {
    historySubscriptions++;
    return history.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchNotifications(String phone) =>
      Stream<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'notice',
          'title': 'Ride notice',
          'message': 'Driver update',
          'isRead': false,
        },
      ]);

  @override
  Future<void> markNotificationRead(String phone, String id) =>
      readWrite.future;
}

void main() {
  testWidgets('history filtering keeps the live query and its loaded records', (
    tester,
  ) async {
    final data = _Data();
    await tester.pumpWidget(
      MaterialApp(
        home: OrderHistoryScreen(phoneNumber: 'test', firestoreService: data),
      ),
    );
    data.history.add(<Map<String, dynamic>>[]);
    await tester.pump();
    expect(data.historySubscriptions, 1);
    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(data.historySubscriptions, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(data.history.close());
  });

  testWidgets(
    'notification opens while the read-status write is still pending',
    (tester) async {
      final data = _Data();
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            phoneNumber: 'test',
            firestoreService: data,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ride notice'));
      await tester.pumpAndSettle();
      expect(data.readWrite.isCompleted, isFalse);
      expect(find.text('Ride notice'), findsNWidgets(2));
      data.readWrite.completeError(
        StateError('Temporary offline write failure'),
      );
      await tester.pump();
      expect(find.text('Ride notice'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
