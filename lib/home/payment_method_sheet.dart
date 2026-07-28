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
    _selectedMethod = widget.initialMethod;
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
                    Navigator.pop(context, _selectedMethod);
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
            _paymentTile(
              method: PaymentMethod.card,
              icon: Icons.credit_card_rounded,
              title: 'Card',
              subtitle: 'Add a debit or credit card',
            ),
            const SizedBox(height: 12),
            _paymentTile(
              method: PaymentMethod.cash,
              icon: Icons.payments_rounded,
              title: 'Cash',
              subtitle: 'Pay the driver after your ride',
            ),
            const SizedBox(height: 12),
            _paymentTile(
              method: PaymentMethod.wallet,
              icon: Icons.account_balance_wallet_rounded,
              title: 'Wallet',
              subtitle: 'Use your AlphaRide balance',
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
  }) {
    final bool selected = method == _selectedMethod;

    return Material(
      color: _surfaceColor,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMethod = method;
          });
        },
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
                  color: selected ? _primaryColor : Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _mutedColor,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey<String>('selected'),
                        color: _primaryColor,
                        size: 25,
                      )
                    : const SizedBox(
                        key: ValueKey<String>('unselected'),
                        width: 25,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
