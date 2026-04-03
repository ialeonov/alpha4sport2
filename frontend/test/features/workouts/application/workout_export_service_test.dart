import 'package:alpha4sport_app/features/workouts/application/workout_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = WorkoutExportService();

  test('buildExport creates factual workout export with muscles and duration',
      () {
    final export = service.buildExport(
      workouts: [
        {
          'id': 42,
          'started_at': '2026-03-12T08:00:00Z',
          'finished_at': '2026-03-12T09:05:00Z',
          'notes': 'Felt strong',
          'exercises': [
            {
              'catalog_exercise_id': 1,
              'exercise_name': 'Bench Press',
              'sets': [
                {'position': 1, 'reps': 8, 'weight': 80, 'rpe': 8.5},
                {'position': 2, 'reps': 8, 'weight': 85, 'rpe': 9.0},
              ],
            },
          ],
        },
      ],
      rangeFrom: DateTime(2026, 3, 12),
      rangeTo: DateTime(2026, 3, 12),
      exerciseCatalog: [
        {
          'id': 1,
          'name': 'Bench Press',
          'primary_muscle': 'chest',
          'secondary_muscles': ['triceps', 'front_delts'],
        },
      ],
      exportedAt: DateTime.utc(2026, 3, 15, 10, 20),
    );

    expect(export['exported_at'], '2026-03-15T10:20:00.000Z');
    expect(export['range'], {'from': '2026-03-12', 'to': '2026-03-12'});

    final workouts = export['workouts'] as List<dynamic>;
    final workout = workouts.single as Map<String, dynamic>;
    expect(workout['id'], '42');
    expect(workout['date'], '2026-03-12');
    expect(workout['duration_minutes'], 65);
    expect(workout['notes'], 'Felt strong');

    final exercises = workout['exercises'] as List<dynamic>;
    final exercise = exercises.single as Map<String, dynamic>;
    expect(exercise['name'], 'Bench Press');
    expect(exercise['primary_muscle'], 'chest');
    expect(exercise['secondary_muscles'], ['triceps', 'front_delts']);
    expect(exercise['best_set'], {'reps': 8, 'weight': 85, 'rpe': 9});
    expect(
      exercise['sets'],
      [
        {'set_index': 1, 'reps': 8, 'weight': 80, 'rpe': 8.5},
        {'set_index': 2, 'reps': 8, 'weight': 85, 'rpe': 9},
      ],
    );
    expect(export.containsKey('exercise_progress'), isFalse);
    expect(exercise.containsKey('progress_snapshot'), isFalse);
    expect(exercise.containsKey('volume'), isFalse);
  });

  test(
      'buildExport counts reps when weight is missing and picks best set by reps',
      () {
    final export = service.buildExport(
      workouts: [
        {
          'id': 'abc',
          'started_at': '2026-03-10T18:30:00Z',
          'finished_at': null,
          'notes': null,
          'exercises': [
            {
              'exercise_name': 'Pull Up',
              'sets': [
                {'position': 1, 'reps': 10, 'weight': 0},
                {'position': 2, 'reps': 12, 'weight': null},
                {'position': 3, 'reps': 8, 'weight': 0},
              ],
            },
          ],
        },
      ],
      rangeFrom: DateTime(2026, 3, 10),
      rangeTo: DateTime(2026, 3, 10),
      exerciseCatalog: const [],
      exportedAt: DateTime.utc(2026, 3, 15, 10, 20),
    );

    final workouts = export['workouts'] as List<dynamic>;
    final workout = workouts.single as Map<String, dynamic>;
    final exercise =
        (workout['exercises'] as List<dynamic>).single as Map<String, dynamic>;

    expect(exercise['best_set'], {'reps': 12, 'weight': null});
    expect(exercise['primary_muscle'], isNull);
    expect(exercise['secondary_muscles'], isEmpty);
    expect(exercise.containsKey('progress_snapshot'), isFalse);
    expect(exercise.containsKey('volume'), isFalse);
    expect(workout['duration_minutes'], isNull);
  });

  test('parseImportWorkouts loads workouts from app-generated export json', () {
    final imported = service.parseImportWorkouts(
      '''
      {
        "exported_at": "2026-03-15T10:20:00.000Z",
        "workouts": [
          {
            "date": "2026-03-12",
            "exercises": [
              {
                "name": "Bench Press",
                "sets": [
                  {"set_index": 1, "reps": 8, "weight": 80, "rpe": 8.5},
                  {"set_index": 2, "reps": 6, "weight": 85, "rpe": 9.0}
                ]
              }
            ]
          }
        ]
      }
      ''',
      exerciseCatalog: const [
        {'id': 10, 'name': 'Bench Press'},
      ],
      sourceName: 'workouts_2026_03_12.json',
    );

    expect(imported, hasLength(1));
    final workout = imported.single;
    expect(workout.name, 'Импорт 2026-03-12');
    expect(workout.sourceLabel, 'workouts_2026_03_12.json · 2026-03-12');
    expect(workout.date, DateTime(2026, 3, 12));
    expect(workout.exercises, hasLength(1));
    expect(workout.exercises.single['catalog_exercise_id'], 10);
    expect(workout.exercises.single['exercise_name'], 'Bench Press');

    final sets = workout.exercises.single['sets'] as List<dynamic>;
    expect(sets, hasLength(2));
    expect(sets.first['position'], 1);
    expect(sets.first['reps'], 8);
    expect(sets.first['weight'], 80);
    expect(sets.first['rpe'], 8.5);
    expect(sets.last['rpe'], 9.0);
  });

  test('parseImportWorkouts supports backend export shape too', () {
    final imported = service.parseImportWorkouts(
      '''
      {
        "exported_at": "2026-03-15",
        "workouts": [
          {
            "name": "Push Day",
            "started_at": "2026-03-11T07:30:00Z",
            "exercises": [
              {
                "exercise_name": "Pull Up",
                "sets": [
                  {"position": 1, "reps": 10, "weight": null, "rpe": 7.5}
                ]
              }
            ]
          }
        ]
      }
      ''',
    );

    expect(imported, hasLength(1));
    final workout = imported.single;
    expect(workout.name, 'Push Day');
    expect(workout.date, DateTime(2026, 3, 11));
    expect(workout.exercises.single['exercise_name'], 'Pull Up');
    expect(
        (workout.exercises.single['sets'] as List<dynamic>).single['reps'], 10);
    expect(
        (workout.exercises.single['sets'] as List<dynamic>).single['rpe'], 7.5);
  });
}
