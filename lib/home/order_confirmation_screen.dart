import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../account/account_ui.dart';
import '../models/ride_option.dart';
import 'driver_search_screen.dart';
import 'services/directions_service.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final String pickupAddress;
  final String destinationAddress;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final List<LatLng> initialRoutePoints;
  final RideOption ride;
  final PaymentMethod paymentMethod;

  const OrderConfirmationScreen({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupLocation,
    required this.destinationLocation,
    this.initialRoutePoints = const <LatLng>[],
    required this.ride,
    required this.paymentMethod,
  });

  @override
  State<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  static const Color primaryColor = Color(0xFF39FF14);

  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  final DirectionsService _directionsService = const DirectionsService();

  late List<LatLng> _routePoints;
  bool _isRouteLoading = false;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _routePoints = List<LatLng>.of(widget.initialRoutePoints);

    if (_routePoints.length < 2) {
      _loadRoadRoute();
    }
  }

  Set<Marker> get _markers {
    return {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        ),
        infoWindow: const InfoWindow(
          title: 'Pickup',
        ),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        infoWindow: const InfoWindow(
          title: 'Destination',
        ),
      ),
    };
  }

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route-preview-shadow'),
        color: Colors.black.withValues(alpha: 0.28),
        width: 15,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: false,
        zIndex: 1,
        points: _routePoints,
      ),
      Polyline(
        polylineId: const PolylineId('route-preview-edge'),
        color: const Color(0xFF12300F),
        width: 11,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: false,
        zIndex: 2,
        points: _routePoints,
      ),
      Polyline(
        polylineId: const PolylineId('route-preview'),
        color: primaryColor,
        width: 8,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: false,
        zIndex: 3,
        points: _routePoints,
      ),
      Polyline(
        polylineId: const PolylineId('route-preview-highlight'),
        color: Colors.white.withValues(alpha: 0.30),
        width: 2,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: false,
        zIndex: 4,
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
      debugPrint('Unable to load confirmation route: $error');

      if (!mounted) return;

      setState(() {
        _isRouteLoading = false;
        _routeError = error is DirectionsException
            ? error.message
            : 'Road route unavailable. Tap to try again.';
      });
    }
  }

  Future<void> _fitRoute() async {
    final GoogleMapController controller = await _mapController.future;

    final List<LatLng> boundsPoints = _routePoints.length >= 2
        ? _routePoints
        : <LatLng>[
            widget.pickupLocation,
            widget.destinationLocation,
          ];

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
        CameraUpdate.newLatLngZoom(
          widget.pickupLocation,
          17,
        ),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        92,
      ),
    );
  }

  void _confirmOrder() {
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSearchScreen(
          pickupLocation: widget.pickupLocation,
          pickupAddress: widget.pickupAddress,
          destinationLocation: widget.destinationLocation,
          destinationAddress: widget.destinationAddress,
          initialRoutePoints: _routePoints,
          ride: widget.ride,
          paymentMethod: widget.paymentMethod,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = AlphaColors.background(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.pickupLocation,
                zoom: 15,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              padding: const EdgeInsets.only(
                top: 140,
                bottom: 310,
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
                    ? Colors.black.withValues(alpha: 0.33)
                    : Colors.white.withValues(alpha: 0.08),
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
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 14,
                  left: 18,
                  child: _roundBackButton(context),
                ),
                Positioned(
                  top: 16,
                  left: 84,
                  right: 18,
                  child: _pickupLabel(),
                ),
              ],
            ),
          ),
          if (_routeError != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 86,
              left: 18,
              right: 18,
              child: _routeErrorBanner(),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _confirmationPanel(),
          ),
        ],
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

  Widget _pickupLabel() {
    final Color backgroundColor = AlphaColors.background(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AlphaColors.border(context),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_rounded,
            color: primaryColor,
            size: 22,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup point',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.pickupAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmationPanel() {
    final Color backgroundColor = AlphaColors.background(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AlphaColors.border(context),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Column(
                children: [
                  _addressLine(
                    label: 'A',
                    address: widget.pickupAddress,
                    color: textColor,
                  ),
                  Divider(
                    height: 18,
                    indent: 39,
                    color: AlphaColors.border(context),
                  ),
                  _addressLine(
                    label: 'B',
                    address: widget.destinationAddress,
                    color: primaryColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 74,
                  height: 48,
                  child: Image.asset(
                    widget.ride.assetPath,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ride.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.ride.seats} seats • ${_paymentLabel(widget.paymentMethod)}',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '~ ${widget.ride.estimatedFareLabel}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _confirmOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: const Color(0xFF071007),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Confirm order',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '~ ${widget.ride.estimatedFareLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressLine({
    required String label,
    required String address,
    required Color color,
  }) {
    final Color textColor = AlphaColors.text(context);
    final Color labelTextColor = AlphaColors.background(context);

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: labelTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _roundBackButton(BuildContext context) {
    return Material(
      color: AlphaColors.surface(context),
      shape: CircleBorder(
        side: BorderSide(color: AlphaColors.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
        },
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            Icons.arrow_back_rounded,
            color: AlphaColors.text(context),
            size: 27,
          ),
        ),
      ),
    );
  }

  String _paymentLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.wallet:
        return 'Wallet';
    }
  }
}
