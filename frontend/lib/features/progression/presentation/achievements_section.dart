import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../domain/progression_models.dart';

const _gold = Color(0xFFFFB300);

IconData achievementIcon(String code) {
  final c = code.toLowerCase();
  if (c.contains('streak')) return Icons.local_fire_department_rounded;
  if (c.contains('pr') || c.contains('record')) {
    return Icons.emoji_events_rounded;
  }
  if (c.contains('month')) return Icons.calendar_month_rounded;
  if (c.contains('week')) return Icons.date_range_rounded;
  if (c.contains('workout')) return Icons.fitness_center_rounded;
  return Icons.star_rounded;
}

/// Достижения: счётчик, ближайшие цели с прогрессом и полный список.
class AchievementsSection extends StatelessWidget {
  const AchievementsSection({super.key, required this.profile});

  final ProgressionProfileData profile;

  @override
  Widget build(BuildContext context) {
    final catalog = profile.achievementCatalog;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (catalog.isEmpty) {
      // Старый сервер без каталога — показываем только полученные.
      return Column(
        children: [
          for (final item in profile.recentAchievements)
            _AchievementTile(
              code: item.code,
              title: item.title,
              subtitle: formatShortDate(item.achievedAt),
              unlocked: true,
            ),
        ],
      );
    }

    final unlocked = catalog.where((a) => a.unlocked).length;
    final nextGoals = catalog.where((a) => !a.unlocked).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Получено $unlocked из ${catalog.length}',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (nextGoals.isNotEmpty) ...[
          Text(
            'Ближайшие цели',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final item in nextGoals.take(3)) _CatalogTile(item: item),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showAll(context, catalog),
            icon: const Icon(Icons.grid_view_rounded, size: 18),
            label: const Text('Все достижения'),
          ),
        ),
      ],
    );
  }

  void _showAll(BuildContext context, List<AchievementCatalogItem> catalog) {
    final sorted = [
      ...catalog.where((a) => a.unlocked),
      ...catalog.where((a) => !a.unlocked).toList()
        ..sort((a, b) => b.ratio.compareTo(a.ratio)),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Достижения',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final item in sorted) _CatalogTile(item: item),
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.item});

  final AchievementCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.unlocked
        ? (item.achievedAt != null
            ? 'Получено ${formatShortDate(item.achievedAt!)}'
            : 'Получено')
        : item.description;
    return _AchievementTile(
      code: item.code,
      title: item.title,
      subtitle: subtitle,
      unlocked: item.unlocked,
      progress: item.unlocked || item.target <= 1 ? null : item.ratio,
      progressLabel:
          item.unlocked || item.target <= 1 ? null : '${item.progress}/${item.target}',
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    this.progress,
    this.progressLabel,
  });

  final String code;
  final String title;
  final String subtitle;
  final bool unlocked;
  final double? progress;
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = unlocked ? _gold : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: unlocked ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              unlocked ? achievementIcon(code) : Icons.lock_outline_rounded,
              size: 19,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: unlocked ? null : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (progressLabel != null)
                      Text(
                        progressLabel!,
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: _gold,
                      backgroundColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
