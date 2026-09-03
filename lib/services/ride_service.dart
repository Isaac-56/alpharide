import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/ride_backend.dart';

class RideService {
  static const String region = 'africa-south1';

  static final RideService instance = RideService._(
    functions: FirebaseFunctions.instanceFor(region: region),
    firestore: FirebaseFirestore.instance,
  );

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  RideService._({
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
  })  : _functions = functions,
        _firestore = firestore;

  Future<RideCreationResult> createRide({
    required String pickupAddress,
    required double pickupLatitude,
    required double pickupLongitude,
    required String destinationAddress,
    required double destinationLatitude,
    required double destinationLongitude,
    required String rideOptionId,
    required String paymentMethod,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('createRide');

      final HttpsCallableResult<dynamic> result = await callable.call<dynamic>(
        <String, dynamic>{
          'pickup': <String, dynamic>{
            'address': pickupAddress,
            'latitude': pickupLatitude,
            'longitude': pickupLongitude,
          },
          'destination': <String, dynamic>{
            'address': destinationAddress,
            'latitude': destinationLatitude,
            'longitude': destinationLongitude,
          },
          'rideOptionId': rideOptionId,
          'paymentMethod': paymentMethod,
        },
      );

      return RideCreationResult.fromCallableData(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw _fromFunctionsException(error);
    } on FormatException catch (error) {
      throw RideBackendException(error.message);
    }
  }

  Future<void> cancelRide({
    required String rideId,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('cancelRide');

      await callable.call<dynamic>(
        <String, dynamic>{
          'rideId': rideId,
        },
      );
    } on FirebaseFunctionsException catch (error) {
      throw _fromFunctionsException(error);
    }
  }

  Stream<RideLiveState?> watchRide(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .snapshots()
        .map<RideLiveState?>(
      (DocumentSnapshot<Map<String, dynamic>> snapshot) {
        final Map<String, dynamic>? data = snapshot.data();

        if (!snapshot.exists || data == null) {
          return null;
        }

        return RideLiveState.fromFirestore(
          rideId: snapshot.id,
          data: data,
        );
      },
    );
  }

  RideBackendException _fromFunctionsException(
    FirebaseFunctionsException error,
  ) {
    final Object? rawDetails = error.details;
    String? existingRideId;

    if (rawDetails is Map) {
      final Object? rawRideId = rawDetails['rideId'];

      if (rawRideId is String && rawRideId.trim().isNotEmpty) {
        existingRideId = rawRideId;
      }
    }

    final String message = switch (error.code) {
      'unauthenticated' => 'Please sign in again before requesting a ride.',
      'already-exists' => 'You already have an active ride.',
      'invalid-argument' => error.message ?? 'The ride request is invalid.',
      'failed-precondition' =>
        error.message ?? 'This ride cannot be changed right now.',
      'permission-denied' => 'You do not have permission to change this ride.',
      'not-found' => 'This ride no longer exists.',
      'unavailable' =>
        error.message ?? 'The ride service is temporarily unavailable.',
      _ => error.message ?? 'The ride service could not complete the request.',
    };

    return RideBackendException(
      message,
      code: error.code,
      rideId: existingRideId,
    );
  }
}
