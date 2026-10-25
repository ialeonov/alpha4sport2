import 'package:flutter/material.dart';

import '../../progression/domain/progression_models.dart';
import '../../progression/presentation/achievements_section.dart';
import '../domain/workout_metrics.dart';

const _gold = Color(0xFFFFB300);

/// Итог тренировки: что сделано и что это дало в прогрессии.
///
/// [before]/[after] — профиль прогрессии до и после сохранения. Если профиль
/// недоступен (офлайн), показываем только статистику тренировки.
Future<void> showWorkoutCompletionSheet(
  BuildContext context, {
  required Map<String, dynamic> workout,
  required ProgressionProfileData? before,
  required ProgressionProfileData? after,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WorkoutCompletionSheet(
      workout: workout,
      before: before,
      after: after,
    ),
  );
}

class _WorkoutCompletionSheet extends StatelessWidget {
  const _WorkoutCompletionSheet({
    required this.workout,
    required this.before,
    required this.after,
  });

  final Map<String, dynamic> workout;
  final ProgressionProfileData? before;
  final ProgressionProfileData? after;

  int get _workingSets {
    var count = 0;
    for (final exercise in (workout['exercises'] as List? ?? const [])) {
      for (final set in ((exercise as Map)['sets'] as List? ?? const [])) {
        final s = set as Map;
        final reps = (s['reps'] as num?) ?? 0;
        if (reps > 0 && s['set_type'] != 'warmup') count++;
      }
    }
    return count;
  }

  int? get _durationMinutes {
    final start = DateTime.tryParse((workout['started_at'] ?? '').toString());
    final end = DateTime.tryParse((workout['finished_at'] ?? '').toString());
    if (start == null || end == null) return null;
    final minutes = end.difference(start).inMinutes;
    return minutes > 0 ? minutes : null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final b = before;
    final a = after;

    final xpGained = (a != null && b != null) ? a.totalXp - b.totalXp : null;
    final levelUp = a != null && b != null && a.level > b.level;
    final newPrCount =
        (a != null && b != null) ? (a.totalPrCount - b.totalPrCount) : 0;
    final newRecords =
        a == null || newPrCount <= 0 ? const <RecordData>[] : a.recentRecords.take(newPrCount).toList();
    final unlockedBefore = {
      for (final item in b?.achievementCatalog ?? const <AchievementCatalogItem>[])
        if (item.unlocked) item.code,
    };
    final newAchievements = b == null
        ? const <AchievementCatalogItem>[]
        : (a?.achievementCatalog ?? const <AchievementCatalogItem>[])
            .where((item) => item.unlocked && !unlockedBefore.contains(item.code))
            .toList();
    final duration = _durationMinutes;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Тренировка завершена',
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              (workout['name'] ?? '').toString(),
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(value: '$_workingSets', label: 'рабочих подходов'),
                _Stat(
                  value: formatTonnage(calculateWorkoutTonnage(workout)),
                  label: 'тоннаж',
                ),
                if (duration != null) _Stat(value: '$duration', label: 'минут'),
              ],
            ),
            if (xpGained != null && xpGained > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _gold.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: _gold, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+$xpGained XP',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: _gold,
                            ),
                          ),
                          Text(
                            levelUp
                                ? 'Новый уровень ${a.level} — ${a.title}!'
                                : 'До уровня ${a!.level + 1}: ${a.xpRemainingToNextLevel} XP',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (a != null) ...[
              const SizedBox(height: 12),
              _WeekProgress(profile: a),
            ],
            if (newRecords.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Новые рекорды',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final record in newRecords)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded, color: _gold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${record.exerciseName} — ${record.recordLabel.toLowerCase()}',
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (newAchievements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Новые достижения',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final item in newAchievements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(achievementIcon(item.code), color: _gold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.title, style: textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отлично'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekProgress extends StatelessWidget {
  const _WeekProgress({required this.profile});

  final ProgressionProfileData profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final count = profile.currentWeek.workoutCount;
    // Неделя засчитывается в серию с 2 тренировок, идеальная — с 3.
    final String hint;
    if (count >= 3) {
      hint = 'Идеальная неделя! Серия: ${profile.currentStreak} нед.';
    } else if (count == 2) {
      hint = 'Неделя засчитана в серию. Ещё одна — и она идеальная.';
    } else {
      hint = 'Ещё одна тренировка на этой неделе — и она пойдёт в серию.';
    }
    return Row(
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= count ? scheme.primary : scheme.surfaceContainerHighest,
            ),
            child: i <= count
                ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
                : null,
          ),
        const SizedBox(width: 6),
        Expanded(child: Text(hint, style: textTheme.bodySmall)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          Text(
            label,
            style: textTheme.labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
