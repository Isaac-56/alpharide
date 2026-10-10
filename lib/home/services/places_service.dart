import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/prediction_model.dart';

class PlacesService {
  // Your Google Maps API Key
  static const String apiKey = "AIzaSyCqwEeIXaslrBo2QCex3cZCwxOIfq0NzZY";

  Future<List<PredictionModel>> searchPlaces(
    String input,
    double latitude,
    double longitude,
  ) async {
    if (input.trim().isEmpty) return [];

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/place/autocomplete/json"
      "?input=$input"
      "&location=$latitude,$longitude"
      "&radius=50000"
      "&strictbounds=false"
      "&key=$apiKey",
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception("Failed to load places.");
    }

    final data = json.decode(response.body);

    if (data["status"] != "OK" && data["status"] != "ZERO_RESULTS") {
      throw Exception(data["error_message"] ?? data["status"]);
    }

    final List predictions = data["predictions"];

    return predictions.map((e) => PredictionModel.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> getPlaceDetails(String placeId) async {
    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/place/details/json"
      "?place_id=$placeId"
      "&fields=geometry/location,formatted_address,name"
      "&key=$apiKey",
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception("Failed to load place details.");
    }

    final data = json.decode(response.body);

    if (data["status"] != "OK") {
      throw Exception(data["error_message"] ?? data["status"]);
    }

    final result = data["result"];

    return {
      "latitude": result["geometry"]["location"]["lat"],
      "longitude": result["geometry"]["location"]["lng"],
      "address": result["formatted_address"],
      "name": result["name"],
    };
  }
}
