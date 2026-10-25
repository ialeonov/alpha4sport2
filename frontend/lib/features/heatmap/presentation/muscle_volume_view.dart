import 'package:flutter/material.dart';

import '../../../core/widgets/athletic_ui.dart';
import '../domain/muscle_heatmap_color_resolver.dart';
import '../domain/muscle_load_calculator.dart';
import 'muscle_heatmap_card.dart';

enum _VolumePeriod { week, month }

/// Недельный объём по мышцам: тепловая карта + список с подходами и
/// давностью последней тренировки мышцы.
class MuscleVolumeView extends StatefulWidget {
  const MuscleVolumeView({
    super.key,
    required this.workouts,
    required this.catalog,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> workouts;
  final List<Map<String, dynamic>> catalog;
  final Future<void> Function() onRefresh;

  @override
  State<MuscleVolumeView> createState() => _MuscleVolumeViewState();
}

class _MuscleVolumeViewState extends State<MuscleVolumeView> {
  static const _calculator = MuscleLoadCalculator();
  _VolumePeriod _period = _VolumePeriod.week;

  List<Map<String, dynamic>> _workoutsSince(DateTime since) {
    return widget.workouts.where((w) {
      final d = DateTime.tryParse((w['started_at'] ?? '').toString())?.toLocal();
      return d != null && !d.isBefore(since);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = _period == _VolumePeriod.week ? 7 : 28;
    final weeks = days / 7;
    final periodWorkouts =
        _workoutsSince(today.subtract(Duration(days: days - 1)));

    final total = _calculator.calculate(
      workouts: periodWorkouts,
      exerciseCatalog: widget.catalog,
      referenceWorkouts: widget.workouts,
    );
    final perWeek = {
      for (final e in total.entries) e.key: e.value / weeks,
    };
    final lastTrained = _calculator.lastTrainedAt(
      workouts: _workoutsSince(today.subtract(const Duration(days: 60))),
      exerciseCatalog: widget.catalog,
    );

    final subtitle = _period == _VolumePeriod.week
        ? 'Последние 7 дней · тренировок: ${periodWorkouts.length}'
        : 'Последние 4 недели · тренировок: ${periodWorkouts.length} · '
            'в среднем за неделю';

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          SegmentedButton<_VolumePeriod>(
            segments: const [
              ButtonSegment(value: _VolumePeriod.week, label: Text('7 дней')),
              ButtonSegment(
                value: _VolumePeriod.month,
                label: Text('4 недели'),
              ),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _period = v.first),
          ),
          const SizedBox(height: 12),
          DashboardCard(
            padding: EdgeInsets.zero,
            child: MuscleHeatmapCard(
              loads: perWeek,
              scale: MuscleHeatmapScale.week,
              title: 'Объём по мышцам',
              subtitle: subtitle,
              showCard: false,
              showMuscleList: true,
              lastTrainedAt: lastTrained,
              emptyMessage: 'За этот период нет рабочих подходов.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Считаются эффективные подходы: рабочий подход на основную мышцу '
            '= 1, на вторичную = 0.5, разминки не учитываются. Лёгкие подходы '
            '(далеко от вашего максимума в упражнении или с низким RPE) '
            'считаются частично. Ориентир для роста — 10–20 подходов на мышцу '
            'в неделю.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}
