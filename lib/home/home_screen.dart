import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/location_selection.dart';
import '../models/ride_option.dart';
import '../services/firestore_service.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/loading_screen.dart';
import '../widgets/location_permission_request.dart';
import 'destination_search.dart';
import 'map_view.dart';
import 'order_confirmation_screen.dart';
import 'order_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color primaryColor = Color(0xFF39FF14);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  StreamSubscription<Position>? _positionStream;

  Map<String, dynamic>? userData;

  bool _isLoading = true;
  bool _locationPermissionGranted = false;
  bool _pickupManuallySelected = false;

  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;

  String pickupAddress = 'Detecting current location...';
  String destinationAddress = '';

  double _sheetSize = 0.13;

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
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final String? phoneNumber = user.phoneNumber;

    if (phoneNumber == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final Map<String, dynamic>? data = await _firestoreService.getUser(
        phoneNumber,
      );

      if (!mounted) return;

      setState(() {
        userData = data;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Failed to load user: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkPermission() async {
    final PermissionStatus status = await Permission.location.status;

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _locationPermissionGranted = true;
      });

      await _getCurrentLocation();
    } else {
      setState(() {
        _locationPermissionGranted = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final PermissionStatus status = await Permission.location.request();

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _locationPermissionGranted = true;
      });

      await _getCurrentLocation();
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services.'),
          ),
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await _updateLocation(position);
      await _positionStream?.cancel();

      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen(
        (Position newPosition) {
          _updateLocation(newPosition);
        },
        onError: (Object error) {
          debugPrint('Location stream error: $error');
        },
      );
    } catch (error) {
      debugPrint('Unable to obtain location: $error');
    }
  }

  Future<void> _updateLocation(Position position) async {
    final LatLng updatedLocation = LatLng(
      position.latitude,
      position.longitude,
    );

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

    if (_mapController.isCompleted) {
      final GoogleMapController controller = await _mapController.future;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(updatedLocation, 17),
      );
    }

    await _resolveCurrentAddress();

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resolveCurrentAddress() async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) return;

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        currentLocation.latitude,
        currentLocation.longitude,
      );

      if (places.isEmpty || _pickupManuallySelected) return;

      final Placemark place = places.first;

      final List<String> addressParts = [
        place.street,
        place.locality,
      ]
          .whereType<String>()
          .map((String part) => part.trim())
          .where((String part) => part.isNotEmpty)
          .toList();

      pickupAddress =
          addressParts.isEmpty ? 'Current location' : addressParts.join(', ');
    } catch (error) {
      debugPrint('Unable to resolve address: $error');

      if (!_pickupManuallySelected) {
        pickupAddress = 'Current location';
      }
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _openDestinationSearch({
    required bool isPickup,
  }) async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for your current location...'),
        ),
      );
      return;
    }

    final LatLng initialSearchLocation = isPickup
        ? _pickupLocation ?? currentLocation
        : _destinationLocation ?? currentLocation;

    final LocationSelection? result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute(
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
              markerId: const MarkerId('destination'),
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

    if (_mapController.isCompleted) {
      final GoogleMapController controller = await _mapController.future;

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(selectedLocation, 16.5),
      );
    }
  }

  Future<void> _openBookingConfirmation(
    RideOption ride,
    PaymentMethod paymentMethod,
  ) async {
    final LatLng? pickupLocation = _pickupLocation ?? _currentLocation;

    if (pickupLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for your current location...'),
        ),
      );
      return;
    }

    final LatLng? destinationLocation = _destinationLocation;

    if (destinationLocation == null || destinationAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose your destination first.'),
        ),
      );

      await _openDestinationSearch(isPickup: false);
      return;
    }

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OrderConfirmationScreen(
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          pickupLocation: pickupLocation,
          destinationLocation: destinationLocation,
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

  Widget _collapsedCard() {
    final bool isDarkMode =
        Theme.of(context).brightness == Brightness.dark;

    final Color panelTextColor =
        isDarkMode ? Colors.white : const Color(0xFF111311);

    final Color secondaryTextColor = isDarkMode
        ? const Color(0xFF9A9F9A)
        : const Color(0xFF687068);

    final Color controlColor = isDarkMode
        ? const Color(0xFF242724)
        : const Color(0xFFF0F3F0);

    return SizedBox(
      height: 90,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 19,
          vertical: 11,
        ),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.28),
                ),
              ),
              child: Image.asset(
                'assets/images/vehicles/alpha_standard.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order now',
                    style: TextStyle(
                      color: panelTextColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Choose a ride that fits you',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: controlColor,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _expandOrderPanel,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: panelTextColor,
                  ),
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
    if (_isLoading) {
      return const LoadingScreen();
    }

    if (!_locationPermissionGranted) {
      return LocationPermissionRequest(
        onRequestPermission: _requestPermission,
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: CustomDrawer(
        userData: userData,
        auth: _auth,
        onSignOut: _signOut,
      ),
      body: Stack(
        children: [
          MapView(
            initialCameraPosition: _currentLocation != null
                ? CameraPosition(
                    target: _currentLocation!,
                    zoom: 17,
                  )
                : _defaultCamera,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
          ),
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.menu_rounded),
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
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.my_location_rounded),
                onPressed: _getCurrentLocation,
              ),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.13,
            minChildSize: 0.13,
            maxChildSize: 0.68,
            snap: true,
            snapSizes: const [
              0.13,
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
                  if ((_sheetSize - notification.extent).abs() > 0.001) {
                    setState(() {
                      _sheetSize = notification.extent;
                    });
                  }

                  return false;
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF101210)
                        : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: const [
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
                    child: _sheetSize < 0.20
                        ? _collapsedCard()
                        : OrderPanel(
                            pickupAddress: pickupAddress,
                            destinationAddress: destinationAddress,
                            onPickupTap: () {
                              _openDestinationSearch(isPickup: true);
                            },
                            onDestinationTap: () {
                              _openDestinationSearch(isPickup: false);
                            },
                            onConfirmRide: _openBookingConfirmation,
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