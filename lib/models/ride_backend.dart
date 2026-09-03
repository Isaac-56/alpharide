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

class RideLiveState {
  final String rideId;
  final String status;
  final String? driverId;
  final int estimatedFare;
  final int? finalFare;
  final String currencyCode;

  const RideLiveState({
    required this.rideId,
    required this.status,
    required this.driverId,
    required this.estimatedFare,
    required this.finalFare,
    required this.currencyCode,
  });

  bool get isTerminal =>
      status == 'completed' || status == 'cancelled' || status == 'expired';

  factory RideLiveState.fromFirestore({
    required String rideId,
    required Map<String, dynamic> data,
  }) {
    final Object? rawDriverId = data['driverId'];
    final Object? rawFinalFare = data['finalFare'];

    return RideLiveState(
      rideId: rideId,
      status: _requiredString(data, 'status'),
      driverId: rawDriverId is String && rawDriverId.trim().isNotEmpty
          ? rawDriverId
          : null,
      estimatedFare: _requiredInt(data, 'estimatedFare'),
      finalFare:
          rawFinalFare == null ? null : _asInt(rawFinalFare, 'finalFare'),
      currencyCode: _requiredString(data, 'currencyCode'),
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

  return raw;
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
