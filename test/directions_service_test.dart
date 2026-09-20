import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passengerapp/home/services/directions_service.dart';

void main() {
  test('trusted callable route data decodes the Google polyline', () {
    final DrivingRoute route = DrivingRoute.fromCallableData(
      <String, dynamic>{
        'distanceMeters': 4321,
        'durationSeconds': 613,
        'encodedPolyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      },
    );

    expect(route.distanceMeters, 4321);
    expect(route.duration, const Duration(seconds: 613));
    expect(route.points.length, 3);
    expect(route.points.first, const LatLng(38.5, -120.2));
    expect(route.points.last, const LatLng(43.252, -126.453));
  });

  test('trusted callable route data rejects malformed responses', () {
    expect(
      () => DrivingRoute.fromCallableData(
        <String, dynamic>{
          'distanceMeters': 0,
          'durationSeconds': 10,
          'encodedPolyline': 'invalid',
        },
      ),
      throwsFormatException,
    );

    expect(
      () => DrivingRoute.fromCallableData(
        <String, dynamic>{
          'distanceMeters': 1000,
          'durationSeconds': 60,
          'encodedPolyline': '',
        },
      ),
      throwsFormatException,
    );
  });
}
