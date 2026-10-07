import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DrivingRoute {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;
  final Map<String, RideFareQuote> fareEstimates;

  const DrivingRoute({
    required this.points,
    required this.distanceMeters,
    required this.duration,
    this.fareEstimates = const <String, RideFareQuote>{},
  });

  factory DrivingRoute.fromCallableData(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('The route response is invalid.');
    }

    final Map<String, dynamic> data = raw.map<String, dynamic>(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );
    final int distanceMeters = _positiveInt(
      data['distanceMeters'],
      'distance',
    );
    final int durationSeconds = _positiveInt(
      data['durationSeconds'],
      'duration',
    );
    final String encodedPolyline = data['encodedPolyline'] is String
        ? (data['encodedPolyline'] as String).trim()
        : '';
    final List<LatLng> points = _decodePolyline(encodedPolyline);
    final Map<String, RideFareQuote> fareEstimates = <String, RideFareQuote>{};
    final Object? rawFares = data['fareEstimates'];
    if (rawFares is Map) {
      for (final MapEntry<Object?, Object?> entry in rawFares.entries) {
        if (entry.value is Map) {
          fareEstimates[entry.key.toString()] = RideFareQuote.fromMap(
            entry.value as Map,
          );
        }
      }
    }

    if (points.length < 2) {
      throw const FormatException('The route polyline is invalid.');
    }

    return DrivingRoute(
      points: List<LatLng>.unmodifiable(points),
      distanceMeters: distanceMeters,
      duration: Duration(seconds: durationSeconds),
      fareEstimates: Map<String, RideFareQuote>.unmodifiable(fareEstimates),
    );
  }

  static int _positiveInt(Object? value, String fieldName) {
    if (value is! num || !value.isFinite || value <= 0) {
      throw FormatException('The route $fieldName is invalid.');
    }
    return value.round();
  }

  static List<LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return const <LatLng>[];

    final List<LatLng> points = <LatLng>[];
    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      final _DecodedValue latitudeValue = _decodeValue(encoded, index);
      index = latitudeValue.nextIndex;
      latitude += latitudeValue.value;

      if (index >= encoded.length) break;

      final _DecodedValue longitudeValue = _decodeValue(encoded, index);
      index = longitudeValue.nextIndex;
      longitude += longitudeValue.value;

      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }

    return points;
  }

  static _DecodedValue _decodeValue(String encoded, int startIndex) {
    int result = 0;
    int shift = 0;
    int index = startIndex;
    int byte;

    do {
      if (index >= encoded.length) {
        return _DecodedValue(0, encoded.length);
      }

      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final int value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    return _DecodedValue(value, index);
  }
}

class RideFareQuote {
  const RideFareQuote({
    required this.estimatedFare,
    required this.minimumFare,
    required this.baseFare,
    required this.perKilometer,
    required this.waitingPerMinute,
  });

  final int estimatedFare;
  final int minimumFare;
  final int baseFare;
  final int perKilometer;
  final int waitingPerMinute;

  factory RideFareQuote.fromMap(Map<dynamic, dynamic> data) {
    int read(String key) {
      final Object? value = data[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw FormatException('The $key fare value is invalid.');
      }
      return value.round();
    }
    return RideFareQuote(
      estimatedFare: read('estimatedFare'),
      minimumFare: read('minimumFare'),
      baseFare: read('baseFare'),
      perKilometer: read('perKilometer'),
      waitingPerMinute: read('waitingPerMinute'),
    );
  }
}

class DirectionsService {
  static const String region = 'africa-south1';
  static const Duration _cacheLifetime = Duration(minutes: 5);
  static const int _maximumCachedRoutes = 20;

  final FirebaseFunctions _functions;
  final Map<String, _CachedRoute> _cache = <String, _CachedRoute>{};
  final Map<String, Future<DrivingRoute>> _inFlight =
      <String, Future<DrivingRoute>>{};

  DirectionsService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: region);

  Future<DrivingRoute> getShortestDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if ((origin.latitude - destination.latitude).abs() < 0.00001 &&
        (origin.longitude - destination.longitude).abs() < 0.00001) {
      throw const DirectionsException(
        'Pickup and destination are the same location. '
        'Choose another destination.',
      );
    }

    final String cacheKey = _routeKey(origin, destination);
    final _CachedRoute? cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) <= _cacheLifetime) {
      // Refresh insertion order so frequently reused routes remain cached.
      _cache
        ..remove(cacheKey)
        ..[cacheKey] = cached;
      return cached.route;
    }
    _cache.remove(cacheKey);

    final Future<DrivingRoute>? existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final Future<DrivingRoute> request = _requestRoute(
      origin: origin,
      destination: destination,
    );
    _inFlight[cacheKey] = request;
    try {
      final DrivingRoute route = await request;
      while (_cache.length >= _maximumCachedRoutes) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = _CachedRoute(route, DateTime.now());
      return route;
    } finally {
      if (identical(_inFlight[cacheKey], request)) {
        _inFlight.remove(cacheKey);
      }
    }
  }

  Future<DrivingRoute> _requestRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final HttpsCallable callable =
          _functions.httpsCallable('calculateRoute');
      final HttpsCallableResult<dynamic> result =
          await callable.call<dynamic>(
        <String, dynamic>{
          'origin': <String, double>{
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
          'destination': <String, double>{
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
        },
      );

      return DrivingRoute.fromCallableData(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw DirectionsException(_functionsMessage(error));
    } on FormatException {
      throw const DirectionsException(
        'The server returned an invalid road route. Please try again.',
      );
    }
  }

  static String _routeKey(LatLng origin, LatLng destination) {
    String coordinate(double value) => value.toStringAsFixed(5);
    return '${coordinate(origin.latitude)}:${coordinate(origin.longitude)}:'
        '${coordinate(destination.latitude)}:${coordinate(destination.longitude)}';
  }

  static String _functionsMessage(FirebaseFunctionsException error) {
    return switch (error.code) {
      'unauthenticated' =>
        'Please sign in again before calculating a road route.',
      'invalid-argument' =>
        error.message ?? 'Choose a valid pickup and destination.',
      'resource-exhausted' =>
        'Too many route requests. Please wait a moment and try again.',
      'deadline-exceeded' =>
        'The road route service is temporarily unavailable. Try again.',
      'unavailable' =>
        'The road route service is temporarily unavailable. Try again.',
      _ => error.message ??
          'The road route could not be calculated. Please try again.',
    };
  }
}

class _CachedRoute {
  const _CachedRoute(this.route, this.storedAt);

  final DrivingRoute route;
  final DateTime storedAt;
}

class _DecodedValue {
  final int value;
  final int nextIndex;

  const _DecodedValue(this.value, this.nextIndex);
}

class DirectionsException implements Exception {
  final String message;

  const DirectionsException(this.message);

  @override
  String toString() => message;
}
