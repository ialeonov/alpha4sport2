import 'package:alpha4sport_app/features/today/domain/today_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _workout(
  DateTime day,
  List<Map<String, dynamic>> exercises, {
  bool finished = true,
}) =>
    {
      'started_at': day.toIso8601String(),
      'finished_at': finished ? day.toIso8601String() : null,
      'exercises': exercises,
    };

Map<String, dynamic> _exercise(
  int catalogId,
  String name,
  List<(double?, int)> sets, {
  int warmups = 0,
}) =>
    {
      'catalog_exercise_id': catalogId,
      'exercise_name': name,
      'sets': [
        for (var i = 0; i < warmups; i++)
          {'weight': 20, 'reps': 15, 'set_type': 'warmup'},
        for (final set in sets)
          {'weight': set.$1, 'reps': set.$2, 'set_type': 'work'},
      ],
    };

void main() {
  final catalog = [
    {'id': 1, 'name': 'Присед', 'primary_muscle': 'квадрицепсы'},
    {'id': 2, 'name': 'Жим лёжа', 'primary_muscle': 'грудь'},
    {'id': 3, 'name': 'Тяга блока', 'primary_muscle': 'широчайшие'},
    {'id': 4, 'name': 'Махи', 'primary_muscle': 'средние_дельты'},
    {'id': 5, 'name': 'Сгибание рук', 'primary_muscle': 'бицепс'},
    {'id': 6, 'name': 'Подтягивания', 'primary_muscle': 'широчайшие'},
  ];
  final now = DateTime(2026, 10, 27, 9);

  test('focuses on the two main groups trained longest ago', () {
    final plan = buildTodayPlan(
      workouts: [
        _workout(DateTime(2026, 10, 26), [
          _exercise(2, 'Жим лёжа', [(80, 8)]),
          _exercise(5, 'Сгибание рук', [(15, 12)]),
        ]),
        _workout(DateTime(2026, 10, 20), [
          _exercise(3, 'Тяга блока', [(60, 10)]),
        ]),
        _workout(DateTime(2026, 10, 7), [
          _exercise(1, 'Присед', [(80, 8)]),
          _exercise(4, 'Махи', [(10, 15)]),
        ]),
      ],
      exerciseCatalog: catalog,
      now: now,
    )!;

    expect(plan.groups.map((g) => g.label), ['Ноги', 'Плечи']);
    expect(plan.groups.first.daysSince, 20);
    expect(plan.headline, 'НОГИ И ПЛЕЧИ');
    expect(plan.workoutName, 'Ноги + плечи');
    expect(plan.exercises.map((e) => e.name), ['Присед', 'Махи']);
  });

  test(
      'takes sets, reps and top weight from the last session, skipping warmups',
      () {
    final plan = buildTodayPlan(
      workouts: [
        _workout(DateTime(2026, 10, 20), [
          _exercise(1, 'Присед', [(90, 6), (85, 8), (85, 8)], warmups: 2),
        ]),
        _workout(DateTime(2026, 10, 10), [
          _exercise(1, 'Присед', [(80, 8)]),
        ]),
      ],
      exerciseCatalog: catalog,
      now: now,
    )!;

    final squat = plan.exercises.single;
    expect(squat.sets, 3);
    expect(squat.weight, 90);
    expect(squat.reps, 6);

    final prepared = plan.toWorkoutExercises().single;
    expect((prepared['sets'] as List).length, 3);
    expect((prepared['sets'] as List).first['weight'], isNull);
  });

  test('prefers the exercises done most often within a group', () {
    final plan = buildTodayPlan(
      workouts: [
        _workout(DateTime(2026, 10, 1), [
          _exercise(6, 'Подтягивания', [(null, 8)]),
        ]),
        _workout(DateTime(2026, 9, 25), [
          _exercise(3, 'Тяга блока', [(60, 10)]),
        ]),
        _workout(DateTime(2026, 9, 20), [
          _exercise(3, 'Тяга блока', [(55, 10)]),
        ]),
      ],
      exerciseCatalog: catalog,
      now: now,
    )!;

    expect(plan.exercises.map((e) => e.name), ['Тяга блока', 'Подтягивания']);
    expect(plan.exercises.last.weight, isNull);
  });

  test('ignores unfinished workouts and returns null without history', () {
    final plan = buildTodayPlan(
      workouts: [
        _workout(
          DateTime(2026, 10, 26),
          [
            _exercise(1, 'Присед', [(80, 8)])
          ],
          finished: false,
        ),
      ],
      exerciseCatalog: catalog,
      now: now,
    );
    expect(plan, isNull);
  });
}
