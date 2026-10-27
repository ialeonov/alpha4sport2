import '../../../core/utils/formatters.dart';
import 'set_target.dart' show normalizeExerciseName;

/// Итог тренировки для экрана сводки: подходы с отметкой разминки и
/// сравнение каждого упражнения с прошлым разом.

enum ExerciseChangeKind { record, up, same, down, first }

class ExerciseChange {
  const ExerciseChange(this.kind, this.label);

  final ExerciseChangeKind kind;

  /// «рекорд 100 кг», «+5 кг», «+2 повт.», «−2.5 кг», «как в прошлый раз»,
  /// «впервые».
  final String label;
}

class SummarySet {
  const SummarySet({
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.isWarmup,
  });

  final double? weight;
  final int reps;
  final double? rpe;
  final bool isWarmup;
}

class ExerciseSummary {
  const ExerciseSummary({
    required this.name,
    required this.catalogExerciseId,
    required this.sets,
    required this.change,
  });

  final String name;
  final int? catalogExerciseId;
  final List<SummarySet> sets;
  final ExerciseChange change;

  int get workingSets => sets.where((set) => !set.isWarmup).length;
}

class WorkoutSummary {
  const WorkoutSummary({required this.exercises});

  final List<ExerciseSummary> exercises;

  int get workingSets =>
      exercises.fold(0, (sum, exercise) => sum + exercise.workingSets);

  int get records => exercises
      .where((exercise) => exercise.change.kind == ExerciseChangeKind.record)
      .length;

  int get improved => exercises
      .where((exercise) => exercise.change.kind == ExerciseChangeKind.up)
      .length;
}

WorkoutSummary buildWorkoutSummary({
  required Map<String, dynamic> workout,
  required List<Map<String, dynamic>> history,
}) {
  final startedAt = DateTime.tryParse((workout['started_at'] ?? '').toString());
  final earlier = history.where((other) {
    if (other['id'] != null && other['id'] == workout['id']) return false;
    if (other['finished_at'] == null) return false;
    final otherStart =
        DateTime.tryParse((other['started_at'] ?? '').toString());
    return otherStart != null &&
        (startedAt == null || otherStart.isBefore(startedAt));
  }).toList()
    ..sort((a, b) => (b['started_at'] ?? '')
        .toString()
        .compareTo((a['started_at'] ?? '').toString()));

  final exercises =
      (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
  return WorkoutSummary(
    exercises: [
      for (final raw in exercises)
        _summarizeExercise((raw as Map).cast<String, dynamic>(), earlier),
    ].where((exercise) => exercise.sets.isNotEmpty).toList(),
  );
}

ExerciseSummary _summarizeExercise(
  Map<String, dynamic> exercise,
  List<Map<String, dynamic>> earlier,
) {
  final sets = markWarmups(
    (exercise['sets'] as List?)?.cast<dynamic>() ?? const [],
  );
  final catalogId = exercise['catalog_exercise_id'] as int?;
  final name = (exercise['exercise_name'] ?? '').toString();
  final key = normalizeExerciseName(name);

  // Лучшие подходы этого упражнения в прошлых тренировках, свежие первыми.
  final previousTops = <_TopSet>[];
  for (final other in earlier) {
    for (final raw in (other['exercises'] as List?) ?? const []) {
      final candidate = (raw as Map).cast<String, dynamic>();
      final sameExercise =
          catalogId != null && candidate['catalog_exercise_id'] == catalogId ||
              normalizeExerciseName(
                      (candidate['exercise_name'] ?? '').toString()) ==
                  key;
      if (!sameExercise) continue;
      final top = _topSet(markWarmups(
        (candidate['sets'] as List?)?.cast<dynamic>() ?? const [],
      ));
      if (top != null) previousTops.add(top);
    }
  }

  return ExerciseSummary(
    name: name,
    catalogExerciseId: catalogId,
    sets: sets,
    change: _compare(_topSet(sets), previousTops),
  );
}

/// Подходы с отметкой разминки: явная разминка или лёгкие подходы до
/// самого тяжёлого (не тяжелее 60 % от него) — так обычно разминаются,
/// даже если подход не отмечен.
List<SummarySet> markWarmups(List<dynamic> rawSets) {
  final parsed = <SummarySet>[];
  for (final raw in rawSets) {
    final set = (raw as Map).cast<String, dynamic>();
    final reps = (set['reps'] as num?)?.toInt() ?? 0;
    if (reps <= 0) continue;
    parsed.add(SummarySet(
      weight: (set['weight'] as num?)?.toDouble(),
      reps: reps,
      rpe: (set['rpe'] as num?)?.toDouble(),
      isWarmup: set['set_type'] == 'warmup',
    ));
  }

  var topIndex = -1;
  var topWeight = 0.0;
  for (var i = 0; i < parsed.length; i++) {
    final weight = parsed[i].weight ?? 0;
    if (!parsed[i].isWarmup && weight > topWeight) {
      topWeight = weight;
      topIndex = i;
    }
  }
  if (topIndex <= 0) return parsed;

  return [
    for (var i = 0; i < parsed.length; i++)
      i < topIndex && (parsed[i].weight ?? 0) <= topWeight * 0.6
          ? SummarySet(
              weight: parsed[i].weight,
              reps: parsed[i].reps,
              rpe: parsed[i].rpe,
              isWarmup: true,
            )
          : parsed[i],
  ];
}

class _TopSet {
  const _TopSet(this.weight, this.reps);
  final double weight;
  final int reps;
}

_TopSet? _topSet(List<SummarySet> sets) {
  _TopSet? top;
  for (final set in sets) {
    if (set.isWarmup) continue;
    final weight = set.weight ?? 0;
    if (top == null ||
        weight > top.weight ||
        (weight == top.weight && set.reps > top.reps)) {
      top = _TopSet(weight, set.reps);
    }
  }
  return top;
}

ExerciseChange _compare(_TopSet? current, List<_TopSet> previous) {
  if (current == null || previous.isEmpty) {
    return const ExerciseChange(ExerciseChangeKind.first, 'впервые');
  }
  final last = previous.first;
  final bestWeight =
      previous.map((top) => top.weight).reduce((a, b) => a > b ? a : b);

  if (current.weight > 0 && current.weight > bestWeight) {
    return ExerciseChange(
      ExerciseChangeKind.record,
      'рекорд ${formatWeight(current.weight)} кг',
    );
  }
  if (current.weight != last.weight) {
    final delta = current.weight - last.weight;
    return ExerciseChange(
      delta > 0 ? ExerciseChangeKind.up : ExerciseChangeKind.down,
      '${delta > 0 ? '+' : '−'}${formatWeight(delta.abs())} кг',
    );
  }
  if (current.reps != last.reps) {
    final delta = current.reps - last.reps;
    return ExerciseChange(
      delta > 0 ? ExerciseChangeKind.up : ExerciseChangeKind.down,
      '${delta > 0 ? '+' : '−'}${delta.abs()} повт.',
    );
  }
  return const ExerciseChange(ExerciseChangeKind.same, 'как в прошлый раз');
}
