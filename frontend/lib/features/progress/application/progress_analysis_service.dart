import '../domain/progress_math.dart';
import '../domain/progress_models.dart';

class ProgressAnalysisService {
  const ProgressAnalysisService({
    this.defaultRepRange =
        const ExerciseRepRange(lower: 6, upper: 10, source: 'default'),
  });

  final ExerciseRepRange defaultRepRange;

  ProgressAnalysisReport buildReport({
    required List<Map<String, dynamic>> workouts,
    required List<Map<String, dynamic>> templates,
  }) {
    final sessionsByExercise = _buildSessionsByExercise(workouts, templates);
    final analyses = sessionsByExercise.entries
        .map((entry) => _analyzeExercise(entry.key, entry.value, templates))
        .toList()
      ..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));

    final readyToIncrease = analyses
        .where((item) => item.decision == ProgressDecision.increase)
        .toList();
    final attentionNeeded = analyses
        .where(
          (item) =>
              item.decision == ProgressDecision.decrease ||
              item.decision == ProgressDecision.insufficientData ||
              item.isStalled,
        )
        .toList();
    final keepWorking = analyses
        .where((item) =>
            !readyToIncrease.contains(item) && !attentionNeeded.contains(item))
        .toList();

    return ProgressAnalysisReport(
      readyToIncrease: readyToIncrease,
      keepWorking: keepWorking,
      attentionNeeded: attentionNeeded,
      allExercises: analyses,
    );
  }

  Map<String, List<ExerciseSessionPerformance>> _buildSessionsByExercise(
    List<Map<String, dynamic>> workouts,
    List<Map<String, dynamic>> templates,
  ) {
    final repRanges = _resolveRepRanges(templates);
    final grouped = <String, List<ExerciseSessionPerformance>>{};
    final latestNameByKey = <String, String>{};
    final latestDateByKey = <String, DateTime>{};

    for (final workout in workouts) {
      final performedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      if (performedAt == null) {
        continue;
      }

      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawExercise in exercises) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final exerciseName =
            (exercise['exercise_name'] ?? '').toString().trim();
        if (exerciseName.isEmpty) {
          continue;
        }

        final catalogId = exercise['catalog_exercise_id'];
        final canonicalKey = catalogId != null
            ? 'c:$catalogId'
            : 'n:${_normalizeExerciseLookupName(exerciseName)}';

        final prevDate = latestDateByKey[canonicalKey];
        if (prevDate == null || performedAt.isAfter(prevDate)) {
          latestDateByKey[canonicalKey] = performedAt;
          latestNameByKey[canonicalKey] = exerciseName;
        }

        final repRange =
            repRanges[_normalizeExerciseLookupName(exerciseName)] ??
                repRanges[_normalizeExerciseLookupName(
                  latestNameByKey[canonicalKey] ?? exerciseName,
                )] ??
                defaultRepRange;
        final session = _buildSessionPerformance(
          exerciseName: exerciseName,
          performedAt: performedAt,
          repRange: repRange,
          sets: (exercise['sets'] as List?)?.cast<dynamic>() ?? const [],
        );
        if (session == null) {
          continue;
        }

        grouped.putIfAbsent(canonicalKey, () => []).add(session);
      }
    }

    for (final sessions in grouped.values) {
      sessions.sort((a, b) => a.performedAt.compareTo(b.performedAt));
    }

    final result = <String, List<ExerciseSessionPerformance>>{};
    for (final entry in grouped.entries) {
      final name = latestNameByKey[entry.key] ?? entry.key;
      result[name] = entry.value;
    }

    return result;
  }

  ExerciseSessionPerformance? _buildSessionPerformance({
    required String exerciseName,
    required DateTime performedAt,
    required ExerciseRepRange repRange,
    required List<dynamic> sets,
  }) {
    ExerciseSetPerformance? topSet;
    var totalSets = 0;
    var setsAtWorkingWeight = 0;
    final rpeAtWorkingWeight = <double>[];

    for (final rawSet in sets) {
      final set = (rawSet as Map).cast<String, dynamic>();
      final reps = set['reps'] as int?;
      final weightValue = set['weight'];
      final weight = weightValue is num ? weightValue.toDouble() : null;
      if (reps == null || weight == null || weight <= 0) {
        continue;
      }

      totalSets += 1;
      final performance = ExerciseSetPerformance(
        reps: reps,
        weight: weight,
        estimated1rm: estimatedOneRepMax(weight: weight, reps: reps),
        normalizedWeight: normalizedWeight(
          weight: weight,
          reps: reps,
          targetReps: repRange.targetReps,
        ),
      );

      if (topSet == null ||
          performance.weight > topSet.weight ||
          (performance.weight == topSet.weight &&
              performance.reps > topSet.reps)) {
        topSet = performance;
      }
    }

    if (topSet == null || totalSets == 0) {
      return null;
    }

    for (final rawSet in sets) {
      final set = (rawSet as Map).cast<String, dynamic>();
      final reps = set['reps'] as int?;
      final weightValue = set['weight'];
      final weight = weightValue is num ? weightValue.toDouble() : null;
      if (reps == null || weight == null || weight <= 0) {
        continue;
      }
      if ((weight - topSet.weight).abs() > 0.001) {
        continue;
      }

      setsAtWorkingWeight += 1;
      final rpeValue = set['rpe'];
      final rpe = rpeValue is num ? rpeValue.toDouble() : null;
      if (rpe != null && rpe >= 0 && rpe <= 10) {
        rpeAtWorkingWeight.add(rpe);
      }
    }

    return ExerciseSessionPerformance(
      exerciseName: exerciseName,
      performedAt: performedAt,
      workingSet: topSet,
      totalSets: totalSets,
      setsAtWorkingWeight: setsAtWorkingWeight,
      averageRpeAtWorkingWeight: rpeAtWorkingWeight.isEmpty
          ? null
          : rpeAtWorkingWeight.reduce((a, b) => a + b) /
              rpeAtWorkingWeight.length,
      hitUpperBound: topSet.reps >= repRange.upper,
      missedLowerBound: topSet.reps < repRange.lower,
    );
  }

  ExerciseProgressAnalysis _analyzeExercise(
    String exerciseName,
    List<ExerciseSessionPerformance> sessions,
    List<Map<String, dynamic>> templates,
  ) {
    final repRange = _resolveRepRanges(
            templates)[_normalizeExerciseLookupName(exerciseName)] ??
        defaultRepRange;
    final recent =
        sessions.length <= 5 ? sessions : sessions.sublist(sessions.length - 5);
    final latest = recent.last;
    final step = _inferWeightStep(recent);

    if (recent.length < 3) {
      return ExerciseProgressAnalysis(
        exerciseName: exerciseName,
        repRange: repRange,
        decision: ProgressDecision.insufficientData,
        recommendedNextWeight: latest.workingSet.weight,
        deltaWeight: 0,
        confidenceScore: _roundScore(recent.length / 3 * 0.45),
        reason:
            'Нужно еще минимум ${3 - recent.length} тренировки для уверенного вывода.',
        sessions: recent,
        isStalled: false,
      );
    }

    final lastThree = recent.sublist(recent.length - 3);
    final upperHits = lastThree.where((item) => item.hitUpperBound).length;
    final lowerMisses = lastThree.where((item) => item.missedLowerBound).length;
    final normalizedTrend = _relativeChange(
      first: lastThree.first.workingSet.normalizedWeight,
      last: lastThree.last.workingSet.normalizedWeight,
    );
    final oneRmTrend = _relativeChange(
      first: lastThree.first.workingSet.estimated1rm,
      last: lastThree.last.workingSet.estimated1rm,
    );
    final currentWeight = latest.workingSet.weight;
    final consistency = _consistencyScore(lastThree);
    final rpeSignal = _buildRpeSignal(lastThree);
    final plateau = upperHits == 0 &&
        normalizedTrend.abs() <= 0.015 &&
        oneRmTrend.abs() <= 0.015;

    if (upperHits >= 2 &&
        normalizedTrend >= -0.02 &&
        oneRmTrend >= -0.02 &&
        rpeSignal.allowsIncrease) {
      final nextWeight = roundWeight(currentWeight + step, step: step);
      return ExerciseProgressAnalysis(
        exerciseName: exerciseName,
        repRange: repRange,
        decision: ProgressDecision.increase,
        recommendedNextWeight: nextWeight,
        deltaWeight: roundWeight(nextWeight - currentWeight, step: 0.5),
        confidenceScore: _roundScore(
          0.72 +
              consistency * 0.2 +
              _dataBonus(recent.length) +
              rpeSignal.confidenceAdjustment,
        ),
        reason: rpeSignal.hasData
            ? 'Последние 3 тренировки уверенно закрывают верх диапазона ${repRange.label}, и RPE еще остается контролируемым.'
            : 'Последние 3 тренировки уверенно закрывают верх диапазона ${repRange.label}.',
        sessions: recent,
        isStalled: false,
      );
    }

    if (lowerMisses >= 2 &&
        normalizedTrend <= -0.04 &&
        oneRmTrend <= -0.04 &&
        rpeSignal.supportsDecrease) {
      final nextWeight = roundWeight(
        (currentWeight - step).clamp(0, double.infinity),
        step: step,
      );
      return ExerciseProgressAnalysis(
        exerciseName: exerciseName,
        repRange: repRange,
        decision: ProgressDecision.decrease,
        recommendedNextWeight: nextWeight,
        deltaWeight: roundWeight(nextWeight - currentWeight, step: 0.5),
        confidenceScore: _roundScore(
          0.66 +
              consistency * 0.16 +
              _dataBonus(recent.length) +
              rpeSignal.confidenceAdjustment,
        ),
        reason: rpeSignal.hasData
            ? 'Повторы ниже ${repRange.lower}, сила просела, а RPE показывает, что рабочий вес стал слишком тяжелым.'
            : 'Повторы ниже ${repRange.lower}, а сила и нормализованный вес просели.',
        sessions: recent,
        isStalled: true,
      );
    }

    final isStalled = plateau ||
        (upperHits < 2 &&
            normalizedTrend.abs() <= 0.015 &&
            oneRmTrend.abs() <= 0.015);
    final reason = rpeSignal.blocksIncreaseBecauseTooHard
        ? 'Вес пока лучше оставить: верх диапазона близко, но RPE уже слишком высокий.'
        : (isStalled
            ? 'Прогресс застопорился: верх диапазона пока не стабилен.'
            : 'Вес пока лучше оставить: верх диапазона ${repRange.label} еще не закреплен.');

    return ExerciseProgressAnalysis(
      exerciseName: exerciseName,
      repRange: repRange,
      decision: ProgressDecision.keep,
      recommendedNextWeight: currentWeight,
      deltaWeight: 0,
      confidenceScore: _roundScore(
        0.58 +
            consistency * 0.14 +
            _dataBonus(recent.length) +
            rpeSignal.confidenceAdjustment,
      ),
      reason: reason,
      sessions: recent,
      isStalled: isStalled,
    );
  }

  Map<String, ExerciseRepRange> _resolveRepRanges(
      List<Map<String, dynamic>> templates) {
    final result = <String, ExerciseRepRange>{};

    for (final template in templates.reversed) {
      final exercises =
          (template['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawExercise in exercises) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final name = (exercise['exercise_name'] ?? '').toString().trim();
        final normalizedName = _normalizeExerciseLookupName(name);
        if (normalizedName.isEmpty || result.containsKey(normalizedName)) {
          continue;
        }

        final targetReps = (exercise['target_reps'] ?? '').toString().trim();
        result[normalizedName] = _parseRepRange(targetReps) ?? defaultRepRange;
      }
    }

    return result;
  }

  ExerciseRepRange? _parseRepRange(String value) {
    if (value.isEmpty) {
      return null;
    }

    final normalized = value.replaceAll(' ', '');
    final rangeMatch = RegExp(r'^(\d+)-(\d+)$').firstMatch(normalized);
    if (rangeMatch != null) {
      final lower = int.parse(rangeMatch.group(1)!);
      final upper = int.parse(rangeMatch.group(2)!);
      if (lower > 0 && upper >= lower) {
        return ExerciseRepRange(lower: lower, upper: upper, source: value);
      }
    }

    final single = int.tryParse(normalized);
    if (single != null && single > 0) {
      return ExerciseRepRange(lower: single, upper: single, source: value);
    }

    return null;
  }

  double _inferWeightStep(List<ExerciseSessionPerformance> sessions) {
    final weights =
        sessions.map((item) => item.workingSet.weight).toSet().toList()..sort();
    var minStep = double.infinity;

    for (var index = 1; index < weights.length; index++) {
      final diff = weights[index] - weights[index - 1];
      if (diff > 0.24 && diff < minStep) {
        minStep = diff;
      }
    }

    if (minStep.isFinite) {
      return roundWeight(minStep, step: 0.25);
    }

    final latestWeight = sessions.last.workingSet.weight;
    if (latestWeight < 20) {
      return 1;
    }
    if (latestWeight < 60) {
      return 2.5;
    }
    return 5;
  }

  double _relativeChange({
    required double first,
    required double last,
  }) {
    if (first <= 0) {
      return 0;
    }
    return (last - first) / first;
  }

  double _consistencyScore(List<ExerciseSessionPerformance> sessions) {
    final weights = sessions.map((item) => item.workingSet.weight).toList();
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    if ((maxWeight - minWeight).abs() <= 0.001) {
      return 1;
    }
    final spread = (maxWeight - minWeight) / maxWeight;
    return (1 - spread).clamp(0, 1).toDouble();
  }

  double _dataBonus(int count) {
    return ((count - 3) * 0.04).clamp(0, 0.12).toDouble();
  }

  double _roundScore(double value) {
    return double.parse(value.clamp(0, 0.99).toStringAsFixed(2));
  }
}

