import 'package:passengerapp/models/ride_contract.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ride status Firestore values round-trip', () {
    for (final RideStatus status in RideStatus.values) {
      expect(RideStatusFirestore.parse(status.firestoreValue), status);
    }
  });

  test('live dispatch only enables compatible launch products', () {
    expect(
      RideContract.liveRideOptions,
      <String>{'boda', 'rickshaw', 'standard'},
    );
    expect(RideContract.isLiveRideOption('standard'), isTrue);
    expect(RideContract.isLiveRideOption('comfort'), isFalse);
  });

  test('valid requested ride parses without assigned driver', () {
    final Timestamp now = Timestamp.fromDate(DateTime.utc(2026, 9, 3, 10));

    final RideRecord ride = RideRecord.fromMap(
      id: 'ride-1',
      data: <String, dynamic>{
        'schemaVersion': 1,
        'passengerId': 'passenger-1',
        'driverId': null,
        'status': 'requested',
        'pickup': <String, dynamic>{
          'address': 'Pickup',
          'latitude': 4.8594,
          'longitude': 31.5713,
        },
        'destination': <String, dynamic>{
          'address': 'Destination',
          'latitude': 4.8700,
          'longitude': 31.5900,
        },
        'rideOptionId': 'standard',
        'requiredVehicleType': 'standard',
        'paymentMethod': 'cash',
        'estimatedFare': 24000,
        'finalFare': null,
        'currencyCode': 'SSP',
        'cancelledBy': null,
        'requestedAt': now,
        'updatedAt': now,
      },
    );

    expect(ride.status, RideStatus.requested);
    expect(ride.hasAssignedDriver, isFalse);
    expect(ride.estimatedFare, 24000);
  });

  test('accepted ride without a driver is rejected', () {
    final Timestamp now = Timestamp.fromDate(DateTime.utc(2026, 9, 3, 10));

    expect(
      () => RideRecord.fromMap(
        id: 'ride-2',
        data: <String, dynamic>{
          'schemaVersion': 1,
          'passengerId': 'passenger-1',
          'status': 'accepted',
          'pickup': <String, dynamic>{
            'address': 'Pickup',
            'latitude': 4.8594,
            'longitude': 31.5713,
          },
          'destination': <String, dynamic>{
            'address': 'Destination',
            'latitude': 4.8700,
            'longitude': 31.5900,
          },
          'rideOptionId': 'standard',
          'requiredVehicleType': 'standard',
          'paymentMethod': 'cash',
          'estimatedFare': 24000,
          'currencyCode': 'SSP',
          'requestedAt': now,
          'updatedAt': now,
        },
      ),
      throwsFormatException,
    );
  });
}
