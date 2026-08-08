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
  static const String _apiKey = String.fromEnvironment('ORS_API_KEY');

  static final Uri _endpoint = Uri.parse(
    'https://api.heigit.org/openrouteservice/v2/'
    'directions/driving-car/geojson',
  );

  const DirectionsService();

  Future<DrivingRoute> getShortestDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw const DirectionsException(
        'The routing key is missing. Start the app with '
        '--dart-define=ORS_API_KEY=YOUR_KEY.',
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
              'Accept': 'application/geo+json, application/json',
              'Authorization': _apiKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(
              <String, Object>{
                // openrouteservice coordinates use longitude first.
                'coordinates': <List<double>>[
                  <double>[origin.longitude, origin.latitude],
                  <double>[destination.longitude, destination.latitude],
                ],
                'preference': 'shortest',
                'instructions': false,
                'geometry_simplify': false,
              },
            ),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (error) {
      throw DirectionsException(
        'Could not connect to the routing service. '
        'Check your internet connection and try again. ($error)',
      );
    }

    final Object? decoded = _tryDecode(response.body);
    final Map<String, dynamic> body =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DirectionsException(_readError(body, response.statusCode));
    }

    final List<dynamic> features = body['features'] is List<dynamic>
        ? body['features'] as List<dynamic>
        : <dynamic>[];

    if (features.isEmpty || features.first is! Map<String, dynamic>) {
      throw const DirectionsException(
        'No drivable road route was found for these locations.',
      );
    }

    final Map<String, dynamic> feature = features.first as Map<String, dynamic>;
    final Map<String, dynamic> geometry =
        feature['geometry'] is Map<String, dynamic>
            ? feature['geometry'] as Map<String, dynamic>
            : <String, dynamic>{};
    final List<dynamic> coordinates = geometry['coordinates'] is List<dynamic>
        ? geometry['coordinates'] as List<dynamic>
        : <dynamic>[];

    final List<LatLng> points = coordinates
        .whereType<List<dynamic>>()
        .where(
          (List<dynamic> coordinate) =>
              coordinate.length >= 2 &&
              coordinate[0] is num &&
              coordinate[1] is num,
        )
        .map(
          (List<dynamic> coordinate) => LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
        )
        .toList(growable: false);

    if (points.length < 2) {
      throw const DirectionsException(
        'The routing service returned an invalid road route.',
      );
    }

    final Map<String, dynamic> properties =
        feature['properties'] is Map<String, dynamic>
            ? feature['properties'] as Map<String, dynamic>
            : <String, dynamic>{};
    final Map<String, dynamic> summary =
        properties['summary'] is Map<String, dynamic>
            ? properties['summary'] as Map<String, dynamic>
            : <String, dynamic>{};

    final int distanceMeters = (summary['distance'] as num?)?.round() ?? 0;
    final int durationSeconds = (summary['duration'] as num?)?.round() ?? 0;

    return DrivingRoute(
      points: List<LatLng>.unmodifiable(points),
      distanceMeters: distanceMeters,
      duration: Duration(seconds: durationSeconds),
    );
  }

  static Object? _tryDecode(String value) {
    if (value.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static String _readError(Map<String, dynamic> body, int statusCode) {
    final Object? error = body['error'];

    if (error is Map<String, dynamic>) {
      final String? message = error['message']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    if (error != null && error.toString().trim().isNotEmpty) {
      return error.toString();
    }

    final String? message = body['message']?.toString();
    if (message != null && message.trim().isNotEmpty) {
      return message;
    }

    if (statusCode == 401 || statusCode == 403) {
      return 'The routing key was rejected. Generate a new HeiGIT key '
          'and restart the app.';
    }

    if (statusCode == 429) {
      return 'The free routing limit has been reached. Try again later.';
    }

    return 'Unable to calculate a road route (error $statusCode).';
  }
}

class DirectionsException implements Exception {
  final String message;

  const DirectionsException(this.message);

  @override
  String toString() => message;
}
