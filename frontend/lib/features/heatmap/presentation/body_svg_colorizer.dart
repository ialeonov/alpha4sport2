import 'package:xml/xml.dart';

class BodySvgColorizer {
  const BodySvgColorizer();

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
