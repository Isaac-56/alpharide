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
