import 'package:flutter/material.dart';

class MuscleHeatmapColorResolver {
  const MuscleHeatmapColorResolver();

  static const Color inactive = Color(0xFFE6E6E6);
  static const Color low = Color(0xFFF4D35E);
  static const Color medium = Color(0xFFF28C28);
  static const Color high = Color(0xFFE53935);

  Color resolve(double loadScore) {
    if (loadScore < 1.5) {
      return inactive;
    }
    if (loadScore < 3.0) {
      return low;
    }
    if (loadScore < 5.0) {
      return medium;
    }
    return high;
  }

  String resolveHex(double loadScore) {
    final color = resolve(loadScore);
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}
