import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account/account_ui.dart';
import '../account/activity_screens.dart';
import '../account/feedback_screens.dart';
import '../account/profile_screens.dart';
import '../account/settings_screens.dart';
import '../account/wallet_screens.dart';
import '../services/firestore_service.dart';
import '../theme_controller.dart';

class CustomDrawer extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final FirebaseAuth auth;
  final VoidCallback? onSignOut;
  final VoidCallback? onProfileUpdated;
  final VoidCallback? onRequestOpen;

  const CustomDrawer({
    super.key,
    required this.userData,
    required this.auth,
    this.onSignOut,
    this.onProfileUpdated,
    this.onRequestOpen,
  });

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color dangerColor = Color(0xFFE5484D);
  static const Duration animationDuration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final String storedName = userData?['name']?.toString().trim() ?? '';
    final String userName = storedName.isEmpty ? 'AlphaRide user' : storedName;
    final String? authenticatedPhone = auth.currentUser?.phoneNumber;
    final String storedPhone =
        userData?['phoneNumber']?.toString().trim() ?? '';
    final String displayPhone = storedPhone.isNotEmpty
        ? storedPhone
        : authenticatedPhone ?? 'Phone unavailable';
    final String photoUrl = userData?['photoUrl']?.toString().trim() ?? '';
    final NetworkImage? avatarImage =
        photoUrl.isEmpty ? null : NetworkImage(photoUrl);
    final double rating =
        double.tryParse(userData?['rating']?.toString() ?? '') ?? 4.90;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color drawerColor =
        isDarkMode ? const Color(0xFF111311) : Colors.white;
    final Color menuTextColor =
        isDarkMode ? const Color(0xFFF5F7F5) : AlphaColors.ink;
    final Color dividerColor =
        isDarkMode ? const Color(0xFF2D302D) : const Color(0xFFE7EAE7);
    final double drawerWidth = (MediaQuery.sizeOf(context).width * 0.84)
        .clamp(290.0, 350.0)
        .toDouble();

    Future<void> openPage(
      Widget page, {
      bool refreshProfile = false,
    }) async {
      final NavigatorState navigator = Navigator.of(context);
      navigator.pop();
      final Object? result = await navigator.push<Object?>(
        MaterialPageRoute<Object?>(builder: (_) => page),
      );

      if (refreshProfile && result == true) {
        onProfileUpdated?.call();
      }

      if (!navigator.mounted || onRequestOpen == null) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) {
          onRequestOpen?.call();
        }
      });
    }

    void openPhonePage(Widget Function(String phone) builder) {
      final String? phone = authenticatedPhone;

      if (phone == null) {
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: dangerColor,
            content: Text('Please sign in again to open this page.'),
          ),
        );
        return;
      }

      openPage(builder(phone));
    }

    return Drawer(
      width: drawerWidth,
      elevation: 8,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: AnimatedContainer(
        duration: animationDuration,
        curve: Curves.easeInOutCubicEmphasized,
        color: drawerColor,
        child: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 20),
              decoration: const BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 66,
                      height: 66,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        foregroundImage: avatarImage,
                        backgroundColor: const Color(0xFFE9F0E8),
                        child: avatarImage == null
                            ? const Icon(
                                Icons.person_rounded,
                                size: 34,
                                color: AlphaColors.ink,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AlphaColors.ink,
                              fontSize: 19,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayPhone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AlphaColors.ink.withValues(alpha: 0.66),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFB000),
                            size: 17,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            rating.toStringAsFixed(2),
                            style: const TextStyle(
                              color: AlphaColors.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                        children: <Widget>[
                          _DrawerMenuItem(
                            icon: Icons.person_outline_rounded,
                            title: 'Profile',
                            foregroundColor: menuTextColor,
                            onTap: () => openPage(
                              ProfileMenuScreen(
                                auth: auth,
                                firestoreService: firestoreService,
                                initialUserData: userData,
                              ),
                              refreshProfile: true,
                            ),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.notifications_none_rounded,
                            title: 'Notifications',
                            foregroundColor: menuTextColor,
                            onTap: () => openPhonePage(
                              (String phone) => NotificationsScreen(
                                phoneNumber: phone,
                                firestoreService: firestoreService,
                              ),
                            ),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'Wallet',
                            foregroundColor: menuTextColor,
                            subtitle: '0 SSP',
                            trailing: const _MiniComingSoon(),
                            onTap: () => openPage(
                              WalletEntryScreen(
                                auth: auth,
                                firestoreService: firestoreService,
                              ),
                            ),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.route_outlined,
                            title: 'My orders',
                            foregroundColor: menuTextColor,
                            onTap: () => openPhonePage(
                              (String phone) => OrderHistoryScreen(
                                phoneNumber: phone,
                                firestoreService: firestoreService,
                              ),
                            ),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.settings_outlined,
                            title: 'Settings',
                            foregroundColor: menuTextColor,
                            onTap: () => openPage(const SettingsScreen()),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'App feedback',
                            foregroundColor: menuTextColor,
                            onTap: () => openPage(
                              FeedbackTopicScreen(
                                auth: auth,
                                firestoreService: firestoreService,
                              ),
                            ),
                          ),
                          _DrawerMenuItem(
                            icon: Icons.group_add_outlined,
                            title: 'Invite friends',
                            foregroundColor: menuTextColor,
                            onTap: () => openPage(const InviteFriendsScreen()),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Divider(color: dividerColor, height: 1),
                          ),
                          _DrawerMenuItem(
                            icon: isDarkMode
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_outlined,
                            title: isDarkMode ? 'Light mode' : 'Night mode',
                            foregroundColor: menuTextColor,
                            trailing: Transform.scale(
                              scale: 0.80,
                              child: Switch(
                                value: isDarkMode,
                                onChanged: AppThemeController.setDarkMode,
                                activeTrackColor: primaryColor,
                                activeThumbColor: AlphaColors.ink,
                                inactiveTrackColor: isDarkMode
                                    ? const Color(0xFF454945)
                                    : const Color(0xFFD8DCD8),
                                inactiveThumbColor: Colors.white,
                              ),
                            ),
                            onTap: () => AppThemeController.setDarkMode(
                              !isDarkMode,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(color: dividerColor, height: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: _DrawerMenuItem(
                        icon: Icons.logout_rounded,
                        title: 'Log out',
                        foregroundColor: dangerColor,
                        onTap: () => _handleLogout(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();

    if (onSignOut != null) {
      onSignOut!();
      return;
    }

    await auth.signOut();
    if (!navigator.mounted) return;

    navigator.pushNamedAndRemoveUntil(
      '/login',
      (Route<dynamic> route) => false,
    );
  }
}

class _DrawerMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color foregroundColor;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.foregroundColor,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Icon(icon, size: 24, color: foregroundColor),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 15.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: foregroundColor.withValues(alpha: 0.56),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniComingSoon extends StatelessWidget {
  const _MiniComingSoon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AlphaColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'SOON',
        style: TextStyle(
          color: AlphaColors.primary,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
