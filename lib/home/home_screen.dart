import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_selection.dart';
import '../models/ride_option.dart';
import '../services/firestore_service.dart';
import '../services/session_service.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/location_permission_request.dart';
import 'destination_search.dart';
import 'map_view.dart';
import 'order_confirmation_screen.dart';
import 'order_panel.dart';
import 'services/directions_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color primaryColor = Color(0xFF39FF14);

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirestoreService _firestoreService = FirestoreService();

  final DirectionsService _directionsService = const DirectionsService();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};

  List<LatLng> _routePoints = const <LatLng>[];
  int _routeRequestId = 0;

  StreamSubscription<Position>? _positionStream;
  Position? _lastProcessedPosition;

  Map<String, dynamic>? userData;
  bool _isLocating = false;
  bool _locationPermissionChecked = false;
  bool _locationPermissionGranted = false;
  bool _pickupManuallySelected = false;
  bool _isSheetCollapsed = true;

  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;

  String pickupAddress = 'Detecting current location...';

  String destinationAddress = '';

  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(4.8517, 31.5825),
    zoom: 15,
  );

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkPermission();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/login',
      );

      return;
    }

    final String? phoneNumber = user.phoneNumber;

    if (phoneNumber == null) {
      if (!mounted) return;

      setState(() {});

      return;
    }

    try {
      final Map<String, dynamic>? data = await _firestoreService.getUser(
        phoneNumber,
      );

      if (!mounted) return;

      setState(() {
        userData = data;
      });
    } catch (error) {
      debugPrint(
        'Failed to load user: $error',
      );

      if (!mounted) return;

      setState(() {});
    }
  }

  Future<void> _checkPermission() async {
    final PermissionStatus status = await Permission.location.status;

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _locationPermissionChecked = true;
        _locationPermissionGranted = true;
      });

      await _getCurrentLocation();
    } else {
      setState(() {
        _locationPermissionChecked = true;
        _locationPermissionGranted = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final PermissionStatus status = await Permission.location.request();

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _locationPermissionChecked = true;
        _locationPermissionGranted = true;
      });

      await _getCurrentLocation();
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _getCurrentLocation() async {
    if (_isLocating) return;

    _isLocating = true;

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable location services.',
            ),
          ),
        );

        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await _updateLocation(
        position,
        centerCamera: true,
        resolveAddress: true,
      );

      await _positionStream?.cancel();

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 15,
        ),
      ).listen(
        (Position newPosition) {
          final Position? previousPosition = _lastProcessedPosition;

          if (previousPosition != null) {
            final double distance = Geolocator.distanceBetween(
              previousPosition.latitude,
              previousPosition.longitude,
              newPosition.latitude,
              newPosition.longitude,
            );

            if (distance < 12) return;
          }

          _updateLocation(
            newPosition,
            centerCamera: false,
            resolveAddress: false,
          );
        },
        onError: (Object error) {
          debugPrint(
            'Location stream error: $error',
          );
        },
      );
    } catch (error) {
      debugPrint(
        'Unable to obtain location: $error',
      );
    } finally {
      _isLocating = false;
    }
  }

  Future<void> _updateLocation(
    Position position, {
    required bool centerCamera,
    required bool resolveAddress,
  }) async {
    final LatLng updatedLocation = LatLng(
      position.latitude,
      position.longitude,
    );

    _lastProcessedPosition = position;

    if (!mounted) return;

    setState(() {
      _currentLocation = updatedLocation;

      if (!_pickupManuallySelected) {
        _pickupLocation = updatedLocation;
      }

      _markers
        ..removeWhere(
          (Marker marker) => marker.markerId.value == 'me',
        )
        ..add(
          Marker(
            markerId: const MarkerId('me'),
            position: updatedLocation,
            infoWindow: const InfoWindow(
              title: 'You are here',
            ),
          ),
        );
    });

    if (centerCamera && _mapController.isCompleted) {
      final GoogleMapController controller = await _mapController.future;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          updatedLocation,
          17,
        ),
      );
    }

    if (!resolveAddress) return;

    await _resolveCurrentAddress();

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _centerOnCurrentLocation() async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) {
      await _getCurrentLocation();
      return;
    }

    if (!_mapController.isCompleted) return;

    final GoogleMapController controller = await _mapController.future;

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        currentLocation,
        17,
      ),
    );
  }

  Future<void> _resolveCurrentAddress() async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) return;

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        currentLocation.latitude,
        currentLocation.longitude,
      );

      if (places.isEmpty || _pickupManuallySelected) {
        return;
      }

      final Placemark place = places.first;

      final List<String> addressParts = <String?>[
        place.street,
        place.locality,
      ]
          .whereType<String>()
          .map(
            (String part) => part.trim(),
          )
          .where(
            (String part) => part.isNotEmpty,
          )
          .toList();

      pickupAddress =
          addressParts.isEmpty ? 'Current location' : addressParts.join(', ');
    } catch (error) {
      debugPrint(
        'Unable to resolve address: $error',
      );

      if (!_pickupManuallySelected) {
        pickupAddress = 'Current location';
      }
    }
  }

  Future<void> _signOut() async {
    await SessionService.instance.signOutCurrentDevice();

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      '/login',
    );
  }

  Future<void> _openDestinationSearch({
    required bool isPickup,
  }) async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waiting for your current location...',
          ),
        ),
      );

      return;
    }

    final LatLng initialSearchLocation = isPickup
        ? _pickupLocation ?? currentLocation
        : _destinationLocation ?? currentLocation;

    final LocationSelection? result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute<LocationSelection>(
        builder: (_) => DestinationSearch(
          latitude: initialSearchLocation.latitude,
          longitude: initialSearchLocation.longitude,
          pickupAddress: pickupAddress,
          initialAddress: isPickup ? pickupAddress : destinationAddress,
          isPickup: isPickup,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final LatLng selectedLocation = LatLng(
      result.latitude,
      result.longitude,
    );

    setState(() {
      if (isPickup) {
        _pickupManuallySelected = true;
        _pickupLocation = selectedLocation;
        pickupAddress = result.displayName;

        _markers
          ..removeWhere(
            (Marker marker) => marker.markerId.value == 'pickup',
          )
          ..add(
            Marker(
              markerId: const MarkerId('pickup'),
              position: selectedLocation,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
              infoWindow: InfoWindow(
                title: 'Pickup point',
                snippet: result.address,
              ),
            ),
          );
      } else {
        _destinationLocation = selectedLocation;

        destinationAddress = result.displayName;

        _markers
          ..removeWhere(
            (Marker marker) => marker.markerId.value == 'destination',
          )
          ..add(
            Marker(
              markerId: const MarkerId(
                'destination',
              ),
              position: selectedLocation,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(
                title: 'Destination',
                snippet: result.address,
              ),
            ),
          );
      }
    });

    await _collapseOrderPanel();

    if (!mounted) return;

    if (_destinationLocation != null) {
      await _refreshRoadRoute(
        showFailureMessage: true,
      );
    } else if (_mapController.isCompleted) {
      final GoogleMapController controller = await _mapController.future;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          selectedLocation,
          16.5,
        ),
      );
    }
  }

  Future<void> _refreshRoadRoute({
    bool showFailureMessage = false,
  }) async {
    final LatLng? pickupLocation = _pickupLocation ?? _currentLocation;
    final LatLng? destinationLocation = _destinationLocation;

    if (pickupLocation == null || destinationLocation == null) {
      if (!mounted) return;

      setState(() {
        _routePoints = const <LatLng>[];
        _polylines.clear();
      });

      return;
    }

    final int requestId = ++_routeRequestId;

    try {
      final DrivingRoute route =
          await _directionsService.getShortestDrivingRoute(
        origin: pickupLocation,
        destination: destinationLocation,
      );

      if (!mounted || requestId != _routeRequestId) return;

      setState(() {
        _routePoints = route.points;
        _polylines
          ..clear()
          ..addAll(
            <Polyline>[
              Polyline(
                polylineId: const PolylineId('road-route-shadow'),
                color: Colors.black.withValues(alpha: 0.28),
                width: 15,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: false,
                zIndex: 1,
                points: route.points,
              ),
              Polyline(
                polylineId: const PolylineId('road-route-edge'),
                color: const Color(0xFF12300F),
                width: 11,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: false,
                zIndex: 2,
                points: route.points,
              ),
              Polyline(
                polylineId: const PolylineId('road-route'),
                color: primaryColor,
                width: 8,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: false,
                zIndex: 3,
                points: route.points,
              ),
              Polyline(
                polylineId: const PolylineId('road-route-highlight'),
                color: Colors.white.withValues(alpha: 0.30),
                width: 2,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                geodesic: false,
                zIndex: 4,
                points: route.points,
              ),
            ],
          );
      });

      await _fitRoutePoints(route.points);
    } catch (error) {
      debugPrint('Unable to calculate road route: $error');

      if (!mounted || requestId != _routeRequestId) return;

      setState(() {
        _routePoints = const <LatLng>[];
        _polylines.clear();
      });

      if (showFailureMessage) {
        final String message = error is DirectionsException
            ? error.message
            : 'The road route could not be loaded. Please try again.';

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                message,
              ),
            ),
          );
      }
    }
  }

  Future<void> _fitRoutePoints(List<LatLng> points) async {
    if (points.isEmpty || !_mapController.isCompleted) return;

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
        CameraUpdate.newLatLngZoom(points.first, 17),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        84,
      ),
    );
  }

  Future<void> _openBookingConfirmation(
    RideOption ride,
    PaymentMethod paymentMethod,
  ) async {
    final LatLng? pickupLocation = _pickupLocation ?? _currentLocation;

    if (pickupLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waiting for your current location...',
          ),
        ),
      );

      return;
    }

    final LatLng? destinationLocation = _destinationLocation;

    if (destinationLocation == null || destinationAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose your destination first.',
          ),
        ),
      );

      await _openDestinationSearch(
        isPickup: false,
      );

      return;
    }

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OrderConfirmationScreen(
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          pickupLocation: pickupLocation,
          destinationLocation: destinationLocation,
          initialRoutePoints: _routePoints,
          ride: ride,
          paymentMethod: paymentMethod,
        ),
      ),
    );
  }

  Future<void> _expandOrderPanel() async {
    if (!_sheetController.isAttached) return;

    await _sheetController.animateTo(
      0.68,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _collapseOrderPanel() async {
    if (!_sheetController.isAttached) return;

    await _sheetController.animateTo(
      0.20,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_locationPermissionChecked && !_locationPermissionGranted) {
      return LocationPermissionRequest(
        onRequestPermission: _requestPermission,
      );
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color mapControlColor =
        isDarkMode ? const Color(0xFF202320) : Colors.white;
    final Color mapControlIconColor =
        isDarkMode ? Colors.white : const Color(0xFF111311);

    return Scaffold(
      key: _scaffoldKey,
      drawer: CustomDrawer(
        userData: userData,
        auth: _auth,
        onSignOut: _signOut,
        onProfileUpdated: _loadUser,
        onRequestOpen: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      body: Stack(
        children: <Widget>[
          MapView(
            initialCameraPosition: _currentLocation != null
                ? CameraPosition(
                    target: _currentLocation!,
                    zoom: 17,
                  )
                : _defaultCamera,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled:
                _locationPermissionChecked && _locationPermissionGranted,
            onMapCreated: (
              GoogleMapController controller,
            ) {
              if (!_mapController.isCompleted) {
                _mapController.complete(
                  controller,
                );
              }
            },
          ),
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: mapControlColor,
              child: IconButton(
                icon: Icon(
                  Icons.menu_rounded,
                  color: mapControlIconColor,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
            ),
          ),
          Positioned(
            top: 50,
            right: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: mapControlColor,
              child: IconButton(
                icon: Icon(
                  Icons.my_location_rounded,
                  color: mapControlIconColor,
                ),
                onPressed: _centerOnCurrentLocation,
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.20,
            minChildSize: 0.20,
            maxChildSize: 0.68,
            snap: true,
            snapSizes: const <double>[
              0.20,
              0.68,
            ],
            builder: (
              BuildContext context,
              ScrollController scrollController,
            ) {
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (
                  DraggableScrollableNotification notification,
                ) {
                  final bool collapsed = notification.extent < 0.30;

                  if (collapsed != _isSheetCollapsed) {
                    setState(() {
                      _isSheetCollapsed = collapsed;
                    });
                  }

                  return false;
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(
                            0xFF101210,
                          )
                        : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 16,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: OrderPanel(
                      pickupAddress: pickupAddress,
                      destinationAddress: destinationAddress,
                      onPickupTap: () {
                        _openDestinationSearch(
                          isPickup: true,
                        );
                      },
                      onDestinationTap: () {
                        _openDestinationSearch(
                          isPickup: false,
                        );
                      },
                      onConfirmRide: _openBookingConfirmation,
                      collapsed: _isSheetCollapsed,
                      onExpand: _expandOrderPanel,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
