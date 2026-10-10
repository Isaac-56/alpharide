import 'package:firebase_database/firebase_database.dart';

import '../../models/driver_location_model.dart';

class DriverLocationService {
  static const Duration staleAfter = Duration(seconds: 90);

  final DatabaseReference _locations =
      FirebaseDatabase.instance.ref('driver_locations');

  Stream<List<DriverLocationModel>> watchOnlineDrivers() {
    return _locations.onValue.map(
      (DatabaseEvent event) {
        final Object? value = event.snapshot.value;

        if (value is! Map<Object?, Object?>) {
          return const <DriverLocationModel>[];
        }

        final int now = DateTime.now().millisecondsSinceEpoch;
        final List<DriverLocationModel> drivers = <DriverLocationModel>[];

        for (final MapEntry<Object?, Object?> entry in value.entries) {
          final Object? rawDriver = entry.value;

          if (rawDriver is! Map<Object?, Object?>) continue;

          final DriverLocationModel driver = DriverLocationModel.fromMap(
            entry.key.toString(),
            rawDriver,
          );

          final bool locationIsFresh = driver.updatedAt == 0 ||
              now - driver.updatedAt <= staleAfter.inMilliseconds;

          if (driver.isOnline &&
              driver.hasValidCoordinates &&
              locationIsFresh) {
            drivers.add(driver);
          }
        }

        return List<DriverLocationModel>.unmodifiable(drivers);
      },
    );
  }
}
