import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_ui.dart';
import '../core/widgets/alpha_components.dart';
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
  final DirectionsService _directionsService = DirectionsService();
  final RideService _rideService = RideService.instance;
  final Set<Marker> _markers = <Marker>{};

  late final AnimationController _progressController;
  late final LiveDriverMarkerController _liveDrivers;
  StreamSubscription<RideLiveState?>? _rideSubscription;

  late List<LatLng> _routePoints;
  RideLiveState? _liveState;
  bool _isRouteLoading = false;
  bool _isCancelling = false;
  bool _terminalHandled = false;
  String _rideStatus = 'requested';
  String? _routeError;
  String? _driverPhotoUrl;
  String? _photoDriverId;
  bool _isDriverPhotoLoading = false;
  int _driverPhotoRequestId = 0;

  bool get _canPassengerCancel =>
      !_isCancelling &&
      (_liveState?.canPassengerCancel ??
          const <String>{
            'requested',
            'offered',
            'accepted',
            'driver_arriving',
            'arrived',
          }.contains(_rideStatus));

  bool get _isSearching =>
      _rideStatus == 'requested' || _rideStatus == 'offered';

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

  Future<void> _loadAssignedDriverPhoto(String? driverId) async {
    final int requestId = ++_driverPhotoRequestId;
    if (driverId == null || driverId.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _photoDriverId = null;
        _driverPhotoUrl = null;
        _isDriverPhotoLoading = false;
      });
      return;
    }

    setState(() {
      _photoDriverId = driverId;
      _driverPhotoUrl = null;
      _isDriverPhotoLoading = true;
    });

    String? photoUrl;
    try {
      photoUrl =
          await _rideService.getAssignedDriverPhotoUrl(widget.rideId);
    } on Object catch (error) {
      debugPrint('Unable to load assigned driver photo: $error');
    }

    if (!mounted ||
        requestId != _driverPhotoRequestId ||
        _photoDriverId != driverId) {
      return;
    }
    setState(() {
      _driverPhotoUrl = photoUrl;
      _isDriverPhotoLoading = false;
    });
  }

  void _handleRideState(RideLiveState? state) {
    if (!mounted || state == null) return;

    final bool statusChanged = _rideStatus != state.status;
    final bool driverChanged = _liveState?.driverId != state.driverId;
    final bool summaryChanged = _liveState?.driver?.displayName !=
            state.driver?.displayName ||
        _liveState?.driver?.plateNumber != state.driver?.plateNumber;

    if (statusChanged || driverChanged || summaryChanged || _liveState == null) {
      setState(() {
        _rideStatus = state.status;
        _liveState = state;
      });
    } else {
      _liveState = state;
    }

    _liveDrivers.showOnlyDriver(state.driverId);
    if (driverChanged) {
      unawaited(_loadAssignedDriverPhoto(state.driverId));
    }

    if (_isSearching) {
      if (!_progressController.isAnimating) {
        _progressController.repeat();
      }
    } else if (_progressController.isAnimating) {
      _progressController.stop();
    }

    final bool externallyTerminal =
        state.status == 'cancelled' || state.status == 'expired';

    if (externallyTerminal && !_terminalHandled) {
      _terminalHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (!_isCancelling || state.status == 'expired') {
          final String message = state.status == 'expired'
              ? 'No driver accepted this request in time.'
              : 'Your ride was cancelled.';

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
        _closeRideFlow();
      });
      return;
    }

    if (state.status == 'completed' && !_terminalHandled) {
      _terminalHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCompletedRide(state);
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

  String get _statusMessage => switch (_rideStatus) {
        'requested' || 'offered' =>
          'We are matching you with the closest available driver.',
        'accepted' =>
          'Your driver accepted the request and is preparing to head to pickup.',
        'driver_arriving' =>
          'Your assigned driver is on the way to your pickup point.',
        'arrived' => 'Your driver has arrived at the pickup point.',
        'in_progress' => 'You are on the way to your destination.',
        'completed' => 'Your trip is complete.',
        _ => 'Your ride is being updated.',
      };

  double get _rideProgress => switch (_rideStatus) {
        'accepted' => 0.22,
        'driver_arriving' => 0.45,
        'arrived' => 0.68,
        'in_progress' => 0.86,
        'completed' => 1,
        _ => 0,
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

  void _closeRideFlow() {
    final ModalRoute<dynamic>? rideRoute = ModalRoute.of(context);
    if (rideRoute == null || !rideRoute.isActive) return;

    final NavigatorState navigator = Navigator.of(context);
    navigator.popUntil((Route<dynamic> route) => route == rideRoute);
    if (rideRoute.isCurrent) navigator.pop();
  }

  Future<void> _cancelRide(String reason) async {
    if (_isCancelling) return;

    setState(() {
      _isCancelling = true;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Cancelling your ride…'),
        ),
      );

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
      _closeRideFlow();
    }
  }

  Future<void> _showCancelConfirmation() async {
    if (!_canPassengerCancel) return;

    final bool? continueCancellation = await showModalBottomSheet<bool>(
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
                        ? () => Navigator.pop(sheetContext, true)
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

    if (continueCancellation != true || !mounted) return;

    final String? reason = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => const CancelReasonScreen(),
      ),
    );

    if (reason != null && mounted) {
      await _cancelRide(reason);
    }
  }

  Future<void> _showCompletedRide(RideLiveState state) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final Color backgroundColor = AlphaColors.background(sheetContext);
        final Color textColor = AlphaColors.text(sheetContext);
        final Color mutedColor = AlphaColors.muted(sheetContext);

        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Align(
                  alignment: Alignment.center,
                  child: CircleAvatar(
                    radius: 31,
                    backgroundColor: primaryColor,
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.black,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Trip completed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Thanks for riding with AlphaRide.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor, fontSize: 14.5),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AlphaColors.surface(sheetContext),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AlphaColors.border(sheetContext)),
                  ),
                  child: Column(
                    children: <Widget>[
                      _ReceiptRow(
                        label: 'Final fare',
                        value:
                            '${RideOption.formatAmount(state.fare)} ${state.currencyCode}',
                      ),
                      if (state.waitingCharge > 0) ...<Widget>[
                        const SizedBox(height: 10),
                        _ReceiptRow(
                          label: 'Distance fare',
                          value:
                              '${RideOption.formatAmount(state.estimatedFare)} ${state.currencyCode}',
                        ),
                        const SizedBox(height: 10),
                        _ReceiptRow(
                          label: 'Customer waiting',
                          value:
                              '${RideOption.formatAmount(state.waitingCharge)} ${state.currencyCode}',
                        ),
                      ],
                      const SizedBox(height: 12),
                      const _ReceiptRow(label: 'Payment', value: 'Cash'),
                      const SizedBox(height: 16),
                      _ReceiptLocation(
                        icon: Icons.my_location_rounded,
                        value: widget.pickupAddress,
                      ),
                      const SizedBox(height: 10),
                      _ReceiptLocation(
                        icon: Icons.flag_rounded,
                        value: widget.destinationAddress,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      if (mounted) _closeRideFlow();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: const Text(
                      'Done',
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
    _driverPhotoRequestId++;
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
        if (!didPop && _canPassengerCancel) _showCancelConfirmation();
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
                padding: const EdgeInsets.only(bottom: 330),
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
    final Color surfaceColor = AlphaColors.surface(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);
    final RideDriverSummary? driver = _liveState?.driver;

    return SafeArea(
      top: false,
      child: AlphaMapSheet(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            AlphaFlowHeader(
              title: _searchTitle,
              subtitle: _statusMessage,
              compact: true,
              trailing: SizedBox(
                width: 90,
                height: 58,
                child: Image.asset(
                  widget.ride.assetPath,
                  fit: BoxFit.contain,
                  cacheWidth: 280,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AlphaMetricChip(
                  icon: widget.ride.id == 'boda'
                      ? Icons.two_wheeler_rounded
                      : widget.ride.id == 'rickshaw'
                      ? Icons.electric_rickshaw_rounded
                      : Icons.local_taxi_rounded,
                  label: widget.ride.name,
                ),
                AlphaMetricChip(
                  icon: Icons.payments_outlined,
                  label:
                      '~ ${RideOption.formatAmount(_liveState?.estimatedFare ?? widget.ride.estimatedFare!)} ${RideOption.currencyCode}',
                ),
                AlphaMetricChip(
                  icon: _isSearching
                      ? Icons.radar_rounded
                      : Icons.navigation_rounded,
                  label: _statusLabel,
                  emphasized: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              AnimatedBuilder(
                animation: _progressController,
                builder: (BuildContext context, Widget? child) {
                  return LinearProgressIndicator(
                    value: _progressController.value,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: surfaceColor,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(primaryColor),
                  );
                },
              )
            else
              LinearProgressIndicator(
                value: _rideProgress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: surfaceColor,
                valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            const SizedBox(height: 14),
            if (_liveState?.isWaiting == true) ...<Widget>[
              const SizedBox(height: 14),
              _PassengerWaitingCard(state: _liveState!),
            ],
            if (!_isSearching && driver != null) ...<Widget>[
              const SizedBox(height: 16),
              _AssignedDriverCard(
                driver: driver,
                photoUrl: _driverPhotoUrl,
                isPhotoLoading: _isDriverPhotoLoading,
              ),
            ],
            const SizedBox(height: 16),
            if (_canPassengerCancel)
              TextButton(
                onPressed: _showCancelConfirmation,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: textColor,
                ),
                child: Text(
                  _isCancelling ? 'Cancelling...' : 'Cancel order',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (!_isSearching)
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 17,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'The ride is active. Trip changes are controlled by the live ride status.',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignedDriverCard extends StatelessWidget {
  const _AssignedDriverCard({
    required this.driver,
    required this.photoUrl,
    required this.isPhotoLoading,
  });

  final RideDriverSummary driver;
  final String? photoUrl;
  final bool isPhotoLoading;

  String get _initials {
    final List<String> names = driver.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return 'A';
    if (names.length == 1) return names.first.substring(0, 1).toUpperCase();
    return '${names.first.substring(0, 1)}${names.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _callDriver(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: driver.phoneNumber);
    try {
      final bool opened = await launchUrl(phoneUri);
      if (opened || !context.mounted) return;
    } on Object {
      if (!context.mounted) return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('The phone dialer could not be opened.'),
        ),
      );
  }

  Widget _avatar(BuildContext context) {
    final Color textColor = AlphaColors.text(context);
    final String? resolvedPhotoUrl =
        photoUrl == null || photoUrl!.trim().isEmpty ? null : photoUrl!.trim();

    Widget fallback() => ColoredBox(
          color: primaryColor.withValues(alpha: 0.18),
          child: Center(
            child: Text(
              _initials,
              style: TextStyle(
                color: textColor,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );

    return Semantics(
      image: true,
      label: 'Photo of driver ${driver.displayName}',
      child: SizedBox(
        width: 68,
        height: 68,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.18),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.48),
                    width: 2,
                  ),
                ),
                child: isPhotoLoading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: primaryColor,
                          ),
                        ),
                      )
                    : resolvedPhotoUrl == null
                        ? fallback()
                        : Image.network(
                            resolvedPhotoUrl,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => fallback(),
                          ),
              ),
            ),
            Positioned(
              right: -1,
              bottom: 1,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AlphaColors.surface(context),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Colors.black,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color borderColor = AlphaColors.border(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.18
                  : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _avatar(context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            driver.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'VERIFIED',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      driver.vehicleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (driver.plateNumber.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AlphaColors.background(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          driver.plateNumber,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (driver.phoneNumber.isNotEmpty) ...<Widget>[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.fromLTRB(13, 9, 8, 9),
              decoration: BoxDecoration(
                color: AlphaColors.background(context),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.phone_in_talk_rounded,
                    color: mutedColor,
                    size: 18,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Driver contact',
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          driver.phoneNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    excludeSemantics: true,
                    label:
                        'Call driver ${driver.displayName} at ${driver.phoneNumber}',
                    child: Material(
                      color: primaryColor,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const Key('callAssignedDriver'),
                        onTap: () => _callDriver(context),
                        child: const SizedBox.square(
                          dimension: 44,
                          child: Icon(
                            Icons.call_rounded,
                            color: Colors.black,
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PassengerWaitingCard extends StatelessWidget {
  const _PassengerWaitingCard({required this.state});

  final RideLiveState state;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(
        const Duration(seconds: 1),
        (int tick) => tick,
      ),
      initialData: 0,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        final DateTime now = DateTime.now();
        final int totalSeconds = state.waitingSecondsAt(now);
        final int activeSeconds = state.waitingStartedAt == null
            ? 0
            : now
                .difference(state.waitingStartedAt!)
                .inSeconds
                .clamp(0, 4 * 60 * 60)
                .toInt();
        final int freeRemaining = (state.waitingGraceSeconds - activeSeconds)
            .clamp(0, 999999)
            .toInt();
        final int projectedCharge = state.waitingChargeAt(now);
        final int projectedFare = state.fareAt(now);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF39FF14).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF39FF14).withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.timer_outlined,
                    color: Color(0xFF39FF14),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Customer-requested waiting • ${_clock(totalSeconds)}',
                      style: TextStyle(
                        color: AlphaColors.text(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                freeRemaining > 0
                    ? '${_clock(freeRemaining)} free waiting remains.'
                    : '${RideOption.formatAmount(projectedCharge)} ${state.currencyCode} waiting • Current fare ${RideOption.formatAmount(projectedFare)} ${state.currencyCode}',
                style: TextStyle(
                  color: AlphaColors.muted(context),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This meter is for a stop requested by you; normal traffic is not charged as customer waiting.',
                style: TextStyle(
                  color: AlphaColors.muted(context),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _clock(int totalSeconds) {
    final int safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final int minutes = safeSeconds ~/ 60;
    final int seconds = safeSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(label, style: TextStyle(color: AlphaColors.muted(context))),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: AlphaColors.text(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReceiptLocation extends StatelessWidget {
  const _ReceiptLocation({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: primaryColor),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AlphaColors.text(context),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
