import 'dart:math';

/// План на сегодня без LLM: какие группы мышц дольше всего не нагружались
/// и какие упражнения на них пользователь обычно делает — с весом и
/// повторами из последней тренировки.

class PlannedGroup {
  const PlannedGroup({required this.label, required this.daysSince});

  /// «Ноги», «Спина» и т. п.
  final String label;

  /// Сколько дней прошло с последней тренировки группы.
  final int daysSince;
}

class PlannedExercise {
  const PlannedExercise({
    required this.name,
    required this.catalogExerciseId,
    required this.sets,
    required this.reps,
    required this.weight,
  });

  final String name;
  final int? catalogExerciseId;
  final int sets;
  final int reps;

  /// Рабочий вес в прошлый раз; null — упражнение с собственным весом.
  final double? weight;
}

class TodayPlan {
  const TodayPlan({required this.groups, required this.exercises});

  final List<PlannedGroup> groups;
  final List<PlannedExercise> exercises;

  /// «НОГИ И ПЛЕЧИ»
  String get headline =>
      groups.map((group) => group.label.toUpperCase()).join(' И ');

  /// Название тренировки: «Ноги + плечи».
  String get workoutName {
    final labels = groups.map((group) => group.label.toLowerCase()).toList();
    final joined = labels.join(' + ');
    return joined.isEmpty
        ? 'Тренировка'
        : '${joined[0].toUpperCase()}${joined.substring(1)}';
  }

  /// Упражнения в формате, который принимает экран тренировки:
  /// подходы без веса — они заполняются по ходу тренировки.
  List<Map<String, dynamic>> toWorkoutExercises() {
    return [
      for (var index = 0; index < exercises.length; index++)
        {
          'catalog_exercise_id': exercises[index].catalogExerciseId,
          'exercise_name': exercises[index].name,
          'position': index + 1,
          'notes': null,
          'sets': List.generate(
            exercises[index].sets,
            (setIndex) => {
              'position': setIndex + 1,
              'reps': exercises[index].reps,
              'weight': null,
              'set_type': 'work',
              'rpe': null,
              'notes': null,
            },
          ),
        },
    ];
  }
}

const Map<String, String> _muscleGroups = {
  'грудь': 'Грудь',
  'широчайшие': 'Спина',
  'трапеции': 'Спина',
  'квадрицепсы': 'Ноги',
  'бицепс_бедра': 'Ноги',
  'ягодицы': 'Ноги',
  'икры': 'Ноги',
  'передние_дельты': 'Плечи',
  'средние_дельты': 'Плечи',
  'задние_дельты': 'Плечи',
  'трицепс': 'Руки',
  'бицепс': 'Руки',
  'пресс': 'Пресс',
};

/// Крупные группы — из них выбирается фокус дня. Руки и пресс получают
/// нагрузку в базовых упражнениях и в фокус не выносятся.
const Set<String> _focusGroups = {'Грудь', 'Спина', 'Ноги', 'Плечи'};

/// Упражнения выбираются из истории за этот период.
const int _historyDays = 60;

