class MuscleZoneDefinition {
  const MuscleZoneDefinition({
    required this.muscle,
    required this.label,
    required this.svgIds,
  });

  final String muscle;
  final String label;
  final List<String> svgIds;
}

class MuscleHeatmapAssetData {
  const MuscleHeatmapAssetData({
    required this.zones,
    required this.zoneLabels,
    required this.muscleToSvgIds,
    required this.allMappableSvgIds,
    required this.defaultFill,
    required this.svgSource,
  });

  final List<MuscleZoneDefinition> zones;
  final Map<String, String> zoneLabels;
  final Map<String, List<String>> muscleToSvgIds;
  final List<String> allMappableSvgIds;
  final String defaultFill;
  final String svgSource;
}

class TopMuscleLoad {
  const TopMuscleLoad({
    required this.muscle,
    required this.label,
    required this.rawLoad,
    required this.normalizedLoad,
  });

  final String muscle;
  final String label;
  final double rawLoad;
  final double normalizedLoad;
}