_RpeSignal _buildRpeSignal(List<ExerciseSessionPerformance> sessions) {
  final values = sessions
      .map((item) => item.averageRpeAtWorkingWeight)
      .whereType<double>()
      .toList();
  if (values.isEmpty) {
    return const _RpeSignal(
      hasData: false,
      allowsIncrease: true,
      supportsDecrease: true,
      blocksIncreaseBecauseTooHard: false,
      confidenceAdjustment: 0,
    );
  }

  final average = values.reduce((a, b) => a + b) / values.length;

  var confidenceAdjustment = 0.0;
  if (average <= 8.5) {
    confidenceAdjustment = 0.04;
  } else if (average > 9.0 && average < 9.3) {
    confidenceAdjustment = -0.03;
  } else if (average >= 9.5) {
    confidenceAdjustment = 0.03;
  }

  return _RpeSignal(
    hasData: true,
    allowsIncrease: average <= 9.0,
    supportsDecrease: average >= 9.3,
    blocksIncreaseBecauseTooHard: average > 9.0,
    confidenceAdjustment: confidenceAdjustment,
  );
}

class _RpeSignal {
  const _RpeSignal({
    required this.hasData,
    required this.allowsIncrease,
    required this.supportsDecrease,
    required this.blocksIncreaseBecauseTooHard,
    required this.confidenceAdjustment,
  });

  final bool hasData;
  final bool allowsIncrease;
  final bool supportsDecrease;
  final bool blocksIncreaseBecauseTooHard;
  final double confidenceAdjustment;
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}
