enum ProgressDecision {
  increase,
  keep,
  decrease,
  insufficientData,
}

class ExerciseRepRange {
  const ExerciseRepRange({
    required this.lower,
    required this.upper,
    required this.source,
  });

  final int lower;
  final int upper;
  final String source;

  int get targetReps => upper;

  String get label => '$lower-$upper';
}

class ExerciseSetPerformance {
  const ExerciseSetPerformance({
    required this.reps,
    required this.weight,
    required this.estimated1rm,
    required this.normalizedWeight,
  });

  final int reps;
  final double weight;
  final double estimated1rm;
  final double normalizedWeight;
}

class ExerciseSessionPerformance {
  const ExerciseSessionPerformance({
    required this.exerciseName,
    required this.performedAt,
    required this.workingSet,
    required this.totalSets,
    required this.setsAtWorkingWeight,
    required this.hitUpperBound,
    required this.missedLowerBound,
  });

  final String exerciseName;
  final DateTime performedAt;
  final ExerciseSetPerformance workingSet;
  final int totalSets;
  final int setsAtWorkingWeight;
  final bool hitUpperBound;
  final bool missedLowerBound;
}

class ExerciseProgressAnalysis {
  const ExerciseProgressAnalysis({
    required this.exerciseName,
    required this.repRange,
    required this.decision,
    required this.recommendedNextWeight,
    required this.deltaWeight,
    required this.confidenceScore,
    required this.reason,
    required this.sessions,
    required this.isStalled,
  });

  final String exerciseName;
  final ExerciseRepRange repRange;
  final ProgressDecision decision;
  final double recommendedNextWeight;
  final double deltaWeight;
  final double confidenceScore;
  final String reason;
  final List<ExerciseSessionPerformance> sessions;
  final bool isStalled;

  ExerciseSessionPerformance? get latestSession =>
      sessions.isEmpty ? null : sessions.last;
}

class ProgressAnalysisReport {
  const ProgressAnalysisReport({
    required this.readyToIncrease,
    required this.keepWorking,
    required this.attentionNeeded,
    required this.allExercises,
  });

  final List<ExerciseProgressAnalysis> readyToIncrease;
  final List<ExerciseProgressAnalysis> keepWorking;
  final List<ExerciseProgressAnalysis> attentionNeeded;
  final List<ExerciseProgressAnalysis> allExercises;
}
