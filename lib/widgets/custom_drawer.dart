import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme_controller.dart';

class CustomDrawer extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final FirebaseAuth auth;
  final VoidCallback? onSignOut;

  const CustomDrawer({
    super.key,
    required this.userData,
    required this.auth,
    this.onSignOut,
  });

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color dangerColor = Color(0xFFE5484D);
  static const Duration themeAnimationDuration = Duration(
    milliseconds: 600,
  );

  @override
  Widget build(BuildContext context) {
    final String storedName = userData?['name']?.toString().trim() ?? '';
    final String userName = storedName.isEmpty ? 'User' : storedName;

    final String storedPhone =
        userData?['phoneNumber']?.toString().trim() ?? '';

    final String phoneNumber = storedPhone.isNotEmpty
        ? storedPhone
        : auth.currentUser?.phoneNumber ?? 'Phone unavailable';

    final String photoUrl = userData?['photoUrl']?.toString().trim() ?? '';

    final NetworkImage? avatarImage =
        photoUrl.isEmpty ? null : NetworkImage(photoUrl);

    final double rating = double.tryParse(
          userData?['rating']?.toString() ?? '',
        ) ??
        4.90;

    final double drawerWidth = (MediaQuery.sizeOf(context).width * 0.82)
        .clamp(280.0, 340.0)
        .toDouble();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (
        BuildContext context,
        ThemeMode themeMode,
        Widget? child,
      ) {
        final bool isDarkMode = themeMode == ThemeMode.dark;

        final Color drawerColor =
            isDarkMode ? const Color(0xFF111311) : Colors.white;

        final Color menuTextColor =
            isDarkMode ? const Color(0xFFF5F7F5) : textColor;

        final Color secondaryTextColor =
            isDarkMode ? const Color(0xFFA7ACA7) : const Color(0xFF6B6F6B);

        final Color dividerColor =
            isDarkMode ? const Color(0xFF2D302D) : const Color(0xFFE7EAE7);

        return Drawer(
          width: drawerWidth,
          elevation: 4,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: AnimatedContainer(
            duration: themeAnimationDuration,
            curve: Curves.easeInOutCubicEmphasized,
            decoration: BoxDecoration(
              color: drawerColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Compact profile section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    16,
                    16,
                    20,
                  ),
                  decoration: const BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.only(
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
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
                                    color: textColor,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                phoneNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF30402D),
                                  fontSize: 13.5,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Rating badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFB000),
                                size: 18,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Menu and bottom logout section
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              12,
                              18,
                              12,
                              12,
                            ),
                            child: Column(
                              children: [
                                _DrawerMenuItem(
                                  icon: Icons.person_outline_rounded,
                                  title: 'Profile',
                                  foregroundColor: menuTextColor,
                                  secondaryColor: secondaryTextColor,
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                ),
                                _DrawerMenuItem(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'My orders',
                                  foregroundColor: menuTextColor,
                                  secondaryColor: secondaryTextColor,
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                ),
                                _DrawerMenuItem(
                                  icon: Icons.local_offer_outlined,
                                  title: 'Promo',
                                  foregroundColor: menuTextColor,
                                  secondaryColor: secondaryTextColor,
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                ),
                                _DrawerMenuItem(
                                  icon: Icons.settings_outlined,
                                  title: 'Settings',
                                  foregroundColor: menuTextColor,
                                  secondaryColor: secondaryTextColor,
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                ),

                                // Animated night-mode control
                                _DrawerMenuItem(
                                  icon: isDarkMode
                                      ? Icons.light_mode_rounded
                                      : Icons.dark_mode_outlined,
                                  title: 'Night mode',
                                  foregroundColor: menuTextColor,
                                  secondaryColor: secondaryTextColor,
                                  onTap: () {
                                    AppThemeController.setDarkMode(
                                      !isDarkMode,
                                    );
                                  },
                                  trailing: Transform.scale(
                                    scale: 0.82,
                                    child: Switch(
                                      value: isDarkMode,
                                      onChanged:
                                          AppThemeController.setDarkMode,
                                      activeTrackColor: primaryColor,
                                      activeThumbColor: textColor,
                                      inactiveTrackColor: isDarkMode
                                          ? const Color(0xFF454945)
                                          : const Color(0xFFD8DCD8),
                                      inactiveThumbColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Bottom-pinned divider and logout
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          child: AnimatedContainer(
                            duration: themeAnimationDuration,
                            curve: Curves.easeInOutCubicEmphasized,
                            height: 1,
                            color: dividerColor,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            12,
                            10,
                            12,
                            8,
                          ),
                          child: _DrawerMenuItem(
                            icon: Icons.logout_rounded,
                            title: 'Log out',
                            foregroundColor: dangerColor,
                            secondaryColor: dangerColor,
                            onTap: () {
                              _handleLogout(context);
                            },
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
      },
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
  final Color foregroundColor;
  final Color secondaryColor;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.foregroundColor,
    required this.secondaryColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: foregroundColor,
                      ),
                      duration: CustomDrawer.themeAnimationDuration,
                      curve: Curves.easeInOutCubicEmphasized,
                      builder: (
                        BuildContext context,
                        Color? animatedColor,
                        Widget? child,
                      ) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (
                            Widget child,
                            Animation<double> animation,
                          ) {
                            return FadeTransition(
                              opacity: animation,
                              child: RotationTransition(
                                turns: Tween<double>(
                                  begin: -0.15,
                                  end: 0,
                                ).animate(animation),
                                child: ScaleTransition(
                                  scale: animation,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Icon(
                            icon,
                            key: ValueKey<IconData>(icon),
                            size: 25,
                            color: animatedColor ?? foregroundColor,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: CustomDrawer.themeAnimationDuration,
                      curve: Curves.easeInOutCubicEmphasized,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 16.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      child: Text(title),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
