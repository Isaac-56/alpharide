import 'package:cloud_firestore/cloud_firestore.dart';

enum RideStatus {
  requested,
  offered,
  accepted,
  driverArriving,
  arrived,
  inProgress,
  completed,
  cancelled,
  expired,
}

extension RideStatusFirestore on RideStatus {
  String get firestoreValue => switch (this) {
        RideStatus.requested => 'requested',
        RideStatus.offered => 'offered',
        RideStatus.accepted => 'accepted',
        RideStatus.driverArriving => 'driver_arriving',
        RideStatus.arrived => 'arrived',
        RideStatus.inProgress => 'in_progress',
        RideStatus.completed => 'completed',
        RideStatus.cancelled => 'cancelled',
        RideStatus.expired => 'expired',
      };

  static RideStatus parse(Object? raw) {
    return switch (raw) {
      'requested' => RideStatus.requested,
      'offered' => RideStatus.offered,
      'accepted' => RideStatus.accepted,
      'driver_arriving' => RideStatus.driverArriving,
      'arrived' => RideStatus.arrived,
      'in_progress' => RideStatus.inProgress,
      'completed' => RideStatus.completed,
      'cancelled' => RideStatus.cancelled,
      'expired' => RideStatus.expired,
      _ => throw FormatException('Unknown ride status: $raw'),
    };
  }
}

enum RideCancellationActor { passenger, driver, system }

extension RideCancellationActorFirestore on RideCancellationActor {
  String get firestoreValue => switch (this) {
        RideCancellationActor.passenger => 'passenger',
        RideCancellationActor.driver => 'driver',
        RideCancellationActor.system => 'system',
      };

  static RideCancellationActor? parse(Object? raw) {
    if (raw == null) return null;
    return switch (raw) {
      'passenger' => RideCancellationActor.passenger,
      'driver' => RideCancellationActor.driver,
      'system' => RideCancellationActor.system,
      _ => throw FormatException('Unknown ride cancellation actor: $raw'),
    };
  }
}

abstract final class RideContract {
  static const int schemaVersion = 1;
  static const String ridesCollection = 'rides';
  static const String driverOffersCollection = 'driver_ride_offers';
  static const String driverOffersSubcollection = 'offers';
  static const String currencyCode = 'SSP';

  static const Set<String> knownRideOptions = <String>{
    'boda',
    'rickshaw',
    'standard',
    'comfort',
    'ev',
    'premium',
    'corporate',
  };

  static const Set<String> liveRideOptions = <String>{
    'boda',
    'rickshaw',
    'standard',
  };

  static const Set<String> liveVehicleTypes = <String>{
    'boda',
    'rickshaw',
    'standard',
  };

  static const Set<String> livePaymentMethods = <String>{'cash'};

  static bool isLiveRideOption(String rideOptionId) {
    return liveRideOptions.contains(rideOptionId.trim().toLowerCase());
  }

  static String requiredVehicleTypeFor(String rideOptionId) {
    final String normalized = rideOptionId.trim().toLowerCase();
    if (!liveRideOptions.contains(normalized)) {
      throw StateError(
        'Ride option "$rideOptionId" is not enabled for live dispatch.',
      );
    }
    return normalized;
  }
}

