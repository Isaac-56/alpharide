import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/driver_location_model.dart';
import 'driver_location_service.dart';

class LiveDriverMarkerPolicy {
  const LiveDriverMarkerPolicy._();

  static const Map<String, String> markerAssets = <String, String>{
    'standard': 'assets/images/vehicles/alpha_driver_top.webp',
    'boda': 'assets/images/vehicles/alpha_boda_top.webp',
    'rickshaw': 'assets/images/vehicles/alpha_rickshaw_top.webp',
  };

  static String normalizedVehicleType(String vehicleType) {
    final String normalized = vehicleType.trim().toLowerCase();

    if (normalized.contains('boda') || normalized.contains('motor')) {
      return 'boda';
    }
    if (normalized.contains('rickshaw') ||
        normalized.contains('tuk') ||
        normalized.contains('three')) {
      return 'rickshaw';
    }

    return 'standard';
  }

  static String markerAssetForVehicle(String vehicleType) {
    return markerAssets[normalizedVehicleType(vehicleType)] ??
        markerAssets['standard']!;
  }

  static double normalizedHeading(double value) {
    return ((value % 360) + 360) % 360;
  }

  static double interpolatedHeading(
    double start,
    double end,
    double progress,
  ) {
    final double difference = ((end - start + 540) % 360) - 180;
    return normalizedHeading(start + (difference * progress));
  }
}

class LiveDriverMarkerController extends ChangeNotifier {
  static const Duration movementDuration = Duration(milliseconds: 1600);
  static const Duration frameDuration = Duration(milliseconds: 33);

  final DriverLocationService _locationService;
  final double radiusKilometers;

  StreamSubscription<List<DriverLocationModel>>? _subscription;
  Timer? _movementTimer;
  final Map<String, BitmapDescriptor> _markerIcons =
      <String, BitmapDescriptor>{};
  List<DriverLocationModel> _latestDrivers = const <DriverLocationModel>[];
  final Map<String, _VisualDriver> _visualDrivers = <String, _VisualDriver>{};

  LatLng _center;
  String? _driverIdFilter;
  bool _started = false;
  bool _disposed = false;

  LiveDriverMarkerController({
    required LatLng center,
    this.radiusKilometers = 12,
    DriverLocationService? locationService,
  })  : _center = center,
        _locationService = locationService ?? DriverLocationService();

  Set<Marker> get markers {
    final BitmapDescriptor? standardIcon = _markerIcons['standard'];
    if (standardIcon == null) return const <Marker>{};

    return _visualDrivers.values.map((_VisualDriver driver) {
      final BitmapDescriptor icon =
          _markerIcons[driver.vehicleType] ?? standardIcon;

      return Marker(
        markerId: MarkerId('live-driver-${driver.driverId}'),
        position: driver.position,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: driver.heading,
        alpha: driver.alpha.clamp(0.0, 1.0).toDouble(),
        infoWindow: InfoWindow(
          title: _driverIdFilter == null
              ? 'Alpha driver nearby'
              : 'Your Alpha driver',
        ),
      );
    }).toSet();
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _subscription = _locationService.watchOnlineDrivers().listen(
      (List<DriverLocationModel> drivers) {
        _latestDrivers = drivers;
        _applyLocations(drivers);
      },
      onError: (Object error) {
        debugPrint('Live driver location stream failed: $error');
      },
    );

    await _loadMarkerIcons();
  }

  void updateCenter(LatLng center) {
    if (_samePoint(_center, center)) return;
    _center = center;
    _applyLocations(_latestDrivers);
  }

  void showOnlyDriver(String? driverId) {
    final String? normalized = driverId?.trim();
    final String? nextFilter = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_driverIdFilter == nextFilter) return;

