import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/services/places_service.dart';

void main() {
  test('search and details use authenticated callables and the same billing session', () async {
    final List<(String, Map<String, dynamic>)> calls =
        <(String, Map<String, dynamic>)>[];
    final PlacesService service = PlacesService(
      invoke: (String name, Map<String, dynamic> data) async {
        calls.add((name, data));
        if (name == 'passengerSearchPlaces') {
          return <String, Object>{
            'results': <Object>[
              <String, String>{
                'placeId': 'ChIJtestplace',
                'primaryText': 'Juba Market',
                'secondaryText': 'South Sudan',
              },
            ],
          };
        }
        return <String, Object>{
          'latitude': 4.86,
          'longitude': 31.57,
          'address': 'Juba, South Sudan',
        };
      },
    );
    final results = await service.searchPlaces(' Juba ', 4.85, 31.57);
    expect(results.single.mainText, 'Juba Market');
    final place = await service.getPlaceDetails(results.single.placeId);
    expect(place['latitude'], 4.86);
    expect(place['address'], 'Juba, South Sudan');
    expect(calls.map((call) => call.$1), <String>[
      'passengerSearchPlaces',
      'passengerGetPlace',
    ]);
    expect(calls[0].$2['sessionToken'], calls[1].$2['sessionToken']);
    expect(calls[0].$2['query'], 'Juba');
    expect(calls[0].$2.containsKey('apiKey'), isFalse);
    await service.searchPlaces('Airport', 4.85, 31.57);
    expect(calls[2].$2['sessionToken'], isNot(calls[0].$2['sessionToken']));
  });

  test('short input never invokes a function and failed details keep the session for retry', () async {
    int requests = 0;
    final List<String> sessions = <String>[];
    final PlacesService service = PlacesService(
      invoke: (String name, Map<String, dynamic> data) async {
        requests++;
        sessions.add(data['sessionToken'] as String);
        if (requests == 1) throw StateError('temporary network failure');
        return <String, Object>{
          'latitude': 4.86,
          'longitude': 31.57,
          'address': 'Juba',
        };
      },
    );
    expect(await service.searchPlaces('a', 4.85, 31.57), isEmpty);
    expect(requests, 0);
    await expectLater(
      service.getPlaceDetails('ChIJtestplace'),
      throwsStateError,
    );
    await service.getPlaceDetails('ChIJtestplace');
    expect(sessions[0], sessions[1]);
  });

  test(
    'malformed backend coordinates cannot become a selected destination',
    () async {
      final PlacesService service = PlacesService(
        invoke: (String name, Map<String, dynamic> data) async =>
            <String, Object>{
              'latitude': 999,
              'longitude': 31,
              'address': 'invalid',
            },
      );
      await expectLater(
        service.getPlaceDetails('ChIJtestplace'),
        throwsFormatException,
      );
    },
  );
  test('transient search failure retries with the original session', () async {
    final List<String> sessions = <String>[];
    final PlacesService service = PlacesService(
      invoke: (String name, Map<String, dynamic> data) async {
        sessions.add(data['sessionToken'] as String);
        if (sessions.length == 1)
          throw FirebaseFunctionsException(code: 'unavailable');
        return <String, Object>{'results': <Object>[]};
      },
    );
    expect(await service.searchPlaces('Juba', 4.85, 31.57), isEmpty);
    expect(sessions.length, 2);
    expect(sessions[0], sessions[1]);
  });

  test(
    'configuration and account failures are actionable and never retried',
    () async {
      for (final String code in <String>[
        'failed-precondition',
        'permission-denied',
        'unauthenticated',
        'resource-exhausted',
        'not-found',
      ]) {
        int attempts = 0;
        final FirebaseFunctionsException error = FirebaseFunctionsException(
          code: code,
          message: 'sensitive upstream details',
        );
        final PlacesService service = PlacesService(
          invoke: (String name, Map<String, dynamic> data) async {
            attempts++;
            throw error;
          },
        );
        await expectLater(
          service.searchPlaces('Juba', 4.85, 31.57),
          throwsA(same(error)),
        );
        expect(attempts, 1);
        expect(PlacesService.errorMessage(error), isNot(contains('sensitive')));
      }
    },
  );
}
