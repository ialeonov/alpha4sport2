import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';

/// Шкала тепловой карты в эффективных подходах.
///
/// Пороги разные для одной тренировки и для недели, но единица одна, поэтому
/// цвет везде означает одно и то же: сколько работы получила мышца.
class MuscleHeatmapScale {
  const MuscleHeatmapScale._({
    required this.thresholds,
    required this.levelLabels,
  });

  /// Одна тренировка.
  static const session = MuscleHeatmapScale._(
    thresholds: [0.5, 2, 4, 7],
    levelLabels: ['немного', 'умеренно', 'много', 'очень много'],
  );

  /// Сумма за неделю (ориентир для роста — 10–20 подходов на мышцу).
  static const week = MuscleHeatmapScale._(
    thresholds: [1, 5, 10, 20],
    levelLabels: ['мало', 'поддержка', 'рост', 'с запасом'],
  );

  /// Нижние границы уровней 1..4.
  final List<double> thresholds;
  final List<String> levelLabels;

  /// 0 — мышца не работала, 1..4 — уровни нагрузки.
  int level(double load) {
    var result = 0;
    for (var i = 0; i < thresholds.length; i++) {
      if (load >= thresholds[i]) result = i + 1;
    }
    return result;
  }

  String rangeLabel(int level) {
    final from = _fmt(thresholds[level - 1]);
    if (level == thresholds.length) return '$from+';
    return '$from–${_fmt(thresholds[level])}';
  }

  static String _fmt(double v) => formatDecimal(v);
}

class MuscleHeatmapColorResolver {
  const MuscleHeatmapColorResolver({this.dark = false});

  factory MuscleHeatmapColorResolver.of(BuildContext context) =>
      MuscleHeatmapColorResolver(
        dark: Theme.of(context).brightness == Brightness.dark,
      );

  final bool dark;

  static const Color inactiveLight = Color(0xFFE3E5E8);
  static const Color inactiveDark = Color(0xFF3A3F48);
  static const List<Color> levels = [
    Color(0xFFF6D365),
    Color(0xFFF39C33),
    Color(0xFFE53935),
    Color(0xFF9C1B4B),
  ];

  Color get inactive => dark ? inactiveDark : inactiveLight;

  Color forLevel(int level) => level <= 0 ? inactive : levels[level - 1];

  Color resolve(double load, MuscleHeatmapScale scale) =>
      forLevel(scale.level(load));

  String resolveHex(double load, MuscleHeatmapScale scale) =>
      toHex(resolve(load, scale));

  static String toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}
