class MuscleLoadNormalizer {
  const MuscleLoadNormalizer();

  Map<String, double> normalize(Map<String, double> loads) {
    return {
      for (final entry in loads.entries)
        entry.key: entry.value < 0 ? 0 : entry.value,
    };
  }
}
