import 'package:alpha4sport_app/features/heatmap/domain/muscle_heatmap_color_resolver.dart';
import 'package:alpha4sport_app/features/heatmap/domain/muscle_load_calculator.dart';
import 'package:alpha4sport_app/features/heatmap/domain/muscle_load_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MuscleLoadCalculator', () {
    const calculator = MuscleLoadCalculator();

    test('scores working sets by reps band, muscle role, and weight', () {
      final loads = calculator.calculateForWorkout(
        workout: {
          'exercises': [
            {
              'catalog_exercise_id': 1,
              'exercise_name': 'Bench press',
              'sets': [
                {'reps': 10, 'weight': 100},
                {'reps': 8, 'weight': 110},
              ],
            },
          ],
        },
        exerciseCatalog: [
          {
            'id': 1,
            'name': 'Bench press',
            'primary_muscle': 'chest',
            'secondary_muscles': ['triceps', 'front_delts'],
          },
        ],
      );

      // set 1: repFactor=1.0, weightFactor=100/110≈0.909 → score≈0.909
      // set 2: repFactor=1.0, weightFactor=110/110=1.0  → score=1.0
      // chest (primary ×1.0): 0.909 + 1.0 = 1.909
      // triceps/front_delts (secondary ×0.4): (0.909 + 1.0) × 0.4 = 0.764
      expect(loads['chest'], closeTo(1.909, 0.001));
      expect(loads['triceps'], closeTo(0.764, 0.001));
      expect(loads['front_delts'], closeTo(0.764, 0.001));
    });

    test('applies reps correction without depending on weight', () {
      final loads = calculator.calculateForWorkout(
        workout: {
          'exercises': [
            {
              'catalog_exercise_id': 2,
              'exercise_name': 'Pull-up',
              'sets': [
                {'reps': 12, 'weight': null},
                {'reps': 22},
              ],
            },
          ],
        },
        exerciseCatalog: [
          {
            'id': 2,
            'name': 'Pull-up',
            'primary_muscle': 'lats',
            'secondary_muscles': ['biceps'],
          },
        ],
      );

      expect(loads['lats'], closeTo(1.65, 0.001));
      expect(loads['biceps'], closeTo(0.66, 0.001));
    });

    test('matches catalog by exercise name when id is missing', () {
      final loads = calculator.calculateForWorkout(
        workout: {
          'exercises': [
            {
              'exercise_name': 'Squat',
              'sets': [
                {'reps': 5, 'weight': 120},
              ],
            },
          ],
        },
        exerciseCatalog: [
          {
            'id': 5,
            'name': 'Squat',
            'primary_muscle': 'quads',
            'secondary_muscles': ['glutes'],
          },
        ],
      );

      expect(loads['quads'], closeTo(1.0, 0.001));
      expect(loads['glutes'], closeTo(0.4, 0.001));
    });

    test('applies diminishing returns per muscle across accumulated sets', () {
      final loads = calculator.calculateForWorkout(
        workout: {
          'exercises': [
            {
              'catalog_exercise_id': 3,
              'exercise_name': 'Chest fly',
              'sets': List.generate(8, (_) => {'reps': 10, 'weight': 20}),
            },
          ],
        },
        exerciseCatalog: [
          {
            'id': 3,
            'name': 'Chest fly',
            'primary_muscle': 'chest',
            'secondary_muscles': ['front_delts'],
          },
        ],
      );

      expect(loads['chest'], closeTo(7.0, 0.001));
      expect(loads['front_delts'], closeTo(2.8, 0.001));
    });

    test('applies stabilizer factor to кор instead of secondary factor', () {
      // кор is in stabilizerMuscles by default and gets stabilizerFactor (0.15),
      // not secondaryMuscleFactor (0.4), so it does not inflate the heatmap
      // when listed as secondary stabilizer in multiple exercises.
      final loads = calculator.calculateForWorkout(
        workout: {
          'exercises': [
            {
              'catalog_exercise_id': 10,
              'exercise_name': 'Bench press',
              'sets': List.generate(3, (_) => {'reps': 8, 'weight': 100}),
            },
            {
              'catalog_exercise_id': 11,
              'exercise_name': 'Shoulder press',
              'sets': List.generate(3, (_) => {'reps': 8, 'weight': 80}),
            },
          ],
        },
        exerciseCatalog: [
          {
            'id': 10,
            'name': 'Bench press',
            'primary_muscle': 'chest',
            'secondary_muscles': ['triceps', 'кор'],
          },
          {
            'id': 11,
            'name': 'Shoulder press',
            'primary_muscle': 'front_delts',
            'secondary_muscles': ['triceps', 'кор'],
          },
        ],
      );

      // triceps: 6 sets × 0.4 secondary (sets 1-4 full, 5-6 ×0.8) = 2×1.0×0.4 + 2×1.0×0.4 + 2×0.8×0.4 = 1.44
      // кор: same 6 sets but factor 0.15 → 2×1.0×0.15 + 2×1.0×0.15 + 2×0.8×0.15 = 0.54
      expect(loads['кор']!, lessThan(loads['triceps']!));
      expect(loads['кор']!, closeTo(0.54, 0.001));
      expect(loads['triceps']!, closeTo(1.44, 0.001));
    });

    test('keeps peak daily load instead of summing across calendar days', () {
      final loads = calculator.calculatePeakForCalendarDays(
        workouts: [
          {
            'started_at': '2026-03-20T09:00:00',
            'exercises': [
              {
                'catalog_exercise_id': 1,
                'exercise_name': 'Bench press',
                'sets': [
                  {'reps': 10, 'weight': 100},
                  {'reps': 8, 'weight': 100},
                ],
              },
            ],
          },
          {
            'started_at': '2026-03-19T09:00:00',
            'exercises': [
              {
                'catalog_exercise_id': 1,
                'exercise_name': 'Bench press',
                'sets': [
                  {'reps': 10, 'weight': 100},
                ],
              },
            ],
          },
        ],
        exerciseCatalog: [
          {
            'id': 1,
            'name': 'Bench press',
            'primary_muscle': 'chest',
            'secondary_muscles': ['triceps'],
          },
        ],
        dayResolver: (workout) =>
            DateTime.parse((workout['started_at'] ?? '').toString()),
      );

      expect(loads['chest'], closeTo(2.0, 0.001));
      expect(loads['triceps'], closeTo(0.8, 0.001));
    });
  });

  group('MuscleLoadNormalizer', () {
    const normalizer = MuscleLoadNormalizer();

    test('preserves absolute loads without leader-based scaling', () {
      final normalized = normalizer.normalize({
        'chest': 100,
        'triceps': 40,
        'biceps': 0,
      });

      expect(normalized['chest'], 100);
      expect(normalized['triceps'], 40);
      expect(normalized['biceps'], 0);
    });
  });

  group('MuscleHeatmapColorResolver', () {
    const resolver = MuscleHeatmapColorResolver();

    test('returns expected color bands', () {
      expect(resolver.resolveHex(0), '#E6E6E6');
      expect(resolver.resolveHex(1.5), '#F4D35E');
      expect(resolver.resolveHex(3.0), '#F28C28');
      expect(resolver.resolveHex(5.0), '#E53935');
    });
  });
}
