import '../../../core/utils/formatters.dart';
import '../../progress/application/progress_analysis_service.dart';
import '../../progress/domain/progress_models.dart';

/// Цель на рабочий подход в следующей тренировке: вес × повторы.
/// Опирается на тот же анализ, что и вкладка «Прогресс», чтобы цифры
/// совпадали везде.
class SetTarget {
  const SetTarget({
    required this.weight,
    required this.reps,
    required this.change,
  });

  final double weight;
  final int reps;

  /// Что меняется относительно прошлой тренировки: «+2.5 кг», «+1 повт.»,
  /// «−2.5 кг» или пусто, если повторяем.
  final String change;

  String get label => '${formatWeight(weight)} × $reps';
}

SetTarget? setTargetFor(ExerciseProgressAnalysis analysis) {
  final last = analysis.latestSession?.workingSet;
  if (last == null) return null;
  final range = analysis.repRange;

  switch (analysis.decision) {
    case ProgressDecision.increase:
      return SetTarget(
        weight: analysis.recommendedNextWeight,
        reps: range.lower,
        change: '+${formatWeight(analysis.deltaWeight)} кг',
      );
    case ProgressDecision.decrease:
      return SetTarget(
        weight: analysis.recommendedNextWeight,
        reps: range.lower,
        change: '−${formatWeight(-analysis.deltaWeight)} кг',
      );
    case ProgressDecision.keep:
    case ProgressDecision.insufficientData:
      // Двойная прогрессия: на том же весе добавляем повтор до верха
      // диапазона, дальше анализ предложит прибавить вес.
      final addRep = last.reps < range.upper;
      return SetTarget(
        weight: last.weight,
        reps: addRep ? last.reps + 1 : last.reps,
        change: addRep ? '+1 повт.' : '',
      );
  }
}

/// Цели для всех упражнений из истории, по нормализованному названию.
/// Незавершённые тренировки и [excludeWorkoutId] (текущая) не учитываются.
Map<String, SetTarget> buildSetTargets({
  required List<Map<String, dynamic>> workouts,
  required List<Map<String, dynamic>> templates,
  int? excludeWorkoutId,
}) {
  final finished = workouts
      .where((workout) =>
          workout['finished_at'] != null &&
          (excludeWorkoutId == null || workout['id'] != excludeWorkoutId))
      .map(_withoutWarmups)
      .toList();
  final report = const ProgressAnalysisService().buildReport(
    workouts: finished,
    templates: templates,
  );

  final result = <String, SetTarget>{};
  for (final analysis in report.allExercises) {
    final target = setTargetFor(analysis);
    if (target != null) {
      result[normalizeExerciseName(analysis.exerciseName)] = target;
    }
  }
  return result;
}

String normalizeExerciseName(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');

Map<String, dynamic> _withoutWarmups(Map<String, dynamic> workout) {
  final exercises =
      (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
  return {
    ...workout,
    'exercises': [
      for (final raw in exercises)
        {
          ...(raw as Map).cast<String, dynamic>(),
          'sets': [
            for (final set in (raw['sets'] as List?) ?? const [])
              if ((set as Map)['set_type'] != 'warmup') set,
          ],
        },
    ],
  };
}
