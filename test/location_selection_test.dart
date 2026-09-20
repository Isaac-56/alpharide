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

  test('generic current location stays readable instead of showing numbers', () {
    const LocationSelection selection = LocationSelection(
      latitude: 4.8517,
      longitude: 31.5825,
      address: 'Current location',
      name: '',
      isCurrentLocation: true,
    );

    expect(selection.displayName, 'My location');
  });

  test('coordinate-like labels are hidden from the pickup UI', () {
    const LocationSelection selection = LocationSelection(
      latitude: 4.8517,
      longitude: 31.5825,
      address: '4.851700, 31.582500',
      name: '',
      isCurrentLocation: true,
    );

    expect(selection.displayName, 'My location');
  });
}
