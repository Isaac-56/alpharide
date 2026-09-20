import 'package:cloud_firestore/cloud_firestore.dart';

class RideCreationResult {
  final String rideId;
  final String status;
  final int estimatedFare;
  final String currencyCode;
  final int routeDistanceMeters;
  final int routeDurationSeconds;

  const RideCreationResult({
    required this.rideId,
    required this.status,
    required this.estimatedFare,
    required this.currencyCode,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
  });

  factory RideCreationResult.fromCallableData(Object? raw) {
    final Map<String, dynamic> data = _stringMap(raw);

    return RideCreationResult(
      rideId: _requiredString(data, 'rideId'),
      status: _requiredString(data, 'status'),
      estimatedFare: _requiredInt(data, 'estimatedFare'),
      currencyCode: _requiredString(data, 'currencyCode'),
      routeDistanceMeters: _requiredInt(data, 'routeDistanceMeters'),
      routeDurationSeconds: _requiredInt(data, 'routeDurationSeconds'),
    );
  }
}

class RideDriverSummary {
  final String displayName;
  final String vehicleType;
  final String make;
  final String model;
  final String color;
  final String plateNumber;

  const RideDriverSummary({
    required this.displayName,
    required this.vehicleType,
    required this.make,
    required this.model,
    required this.color,
    required this.plateNumber,
  });

  String get vehicleLabel {
    final List<String> parts = <String>[
      color,
      make,
      model,
    ].where((String value) => value.trim().isNotEmpty).toList(growable: false);

    if (parts.isNotEmpty) return parts.join(' ');
    if (vehicleType.trim().isNotEmpty) return vehicleType.trim();
    return 'Vehicle details unavailable';
  }

  factory RideDriverSummary.fromMap(Map<String, dynamic> data) {
    return RideDriverSummary(
      displayName: _optionalString(data['displayName']) ?? 'Alpha driver',
      vehicleType: _optionalString(data['vehicleType']) ?? '',
      make: _optionalString(data['make']) ?? '',
      model: _optionalString(data['model']) ?? '',
      color: _optionalString(data['color']) ?? '',
      plateNumber: _optionalString(data['plateNumber']) ?? '',
    );
  }
}

class RideLiveState {
  final String rideId;
  final String status;
  final String? driverId;
  final RideDriverSummary? driver;
  final int estimatedFare;
  final int? finalFare;
  final String currencyCode;
  final bool isWaiting;
  final DateTime? waitingStartedAt;
  final int waitingSeconds;
  final int billableWaitingSeconds;
  final int waitingCharge;
  final int waitingGraceSeconds;
  final int waitingRatePerMinute;

  const RideLiveState({
    required this.rideId,
    required this.status,
    required this.driverId,
    required this.driver,
    required this.estimatedFare,
    required this.finalFare,
    required this.currencyCode,
    this.isWaiting = false,
    this.waitingStartedAt,
    this.waitingSeconds = 0,
    this.billableWaitingSeconds = 0,
    this.waitingCharge = 0,
    this.waitingGraceSeconds = 120,
    this.waitingRatePerMinute = 0,
  });

  bool get isTerminal =>
      status == 'completed' || status == 'cancelled' || status == 'expired';

  bool get canPassengerCancel => const <String>{
        'requested',
        'offered',
        'accepted',
        'driver_arriving',
        'arrived',
      }.contains(status);

  int get fare => finalFare ?? estimatedFare;

  int waitingSecondsAt(DateTime now) {
    if (!isWaiting || waitingStartedAt == null) return waitingSeconds;
    final int activeSeconds = now.difference(waitingStartedAt!).inSeconds;
    return waitingSeconds + activeSeconds.clamp(0, 4 * 60 * 60).toInt();
  }

