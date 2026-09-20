class LocationSelection {
  final double latitude;
  final double longitude;
  final String address;
  final String name;
  final bool isCurrentLocation;

  const LocationSelection({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.name,
    this.isCurrentLocation = false,
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

    return isCurrentLocation ? 'My location' : 'Pinned location';
  }

  static bool _isSpecificLabel(String value) {
    if (value.isEmpty) return false;
    final String normalized = value.toLowerCase();
    return normalized != 'current location' &&
        normalized != 'selected location' &&
        normalized != 'detecting current location...' &&
        !_looksLikeCoordinates(normalized);
  }

  static bool _looksLikeCoordinates(String value) {
    return RegExp(r'^[-+\d\s.,]+$').hasMatch(value);
  }
}
