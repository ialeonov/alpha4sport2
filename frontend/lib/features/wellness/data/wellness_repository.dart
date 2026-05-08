import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../domain/wellness_entry.dart';

class WellnessRepository {
  static const _prefix = 'wellness_';

  static String _keyFor(DateTime date) {
    final d = DateUtils.dateOnly(date);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$_prefix$y-$m-$day';
  }

  static WellnessEntry? loadForDate(DateTime date) {
    final raw = LocalCache.get<String>(_keyFor(date));
    if (raw == null) return null;
    try {
      return WellnessEntry.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(WellnessEntry entry) async {
    final saved = await BackendApi.upsertWellnessEntry(
      date: entry.date,
      sleep: entry.sleep,
      energy: entry.energy,
      stress: entry.stress,
      mood: entry.mood,
      comment: entry.comment,
    );
    await _cacheServerEntry(saved);
  }

  static Future<WellnessEntry?> fetchForDate(DateTime date) async {
    final entries = await syncRange(start: date, end: date);
    return entries.isEmpty ? null : entries.first;
  }

  static Future<List<WellnessEntry>> syncRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await BackendApi.getWellnessEntries(start: start, end: end);
    final entries = <WellnessEntry>[];
    final serverDates = <DateTime>{};
    for (final row in rows) {
      final entry = await _cacheServerEntry(row);
      entries.add(entry);
      serverDates.add(DateUtils.dateOnly(entry.date));
    }

    var cursor = DateUtils.dateOnly(start);
    final last = DateUtils.dateOnly(end);
    while (!cursor.isAfter(last)) {
      if (!serverDates.contains(cursor)) {
        final localEntry = loadForDate(cursor);
        if (localEntry != null) {
          final saved = await BackendApi.upsertWellnessEntry(
            date: localEntry.date,
            sleep: localEntry.sleep,
            energy: localEntry.energy,
            stress: localEntry.stress,
            mood: localEntry.mood,
            comment: localEntry.comment,
          );
          entries.add(await _cacheServerEntry(saved));
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return entries;
  }

  /// Returns the subset of [dates] for which a wellness entry exists.
  static Set<DateTime> datesWithEntries(Iterable<DateTime> dates) {
    final result = <DateTime>{};
    for (final date in dates) {
      final normalized = DateUtils.dateOnly(date);
      if (LocalCache.get<String>(_keyFor(normalized)) != null) {
        result.add(normalized);
      }
    }
    return result;
  }

  static Future<WellnessEntry> _cacheServerEntry(
    Map<String, dynamic> json,
  ) async {
    final entry = WellnessEntry.fromJson({
      'date': json['entry_date'] ?? json['date'],
      'sleep': json['sleep'],
      'energy': json['energy'],
      'stress': json['stress'],
      'mood': json['mood'],
      'comment': json['comment'],
    });
    await LocalCache.put(_keyFor(entry.date), entry.toJsonString());
    return entry;
  }
}
