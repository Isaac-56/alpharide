import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../../models/prediction_model.dart';

typedef PlacesInvoker = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> data,
);

class PlacesService {
  PlacesService({FirebaseFunctions? functions, PlacesInvoker? invoke})
    : _functions = functions,
      _invokeOverride = invoke;

  final FirebaseFunctions? _functions;
  final PlacesInvoker? _invokeOverride;
  String? _sessionToken;

  String _session() {
    final String? current = _sessionToken;
    if (current != null) return current;
    final Random random = Random.secure();
    return _sessionToken = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Object?> _call(String name, Map<String, dynamic> data) async {
    if (_invokeOverride != null) return _invokeOverride(name, data);
    final FirebaseFunctions functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'africa-south1');
    final HttpsCallableResult<dynamic> result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call<dynamic>(data);
    return result.data;
  }

  Future<List<PredictionModel>> searchPlaces(
    String input,
    double latitude,
    double longitude,
  ) async {
    final String query = input.trim();
    if (query.length < 2) return <PredictionModel>[];
    final Object? response = await _call(
      'passengerSearchPlaces',
      <String, dynamic>{
        'query': query,
        'latitude': latitude,
        'longitude': longitude,
        'sessionToken': _session(),
      },
    );
    if (response is! Map || response['results'] is! List) {
      throw const FormatException(
        'Location search returned an invalid response.',
      );
    }
    return (response['results'] as List)
        .whereType<Map>()
        .map((Map place) {
          final String primaryText = place['primaryText']?.toString() ?? '';
          return PredictionModel(
            placeId: place['placeId']?.toString() ?? '',
            mainText: primaryText.isNotEmpty
                ? primaryText
                : place['description']?.toString() ?? '',
            secondaryText: place['secondaryText']?.toString() ?? '',
          );
        })
        .where((PredictionModel place) => place.placeId.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> getPlaceDetails(String placeId) async {
    final String session = _session();
    final Object? response = await _call('passengerGetPlace', <String, dynamic>{
      'placeId': placeId,
      'sessionToken': session,
    });
    if (response is! Map) {
      throw const FormatException('The selected location could not be loaded.');
    }
    final num? latitude = response['latitude'] is num
        ? response['latitude'] as num
        : null;
    final num? longitude = response['longitude'] is num
        ? response['longitude'] as num
        : null;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException(
        'The selected place has no valid map location.',
      );
    }
    if (_sessionToken == session) _sessionToken = null;
    return <String, dynamic>{
      'latitude': latitude.toDouble(),
      'longitude': longitude.toDouble(),
      'address': response['address']?.toString() ?? '',
      // DestinationSearch preserves the selected prediction's main text.
      'name': '',
    };
  }
}
