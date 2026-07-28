import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  static const Color secondaryTextColor = Color(0xFF6B6B6B);

  GoogleMapController? _mapController;

  late LatLng _selectedLocation;
  late String _selectedAddress;

  bool _isResolvingAddress = false;
  bool _isLocatingUser = false;
  int _addressRequestId = 0;

  @override
  void initState() {
    super.initState();

    _selectedLocation = widget.initialLocation;
    _selectedAddress = widget.initialAddress.trim().isEmpty
        ? 'Finding this address...'
        : widget.initialAddress.trim();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAddress(_selectedLocation);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress(LatLng location) async {
    final int requestId = ++_addressRequestId;

    if (mounted) {
      setState(() {
        _isResolvingAddress = true;
      });
    }

    try {
      final List<Placemark> places = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (!mounted || requestId != _addressRequestId) return;

      final String address =
          places.isEmpty ? 'Pinned location' : _formatPlacemark(places.first);

      setState(() {
        _selectedAddress = address;
        _isResolvingAddress = false;
      });
    } catch (error) {
      debugPrint('Unable to resolve selected location: $error');

      if (!mounted || requestId != _addressRequestId) return;

      setState(() {
        _selectedAddress = 'Pinned location';
        _isResolvingAddress = false;
      });
    }
  }

  String _formatPlacemark(Placemark place) {
    final List<String> parts = [
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

    final List<String> uniqueParts = [];

    for (final String part in parts) {
      if (!uniqueParts.contains(part)) {
        uniqueParts.add(part);
      }
    }

    return uniqueParts.isEmpty
        ? 'Pinned location'
        : uniqueParts.take(3).join(', ');
  }

  void _onCameraMove(CameraPosition position) {
    _selectedLocation = position.target;
  }

  void _onCameraIdle() {
    _resolveAddress(_selectedLocation);
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isLocatingUser) return;

    setState(() {
      _isLocatingUser = true;
    });

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final LatLng currentLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      _selectedLocation = currentLocation;

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          currentLocation,
          17,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to get your current location.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLocatingUser = false;
        });
      }
    }
  }

  Future<void> _moveToTappedPoint(LatLng point) async {
    _selectedLocation = point;

    await _mapController?.animateCamera(
      CameraUpdate.newLatLng(point),
    );
  }

  void _confirmLocation() {
    if (_isResolvingAddress) return;

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

  @override
  Widget build(BuildContext context) {
    final String pointLabel =
        widget.isPickup ? 'Pickup point' : 'Destination point';

    final String buttonLabel =
        widget.isPickup ? 'Confirm pickup point' : 'Confirm destination';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 17,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
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

          // Fixed center pickup marker
          Center(
            child: IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -27),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
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
                        boxShadow: const [
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
                    Container(
                      width: 3,
                      height: 18,
                      color: textColor,
                    ),
                    Container(
                      width: 10,
                      height: 4,
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
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
                  color: Colors.white,
                  elevation: 3,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Current-location tracker
          Positioned(
            right: 16,
            bottom: 218,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                elevation: 3,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: _isLocatingUser ? null : _moveToCurrentLocation,
                  icon: _isLocatingUser
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: textColor,
                          ),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: textColor,
                        ),
                ),
              ),
            ),
          ),

          // Selected address and confirmation
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
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
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: textColor,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pointLabel,
                                style: const TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isResolvingAddress
                                    ? 'Finding this address...'
                                    : _selectedAddress,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textColor,
                                  fontSize: 15.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
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
                        onPressed:
                            _isResolvingAddress ? null : _confirmLocation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: textColor,
                          disabledBackgroundColor:
                              primaryColor.withValues(alpha: 0.45),
                          disabledForegroundColor:
                              textColor.withValues(alpha: 0.55),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(
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