    _driverIdFilter = nextFilter;
    _applyLocations(_latestDrivers);
  }

  Future<void> _loadMarkerIcons() async {
    for (final MapEntry<String, String> entry
        in LiveDriverMarkerPolicy.markerAssets.entries) {
      try {
        _markerIcons[entry.key] = await _loadMarkerIcon(entry.value);
      } catch (error) {
        debugPrint(
          'Unable to load the ${entry.key} top-view driver marker: $error',
        );
      }
    }

    final BitmapDescriptor standardIcon = _markerIcons['standard'] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    _markerIcons['standard'] = standardIcon;
    _markerIcons.putIfAbsent('boda', () => standardIcon);
    _markerIcons.putIfAbsent('rickshaw', () => standardIcon);

    if (_disposed) return;
    _applyLocations(_latestDrivers);
  }

  Future<BitmapDescriptor> _loadMarkerIcon(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 96,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();

    try {
      final ByteData? bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) {
        throw StateError('Unable to decode $assetPath.');
      }

      return BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        ),
      );
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  void _applyLocations(List<DriverLocationModel> locations) {
    if (_disposed || _markerIcons.isEmpty) return;

    final List<DriverLocationModel> visibleDrivers = locations.where(
      (DriverLocationModel driver) {
        final String? filter = _driverIdFilter;
        if (filter != null) {
          return driver.driverId == filter;
        }

        final double distanceMeters = Geolocator.distanceBetween(
          _center.latitude,
          _center.longitude,
          driver.latitude,
          driver.longitude,
        );

        return distanceMeters <= radiusKilometers * 1000;
      },
    ).toList(growable: false);

    final Set<String> incomingIds = visibleDrivers
        .map((DriverLocationModel driver) => driver.driverId)
        .toSet();
    bool animationNeeded = false;

    for (final _VisualDriver driver in _visualDrivers.values) {
      if (!incomingIds.contains(driver.driverId) &&
          (!driver.removeWhenInvisible || driver.targetAlpha != 0)) {
        driver
          ..startPosition = driver.position
          ..targetPosition = driver.position
          ..startHeading = driver.heading
          ..targetHeading = driver.heading
          ..startAlpha = driver.alpha
          ..targetAlpha = 0
          ..removeWhenInvisible = true;
        animationNeeded = true;
      }
    }

    for (final DriverLocationModel driver in visibleDrivers) {
      final LatLng destination = LatLng(
        driver.latitude,
        driver.longitude,
      );
      final _VisualDriver? current = _visualDrivers[driver.driverId];

      if (current == null) {
        _visualDrivers[driver.driverId] = _VisualDriver(
          driverId: driver.driverId,
          vehicleType: LiveDriverMarkerPolicy.normalizedVehicleType(
            driver.vehicleType,
          ),
          position: destination,
          startPosition: destination,
          targetPosition: destination,
          heading: LiveDriverMarkerPolicy.normalizedHeading(
            driver.heading ?? 0,
          ),
          startHeading: LiveDriverMarkerPolicy.normalizedHeading(
            driver.heading ?? 0,
          ),
          targetHeading: LiveDriverMarkerPolicy.normalizedHeading(
            driver.heading ?? 0,
          ),
          alpha: 0,
          startAlpha: 0,
          targetAlpha: 1,
          removeWhenInvisible: false,
        );
        animationNeeded = true;
        continue;
      }

      final String vehicleType =
          LiveDriverMarkerPolicy.normalizedVehicleType(driver.vehicleType);
      final double targetHeading = LiveDriverMarkerPolicy.normalizedHeading(
        driver.heading ??
            (_samePoint(current.position, destination)
                ? current.heading
                : _bearingBetween(current.position, destination)),
      );
      final bool targetUnchanged =
          current.vehicleType == vehicleType &&
          _samePoint(current.targetPosition, destination) &&
          _sameHeading(current.targetHeading, targetHeading) &&
          current.targetAlpha == 1 &&
          !current.removeWhenInvisible;
      if (targetUnchanged) continue;

      current
        ..vehicleType = vehicleType
        ..startPosition = current.position
        ..targetPosition = destination
        ..startHeading = current.heading
        ..targetHeading = targetHeading
        ..startAlpha = current.alpha
        ..targetAlpha = 1
        ..removeWhenInvisible = false;
      animationNeeded = true;
    }

    if (animationNeeded) {
      _startMovementAnimation();
    }
  }

  void _startMovementAnimation() {
    _movementTimer?.cancel();

    if (_visualDrivers.isEmpty) {
      _notifySafely();
      return;
    }

    final Stopwatch stopwatch = Stopwatch()..start();

    _movementTimer = Timer.periodic(
      frameDuration,
      (Timer timer) {
        if (_disposed) {
          timer.cancel();
          return;
        }

        final double rawProgress =
            stopwatch.elapsedMilliseconds / movementDuration.inMilliseconds;
        final double progress = rawProgress.clamp(0.0, 1.0).toDouble();
        final double eased = Curves.easeInOutCubic.transform(progress);

        for (final _VisualDriver driver in _visualDrivers.values) {
          driver
            ..position = LatLng(
              _lerp(
                driver.startPosition.latitude,
                driver.targetPosition.latitude,
                eased,
              ),
              _lerp(
                driver.startPosition.longitude,
                driver.targetPosition.longitude,
                eased,
              ),
            )
            ..heading = LiveDriverMarkerPolicy.interpolatedHeading(
              driver.startHeading,
              driver.targetHeading,
              eased,
            )
            ..alpha = _lerp(
              driver.startAlpha,
              driver.targetAlpha,
              eased,
            );
        }

        _notifySafely();

        if (progress >= 1) {
          _visualDrivers.removeWhere(
            (String driverId, _VisualDriver driver) =>
                driver.removeWhenInvisible && driver.alpha <= 0.001,
          );
          _notifySafely();
          stopwatch.stop();
          timer.cancel();
        }
      },
    );
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  static bool _samePoint(LatLng first, LatLng second) {
    return (first.latitude - second.latitude).abs() < 0.00001 &&
        (first.longitude - second.longitude).abs() < 0.00001;
  }

  static bool _sameHeading(double first, double second) {
    final double difference = ((first - second + 540) % 360) - 180;
    return difference.abs() < 0.1;
  }

  static double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }

  static double _bearingBetween(LatLng start, LatLng end) {
    if (_samePoint(start, end)) return 0;

    final double startLatitude = start.latitude * math.pi / 180;
    final double endLatitude = end.latitude * math.pi / 180;
    final double longitudeDifference =
        (end.longitude - start.longitude) * math.pi / 180;

    final double y = math.sin(longitudeDifference) * math.cos(endLatitude);
    final double x = math.cos(startLatitude) * math.sin(endLatitude) -
        math.sin(startLatitude) *
            math.cos(endLatitude) *
            math.cos(longitudeDifference);

    return LiveDriverMarkerPolicy.normalizedHeading(
      math.atan2(y, x) * 180 / math.pi,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _movementTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

class _VisualDriver {
  final String driverId;
  String vehicleType;
  LatLng position;
  LatLng startPosition;
  LatLng targetPosition;
  double heading;
  double startHeading;
  double targetHeading;
  double alpha;
  double startAlpha;
  double targetAlpha;
  bool removeWhenInvisible;

  _VisualDriver({
    required this.driverId,
    required this.vehicleType,
    required this.position,
    required this.startPosition,
    required this.targetPosition,
    required this.heading,
    required this.startHeading,
    required this.targetHeading,
    required this.alpha,
    required this.startAlpha,
    required this.targetAlpha,
    required this.removeWhenInvisible,
  });
}
