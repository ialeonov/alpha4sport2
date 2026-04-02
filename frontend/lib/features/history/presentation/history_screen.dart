import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/muscle_heatmap_card.dart';
import '../../progression/application/progression_controller.dart';
import '../../workouts/application/workout_export_service.dart';
import '../../workouts/application/workout_share_service.dart';
import '../../workouts/domain/workout_metrics.dart';
import '../../workouts/presentation/workout_form_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _searchController = TextEditingController();
  final WorkoutExportService _workoutExportService =
      const WorkoutExportService();
  List<Map<String, dynamic>> _exerciseCatalog = const [];

  @override
  void initState() {
    super.initState();
    _future = _loadWorkouts();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await BackendApi.getExercises();
      if (mounted) setState(() => _exerciseCatalog = catalog);
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null && mounted) {
        setState(() => _exerciseCatalog =
            cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList());
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadWorkouts() async {
    try {
      return await BackendApi.getWorkouts();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadWorkouts());
    await _future;
  }

  DateTime? _workoutDate(Map<String, dynamic> workout) {
    return DateTime.tryParse((workout['started_at'] ?? '').toString())
        ?.toLocal();
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> workouts) {
    final query = _searchController.text.trim().toLowerCase();
    return workouts.where((workout) {
      final name = (workout['name'] ?? '').toString().toLowerCase();
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      final exerciseText = exercises
          .map((exercise) => ((exercise as Map)['exercise_name'] ?? '')
              .toString()
              .toLowerCase())
          .join(' ');
      return query.isEmpty ||
          name.contains(query) ||
          exerciseText.contains(query);
    }).toList();
  }

  Future<void> _exportWorkoutRange(List<Map<String, dynamic>> workouts) async {
    if (workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет тренировок для экспорта.')),
      );
      return;
    }

    final datedWorkouts = workouts
        .where((workout) => _workoutExportService.workoutDate(workout) != null)
        .toList();
    if (datedWorkouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось определить даты тренировок для экспорта.'),
        ),
      );
      return;
    }

    DateTime? firstDate;
    DateTime? lastDate;
    for (final workout in datedWorkouts) {
      final day = _workoutExportService.workoutDate(workout)!;
      if (firstDate == null || day.isBefore(firstDate)) {
        firstDate = day;
      }
      if (lastDate == null || day.isAfter(lastDate)) {
        lastDate = day;
      }
    }

    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: firstDate!,
      lastDate: lastDate!,
      initialDateRange: DateTimeRange(start: firstDate, end: lastDate),
      locale: const Locale('ru'),
    );
    if (pickedRange == null) {
      return;
    }

    final selectedWorkouts = _workoutExportService.filterWorkoutsByDateRange(
      workouts: workouts,
      from: pickedRange.start,
      to: pickedRange.end,
    );
    if (selectedWorkouts.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В выбранном диапазоне нет тренировок для экспорта.'),
        ),
      );
      return;
    }

    try {
      final exerciseCatalog = await _workoutExportService.loadExerciseCatalog();
      final templates = await _workoutExportService.loadTemplates();
      final exportData = _workoutExportService.buildExport(
        workouts: selectedWorkouts,
        rangeFrom: pickedRange.start,
        rangeTo: pickedRange.end,
        exerciseCatalog: exerciseCatalog,
        templates: templates,
      );
      final saved = await _workoutExportService.saveExportJson(
        exportData: exportData,
        suggestedFileName:
            'workouts_${formatExportFileDate(pickedRange.start)}__${formatExportFileDate(pickedRange.end)}.json',
      );
      if (!mounted || !saved) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Экспорт диапазона сохранён.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось экспортировать диапазон тренировок.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _shareWorkout(Map<String, dynamic> workout) async {
    await WorkoutShareService.share(
      context: context,
      workout: workout,
      exerciseCatalog: _exerciseCatalog,
    );
  }

  Future<void> _openEditWorkout(Map<String, dynamic> workout) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormScreen(initialWorkout: workout),
      ),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _deleteWorkout(Map<String, dynamic> workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: Text(
          'Тренировка "${(workout['name'] ?? 'Тренировка').toString()}" будет удалена без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      final workoutId = workout['id'] as int;
      await BackendApi.deleteWorkout(workoutId);
      await LocalCache.remove('workout_draft_$workoutId');
      final activeDraft = LocalCache.get<String>(CacheKeys.activeWorkoutDraft);
      if (activeDraft == 'workout_draft_$workoutId') {
        await LocalCache.remove(CacheKeys.activeWorkoutDraft);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось удалить тренировку.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Тренировка удалена.')),
    );
    await ProgressionController.instance.refresh();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBackdrop(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  BackendApi.describeError(
                    snapshot.error!,
                    fallback: 'Не удалось загрузить историю тренировок.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final workouts = snapshot.data ?? [];
          final filtered = _applySearch(workouts);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                DashboardSummaryCard(
                  subtitle: 'Поиск и журнал',
                  title: 'Все тренировки',
                  bottom: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ExpandedActionButton(
                        label: 'Экспорт диапазона',
                        icon: Icons.file_download_outlined,
                        onPressed: filtered.isEmpty
                            ? null
                            : () => _exportWorkoutRange(filtered),
                        outlined: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _HistoryHeatmapCard(),
                const SizedBox(height: 14),
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Поиск по названию или упражнению',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  DashboardCard(
                    child: Text(
                      workouts.isEmpty
                          ? 'Тренировок пока нет.'
                          : 'По запросу ничего не найдено.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                else
                  ...filtered.map((workout) {
                    final startedAt = _workoutDate(workout);
                    final exercises =
                        (workout['exercises'] as List?)?.cast<dynamic>() ??
                            const [];
                    final exerciseCount = exercises.length;
                    final tonnage =
                        formatTonnage(calculateWorkoutTonnage(workout));
                    final preview = exercises
                        .take(3)
                        .map((exercise) =>
                            ((exercise as Map)['exercise_name'] ?? '')
                                .toString())
                        .where((name) => name.isNotEmpty)
                        .join(' · ');
                    final isActive = workout['finished_at'] == null;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Dismissible(
                        key: ValueKey(workout['id']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await _deleteWorkout(workout);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: scheme.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child:
                              Icon(Icons.delete_outline, color: scheme.error),
                        ),
                        child: DashboardCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          onTap: () => _openEditWorkout(workout),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      (workout['name'] ?? 'Тренировка')
                                          .toString(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isActive)
                                    StatusBadge(
                                      label: 'Активна',
                                      color: scheme.secondary,
                                      compact: true,
                                    ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        Icons.ios_share_rounded,
                                        size: 18,
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                      tooltip: 'Поделиться карточкой',
                                      onPressed: () => _shareWorkout(workout),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 12,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    startedAt == null
                                        ? 'Без даты'
                                        : formatShortDate(startedAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                  if (exerciseCount > 0) ...[
                                    const SizedBox(width: 10),
                                    Icon(
                                      Icons.fitness_center_rounded,
                                      size: 12,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$exerciseCount упр.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  if (tonnage != '0 кг') ...[
                                    const SizedBox(width: 10),
                                    Icon(
                                      Icons.monitor_weight_rounded,
                                      size: 12,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      tonnage,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                              if (preview.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.65),
                                        height: 1.35,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ignore: unused_element
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryHeatmapCard extends StatefulWidget {
  const _HistoryHeatmapCard();

  @override
  State<_HistoryHeatmapCard> createState() => _HistoryHeatmapCardState();
}

class _HistoryHeatmapCardState extends State<_HistoryHeatmapCard> {
  late Future<_HeatmapData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HeatmapData> _load() async {
    try {
      final results = await Future.wait([
        BackendApi.getWorkouts(),
        BackendApi.getExercises(),
      ]);
      return _build(workouts: results[0], catalog: results[1]);
    } catch (_) {
      final wCache = LocalCache.get<List>(CacheKeys.workoutsCache);
      final cCache = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (wCache != null && cCache != null) {
        return _build(
          workouts: wCache.cast<Map>().map((e) => e.cast<String, dynamic>()).toList(),
          catalog: cCache.cast<Map>().map((e) => e.cast<String, dynamic>()).toList(),
        );
      }
      rethrow;
    }
  }

  _HeatmapData _build({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> catalog,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final since = today.subtract(const Duration(days: 6));
    final recent = workouts.where((w) {
      final d = DateTime.tryParse((w['started_at'] ?? '').toString())?.toLocal();
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(since) && !day.isAfter(today);
    }).toList();
    final calc = const MuscleLoadCalculator();
    final raw = calc.calculatePeakForCalendarDays(
      workouts: recent,
      exerciseCatalog: catalog,
      dayResolver: (w) => DateTime.tryParse((w['started_at'] ?? '').toString())?.toLocal(),
    );
    return _HeatmapData(
      workoutCount: recent.length,
      rawLoads: raw,
      normalizedLoads: calc.normalizer.normalize(raw),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HeatmapData>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Нагрузка за 7 дней'),
            const SizedBox(height: 10),
            MuscleHeatmapCard(
              title: 'Тепловая карта мышц',
              subtitle: 'Последние 7 дней · ${data.workoutCount} тренировок',
              rawLoads: data.rawLoads,
              normalizedLoads: data.normalizedLoads,
              emptyMessage: 'За последние 7 дней нет данных.',
            ),
          ],
        );
      },
    );
  }
}

class _HeatmapData {
  const _HeatmapData({
    required this.workoutCount,
    required this.rawLoads,
    required this.normalizedLoads,
  });
  final int workoutCount;
  final Map<String, double> rawLoads;
  final Map<String, double> normalizedLoads;
}

class ExpandedActionButton extends StatelessWidget {
  const ExpandedActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
