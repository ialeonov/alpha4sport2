import 'muscle_heatmap_models.dart';
import 'muscle_load_normalizer.dart';

class MuscleLoadCalculator {
  const MuscleLoadCalculator({
    this.baseSetScore = 1.0,
    this.primaryMuscleFactor = 1.0,
    this.secondaryMuscleFactor = 0.4,
    this.stabilizerFactor = 0.15,
    this.stabilizerMuscles = const {'кор'},
    this.normalizer = const MuscleLoadNormalizer(),
  });

  final double baseSetScore;
  final double primaryMuscleFactor;
  final double secondaryMuscleFactor;

  /// Factor applied to stabilizer muscles (e.g. core) that are listed as
  /// secondary in nearly every exercise. Much lower than [secondaryMuscleFactor]
  /// so that stabilizers don't dominate the heatmap.
  final double stabilizerFactor;

  /// Set of muscle keys treated as stabilizers. Defaults to {'кор'}.
  final Set<String> stabilizerMuscles;
  final MuscleLoadNormalizer normalizer;

  Map<String, double> calculateForWorkout({
    required Map<String, dynamic> workout,
    required List<Map<String, dynamic>> exerciseCatalog,
  }) {
    return calculateForWorkouts(
      workouts: [workout],
      exerciseCatalog: exerciseCatalog,
    );
  }

  Map<String, double> calculateForWorkouts({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> exerciseCatalog,
  }) {
    final catalogById = <int, Map<String, dynamic>>{};
    final catalogByName = <String, Map<String, dynamic>>{};

    for (final exercise in exerciseCatalog) {
      final id = exercise['id'];
      if (id is int) {
        catalogById[id] = exercise;
      }
      final name = (exercise['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        catalogByName[_normalizeExerciseLookupName(name)] = exercise;
      }
    }

    final loads = <String, double>{};
    // Separate set counters for primary and secondary involvement so that
    // secondary sets (e.g. biceps in a back exercise) do not consume the
    // diminishing-returns budget for dedicated primary work.
    final primarySetCountsByMuscle = <String, int>{};
    final secondarySetCountsByMuscle = <String, int>{};
    for (final workout in workouts) {
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawExercise in exercises) {
        if (rawExercise is! Map) {
          continue;
        }
        final exercise = rawExercise.cast<String, dynamic>();
        final catalogEntry = _resolveCatalogEntry(
          exercise: exercise,
          catalogById: catalogById,
          catalogByName: catalogByName,
        );
        if (catalogEntry == null) {
          continue;
        }

        final primaryMuscle =
            (catalogEntry['primary_muscle'] ?? '').toString().trim();
        final secondaryMuscles =
            (catalogEntry['secondary_muscles'] as List?)?.cast<dynamic>() ??
                const [];
        final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];

        // Find max weight in this exercise to compute weight-proportional scores.
        // If all sets have no weight (bodyweight exercise), maxWeight stays 0
        // and each set contributes its full base score.
        double maxWeight = 0;
        for (final rawSet in sets) {
          if (rawSet is! Map) continue;
          final w = _toDouble(rawSet.cast<String, dynamic>()['weight']);
          if (w > maxWeight) maxWeight = w;
        }

        for (final rawSet in sets) {
          if (rawSet is! Map) {
            continue;
          }
          final set = rawSet.cast<String, dynamic>();
          final setScore = _calculateSetScore(set, maxWeight: maxWeight);
          if (setScore <= 0) {
            continue;
          }

          if (primaryMuscle.isNotEmpty) {
            _addMuscleLoad(
              loads: loads,
              setCountsByMuscle: primarySetCountsByMuscle,
              muscle: primaryMuscle,
              setScore: setScore,
              muscleFactor: primaryMuscleFactor,
            );
          }

          for (final rawMuscle in secondaryMuscles) {
            final muscle = rawMuscle.toString().trim();
            if (muscle.isEmpty) {
              continue;
            }
            final factor = stabilizerMuscles.contains(muscle)
                ? stabilizerFactor
                : secondaryMuscleFactor;
            _addMuscleLoad(
              loads: loads,
              setCountsByMuscle: secondarySetCountsByMuscle,
              muscle: muscle,
              setScore: setScore,
              muscleFactor: factor,
            );
          }
        }
      }
    }

