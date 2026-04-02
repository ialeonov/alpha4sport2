import 'package:alpha4sport_app/features/progress/application/progress_analysis_service.dart';
import 'package:alpha4sport_app/features/progress/domain/progress_math.dart';
import 'package:alpha4sport_app/features/progress/domain/progress_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('progress math', () {
    test('calculates estimated 1RM by formula', () {
      final result = estimatedOneRepMax(weight: 100, reps: 10);
      expect(result, closeTo(133.33, 0.01));
    });

    test('calculates normalized weight by formula', () {
      final result = normalizedWeight(weight: 100, reps: 8, targetReps: 10);
      expect(result, closeTo(93.10, 0.01));
    });
  });

  group('ProgressAnalysisService', () {
    const service = ProgressAnalysisService();

    test('selects top set by heaviest weight and then reps', () {
      final report = service.buildReport(
        workouts: [
          _workoutWithSets('2026-03-01T10:00:00Z', 'Bench Press', [
            _set(weight: 60, reps: 10),
            _set(weight: 70, reps: 8),
            _set(weight: 75, reps: 6),
            _set(weight: 75, reps: 7),
          ]),
          _workout('2026-03-05T10:00:00Z', 'Bench Press', weight: 75, reps: 7),
          _workout('2026-03-09T10:00:00Z', 'Bench Press', weight: 75, reps: 7),
        ],
        templates: [_template('Bench Press', '6-8')],
      );

      final workingSet = report.allExercises.single.sessions.first.workingSet;
      expect(workingSet.weight, 75);
      expect(workingSet.reps, 7);
    });

    test(
        'does not choose lighter set with better normalized weight over heavier top set',
        () {
      final report = service.buildReport(
        workouts: [
          _workoutWithSets('2026-03-01T10:00:00Z', 'Bench Press', [
            _set(weight: 90, reps: 12),
            _set(weight: 100, reps: 8),
          ]),
          _workout('2026-03-05T10:00:00Z', 'Bench Press', weight: 100, reps: 8),
          _workout('2026-03-09T10:00:00Z', 'Bench Press', weight: 100, reps: 8),
        ],
        templates: [_template('Bench Press', '8-10')],
      );

      final workingSet = report.allExercises.single.sessions.first.workingSet;
      expect(workingSet.weight, 100);
      expect(workingSet.reps, 8);
    });

    test('returns increase when two of last three top sets hit upper bound',
        () {
      final report = service.buildReport(
        workouts: [
          _workout('2026-03-01T10:00:00Z', 'Bench Press', weight: 75, reps: 7),
          _workout('2026-03-05T10:00:00Z', 'Bench Press', weight: 75, reps: 8),
          _workout('2026-03-09T10:00:00Z', 'Bench Press', weight: 75, reps: 8),
        ],
        templates: [_template('Bench Press', '6-8')],
      );

      final analysis = report.allExercises.single;
      expect(analysis.decision, ProgressDecision.increase);
      expect(analysis.recommendedNextWeight, 80);
      expect(analysis.deltaWeight, 5);
      expect(analysis.confidenceScore, greaterThan(0.7));
    });

    test('returns keep when upper range is not stable yet', () {
      final report = service.buildReport(
        workouts: [
          _workout('2026-03-01T10:00:00Z', 'Row', weight: 75, reps: 6),
          _workout('2026-03-05T10:00:00Z', 'Row', weight: 75, reps: 7),
          _workout('2026-03-09T10:00:00Z', 'Row', weight: 75, reps: 8),
        ],
        templates: [_template('Row', '6-8')],
      );

      final analysis = report.allExercises.single;
      expect(analysis.decision, ProgressDecision.keep);
      expect(analysis.recommendedNextWeight, 75);
      expect(analysis.deltaWeight, 0);
    });

    test('returns decrease when user misses lower bound and metrics worsen',
        () {
      final report = service.buildReport(
        workouts: [
          _workout('2026-03-01T10:00:00Z', 'Squat', weight: 80, reps: 5),
          _workout('2026-03-05T10:00:00Z', 'Squat', weight: 75, reps: 5),
          _workout('2026-03-09T10:00:00Z', 'Squat', weight: 75, reps: 4),
        ],
        templates: [_template('Squat', '6-8')],
      );

      final analysis = report.allExercises.single;
      expect(analysis.decision, ProgressDecision.decrease);
      expect(analysis.recommendedNextWeight, 70);
      expect(analysis.deltaWeight, -5);
      expect(analysis.isStalled, isTrue);
    });

    test(
        'returns insufficient data when fewer than three sessions are available',
        () {
      final report = service.buildReport(
        workouts: [
          _workout('2026-03-01T10:00:00Z', 'Overhead Press',
              weight: 40, reps: 8),
          _workout('2026-03-05T10:00:00Z', 'Overhead Press',
              weight: 40, reps: 9),
        ],
        templates: [_template('Overhead Press', '6-10')],
      );

      final analysis = report.allExercises.single;
      expect(analysis.decision, ProgressDecision.insufficientData);
      expect(analysis.recommendedNextWeight, 40);
      expect(analysis.deltaWeight, 0);
    });
  });
}

Map<String, dynamic> _set({
  required double weight,
  required int reps,
}) {
  return {
    'reps': reps,
    'weight': weight,
  };
}

Map<String, dynamic> _workout(
  String startedAt,
  String exerciseName, {
  required double weight,
  required int reps,
}) {
  return _workoutWithSets(startedAt, exerciseName, [
    _set(weight: weight, reps: reps),
    _set(weight: weight, reps: reps),
    _set(weight: weight, reps: reps),
  ]);
}

Map<String, dynamic> _workoutWithSets(
  String startedAt,
  String exerciseName,
  List<Map<String, dynamic>> sets,
) {
  return {
    'started_at': startedAt,
    'exercises': [
      {
        'exercise_name': exerciseName,
        'sets': sets,
      },
    ],
  };
}

Map<String, dynamic> _template(String exerciseName, String targetReps) {
  return {
    'exercises': [
      {
        'exercise_name': exerciseName,
        'target_reps': targetReps,
      },
    ],
  };
}
