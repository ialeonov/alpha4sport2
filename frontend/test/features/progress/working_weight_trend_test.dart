import 'package:alpha4sport_app/features/progress/domain/progress_models.dart';
import 'package:alpha4sport_app/features/progress/domain/working_weight_trend.dart';
import 'package:flutter_test/flutter_test.dart';

ExerciseSessionPerformance _session(DateTime day, double weight) =>
    ExerciseSessionPerformance(
      exerciseName: 'Жим',
      performedAt: day,
      workingSet: ExerciseSetPerformance(
        reps: 8,
        weight: weight,
        estimated1rm: weight * 1.27,
        normalizedWeight: weight,
      ),
      totalSets: 3,
      setsAtWorkingWeight: 3,
      averageRpeAtWorkingWeight: null,
      hitUpperBound: false,
      missedLowerBound: false,
    );

void main() {
  test('compares with the last session before the month started', () {
    final change = workingWeightChange([
      _session(DateTime(2026, 9, 1), 60),
      _session(DateTime(2026, 9, 20), 70),
      _session(DateTime(2026, 10, 5), 75),
      _session(DateTime(2026, 10, 25), 80),
    ])!;

    expect(change.delta, 10);
    expect(change.since, DateTime(2026, 9, 20));
  });

  test('uses the first session when the exercise is newer than a month', () {
    final change = workingWeightChange([
      _session(DateTime(2026, 10, 10), 50),
      _session(DateTime(2026, 10, 25), 55),
    ])!;

    expect(change.delta, 5);
  });

  test('returns null with nothing to compare', () {
    expect(workingWeightChange([_session(DateTime(2026, 10, 25), 55)]), isNull);
  });

  test('charts three months but keeps a few points when sessions are rare', () {
    final history = [
      _session(DateTime(2026, 3, 1), 40),
      _session(DateTime(2026, 5, 1), 45),
      _session(DateTime(2026, 7, 1), 50),
      _session(DateTime(2026, 10, 1), 55),
    ];
    expect(chartSessions(history).length, 4);

    final dense = [
      for (var i = 0; i < 20; i++)
        _session(DateTime(2026, 5, 1).add(Duration(days: i * 7)), 40.0 + i),
    ];
    final charted = chartSessions(dense);
    expect(charted.length, lessThan(20));
    expect(charted.last, dense.last);
  });
}
