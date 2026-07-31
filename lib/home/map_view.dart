import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapView extends StatelessWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<CameraPosition>? onCameraMove;
  final bool myLocationEnabled;

  const MapView({
    super.key,
    required this.initialCameraPosition,
    required this.markers,
    required this.polylines,
    required this.onMapCreated,
    this.onCameraMove,
    this.myLocationEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: initialCameraPosition,
      onMapCreated: onMapCreated,
      onCameraMove: onCameraMove,
      markers: markers,
      polylines: polylines,
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      trafficEnabled: false,
      buildingsEnabled: true,
      indoorViewEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      zoomGesturesEnabled: true,
      mapType: MapType.normal,
    );
  }
}
