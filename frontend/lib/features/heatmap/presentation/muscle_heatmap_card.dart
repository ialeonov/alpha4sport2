import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/muscle_heatmap_asset_loader.dart';
import '../domain/muscle_heatmap_color_resolver.dart';
import '../domain/muscle_heatmap_models.dart';
import '../domain/muscle_load_calculator.dart';
import 'body_svg_colorizer.dart';

const double _svgAspectRatio = 597.8 / 608.2;

/// «12 подх.» / «2.5 подх.» — нагрузка в эффективных подходах.
String formatEffectiveSets(double value) {
  var text = value >= 10 ? value.round().toString() : value.toStringAsFixed(1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '$text подх.';
}

class MuscleHeatmapCard extends StatelessWidget {
  const MuscleHeatmapCard({
    super.key,
    required this.loads,
    this.scale = MuscleHeatmapScale.session,
    this.title = '',
    this.subtitle = '',
    this.emptyMessage = 'Нет данных для карты нагрузки.',
    this.showCard = true,
    this.showHeader = true,
    this.showLegend = true,
    this.showMuscleList = false,
    this.lastTrainedAt = const {},
  });

  /// Эффективные подходы по мышцам.
  final Map<String, double> loads;
  final MuscleHeatmapScale scale;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final bool showCard;
  final bool showHeader;
  final bool showLegend;
  final bool showMuscleList;
  final Map<String, DateTime> lastTrainedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolver = MuscleHeatmapColorResolver.of(context);

    return FutureBuilder<MuscleHeatmapAssetData>(
      future: const MuscleHeatmapAssetLoader().load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'Не удалось загрузить карту нагрузки.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        final assetData = snapshot.data!;
        final svgSource = const BodySvgColorizer().colorizeFromLoads(
          assetData: assetData,
          loads: loads,
          scale: scale,
          resolver: resolver,
        );
        final hasData = loads.values.any((v) => v >= scale.thresholds.first);

        final content = Padding(
          padding:
              showCard ? const EdgeInsets.all(18) : const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader && title.isNotEmpty) ...[
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final heatmapWidth = constraints.maxWidth.clamp(0.0, 380.0);
                    return Center(
                      child: SizedBox(
                        width: heatmapWidth,
                        child: AspectRatio(
                          aspectRatio: _svgAspectRatio,
                          child:
                              SvgPicture.string(svgSource, fit: BoxFit.contain),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!hasData) ...[
                const SizedBox(height: 12),
                Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ] else if (showLegend) ...[
                const SizedBox(height: 12),
                HeatmapLegend(scale: scale, resolver: resolver),
              ],
              if (showMuscleList && hasData) ...[
                const SizedBox(height: 16),
                _MuscleLoadList(
                  loads: loads,
                  scale: scale,
                  resolver: resolver,
                  assetData: assetData,
                  lastTrainedAt: lastTrainedAt,
                ),
              ],
            ],
          ),
        );

        return showCard ? Card(child: content) : content;
      },
    );
  }
}

class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key, required this.scale, required this.resolver});

  final MuscleHeatmapScale scale;
  final MuscleHeatmapColorResolver resolver;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var level = 1; level <= scale.thresholds.length; level++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: resolver.forLevel(level),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${scale.rangeLabel(level)} · ${scale.levelLabels[level - 1]}',
                style: style,
              ),
            ],
          ),
      ],
    );
  }
}

class _MuscleLoadList extends StatelessWidget {
  const _MuscleLoadList({
    required this.loads,
    required this.scale,
    required this.resolver,
    required this.assetData,
    required this.lastTrainedAt,
  });

  final Map<String, double> loads;
  final MuscleHeatmapScale scale;
  final MuscleHeatmapColorResolver resolver;
  final MuscleHeatmapAssetData assetData;
  final Map<String, DateTime> lastTrainedAt;

  String _label(String muscle) =>
      assetData.zoneLabels[muscle] ?? formatMuscleLabel(muscle);

