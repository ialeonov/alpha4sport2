import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../domain/muscle_load_calculator.dart';
import 'muscle_heatmap_card.dart';

class WeeklyMuscleHeatmapTab extends StatefulWidget {
  const WeeklyMuscleHeatmapTab({super.key});

  @override
  State<WeeklyMuscleHeatmapTab> createState() => _WeeklyMuscleHeatmapTabState();
}

class _WeeklyMuscleHeatmapTabState extends State<WeeklyMuscleHeatmapTab> {
  late Future<_WeeklyHeatmapData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_WeeklyHeatmapData> _loadData() async {
    try {
      final results = await Future.wait([
        BackendApi.getWorkouts(),
        BackendApi.getExercises(),
      ]);
      return _buildData(
        workouts: results[0],
        catalog: results[1],
      );
    } catch (_) {
      final workoutsCache = LocalCache.get<List>(CacheKeys.workoutsCache);
      final catalogCache = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (workoutsCache != null && catalogCache != null) {
        return _buildData(
          workouts: workoutsCache
              .cast<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(),
          catalog: catalogCache
              .cast<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(),
        );
      }
      rethrow;
    }
  }

  _WeeklyHeatmapData _buildData({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> catalog,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstIncludedDay = today.subtract(const Duration(days: 6));
    final recentWorkouts = workouts.where((workout) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      if (startedAt == null) {
        return false;
      }
      final workoutDay = DateTime(startedAt.year, startedAt.month, startedAt.day);
      return !workoutDay.isBefore(firstIncludedDay) &&
          !workoutDay.isAfter(today);
    }).toList();

    final calculator = const MuscleLoadCalculator();
    final rawLoads = calculator.calculatePeakForCalendarDays(
      workouts: recentWorkouts,
      exerciseCatalog: catalog,
      dayResolver: (workout) => DateTime.tryParse(
        (workout['started_at'] ?? '').toString(),
      )?.toLocal(),
    );
    final normalizedLoads = calculator.normalizer.normalize(rawLoads);
    return _WeeklyHeatmapData(
      workoutCount: recentWorkouts.length,
      rawLoads: rawLoads,
      normalizedLoads: normalizedLoads,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WeeklyHeatmapData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              BackendApi.describeError(
                snapshot.error!,
                fallback: 'Не удалось загрузить heatmap за 7 дней.',
              ),
            ),
          );
        }

        final data = snapshot.data!;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              MuscleHeatmapCard(
                title: 'Тепловая карта мышц · 7 дней',
                subtitle:
                    'Последние 7 календарных дней: ${data.workoutCount} тренировок. По каждой мышце берётся максимальная нагрузка одного дня за этот период.',
                rawLoads: data.rawLoads,
                normalizedLoads: data.normalizedLoads,
                emptyMessage:
                    'За последние 7 календарных дней нет тренировок с данными для heatmap.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeeklyHeatmapData {
  const _WeeklyHeatmapData({
    required this.workoutCount,
    required this.rawLoads,
    required this.normalizedLoads,
  });

  final int workoutCount;
  final Map<String, double> rawLoads;
  final Map<String, double> normalizedLoads;
}
