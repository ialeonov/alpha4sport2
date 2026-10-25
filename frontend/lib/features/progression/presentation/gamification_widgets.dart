import 'package:flutter/material.dart';

import '../../../core/widgets/athletic_ui.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../domain/progression_models.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Три задания недели с прогрессом и бонусом за все.
class WeeklyQuestsCard extends StatelessWidget {
  const WeeklyQuestsCard({
    super.key,
    required this.quests,
    required this.bonusXp,
  });

  final List<WeeklyQuest> quests;
  final int bonusXp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final done = quests.where((q) => q.completed).length;
    final allDone = done == quests.length;

    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Задания недели',
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                allDone
                    ? 'все выполнены · +$bonusXp XP'
                    : '$done из ${quests.length} · бонус +$bonusXp XP',
                style: textTheme.labelMedium?.copyWith(
                  color: allDone ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: allDone ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final quest in quests) ...[
            _QuestRow(quest: quest),
            if (quest != quests.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.quest});

  final WeeklyQuest quest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                quest.completed ? scheme.primary : scheme.surfaceContainerHigh,
          ),
          child: quest.completed
              ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
              : null,
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
                      quest.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: quest.completed
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    quest.completed
                        ? '+${quest.xp} XP'
                        : '${quest.progress}/${quest.target}',
                    style: textTheme.labelMedium?.copyWith(
                      color: quest.completed
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
              if (!quest.completed) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: quest.ratio,
                    minHeight: 5,
                    color: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Уровни мышц плитками: уровень крупно, полоса — путь до следующего.
class MuscleLevelsGrid extends StatelessWidget {
  const MuscleLevelsGrid({super.key, required this.levels});

  final List<MuscleLevel> levels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sorted = [...levels]..sort((a, b) => b.sets.compareTo(a.sets));
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in sorted)
              Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                decoration: BoxDecoration(
                  color: item.level > 0
                      ? scheme.surfaceContainerHigh
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatMuscleLabel(item.muscle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'УР ',
                          style: textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          '${item.level}',
                          style: TextStyle(
                            fontFamily: 'Bebas Neue Cyrillic',
                            fontSize: 28,
                            height: 1.1,
                            color: item.level > 0
                                ? scheme.primary
                                : scheme.outline,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: item.levelProgress,
                        minHeight: 4,
                        color: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.sets}/${item.nextLevelSets} подх.',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
