import 'package:flutter/material.dart';

class CancelReasonScreen extends StatelessWidget {
  const CancelReasonScreen({super.key});

  static const Color backgroundColor = Color(0xFF101210);
  static const Color primaryColor = Color(0xFF39FF14);
  static const Color surfaceColor = Color(0xFF202320);

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
                shape: const CircleBorder(
                  side: BorderSide(
                    color: Color(0xFF4A4E4A),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context, false);
                  },
                  child: const SizedBox(
                    width: 54,
                    height: 54,
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 38),
              const Text(
                'Cancel order',
                style: TextStyle(
                  color: Colors.white,
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF8F948F),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Row(
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
                        color: Color(0xFF8F948F),
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
