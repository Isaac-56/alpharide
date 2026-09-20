import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/models/location_selection.dart';

void main() {
  test('location selection prefers a resolved place name', () {
    const LocationSelection selection = LocationSelection(
      latitude: 4.8517,
      longitude: 31.5825,
      address: 'Airport Road, Juba',
      name: 'Imperial Plaza',
    );

    expect(selection.displayName, 'Imperial Plaza');
  });

  test('generic current location falls back to exact coordinates', () {
    const LocationSelection selection = LocationSelection(
      latitude: 4.8517,
      longitude: 31.5825,
      address: 'Current location',
      name: '',
    );

    expect(selection.displayName, '4.851700, 31.582500');
  });
}
