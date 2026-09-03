import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/models/ride_backend.dart';

void main() {
  test('ride creation response parses trusted backend quote', () {
    final RideCreationResult result = RideCreationResult.fromCallableData(
      <String, dynamic>{
        'rideId': 'ride-123',
        'status': 'requested',
        'estimatedFare': 21500,
        'currencyCode': 'SSP',
        'routeDistanceMeters': 10000,
        'routeDurationSeconds': 1200,
      },
    );

    expect(result.rideId, 'ride-123');
    expect(result.status, 'requested');
    expect(result.estimatedFare, 21500);
    expect(result.currencyCode, 'SSP');
    expect(result.routeDistanceMeters, 10000);
    expect(result.routeDurationSeconds, 1200);
  });

  test('live ride state parses driver assignment fields', () {
    final RideLiveState state = RideLiveState.fromFirestore(
      rideId: 'ride-123',
      data: <String, dynamic>{
        'status': 'accepted',
        'driverId': 'driver-7',
        'estimatedFare': 21500,
        'finalFare': null,
        'currencyCode': 'SSP',
      },
    );

    expect(state.rideId, 'ride-123');
    expect(state.driverId, 'driver-7');
    expect(state.status, 'accepted');
    expect(state.isTerminal, false);
  });

  test('terminal ride states are recognized', () {
    for (final String status in <String>[
      'cancelled',
      'expired',
      'completed',
    ]) {
      final RideLiveState state = RideLiveState.fromFirestore(
        rideId: 'ride-123',
        data: <String, dynamic>{
          'status': status,
          'driverId': null,
          'estimatedFare': 21500,
          'finalFare': status == 'completed' ? 22000 : null,
          'currencyCode': 'SSP',
        },
      );

      expect(state.isTerminal, true);
    }
  });
}
