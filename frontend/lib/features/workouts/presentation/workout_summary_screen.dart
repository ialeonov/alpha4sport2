import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../heatmap/data/heatmap_reference_workouts.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/muscle_heatmap_card.dart';
import '../application/workout_share_service.dart';
import '../domain/workout_metrics.dart';
import '../domain/workout_summary.dart';
import 'workout_form_screen.dart';

/// Сводка завершённой тренировки: что сделано, что выросло, какие мышцы
/// работали. Правка — по кнопке «Изменить».
///
/// Возвращает true, если тренировку изменили или удалили.
class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({super.key, required this.workout});

  final Map<String, dynamic> workout;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  List<Map<String, dynamic>> _history = const [];
  List<Map<String, dynamic>> _catalog = const [];

  @override
  void initState() {
    super.initState();
    _history = _cachedList(CacheKeys.workoutsCache) ?? const [];
    _catalog = _cachedList(CacheKeys.exerciseCatalogCache) ?? const [];
    _load();
  }

  List<Map<String, dynamic>>? _cachedList(String key) {
    return LocalCache.get<List>(key)
        ?.cast<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        if (_history.isEmpty) BackendApi.getWorkouts(),
        if (_catalog.isEmpty) BackendApi.getExercises(),
      ]);
      if (!mounted || results.isEmpty) return;
      var index = 0;
      setState(() {
        if (_history.isEmpty) _history = results[index++];
        if (_catalog.isEmpty) _catalog = results[index++];
      });
    } catch (_) {
      // Без истории сводка всё равно покажет подходы — без сравнения.
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormScreen(initialWorkout: widget.workout),
      ),
    );
    if (changed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _share() {
    return WorkoutShareService.share(
      context: context,
      workout: widget.workout,
      exerciseCatalog: _catalog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workout = widget.workout;
    final summary = buildWorkoutSummary(workout: workout, history: _history);
    final startedAt =
        DateTime.tryParse((workout['started_at'] ?? '').toString())?.toLocal();
    final finishedAt =
        DateTime.tryParse((workout['finished_at'] ?? '').toString())?.toLocal();
    final minutes = startedAt != null && finishedAt != null
        ? finishedAt.difference(startedAt).inMinutes
        : 0;
    final notes = (workout['notes'] ?? '').toString().trim();
    final loads = const MuscleLoadCalculator().calculateForWorkout(
      workout: workout,
      exerciseCatalog: _catalog,
      referenceWorkouts: cachedHeatmapReferenceWorkouts(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (workout['name'] ?? 'Тренировка').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Поделиться карточкой',
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Изменить'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (startedAt != null)
              Text(
                _dateLine(startedAt, finishedAt),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (minutes > 0) ...[
                  Expanded(child: _StatTile(value: '$minutes', label: 'минут')),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _StatTile(
                    value: '${summary.workingSets}',
                    label: 'подходов',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    value: formatTonnage(calculateWorkoutTonnage(workout)),
                    label: 'тоннаж',
                  ),
                ),
              ],
            ),
            if (summary.records > 0 || summary.improved > 0) ...[
              const SizedBox(height: 8),
              _HighlightsCard(
                records: summary.records,
                improved: summary.improved,
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              DashboardCard(
                padding: const EdgeInsets.all(14),
                child: Text(notes),
              ),
            ],
            const SizedBox(height: 16),
            const DashboardSectionLabel('Упражнения'),
            const SizedBox(height: 8),
            for (final exercise in summary.exercises) ...[
              _ExerciseCard(exercise: exercise),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            const DashboardSectionLabel('Нагрузка на мышцы'),
            const SizedBox(height: 8),
            MuscleHeatmapCard(loads: loads, showHeader: false),
          ],
        ),
      ),
    );
  }

  static String _dateLine(DateTime start, DateTime? finish) {
    const weekdays = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    String time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    final date = '${weekdays[start.weekday - 1]}, ${start.day} '
        '${months[start.month - 1]}';
    return finish == null
        ? '$date · ${time(start)}'
        : '$date · ${time(start)}–${time(finish)}';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.records, required this.improved});

  final int records;
  final int improved;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = [
      if (records > 0) _plural(records, 'рекорд', 'рекорда', 'рекордов'),
      if (improved > 0)
        'выросло ${_plural(improved, 'упражнение', 'упражнения', 'упражнений')}',
    ];
    return DashboardCard(
      padding: const EdgeInsets.all(14),
      color: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.10),
        scheme.surfaceContainerLow,
      ),
      borderColor: scheme.primary.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(Icons.trending_up_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n $one';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$n $few';
    }
    return '$n $many';
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});

  final ExerciseSummary exercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    var workNumber = 0;
    return DashboardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ChangeChip(change: exercise.change),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final set in exercise.sets)
                _SetChip(
                  set: set,
                  number: set.isWarmup ? null : ++workNumber,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.change});

  final ExerciseChange change;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (change.kind) {
      ExerciseChangeKind.record => (scheme.primary, scheme.onPrimary),
      ExerciseChangeKind.up => (
          Colors.green.withValues(alpha: 0.18),
          Colors.green.shade400,
        ),
      ExerciseChangeKind.down => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
      ExerciseChangeKind.same || ExerciseChangeKind.first => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        change.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _SetChip extends StatelessWidget {
  const _SetChip({required this.set, required this.number});

  final SummarySet set;

  /// Номер рабочего подхода; null — разминка.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final warmup = set.isWarmup;
    final weight = set.weight;
    final value = weight == null || weight <= 0
        ? '${set.reps} повт.'
        : '${formatWeight(weight)} × ${set.reps}';
    final rpe = set.rpe;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
      decoration: BoxDecoration(
        color: warmup ? Colors.transparent : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: warmup ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: warmup
                  ? Colors.amber.withValues(alpha: 0.2)
                  : scheme.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              warmup ? 'Р' : '$number',
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color:
                    warmup ? Colors.amber.shade700 : scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: warmup ? FontWeight.w500 : FontWeight.w700,
              color: warmup ? scheme.onSurfaceVariant : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (rpe != null && !warmup) ...[
            const SizedBox(width: 4),
            Text(
              '@${rpe.toStringAsFixed(rpe % 1 == 0 ? 0 : 1)}',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
