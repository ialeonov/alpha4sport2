import 'package:xml/xml.dart';

import '../domain/muscle_heatmap_color_resolver.dart';
import '../domain/muscle_heatmap_models.dart';

class BodySvgColorizer {
  const BodySvgColorizer();

  /// Builds a colored SVG from [loads] (effective sets) using [assetData].
  ///
  /// When multiple muscle keys share the same SVG element (e.g.
  /// "средние_дельты" and "передние_дельты" both target the
  /// "передние_дельты" SVG id), the element is colored by the
  /// **highest** load among all contributing muscles.  Without this
  /// rule a low secondary-muscle score can overwrite a higher primary
  /// score accumulated from earlier exercises.
  String colorizeFromLoads({
    required MuscleHeatmapAssetData assetData,
    required Map<String, double> loads,
    required MuscleHeatmapScale scale,
    MuscleHeatmapColorResolver resolver = const MuscleHeatmapColorResolver(),
  }) {
    final inactiveFill = MuscleHeatmapColorResolver.toHex(resolver.inactive);
    final idToColor = <String, String>{
      for (final id in assetData.allMappableSvgIds) id: inactiveFill,
    };
    final idToMaxLoad = <String, double>{};

    loads.forEach((muscle, load) {
      final svgIds = assetData.muscleToSvgIds[muscle] ?? const [];
      for (final svgId in svgIds) {
        if (load > (idToMaxLoad[svgId] ?? 0)) {
          idToMaxLoad[svgId] = load;
          idToColor[svgId] = resolver.resolveHex(load, scale);
        }
      }
    });

    return colorize(
      // Неразмеченные части силуэта тоже перекрашиваем под тему.
      svgSource: assetData.svgSource
          .replaceAll(assetData.defaultFill, inactiveFill),
      svgIdToColor: idToColor,
      fallbackFill: inactiveFill,
    );
  }

  String colorize({
    required String svgSource,
    required Map<String, String> svgIdToColor,
    required String fallbackFill,
  }) {
    final document = XmlDocument.parse(svgSource);
    final elements = document.descendants.whereType<XmlElement>();

    for (final element in elements) {
      final id = element.getAttribute('id');
      if (id == null) {
        continue;
      }
      final color =
          svgIdToColor[id] ?? _resolveFallbackColor(element, fallbackFill);
      if (color == null) continue;
      element.setAttribute('fill', color);
      element.setAttribute(
          'style', _mergeStyle(element.getAttribute('style'), color));
    }

    return document.toXmlString();
  }

  String? _resolveFallbackColor(XmlElement element, String fallbackFill) {
    if (element.getAttribute('fill') != null) {
      return null;
    }

    final style = element.getAttribute('style');
    if (style != null && style.contains('fill:')) {
      return null;
    }

    final classes = (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty);
    if (classes.isEmpty) {
      return null;
    }

    return fallbackFill;
  }

  String _mergeStyle(String? currentStyle, String color) {
    final parts = <String>[];
    final tokens = (currentStyle ?? '')
        .split(';')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && !token.startsWith('fill:'));
    parts.addAll(tokens);
    parts.add('fill:$color');
    return '${parts.join(';')};';
  }
}
