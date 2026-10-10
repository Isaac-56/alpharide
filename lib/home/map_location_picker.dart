import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../account/account_ui.dart';
import '../models/location_selection.dart';

class MapLocationPicker extends StatefulWidget {
  final LatLng initialLocation;
  final String initialAddress;
  final bool isPickup;

  const MapLocationPicker({
    super.key,
    required this.initialLocation,
    required this.initialAddress,
    required this.isPickup,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color errorColor = Color(0xFFD83A3A);

  GoogleMapController? _mapController;
  Timer? _addressDebounce;

  late LatLng _selectedLocation;
  late String _selectedAddress;

  bool _isCameraMoving = false;
  bool _isResolvingAddress = false;
  bool _isLocatingUser = false;
  bool _isConfirming = false;

  int _addressRequestId = 0;

  bool get _canConfirm =>
      !_isCameraMoving &&
      !_isResolvingAddress &&
      !_isLocatingUser &&
      !_isConfirming;

  @override
  void initState() {
    super.initState();

    _selectedLocation = widget.initialLocation;

    final String initialAddress = widget.initialAddress.trim();

    _selectedAddress =
        initialAddress.isEmpty ? 'Finding this address...' : initialAddress;

    if (initialAddress.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resolveAddress(_selectedLocation);
        }
      });
    }
  }

  @override
  void dispose() {
    _addressRequestId++;
    _addressDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: isError ? errorColor : textColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _resolveAddress(
    LatLng location,
  ) async {
    final int requestId = ++_addressRequestId;

    if (!mounted) return;

    setState(() {
      _isResolvingAddress = true;
    });

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (!mounted || requestId != _addressRequestId) {
        return;
      }

      final String address =
          places.isEmpty ? 'Pinned location' : _formatPlacemark(places.first);

      setState(() {
        _selectedAddress = address;
        _isResolvingAddress = false;
      });
    } catch (error) {
      debugPrint(
        'Unable to resolve selected location: $error',
      );

      if (!mounted || requestId != _addressRequestId) {
        return;
      }

      setState(() {
        _selectedAddress = 'Pinned location';
        _isResolvingAddress = false;
      });
    }
  }

  String _formatPlacemark(Placemark place) {
    final List<String> parts = <String?>[
      place.name,
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ]
        .whereType<String>()
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList();

    final List<String> uniqueParts = <String>[];
    final Set<String> normalizedParts = <String>{};

    for (final String part in parts) {
      final String normalized = part.toLowerCase();

      if (normalizedParts.add(normalized)) {
        uniqueParts.add(part);
      }
    }

    return uniqueParts.isEmpty
        ? 'Pinned location'
        : uniqueParts.take(3).join(', ');
  }

  void _onMapCreated(
    GoogleMapController controller,
  ) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    _selectedLocation = position.target;
    _addressDebounce?.cancel();

    if (_isCameraMoving) return;

    _addressRequestId++;

    setState(() {
      _isCameraMoving = true;
      _isResolvingAddress = true;
    });
  }

  void _onCameraIdle() {
    if (!mounted) return;

    setState(() {
      _isCameraMoving = false;
    });

    final LatLng location = _selectedLocation;

    _addressDebounce?.cancel();

    _addressDebounce = Timer(
      const Duration(milliseconds: 320),
      () => _resolveAddress(location),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      _showMessage(
        'Turn on location services to find your position.',
        isError: true,
      );

      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showMessage(
        'Location permission is required to find your position.',
        isError: true,
      );

      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showMessage(
        'Location permission is disabled. Enable it in phone settings.',
        isError: true,
      );

      return false;
    }

    return true;
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isLocatingUser || _isConfirming) return;

    setState(() {
      _isLocatingUser = true;
    });

    try {
      final bool hasPermission = await _ensureLocationPermission();

      if (!hasPermission || !mounted) return;

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;

      final LatLng currentLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      _selectedLocation = currentLocation;

      final GoogleMapController? controller = _mapController;

      if (controller != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            currentLocation,
            17,
          ),
        );
      } else {
        await _resolveAddress(currentLocation);
      }
    } on TimeoutException {
      _showMessage(
        'Location is taking too long. Please try again.',
        isError: true,
      );
    } catch (error) {
      debugPrint(
        'Unable to get current location: $error',
      );

      _showMessage(
        'Unable to get your current location.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLocatingUser = false;
        });
      }
    }
  }

  Future<void> _moveToTappedPoint(
    LatLng point,
  ) async {
    if (_isLocatingUser || _isConfirming) return;

    _selectedLocation = point;

    final GoogleMapController? controller = _mapController;

    if (controller == null) {
      await _resolveAddress(point);
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLng(point),
      );
    } catch (error) {
      debugPrint(
        'Unable to move map camera: $error',
      );

      if (mounted) {
        await _resolveAddress(point);
      }
    }
  }

  void _confirmLocation() {
    if (!_canConfirm) return;

    setState(() {
      _isConfirming = true;
    });

    Navigator.pop(
      context,
      LocationSelection(
        latitude: _selectedLocation.latitude,
        longitude: _selectedLocation.longitude,
        address: _selectedAddress,
        name: _selectedAddress,
      ),
    );
  }

  void _closePicker() {
    if (_isConfirming) return;

    _addressDebounce?.cancel();
    _addressRequestId++;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final String pointLabel =
        widget.isPickup ? 'Pickup point' : 'Destination point';

    final String buttonLabel =
        widget.isPickup ? 'Confirm pickup point' : 'Confirm destination';

    final double bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final Color pageBackground = AlphaColors.background(context);
    final Color surface = AlphaColors.surface(context);
    final Color foreground = AlphaColors.text(context);
    final Color muted = AlphaColors.muted(context);

    return Scaffold(
      backgroundColor: pageBackground,
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 17,
            ),
            onMapCreated: _onMapCreated,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            onTap: _moveToTappedPoint,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            buildingsEnabled: true,
          ),

          // Fixed center marker
          Center(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Transform.translate(
                  offset: const Offset(0, -27),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AnimatedScale(
                        scale: _isCameraMoving ? 1.08 : 1,
                        duration: const Duration(
                          milliseconds: 160,
                        ),
                        curve: Curves.easeOut,
                        child: Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 4,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: textColor,
                            size: 30,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(
                          milliseconds: 160,
                        ),
                        width: 3,
                        height: _isCameraMoving ? 24 : 18,
                        color: textColor,
                      ),
                      Container(
                        width: 10,
                        height: 4,
                        decoration: BoxDecoration(
                          color: textColor.withValues(
                            alpha: 0.25,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: surface,
                  elevation: 3,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: 'Close map',
                    onPressed: _isConfirming ? null : _closePicker,
                    icon: Icon(
                      Icons.close_rounded,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Current-location tracker
          Positioned(
            right: 16,
            bottom: 218 + bottomSafeArea,
            child: Material(
              color: surface,
              elevation: 3,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: 'Use current location',
                onPressed: _isLocatingUser || _isConfirming
                    ? null
                    : _moveToCurrentLocation,
                icon: _isLocatingUser
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: textColor,
                        ),
                      )
                    : Icon(
                        Icons.my_location_rounded,
                        color: foreground,
                      ),
              ),
            ),
          ),

          // Selected address panel
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                24,
                20,
                24,
                16,
              ),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 24,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                          ),
                          child: Icon(
                            Icons.location_on_outlined,
                            color: foreground,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                pointLabel,
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedSwitcher(
                                duration: const Duration(
                                  milliseconds: 180,
                                ),
                                child: Text(
                                  _isResolvingAddress || _isCameraMoving
                                      ? 'Finding this address...'
                                      : _selectedAddress,
                                  key: ValueKey<String>(
                                    _isResolvingAddress || _isCameraMoving
                                        ? 'resolving-address'
                                        : _selectedAddress,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 15.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _canConfirm ? _confirmLocation : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: textColor,
                          disabledBackgroundColor: primaryColor.withValues(
                            alpha: 0.45,
                          ),
                          disabledForegroundColor: textColor.withValues(
                            alpha: 0.55,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                        ),
                        icon: _isResolvingAddress || _isCameraMoving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: textColor,
                                ),
                              )
                            : const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 21,
                              ),
                        label: Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
