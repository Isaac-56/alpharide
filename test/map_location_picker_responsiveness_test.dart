import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passengerapp/home/map_location_picker.dart';
import 'package:passengerapp/models/location_selection.dart';

void main() {
  testWidgets('a stationary pin can be confirmed while its address is pending', (tester) async {
    final pending = Completer<List<Placemark>>();
    late GoogleMap map;
    LocationSelection? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(onPressed: () async {
        selected = await Navigator.of(context).push<LocationSelection>(MaterialPageRoute(
          builder: (_) => MapLocationPicker(
            initialLocation: const LatLng(4.85, 31.57),
            initialAddress: 'Old address',
            isPickup: false,
            addressResolver: (_, __) => pending.future,
            mapBuilder: (value) { map = value; return const SizedBox.expand(); },
          ),
        ));
      }, child: const Text('Open')));
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    map.onCameraMove!(const CameraPosition(target: LatLng(4.86, 31.58), zoom: 17));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    map.onCameraIdle!();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await tester.tap(find.text('Confirm destination'));
    await tester.pumpAndSettle();
    expect(selected?.latitude, 4.86);
    expect(selected?.longitude, 31.58);
    expect(selected?.address, 'Pinned location');
    pending.complete(<Placemark>[Placemark(name: 'Late address')]);
    await tester.pump();
    expect(selected?.address, 'Pinned location');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older address cannot replace a more recently selected pin', (tester) async {
    final old = Completer<List<Placemark>>();
    final current = Completer<List<Placemark>>();
    late GoogleMap map;
    await tester.pumpWidget(MaterialApp(home: MapLocationPicker(
      initialLocation: const LatLng(4.85, 31.57), initialAddress: 'Initial', isPickup: false,
      addressResolver: (lat, lng) => lat == 4.86 ? old.future : current.future,
      mapBuilder: (value) { map = value; return const SizedBox.expand(); },
    )));
    map.onCameraMove!(const CameraPosition(target: LatLng(4.86, 31.58), zoom: 17));
    map.onCameraIdle!();
    await tester.pump(const Duration(milliseconds: 350));
    map.onCameraMove!(const CameraPosition(target: LatLng(4.87, 31.59), zoom: 17));
    map.onCameraIdle!();
    await tester.pump(const Duration(milliseconds: 350));
    current.complete(<Placemark>[Placemark(name: 'New pin')]);
    await tester.pump();
    old.complete(<Placemark>[Placemark(name: 'Old pin')]);
    await tester.pumpAndSettle();
    expect(find.text('New pin'), findsOneWidget);
    expect(find.text('Old pin'), findsNothing);
  });
}