TodayPlan? buildTodayPlan({
  required List<Map<String, dynamic>> workouts,
  required List<Map<String, dynamic>> exerciseCatalog,
  required DateTime now,
  int maxExercises = 5,
}) {
  final muscleById = <int, String>{};
  final muscleByName = <String, String>{};
  final catalogNameById = <int, String>{};
  for (final item in exerciseCatalog) {
    final muscle = (item['primary_muscle'] ?? '').toString().trim();
    final name = (item['name'] ?? '').toString();
    final id = item['id'];
    if (id is int) {
      muscleById[id] = muscle;
      catalogNameById[id] = name;
    }
    muscleByName[_normalizeName(name)] = muscle;
  }

  final today = DateTime(now.year, now.month, now.day);
  final finished = <({DateTime day, Map<String, dynamic> workout})>[];
  for (final workout in workouts) {
    if (workout['finished_at'] == null) continue;
    final startedAt =
        DateTime.tryParse((workout['started_at'] ?? '').toString())?.toLocal();
    if (startedAt == null) continue;
    finished.add((
      day: DateTime(startedAt.year, startedAt.month, startedAt.day),
      workout: workout,
    ));
  }
  // Свежие тренировки первыми: первое попадание упражнения — последнее.
  finished.sort((a, b) => b.day.compareTo(a.day));

  final lastDayByGroup = <String, DateTime>{};
  final statsByKey = <String, _ExerciseStats>{};

  for (final entry in finished) {
    final exercises =
        (entry.workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    for (final raw in exercises) {
      final exercise = (raw as Map).cast<String, dynamic>();
      final workSets = _workSets(exercise);
      if (workSets.isEmpty) continue;

      final catalogId = exercise['catalog_exercise_id'] as int?;
      final rawName = (exercise['exercise_name'] ?? '').toString().trim();
      final muscle = (catalogId != null ? muscleById[catalogId] : null) ??
          muscleByName[_normalizeName(rawName)];
      final group = _muscleGroups[muscle];
      if (group == null) continue;

      lastDayByGroup.putIfAbsent(group, () => entry.day);

      final key = catalogId != null ? 'id:$catalogId' : _normalizeName(rawName);
      final stats = statsByKey.putIfAbsent(
        key,
        () => _ExerciseStats(
          name: (catalogId != null ? catalogNameById[catalogId] : null) ??
              rawName,
          catalogExerciseId: catalogId,
          group: group,
          lastDay: entry.day,
          lastWorkSets: workSets,
        ),
      );
      if (today.difference(entry.day).inDays <= _historyDays) {
        stats.recentSessions++;
      }
    }
  }

  final focus = lastDayByGroup.entries
      .where((entry) => _focusGroups.contains(entry.key))
      .toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  if (focus.isEmpty) return null;

  final groups = focus
      .take(2)
      .map(
        (entry) => PlannedGroup(
          label: entry.key,
          daysSince: max(0, today.difference(entry.value).inDays),
        ),
      )
      .toList();

  List<_ExerciseStats> candidatesFor(String group) => statsByKey.values
      .where((stats) =>
          stats.group == group &&
          (stats.recentSessions > 0 ||
              today.difference(stats.lastDay).inDays <= _historyDays * 3))
      .toList()
    ..sort((a, b) {
      final byFrequency = b.recentSessions.compareTo(a.recentSessions);
      return byFrequency != 0 ? byFrequency : b.lastDay.compareTo(a.lastDay);
    });

  // Первой группе — больше упражнений; если во второй не хватает,
  // добираем из первой и наоборот.
  final perGroup = groups.length == 1
      ? [maxExercises]
      : [(maxExercises + 1) ~/ 2, maxExercises ~/ 2];
  final pools = [for (final group in groups) candidatesFor(group.label)];
  final picked = <_ExerciseStats>[];
  for (var i = 0; i < pools.length; i++) {
    picked.addAll(pools[i].take(perGroup[i]));
  }
  for (final pool in pools) {
    for (final stats in pool) {
      if (picked.length >= maxExercises) break;
      if (!picked.contains(stats)) picked.add(stats);
    }
  }
  if (picked.isEmpty) return null;

  return TodayPlan(
    groups: groups,
    exercises: picked.map((stats) => stats.toPlanned()).toList(),
  );
}

class _ExerciseStats {
  _ExerciseStats({
    required this.name,
    required this.catalogExerciseId,
    required this.group,
    required this.lastDay,
    required this.lastWorkSets,
  });

  final String name;
  final int? catalogExerciseId;
  final String group;
  final DateTime lastDay;
  final List<({double? weight, int reps})> lastWorkSets;
  int recentSessions = 0;

  PlannedExercise toPlanned() {
    // Ориентир — самый тяжёлый рабочий подход прошлой тренировки.
    var top = lastWorkSets.first;
    for (final set in lastWorkSets) {
      if ((set.weight ?? 0) > (top.weight ?? 0)) top = set;
    }
    return PlannedExercise(
      name: name,
      catalogExerciseId: catalogExerciseId,
      sets: lastWorkSets.length.clamp(1, 6),
      reps: top.reps,
      weight: (top.weight ?? 0) > 0 ? top.weight : null,
    );
  }
}

List<({double? weight, int reps})> _workSets(Map<String, dynamic> exercise) {
  final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
  final result = <({double? weight, int reps})>[];
  for (final raw in sets) {
    final set = (raw as Map).cast<String, dynamic>();
    if (set['set_type'] == 'warmup') continue;
    final reps = (set['reps'] as num?)?.toInt() ?? 0;
    if (reps <= 0) continue;
    result.add((weight: (set['weight'] as num?)?.toDouble(), reps: reps));
  }
  return result;
}

String _normalizeName(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');
