import 'muscle_heatmap_models.dart';

const String _coreMuscle = 'кор';
const Set<String> _coreMuscleAliases = {
  'разгибатель_спины',
  'поясница',
};

/// Считает нагрузку на мышцы в «эффективных подходах».
///
/// Один рабочий подход, сделанный близко к отказу, на основную мышцу
/// упражнения = 1 эффективный подход. Дальше применяются поправки:
/// * разминочные подходы не считаются;
/// * интенсивность — по RPE, а если его нет, по тому, насколько подход
///   близок к лучшему e1RM пользователя в этом же упражнении
///   (20 кг в махах и 20 кг в жиме ногами — разные вещи);
/// * вторичные мышцы получают долю подхода, стабилизаторы — ещё меньше;
/// * в рамках одной тренировки работает убывающая отдача по каждой мышце.
///
/// Результат одинаково интерпретируется на всех экранах: «сколько
/// эффективных подходов получила мышца» за тренировку или за период.
class MuscleLoadCalculator {
  const MuscleLoadCalculator({
    this.primaryMuscleFactor = 1.0,
    this.secondaryMuscleFactor = 0.5,
    this.stabilizerFactor = 0.2,
    this.stabilizerMuscles = const {_coreMuscle},
  });

  final double primaryMuscleFactor;
  final double secondaryMuscleFactor;

  /// Доля для мышц-стабилизаторов (кор), которые указаны вторичными почти
  /// в каждом упражнении и иначе доминировали бы на карте.
  final double stabilizerFactor;
  final Set<String> stabilizerMuscles;

  /// Нагрузка одной тренировки.
  Map<String, double> calculateForWorkout({
    required Map<String, dynamic> workout,
    required List<Map<String, dynamic>> exerciseCatalog,
    List<Map<String, dynamic>> referenceWorkouts = const [],
  }) {
    return calculate(
      workouts: [workout],
      exerciseCatalog: exerciseCatalog,
      referenceWorkouts: referenceWorkouts,
    );
  }

  /// Суммарная нагрузка за несколько тренировок (например, за неделю).
  ///
  /// [referenceWorkouts] — история для оценки лучшего e1RM в каждом
  /// упражнении. Сами [workouts] учитываются всегда, поэтому даже без
  /// истории лёгкие подходы считаются относительно лучшего подхода сессии.
  Map<String, double> calculate({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> exerciseCatalog,
    List<Map<String, dynamic>> referenceWorkouts = const [],
  }) {
    final lookup = _CatalogLookup(exerciseCatalog);
    final bestE1rm = _bestE1rmByExercise(
      [...referenceWorkouts, ...workouts],
      lookup,
    );
    final loads = <String, double>{};
    for (final workout in workouts) {
      _calculateWorkout(workout, lookup, bestE1rm).forEach((muscle, value) {
        loads.update(muscle, (prev) => prev + value, ifAbsent: () => value);
      });
    }
    return loads;
  }