  int billableWaitingSecondsAt(DateTime now) {
    if (!isWaiting || waitingStartedAt == null) {
      return billableWaitingSeconds;
    }
    final int activeSeconds =
        now
            .difference(waitingStartedAt!)
            .inSeconds
            .clamp(0, 4 * 60 * 60)
            .toInt();
    return billableWaitingSeconds +
        (activeSeconds - waitingGraceSeconds)
            .clamp(0, 4 * 60 * 60)
            .toInt();
  }

  int waitingChargeAt(DateTime now) {
    final int seconds = billableWaitingSecondsAt(now);
    if (seconds == 0 || waitingRatePerMinute <= 0) return waitingCharge;
    final double raw = seconds / 60 * waitingRatePerMinute;
    return (raw / 100).ceil() * 100;
  }

  int fareAt(DateTime now) =>
      finalFare ?? (estimatedFare + waitingChargeAt(now));

  factory RideLiveState.fromFirestore({
    required String rideId,
    required Map<String, dynamic> data,
  }) {
    final Object? rawDriverId = data['driverId'];
    final Object? rawDriverSummary = data['driverSummary'];
    final Object? rawFinalFare = data['finalFare'];

    RideDriverSummary? driver;
    if (rawDriverSummary is Map<String, dynamic>) {
      driver = RideDriverSummary.fromMap(rawDriverSummary);
    } else if (rawDriverSummary is Map) {
      driver = RideDriverSummary.fromMap(
        Map<String, dynamic>.from(rawDriverSummary),
      );
    }

    return RideLiveState(
      rideId: rideId,
      status: _requiredString(data, 'status'),
      driverId: rawDriverId is String && rawDriverId.trim().isNotEmpty
          ? rawDriverId.trim()
          : null,
      driver: driver,
      estimatedFare: _requiredInt(data, 'estimatedFare'),
      finalFare:
          rawFinalFare == null ? null : _asInt(rawFinalFare, 'finalFare'),
      currencyCode: _requiredString(data, 'currencyCode'),
      isWaiting: data['isWaiting'] == true,
      waitingStartedAt: _optionalTimestamp(data['waitingStartedAt']),
      waitingSeconds: _nonNegativeInt(data['waitingSeconds']),
      billableWaitingSeconds:
          _nonNegativeInt(data['billableWaitingSeconds']),
      waitingCharge: _nonNegativeInt(data['waitingCharge']),
      waitingGraceSeconds:
          _nonNegativeInt(data['waitingGraceSeconds'], fallback: 120),
      waitingRatePerMinute:
          _nonNegativeInt(data['waitingRatePerMinute']),
    );
  }
}

class RideBackendException implements Exception {
  final String message;
  final String? code;
  final String? rideId;

  const RideBackendException(
    this.message, {
    this.code,
    this.rideId,
  });

  @override
  String toString() => message;
}

Map<String, dynamic> _stringMap(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('Backend response is not a map.');
  }

  return raw.map<String, dynamic>(
    (Object? key, Object? value) {
      if (key is! String) {
        throw const FormatException(
          'Backend response contains a non-string key.',
        );
      }

      return MapEntry<String, dynamic>(key, value);
    },
  );
}

String _requiredString(Map<String, dynamic> data, String field) {
  final Object? raw = data[field];

  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('Backend response is missing $field.');
  }

  return raw.trim();
}

String? _optionalString(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return raw.trim();
}

int _requiredInt(Map<String, dynamic> data, String field) {
  return _asInt(data[field], field);
}

int _asInt(Object? raw, String field) {
  if (raw is int) return raw;

  if (raw is num && raw.isFinite && raw == raw.roundToDouble()) {
    return raw.toInt();
  }

  throw FormatException('Backend response has an invalid $field.');
}

int _nonNegativeInt(Object? raw, {int fallback = 0}) {
  if (raw == null) return fallback;
  if (raw is int && raw >= 0) return raw;
  if (raw is num && raw.isFinite && raw >= 0) return raw.round();
  return fallback;
}

DateTime? _optionalTimestamp(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return null;
}
