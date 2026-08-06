import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../account/account_ui.dart';
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
  static const Color errorColor = Color(0xFFD83A3A);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PlacesService _placesService = PlacesService();
  final List<PredictionModel> _predictions = <PredictionModel>[];

  Timer? _searchDebounce;

  int _searchRequestId = 0;

  bool _isSearching = false;
  bool _isOpeningMap = false;

  String? _resolvingPlaceId;
  String? _errorMessage;

  bool get _isResolvingPlace => _resolvingPlaceId != null;

  @override
  void dispose() {
    _searchRequestId++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    final String query = value.trim();
    final int requestId = ++_searchRequestId;

    setState(() {
      _errorMessage = null;

      if (query.isEmpty) {
        _predictions.clear();
        _isSearching = false;
      } else {
        _isSearching = true;
      }
    });

    if (query.isEmpty) return;

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query, requestId),
    );
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();

    final String query = value.trim();

    if (query.isEmpty) {
      _clearSearch();
      return;
    }

    final int requestId = ++_searchRequestId;

    _search(query, requestId);
  }

  Future<void> _search(
    String query,
    int requestId,
  ) async {
    if (!mounted || query.isEmpty || requestId != _searchRequestId) {
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final List<PredictionModel> results = await _placesService.searchPlaces(
        query,
        widget.latitude,
        widget.longitude,
      );

      if (!mounted ||
          requestId != _searchRequestId ||
          _searchController.text.trim() != query) {
        return;
      }

      setState(() {
        _predictions
          ..clear()
          ..addAll(results);

        _isSearching = false;
      });
    } catch (error) {
      debugPrint('Location search failed: $error');

      if (!mounted || requestId != _searchRequestId) {
        return;
      }

      setState(() {
        _predictions.clear();
        _isSearching = false;
        _errorMessage = 'Unable to search locations. Please try again.';
      });
    }
  }

  Future<void> _selectPrediction(
    PredictionModel prediction,
  ) async {
    if (_isResolvingPlace || _isOpeningMap) return;

    _searchDebounce?.cancel();
    _searchRequestId++;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = false;
      _resolvingPlaceId = prediction.placeId;
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
        _resolvingPlaceId = null;
        _errorMessage = 'Unable to open this location. Please try again.';
      });
    }
  }

  Future<void> _openMapPicker() async {
    if (_isOpeningMap || _isResolvingPlace) return;

    _searchDebounce?.cancel();
    _searchRequestId++;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = false;
      _isOpeningMap = true;
      _errorMessage = null;
    });

    final LocationSelection? result;

    try {
      result = await Navigator.push<LocationSelection>(
        context,
        MaterialPageRoute<LocationSelection>(
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
    } catch (error) {
      debugPrint('Unable to open map picker: $error');

      if (!mounted) return;

      setState(() {
        _isOpeningMap = false;
        _errorMessage = 'Unable to open the map. Please try again.';
      });

      return;
    }

    if (!mounted) return;

    if (result != null) {
      Navigator.pop(context, result);
      return;
    }

    setState(() {
      _isOpeningMap = false;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;

    _searchController.clear();

    setState(() {
      _predictions.clear();
      _errorMessage = null;
      _isSearching = false;
    });

    _searchFocusNode.requestFocus();
  }

  void _closePage() {
    if (_isResolvingPlace || _isOpeningMap) return;

    _searchDebounce?.cancel();
    _searchRequestId++;

    FocusScope.of(context).unfocus();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final String fieldLabel =
        widget.isPickup ? 'Search pickup location' : 'Where are you going?';

    final String mapButtonLabel =
        widget.isPickup ? 'Set pickup point on map' : 'Set destination on map';

    final bool hasQuery = _searchController.text.trim().isNotEmpty;
    final Color pageBackground = AlphaColors.background(context);
    final Color textColor = AlphaColors.text(context);
    final Color secondaryTextColor = AlphaColors.muted(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color borderColor = AlphaColors.border(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: pageBackground,
      body: SafeArea(
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          slivers: <Widget>[
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
                  children: <Widget>[
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Material(
                        color: surfaceColor,
                        shape: CircleBorder(
                          side: BorderSide(color: borderColor),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _isResolvingPlace || _isOpeningMap
                              ? null
                              : _closePage,
                          customBorder: const CircleBorder(),
                          child: Icon(
                            Icons.close_rounded,
                            color: textColor,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
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
                      style: TextStyle(
                        color: textColor,
                        fontSize: 19,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: borderColor,
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      enabled: !_isResolvingPlace && !_isOpeningMap,
                      autofocus: true,
                      keyboardType: TextInputType.streetAddress,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      enableSuggestions: true,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        labelText: fieldLabel,
                        labelStyle: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 14,
                        ),
                        floatingLabelStyle: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: textColor,
                        ),
                        suffixIcon: hasQuery
                            ? IconButton(
                                tooltip: 'Clear search',
                                onPressed: _isResolvingPlace || _isOpeningMap
                                    ? null
                                    : _clearSearch,
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
                          borderSide: BorderSide(color: borderColor),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: textColor,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onChanged: _onSearchChanged,
                      onSubmitted: _submitSearch,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _isResolvingPlace || _isOpeningMap
                            ? null
                            : _openMapPicker,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          disabledForegroundColor: secondaryTextColor,
                          side: BorderSide(color: borderColor),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 17,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
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
                              child: _isOpeningMap
                                  ? SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: textColor,
                                      ),
                                    )
                                  : Icon(
                                      Icons.map_outlined,
                                      color: textColor,
                                      size: 21,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                mapButtonLabel,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: secondaryTextColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: !_isSearching
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey<String>(
                                'search-progress',
                              ),
                              padding: EdgeInsets.only(top: 18),
                              child: LinearProgressIndicator(
                                color: primaryColor,
                                backgroundColor: surfaceColor,
                                minHeight: 3,
                              ),
                            ),
                    ),
                    if (_errorMessage != null) ...<Widget>[
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.error_outline_rounded,
                              color: errorColor,
                              size: 19,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: errorColor,
                                  fontSize: 13.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (_predictions.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  24,
                ),
                sliver: SliverList.separated(
                  itemCount: _predictions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 70,
                    endIndent: 12,
                    color: borderColor,
                  ),
                  itemBuilder: (
                    BuildContext context,
                    int index,
                  ) {
                    final PredictionModel prediction = _predictions[index];

                    return _SearchResultTile(
                      prediction: prediction,
                      isLoading: _resolvingPlaceId == prediction.placeId,
                      enabled: !_isResolvingPlace && !_isOpeningMap,
                      onTap: () => _selectPrediction(prediction),
                    );
                  },
                ),
              ),
            if (!_isSearching &&
                hasQuery &&
                _predictions.isEmpty &&
                _errorMessage == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.location_off_outlined,
                          color: secondaryTextColor,
                          size: 30,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No matching locations found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
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
  final bool isLoading;
  final bool enabled;

  const _SearchResultTile({
    required this.prediction,
    required this.onTap,
    required this.isLoading,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _DestinationSearchState.primaryColor
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: textColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      prediction.mainText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (prediction.secondaryText.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        prediction.secondaryText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textColor,
                        ),
                      )
                    : Icon(
                        Icons.north_west_rounded,
                        color: mutedColor,
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
