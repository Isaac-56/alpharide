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

  bool get _isDarkMode =>
      Theme.of(context).brightness == Brightness.dark;

  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF101210) : Colors.white;

  Color get surfaceColor =>
      _isDarkMode ? const Color(0xFF202320) : const Color(0xFFF3F5F3);

  Color get textColor =>
      _isDarkMode ? Colors.white : const Color(0xFF111311);

  Color get mutedColor =>
      _isDarkMode ? const Color(0xFF9A9F9A) : const Color(0xFF687068);

  Color get dividerColor =>
      _isDarkMode ? const Color(0xFF303330) : const Color(0xFFE1E6E1);

  RideOption _selectedRide = RideOption.options.first;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  Future<void> _handleRideTap(RideOption ride) async {
    if (_selectedRide.id != ride.id) {
      setState(() {
        _selectedRide = ride;
      });
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RideOptionDetailsScreen(
          ride: ride,
        ),
      ),
    );
  }

  Future<void> _choosePaymentMethod() async {
    final PaymentMethod? result = await showPaymentMethodSheet(
      context: context,
      selectedMethod: _paymentMethod,
    );

    if (result == null || !mounted) return;

    setState(() {
      _paymentMethod = result;
    });
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
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 13),
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _routeCard(),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
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
            const SizedBox(height: 11),
            SizedBox(
              height: 104,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: RideOption.options.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) {
                  final RideOption ride = RideOption.options[index];
                  return _rideCard(ride);
                },
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _actionTile(
                icon: _paymentIcon,
                label: 'Payment • $_paymentLabel',
                onTap: _choosePaymentMethod,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 57,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onConfirmRide(
                      _selectedRide,
                      _paymentMethod,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: const Color(0xFF071007),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Set pick-up point',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '~ ${_selectedRide.estimatedFare} ETB',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'The final fare may change with time and distance',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeCard() {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dividerColor,
        ),
      ),
      child: Column(
        children: [
          _routeRow(
            label: 'Pickup',
            address: widget.pickupAddress,
            markerLabel: 'A',
            markerColor: Colors.white,
            onTap: widget.onPickupTap,
          ),
          Divider(
            height: 1,
            indent: 62,
            color: dividerColor,
          ),
          _routeRow(
            label: 'Destination',
            address: widget.destinationAddress.isEmpty
                ? 'Where are you going?'
                : widget.destinationAddress,
            markerLabel: 'B',
            markerColor: primaryColor,
            onTap: widget.onDestinationTap,
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
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
                  children: [
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

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${ride.name}, about ${ride.estimatedFare} ETB, ${ride.seats} seats',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _handleRideTap(ride);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOut,
            width: 178,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? primaryColor.withValues(alpha: 0.075)
                  : surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? primaryColor : dividerColor,
                width: selected ? 2.2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.12),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  height: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Hero(
                          tag: 'ride-${ride.id}',
                          child: Image.asset(
                            ride.assetPath,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (ride.isElectric)
                        const Positioned(
                          top: 2,
                          left: 2,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: primaryColor,
                            child: Icon(
                              Icons.bolt_rounded,
                              color: Color(0xFF071007),
                              size: 15,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ride.name.replaceFirst('Alpha ', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${ride.seats} seats',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '~ ${ride.estimatedFare} ETB',
                          style: TextStyle(
                            color: selected ? primaryColor : textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
  }) {
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 13,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: textColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
