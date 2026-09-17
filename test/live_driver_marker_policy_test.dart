import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/services/live_driver_marker_controller.dart';

void main() {
  group('LiveDriverMarkerPolicy', () {
    test('selects the correct overhead marker for every launch vehicle', () {
      expect(
        LiveDriverMarkerPolicy.markerAssetForVehicle('standard'),
        'assets/images/vehicles/alpha_driver_top.png',
      );
      expect(
        LiveDriverMarkerPolicy.markerAssetForVehicle('Alpha Boda'),
        'assets/images/vehicles/alpha_boda_top.png',
      );
      expect(
        LiveDriverMarkerPolicy.markerAssetForVehicle('Tuk Tuk'),
        'assets/images/vehicles/alpha_rickshaw_top.png',
      );
    });

    test('uses the standard car marker for unknown vehicle labels', () {
      expect(
        LiveDriverMarkerPolicy.markerAssetForVehicle('future vehicle'),
        'assets/images/vehicles/alpha_driver_top.png',
      );
    });

    test('normalizes headings into one complete turn', () {
      expect(LiveDriverMarkerPolicy.normalizedHeading(360), 0);
      expect(LiveDriverMarkerPolicy.normalizedHeading(725), 5);
      expect(LiveDriverMarkerPolicy.normalizedHeading(-10), 350);
    });

    test('interpolates through north using the shortest rotation', () {
      expect(
        LiveDriverMarkerPolicy.interpolatedHeading(350, 10, 0.5),
        closeTo(0, 0.001),
      );
      expect(
        LiveDriverMarkerPolicy.interpolatedHeading(10, 350, 0.5),
        closeTo(0, 0.001),
      );
    });
  });
}
