import 'package:flutter/material.dart';

abstract final class AlphaColors {
  static const Color primary = Color(0xFF39FF14);
  static const Color ink = Color(0xFF101310);
  static const Color darkBackground = Color(0xFF101210);
  static const Color darkSurface = Color(0xFF202320);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFFFB020);

  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBackground
          : const Color(0xFFF8FAF8);

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurface
          : Colors.white;

  static Color text(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF7F9F7)
          : ink;

  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9DA39D)
          : const Color(0xFF6B716B);

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF303430)
          : const Color(0xFFE4E8E4);
}

class AlphaPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  final VoidCallback? onBack;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final FloatingActionButton? floatingActionButton;

  const AlphaPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.onBack,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(22, 12, 22, 28),
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = scrollable
        ? SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: padding,
            child: child,
          )
        : Padding(
            padding: padding,
            child: child,
          );

    return Scaffold(
      backgroundColor: AlphaColors.background(context),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Row(
                children: <Widget>[
                  AlphaBackButton(onPressed: onBack),
                  const Spacer(),
                  if (action != null) action!,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: AlphaColors.text(context),
                    fontSize: 30,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class AlphaBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool closeIcon;

  const AlphaBackButton({
    super.key,
    this.onPressed,
    this.closeIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AlphaColors.surface(context),
      shape: CircleBorder(
        side: BorderSide(color: AlphaColors.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed ?? () => Navigator.maybePop(context),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            closeIcon ? Icons.close_rounded : Icons.arrow_back_rounded,
            color: AlphaColors.text(context),
            size: 27,
          ),
        ),
      ),
    );
  }
}

class AlphaMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showDivider;
  final Color? iconColor;

  const AlphaMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.showDivider = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = enabled
        ? AlphaColors.text(context)
        : AlphaColors.muted(context).withValues(alpha: 0.58);

    return Column(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: enabled
                          ? AlphaColors.primary.withValues(alpha: 0.11)
                          : AlphaColors.border(context).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: enabled
                          ? iconColor ?? AlphaColors.text(context)
                          : foreground,
                      size: 23,
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
                            color: foreground,
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: AlphaColors.muted(context),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailingText != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Text(
                      trailingText!,
                      style: TextStyle(
                        color: AlphaColors.muted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 10),
                    trailing!,
                  ] else if (enabled && onTap != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AlphaColors.muted(context),
                      size: 24,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 60,
            color: AlphaColors.border(context),
          ),
      ],
    );
  }
}

class AlphaComingSoonBadge extends StatelessWidget {
  final bool compact;

  const AlphaComingSoonBadge({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: AlphaColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AlphaColors.primary.withValues(alpha: 0.32),
        ),
      ),
      child: const Text(
        'Coming soon',
        style: TextStyle(
          color: AlphaColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AlphaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AlphaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 82,
              height: 82,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AlphaColors.primary.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AlphaColors.primary, size: 38),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AlphaColors.text(context),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AlphaColors.muted(context),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class AlphaPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const AlphaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AlphaColors.ink,
                ),
              )
            : icon == null
                ? const SizedBox.shrink()
                : Icon(icon, size: 21),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AlphaColors.primary,
          foregroundColor: AlphaColors.ink,
          disabledBackgroundColor: AlphaColors.primary.withValues(alpha: 0.45),
          disabledForegroundColor: AlphaColors.ink.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

InputDecoration alphaInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  IconData? prefixIcon,
}) {
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: AlphaColors.border(context)),
  );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
    filled: true,
    fillColor: AlphaColors.surface(context),
    labelStyle: TextStyle(color: AlphaColors.muted(context)),
    hintStyle: TextStyle(color: AlphaColors.muted(context)),
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AlphaColors.primary, width: 1.6),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: AlphaColors.danger),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: const BorderSide(color: AlphaColors.danger, width: 1.6),
    ),
  );
}

void showAlphaMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? AlphaColors.danger : null,
        content: Text(message),
      ),
    );
}
