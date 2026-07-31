import 'package:flutter/material.dart';

import '../models/ride_option.dart';

const Color _primaryColor = Color(0xFF39FF14);
const Color _backgroundColor = Color(0xFF101210);
const Color _surfaceColor = Color(0xFF202320);
const Color _mutedColor = Color(0xFF9A9F9A);

Future<PaymentMethod?> showPaymentMethodSheet({
  required BuildContext context,
  required PaymentMethod selectedMethod,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return _PaymentMethodSheet(
        initialMethod: selectedMethod,
      );
    },
  );
}

class _PaymentMethodSheet extends StatefulWidget {
  final PaymentMethod initialMethod;

  const _PaymentMethodSheet({
    required this.initialMethod,
  });

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  late PaymentMethod _selectedMethod;

  @override
  void initState() {
    super.initState();

    // Cash is currently the only available payment method.
    _selectedMethod = PaymentMethod.cash;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4E4A),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Payment method',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      PaymentMethod.cash,
                    );
                  },
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Cash — currently available
            _paymentTile(
              method: PaymentMethod.cash,
              icon: Icons.payments_rounded,
              title: 'Cash',
              subtitle: 'Pay the driver after your ride',
              enabled: true,
            ),
            const SizedBox(height: 12),

            // Card — coming soon
            _paymentTile(
              method: PaymentMethod.card,
              icon: Icons.credit_card_rounded,
              title: 'Card',
              subtitle: 'Debit and credit card payments',
              enabled: false,
              comingSoon: true,
            ),
            const SizedBox(height: 12),

            // Wallet — coming soon
            _paymentTile(
              method: PaymentMethod.wallet,
              icon: Icons.account_balance_wallet_rounded,
              title: 'Wallet',
              subtitle: 'Pay using your AlphaRide balance',
              enabled: false,
              comingSoon: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentTile({
    required PaymentMethod method,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    bool comingSoon = false,
  }) {
    final bool selected = enabled && method == _selectedMethod;

    return Material(
      color: enabled ? _surfaceColor : _surfaceColor.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                setState(() {
                  _selectedMethod = method;
                });
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _primaryColor : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? _primaryColor.withValues(alpha: 0.14)
                      : const Color(0xFF2B2E2B),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? _primaryColor
                      : enabled
                          ? Colors.white
                          : _mutedColor.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.48),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled
                            ? _mutedColor
                            : _mutedColor.withValues(alpha: 0.48),
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (comingSoon)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2E2B),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: const Color(0xFF3B3F3B),
                    ),
                  ),
                  child: const Text(
                    'Coming soon',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _primaryColor,
                  size: 25,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
