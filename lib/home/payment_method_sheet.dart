import 'package:flutter/material.dart';

import '../account/account_ui.dart';
import '../models/ride_option.dart';

const Color _primaryColor = Color(0xFF39FF14);

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
    _selectedMethod = widget.initialMethod == PaymentMethod.cash
        ? widget.initialMethod
        : PaymentMethod.cash;
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = AlphaColors.background(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(
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
                color: AlphaColors.border(context),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment method',
                    style: TextStyle(
                      color: AlphaColors.text(context),
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
    final Color surfaceColor = AlphaColors.surface(context);
    final Color mutedColor = AlphaColors.muted(context);
    final Color textColor = AlphaColors.text(context);

    return Material(
      color: enabled ? surfaceColor : surfaceColor.withValues(alpha: 0.62),
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
                      : AlphaColors.border(context).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? _primaryColor
                      : enabled
                          ? textColor
                          : mutedColor.withValues(alpha: 0.55),
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
                            ? textColor
                            : textColor.withValues(alpha: 0.48),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled
                            ? mutedColor
                            : mutedColor.withValues(alpha: 0.48),
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
                    color: AlphaColors.border(context).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AlphaColors.border(context),
                    ),
                  ),
                  child: Text(
                    'Coming soon',
                    style: TextStyle(
                      color: mutedColor,
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
