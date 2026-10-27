import 'package:alpha4sport_app/features/workouts/domain/workout_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _workout(
  int id,
  DateTime day,
  List<(num?, int)> sets, {
  String name = 'Жим лёжа',
  bool finished = true,
}) =>
    {
      'id': id,
      'started_at': day.toIso8601String(),
      'finished_at': finished ? day.toIso8601String() : null,
      'exercises': [
        {
          'exercise_name': name,
          'sets': [
            for (final set in sets)
              {'weight': set.$1, 'reps': set.$2, 'set_type': 'work'},
          ],
        },
      ],
    };

void main() {
  test('treats light sets before the heaviest one as warmups', () {
    final sets = markWarmups([
      {'weight': 20, 'reps': 30},
      {'weight': 60, 'reps': 15},
      {'weight': 80, 'reps': 10},
      {'weight': 100, 'reps': 3},
      {'weight': 60, 'reps': 12},
    ]);

    expect(sets.map((s) => s.isWarmup), [true, true, false, false, false]);
  });

  test('keeps explicit warmups and bodyweight sets as they are', () {
    final sets = markWarmups([
      {'weight': 40, 'reps': 10, 'set_type': 'warmup'},
      {'weight': null, 'reps': 12},
      {'weight': null, 'reps': 10},
    ]);

    expect(sets.map((s) => s.isWarmup), [true, false, false]);
  });

  test('marks a record when the top weight beats every earlier session', () {
    final current = _workout(3, DateTime(2026, 10, 20), [(20, 30), (105, 3)]);
    final summary = buildWorkoutSummary(
      workout: current,
      history: [
        current,
        _workout(2, DateTime(2026, 10, 13), [(90, 5)]),
        _workout(1, DateTime(2026, 10, 6), [(100, 2)]),
      ],
    );

    final exercise = summary.exercises.single;
    expect(exercise.change.kind, ExerciseChangeKind.record);
    expect(exercise.change.label, 'рекорд 105 кг');
    expect(exercise.workingSets, 1);
    expect(summary.records, 1);
  });

  test('compares weight, then reps with the previous session', () {
    final heavier = buildWorkoutSummary(
      workout: _workout(3, DateTime(2026, 10, 20), [(85, 6)]),
      history: [
        _workout(2, DateTime(2026, 10, 13), [(80, 8)]),
        _workout(1, DateTime(2026, 10, 6), [(90, 3)]),
      ],
    ).exercises.single.change;
    expect(heavier.kind, ExerciseChangeKind.up);
    expect(heavier.label, '+5 кг');

    final moreReps = buildWorkoutSummary(
      workout: _workout(3, DateTime(2026, 10, 20), [(80, 10)]),
      history: [
        _workout(2, DateTime(2026, 10, 13), [(80, 8)])
      ],
    ).exercises.single.change;
    expect(moreReps.label, '+2 повт.');
  });

  test('ignores later and unfinished workouts', () {
    final change = buildWorkoutSummary(
      workout: _workout(2, DateTime(2026, 10, 13), [(80, 8)]),
      history: [
        _workout(3, DateTime(2026, 10, 20), [(70, 8)]),
        _workout(1, DateTime(2026, 10, 10), [(60, 8)], finished: false),
      ],
    ).exercises.single.change;

    expect(change.kind, ExerciseChangeKind.first);
  });
}
