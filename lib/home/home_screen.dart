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

  final FirestoreService _firestoreService =
  FirestoreService();

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  final Completer<GoogleMapController>
  _mapController =
  Completer<GoogleMapController>();

  StreamSubscription<Position>? _positionStream;

  final Set<Marker> _markers = {};

  final Set<Polyline> _polylines = {};

  Map<String, dynamic>? userData;

  bool _isLoading = true;

  bool _locationPermissionGranted = false;

  bool _pickupManuallySelected = false;

  LatLng? _currentLocation;

  String pickupAddress =
      "Detecting current location...";

  String destinationAddress = "";

  double _sheetSize = 0.13;

  static const CameraPosition _defaultCamera =
  CameraPosition(
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
    User? user = _auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        "/login",
      );

      return;
    }

    final data =
    await _firestoreService.getUser(
      user.phoneNumber!,
    );

    if (!mounted) return;

    setState(() {
      userData = data;
      _isLoading = false;
    });
  }

  Future<void> _checkPermission() async {
    final status =
    await Permission.location.status;

    if (status.isGranted) {
      _locationPermissionGranted = true;

      setState(() {});

      _getCurrentLocation();
    } else {
      setState(() {
        _locationPermissionGranted = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final status =
    await Permission.location.request();

    if (status.isGranted) {
      setState(() {
        _locationPermissionGranted = true;
      });

      _getCurrentLocation();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position =
      await Geolocator.getCurrentPosition(
        desiredAccuracy:
        LocationAccuracy.high,
      );

      _updateLocation(position);

      _positionStream?.cancel();

      _positionStream =
          Geolocator.getPositionStream(
            locationSettings:
            const LocationSettings(
              accuracy:
              LocationAccuracy.best,
              distanceFilter: 5,
            ),
          ).listen(_updateLocation);
    } catch (e) {
      debugPrint(e.toString());
    }
  }  Future<void> _updateLocation(
      Position position) async {
    _currentLocation = LatLng(
      position.latitude,
      position.longitude,
    );

    // _markers.clear();

    _markers.add(
      Marker(
        markerId: const MarkerId("me"),
        position: _currentLocation!,
        infoWindow: const InfoWindow(
          title: "You are here",
        ),
      ),
    );

    if (_mapController.isCompleted) {
      final controller =
      await _mapController.future;

      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          _currentLocation!,
          17,
        ),
      );
    }

    await _resolveAddress();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _resolveAddress() async {
    if (_currentLocation == null) return;

    try {
      final places =
      await placemarkFromCoordinates(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
      );

      if (places.isNotEmpty) {
        final place = places.first;

        pickupAddress =
        "${place.street ?? ""}, ${place.locality ?? ""}";
      }
    } catch (_) {}
  }

  Future<void> _signOut() async {
    await _auth.signOut();

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      "/login",
    );
  }

  Future<void> _openDestinationSearch({
    required bool isPickup,
  }) async {
    final PredictionModel? result =
    await Navigator.push<PredictionModel>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationSearch(
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
          isPickup: isPickup,
        )
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (isPickup) {
        pickupAddress = result.mainText;
      } else {
        destinationAddress = result.mainText;
      }
    });

    // Next Part:
    // Use result.placeId to obtain latitude/longitude.
  }

  Widget _collapsedCard() {
    return SizedBox(
      height: 90,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),        child: Row(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius:
              BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.local_taxi,
              color: Colors.green,
            ),
          ),

          const SizedBox(width: 15),

          const Expanded(
            child: Text(
              "Order Now",
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
  }  @override
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

          /// Google Map
          MapView(
            initialCameraPosition:
            _currentLocation != null
                ? CameraPosition(
              target: _currentLocation!,
              zoom: 17,
            )
                : _defaultCamera,

            markers: _markers,

            polylines: _polylines,

            onMapCreated: (controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
          ),

          /// Menu Button
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  _scaffoldKey.currentState
                      ?.openDrawer();
                },
              ),
            ),
          ),

          /// GPS Button
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

          /// Bottom Draggable Sheet
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
                context,
                scrollController,
                ) {
              return NotificationListener<
                  DraggableScrollableNotification>(
                onNotification:
                    (notification) {

                  setState(() {
                    _sheetSize =
                        notification.extent;
                  });

                  return true;
                },

                child: Container(
                  decoration:
                  const BoxDecoration(
                    color: Colors.white,

                    borderRadius:
                    BorderRadius.vertical(
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
                    controller:
                    scrollController,                    child: _sheetSize < 0.20
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
                      _openDestinationSearch(isPickup: false,
                      );
                    },

                    onConfirmPickup: () {
                      if (_currentLocation == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Waiting for current location...",
                            ),
                          ),
                        );
                        return;
                      }

                      // Part 3
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