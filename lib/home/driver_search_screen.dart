import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../account/account_ui.dart';
import '../models/ride_option.dart';
import 'cancel_reason_screen.dart';
import 'services/directions_service.dart';

class DriverSearchScreen extends StatefulWidget {
  final LatLng pickupLocation;
  final String pickupAddress;
  final LatLng destinationLocation;
  final String destinationAddress;
  final List<LatLng> initialRoutePoints;
  final RideOption ride;
  final PaymentMethod paymentMethod;

  const DriverSearchScreen({
    super.key,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.destinationLocation,
    required this.destinationAddress,
    this.initialRoutePoints = const <LatLng>[],
    required this.ride,
    required this.paymentMethod,
  });

  @override
  State<DriverSearchScreen> createState() => _DriverSearchScreenState();
}

class _DriverSearchScreenState extends State<DriverSearchScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF39FF14);

  late final AnimationController _progressController;
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final DirectionsService _directionsService = const DirectionsService();
  final Set<Marker> _markers = {};

  late List<LatLng> _routePoints;
  bool _isRouteLoading = false;
  String? _routeError;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _routePoints = List<LatLng>.of(widget.initialRoutePoints);

    _buildDriverMarkers();

    if (_routePoints.length < 2) {
      _loadRoadRoute();
    }
  }

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('active-trip-route'),
        color: primaryColor,
        width: 6,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: false,
        points: _routePoints,
      ),
    };
  }

  Future<void> _loadRoadRoute() async {
    if (_isRouteLoading) return;

    setState(() {
      _isRouteLoading = true;
      _routeError = null;
    });

    try {
      final DrivingRoute route =
          await _directionsService.getShortestDrivingRoute(
        origin: widget.pickupLocation,
        destination: widget.destinationLocation,
      );

      if (!mounted) return;

      setState(() {
        _routePoints = route.points;
        _isRouteLoading = false;
      });

      await _fitRoute();
    } catch (error) {
      debugPrint('Unable to load driver-search route: $error');

      if (!mounted) return;

      setState(() {
        _isRouteLoading = false;
        _routeError = error is DirectionsException
            ? error.message
            : 'Road route unavailable. Tap to retry.';
      });
    }
  }

  Future<void> _fitRoute() async {
    if (!_mapController.isCompleted) return;

    final List<LatLng> boundsPoints = _routePoints.length >= 2
        ? _routePoints
        : <LatLng>[
            widget.pickupLocation,
            widget.destinationLocation,
          ];
    final GoogleMapController controller = await _mapController.future;

    double south = boundsPoints.first.latitude;
    double north = boundsPoints.first.latitude;
    double west = boundsPoints.first.longitude;
    double east = boundsPoints.first.longitude;

    for (final LatLng point in boundsPoints.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }

    if ((north - south).abs() < 0.0001 && (east - west).abs() < 0.0001) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(widget.pickupLocation, 17),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        82,
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<BitmapDescriptor> _vehicleMarker() async {
    final ByteData data = await rootBundle.load(widget.ride.assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 94,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }

    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
  }

  Future<void> _buildDriverMarkers() async {
    final BitmapDescriptor carIcon = await _vehicleMarker();

    if (!mounted) return;

    final double latitude = widget.pickupLocation.latitude;
    final double longitude = widget.pickupLocation.longitude;

    setState(() {
      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: widget.pickupLocation,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: const InfoWindow(
              title: 'Your pickup',
            ),
          ),
        )
        ..add(
          Marker(
            markerId: const MarkerId('destination'),
            position: widget.destinationLocation,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: 'Destination',
              snippet: widget.destinationAddress,
            ),
          ),
        )
        ..addAll(
          [
            LatLng(latitude + 0.0022, longitude - 0.0014),
            LatLng(latitude - 0.0017, longitude + 0.0018),
            LatLng(latitude + 0.0008, longitude + 0.0026),
          ].asMap().entries.map(
                (MapEntry<int, LatLng> entry) => Marker(
                  markerId: MarkerId('driver-${entry.key}'),
                  position: entry.value,
                  icon: carIcon,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                ),
              ),
        );
    });
  }

  Future<void> _showCancelConfirmation() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final Color backgroundColor = AlphaColors.background(sheetContext);
        final Color textColor = AlphaColors.text(sheetContext);
        final Color mutedColor = AlphaColors.muted(sheetContext);

        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AlphaColors.border(sheetContext),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);

                      final bool? cancelled = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CancelReasonScreen(),
                        ),
                      );

                      if (cancelled == true && mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(
                      'Cancel order',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Text(
                  'Are you sure?',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cancelling may lead to a longer wait, and rebooking does not guarantee a faster trip.',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: const Color(0xFF071007),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: const Text(
                      'Wait for driver',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = AlphaColors.background(context);
    final Color textColor = AlphaColors.text(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _showCancelConfirmation();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: widget.pickupLocation,
                  zoom: 15.7,
                ),
                markers: _markers,
                polylines: _polylines,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                padding: const EdgeInsets.only(
                  bottom: 260,
                ),
                onMapCreated: (GoogleMapController controller) {
                  if (!_mapController.isCompleted) {
                    _mapController.complete(controller);
                    Future<void>.delayed(
                      const Duration(milliseconds: 350),
                      _fitRoute,
                    );
                  }
                },
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: isDarkMode
                      ? Colors.black.withValues(alpha: 0.40)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 230,
                          ),
                          child: Text(
                            widget.pickupAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isRouteLoading)
              const SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: primaryColor,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            if (_routeError != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 78,
                left: 18,
                right: 18,
                child: _routeErrorBanner(),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _searchPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeErrorBanner() {
    return Material(
      color: AlphaColors.surface(context).withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _loadRoadRoute,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 10,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: primaryColor,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _routeError!,
                  style: TextStyle(
                    color: AlphaColors.text(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.refresh_rounded,
                color: AlphaColors.text(context),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchPanel() {
    final Color backgroundColor = AlphaColors.background(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Looking for a driver',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.ride.name} • ~ ${widget.ride.estimatedFareLabel}',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 86,
                  height: 58,
                  child: Image.asset(
                    widget.ride.assetPath,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AnimatedBuilder(
              animation: _progressController,
              builder: (BuildContext context, Widget? child) {
                return LinearProgressIndicator(
                  value: _progressController.value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(99),
                  backgroundColor: surfaceColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    primaryColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              'We are matching you with the closest available driver.',
              style: TextStyle(
                color: mutedColor,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: _showCancelConfirmation,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: textColor,
              ),
              child: const Text(
                'Cancel order',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
