class LocationSelection {
  final double latitude;
  final double longitude;
  final String address;
  final String name;

  const LocationSelection({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.name,
  });

  String get displayName {
    final String trimmedName = name.trim();
    if (_isSpecificLabel(trimmedName)) {
      return trimmedName;
    }

    final String trimmedAddress = address.trim();
    if (_isSpecificLabel(trimmedAddress)) {
      return trimmedAddress;
    }

    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  static bool _isSpecificLabel(String value) {
    if (value.isEmpty) return false;
    final String normalized = value.toLowerCase();
    return normalized != 'current location' &&
        normalized != 'selected location' &&
        normalized != 'detecting current location...';
  }
}
