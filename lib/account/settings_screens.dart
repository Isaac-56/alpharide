import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme_controller.dart';
import 'account_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Settings',
      child: Column(
        children: <Widget>[
          AlphaMenuTile(
            icon: Icons.brightness_6_outlined,
            title: 'App appearance',
            subtitle: 'Device, light, or dark mode',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AppAppearanceScreen(),
              ),
            ),
          ),
          AlphaMenuTile(
            icon: Icons.support_agent_rounded,
            title: 'Get in touch',
            subtitle: 'Support, legal information, and social channels',
            showDivider: false,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const GetInTouchScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppAppearanceScreen extends StatelessWidget {
  const AppAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'App appearance',
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.themeMode,
        builder: (
          BuildContext context,
          ThemeMode selectedMode,
          Widget? child,
        ) {
          return Column(
            children: <Widget>[
              _ThemeModeTile(
                icon: Icons.settings_suggest_outlined,
                title: 'Use device settings',
                subtitle: 'Follow your phone appearance automatically',
                selected: selectedMode == ThemeMode.system,
                onTap: () => AppThemeController.setThemeMode(ThemeMode.system),
              ),
              _ThemeModeTile(
                icon: Icons.light_mode_outlined,
                title: 'Light mode',
                subtitle: 'Bright, clean, and easy to read',
                selected: selectedMode == ThemeMode.light,
                onTap: () => AppThemeController.setThemeMode(ThemeMode.light),
              ),
              _ThemeModeTile(
                icon: Icons.dark_mode_outlined,
                title: 'Dark mode',
                subtitle: 'Comfortable viewing in low light',
                selected: selectedMode == ThemeMode.dark,
                showDivider: false,
                onTap: () => AppThemeController.setThemeMode(ThemeMode.dark),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool showDivider;

  const _ThemeModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return AlphaMenuTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      showDivider: showDivider,
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          color: selected ? AlphaColors.primary : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AlphaColors.primary : AlphaColors.border(context),
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(
                Icons.check_rounded,
                color: AlphaColors.ink,
                size: 18,
              )
            : null,
      ),
    );
  }
}

class GetInTouchScreen extends StatelessWidget {
  const GetInTouchScreen({super.key});

  // Add official AlphaRide channels here when they are finalized.
  static const String supportPhone = '';
  static const String supportEmail = '';
  static const String facebookUrl = '';
  static const String xUrl = '';

  Future<void> _open(
    BuildContext context,
    Uri? uri,
  ) async {
    if (uri == null) {
      showAlphaMessage(
        context,
        'This AlphaRide contact channel will be available soon.',
      );
      return;
    }

    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (opened || !context.mounted) return;

      showAlphaMessage(
        context,
        'Unable to open this contact channel.',
        error: true,
      );
    } catch (_) {
      if (!context.mounted) return;
      showAlphaMessage(
        context,
        'Unable to open this contact channel.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Get in touch',
      child: Column(
        children: <Widget>[
          AlphaMenuTile(
            icon: Icons.call_outlined,
            title: 'Call us',
            onTap: () => _open(
              context,
              supportPhone.isEmpty ? null : Uri.parse('tel:$supportPhone'),
            ),
          ),
          AlphaMenuTile(
            icon: Icons.mail_outline_rounded,
            title: 'Email us',
            onTap: () => _open(
              context,
              supportEmail.isEmpty
                  ? null
                  : Uri(
                      scheme: 'mailto',
                      path: supportEmail,
                      queryParameters: <String, String>{
                        'subject': 'AlphaRide support',
                      },
                    ),
            ),
          ),
          AlphaMenuTile(
            icon: Icons.info_outline_rounded,
            title: 'Get legal information',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const LegalInformationScreen(),
              ),
            ),
          ),
          AlphaMenuTile(
            icon: Icons.facebook_rounded,
            title: 'Facebook',
            onTap: () => _open(
              context,
              facebookUrl.isEmpty ? null : Uri.parse(facebookUrl),
            ),
          ),
          AlphaMenuTile(
            icon: Icons.alternate_email_rounded,
            title: 'X (Twitter)',
            showDivider: false,
            onTap: () => _open(
              context,
              xUrl.isEmpty ? null : Uri.parse(xUrl),
            ),
          ),
        ],
      ),
    );
  }
}

class LegalInformationScreen extends StatelessWidget {
  const LegalInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Legal information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LegalCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            body:
                'AlphaRide uses account, location, and trip information to provide passenger services, improve safety, and support your account. Your location is used only when required by an active app feature and can be controlled from your phone settings.',
          ),
          const SizedBox(height: 14),
          _LegalCard(
            icon: Icons.description_outlined,
            title: 'Terms of service',
            body:
                'By using AlphaRide, you agree to provide accurate account information, use the service responsibly, and follow local laws. Ride availability, estimates, and final fares can vary by route, traffic, and operating conditions.',
          ),
          const SizedBox(height: 14),
          _LegalCard(
            icon: Icons.health_and_safety_outlined,
            title: 'Safety',
            body:
                'Verify the driver and vehicle before entering, wear a seat belt when available, and contact local emergency services if you are in immediate danger.',
          ),
          const SizedBox(height: 18),
          Text(
            'This in-app summary is provided for convenience. Publish your final company policies and official contact details before production release.',
            style: TextStyle(
              color: AlphaColors.muted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _LegalCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AlphaColors.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AlphaColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AlphaColors.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: AlphaColors.text(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: TextStyle(
              color: AlphaColors.muted(context),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
