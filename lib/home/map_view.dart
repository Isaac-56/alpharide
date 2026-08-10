import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'services/live_driver_marker_controller.dart';

class MapView extends StatefulWidget {
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
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late final LiveDriverMarkerController _liveDrivers;

  @override
  void initState() {
    super.initState();
    _liveDrivers = LiveDriverMarkerController(
      center: widget.initialCameraPosition.target,
    )
      ..addListener(_refreshDriverMarkers)
      ..start();
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liveDrivers.updateCenter(widget.initialCameraPosition.target);
  }

  @override
  void dispose() {
    _liveDrivers
      ..removeListener(_refreshDriverMarkers)
      ..dispose();
    super.dispose();
  }

  void _refreshDriverMarkers() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: widget.initialCameraPosition,
      onMapCreated: widget.onMapCreated,
      onCameraMove: widget.onCameraMove,
      markers: <Marker>{
        ...widget.markers,
        ..._liveDrivers.markers,
      },
      polylines: widget.polylines,
      myLocationEnabled: widget.myLocationEnabled,
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
