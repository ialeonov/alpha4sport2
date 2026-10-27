import '../../../core/utils/formatters.dart';

double calculateSetsTonnage(List<dynamic> sets) {
  return sets.fold<double>(0, (sum, rawSet) {
    if (rawSet is! Map) return sum;
    final set = rawSet.cast<String, dynamic>();
    final reps = _toDouble(set['reps']);
    final weight = _toDouble(set['weight']);
    return sum + (reps * weight);
  });
}

double calculateExerciseTonnage(Map<String, dynamic> exercise) {
  final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
  return calculateSetsTonnage(sets);
}

double calculateWorkoutTonnage(Map<String, dynamic> workout) {
  final exercises =
      (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
  return exercises.fold<double>(0, (sum, rawExercise) {
    if (rawExercise is! Map) return sum;
    return sum + calculateExerciseTonnage(rawExercise.cast<String, dynamic>());
  });
}

/// Тоннаж одинаково везде: «825 кг», «8,2 т».
String formatTonnage(double kilograms) {
  if (kilograms <= 0) {
    return '0 кг';
  }

  if (kilograms >= 1000) {
    return '${formatDecimal(kilograms / 1000)} т';
  }

  return '${kilograms.round()} кг';
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
}