  /// Для каждой мышцы — дата последней тренировки, где она получила хотя бы
  /// [minEffectiveSets] эффективных подходов.
  Map<String, DateTime> lastTrainedAt({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> exerciseCatalog,
    double minEffectiveSets = 1.0,
  }) {
    final lookup = _CatalogLookup(exerciseCatalog);
    final bestE1rm = _bestE1rmByExercise(workouts, lookup);
    final result = <String, DateTime>{};
    for (final workout in workouts) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      if (startedAt == null) continue;
      _calculateWorkout(workout, lookup, bestE1rm).forEach((muscle, value) {
        if (value < minEffectiveSets) return;
        final previous = result[muscle];
        if (previous == null || startedAt.isAfter(previous)) {
          result[muscle] = startedAt;
        }
      });
    }
    return result;
  }

  List<TopMuscleLoad> buildTopMuscles({
    required Map<String, double> loads,
    required Map<String, String> labels,
    int limit = 3,
    double minLoad = 0.5,
  }) {
    final sorted = loads.entries.where((e) => e.value >= minLoad).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(limit)
        .map(
          (entry) => TopMuscleLoad(
            muscle: entry.key,
            label: labels[entry.key] ?? _formatMuscleLabel(entry.key),
            load: entry.value,
          ),
        )
        .toList();
  }

  Map<String, double> _calculateWorkout(
    Map<String, dynamic> workout,
    _CatalogLookup lookup,
    Map<String, double> bestE1rm,
  ) {
    // Сырые эффективные подходы по мышцам внутри одной тренировки — до
    // применения убывающей отдачи.
    final rawByMuscle = <String, double>{};
    final exercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    for (final rawExercise in exercises) {
      if (rawExercise is! Map) continue;
      final exercise = rawExercise.cast<String, dynamic>();
      final catalogEntry = lookup.resolve(exercise);
      if (catalogEntry == null) continue;

      final primaryMuscle =
          _canonicalizeMuscleKey(catalogEntry['primary_muscle']);
      final secondaryMuscles = _canonicalizeSecondaryMuscles(
        primaryMuscle,
        (catalogEntry['secondary_muscles'] as List?)?.cast<dynamic>() ??
            const [],
      );
      final best = bestE1rm[lookup.keyFor(exercise, catalogEntry)] ?? 0;

      final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawSet in sets) {
        if (rawSet is! Map) continue;
        final setScore = effectiveSetScore(rawSet.cast<String, dynamic>(),
            bestE1rm: best);
        if (setScore <= 0) continue;

        if (primaryMuscle.isNotEmpty) {
          rawByMuscle.update(
            primaryMuscle,
            (v) => v + setScore * primaryMuscleFactor,
            ifAbsent: () => setScore * primaryMuscleFactor,
          );
        }
        for (final muscle in secondaryMuscles) {
          final factor = stabilizerMuscles.contains(muscle)
              ? stabilizerFactor
              : secondaryMuscleFactor;
          rawByMuscle.update(
            muscle,
            (v) => v + setScore * factor,
            ifAbsent: () => setScore * factor,
          );
        }
      }
    }
    return {
      for (final entry in rawByMuscle.entries)
        entry.key: sessionDiminishingReturns(entry.value),
    };
  }

  /// Вклад одного подхода: 0 для разминки и пустых подходов, иначе 0.3–1.0.
  double effectiveSetScore(Map<String, dynamic> set, {double bestE1rm = 0}) {
    if ((set['set_type'] ?? 'work').toString() == 'warmup') return 0;
    final reps = _toDouble(set['reps']);
    if (reps <= 0) return 0;
    return _repFactor(reps) * _intensityFactor(set, reps, bestE1rm);
  }

  double _intensityFactor(Map<String, dynamic> set, double reps, double best) {
    final rpe = _toDouble(set['rpe']);
    if (rpe > 0) {
      if (rpe >= 8) return 1.0;
      if (rpe >= 7) return 0.85;
      if (rpe >= 6) return 0.65;
      return 0.45;
    }
    final weight = _toDouble(set['weight']);
    if (weight <= 0 || best <= 0) {
      // Собственный вес или нет истории — считаем рабочим подходом.
      return 1.0;
    }
    // Эпли учитывает повторения, поэтому отношение e1RM подхода к лучшему
    // e1RM — грубая оценка близости к отказу.
    final ratio = estimate1rm(weight, reps) / best;
    if (ratio >= 0.9) return 1.0;
    if (ratio <= 0.65) return 0.3;
    return 0.3 + (ratio - 0.65) / 0.25 * 0.7;
  }

  double _repFactor(double reps) {
    if (reps <= 3) return 0.75;
    if (reps <= 30) return 1.0;
    return 0.7;
  }

  Map<String, double> _bestE1rmByExercise(
    List<Map<String, dynamic>> workouts,
    _CatalogLookup lookup,
  ) {
    final best = <String, double>{};
    for (final workout in workouts) {
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawExercise in exercises) {
        if (rawExercise is! Map) continue;
        final exercise = rawExercise.cast<String, dynamic>();
        final key = lookup.keyFor(exercise, lookup.resolve(exercise));
        if (key.isEmpty) continue;
        final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
        for (final rawSet in sets) {
          if (rawSet is! Map) continue;
          if ((rawSet['set_type'] ?? 'work').toString() == 'warmup') continue;
          final reps = _toDouble(rawSet['reps']);
          final weight = _toDouble(rawSet['weight']);
          if (reps <= 0 || reps > 30 || weight <= 0) continue;
          final e1rm = estimate1rm(weight, reps);
          if (e1rm > (best[key] ?? 0)) best[key] = e1rm;
        }
      }
    }
    return best;
  }
}

/// Оценка 1ПМ по Эпли.
double estimate1rm(double weight, double reps) =>
    reps <= 1 ? weight : weight * (1 + reps / 30);

/// Убывающая отдача внутри одной тренировки: первые 6 эффективных подходов
/// на мышцу идут полностью, 6–10 — на 70%, дальше — на 40%.
double sessionDiminishingReturns(double sets) {
  if (sets <= 6) return sets;
  if (sets <= 10) return 6 + (sets - 6) * 0.7;
  return 8.8 + (sets - 10) * 0.4;
}

class _CatalogLookup {
  _CatalogLookup(List<Map<String, dynamic>> catalog) {
    for (final exercise in catalog) {
      final id = exercise['id'];
      if (id is int) byId[id] = exercise;
      final name = (exercise['name'] ?? '').toString().trim();
      if (name.isNotEmpty) byName[_normalizeExerciseLookupName(name)] = exercise;
    }
  }

  final byId = <int, Map<String, dynamic>>{};
  final byName = <String, Map<String, dynamic>>{};

  Map<String, dynamic>? resolve(Map<String, dynamic> exercise) {
    final catalogExerciseId = exercise['catalog_exercise_id'];
    if (catalogExerciseId is int) {
      final entry = byId[catalogExerciseId];
      if (entry != null) return entry;
    }
    final name = (exercise['exercise_name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    return byName[_normalizeExerciseLookupName(name)];
  }

  /// Ключ упражнения для истории e1RM: id каталога, иначе нормализованное имя.
  String keyFor(Map<String, dynamic> exercise, Map<String, dynamic>? entry) {
    final id = entry?['id'];
    if (id is int) return 'id:$id';
    final name = (exercise['exercise_name'] ?? '').toString().trim();
    return name.isEmpty ? '' : 'name:${_normalizeExerciseLookupName(name)}';
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}

String _canonicalizeMuscleKey(dynamic value) {
  final muscle = value?.toString().trim() ?? '';
  return _coreMuscleAliases.contains(muscle) ? _coreMuscle : muscle;
}

List<String> _canonicalizeSecondaryMuscles(
  String primaryMuscle,
  List<dynamic> rawMuscles,
) {
  final seen = <String>{};
  final muscles = <String>[];
  for (final rawMuscle in rawMuscles) {
    final muscle = _canonicalizeMuscleKey(rawMuscle);
    if (muscle.isEmpty || muscle == primaryMuscle || !seen.add(muscle)) {
      continue;
    }
    muscles.add(muscle);
  }
  return muscles;
}

String formatMuscleLabel(String value) => _formatMuscleLabel(value);

String _formatMuscleLabel(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return normalized;
  return normalized[0].toUpperCase() + normalized.substring(1);
}
