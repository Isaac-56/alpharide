import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/ride_option.dart';
import 'driver_search_screen.dart';
import 'home_screen.dart';

class ActiveRideGate extends StatefulWidget {
  const ActiveRideGate({super.key});

  @override
  State<ActiveRideGate> createState() => _ActiveRideGateState();
}

class _ActiveRideGateState extends State<ActiveRideGate> {
  static const Set<String> _activeStatuses = <String>{
    'requested',
    'offered',
    'accepted',
    'driver_arriving',
    'arrived',
    'in_progress',
  };

  late final Future<_ResumableRide?> _resumeRide;
  bool _resumeScheduled = false;

  @override
  void initState() {
    super.initState();
    _resumeRide = _loadActiveRide();
  }

  Future<_ResumableRide?> _loadActiveRide() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final DocumentSnapshot<Map<String, dynamic>> activeSnapshot =
        await firestore.collection('active_passenger_rides').doc(user.uid).get();
    final Map<String, dynamic>? activeData = activeSnapshot.data();
    final Object? rawRideId = activeData?['rideId'];
    if (rawRideId is! String || rawRideId.trim().isEmpty) return null;

    final String rideId = rawRideId.trim();
    final DocumentSnapshot<Map<String, dynamic>> rideSnapshot =
        await firestore.collection('rides').doc(rideId).get();
    final Map<String, dynamic>? rideData = rideSnapshot.data();
    if (!rideSnapshot.exists || rideData == null) return null;

    final String status = rideData['status']?.toString().trim().toLowerCase() ?? '';
    if (!_activeStatuses.contains(status)) return null;

    return _ResumableRide.fromFirestore(rideId: rideId, data: rideData);
  }

  void _scheduleResume(_ResumableRide ride) {
    if (_resumeScheduled) return;
    _resumeScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DriverSearchScreen(
            rideId: ride.rideId,
            pickupLocation: ride.pickup,
            pickupAddress: ride.pickupAddress,
            destinationLocation: ride.destination,
            destinationAddress: ride.destinationAddress,
            ride: ride.ride,
            paymentMethod: ride.paymentMethod,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResumableRide?>(
      future: _resumeRide,
      builder: (
        BuildContext context,
        AsyncSnapshot<_ResumableRide?> snapshot,
      ) {
        final _ResumableRide? ride = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError &&
            ride != null) {
          _scheduleResume(ride);
        }

        return const HomeScreen();
      },
    );
  }
}

class _ResumableRide {
  const _ResumableRide({
    required this.rideId,
    required this.pickup,
    required this.pickupAddress,
    required this.destination,
    required this.destinationAddress,
    required this.ride,
    required this.paymentMethod,
  });

  final String rideId;
  final LatLng pickup;
  final String pickupAddress;
  final LatLng destination;
  final String destinationAddress;
  final RideOption ride;
  final PaymentMethod paymentMethod;

  factory _ResumableRide.fromFirestore({
    required String rideId,
    required Map<String, dynamic> data,
  }) {
    final Map<String, dynamic> pickup = _requiredMap(data['pickup'], 'pickup');
    final Map<String, dynamic> destination =
        _requiredMap(data['destination'], 'destination');
    final String rideOptionId = _requiredString(
      data['rideOptionId'],
      'rideOptionId',
    );
    final int estimatedFare = _requiredInt(
      data['estimatedFare'],
      'estimatedFare',
    );
    final String payment = _requiredString(
      data['paymentMethod'],
      'paymentMethod',
    );

    final RideOption baseRide = RideOption.options.firstWhere(
      (RideOption option) => option.id == rideOptionId,
      orElse: () =>
          throw const FormatException('Unsupported active ride option.'),
    );

    final PaymentMethod paymentMethod = switch (payment) {
      'cash' => PaymentMethod.cash,
      'card' => PaymentMethod.card,
      'wallet' => PaymentMethod.wallet,
      _ => throw const FormatException(
          'Unsupported active ride payment method.',
        ),
    };

    return _ResumableRide(
      rideId: rideId,
      pickup: LatLng(
        _requiredDouble(pickup['latitude'], 'pickup.latitude'),
        _requiredDouble(pickup['longitude'], 'pickup.longitude'),
      ),
      pickupAddress: _requiredString(pickup['address'], 'pickup.address'),
      destination: LatLng(
        _requiredDouble(destination['latitude'], 'destination.latitude'),
        _requiredDouble(destination['longitude'], 'destination.longitude'),
      ),
      destinationAddress: _requiredString(
        destination['address'],
        'destination.address',
      ),
      ride: baseRide.withEstimatedFare(estimatedFare),
      paymentMethod: paymentMethod,
    );
  }
}

Map<String, dynamic> _requiredMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Active ride field "$field" is invalid.');
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Active ride field "$field" is missing.');
  }
  return value.trim();
}

int _requiredInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Active ride field "$field" is invalid.');
}

double _requiredDouble(Object? value, String field) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Active ride field "$field" is invalid.');
}
