import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/muscle_heatmap_asset_loader.dart';
import '../domain/muscle_heatmap_color_resolver.dart';
import '../domain/muscle_heatmap_models.dart';
import '../domain/muscle_load_calculator.dart';
import 'body_svg_colorizer.dart';

class MuscleHeatmapCard extends StatelessWidget {
  const MuscleHeatmapCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rawLoads,
    required this.normalizedLoads,
    this.emptyMessage = 'Нет данных для heatmap.',
    this.showCard = true,
    this.showHeader = true,
  });

  final String title;
  final String subtitle;
  final Map<String, double> rawLoads;
  final Map<String, double> normalizedLoads;
  final String emptyMessage;
  final bool showCard;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<MuscleHeatmapAssetData>(
      future: const MuscleHeatmapAssetLoader().load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Не удалось загрузить heatmap.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        final assetData = snapshot.data!;
        final svgSource = _buildSvg(assetData);

        final content = Padding(
          padding:
              showCard ? const EdgeInsets.all(18) : const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
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
                          aspectRatio: 597.8 / 608.2,
                          child:
                              SvgPicture.string(svgSource, fit: BoxFit.contain),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        return showCard ? Card(child: content) : content;
      },
    );
  }

  String _buildSvg(MuscleHeatmapAssetData assetData) =>
      const BodySvgColorizer().colorizeFromLoads(
        assetData: assetData,
        normalizedLoads: normalizedLoads,
      );
}

class WorkoutHeatmapPreview extends StatelessWidget {
  const WorkoutHeatmapPreview({
    super.key,
    required this.rawLoads,
    required this.normalizedLoads,
    this.emptyMessage = 'Нет данных для карты нагрузки.',
    this.width,
    this.showLegend = false,
  });

  final Map<String, double> rawLoads;
  final Map<String, double> normalizedLoads;
  final String emptyMessage;
  final double? width;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          rawLoads: rawLoads,
          normalizedLoads: normalizedLoads,
          labels: assetData.zoneLabels,
          limit: 2,
        );
        final hasData = topMuscles.isNotEmpty;
        final svgSource = _buildSvg(assetData);

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
                aspectRatio: 597.8 / 608.2,
                child: SvgPicture.string(svgSource, fit: BoxFit.contain),
              ),
              if (!hasData)
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
                        (muscle) => _LegendChip(
                          label: muscle.label,
                          color: const MuscleHeatmapColorResolver()
                              .resolve(muscle.normalizedLoad),
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

  String _buildSvg(MuscleHeatmapAssetData assetData) =>
      const BodySvgColorizer().colorizeFromLoads(
        assetData: assetData,
        normalizedLoads: normalizedLoads,
      );
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 9),
      label: Text(label),
    );
  }
}
