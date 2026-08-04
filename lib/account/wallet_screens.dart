import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ride_option.dart';
import '../services/firestore_service.dart';
import 'account_ui.dart';

class WalletEntryScreen extends StatefulWidget {
  final FirebaseAuth auth;
  final FirestoreService firestoreService;

  const WalletEntryScreen({
    super.key,
    required this.auth,
    required this.firestoreService,
  });

  @override
  State<WalletEntryScreen> createState() => _WalletEntryScreenState();
}

class _WalletEntryScreenState extends State<WalletEntryScreen> {
  static const String _introKey = 'alpha_wallet_intro_seen';

  bool? _introSeen;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    if (!mounted) return;
    setState(() => _introSeen = preferences.getBool(_introKey) ?? false);
  }

  Future<void> _finishIntro() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_introKey, true);

    if (!mounted) return;
    setState(() => _introSeen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_introSeen == null) {
      return Scaffold(
        backgroundColor: AlphaColors.background(context),
        body: const Center(
          child: CircularProgressIndicator(color: AlphaColors.primary),
        ),
      );
    }

    if (_introSeen == false) {
      return WalletIntroScreen(onContinue: _finishIntro);
    }

    return WalletScreen(
      auth: widget.auth,
      firestoreService: widget.firestoreService,
    );
  }
}

class WalletIntroScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const WalletIntroScreen({
    super.key,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlphaColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Material(
                    color: Colors.white.withValues(alpha: 0.30),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AlphaColors.ink,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AlphaColors.ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'COMING SOON',
                      style: TextStyle(
                        color: AlphaColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'A safer way to pay is on the way',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AlphaColors.ink,
                  fontSize: 30,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'AlphaRide Wallet is being prepared for South Sudan. Cash remains available for every ride today.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AlphaColors.ink.withValues(alpha: 0.70),
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const _WalletShieldIllustration(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AlphaColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: const Text(
                    'Explore wallet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletShieldIllustration extends StatelessWidget {
  const _WalletShieldIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      height: 230,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AlphaColors.ink.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            Icons.shield_rounded,
            color: Colors.white.withValues(alpha: 0.96),
            size: 170,
          ),
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: AlphaColors.ink,
            size: 66,
          ),
          const Positioned(
            bottom: 56,
            right: 58,
            child: CircleAvatar(
              radius: 19,
              backgroundColor: AlphaColors.primary,
              child: Icon(
                Icons.lock_rounded,
                color: AlphaColors.ink,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WalletScreen extends StatelessWidget {
  final FirebaseAuth auth;
  final FirestoreService firestoreService;

  const WalletScreen({
    super.key,
    required this.auth,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Wallet',
      action: TextButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const AboutWalletScreen(),
          ),
        ),
        child: const Text(
          'About wallet',
          style: TextStyle(
            color: AlphaColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AlphaColors.surface(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AlphaColors.border(context)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'AlphaRide South Sudan',
                        style: TextStyle(
                          color: AlphaColors.muted(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const AlphaComingSoonBadge(compact: true),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '0 SSP',
                  style: TextStyle(
                    color: AlphaColors.text(context),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AlphaColors.border(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: AlphaColors.muted(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Top up',
                          style: TextStyle(
                            color: AlphaColors.muted(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Available later',
                          style: TextStyle(
                            color: AlphaColors.muted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          AlphaMenuTile(
            icon: Icons.payment_rounded,
            title: 'Payment methods',
            subtitle: 'Cash available; Card and Wallet coming soon',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const WalletPaymentMethodsScreen(),
              ),
            ),
          ),
          const AlphaMenuTile(
            icon: Icons.volunteer_activism_outlined,
            title: 'Default tips',
            subtitle: 'Digital tips will be available later',
            enabled: false,
            trailing: AlphaComingSoonBadge(compact: true),
          ),
          AlphaMenuTile(
            icon: Icons.receipt_long_outlined,
            title: 'Transactions',
            showDivider: false,
            onTap: () {
              final String? phone = auth.currentUser?.phoneNumber;

              if (phone == null) {
                showAlphaMessage(
                  context,
                  'Please sign in again to view transactions.',
                  error: true,
                );
                return;
              }

              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WalletTransactionsScreen(
                    phoneNumber: phone,
                    firestoreService: firestoreService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class WalletPaymentMethodsScreen extends StatelessWidget {
  const WalletPaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Payment methods',
      child: Column(
        children: <Widget>[
          _WalletPaymentTile(
            icon: Icons.payments_rounded,
            title: 'Cash',
            subtitle: 'Pay your driver after the ride',
            selected: true,
            enabled: true,
          ),
          const SizedBox(height: 12),
          const _WalletPaymentTile(
            icon: Icons.credit_card_rounded,
            title: 'Card',
            subtitle: 'Debit and credit cards',
            selected: false,
            enabled: false,
          ),
          const SizedBox(height: 12),
          const _WalletPaymentTile(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Wallet',
            subtitle: 'Pay from your AlphaRide balance',
            selected: false,
            enabled: false,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AlphaColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AlphaColors.primary.withValues(alpha: 0.26),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.info_outline_rounded,
                  color: AlphaColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AlphaRide currently accepts cash only. Card and Wallet are disabled until secure digital payments launch.',
                    style: TextStyle(
                      color: AlphaColors.muted(context),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletPaymentTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;

  const _WalletPaymentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = enabled
        ? AlphaColors.text(context)
        : AlphaColors.muted(context).withValues(alpha: 0.58);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: enabled
            ? AlphaColors.surface(context)
            : AlphaColors.surface(context).withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AlphaColors.primary : AlphaColors.border(context),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AlphaColors.primary.withValues(alpha: 0.14)
                  : AlphaColors.border(context).withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: selected ? AlphaColors.primary : textColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AlphaColors.muted(context),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (enabled)
            const Icon(
              Icons.check_circle_rounded,
              color: AlphaColors.primary,
              size: 26,
            )
          else
            const AlphaComingSoonBadge(compact: true),
        ],
      ),
    );
  }
}

class AboutWalletScreen extends StatelessWidget {
  const AboutWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'About wallet',
      child: const Column(
        children: <Widget>[
          _WalletQuestion(
            question: 'What is AlphaRide Wallet?',
            answer:
                'AlphaRide Wallet is a planned digital balance for passenger payments in South Sudan. Until it launches, every AlphaRide trip remains cash-only.',
          ),
          _WalletQuestion(
            question: 'Can I top up now?',
            answer:
                'Not yet. Top-ups, cards, and Wallet payments stay disabled while secure payment partners and customer protections are finalized.',
          ),
          _WalletQuestion(
            question: 'What currency will it use?',
            answer:
                'Wallet balances, transactions, and ride payments will be shown in South Sudanese pounds (SSP).',
          ),
          _WalletQuestion(
            question: 'Will my Wallet balance expire?',
            answer:
                'Final Wallet terms will be published before launch. AlphaRide will clearly explain balance, refund, and expiry rules before customers can add money.',
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _WalletQuestion extends StatelessWidget {
  final String question;
  final String answer;
  final bool showDivider;

  const _WalletQuestion({
    required this.question,
    required this.answer,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.menu_book_outlined,
                color: AlphaColors.primary,
                size: 23,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  question,
                  style: TextStyle(
                    color: AlphaColors.text(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            answer,
            style: TextStyle(
              color: AlphaColors.muted(context),
              fontSize: 14.5,
              height: 1.58,
            ),
          ),
          if (showDivider) ...<Widget>[
            const SizedBox(height: 20),
            Divider(color: AlphaColors.border(context), height: 1),
          ],
        ],
      ),
    );
  }
}

class WalletTransactionsScreen extends StatelessWidget {
  final String phoneNumber;
  final FirestoreService firestoreService;

  const WalletTransactionsScreen({
    super.key,
    required this.phoneNumber,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Transactions',
      scrollable: false,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firestoreService.watchWalletTransactions(phoneNumber),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AlphaColors.primary),
            );
          }

          if (snapshot.hasError) {
            return const AlphaEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Transactions are unavailable',
              message: 'Check your connection and try this page again.',
            );
          }

          final List<Map<String, dynamic>> transactions =
              snapshot.data ?? <Map<String, dynamic>>[];

          if (transactions.isEmpty) {
            return const AlphaEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message:
                  'Your Wallet history will appear here after digital payments launch.',
            );
          }

          return ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              return _TransactionTile(data: transactions[index]);
            },
          );
        },
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TransactionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final int amount = (data['amount'] as num?)?.round() ?? 0;
    final bool credit = amount >= 0;
    final Timestamp? createdAt = data['createdAt'] as Timestamp?;
    final DateTime? date = createdAt?.toDate();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AlphaColors.surface(context),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AlphaColors.border(context)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: (credit ? AlphaColors.primary : AlphaColors.danger)
                .withValues(alpha: 0.12),
            child: Icon(
              credit ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: credit ? AlphaColors.primary : AlphaColors.danger,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data['title']?.toString() ?? 'Wallet transaction',
                  style: TextStyle(
                    color: AlphaColors.text(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date == null
                      ? 'Processing'
                      : '${date.day}/${date.month}/${date.year}',
                  style: TextStyle(
                    color: AlphaColors.muted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${credit ? '+' : '-'}${RideOption.formatAmount(amount.abs())} SSP',
            style: TextStyle(
              color: credit ? AlphaColors.primary : AlphaColors.text(context),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
