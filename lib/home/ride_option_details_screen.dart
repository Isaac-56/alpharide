import 'package:flutter/material.dart';

import '../account/account_ui.dart';
import '../models/ride_option.dart';

class RideOptionDetailsScreen extends StatelessWidget {
  final RideOption ride;

  const RideOptionDetailsScreen({
    super.key,
    required this.ride,
  });

  static const Color primaryColor = Color(0xFF39FF14);

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = AlphaColors.background(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

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
                          style: TextStyle(
                            color: textColor,
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
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _detailRow(
                    context: context,
                    label: 'Estimated price',
                    value: '~ ${ride.estimatedFareLabel}',
                  ),
                  _detailRow(
                    context: context,
                    label: 'Seats',
                    value: '${ride.seats} seats',
                  ),
                  _acceptedPaymentRow(context),
                  const SizedBox(height: 30),
                  Text(
                    'AlphaRide transport',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _detailRow(
                    context: context,
                    label: 'Minimum fare',
                    value: ride.minimumFareLabel,
                  ),
                  _detailRow(
                    context: context,
                    label: 'Base fare',
                    value: ride.baseFareLabel,
                  ),
                  _detailRow(
                    context: context,
                    label: 'Distance and time',
                    value: '${ride.perMinuteLabel} • ${ride.perKilometerLabel}',
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
                      title: Text(
                        'More',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
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
      color: AlphaColors.surface(context),
      shape: CircleBorder(
        side: BorderSide(color: AlphaColors.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
        },
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            Icons.arrow_back_rounded,
            color: AlphaColors.text(context),
            size: 27,
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AlphaColors.border(context),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: mutedColor,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedPaymentRow(BuildContext context) {
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AlphaColors.border(context),
          ),
        ),
      ),
      child: Row(
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
            Icons.payments_rounded,
            color: textColor,
            size: 25,
          ),
          const SizedBox(width: 8),
          Text(
            'Cash only',
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
