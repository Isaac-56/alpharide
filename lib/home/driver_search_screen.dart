import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../account/account_ui.dart';
import '../models/ride_backend.dart';
import '../models/ride_option.dart';
import '../services/ride_service.dart';
import 'cancel_reason_screen.dart';
import 'services/directions_service.dart';
import 'services/live_driver_marker_controller.dart';

class DriverSearchScreen extends StatefulWidget {
  final String rideId;
  final LatLng pickupLocation;
  final String pickupAddress;
  final LatLng destinationLocation;
  final String destinationAddress;
  final List<LatLng> initialRoutePoints;
  final RideOption ride;
  final PaymentMethod paymentMethod;

  const DriverSearchScreen({
    super.key,
    required this.rideId,
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

  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final DirectionsService _directionsService = const DirectionsService();
  final RideService _rideService = RideService.instance;
  final Set<Marker> _markers = <Marker>{};

  late final AnimationController _progressController;
  late final LiveDriverMarkerController _liveDrivers;
  StreamSubscription<RideLiveState?>? _rideSubscription;

  late List<LatLng> _routePoints;
  bool _isRouteLoading = false;
  bool _isCancelling = false;
  bool _terminalHandled = false;
  String _rideStatus = 'requested';
  String? _routeError;

  bool get _canPassengerCancel =>
      !_isCancelling &&
      (_rideStatus == 'requested' || _rideStatus == 'offered');

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _routePoints = List<LatLng>.of(widget.initialRoutePoints);
    _liveDrivers = LiveDriverMarkerController(center: widget.pickupLocation)
      ..addListener(_refreshDriverMarkers)
      ..start();

    _buildStaticMarkers();
    _listenToRide();

    if (_routePoints.length < 2) {
      _loadRoadRoute();
    }
  }

  void _listenToRide() {
    _rideSubscription = _rideService.watchRide(widget.rideId).listen(
      _handleRideState,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Unable to watch ride ${widget.rideId}: $error');
      },
    );
  }

  void _handleRideState(RideLiveState? state) {
    if (!mounted || state == null) return;

    if (_rideStatus != state.status) {
      setState(() {
        _rideStatus = state.status;
      });
    }

    final bool externallyTerminal =
        state.status == 'cancelled' || state.status == 'expired';

    if (externallyTerminal && !_terminalHandled && !_isCancelling) {
      _terminalHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final String message = state.status == 'expired'
            ? 'Your ride request expired.'
            : 'Your ride was cancelled.';

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        Navigator.pop(context);
      });
    }
  }

  String get _statusLabel => switch (_rideStatus) {
        'requested' => 'Request sent',
        'offered' => 'Contacting drivers',
        'accepted' => 'Driver assigned',
        'driver_arriving' => 'Driver on the way',
        'arrived' => 'Driver arrived',
        'in_progress' => 'Trip in progress',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'expired' => 'Expired',
        _ => 'Updating ride',
      };

  String get _searchTitle => switch (_rideStatus) {
        'requested' || 'offered' => 'Looking for a driver',
        'accepted' => 'Driver assigned',
        'driver_arriving' => 'Driver on the way',
        'arrived' => 'Driver arrived',
        'in_progress' => 'Trip in progress',
        'completed' => 'Ride completed',
        'cancelled' => 'Ride cancelled',
        'expired' => 'Request expired',
        _ => 'Ride update',
      };

  Set<Polyline> get _polylines {
    if (_routePoints.length < 2) return const <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('active-trip-route-shadow'),
        color: Colors.black.withValues(alpha: 0.28),
        width: 15,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1,
        points: _routePoints,
      ),
      Polyline(
        polylineId: const PolylineId('active-trip-route'),
        color: primaryColor,
        width: 8,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 2,
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

    final List<LatLng> points = _routePoints.length >= 2
        ? _routePoints
        : <LatLng>[widget.pickupLocation, widget.destinationLocation];
    final GoogleMapController controller = await _mapController.future;

    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;

    for (final LatLng point in points.skip(1)) {
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

  void _buildStaticMarkers() {
    _markers
      ..clear()
      ..add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickupLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Your pickup'),
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
      );
  }

  void _refreshDriverMarkers() {
    if (mounted) setState(() {});
  }

  Future<void> _cancelRide(String reason) async {
    if (!_canPassengerCancel) return;

    setState(() {
      _isCancelling = true;
    });

    bool cancelled = false;
    try {
      await _rideService.cancelRide(rideId: widget.rideId, reason: reason);
      cancelled = true;
    } on RideBackendException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('Unable to cancel ride ${widget.rideId}: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('The ride could not be cancelled. Please try again.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }

    if (cancelled && mounted) {
      _terminalHandled = true;
      Navigator.pop(context);
    }
  }

  Future<void> _showCancelConfirmation() async {
    if (!_canPassengerCancel) return;

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
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _canPassengerCancel
                        ? () async {
                            Navigator.pop(sheetContext);
                            final String? reason =
                                await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CancelReasonScreen(),
                              ),
                            );
                            if (reason != null && mounted) {
                              await _cancelRide(reason);
                            }
                          }
                        : null,
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
                    onPressed: () => Navigator.pop(sheetContext),
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
  void dispose() {
    _rideSubscription?.cancel();
    _liveDrivers
      ..removeListener(_refreshDriverMarkers)
      ..dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor = AlphaColors.background(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _showCancelConfirmation();
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
                markers: <Marker>{..._markers, ..._liveDrivers.markers},
                polylines: _polylines,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                padding: const EdgeInsets.only(bottom: 275),
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
                top: MediaQuery.paddingOf(context).top + 18,
                left: 18,
                right: 18,
                child: Material(
                  color: AlphaColors.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _loadRoadRoute,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _routeError!,
                        style: TextStyle(color: AlphaColors.text(context)),
                      ),
                    ),
                  ),
                ),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                        _searchTitle,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.ride.name} • ~ ${widget.ride.estimatedFareLabel}',
                        style: TextStyle(color: mutedColor, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusLabel,
                        style: const TextStyle(
                          color: primaryColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 86,
                  height: 58,
                  child: Image.asset(widget.ride.assetPath, fit: BoxFit.contain),
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
                  valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
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
              onPressed: _canPassengerCancel ? _showCancelConfirmation : null,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: textColor,
              ),
              child: Text(
                _isCancelling
                    ? 'Cancelling...'
                    : _canPassengerCancel
                        ? 'Cancel order'
                        : 'Cancellation unavailable',
                style: const TextStyle(
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
