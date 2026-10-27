import 'progress_models.dart';

/// Как изменился рабочий вес (самый тяжёлый подход тренировки) за период.
class WorkingWeightChange {
  const WorkingWeightChange({required this.delta, required this.since});

  /// Разница в кг: последняя тренировка минус тренировка в начале периода.
  final double delta;

  /// С какой тренировки считаем.
  final DateTime since;
}

/// Изменение за [period] (по умолчанию — месяц) по [history] от старых к
/// новым. Точка отсчёта — последняя тренировка не позже начала периода, а
/// если упражнение начали делать позже — первая тренировка в периоде.
/// null, если сравнивать не с чем.
WorkingWeightChange? workingWeightChange(
  List<ExerciseSessionPerformance> history, {
  Duration period = const Duration(days: 30),
}) {
  if (history.length < 2) return null;
  final latest = history.last;
  final periodStart = latest.performedAt.subtract(period);

  ExerciseSessionPerformance? base;
  for (final session in history) {
    if (!session.performedAt.isAfter(periodStart)) {
      base = session;
    } else {
      base ??= session;
      break;
    }
  }
  if (base == null || identical(base, latest)) return null;

  return WorkingWeightChange(
    delta: latest.workingSet.weight - base.workingSet.weight,
    since: base.performedAt,
  );
}

/// Тренировки для графика: последние три месяца, но не меньше [minPoints]
/// последних, если тренировок за это время мало.
List<ExerciseSessionPerformance> chartSessions(
  List<ExerciseSessionPerformance> history, {
  Duration period = const Duration(days: 90),
  int minPoints = 4,
}) {
  if (history.isEmpty) return const [];
  final from = history.last.performedAt.subtract(period);
  final recent =
      history.where((session) => !session.performedAt.isBefore(from)).toList();
  if (recent.length >= minPoints || recent.length == history.length) {
    return recent;
  }
  return history.sublist(
    history.length - minPoints.clamp(0, history.length),
  );
}
