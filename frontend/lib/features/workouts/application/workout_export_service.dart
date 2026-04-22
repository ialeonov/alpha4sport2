import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';

class WorkoutExportService {
  const WorkoutExportService();

  Future<List<Map<String, dynamic>>> loadExerciseCatalog() async {
    try {
      return await BackendApi.getExercises();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadTemplates() async {
    try {
      return await BackendApi.getTemplates();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.templatesCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
      return const [];
    }
  }

  Map<String, dynamic> buildExport({
    required List<Map<String, dynamic>> workouts,
    required DateTime rangeFrom,
    required DateTime rangeTo,
    required List<Map<String, dynamic>> exerciseCatalog,
    DateTime? exportedAt,
  }) {
    final catalogById = <int, Map<String, dynamic>>{};
    final catalogByName = <String, Map<String, dynamic>>{};

    for (final exercise in exerciseCatalog) {
      final id = exercise['id'];
      if (id is int) {
        catalogById[id] = exercise;
      }

      final name = (exercise['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        catalogByName[_normalizeExerciseLookupName(name)] = exercise;
      }
    }

    final normalizedWorkouts = [...workouts]..sort((a, b) {
        final aStartedAt = _parseDateTime(a['started_at']) ?? DateTime(1970);
        final bStartedAt = _parseDateTime(b['started_at']) ?? DateTime(1970);
        return aStartedAt.compareTo(bStartedAt);
      });

    return {
      'exported_at': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'range': {
        'from': _formatDate(rangeFrom),
        'to': _formatDate(rangeTo),
      },
      'workouts': normalizedWorkouts
          .map(
            (workout) => _buildWorkoutExport(
              workout: workout,
              catalogById: catalogById,
              catalogByName: catalogByName,
            ),
          )
          .toList(),
    };
  }

  Future<bool> saveExportJson({
    required Map<String, dynamic> exportData,
    required String suggestedFileName,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedFileName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        ),
      ],
    );
    if (location == null) {
      return false;
    }

    final json = const JsonEncoder.withIndent('  ').convert(exportData);
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      name: suggestedFileName,
    );
    await file.saveTo(location.path);
    return true;
  }

