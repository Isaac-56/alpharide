import 'package:flutter/material.dart';

import '../models/ride_option.dart';
import 'payment_method_sheet.dart';
import 'ride_option_details_screen.dart';

typedef RideSelectionCallback = void Function(
  RideOption ride,
  PaymentMethod paymentMethod,
);

class OrderPanel extends StatefulWidget {
  final String pickupAddress;
  final String destinationAddress;
  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;
  final RideSelectionCallback onConfirmRide;

  const OrderPanel({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.onPickupTap,
    required this.onDestinationTap,
    required this.onConfirmRide,
  });

  @override
  State<OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<OrderPanel> {
  static const Color primaryColor = Color(0xFF39FF14);

  RideOption _selectedRide = RideOption.options.first;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  bool _isOpeningDetails = false;
  bool _isOpeningPayment = false;
  bool _isConfirmingRide = false;
  bool _isOpeningLocation = false;

  bool get _isInteractionLocked =>
      _isOpeningDetails ||
      _isOpeningPayment ||
      _isConfirmingRide ||
      _isOpeningLocation;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF101210) : Colors.white;

  Color get surfaceColor =>
      _isDarkMode ? const Color(0xFF202320) : const Color(0xFFF3F5F3);

  Color get textColor => _isDarkMode ? Colors.white : const Color(0xFF111311);

  Color get mutedColor =>
      _isDarkMode ? const Color(0xFF9A9F9A) : const Color(0xFF687068);

  Color get dividerColor =>
      _isDarkMode ? const Color(0xFF303330) : const Color(0xFFE1E6E1);