    return loads;
  }

  Map<String, double> calculateNormalizedForWorkout({
    required Map<String, dynamic> workout,
    required List<Map<String, dynamic>> exerciseCatalog,
  }) {
    return normalizer.normalize(
      calculateForWorkout(workout: workout, exerciseCatalog: exerciseCatalog),
    );
  }

  Map<String, double> calculateNormalizedForWorkouts({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> exerciseCatalog,
  }) {
    return normalizer.normalize(
      calculateForWorkouts(
          workouts: workouts, exerciseCatalog: exerciseCatalog),
    );
  }

  Map<String, double> calculatePeakForCalendarDays({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> exerciseCatalog,
    required DateTime? Function(Map<String, dynamic> workout) dayResolver,
  }) {
    final workoutsByDay = <DateTime, List<Map<String, dynamic>>>{};

    for (final workout in workouts) {
      final resolved = dayResolver(workout);
      if (resolved == null) {
        continue;
      }
      final day = DateTime(resolved.year, resolved.month, resolved.day);
      workoutsByDay.putIfAbsent(day, () => []).add(workout);
    }

    final peakLoads = <String, double>{};
    for (final dayWorkouts in workoutsByDay.values) {
      final dayLoads = calculateForWorkouts(
        workouts: dayWorkouts,
        exerciseCatalog: exerciseCatalog,
      );
      for (final entry in dayLoads.entries) {
        final previous = peakLoads[entry.key] ?? 0;
        if (entry.value > previous) {
          peakLoads[entry.key] = entry.value;
        }
      }
    }

    return peakLoads;
  }

  List<TopMuscleLoad> buildTopMuscles({
    required Map<String, double> rawLoads,
    required Map<String, double> normalizedLoads,
    required Map<String, String> labels,
    int limit = 3,
  }) {
    final sorted = rawLoads.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .where((entry) => entry.value > 0)
        .take(limit)
        .map(
          (entry) => TopMuscleLoad(
            muscle: entry.key,
            label: labels[entry.key] ?? _formatMuscleLabel(entry.key),
            rawLoad: entry.value,
            normalizedLoad: normalizedLoads[entry.key] ?? 0,
          ),
        )
        .toList();
  }

  void _addMuscleLoad({
    required Map<String, double> loads,
    required Map<String, int> setCountsByMuscle,
    required String muscle,
    required double setScore,
    required double muscleFactor,
  }) {
    final nextSetCount = (setCountsByMuscle[muscle] ?? 0) + 1;
    setCountsByMuscle[muscle] = nextSetCount;
    final contribution =
        setScore * muscleFactor * _diminishingReturnsFactor(nextSetCount);
    loads.update(
      muscle,
      (value) => value + contribution,
      ifAbsent: () => contribution,
    );
  }

  double _calculateSetScore(
    Map<String, dynamic> set, {
    double maxWeight = 0,
  }) {
    final reps = _toDouble(set['reps']);
    if (reps <= 0) {
      return 0;
    }
    // Weight factor: scale each set's contribution relative to the heaviest
    // set in the exercise. Warmup/dropsets contribute proportionally less.
    // Falls back to 1.0 for bodyweight exercises (maxWeight == 0).
    final weightFactor = maxWeight > 0
        ? (_toDouble(set['weight']) / maxWeight).clamp(0.0, 1.0)
        : 1.0;
    return baseSetScore * _repFactor(reps) * weightFactor;
  }

  double _repFactor(double reps) {
    if (reps <= 12) {
      return 1.0;
    }
    if (reps <= 20) {
      return 0.85;
    }
    return 0.65;
  }

  double _diminishingReturnsFactor(int setCount) {
    if (setCount <= 4) {
      return 1.0;
    }
    if (setCount <= 7) {
      return 0.8;
    }
    return 0.6;
  }

  Map<String, dynamic>? _resolveCatalogEntry({
    required Map<String, dynamic> exercise,
    required Map<int, Map<String, dynamic>> catalogById,
    required Map<String, Map<String, dynamic>> catalogByName,
  }) {
    final catalogExerciseId = exercise['catalog_exercise_id'];
    if (catalogExerciseId is int) {
      final byId = catalogById[catalogExerciseId];
      if (byId != null) {
        return byId;
      }
    }

    final name = (exercise['exercise_name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return null;
    }
    return catalogByName[_normalizeExerciseLookupName(name)];
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value == null) {
      return 0;
    }
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}

String formatMuscleLabel(String value) => _formatMuscleLabel(value);

String _formatMuscleLabel(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) {
    return normalized;
  }
  return normalized[0].toUpperCase() + normalized.substring(1);
}