  String? _sinceLabel(String muscle) {
    final last = lastTrainedAt[muscle];
    if (last == null) return null;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (days <= 0) return 'сегодня';
    if (days == 1) return 'вчера';
    return '$days дн. назад';
  }

  @override
  Widget build(BuildContext context) {
    final minLoad = scale.thresholds.first;
    final active = loads.entries.where((e) => e.value >= minLoad).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // За неделю важно видеть и пропущенные мышцы, в одной тренировке — нет.
    final idle = scale == MuscleHeatmapScale.week
        ? (assetData.zones
            .map((z) => z.muscle)
            .toSet()
            .where((m) => (loads[m] ?? 0) < minLoad)
            .toList()
          ..sort((a, b) => _label(a).compareTo(_label(b))))
        : const <String>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 3;
        const gap = 8.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in active)
              SizedBox(
                width: tileWidth,
                child: _MuscleTile(
                  label: _label(entry.key),
                  value: entry.value,
                  since: _sinceLabel(entry.key),
                  color: resolver.resolve(entry.value, scale),
                ),
              ),
            for (final muscle in idle)
              SizedBox(
                width: tileWidth,
                child: _MuscleTile(
                  label: _label(muscle),
                  value: 0,
                  since: _sinceLabel(muscle),
                  color: null,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Плитка мышцы: крупное число эффективных подходов, фон — цвет уровня.
class _MuscleTile extends StatelessWidget {
  const _MuscleTile({
    required this.label,
    required this.value,
    required this.since,
    required this.color,
  });

  final String label;
  final double value;
  final String? since;

  /// Цвет уровня нагрузки; null — мышца без нагрузки.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tint = color;
    final number = value == 0
        ? '0'
        : (value >= 10
            ? value.round().toString()
            : value.toStringAsFixed(1).replaceAll('.0', ''));
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: tint == null
            ? Colors.transparent
            : Color.alphaBlend(
                tint.withValues(alpha: 0.22),
                scheme.surfaceContainerLow,
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tint == null
              ? scheme.outlineVariant
              : tint.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tint == null ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            number,
            style: TextStyle(
              fontFamily: 'Bebas Neue Cyrillic',
              fontSize: 28,
              height: 1.1,
              color: tint == null ? scheme.outline : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            since ?? 'подходов',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutHeatmapPreview extends StatelessWidget {
  const WorkoutHeatmapPreview({
    super.key,
    required this.loads,
    this.emptyMessage = 'Нет данных для карты нагрузки.',
    this.width,
    this.showLegend = false,
  });

  final Map<String, double> loads;
  final String emptyMessage;
  final double? width;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolver = MuscleHeatmapColorResolver.of(context);
    const scale = MuscleHeatmapScale.session;
    final previewWidth = width;

    return FutureBuilder<MuscleHeatmapAssetData>(
      future: const MuscleHeatmapAssetLoader().load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: previewWidth,
            height: 148,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: previewWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              'Карта недоступна',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          );
        }

        final assetData = snapshot.data!;
        final topMuscles = const MuscleLoadCalculator().buildTopMuscles(
          loads: loads,
          labels: assetData.zoneLabels,
          limit: 2,
          minLoad: scale.thresholds.first,
        );
        final svgSource = const BodySvgColorizer().colorizeFromLoads(
          assetData: assetData,
          loads: loads,
          scale: scale,
          resolver: resolver,
        );

        return Container(
          width: previewWidth,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: _svgAspectRatio,
                child: SvgPicture.string(svgSource, fit: BoxFit.contain),
              ),
              if (topMuscles.isEmpty)
                Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                )
              else if (showLegend) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: topMuscles
                      .map(
                        (muscle) => Chip(
                          avatar: CircleAvatar(
                            backgroundColor:
                                resolver.resolve(muscle.load, scale),
                            radius: 9,
                          ),
                          label: Text(
                            '${muscle.label} · ${formatEffectiveSets(muscle.load)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
