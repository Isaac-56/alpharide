import 'package:flutter/material.dart';

import '../theme/alpha_theme.dart';

class AlphaSheetHandle extends StatelessWidget {
  const AlphaSheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 48,
      height: 5,
      decoration: BoxDecoration(
        color: context.alphaBorder,
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

class AlphaFlowHeader extends StatelessWidget {
  const AlphaFlowHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      if (leading != null) ...<Widget>[
        leading!,
        const SizedBox(width: 14),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(letterSpacing: -0.45),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) ...<Widget>[
        const SizedBox(width: 12),
        trailing!,
      ],
    ],
  );
}

class AlphaSurfaceCard extends StatelessWidget {
  const AlphaSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Material(
    color: context.alphaSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AlphaSpacing.cardRadius),
      side: BorderSide(
        color: highlighted ? AlphaColors.primary : context.alphaBorder,
        width: highlighted ? 2 : 1,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class AlphaMetricChip extends StatelessWidget {
  const AlphaMetricChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: emphasized
          ? AlphaColors.primary.withValues(alpha: 0.18)
          : context.alphaSoftSurface,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 17, color: context.alphaInk),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: context.alphaInk,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class AlphaMapSheet extends StatelessWidget {
  const AlphaMapSheet({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.showHandle = true,
    this.constraints,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool showHandle;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: constraints,
    decoration: BoxDecoration(
      color: context.alphaCanvas,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AlphaSpacing.sheetRadius),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(
            alpha: context.isDarkMode ? 0.28 : 0.10,
          ),
          blurRadius: 30,
          offset: const Offset(0, -8),
        ),
      ],
    ),
    child: Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showHandle) ...<Widget>[
            const AlphaSheetHandle(),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    ),
  );
}

class AlphaFlowProgress extends StatelessWidget {
  const AlphaFlowProgress({
    required this.currentStep,
    required this.totalSteps,
    this.label,
    super.key,
  });

  final int currentStep;
  final int totalSteps;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final int safeTotal = totalSteps < 1 ? 1 : totalSteps;
    final int safeStep = currentStep.clamp(0, safeTotal).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: safeStep / safeTotal,
            minHeight: 5,
            color: AlphaColors.primary,
            backgroundColor: context.alphaSoftSurface,
          ),
        ),
      ],
    );
  }
}

class AlphaStatusPill extends StatelessWidget {
  const AlphaStatusPill({required this.label, this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: AlphaColors.primary.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: context.alphaInk),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: context.alphaInk,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class AlphaRouteRow extends StatelessWidget {
  const AlphaRouteRow({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AlphaSpacing.controlHeight),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: context.alphaSoftSurface,
      borderRadius: BorderRadius.circular(AlphaSpacing.controlRadius),
    ),
    child: Row(
      children: <Widget>[
        Icon(icon, size: 19, color: context.alphaMuted),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
