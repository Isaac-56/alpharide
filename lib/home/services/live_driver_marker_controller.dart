import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/driver_location_model.dart';
import 'driver_location_service.dart';

class LiveDriverMarkerController extends ChangeNotifier {
  static const String markerAsset =
      'assets/images/vehicles/alpha_driver_top.png';
  static const Duration movementDuration = Duration(milliseconds: 950);
  static const Duration frameDuration = Duration(milliseconds: 33);

  final DriverLocationService _locationService;
  final double radiusKilometers;

  StreamSubscription<List<DriverLocationModel>>? _subscription;
  Timer? _movementTimer;
  BitmapDescriptor? _markerIcon;
  List<DriverLocationModel> _latestDrivers = const <DriverLocationModel>[];
  final Map<String, _VisualDriver> _visualDrivers = <String, _VisualDriver>{};

  LatLng _center;
  bool _started = false;
  bool _disposed = false;

  LiveDriverMarkerController({
    required LatLng center,
    this.radiusKilometers = 12,
    DriverLocationService? locationService,
  })  : _center = center,
        _locationService = locationService ?? DriverLocationService();

  Set<Marker> get markers {
    final BitmapDescriptor? icon = _markerIcon;

    if (icon == null) return const <Marker>{};

    return _visualDrivers.values
        .map(
          (_VisualDriver driver) => Marker(
            markerId: MarkerId('live-driver-${driver.driverId}'),
            position: driver.position,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            rotation: driver.heading,
            alpha: driver.alpha.clamp(0.0, 1.0).toDouble(),
            infoWindow: const InfoWindow(
              title: 'Alpha driver nearby',
            ),
          ),
        )
        .toSet();
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

    await _loadMarkerIcon();
  }

  void updateCenter(LatLng center) {
    if (_samePoint(_center, center)) return;
    _center = center;
    _applyLocations(_latestDrivers);
  }

  Future<void> _loadMarkerIcon() async {
    try {
      final ByteData data = await rootBundle.load(markerAsset);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 96,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();

      try {
        final ByteData? bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (bytes != null) {
          _markerIcon = BitmapDescriptor.bytes(
            bytes.buffer.asUint8List(
              bytes.offsetInBytes,
              bytes.lengthInBytes,
            ),
          );
        }
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    } catch (error) {
      debugPrint('Unable to load the top-view driver marker: $error');
      _markerIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }

    if (_disposed) return;
    _applyLocations(_latestDrivers);
  }

  void _applyLocations(List<DriverLocationModel> locations) {
    if (_disposed || _markerIcon == null) return;

    final List<DriverLocationModel> nearbyDrivers = locations.where(
      (DriverLocationModel driver) {
        final double distanceMeters = Geolocator.distanceBetween(
          _center.latitude,
          _center.longitude,
          driver.latitude,
          driver.longitude,
        );

        return distanceMeters <= radiusKilometers * 1000;
      },
    ).toList(growable: false);

    final Set<String> incomingIds = nearbyDrivers
        .map((DriverLocationModel driver) => driver.driverId)
        .toSet();

    for (final _VisualDriver driver in _visualDrivers.values) {
      if (!incomingIds.contains(driver.driverId)) {
        driver
          ..startPosition = driver.position
          ..targetPosition = driver.position
          ..startHeading = driver.heading
          ..targetHeading = driver.heading
          ..startAlpha = driver.alpha
          ..targetAlpha = 0
          ..removeWhenInvisible = true;
      }
    }

    for (final DriverLocationModel driver in nearbyDrivers) {
      final LatLng destination = LatLng(
        driver.latitude,
        driver.longitude,
      );
      final _VisualDriver? current = _visualDrivers[driver.driverId];

      if (current == null) {
        _visualDrivers[driver.driverId] = _VisualDriver(
          driverId: driver.driverId,
          position: destination,
          startPosition: destination,
          targetPosition: destination,
          heading: _normalizeHeading(driver.heading ?? 0),
          startHeading: _normalizeHeading(driver.heading ?? 0),
          targetHeading: _normalizeHeading(driver.heading ?? 0),
          alpha: 0,
          startAlpha: 0,
          targetAlpha: 1,
          removeWhenInvisible: false,
        );
        continue;
      }

      current
        ..startPosition = current.position
        ..targetPosition = destination
        ..startHeading = current.heading
        ..targetHeading = _normalizeHeading(
          driver.heading ??
              (_samePoint(current.position, destination)
                  ? current.heading
                  : _bearingBetween(current.position, destination)),
        )
        ..startAlpha = current.alpha
        ..targetAlpha = 1
        ..removeWhenInvisible = false;
    }

    _startMovementAnimation();
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
            ..heading = _lerpHeading(
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

  static double _lerp(double start, double end, double progress) {
    return start + ((end - start) * progress);
  }

  static double _normalizeHeading(double value) {
    return ((value % 360) + 360) % 360;
  }

  static double _lerpHeading(double start, double end, double progress) {
    final double difference = ((end - start + 540) % 360) - 180;
    return _normalizeHeading(start + (difference * progress));
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

    return _normalizeHeading(math.atan2(y, x) * 180 / math.pi);
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
