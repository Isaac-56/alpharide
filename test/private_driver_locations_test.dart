import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/home/services/driver_location_service.dart';

void main() {
  test(
    'nearby maps use the bounded server endpoint without a driver identity',
    () async {
      final List<String> calls = <String>[];
      final DriverLocationService service = DriverLocationService(
        invoke: (String name, Map<String, dynamic> data) async {
          calls.add(name);
          expect(data, <String, dynamic>{'latitude': 4.85, 'longitude': 31.58});
          return <String, Object>{
            'drivers': <Object>[
              <String, Object>{
                'driverId': 'nearby_opaque',
                'latitude': 4.852,
                'longitude': 31.583,
                'isOnline': true,
              },
            ],
          };
        },
      );
      final result = await service
          .watchOnlineDrivers(
            latitude: () => 4.85,
            longitude: () => 31.58,
            assignedDriverId: () => null,
          )
          .first;
      expect(calls, <String>['passengerNearbyDrivers']);
      expect(result.single.driverId, 'nearby_opaque');
    },
  );

  test(
    'a late nearby response cannot replace assigned-driver tracking',
    () async {
      final Completer<dynamic> first = Completer<dynamic>();
      String? assigned;
      final List<String> calls = <String>[];
      final DriverLocationService service = DriverLocationService(
        invoke: (String name, Map<String, dynamic> data) async {
          calls.add(name);
          if (name == 'passengerNearbyDrivers') return first.future;
          expect(data, <String, dynamic>{'driverId': 'assigned'});
          return <String, Object>{
            'drivers': <Object>[
              <String, Object>{
                'driverId': 'assigned',
                'latitude': 4.851234,
                'longitude': 31.581234,
                'isOnline': true,
              },
            ],
          };
        },
      );
      final result = service
          .watchOnlineDrivers(
            latitude: () => 4.85,
            longitude: () => 31.58,
            assignedDriverId: () => assigned,
          )
          .first;
      await Future<void>.delayed(Duration.zero);
      assigned = 'assigned';
      first.complete(<String, Object>{
        'drivers': <Object>[
          <String, Object>{
            'driverId': 'old',
            'latitude': 4.852,
            'longitude': 31.583,
          },
        ],
      });
      expect((await result).single.driverId, 'assigned');
      expect(calls, <String>[
        'passengerNearbyDrivers',
        'passengerAssignedDriverLocation',
      ]);
    },
  );

  test(
    'access failures clear markers without falling back to fleet reads',
    () async {
      int calls = 0;
      final DriverLocationService service = DriverLocationService(
        invoke: (String name, Map<String, dynamic> data) async {
          calls++;
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          );
        },
      );
      expect(
        await service
            .watchOnlineDrivers(
              latitude: () => 4.85,
              longitude: () => 31.58,
              assignedDriverId: () => 'assigned',
            )
            .first,
        isEmpty,
      );
      expect(calls, 1);
    },
  );
}
