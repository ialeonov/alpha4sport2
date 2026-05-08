import 'dart:convert';

import 'package:flutter/material.dart';

enum WellnessZone { green, yellow, red }

class WellnessEntry {
  const WellnessEntry({
    required this.date,
    required this.sleep,
    required this.energy,
    required this.stress,
    required this.mood,
    this.comment,
  });

  final DateTime date;
  final int sleep;
  final int energy;
  final int stress;
  final int mood;
  final String? comment;

  WellnessEntry copyWith({
    DateTime? date,
    int? sleep,
    int? energy,
    int? stress,
    int? mood,
    String? comment,
    bool clearComment = false,
  }) =>
      WellnessEntry(
        date: date ?? this.date,
        sleep: sleep ?? this.sleep,
        energy: energy ?? this.energy,
        stress: stress ?? this.stress,
        mood: mood ?? this.mood,
        comment: clearComment ? null : (comment ?? this.comment),
      );

  Map<String, dynamic> toJson() => {
        'date': DateUtils.dateOnly(date).toIso8601String(),
        'sleep': sleep,
        'energy': energy,
        'stress': stress,
        'mood': mood,
        'comment': comment,
      };

  factory WellnessEntry.fromJson(Map<String, dynamic> json) => WellnessEntry(
        date: DateTime.parse(json['date'] as String),
        sleep: json['sleep'] as int,
        energy: json['energy'] as int,
        stress: json['stress'] as int,
        mood: json['mood'] as int,
        comment: json['comment'] as String?,
      );

  String toJsonString() => jsonEncode(toJson());

  factory WellnessEntry.fromJsonString(String s) =>
      WellnessEntry.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ── Zone calculation ────────────────────────────────────────────────────────

  /// Average score: sleep + energy + (6 − stress) + mood / 4
  /// Stress is inverted so that high stress → low score.
  double get zoneScore {
    final invertedStress = 6 - stress;
    return (sleep + energy + invertedStress + mood) / 4.0;
  }

  WellnessZone get zone {
    final s = zoneScore;
    if (s >= 4.0) return WellnessZone.green;
    if (s >= 2.5) return WellnessZone.yellow;
    return WellnessZone.red;
  }

  // ── Legacy summary (still used by AI coach text) ─────────────────────────

  String get summaryEmoji {
    if (stress >= 4) return '😰';
    if (sleep <= 2 || energy <= 2) return '😴';
    if (mood <= 2) return '😔';
    if (sleep >= 4 && energy >= 4 && mood >= 4) return '💪';
    return '😐';
  }

  String get summaryText {
    if (stress >= 4) return 'Напряжённый день';
    if (sleep <= 2 || energy <= 2) return 'Устал';
    if (mood <= 2) return 'Тяжёлый день';
    if (sleep >= 4 && energy >= 4 && mood >= 4) return 'Отличный день';
    return 'Норм';
  }
}
