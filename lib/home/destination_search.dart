import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/location_selection.dart';
import '../models/prediction_model.dart';
import 'map_location_picker.dart';
import 'services/places_service.dart';

class DestinationSearch extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String pickupAddress;
  final String initialAddress;
  final bool isPickup;

  const DestinationSearch({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.pickupAddress,
    required this.initialAddress,
    this.isPickup = false,
  });

  @override
  State<DestinationSearch> createState() => _DestinationSearchState();
}

class _DestinationSearchState extends State<DestinationSearch> {
  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color secondaryTextColor = Color(0xFF6B6B6B);
  static const Color surfaceColor = Color(0xFFF7F8F7);
  static const Color borderColor = Color(0xFFE7EAE7);
  static const Color errorColor = Color(0xFFD83A3A);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PlacesService _placesService = PlacesService();

  final List<PredictionModel> _predictions = [];

  Timer? _searchDebounce;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _errorMessage = null;
    });

    _searchDebounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _predictions.clear();
        _isLoading = false;
      });
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () {
        _search(value);
      },
    );
  }

  Future<void> _search(String value) async {
    final String query = value.trim();

    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<PredictionModel> results = await _placesService.searchPlaces(
        query,
        widget.latitude,
        widget.longitude,
      );

      if (!mounted || _searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _predictions
          ..clear()
          ..addAll(results);
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Location search failed: $error');

      if (!mounted) return;

      setState(() {
        _predictions.clear();
        _isLoading = false;
        _errorMessage = 'Unable to search locations. Please try again.';
      });
    }
  }

  Future<void> _selectPrediction(
    PredictionModel prediction,
  ) async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, dynamic> place = await _placesService.getPlaceDetails(
        prediction.placeId,
      );

      if (!mounted) return;

      final double? latitude = (place['latitude'] as num?)?.toDouble();
      final double? longitude = (place['longitude'] as num?)?.toDouble();

      if (latitude == null || longitude == null) {
        throw const FormatException(
          'This location does not contain valid coordinates.',
        );
      }

      final String address = place['address']?.toString().trim() ?? '';

      final String placeName = place['name']?.toString().trim() ?? '';

      Navigator.pop(
        context,
        LocationSelection(
          latitude: latitude,
          longitude: longitude,
          address: address.isEmpty ? prediction.secondaryText : address,
          name: placeName.isEmpty ? prediction.mainText : placeName,
        ),
      );
    } catch (error) {
      debugPrint('Unable to select place: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to open this location.';
      });
    }
  }

  Future<void> _openMapPicker() async {
    FocusScope.of(context).unfocus();

    final LocationSelection? result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(
          initialLocation: LatLng(
            widget.latitude,
            widget.longitude,
          ),
          initialAddress: widget.initialAddress,
          isPickup: widget.isPickup,
        ),
      ),
    );

    if (result == null || !mounted) return;

    Navigator.pop(context, result);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();

    setState(() {
      _predictions.clear();
      _errorMessage = null;
      _isLoading = false;
    });

    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final String fieldLabel =
        widget.isPickup ? 'Search pickup location' : 'Where are you going?';

    final String mapButtonLabel =
        widget.isPickup ? 'Set pickup point on map' : 'Set destination on map';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        16,
                        24,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 46,
                            height: 46,
                            child: Material(
                              color: Colors.white,
                              shape: const CircleBorder(
                                side: BorderSide(
                                  color: borderColor,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                },
                                customBorder: const CircleBorder(),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: textColor,
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          const Text(
                            'Pick-up address',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 13.5,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.pickupAddress.trim().isEmpty
                                ? 'Current location'
                                : widget.pickupAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 19,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: borderColor,
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              labelText: fieldLabel,
                              labelStyle: const TextStyle(
                                color: secondaryTextColor,
                                fontSize: 14,
                              ),
                              floatingLabelStyle: const TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: textColor,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      onPressed: _clearSearch,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: surfaceColor,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: borderColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: textColor,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            onChanged: _onSearchChanged,
                            onSubmitted: _search,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: _openMapPicker,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textColor,
                                side: const BorderSide(
                                  color: borderColor,
                                ),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 17,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: primaryColor.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.map_outlined,
                                      color: textColor,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      mapButtonLabel,
                                      style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: secondaryTextColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isLoading) ...[
                            const SizedBox(height: 18),
                            const LinearProgressIndicator(
                              color: primaryColor,
                              backgroundColor: surfaceColor,
                              minHeight: 3,
                            ),
                          ],
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: errorColor.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: errorColor,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                  if (!_isLoading && _predictions.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24,
                      ),
                      sliver: SliverList.separated(
                        itemCount: _predictions.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 70,
                          endIndent: 12,
                          color: borderColor,
                        ),
                        itemBuilder: (
                          BuildContext context,
                          int index,
                        ) {
                          final PredictionModel prediction =
                              _predictions[index];

                          return _SearchResultTile(
                            prediction: prediction,
                            onTap: () {
                              _selectPrediction(prediction);
                            },
                          );
                        },
                      ),
                    ),
                  if (!_isLoading &&
                      _searchController.text.isNotEmpty &&
                      _predictions.isEmpty &&
                      _errorMessage == null)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No matching locations found.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final PredictionModel prediction;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.prediction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _DestinationSearchState.primaryColor
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: _DestinationSearchState.textColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.mainText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _DestinationSearchState.textColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (prediction.secondaryText.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        prediction.secondaryText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _DestinationSearchState.secondaryTextColor,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Icon(
                  Icons.north_west_rounded,
                  color: _DestinationSearchState.secondaryTextColor,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
