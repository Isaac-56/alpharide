import 'package:flutter/material.dart';

import '../models/prediction_model.dart';
import 'services/places_service.dart';

class DestinationSearch extends StatefulWidget {
  final double latitude;
  final double longitude;
  final bool isPickup;

  const DestinationSearch({
    super.key,
    required this.latitude,
    required this.longitude,
    this.isPickup = false,
  });

  @override
  State<DestinationSearch> createState() => _DestinationSearchState();
}

class _DestinationSearchState extends State<DestinationSearch> {
  final TextEditingController _searchController = TextEditingController();

  final PlacesService _placesService = PlacesService();

  List<PredictionModel> _predictions = [];

  bool _isLoading = false;

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      setState(() {
        _predictions = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _placesService.searchPlaces(
        value,
        widget.latitude,
        widget.longitude,
      );

      if (!mounted) return;

      setState(() {
        _predictions = results;
      });
    } catch (e) {
      debugPrint(e.toString());

      if (!mounted) return;

      setState(() {
        _predictions = [];
      });
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  Widget _buildResult(PredictionModel prediction) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.location_on),
      ),
      title: Text(
        prediction.mainText,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(prediction.secondaryText),
      onTap: () async {
        try {
          setState(() {
            _isLoading = true;
          });

          final place = await _placesService.getPlaceDetails(
            prediction.placeId,
          );

          if (!mounted) return;

          Navigator.pop(context, place);
        } catch (e) {
          if (!mounted) return;

          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPickup ? "Choose Pickup Address" : "Choose Destination"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.isPickup ? "Where should the driver pick you up?" : "Where are you going?",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();

                    setState(() {
                      _predictions = [];
                    });
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onChanged: _search,
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: CircularProgressIndicator(),
            ),
          if (!_isLoading && _searchController.text.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  widget.isPickup ? "Start typing to search for a pickup location" : "Start typing to search for a destination",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          if (!_isLoading &&
              _searchController.text.isNotEmpty &&
              _predictions.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  "No locations found",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          if (_predictions.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _predictions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) => _buildResult(_predictions[index]),
              ),
            ),
        ],
      ),
    );
  }
}