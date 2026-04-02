import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/muscle_heatmap_models.dart';

class MuscleHeatmapAssetLoader {
  const MuscleHeatmapAssetLoader();

  static const _svgPath = 'assets/heatmap/body.svg';
  static const _mapPath = 'assets/heatmap/body_muscle_map.json';

  static Future<MuscleHeatmapAssetData>? _cache;

  Future<MuscleHeatmapAssetData> load() {
    _cache ??= _loadInternal();
    return _cache!;
  }

  Future<MuscleHeatmapAssetData> _loadInternal() async {
    final svgSource = await rootBundle.loadString(_svgPath);
    final mapSource = await rootBundle.loadString(_mapPath);
    final payload = json.decode(mapSource) as Map<String, dynamic>;

    final zones = <MuscleZoneDefinition>[
      ..._parseZones(payload['front_zones']),
      ..._parseZones(payload['back_zones']),
      ..._parseZones(payload['shared_or_optional_zones']),
    ];

    final zoneLabels = <String, String>{
      for (final zone in zones) zone.muscle: zone.label,
    };
    final muscleToSvgIds = <String, List<String>>{
      for (final zone in zones) zone.muscle: zone.svgIds,
    };

    final coloringRules = (payload['coloring_rules'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allMappableSvgIds =
        (payload['all_mappable_svg_ids'] as List?)?.cast<dynamic>().map((value) => value.toString()).toList() ?? const [];

    return MuscleHeatmapAssetData(
      zones: zones,
      zoneLabels: zoneLabels,
      muscleToSvgIds: muscleToSvgIds,
      allMappableSvgIds: allMappableSvgIds,
      defaultFill: (coloringRules['default_fill'] ?? '#E6E6E6').toString(),
      svgSource: svgSource,
    );
  }

  List<MuscleZoneDefinition> _parseZones(dynamic rawZones) {
    final zones = (rawZones as List?)?.cast<dynamic>() ?? const [];
    return zones.whereType<Map>().map((rawZone) {
      final zone = rawZone.cast<String, dynamic>();
      return MuscleZoneDefinition(
        muscle: (zone['muscle'] ?? '').toString(),
        label: (zone['label'] ?? '').toString(),
        svgIds: (zone['svg_ids'] as List?)?.cast<dynamic>().map((value) => value.toString()).toList() ?? const [],
      );
    }).where((zone) => zone.muscle.isNotEmpty).toList();
  }
}
