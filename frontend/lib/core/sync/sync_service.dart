import 'dart:async';

import '../network/backend_api.dart';
import '../network/connectivity_service.dart';
import '../storage/local_cache.dart';
import '../storage/offline_queue.dart';

class SyncService {
  SyncService._();
  static final instance = SyncService._();

  StreamSubscription<bool>? _subscription;

  void init() {
    _subscription = ConnectivityService.instance.onlineStream.listen((online) {
      if (online) drainQueue();
    });
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> drainQueue() async {
    final mutations = OfflineQueue.getAll();
    if (mutations.isEmpty) return;

    for (final mutation in List.of(mutations)) {
      try {
        await _execute(mutation);
        await OfflineQueue.remove(mutation['id'] as String);
      } catch (_) {
        break;
      }
    }

    // обновляем кэш тренировок в фоне, не блокируя завершение drain
    if (OfflineQueue.isEmpty) {
      BackendApi.getWorkouts()
          .then((fresh) => LocalCache.put(CacheKeys.workoutsCache, fresh))
          .catchError((_) {});
    }
  }

  Future<void> _execute(Map<String, dynamic> mutation) async {
    final type = mutation['type'] as String;
    final payload = (mutation['payload'] as Map).cast<String, dynamic>();

    switch (type) {
      case 'create_workout':
        await BackendApi.createWorkoutDetailed(
          name: payload['name'] as String,
          exercises:
              (payload['exercises'] as List).cast<Map<String, dynamic>>(),
          startedAt: DateTime.parse(payload['started_at'] as String),
          finishedAt: payload['finished_at'] != null
              ? DateTime.parse(payload['finished_at'] as String)
              : null,
          notes: payload['notes'] as String?,
        );
      case 'update_workout':
        await BackendApi.updateWorkout(
          workoutId: payload['workout_id'] as int,
          name: payload['name'] as String,
          exercises:
              (payload['exercises'] as List).cast<Map<String, dynamic>>(),
          startedAt: DateTime.parse(payload['started_at'] as String),
          finishedAt: payload['finished_at'] != null
              ? DateTime.parse(payload['finished_at'] as String)
              : null,
          notes: payload['notes'] as String?,
        );
    }
  }
}