  Future<List<ImportedWorkoutDraft>> pickImportWorkouts({
    List<Map<String, dynamic>> exerciseCatalog = const [],
  }) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json', 'text/json'],
        ),
      ],
    );
    if (file == null) {
      return const [];
    }

    final jsonString = await file.readAsString();
    return parseImportWorkouts(
      jsonString,
      exerciseCatalog: exerciseCatalog,
      sourceName: file.name,
    );
  }

  List<ImportedWorkoutDraft> parseImportWorkouts(
    String jsonString, {
    List<Map<String, dynamic>> exerciseCatalog = const [],
    String? sourceName,
  }) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map) {
      throw const FormatException(
        'JSON должен содержать объект экспорта с полем workouts.',
      );
    }

    final catalogByName = <String, Map<String, dynamic>>{};
    for (final exercise in exerciseCatalog) {
      final name = (exercise['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) {
        catalogByName[_normalizeExerciseLookupName(name)] = exercise;
      }
    }

    final rawWorkouts = (decoded['workouts'] as List?)?.cast<dynamic>();
    if (rawWorkouts == null) {
      throw const FormatException('В JSON не найден список workouts.');
    }

    final imported = <ImportedWorkoutDraft>[];
    for (var index = 0; index < rawWorkouts.length; index++) {
      final rawWorkout = rawWorkouts[index];
      if (rawWorkout is! Map) {
        continue;
      }
      final parsed = _parseImportedWorkout(
        rawWorkout.cast<String, dynamic>(),
        index: index,
        catalogByName: catalogByName,
        sourceName: sourceName,
      );
      if (parsed != null) {
        imported.add(parsed);
      }
    }

    return imported;
  }

  DateTime? workoutDate(Map<String, dynamic> workout) {
    final startedAt = _parseDateTime(workout['started_at']);
    if (startedAt == null) {
      return null;
    }
    return DateTime(startedAt.year, startedAt.month, startedAt.day);
  }

  List<Map<String, dynamic>> filterWorkoutsByDateRange({
    required List<Map<String, dynamic>> workouts,
    required DateTime from,
    required DateTime to,
  }) {
    final normalizedFrom = DateTime(from.year, from.month, from.day);
    final normalizedTo = DateTime(to.year, to.month, to.day);

    return workouts.where((workout) {
      final day = workoutDate(workout);
      if (day == null) {
        return false;
      }
      return !day.isBefore(normalizedFrom) && !day.isAfter(normalizedTo);
    }).toList();
  }

  ImportedWorkoutDraft? _parseImportedWorkout(
    Map<String, dynamic> workout, {
    required int index,
    required Map<String, Map<String, dynamic>> catalogByName,
    String? sourceName,
  }) {
    final date = _parseImportedWorkoutDate(workout);
    final rawExercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final exercises = <Map<String, dynamic>>[];

    for (var exerciseIndex = 0;
        exerciseIndex < rawExercises.length;
        exerciseIndex++) {
      final rawExercise = rawExercises[exerciseIndex];
      if (rawExercise is! Map) {
        continue;
      }
      final parsedExercise = _parseImportedExercise(
        rawExercise.cast<String, dynamic>(),
        position: exerciseIndex + 1,
        catalogByName: catalogByName,
      );
      if (parsedExercise != null) {
        exercises.add(parsedExercise);
      }
    }

    if (exercises.isEmpty) {
      return null;
    }

    final dateLabel = date == null ? '#${index + 1}' : formatExportDate(date);
    final explicitName = (workout['name'] ?? '').toString().trim();
    final fallbackSource = (sourceName ?? '').trim();

    return ImportedWorkoutDraft(
      name: explicitName.isNotEmpty ? explicitName : 'Импорт $dateLabel',
      date: date ?? DateTime.now(),
      exercises: exercises,
      sourceLabel: fallbackSource.isNotEmpty
          ? '$fallbackSource · $dateLabel'
          : 'Тренировка $dateLabel',
    );
  }

  DateTime? _parseImportedWorkoutDate(Map<String, dynamic> workout) {
    final rawDate = workout['date'];
    if (rawDate != null) {
      final parsedDate = DateTime.tryParse(rawDate.toString());
      if (parsedDate != null) {
        return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }
    }

    final startedAt = _parseDateTime(workout['started_at']);
    if (startedAt != null) {
      return DateTime(startedAt.year, startedAt.month, startedAt.day);
    }

    return null;
  }

  Map<String, dynamic>? _parseImportedExercise(
    Map<String, dynamic> exercise, {
    required int position,
    required Map<String, Map<String, dynamic>> catalogByName,
  }) {
    final name = ((exercise['name'] ?? exercise['exercise_name']) ?? '')
        .toString()
        .trim();
    if (name.isEmpty) {
      return null;
    }

    final rawSets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
    final sets = <Map<String, dynamic>>[];
    for (var setIndex = 0; setIndex < rawSets.length; setIndex++) {
      final rawSet = rawSets[setIndex];
      if (rawSet is! Map) {
        continue;
      }
      final set = rawSet.cast<String, dynamic>();
      final importedNote = (set['notes'] ?? '').toString().trim();
      sets.add({
        'position':
            _normalizeInt(set['position'] ?? set['set_index']) ?? setIndex + 1,
        'reps': _normalizeInt(set['reps']) ?? 0,
        'weight': _normalizeNumber(set['weight']),
        'set_type': (set['set_type'] ?? 'work').toString(),
        'rpe': _normalizeNumber(set['rpe']),
        'notes': importedNote.isEmpty ? null : importedNote,
      });
    }

    if (sets.isEmpty) {
      sets.add({
        'position': 1,
        'reps': 0,
        'weight': null,
        'set_type': 'work',
        'rpe': null,
        'notes': null,
      });
    }

    final catalogEntry = catalogByName[_normalizeExerciseLookupName(name)];
    final exerciseNote =
        (exercise['notes'] ?? exercise['note'] ?? '').toString().trim();
    return {
      'catalog_exercise_id': catalogEntry?['id'] as int?,
      'exercise_name': name,
      'position': position,
      'notes': exerciseNote.isEmpty ? null : exerciseNote,
      'sets': sets,
    };
  }

  Map<String, dynamic> _buildWorkoutExport({
    required Map<String, dynamic> workout,
    required Map<int, Map<String, dynamic>> catalogById,
    required Map<String, Map<String, dynamic>> catalogByName,
  }) {
    final startedAt = _parseDateTime(workout['started_at']);
    final finishedAt = _parseDateTime(workout['finished_at']);
    final exercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];

    return {
      'id': workout['id']?.toString(),
      'date': startedAt == null ? null : _formatDate(startedAt),
      'duration_minutes': _calculateDurationMinutes(startedAt, finishedAt),
      'notes': workout['notes']?.toString(),
      'exercises': exercises
          .whereType<Map>()
          .map(
            (exercise) => _buildExerciseExport(
              exercise: exercise.cast<String, dynamic>(),
              catalogEntry: _resolveCatalogEntry(
                exercise: exercise.cast<String, dynamic>(),
                catalogById: catalogById,
                catalogByName: catalogByName,
              ),
            ),
          )
          .toList(),
    };
  }

  Map<String, dynamic> _buildExerciseExport({
    required Map<String, dynamic> exercise,
    required Map<String, dynamic>? catalogEntry,
  }) {
    final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
    final exportedSets = <Map<String, dynamic>>[];
    Map<String, dynamic>? bestSet;

    for (var index = 0; index < sets.length; index++) {
      final rawSet = sets[index];
      if (rawSet is! Map) {
        continue;
      }

      final set = rawSet.cast<String, dynamic>();
      final reps = _normalizeNumber(set['reps']);
      final weight = _normalizeNumber(set['weight']);
      final setType = (set['set_type'] ?? 'work').toString();
      final rpe = _normalizeNumber(set['rpe']);
      final setIndex = _normalizeInt(set['position']) ?? index + 1;
      final setNotes = (set['notes'] ?? '').toString().trim();
      final exportedSet = {
        'set_index': setIndex,
        'reps': reps,
        'weight': weight,
        'set_type': setType,
        'rpe': rpe,
        if (setNotes.isNotEmpty) 'notes': setNotes,
      };

      exportedSets.add(exportedSet);
      bestSet = _pickBestSet(current: bestSet, candidate: exportedSet);
    }

    final primaryMuscle =
        (catalogEntry?['primary_muscle'] ?? '').toString().trim();
    final secondaryMuscles =
        (catalogEntry?['secondary_muscles'] as List?)?.cast<dynamic>() ??
            const [];

    final exerciseNote = (exercise['notes'] ?? '').toString().trim();
    return {
      'name': (exercise['exercise_name'] ?? '').toString(),
      if (exerciseNote.isNotEmpty) 'notes': exerciseNote,
      'primary_muscle': primaryMuscle.isEmpty ? null : primaryMuscle,
      'secondary_muscles': secondaryMuscles
          .map((muscle) => muscle.toString().trim())
          .where((muscle) => muscle.isNotEmpty)
          .toList(),
      'sets': exportedSets,
      'best_set': bestSet == null
          ? null
          : {
              'reps': bestSet['reps'],
              'weight': bestSet['weight'],
              if (bestSet['set_type'] != null) 'set_type': bestSet['set_type'],
              if (bestSet['rpe'] != null) 'rpe': bestSet['rpe'],
            },
    };
  }

  Map<String, dynamic>? _resolveCatalogEntry({
    required Map<String, dynamic> exercise,
    required Map<int, Map<String, dynamic>> catalogById,
    required Map<String, Map<String, dynamic>> catalogByName,
  }) {
    final catalogExerciseId = exercise['catalog_exercise_id'];
    if (catalogExerciseId is int) {
      final byId = catalogById[catalogExerciseId];
      if (byId != null) {
        return byId;
      }
    }

    final name = (exercise['exercise_name'] ?? '').toString().trim();
    if (name.isEmpty) {
      return null;
    }
    return catalogByName[_normalizeExerciseLookupName(name)];
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  int? _calculateDurationMinutes(DateTime? startedAt, DateTime? finishedAt) {
    if (startedAt == null || finishedAt == null) {
      return null;
    }

    final duration = finishedAt.difference(startedAt);
    if (duration.isNegative) {
      return null;
    }
    return duration.inMinutes;
  }

  num? _normalizeNumber(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value % 1 == 0 ? value.toInt() : value.toDouble();
    }

    final parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    if (parsed == null) {
      return null;
    }
    return parsed % 1 == 0 ? parsed.toInt() : parsed;
  }

  int? _normalizeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  double _calculateSetVolume({
    required num? reps,
    required num? weight,
  }) {
    final repsValue = (reps ?? 0).toDouble();
    final weightValue = (weight ?? 0).toDouble();
    if (repsValue <= 0) {
      return 0;
    }
    if (weightValue <= 0) {
      return repsValue;
    }
    return repsValue * weightValue;
  }

  Map<String, dynamic>? _pickBestSet({
    required Map<String, dynamic>? current,
    required Map<String, dynamic> candidate,
  }) {
    if (current == null) {
      return candidate;
    }

    final currentWeight = _bestSetWeight(current);
    final candidateWeight = _bestSetWeight(candidate);
    if (candidateWeight > currentWeight) {
      return candidate;
    }
    if (candidateWeight < currentWeight) {
      return current;
    }

    final currentReps = _bestSetReps(current);
    final candidateReps = _bestSetReps(candidate);
    if (candidateReps > currentReps) {
      return candidate;
    }
    return current;
  }

  double _bestSetWeight(Map<String, dynamic> set) {
    final weight = set['weight'];
    if (weight is num && weight > 0) {
      return weight.toDouble();
    }
    return 0;
  }

  int _bestSetReps(Map<String, dynamic> set) {
    final reps = set['reps'];
    if (reps is int) {
      return reps;
    }
    if (reps is num) {
      return reps.toInt();
    }
    return 0;
  }
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}

String formatExportDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String formatExportFileDate(DateTime value) {
  return formatExportDate(value).replaceAll('-', '_');
}

String _formatDate(DateTime value) => formatExportDate(value);

class ImportedWorkoutDraft {
  const ImportedWorkoutDraft({
    required this.name,
    required this.date,
    required this.exercises,
    required this.sourceLabel,
  });

  final String name;
  final DateTime date;
  final List<Map<String, dynamic>> exercises;
  final String sourceLabel;
}
