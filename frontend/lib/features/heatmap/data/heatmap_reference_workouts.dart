import '../../../core/storage/local_cache.dart';

List? _lastRaw;
List<Map<String, dynamic>> _lastResult = const [];

/// Вся известная история тренировок из локального кэша — нужна калькулятору
/// нагрузки, чтобы оценить лучший e1RM пользователя в каждом упражнении.
List<Map<String, dynamic>> cachedHeatmapReferenceWorkouts() {
  final raw = LocalCache.get<List>(CacheKeys.workoutsCache);
  if (raw == null) return const [];
  if (identical(raw, _lastRaw)) return _lastResult;
  _lastRaw = raw;
  _lastResult = raw
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList(growable: false);
  return _lastResult;
}
