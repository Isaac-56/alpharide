import 'package:flutter/material.dart';

import '../models/ride_option.dart';

class RideOptionDetailsScreen extends StatelessWidget {
  final RideOption ride;

  const RideOptionDetailsScreen({
    super.key,
    required this.ride,
  });

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color backgroundColor = Color(0xFF101210);
  static const Color dividerColor = Color(0xFF292C29);
  static const Color mutedColor = Color(0xFF8F948F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 86, 24, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 270,
                    child: Hero(
                      tag: 'ride-${ride.id}',
                      child: Image.asset(
                        ride.assetPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ride.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                      if (ride.isElectric)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 17,
                                color: primaryColor,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Electric',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ride.description,
                    style: const TextStyle(
                      color: mutedColor,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _detailRow(
                    label: 'Estimated price',
                    value: '~ ${ride.estimatedFare} ETB',
                  ),
                  _detailRow(
                    label: 'Seats',
                    value: '${ride.seats} seats',
                  ),
                  _acceptedPaymentRow(),
                  const SizedBox(height: 30),
                  const Text(
                    'AlphaRide transport',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailRow(
                    label: 'Minimum fare',
                    value: '${ride.minimumFare} ETB',
                  ),
                  _detailRow(
                    label: 'Base fare',
                    value: '${ride.baseFare} ETB',
                  ),
                  _detailRow(
                    label: 'Distance and time',
                    value:
                        '${ride.perMinute} ETB/min • ${ride.perKilometer} ETB/km',
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(
                        bottom: 8,
                      ),
                      iconColor: primaryColor,
                      collapsedIconColor: mutedColor,
                      title: const Text(
                        'More',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: const [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The final price can change with traffic, waiting time, route changes, tolls, or active promotions.',
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 18,
              child: _roundBackButton(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBackButton(BuildContext context) {
    return Material(
      color: const Color(0xFF232623),
      shape: const CircleBorder(
        side: BorderSide(
          color: Color(0xFF4A4E4A),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
        },
        child: const SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dividerColor,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: mutedColor,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedPaymentRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dividerColor,
          ),
        ),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'Accepted',
              style: TextStyle(
                color: mutedColor,
                fontSize: 15,
              ),
            ),
          ),
          Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: 25,
          ),
          SizedBox(width: 13),
          Icon(
            Icons.credit_card_rounded,
            color: Colors.white,
            size: 25,
          ),
          SizedBox(width: 13),
          Icon(
            Icons.payments_rounded,
            color: Colors.white,
            size: 25,
          ),
        ],
      ),
    );
  }
}
