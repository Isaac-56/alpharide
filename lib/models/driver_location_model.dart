class DriverLocationModel {
  final String driverId;
  final double latitude;
  final double longitude;
  final double? heading;
  final bool isOnline;
  final int updatedAt;
  final String vehicleType;

  const DriverLocationModel({
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.isOnline,
    required this.updatedAt,
    required this.vehicleType,
  });

  factory DriverLocationModel.fromMap(
    String driverId,
    Map<Object?, Object?> data,
  ) {
    return DriverLocationModel(
      driverId: driverId,
      latitude: _toDouble(data['latitude'] ?? data['lat']) ?? 0,
      longitude: _toDouble(data['longitude'] ?? data['lng']) ?? 0,
      heading: _toDouble(data['heading'] ?? data['bearing']),
      isOnline: _toBool(data['isOnline'] ?? data['online']),
      updatedAt: _toInt(data['updatedAt'] ?? data['lastUpdated']) ?? 0,
      vehicleType: data['vehicleType']?.toString() ?? 'standard',
    );
  }

  bool get hasValidCoordinates {
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _toInt(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final String normalized = value?.toString().toLowerCase().trim() ?? '';
    return normalized == 'true' || normalized == 'online' || normalized == '1';
  }
}
