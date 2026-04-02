double estimatedOneRepMax({
  required double weight,
  required int reps,
}) {
  if (weight <= 0 || reps <= 0 || reps >= 37) {
    return weight > 0 ? weight : 0;
  }
  return weight * 36 / (37 - reps);
}

double normalizedWeight({
  required double weight,
  required int reps,
  required int targetReps,
}) {
  if (weight <= 0 ||
      reps <= 0 ||
      reps >= 37 ||
      targetReps <= 0 ||
      targetReps >= 37) {
    return weight > 0 ? weight : 0;
  }
  return weight * (37 - targetReps) / (37 - reps);
}

double roundWeight(double value, {double step = 0.5}) {
  if (step <= 0) {
    return value;
  }
  final rounded = (value / step).round() * step;
  return double.parse(rounded.toStringAsFixed(step < 1 ? 2 : 1));
}
