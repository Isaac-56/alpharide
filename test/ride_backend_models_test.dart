import 'package:cloud_firestore/cloud_firestore.dart';
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

  test('live ride state parses safe assigned driver details', () {
    final RideLiveState state = RideLiveState.fromFirestore(
      rideId: 'ride-123',
      data: <String, dynamic>{
        'status': 'accepted',
        'driverId': 'driver-7',
        'driverSummary': <String, dynamic>{
          'displayName': 'Daniel Driver',
          'vehicleType': 'Car',
          'make': 'Toyota',
          'model': 'Corolla',
          'color': 'White',
          'plateNumber': 'SSD 1234',
        },
        'estimatedFare': 21500,
        'finalFare': null,
        'currencyCode': 'SSP',
      },
    );

    expect(state.rideId, 'ride-123');
    expect(state.driverId, 'driver-7');
    expect(state.status, 'accepted');
    expect(state.driver?.displayName, 'Daniel Driver');
    expect(state.driver?.vehicleLabel, 'White Toyota Corolla');
    expect(state.driver?.plateNumber, 'SSD 1234');
    expect(state.fare, 21500);
    expect(state.isTerminal, false);
  });

  test('driver summary falls back cleanly when optional fields are absent', () {
    final RideLiveState state = RideLiveState.fromFirestore(
      rideId: 'ride-123',
      data: <String, dynamic>{
        'status': 'accepted',
        'driverId': 'driver-7',
        'driverSummary': <String, dynamic>{},
        'estimatedFare': 21500,
        'finalFare': null,
        'currencyCode': 'SSP',
      },
    );

    expect(state.driver?.displayName, 'Alpha driver');
    expect(state.driver?.vehicleLabel, 'Vehicle details unavailable');
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
          'driverSummary': null,
          'estimatedFare': 21500,
          'finalFare': status == 'completed' ? 22000 : null,
          'currencyCode': 'SSP',
        },
      );

      expect(state.isTerminal, true);
      expect(state.fare, status == 'completed' ? 22000 : 21500);
    }
  });

  test('passenger sees live customer waiting and projected fare', () {
    final DateTime now = DateTime.utc(2026, 9, 20, 12, 5);
    final RideLiveState state = RideLiveState.fromFirestore(
      rideId: 'ride-waiting',
      data: <String, dynamic>{
        'status': 'in_progress',
        'driverId': 'driver-7',
        'driverSummary': null,
        'estimatedFare': 42000,
        'finalFare': null,
        'currencyCode': 'SSP',
        'isWaiting': true,
        'waitingStartedAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 3)),
        ),
        'waitingSeconds': 0,
        'billableWaitingSeconds': 0,
        'waitingCharge': 0,
        'waitingGraceSeconds': 120,
        'waitingRatePerMinute': 450,
      },
    );

    expect(state.waitingSecondsAt(now), 180);
    expect(state.waitingChargeAt(now), 500);
    expect(state.fareAt(now), 42500);
  });

  test('passenger cancellation remains available until a trip starts', () {
    for (final String status in <String>[
      'requested',
      'offered',
      'accepted',
      'driver_arriving',
      'arrived',
    ]) {
      final RideLiveState state = RideLiveState.fromFirestore(
        rideId: 'ride-cancellable',
        data: <String, dynamic>{
          'status': status,
          'driverId': null,
          'driverSummary': null,
          'estimatedFare': 10000,
          'finalFare': null,
          'currencyCode': 'SSP',
        },
      );

      expect(state.canPassengerCancel, true, reason: status);
    }

    for (final String status in <String>['in_progress', 'completed']) {
      final RideLiveState state = RideLiveState.fromFirestore(
        rideId: 'ride-locked',
        data: <String, dynamic>{
          'status': status,
          'driverId': null,
          'driverSummary': null,
          'estimatedFare': 10000,
          'finalFare': null,
          'currencyCode': 'SSP',
        },
      );

      expect(state.canPassengerCancel, false, reason: status);
    }
  });
}