class RidePoint {
  const RidePoint({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String address;
  final double latitude;
  final double longitude;

  factory RidePoint.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Ride location must be a map.');
    }
    final Map<Object?, Object?> data = raw;
    final String address = _requiredString(data['address'], 'address');
    final double latitude = _requiredDouble(data['latitude'], 'latitude');
    final double longitude = _requiredDouble(data['longitude'], 'longitude');

    if (latitude < -90 || latitude > 90) {
      throw const FormatException('Latitude is outside the valid range.');
    }
    if (longitude < -180 || longitude > 180) {
      throw const FormatException('Longitude is outside the valid range.');
    }

    return RidePoint(
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class RideRecord {
  const RideRecord({
    required this.id,
    required this.passengerId,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.rideOptionId,
    required this.requiredVehicleType,
    required this.paymentMethod,
    required this.estimatedFare,
    required this.currencyCode,
    required this.requestedAt,
    required this.updatedAt,
    this.driverId,
    this.finalFare,
    this.cancelledBy,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
  });

  final String id;
  final String passengerId;
  final String? driverId;
  final RideStatus status;
  final RidePoint pickup;
  final RidePoint destination;
  final String rideOptionId;
  final String requiredVehicleType;
  final String paymentMethod;
  final int estimatedFare;
  final int? finalFare;
  final String currencyCode;
  final RideCancellationActor? cancelledBy;
  final DateTime requestedAt;
  final DateTime updatedAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  bool get hasAssignedDriver => driverId != null && driverId!.isNotEmpty;

  bool get isTerminal =>
      status == RideStatus.completed ||
      status == RideStatus.cancelled ||
      status == RideStatus.expired;

  factory RideRecord.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final int version = _requiredInt(data['schemaVersion'], 'schemaVersion');
    if (version != RideContract.schemaVersion) {
      throw FormatException('Unsupported ride schema version: $version');
    }

    final RideRecord record = RideRecord(
      id: id,
      passengerId: _requiredString(data['passengerId'], 'passengerId'),
      driverId: _optionalString(data['driverId']),
      status: RideStatusFirestore.parse(data['status']),
      pickup: RidePoint.fromMap(data['pickup']),
      destination: RidePoint.fromMap(data['destination']),
      rideOptionId:
          _requiredString(data['rideOptionId'], 'rideOptionId').toLowerCase(),
      requiredVehicleType: _requiredString(
        data['requiredVehicleType'],
        'requiredVehicleType',
      ).toLowerCase(),
      paymentMethod:
          _requiredString(data['paymentMethod'], 'paymentMethod').toLowerCase(),
      estimatedFare: _requiredInt(data['estimatedFare'], 'estimatedFare'),
      finalFare: _optionalInt(data['finalFare']),
      currencyCode:
          _requiredString(data['currencyCode'], 'currencyCode').toUpperCase(),
      cancelledBy: RideCancellationActorFirestore.parse(data['cancelledBy']),
      requestedAt: _requiredDateTime(data['requestedAt'], 'requestedAt'),
      updatedAt: _requiredDateTime(data['updatedAt'], 'updatedAt'),
      acceptedAt: _optionalDateTime(data['acceptedAt']),
      arrivedAt: _optionalDateTime(data['arrivedAt']),
      startedAt: _optionalDateTime(data['startedAt']),
      completedAt: _optionalDateTime(data['completedAt']),
      cancelledAt: _optionalDateTime(data['cancelledAt']),
    );

    record._validate();
    return record;
  }

  void _validate() {
    if (!RideContract.liveRideOptions.contains(rideOptionId)) {
      throw FormatException(
        'Ride option "$rideOptionId" is not enabled for live dispatch.',
      );
    }

    final String expectedVehicle =
        RideContract.requiredVehicleTypeFor(rideOptionId);
    if (requiredVehicleType != expectedVehicle) {
      throw FormatException(
        'Ride option "$rideOptionId" requires vehicle "$expectedVehicle".',
      );
    }

    if (!RideContract.livePaymentMethods.contains(paymentMethod)) {
      throw FormatException(
        'Payment method "$paymentMethod" is not enabled for live rides.',
      );
    }

    if (currencyCode != RideContract.currencyCode) {
      throw FormatException('Unsupported ride currency: $currencyCode');
    }

    if (estimatedFare <= 0) {
      throw const FormatException('Estimated fare must be positive.');
    }

    final bool assignmentRequired = switch (status) {
      RideStatus.accepted ||
      RideStatus.driverArriving ||
      RideStatus.arrived ||
      RideStatus.inProgress ||
      RideStatus.completed =>
        true,
      _ => false,
    };

    if (assignmentRequired && !hasAssignedDriver) {
      throw FormatException(
        'Ride status "${status.firestoreValue}" requires a driver.',
      );
    }

    if ((status == RideStatus.requested || status == RideStatus.offered) &&
        hasAssignedDriver) {
      throw FormatException(
        'Ride status "${status.firestoreValue}" cannot already have a driver.',
      );
    }

    if (status == RideStatus.completed) {
      if (finalFare == null || finalFare! <= 0) {
        throw const FormatException(
          'Completed rides require a positive final fare.',
        );
      }
      if (completedAt == null) {
        throw const FormatException(
          'Completed rides require a completion timestamp.',
        );
      }
    }

    if (status == RideStatus.cancelled) {
      if (cancelledBy == null || cancelledAt == null) {
        throw const FormatException(
          'Cancelled rides require actor and timestamp.',
        );
      }
    }
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Ride field "$field" must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Optional ride string has an invalid type.');
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _requiredInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Ride field "$field" must be an integer.');
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  return _requiredInt(value, 'optional integer');
}

double _requiredDouble(Object? value, String field) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Ride field "$field" must be a finite number.');
}

DateTime _requiredDateTime(Object? value, String field) {
  final DateTime? parsed = _optionalDateTime(value);
  if (parsed == null) {
    throw FormatException('Ride field "$field" must be a timestamp.');
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  throw const FormatException('Ride timestamp has an invalid type.');
}
