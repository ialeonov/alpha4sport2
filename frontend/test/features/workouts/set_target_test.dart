import 'package:alpha4sport_app/features/workouts/domain/set_target.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _workout(
  int id,
  DateTime day,
  List<(double, int)> sets, {
  bool finished = true,
  String name = 'Жим лёжа',
}) =>
    {
      'id': id,
      'started_at': day.toIso8601String(),
      'finished_at': finished ? day.toIso8601String() : null,
      'exercises': [
        {
          'exercise_name': name,
          'sets': [
            {'weight': 20, 'reps': 30, 'set_type': 'warmup'},
            for (final set in sets)
              {'weight': set.$1, 'reps': set.$2, 'set_type': 'work'},
          ],
        },
      ],
    };

void main() {
  test('adds a rep on the same weight while below the top of the range', () {
    final targets = buildSetTargets(
      workouts: [
        _workout(1, DateTime(2026, 10, 20), [(80, 7), (80, 6)])
      ],
      templates: const [],
    );

    final target = targets['жим лежа']!;
    expect(target.weight, 80);
    expect(target.reps, 8);
    expect(target.change, '+1 повт.');
    expect(target.label, '80 × 8');
  });

  test('adds weight after the top of the range is hit three times', () {
    final targets = buildSetTargets(
      workouts: [
        _workout(1, DateTime(2026, 10, 1), [(80, 10)]),
        _workout(2, DateTime(2026, 10, 8), [(80, 10)]),
        _workout(3, DateTime(2026, 10, 15), [(80, 10)]),
      ],
      templates: const [],
    );

    final target = targets['жим лежа']!;
    expect(target.weight, greaterThan(80));
    expect(target.reps, 6);
    expect(target.change, startsWith('+'));
  });

  test('uses the template rep range', () {
    final targets = buildSetTargets(
      workouts: [
        _workout(1, DateTime(2026, 10, 20), [(80, 12)])
      ],
      templates: [
        {
          'exercises': [
            {'exercise_name': 'Жим лёжа', 'target_reps': '10-15'},
          ],
        },
      ],
    );

    expect(targets['жим лежа']!.reps, 13);
  });

  test('ignores the current and unfinished workouts', () {
    final targets = buildSetTargets(
      workouts: [
        _workout(1, DateTime(2026, 10, 20), [(80, 7)]),
        _workout(2, DateTime(2026, 10, 27), [(100, 3)]),
        _workout(3, DateTime(2026, 10, 26), [(90, 5)], finished: false),
      ],
      templates: const [],
      excludeWorkoutId: 2,
    );

    expect(targets['жим лежа']!.weight, 80);
  });
}
