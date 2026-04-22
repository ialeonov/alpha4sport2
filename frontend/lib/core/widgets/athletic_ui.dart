import 'package:flutter/material.dart';
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE8C7AA)
        : Theme.of(context).colorScheme.onSurface;
    const style = TextStyle(
      fontFamily: 'Bebas Neue Cyrillic',
      fontSize: 44,
      letterSpacing: 2,
      height: 1,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tp = TextPainter(
            text: TextSpan(text: text.toUpperCase(), style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: double.infinity);
          final scaleX = constraints.maxWidth / tp.width;
          return SizedBox(
            width: constraints.maxWidth,
            height: tp.height,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: 1.0,
              alignment: Alignment.centerLeft,
              child: Text(
                text.toUpperCase(),
                style: style.copyWith(color: color),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DashboardSectionLabel extends StatelessWidget {
  const DashboardSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 28,
    this.color,
    this.borderColor,
    this.leftAccentColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final Color? leftAccentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(padding: padding, child: child);

    Widget inner = leftAccentColor != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: leftAccentColor),
                  Expanded(child: content),
                ],
              ),
            ),
          )
        : content;

    if (onTap != null) {
      inner = InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: inner,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: color ??
            Color.alphaBlend(
              scheme.secondary.withValues(alpha: 0.07),
              scheme.surfaceContainerLow,
            ),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: inner,
      ),
    );
  }
}

class DashboardSummaryCard extends StatelessWidget {
  const DashboardSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.bottom,
    this.padding = const EdgeInsets.all(22),
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? bottom;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              scheme.secondary.withValues(alpha: 0.14),
              scheme.surfaceContainer,
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.14),
              scheme.surfaceContainerLow,
            ),
          ],
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 16),
                  trailing!,
                ],
              ],
            ),
            if (bottom != null) ...[
              const SizedBox(height: 18),
              bottom!,
            ],
          ],
        ),
      ),
    );
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class MetricBadge extends StatelessWidget {
  const MetricBadge({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 14 : 16, color: color),
            SizedBox(width: compact ? 6 : 8),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
