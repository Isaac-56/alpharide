import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DrivingRoute {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;

  const DrivingRoute({
    required this.points,
    required this.distanceMeters,
    required this.duration,
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

    if (points.length < 2) {
      throw const FormatException('The route polyline is invalid.');
    }

    return DrivingRoute(
      points: List<LatLng>.unmodifiable(points),
      distanceMeters: distanceMeters,
      duration: Duration(seconds: durationSeconds),
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

class DirectionsService {
  static const String region = 'africa-south1';

  final FirebaseFunctions _functions;

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
