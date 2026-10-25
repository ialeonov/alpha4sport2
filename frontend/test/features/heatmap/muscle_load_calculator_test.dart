import 'package:alpha4sport_app/features/heatmap/domain/muscle_heatmap_color_resolver.dart';
import 'package:alpha4sport_app/features/heatmap/domain/muscle_load_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalog = [
  {
    'id': 1,
    'name': 'Жим лёжа',
    'primary_muscle': 'грудь',
    'secondary_muscles': ['трицепс', 'передние_дельты', 'кор'],
  },
  {
    'id': 2,
    'name': 'Махи в стороны',
    'primary_muscle': 'средние_дельты',
    'secondary_muscles': <String>[],
  },
  {
    'id': 3,
    'name': 'Подтягивания',
    'primary_muscle': 'широчайшие',
    'secondary_muscles': ['бицепс', 'разгибатель_спины'],
  },
];

Map<String, dynamic> _workout(
  List<Map<String, dynamic>> exercises, {
  String startedAt = '2026-10-20T10:00:00',
}) =>
    {'started_at': startedAt, 'exercises': exercises};

Map<String, dynamic> _exercise(int id, List<Map<String, dynamic>> sets) =>
    {'catalog_exercise_id': id, 'exercise_name': '', 'sets': sets};

void main() {
  const calculator = MuscleLoadCalculator();

  group('MuscleLoadCalculator', () {
    test('counts each hard working set as one effective set', () {
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(1, [
            {'reps': 8, 'weight': 80},
            {'reps': 8, 'weight': 80},
            {'reps': 8, 'weight': 80},
          ]),
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['грудь'], closeTo(3.0, 1e-9));
      expect(loads['трицепс'], closeTo(1.5, 1e-9));
      expect(loads['кор'], closeTo(0.6, 1e-9));
    });

    test('light isolation work is not penalised by absolute weight', () {
      // Раньше 3×15 по 10 кг давали 1.33 «балла» и мышца оставалась серой.
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(2, [
            for (var i = 0; i < 3; i++) {'reps': 15, 'weight': 10},
          ]),
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['средние_дельты'], closeTo(3.0, 1e-9));
      expect(MuscleHeatmapScale.session.level(loads['средние_дельты']!), 2);
    });

    test('ignores warmup sets', () {
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(1, [
            {'reps': 10, 'weight': 40, 'set_type': 'warmup'},
            {'reps': 8, 'weight': 80, 'set_type': 'work'},
          ]),
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['грудь'], closeTo(1.0, 1e-9));
    });

    test('uses RPE when present', () {
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(1, [
            {'reps': 8, 'weight': 80, 'rpe': 9},
            {'reps': 8, 'weight': 80, 'rpe': 7},
            {'reps': 8, 'weight': 80, 'rpe': 5},
          ]),
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['грудь'], closeTo(1.0 + 0.85 + 0.45, 1e-9));
    });

    test('discounts sets far below the personal best of the exercise', () {
      final history = _workout([
        _exercise(1, [
          {'reps': 5, 'weight': 100}, // e1RM ≈ 116.7
        ]),
      ], startedAt: '2026-10-01T10:00:00');

      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(1, [
            {'reps': 10, 'weight': 40}, // e1RM ≈ 53 → далеко от отказа
          ]),
        ]),
        exerciseCatalog: _catalog,
        referenceWorkouts: [history],
      );

      expect(loads['грудь'], closeTo(0.3, 1e-9));
    });

    test('applies diminishing returns within one session only', () {
      Map<String, dynamic> session(String date, int sets) => _workout([
            _exercise(2, [
              for (var i = 0; i < sets; i++) {'reps': 12, 'weight': 10},
            ]),
          ], startedAt: date);

      final single = calculator.calculateForWorkout(
        workout: session('2026-10-20T10:00:00', 12),
        exerciseCatalog: _catalog,
      );
      // 6 + 4×0.7 + 2×0.4
      expect(single['средние_дельты'], closeTo(9.6, 1e-9));

      final week = calculator.calculate(
        workouts: [
          session('2026-10-20T10:00:00', 6),
          session('2026-10-23T10:00:00', 6),
        ],
        exerciseCatalog: _catalog,
      );
      expect(week['средние_дельты'], closeTo(12.0, 1e-9));
    });

    test('bodyweight sets count fully, merges back extensors into core', () {
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          _exercise(3, [
            {'reps': 10, 'weight': null},
            {'reps': 8},
          ]),
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['широчайшие'], closeTo(2.0, 1e-9));
      expect(loads['бицепс'], closeTo(1.0, 1e-9));
      expect(loads['кор'], closeTo(0.4, 1e-9));
      expect(loads.containsKey('разгибатель_спины'), isFalse);
    });

    test('matches catalog by exercise name when id is missing', () {
      final loads = calculator.calculateForWorkout(
        workout: _workout([
          {
            'exercise_name': 'жим лежа',
            'sets': [
              {'reps': 5, 'weight': 100},
            ],
          },
        ]),
        exerciseCatalog: _catalog,
      );

      expect(loads['грудь'], closeTo(1.0, 1e-9));
    });

    test('lastTrainedAt returns the latest meaningful session per muscle', () {
      final result = calculator.lastTrainedAt(
        workouts: [
          _workout([
            _exercise(1, [
              {'reps': 8, 'weight': 80},
            ]),
          ], startedAt: '2026-10-10T10:00:00'),
          _workout([
            _exercise(1, [
              {'reps': 8, 'weight': 80},
            ]),
          ], startedAt: '2026-10-20T10:00:00'),
        ],
        exerciseCatalog: _catalog,
      );

      expect(result['грудь']!.day, 20);
      // Трицепс получает 0.5 подхода — ниже порога «тренировалась».
      expect(result.containsKey('трицепс'), isFalse);
    });
  });

  group('MuscleHeatmapScale', () {
    test('session and week bands', () {
      expect(MuscleHeatmapScale.session.level(0.2), 0);
      expect(MuscleHeatmapScale.session.level(1), 1);
      expect(MuscleHeatmapScale.session.level(3), 2);
      expect(MuscleHeatmapScale.session.level(5), 3);
      expect(MuscleHeatmapScale.session.level(9), 4);

      expect(MuscleHeatmapScale.week.level(0.5), 0);
      expect(MuscleHeatmapScale.week.level(4), 1);
      expect(MuscleHeatmapScale.week.level(8), 2);
      expect(MuscleHeatmapScale.week.level(15), 3);
      expect(MuscleHeatmapScale.week.level(25), 4);
      expect(MuscleHeatmapScale.week.rangeLabel(3), '10–20');
      expect(MuscleHeatmapScale.week.rangeLabel(4), '20+');
    });

    test('resolver adapts inactive color to theme', () {
      const light = MuscleHeatmapColorResolver();
      const dark = MuscleHeatmapColorResolver(dark: true);
      expect(light.resolve(0, MuscleHeatmapScale.week),
          MuscleHeatmapColorResolver.inactiveLight);
      expect(dark.resolve(0, MuscleHeatmapScale.week),
          MuscleHeatmapColorResolver.inactiveDark);
      expect(dark.resolveHex(15, MuscleHeatmapScale.week), '#E53935');
    });
  });
}
