import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/models/ride_history.dart';

void main() {
  test('completed live ride maps to passenger history', () {
    final Map<String, dynamic>? item = liveRideToOrderHistory(
      rideId: 'ride-1',
      data: <String, dynamic>{
        'status': 'completed',
        'estimatedFare': 10000,
        'finalFare': 10500,
        'currencyCode': 'SSP',
        'paymentMethod': 'cash',
        'rideOptionId': 'standard',
        'pickup': <String, dynamic>{'address': 'Imperial Plaza'},
        'destination': <String, dynamic>{'address': 'Juba Airport'},
        'completedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
      },
    );

    expect(item, isNotNull);
    expect(item?['fare'], 10500);
    expect(item?['pickupAddress'], 'Imperial Plaza');
    expect(item?['destinationAddress'], 'Juba Airport');
    expect(item?['status'], 'completed');
  });

  test('active rides stay out of history', () {
    for (final String status in <String>[
      'requested',
      'offered',
      'accepted',
      'driver_arriving',
      'arrived',
      'in_progress',
    ]) {
      expect(
        liveRideToOrderHistory(
          rideId: 'ride-$status',
          data: <String, dynamic>{
            'status': status,
            'estimatedFare': 10000,
          },
        ),
        isNull,
      );
    }
  });

  test('cancelled and expired rides remain visible in history', () {
    for (final String status in <String>['cancelled', 'expired']) {
      final Map<String, dynamic>? item = liveRideToOrderHistory(
        rideId: 'ride-$status',
        data: <String, dynamic>{
          'status': status,
          'estimatedFare': 8000,
          'pickup': <String, dynamic>{'address': 'A'},
          'destination': <String, dynamic>{'address': 'B'},
          'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        },
      );
      expect(item?['status'], status);
      expect(item?['fare'], 8000);
    }
  });

  test('history is sorted newest first', () {
    final List<Map<String, dynamic>> sorted = sortRideHistoryNewestFirst(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'old',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        },
        <String, dynamic>{
          'id': 'new',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(3000),
        },
        <String, dynamic>{
          'id': 'middle',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(2000),
        },
      ],
    );

    expect(sorted.map((Map<String, dynamic> item) => item['id']), <String>[
      'new',
      'middle',
      'old',
    ]);
  });
}
