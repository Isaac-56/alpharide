class AddressModel {
  final String placeId;
  final String placeName;
  final String placeAddress;
  final double latitude;
  final double longitude;

  const AddressModel({
    required this.placeId,
    required this.placeName,
    required this.placeAddress,
    required this.latitude,
    required this.longitude,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      placeId: json["placeId"] ?? "",
      placeName: json["placeName"] ?? "",
      placeAddress: json["placeAddress"] ?? "",
      latitude: (json["latitude"] ?? 0).toDouble(),
      longitude: (json["longitude"] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "placeId": placeId,
      "placeName": placeName,
      "placeAddress": placeAddress,
      "latitude": latitude,
      "longitude": longitude,
    };
  }

  AddressModel copyWith({
    String? placeId,
    String? placeName,
    String? placeAddress,
    double? latitude,
    double? longitude,
  }) {
    return AddressModel(
      placeId: placeId ?? this.placeId,
      placeName: placeName ?? this.placeName,
      placeAddress: placeAddress ?? this.placeAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}