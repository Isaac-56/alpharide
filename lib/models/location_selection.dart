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

    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }

    return address.trim().isEmpty ? 'Selected location' : address.trim();
  }
}
