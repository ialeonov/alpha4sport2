import 'package:alpha4sport_app/features/heatmap/presentation/body_svg_colorizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  group('BodySvgColorizer', () {
    test('preserves fallback fill for unmapped class-based zones', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg">
  <style>.st0{fill:#E6E6E6;}</style>
  <path id="head" class="st0" d="M0 0h10v10z" />
  <path id="chest" class="st0" d="M10 0h10v10z" />
</svg>
''';

      final result = const BodySvgColorizer().colorize(
        svgSource: svg,
        svgIdToColor: const {'chest': '#FF3B30'},
        fallbackFill: '#E6E6E6',
      );
      final document = XmlDocument.parse(result);
      final head = document
          .findAllElements('path')
          .firstWhere((node) => node.getAttribute('id') == 'head');
      final chest = document
          .findAllElements('path')
          .firstWhere((node) => node.getAttribute('id') == 'chest');

      expect(head.getAttribute('fill'), '#E6E6E6');
      expect(chest.getAttribute('fill'), '#FF3B30');
    });

    test('does not override explicit inline fills for unmapped zones', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg">
  <path id="accent" fill="#123456" d="M0 0h10v10z" />
</svg>
''';

      final result = const BodySvgColorizer().colorize(
        svgSource: svg,
        svgIdToColor: const {},
        fallbackFill: '#E6E6E6',
      );
      final document = XmlDocument.parse(result);
      final accent = document.findAllElements('path').single;

      expect(accent.getAttribute('fill'), '#123456');
    });
  });
}