  Future<void> _handleRideTap(
    RideOption ride,
  ) async {
    if (_isInteractionLocked) return;

    if (_selectedRide.id != ride.id) {
      setState(() {
        _selectedRide = ride;
      });
      return;
    }

    setState(() {
      _isOpeningDetails = true;
    });

    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RideOptionDetailsScreen(
            ride: ride,
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'Unable to open ride details: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningDetails = false;
        });
      }
    }
  }

  Future<void> _choosePaymentMethod() async {
    if (_isInteractionLocked) return;

    setState(() {
      _isOpeningPayment = true;
    });

    try {
      final PaymentMethod? result = await showPaymentMethodSheet(
        context: context,
        selectedMethod: _paymentMethod,
      );

      if (result == null || !mounted) return;

      setState(() {
        _paymentMethod = result;
      });
    } catch (error) {
      debugPrint(
        'Unable to open payment methods: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningPayment = false;
        });
      }
    }
  }

  void _handleLocationTap(
    VoidCallback callback,
  ) {
    if (_isInteractionLocked) return;

    setState(() {
      _isOpeningLocation = true;
    });

    try {
      callback();
    } catch (error) {
      debugPrint(
        'Unable to open location selection: $error',
      );
    } finally {
      Future<void>.delayed(
        const Duration(milliseconds: 550),
        () {
          if (!mounted) return;

          setState(() {
            _isOpeningLocation = false;
          });
        },
      );
    }
  }

  void _confirmRide() {
    if (_isInteractionLocked) return;

    setState(() {
      _isConfirmingRide = true;
    });

    try {
      widget.onConfirmRide(
        _selectedRide,
        _paymentMethod,
      );
    } catch (error) {
      debugPrint(
        'Unable to confirm ride: $error',
      );
    } finally {
      Future<void>.delayed(
        const Duration(milliseconds: 700),
        () {
          if (!mounted) return;

          setState(() {
            _isConfirmingRide = false;
          });
        },
      );
    }
  }

  String get _paymentLabel {
    switch (_paymentMethod) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.wallet:
        return 'Wallet';
    }
  }

  IconData get _paymentIcon {
    switch (_paymentMethod) {
      case PaymentMethod.cash:
        return Icons.payments_rounded;
      case PaymentMethod.card:
        return Icons.credit_card_rounded;
      case PaymentMethod.wallet:
        return Icons.account_balance_wallet_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          10,
          0,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: AnimatedContainer(
                duration: const Duration(
                  milliseconds: 260,
                ),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: _isDarkMode
                      ? const Color(0xFF4B4F4B)
                      : const Color(0xFFC7CCC7),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                16,
                20,
                12,
              ),
              child: Text(
                'Order a ride',
                style: TextStyle(
                  color: textColor,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: _routeCard(),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Choose your ride',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Tap again for details',
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: RideOption.options.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (
                  BuildContext context,
                  int index,
                ) {
                  final RideOption ride = RideOption.options[index];

                  return _rideCard(ride);
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: _actionTile(
                icon: _paymentIcon,
                label: 'Payment • $_paymentLabel',
                loading: _isOpeningPayment,
                onTap: _choosePaymentMethod,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isInteractionLocked ? null : _confirmRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: const Color(0xFF071007),
                    disabledBackgroundColor: primaryColor.withValues(
                      alpha: 0.52,
                    ),
                    disabledForegroundColor: const Color(0xFF071007).withValues(
                      alpha: 0.62,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(
                      milliseconds: 160,
                    ),
                    child: _isConfirmingRide
                        ? const SizedBox(
                            key: ValueKey<String>(
                              'confirming-ride',
                            ),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Color(0xFF071007),
                            ),
                          )
                        : Row(
                            key: const ValueKey<String>(
                              'confirm-ride',
                            ),
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'Set pick-up point',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '~ ${_selectedRide.estimatedFareLabel}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                ),
                child: Text(
                  'The final fare may change with time and distance',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dividerColor,
        ),
      ),
      child: Column(
        children: <Widget>[
          _routeRow(
            label: 'Pickup',
            address: widget.pickupAddress.trim().isEmpty
                ? 'Current location'
                : widget.pickupAddress,
            markerLabel: 'A',
            markerColor: Colors.white,
            onTap: () => _handleLocationTap(
              widget.onPickupTap,
            ),
          ),
          Divider(
            height: 1,
            indent: 62,
            color: dividerColor,
          ),
          _routeRow(
            label: 'Destination',
            address: widget.destinationAddress.trim().isEmpty
                ? 'Where are you going?'
                : widget.destinationAddress,
            markerLabel: 'B',
            markerColor: primaryColor,
            onTap: () => _handleLocationTap(
              widget.onDestinationTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeRow({
    required String label,
    required String address,
    required String markerLabel,
    required Color markerColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isInteractionLocked ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: markerColor == Colors.white
                      ? Border.all(
                          color: dividerColor,
                        )
                      : null,
                ),
                child: Text(
                  markerLabel,
                  style: const TextStyle(
                    color: Color(0xFF111311),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: mutedColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rideCard(RideOption ride) {
    final bool selected = ride.id == _selectedRide.id;

    final bool openingThisRide = selected && _isOpeningDetails;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${ride.name}, about ${ride.estimatedFareLabel}, ${ride.seats} seats',
      hint: selected
          ? 'Tap again to open ride details'
          : 'Tap to select this ride',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOut,
        width: 174,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? primaryColor : dividerColor,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: primaryColor.withValues(
                      alpha: 0.11,
                    ),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: selected
              ? Color.alphaBlend(
                  primaryColor.withValues(
                    alpha: 0.075,
                  ),
                  backgroundColor,
                )
              : surfaceColor,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isInteractionLocked ? null : () => _handleRideTap(ride),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 7,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 78,
                    height: double.infinity,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: Hero(
                            tag: 'ride-${ride.id}',
                            child: Image.asset(
                              ride.assetPath,
                              fit: BoxFit.contain,
                              cacheWidth: 240,
                              filterQuality: FilterQuality.low,
                              gaplessPlayback: true,
                              excludeFromSemantics: true,
                              errorBuilder: (
                                BuildContext context,
                                Object error,
                                StackTrace? stackTrace,
                              ) {
                                return Icon(
                                  Icons.directions_car_filled_rounded,
                                  color: mutedColor,
                                  size: 42,
                                );
                              },
                            ),
                          ),
                        ),
                        if (ride.isElectric)
                          const Positioned(
                            top: 2,
                            left: 2,
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: primaryColor,
                              child: Icon(
                                Icons.bolt_rounded,
                                color: Color(
                                  0xFF071007,
                                ),
                                size: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(
                        milliseconds: 150,
                      ),
                      child: openingThisRide
                          ? const Center(
                              key: ValueKey<String>(
                                'ride-details-loading',
                              ),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: primaryColor,
                                ),
                              ),
                            )
                          : Column(
                              key: ValueKey<String>(
                                'ride-${ride.id}',
                              ),
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                Text(
                                  ride.name.replaceFirst(
                                    'Alpha ',
                                    '',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(
                                  height: 3,
                                ),
                                Text(
                                  '${ride.seats} seats',
                                  style: TextStyle(
                                    color: mutedColor,
                                    fontSize: 9.5,
                                  ),
                                ),
                                const SizedBox(
                                  height: 5,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '~ ${ride.estimatedFareLabel}',
                                    style: TextStyle(
                                      color:
                                          selected ? primaryColor : textColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool loading,
  }) {
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isInteractionLocked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 12,
          ),
          child: Row(
            children: <Widget>[
              AnimatedSwitcher(
                duration: const Duration(
                  milliseconds: 150,
                ),
                child: loading
                    ? const SizedBox(
                        key: ValueKey<String>(
                          'payment-loading',
                        ),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: primaryColor,
                        ),
                      )
                    : Icon(
                        icon,
                        key: ValueKey<IconData>(icon),
                        color: textColor,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(
                    milliseconds: 170,
                  ),
                  child: Text(
                    label,
                    key: ValueKey<String>(label),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: mutedColor,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
