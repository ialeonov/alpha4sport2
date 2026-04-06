import 'package:hive_flutter/hive_flutter.dart';

class LocalCache {
  static const _boxName = 'alpha4sport_cache';
  static const _sessionKeys = <String>{
    CacheKeys.token,
    CacheKeys.workoutsCache,
    CacheKeys.templatesCache,
    CacheKeys.exerciseCatalogCache,
    CacheKeys.bodyEntriesCache,
    CacheKeys.bodyweightTrendCache,
    CacheKeys.weeklyVolumeCache,
    // activeWorkoutDraft and workout_draft_* are user data, not session data —
    // they must survive session expiry so the user can resume after re-login.
  };
  static const _sessionPrefixes = <String>[];

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  static Box get _box => Hive.box(_boxName);

  static T? get<T>(String key) => _box.get(key) as T?;

  static Future<void> put(String key, dynamic value) => _box.put(key, value);

  static Future<void> remove(String key) => _box.delete(key);

  static Future<void> clear() => _box.clear();

  static Future<void> clearSessionData() async {
    for (final key in _sessionKeys) {
      await _box.delete(key);
    }

    final dynamicKeys = _box.keys.map((key) => key.toString()).toList();
    for (final key in dynamicKeys) {
      if (_sessionPrefixes.any((prefix) => key.startsWith(prefix))) {
        await _box.delete(key);
      }
    }
  }
}

class CacheKeys {
  static const token = 'auth_token';
  static const baseUrl = 'base_url';
  static const workoutsCache = 'workouts_cache';
  static const templatesCache = 'templates_cache';
  static const exerciseCatalogCache = 'exercise_catalog_cache';
  static const bodyEntriesCache = 'body_entries_cache';
  static const bodyweightTrendCache = 'bodyweight_trend_cache';
  static const weeklyVolumeCache = 'weekly_volume_cache';
  static const activeWorkoutDraft = 'active_workout_draft';
  static const customPrograms = 'custom_programs';
}
