import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class DrivingRoute {
  final List<LatLng> points;
  final int distanceMeters;
  final Duration duration;

  const DrivingRoute({
    required this.points,
    required this.distanceMeters,
    required this.duration,
  });
}

class DirectionsService {
  static const String _apiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
  );
  static const String _androidPackage =
      'com.alpharideapp.passengerapp';
  static const String _androidCertificateSha1 = String.fromEnvironment(
    'GOOGLE_ANDROID_CERT_SHA1',
  );

  static final Uri _endpoint = Uri.parse(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
  );

  const DirectionsService();

  Future<DrivingRoute> getShortestDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const DirectionsException(
        'Google routing is not configured. Restart AlphaRide with a '
        'GOOGLE_ROUTES_API_KEY.',
      );
    }

    if ((origin.latitude - destination.latitude).abs() < 0.00001 &&
        (origin.longitude - destination.longitude).abs() < 0.00001) {
      throw const DirectionsException(
        'Pickup and destination are the same location. '
        'Choose another destination.',
      );
    }

    late final http.Response response;

    try {
      response = await http
          .post(
            _endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'routes.distanceMeters,routes.duration,'
                  'routes.polyline.encodedPolyline',
              'X-Android-Package': _androidPackage,
              if (_androidCertificateSha1.trim().isNotEmpty)
                'X-Android-Cert': _androidCertificateSha1
                    .replaceAll(':', '')
                    .toUpperCase(),
            },
            body: jsonEncode(
              <String, Object>{
                'origin': <String, Object>{
                  'location': <String, Object>{
                    'latLng': <String, double>{
                      'latitude': origin.latitude,
                      'longitude': origin.longitude,
                    },
                  },
                },
                'destination': <String, Object>{
                  'location': <String, Object>{
                    'latLng': <String, double>{
                      'latitude': destination.latitude,
                      'longitude': destination.longitude,
                    },
                  },
                },
                'travelMode': 'DRIVE',
                'routingPreference': 'TRAFFIC_AWARE',
                'computeAlternativeRoutes': false,
                'polylineQuality': 'HIGH_QUALITY',
                'polylineEncoding': 'ENCODED_POLYLINE',
                'routeModifiers': <String, bool>{
                  'avoidTolls': false,
                  'avoidHighways': false,
                  'avoidFerries': true,
                },
                'languageCode': 'en',
                'units': 'METRIC',
              },
            ),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (error) {
      throw DirectionsException(
        'Could not connect to Google Routes. '
        'Check your internet connection and try again. ($error)',
      );
    }

    final Object? decoded = _tryDecode(response.body);
    final Map<String, dynamic> body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DirectionsException(_readError(body, response.statusCode));
    }

    final List<dynamic> routes = body['routes'] is List<dynamic>
        ? body['routes'] as List<dynamic>
        : <dynamic>[];

    if (routes.isEmpty || routes.first is! Map<String, dynamic>) {
      throw const DirectionsException(
        'Google could not find a drivable road route for these locations.',
      );
    }

    final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
    final Map<String, dynamic> polyline = route['polyline']
            is Map<String, dynamic>
        ? route['polyline'] as Map<String, dynamic>
        : <String, dynamic>{};
    final String encodedPolyline =
        polyline['encodedPolyline']?.toString() ?? '';
    final List<LatLng> points = _decodePolyline(encodedPolyline);

    if (points.length < 2) {
      throw const DirectionsException(
        'Google returned an invalid road route. Please try again.',
      );
    }

    final int distanceMeters =
        (route['distanceMeters'] as num?)?.round() ?? 0;
    final Duration duration = _parseDuration(route['duration']?.toString());

    return DrivingRoute(
      points: List<LatLng>.unmodifiable(points),
      distanceMeters: distanceMeters,
      duration: duration,
    );
  }

  static Object? _tryDecode(String value) {
    if (value.trim().isEmpty) return null;

    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static Duration _parseDuration(String? value) {
    if (value == null || !value.endsWith('s')) {
      return Duration.zero;
    }

    final double? seconds = double.tryParse(
      value.substring(0, value.length - 1),
    );

    return Duration(milliseconds: ((seconds ?? 0) * 1000).round());
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

      points.add(
        LatLng(latitude / 1e5, longitude / 1e5),
      );
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

  static String _readError(Map<String, dynamic> body, int statusCode) {
    final Object? error = body['error'];

    if (error is Map<String, dynamic>) {
      final String? status = error['status']?.toString();
      final String? message = error['message']?.toString();

      if (status == 'PERMISSION_DENIED') {
        return 'Google Routes rejected this request. Enable Routes API, '
            'attach billing, and check the API-key restrictions.';
      }

      if (status == 'RESOURCE_EXHAUSTED') {
        return 'The Google Routes quota has been reached. Try again later.';
      }

      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    if (statusCode == 401 || statusCode == 403) {
      return 'Google Routes rejected this request. Enable Routes API, '
          'attach billing, and check the API-key restrictions.';
    }

    if (statusCode == 429) {
      return 'The Google Routes quota has been reached. Try again later.';
    }

    return 'Unable to calculate a Google road route (error $statusCode).';
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
