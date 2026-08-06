import 'package:flutter/material.dart';

import '../account/account_ui.dart';

class CancelReasonScreen extends StatelessWidget {
  const CancelReasonScreen({super.key});

  static const Color primaryColor = Color(0xFF39FF14);

  static const List<String> reasons = [
    'Fare is too high',
    'Just trying the app',
    'Changed my mind',
    'No driver assigned',
    'Pickup point is incorrect',
    'Custom reason',
  ];

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = AlphaColors.background(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: surfaceColor,
                shape: CircleBorder(
                  side: BorderSide(color: AlphaColors.border(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context, false);
                  },
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: Icon(
                      Icons.close_rounded,
                      color: textColor,
                      size: 29,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 38),
              Text(
                'Cancel order',
                style: TextStyle(
                  color: textColor,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.65,
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView.separated(
                  itemCount: reasons.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final String reason = reasons[index];

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Order cancelled: $reason',
                              ),
                            ),
                          );
                          Navigator.pop(context, true);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 17,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                  },
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: primaryColor,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Choose the reason that best describes your cancellation.',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
