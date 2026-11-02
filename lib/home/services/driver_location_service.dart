import 'package:cloud_functions/cloud_functions.dart';

import '../../models/driver_location_model.dart';

/// Passenger maps never subscribe to the private fleet location database.
class DriverLocationService {
  static const Duration staleAfter = Duration(seconds: 90);
  final FirebaseFunctions? _functionsOverride;
  final Future<dynamic> Function(String, Map<String, dynamic>)? _invokeOverride;
  DriverLocationService({
    FirebaseFunctions? functions,
    Future<dynamic> Function(String, Map<String, dynamic>)? invoke,
  }) : _functionsOverride = functions,
       _invokeOverride = invoke;

  Future<dynamic> _invoke(String name, Map<String, dynamic> data) async {
    if (_invokeOverride != null) {
      return _invokeOverride(name, data);
    }
    final FirebaseFunctions functions =
        _functionsOverride ??
        FirebaseFunctions.instanceFor(region: 'africa-south1');
    return (await functions
            .httpsCallable(
              name,
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 15),
              ),
            )
            .call<dynamic>(data))
        .data;
  }

  Stream<List<DriverLocationModel>> watchOnlineDrivers({
    required double Function() latitude,
    required double Function() longitude,
    required String? Function() assignedDriverId,
    bool Function()? isActive,
  }) async* {
    while (isActive?.call() ?? true) {
      final String? selected = assignedDriverId();
      final double requestedLatitude = latitude();
      final double requestedLongitude = longitude();
      try {
        final dynamic response = await _invoke(
          selected == null
              ? 'passengerNearbyDrivers'
              : 'passengerAssignedDriverLocation',
          selected == null
              ? <String, dynamic>{
                  'latitude': requestedLatitude,
                  'longitude': requestedLongitude,
                }
              : <String, dynamic>{'driverId': selected},
        );
        if (!(isActive?.call() ?? true)) {
          return;
        }
        // Never apply a late nearby/old-trip response after the filter changed.
        if (selected != assignedDriverId() ||
            requestedLatitude != latitude() ||
            requestedLongitude != longitude()) {
          continue;
        }
        final Object? raw = response;
        final Object? rows = raw is Map ? raw['drivers'] : null;
        final List<DriverLocationModel> drivers = <DriverLocationModel>[];
        if (rows is List) {
          for (final Object? row in rows) {
            if (row is! Map) {
              continue;
            }
            final DriverLocationModel driver = DriverLocationModel.fromMap(
              row['driverId']?.toString() ?? '',
              Map<Object?, Object?>.from(row),
            );
            if (driver.driverId.isNotEmpty && driver.hasValidCoordinates) {
              drivers.add(driver);
            }
          }
        }
        yield List<DriverLocationModel>.unmodifiable(drivers);
      } on FirebaseFunctionsException {
        // Drop stale markers and retry; never fall back to the private feed.
        yield const <DriverLocationModel>[];
      }
      await Future<void>.delayed(Duration(seconds: selected == null ? 5 : 2));
    }
  }
}
