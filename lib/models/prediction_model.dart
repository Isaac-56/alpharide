class PredictionModel {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PredictionModel({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory PredictionModel.fromJson(Map<String, dynamic> json) {
    return PredictionModel(
      placeId: json["place_id"] ?? "",
      mainText: json["structured_formatting"]?["main_text"] ?? "",
      secondaryText: json["structured_formatting"]?["secondary_text"] ?? "",
    );
  }
}
