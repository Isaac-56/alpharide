import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/prediction_model.dart';
import '../services/firestore_service.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/loading_screen.dart';
import '../widgets/location_permission_request.dart';
import 'destination_search.dart';
import 'map_view.dart';
import 'order_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirestoreService _firestoreService = FirestoreService();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();

  StreamSubscription<Position>? _positionStream;

  final Set<Marker> _markers = {};

  final Set<Polyline> _polylines = {};

  Map<String, dynamic>? userData;

  bool _isLoading = true;

  bool _locationPermissionGranted = false;

  LatLng? _currentLocation;

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
          debugPrint(
            'Location stream error: $error',
          );
        },
      );
    } catch (error) {
      debugPrint(
        'Unable to obtain location: $error',
      );
    }
  }

  Future<void> _updateLocation(
    Position position,
  ) async {
    final LatLng updatedLocation = LatLng(
      position.latitude,
      position.longitude,
    );

    _currentLocation = updatedLocation;

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
        CameraUpdate.newLatLngZoom(
          updatedLocation,
          17,
        ),
      );
    }

    await _resolveAddress();

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _resolveAddress() async {
    final LatLng? currentLocation = _currentLocation;

    if (currentLocation == null) return;

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        currentLocation.latitude,
        currentLocation.longitude,
      );

      if (places.isEmpty) return;

      final Placemark place = places.first;

      final List<String> addressParts = [
        place.street,
        place.locality,
      ]
          .whereType<String>()
          .where(
            (String part) => part.trim().isNotEmpty,
          )
          .toList();

      pickupAddress =
          addressParts.isEmpty ? 'Current location' : addressParts.join(', ');
    } catch (error) {
      debugPrint(
        'Unable to resolve address: $error',
      );

      pickupAddress = 'Current location';
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();

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

    final PredictionModel? result = await Navigator.push<PredictionModel>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationSearch(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
          isPickup: isPickup,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      if (isPickup) {
        pickupAddress = result.mainText;
      } else {
        destinationAddress = result.mainText;
      }
    });
  }

  Widget _collapsedCard() {
    return SizedBox(
      height: 90,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Text(
                'Order Now',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_up,
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

          // Menu button
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
            ),
          ),

          // Current location button
          Positioned(
            top: 50,
            right: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(
                  Icons.my_location,
                ),
                onPressed: _getCurrentLocation,
              ),
            ),
          ),

          // Bottom ride-ordering panel
          DraggableScrollableSheet(
            initialChildSize: 0.13,
            minChildSize: 0.13,
            maxChildSize: 0.60,
            snap: true,
            snapSizes: const [
              0.13,
              0.60,
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: _sheetSize < 0.20
                        ? _collapsedCard()
                        : OrderPanel(
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
                            onConfirmPickup: () {
                              if (_currentLocation == null) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Waiting for current location...',
                                    ),
                                  ),
                                );

                                return;
                              }

                              // Add ride-confirmation
                              // functionality here.
                            },
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
