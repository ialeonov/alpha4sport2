import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/navigation/page_close_guard.dart';
import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../progression/application/progression_controller.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/muscle_heatmap_card.dart';
import '../application/workout_share_service.dart';
import '../domain/workout_metrics.dart';

class WorkoutFormScreen extends StatefulWidget {
  const WorkoutFormScreen({
    super.key,
    this.initialWorkout,
    this.initialDate,
    this.initialName,
    this.initialExercises,
  });

  final Map<String, dynamic>? initialWorkout;
  final DateTime? initialDate;
  final String? initialName;
  final List<Map<String, dynamic>>? initialExercises;

  @override
  State<WorkoutFormScreen> createState() => _WorkoutFormScreenState();
}

class _WorkoutFormScreenState extends State<WorkoutFormScreen> {
  static const Duration _autoSaveDelay = Duration(seconds: 2);
  static const String _newWorkoutDraftKey = 'workout_draft_new';

  late final TextEditingController _nameController;
  late final PageCloseGuard _pageCloseGuard;
  late final ScrollController _scrollController;
  late DateTime _selectedDate;
  late DateTime _startedAt;
  DateTime? _finishedAt;

  final List<_ExerciseDraft> _exercises = [];
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _workoutHistory = const [];
  final Map<String, _ExerciseLastSetState> _lastSetByExerciseName = {};

  String? _catalogError;
  int? _workoutId;
  bool _catalogLoading = false;
  bool _savingToServer = false;
  bool _restoredDraft = false;
  bool _restoredDraftSyncedWithServer = false;
  bool _didChangeServerData = false;
  bool _hasUnsavedChanges = false;
  _SaveStatus _saveStatus = _SaveStatus.saved;
  Timer? _draftSaveTimer;
  String? _lastSavedFingerprint;

  bool get _isEditing => _workoutId != null;
  bool get _isFinished => _finishedAt != null;
  bool get _shouldPersistDrafts => !_isFinished;

  String get _currentDraftKey =>
      _workoutId == null ? _newWorkoutDraftKey : 'workout_draft_$_workoutId';

  List<String> get _draftKeys {
    final keys = <String>{
      if (_workoutId == null) _newWorkoutDraftKey else _currentDraftKey,
    };
    return keys.toList();
  }

  @override
  void initState() {
    super.initState();
    _pageCloseGuard = PageCloseGuard(() => _hasUnsavedChanges);
    _pageCloseGuard.attach();
    _scrollController = ScrollController();

    final sourceWorkout = _restoreDraftSnapshot() ?? widget.initialWorkout;
    final now = DateTime.now();
    final initialDate = widget.initialDate;
    final hasExplicitInitialTime = initialDate != null &&
        (initialDate.hour != 0 ||
            initialDate.minute != 0 ||
            initialDate.second != 0 ||
            initialDate.millisecond != 0 ||
            initialDate.microsecond != 0);

    _workoutId = sourceWorkout?['id'] as int?;
    _startedAt = _parseDate(sourceWorkout?['started_at']) ??
        (initialDate == null
            ? now
            : hasExplicitInitialTime
                ? initialDate
                : DateTime(
                    initialDate.year,
                    initialDate.month,
                    initialDate.day,
                    now.hour,
                    now.minute,
                  ));
    _finishedAt = _parseDate(sourceWorkout?['finished_at']);
    _selectedDate = DateUtils.dateOnly(_startedAt);
    _nameController = TextEditingController(
      text: (sourceWorkout?['name'] ??
              widget.initialName ??
              'Тренировка ${formatShortDate(DateTime.now())}')
          .toString(),
    );

    final exercises = sourceWorkout != null
        ? (sourceWorkout['exercises'] as List?)?.cast<dynamic>() ?? const []
        : (widget.initialExercises ?? const []).cast<dynamic>();
    if (exercises.isEmpty) {
      _exercises.add(_ExerciseDraft.empty());
    } else {
      for (final exercise in exercises) {
        _exercises.add(
          _ExerciseDraft.fromMap((exercise as Map).cast<String, dynamic>()),
        );
      }
      if (_restoredDraft || widget.initialWorkout != null) {
        for (final exercise in _exercises) {
          exercise.isCollapsed = true;
        }
      }
    }

    _lastSavedFingerprint = _createFingerprint(_buildDraftSnapshot());
    _hasUnsavedChanges = _restoredDraft && !_restoredDraftSyncedWithServer;
    _saveStatus = _hasUnsavedChanges ? _SaveStatus.unsaved : _SaveStatus.saved;

    _loadCatalog();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _pageCloseGuard.dispose();
    _scrollController.dispose();
    _nameController.dispose();
    for (final exercise in _exercises) {
      exercise.dispose();
    }
    super.dispose();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  Map<String, dynamic>? _restoreDraftSnapshot() {
    final workoutId = widget.initialWorkout?['id'] as int?;
    final draftKey =
        workoutId == null ? _newWorkoutDraftKey : 'workout_draft_$workoutId';
    if (widget.initialWorkout?['finished_at'] != null) {
      unawaited(LocalCache.remove(draftKey));
      return null;
    }
    final cached = LocalCache.get<Map>(draftKey);
    if (cached == null) {
      return null;
    }
    final restored = cached.cast<String, dynamic>();
    final nestedDraft = restored['data'];
    if (nestedDraft is Map) {
      if (nestedDraft['finished_at'] != null) {
        unawaited(LocalCache.remove(draftKey));
        return null;
      }
      if (workoutId == null &&
          restored['synced_with_server'] == true &&
          nestedDraft['id'] != null) {
        unawaited(LocalCache.remove(draftKey));
        return null;
      }
      _restoredDraft = true;
      _restoredDraftSyncedWithServer = restored['synced_with_server'] == true;
      return nestedDraft.cast<String, dynamic>();
    }
    _restoredDraft = true;
    return restored;
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });

    try {
      final catalog = await BackendApi.getExercises();
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _catalogLoading = false;
      });
      _syncExercisesWithCatalog(markChanged: false);
      _loadLastSets();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null && mounted) {
        setState(() {
          _catalog =
              cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
          _catalogLoading = false;
        });
        _syncExercisesWithCatalog(markChanged: false);
        _loadLastSets();
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _catalogLoading = false;
        _catalogError = 'Не удалось загрузить каталог упражнений.';
      });
    }
  }

  void _syncExercisesWithCatalog({required bool markChanged}) {
    if (_catalog.isEmpty) {
      return;
    }

    var changed = false;
    for (final exercise in _exercises) {
      if (exercise.catalogExerciseId != null) {
        final matchedById = _catalog.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['id'] == exercise.catalogExerciseId,
              orElse: () => null,
            );
        if (matchedById != null) {
          final catalogName = (matchedById['name'] ?? '').toString();
          if (catalogName.isNotEmpty &&
              exercise.nameController.text != catalogName) {
            exercise.nameController.text = catalogName;
            changed = true;
          }
        }
      }
    }

    if (!changed) {
      return;
    }
    if (mounted) {
      setState(() {});
    }
    if (markChanged) {
      _handleDraftChanged();
    }
  }

  Future<void> _ensureWorkoutHistoryLoaded() async {
    if (_workoutHistory.isEmpty) {
      try {
        _workoutHistory = await BackendApi.getWorkouts();
      } catch (_) {
        final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
        if (cached != null) {
          _workoutHistory = cached
              .cast<Map>()
              .map((entry) => entry.cast<String, dynamic>())
              .toList();
        }
      }
    }
  }

  Future<void> _loadLastSets() async {
    await _ensureWorkoutHistoryLoaded();
    final names = _exercises
        .map((item) => item.nameController.text.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    for (final name in names) {
      await _fetchExerciseLastSet(name);
    }
  }

  Future<void> _fetchExerciseLastSet(String exerciseName) async {
    final normalizedName = exerciseName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    setState(() {
      _lastSetByExerciseName[normalizedName] =
          const _ExerciseLastSetState.loading();
    });

    await _ensureWorkoutHistoryLoaded();

    final lastSet = _extractLastWorkingSet(_workoutHistory, normalizedName);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastSetByExerciseName[normalizedName] =
          _ExerciseLastSetState.loaded(lastSet);
    });
  }

  _WorkingSetSummary? _extractLastWorkingSet(
    List<Map<String, dynamic>> history,
    String exerciseName,
  ) {
    for (final workout in history) {
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawExercise in exercises) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        if ((exercise['exercise_name'] ?? '').toString() != exerciseName) {
          continue;
        }
        final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
        if (sets.isEmpty) {
          continue;
        }
        final rawSet = (sets.last as Map).cast<String, dynamic>();
        final reps = (rawSet['reps'] as num?)?.toInt();
        final weight = (rawSet['weight'] as num?)?.toDouble();
        if (reps == null || weight == null) {
          continue;
        }
        return _WorkingSetSummary(reps: reps, weight: weight);
      }
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedDate = DateUtils.dateOnly(picked);
      _startedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startedAt.hour,
        _startedAt.minute,
      );
      if (_finishedAt != null) {
        _finishedAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _finishedAt!.hour,
          _finishedAt!.minute,
        );
      }
    });
    _handleDraftChanged();
  }

  Future<void> _pickExercise(int exerciseIndex) async {
    if (_catalogLoading) {
      return;
    }
    if (_catalog.isEmpty) {
      _showError(_catalogError ?? 'Каталог упражнений пока недоступен.');
      return;
    }

    final draft = _exercises[exerciseIndex];
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ExerciseCatalogSheet(
        catalog: _catalog,
        initialExerciseId: draft.catalogExerciseId,
      ),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      draft.catalogExerciseId = selected['id'] as int?;
      draft.nameController.text = (selected['name'] ?? '').toString();
      draft.isCollapsed = false;
    });
    _handleDraftChanged();
    unawaited(_fetchExerciseLastSet(draft.nameController.text));
  }

  void _addExercise() {
    late final _ExerciseDraft draft;
    setState(() {
      for (final exercise in _exercises) {
        exercise.isCollapsed = true;
      }
      draft = _ExerciseDraft.empty();
      _exercises.add(draft);
    });
    _handleDraftChanged();
    _scrollToKey(draft.containerKey);
  }

  void _removeExercise(int index) {
    if (_exercises.length == 1) {
      return;
    }
    setState(() {
      final draft = _exercises.removeAt(index);
      draft.dispose();
    });
    _handleDraftChanged();
  }

  Future<void> _openExerciseNoteDialog(int exerciseIndex) async {
    final exercise = _exercises[exerciseIndex];
    final tempController =
        TextEditingController(text: exercise.noteController.text);
    String? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Заметка к упражнению'),
          content: TextField(
            controller: tempController,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
            ),
            if (exercise.noteController.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  result = '';
                  Navigator.of(ctx).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                ),
                child: const Text('Удалить'),
              ),
            FilledButton(
              onPressed: () {
                result = tempController.text.trim();
                Navigator.of(ctx).pop();
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    tempController.dispose();
    if (result != null) {
      setState(() {
        exercise.noteController.text = result!;
      });
      _handleDraftChanged();
    }
  }

  void _addSet(int exerciseIndex, {_SetDraft? copyFrom}) {
    late final _SetDraft draft;
    setState(() {
      final source = copyFrom ??
          (_exercises[exerciseIndex].sets.isEmpty
              ? null
              : _exercises[exerciseIndex].sets.last);
      final exercise = _exercises[exerciseIndex];
      exercise.isCollapsed = false;
      draft = source == null ? _SetDraft.empty() : _SetDraft.copyOf(source);
      exercise.sets.add(draft);
    });
    _handleDraftChanged();
    _scrollToKey(draft.containerKey);
  }

  void _scrollToKey(
    GlobalKey key, {
    double alignment = 0.08,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext = key.currentContext;
      if (targetContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        targetContext,
        alignment: alignment,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    final sets = _exercises[exerciseIndex].sets;
    if (sets.length == 1) {
      return;
    }
    setState(() {
      final draft = sets.removeAt(setIndex);
      draft.dispose();
    });
    _handleDraftChanged();
  }

  void _incrementReps(_SetDraft set, int delta) {
    final current = int.tryParse(set.repsController.text.trim()) ?? 0;
    set.repsController.text = (current + delta).clamp(0, 999).toString();
    _handleDraftChanged();
  }

  void _incrementWeight(_SetDraft set, double delta) {
    final current = _parseWeight(set.weightController.text) ?? 0;
    set.weightController.text = formatWeight(current + delta);
    _handleDraftChanged();
  }

  Future<void> _editWeight(_SetDraft set) async {
    final controller = TextEditingController();
    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Точный вес',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Введите нужный вес сразу, например 31.5 кг.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Вес, кг',
                    hintText: 'Например, 31.5',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniActionChip(
                      label: 'Очистить',
                      onTap: () {
                        controller.clear();
                        Navigator.of(context).pop(0);
                      },
                    ),
                    _MiniActionChip(
                      label: '20 кг',
                      onTap: () => Navigator.of(context).pop(20),
                    ),
                    _MiniActionChip(
                      label: '25 кг',
                      onTap: () => Navigator.of(context).pop(25),
                    ),
                    _MiniActionChip(
                      label: '30 кг',
                      onTap: () => Navigator.of(context).pop(30),
                    ),
                    _MiniActionChip(
                      label: '40 кг',
                      onTap: () => Navigator.of(context).pop(40),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final parsed = _parseWeight(controller.text);
                      if (parsed == null && controller.text.trim().isNotEmpty) {
                        Navigator.of(context).pop(double.nan);
                        return;
                      }
                      Navigator.of(context).pop(parsed ?? 0);
                    },
                    child: const Text('Применить'),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );

    controller.dispose();

    if (value == null) {
      return;
    }
    if (value.isNaN) {
      _showError('Введите корректный вес, например 31.5');
      return;
    }

    set.weightController.text = value <= 0 ? '' : formatWeight(value);
    _handleDraftChanged();
  }

  void _handleDraftChanged() {
    final fingerprint = _createFingerprint(_buildDraftSnapshot());
    final hasUnsavedChanges = fingerprint != _lastSavedFingerprint;

    if (mounted) {
      setState(() {
        _hasUnsavedChanges = hasUnsavedChanges;
        _saveStatus =
            hasUnsavedChanges ? _SaveStatus.unsaved : _SaveStatus.saved;
      });
    } else {
      _hasUnsavedChanges = hasUnsavedChanges;
      _saveStatus = hasUnsavedChanges ? _SaveStatus.unsaved : _SaveStatus.saved;
    }
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    if (!_shouldPersistDrafts) {
      unawaited(_clearDraftSnapshot());
      return;
    }
    _draftSaveTimer = Timer(_autoSaveDelay, _persistDraftSnapshot);
  }

  Future<void> _persistDraftSnapshot({bool syncedWithServer = false}) async {
    if (!_shouldPersistDrafts) {
      await _clearDraftSnapshot();
      return;
    }
    final previousStatus = _saveStatus;
    if (mounted) {
      setState(() => _saveStatus = _SaveStatus.saving);
    } else {
      _saveStatus = _SaveStatus.saving;
    }

    try {
      final draft = {
        'data': _buildDraftSnapshot(),
        'synced_with_server': syncedWithServer,
      };
      for (final key in _draftKeys) {
        await LocalCache.put(key, draft);
      }
      await LocalCache.put(CacheKeys.activeWorkoutDraft, _currentDraftKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _saveStatus =
            _hasUnsavedChanges ? _SaveStatus.unsaved : _SaveStatus.saved;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saveStatus = previousStatus == _SaveStatus.saved
            ? _SaveStatus.error
            : previousStatus;
      });
    }
  }

  Map<String, dynamic> _buildDraftSnapshot() {
    return {
      if (_workoutId != null) 'id': _workoutId,
      'name': _nameController.text.trim(),
      'started_at': _startedAt.toIso8601String(),
      'finished_at': _finishedAt?.toIso8601String(),
      'exercises': List.generate(_exercises.length, (exerciseIndex) {
        final exercise = _exercises[exerciseIndex];
        final exerciseNote = exercise.noteController.text.trim();
        return {
          'catalog_exercise_id': exercise.catalogExerciseId,
          'exercise_name': exercise.nameController.text.trim(),
          'position': exerciseIndex + 1,
          'notes': exerciseNote.isEmpty ? null : exerciseNote,
          'sets': List.generate(exercise.sets.length, (setIndex) {
            final set = exercise.sets[setIndex];
            return {
              'position': setIndex + 1,
              'reps': int.tryParse(set.repsController.text.trim()) ?? 0,
              'weight': _parseWeight(set.weightController.text),
              'rpe': null,
              'notes': null,
            };
          }),
        };
      }),
    };
  }

  String _createFingerprint(Map<String, dynamic> draft) => draft.toString();

  double? _parseWeight(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  List<Map<String, dynamic>>? _buildExercisesPayload() {
    final exercisesPayload = <Map<String, dynamic>>[];
    for (var exerciseIndex = 0;
        exerciseIndex < _exercises.length;
        exerciseIndex++) {
      final exercise = _exercises[exerciseIndex];
      final exerciseName = exercise.nameController.text.trim();
      if (exercise.catalogExerciseId == null || exerciseName.isEmpty) {
        _showError(
          'Выберите упражнение из каталога для блока #${exerciseIndex + 1}.',
        );
        return null;
      }

      final setsPayload = <Map<String, dynamic>>[];
      for (var setIndex = 0; setIndex < exercise.sets.length; setIndex++) {
        final set = exercise.sets[setIndex];
        final reps = int.tryParse(set.repsController.text.trim());
        final weight = _parseWeight(set.weightController.text);
        if (reps == null) {
          _showError(
            'Введите повторы для подхода ${setIndex + 1} в упражнении "$exerciseName".',
          );
          return null;
        }
        if (set.weightController.text.trim().isNotEmpty && weight == null) {
          _showError(
            'Введите корректный вес для подхода ${setIndex + 1} в упражнении "$exerciseName".',
          );
          return null;
        }
        setsPayload.add({
          'position': setIndex + 1,
          'reps': reps,
          'weight': weight,
          'rpe': null,
          'notes': null,
        });
      }

      final exerciseNote = exercise.noteController.text.trim();
      exercisesPayload.add({
        'catalog_exercise_id': exercise.catalogExerciseId,
        'exercise_name': exerciseName,
        'position': exerciseIndex + 1,
        'notes': exerciseNote.isEmpty ? null : exerciseNote,
        'sets': setsPayload,
      });
    }
    return exercisesPayload;
  }

  DateTime _resolveFinishedAt() {
    final now = DateTime.now();
    if (DateUtils.isSameDay(_selectedDate, now) && now.isAfter(_startedAt)) {
      return now;
    }
    return _startedAt.add(const Duration(hours: 1));
  }

  Future<void> _saveWorkout({required bool finishWorkout}) async {
    if (_savingToServer) {
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Введите название тренировки.');
      return;
    }

    final exercisesPayload = _buildExercisesPayload();
    if (exercisesPayload == null) {
      return;
    }

    final finishedAt = finishWorkout
        ? _resolveFinishedAt()
        : (_isFinished ? _finishedAt ?? _resolveFinishedAt() : null);

    setState(() {
      _savingToServer = true;
      _saveStatus = _SaveStatus.saving;
    });

    try {
      final result = _isEditing
          ? await BackendApi.updateWorkout(
              workoutId: _workoutId!,
              name: name,
              exercises: exercisesPayload,
              startedAt: _startedAt,
              finishedAt: finishedAt,
            )
          : await BackendApi.createWorkoutDetailed(
              name: name,
              exercises: exercisesPayload,
              startedAt: _startedAt,
              finishedAt: finishedAt,
            );

      _workoutId ??= result['id'] as int?;
      _finishedAt = _parseDate(result['finished_at']) ?? finishedAt;
      _lastSavedFingerprint = _createFingerprint(_buildDraftSnapshot());
      _didChangeServerData = true;

      if (finishWorkout) {
        await _clearDraftSnapshot();
      } else if (_isFinished) {
        await _clearDraftSnapshot();
      } else {
        await LocalCache.remove(_newWorkoutDraftKey);
        await _persistDraftSnapshot(syncedWithServer: true);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _hasUnsavedChanges = false;
        _saveStatus = _SaveStatus.saved;
      });
      unawaited(ProgressionController.instance.refresh());

      if (finishWorkout) {
        unawaited(HapticFeedback.heavyImpact());
        Navigator.of(context).pop(true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тренировка сохранена.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saveStatus = _SaveStatus.error);
      _showError(
        BackendApi.describeError(
          error,
          fallback: finishWorkout
              ? 'Не удалось завершить тренировку.'
              : 'Не удалось сохранить тренировку.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingToServer = false);
      } else {
        _savingToServer = false;
      }
    }
  }

  Future<void> _clearDraftSnapshot() async {
    _draftSaveTimer?.cancel();
    final keysToRemove = <String>{_newWorkoutDraftKey, _currentDraftKey};
    for (final key in keysToRemove) {
      await LocalCache.remove(key);
    }
    final activeDraft = LocalCache.get<String>(CacheKeys.activeWorkoutDraft);
    if (activeDraft != null && keysToRemove.contains(activeDraft)) {
      await LocalCache.remove(CacheKeys.activeWorkoutDraft);
    }
  }

  Future<bool> _confirmLeaveIfNeeded() async {
    if (!_hasUnsavedChanges) {
      return true;
    }
    if (_isFinished) {
      final shouldLeaveFinished = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Есть несохранённые изменения'),
          content: const Text(
            'Если выйти сейчас, изменения в завершённой тренировке будут потеряны.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Выйти'),
            ),
          ],
        ),
      );
      return shouldLeaveFinished ?? false;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Есть несохранённые изменения'),
        content: const Text(
          'Если выйти сейчас, изменения останутся только в черновике и не попадут в завершённую тренировку.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Остаться'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  Future<void> _handleBackPressed() async {
    final shouldLeave = await _confirmLeaveIfNeeded();
    if (!mounted || !shouldLeave) {
      return;
    }
    Navigator.of(context).pop(_didChangeServerData);
  }

  Future<void> _handleMinimize() async {
    if (_savingToServer) return;
    if (_hasUnsavedChanges || !_isEditing) {
      await _saveWorkout(finishWorkout: false);
      if (!mounted || _saveStatus == _SaveStatus.error) return;
    }
    if (mounted) {
      Navigator.of(context).pop(_didChangeServerData);
    }
  }

  Future<void> _handleFinishPressed() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить тренировку?'),
        content: const Text(
          'После завершения тренировка перестанет храниться как черновик. Если захотите что-то поменять позже, изменения нужно будет сохранять сразу.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (shouldFinish != true) {
      return;
    }
    await _saveWorkout(finishWorkout: true);
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _saveStatusLabel() {
    switch (_saveStatus) {
      case _SaveStatus.saved:
        return 'Сохранено';
      case _SaveStatus.unsaved:
        return 'Есть изменения';
      case _SaveStatus.saving:
        return 'Сохраняем...';
      case _SaveStatus.error:
        return 'Ошибка сохранения';
    }
  }

  Color _saveStatusColor(ColorScheme scheme) {
    switch (_saveStatus) {
      case _SaveStatus.saved:
        return scheme.primary;
      case _SaveStatus.unsaved:
        return scheme.secondary;
      case _SaveStatus.saving:
        return scheme.tertiary;
      case _SaveStatus.error:
        return scheme.error;
    }
  }

  Map<String, dynamic> _draftWorkoutForHeatmap() {
    return {
      'exercises': List.generate(_exercises.length, (exerciseIndex) {
        final exercise = _exercises[exerciseIndex];
        return {
          'catalog_exercise_id': exercise.catalogExerciseId,
          'exercise_name': exercise.nameController.text.trim(),
          'position': exerciseIndex + 1,
          'sets': List.generate(exercise.sets.length, (setIndex) {
            final set = exercise.sets[setIndex];
            return {
              'position': setIndex + 1,
              'reps': int.tryParse(set.repsController.text.trim()) ?? 0,
              'weight': _parseWeight(set.weightController.text),
            };
          }),
        };
      }),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final calculator = const MuscleLoadCalculator();
    final rawLoads = calculator.calculateForWorkout(
      workout: _draftWorkoutForHeatmap(),
      exerciseCatalog: _catalog,
    );
    final normalizedLoads = calculator.normalizer.normalize(rawLoads);

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _handleBackPressed();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _handleBackPressed,
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(_isEditing ? 'Тренировка' : 'Новая тренировка'),
          backgroundColor: Colors.transparent,
          actions: [
            if (_isEditing && _isFinished)
              IconButton(
                icon: const Icon(Icons.ios_share_rounded),
                tooltip: 'Поделиться карточкой',
                onPressed: () => WorkoutShareService.share(
                  context: context,
                  workout: _buildDraftSnapshot(),
                  exerciseCatalog: _catalog,
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow.withValues(alpha: 0.98),
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _saveStatusColor(scheme),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveStatusLabel(),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: _saveStatusColor(scheme),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (_restoredDraft)
                      StatusBadge(
                        label: 'Черновик',
                        color: scheme.secondary,
                        compact: true,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _savingToServer
                            ? null
                            : _isFinished
                                ? () => _saveWorkout(finishWorkout: false)
                                : _handleMinimize,
                        icon: _savingToServer
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_isFinished
                                ? Icons.save_outlined
                                : Icons.minimize_outlined),
                        label: Text(_isFinished ? 'Сохранить' : 'Свернуть'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _savingToServer || _isFinished
                            ? null
                            : _handleFinishPressed,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(_isFinished ? 'Завершена' : 'Завершить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: AppBackdrop(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _pickDate,
                    child: StatusBadge(
                      label: formatShortDate(_selectedDate),
                      color: scheme.onSurfaceVariant,
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                  StatusBadge(
                    label: _saveStatusLabel(),
                    color: _saveStatusColor(scheme),
                    icon: Icons.cloud_done_outlined,
                  ),
                  StatusBadge(
                    label: _isFinished ? 'Завершена' : 'В работе',
                    color: _isFinished ? scheme.primary : scheme.secondary,
                    icon: _isFinished
                        ? Icons.check_circle_outline
                        : Icons.fitness_center,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_catalogError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DashboardCard(
                    child: Text(_catalogError!),
                  ),
                ),
              ...List.generate(_exercises.length, (exerciseIndex) {
                final exercise = _exercises[exerciseIndex];
                final accent = _exerciseAccentColor(scheme, exerciseIndex);
                final lastSetState =
                    _lastSetByExerciseName[exercise.nameController.text.trim()];
                final canDelete = _exercises.length > 1;
                final isEmpty =
                    exercise.nameController.text.trim().isEmpty;
                return Padding(
                  key: exercise.containerKey,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: ObjectKey(exercise),
                    direction: canDelete && !isEmpty
                        ? DismissDirection.endToStart
                        : DismissDirection.none,
                    confirmDismiss: (_) => showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить упражнение?'),
                        content: const Text(
                          'Упражнение и все подходы будут удалены безвозвратно.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(ctx).colorScheme.error,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    ),
                    onDismissed: (_) => _removeExercise(exerciseIndex),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Удалить',
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.delete_outline,
                              color: scheme.onErrorContainer),
                        ],
                      ),
                    ),
                    child: DashboardCard(
                      leftAccentColor: accent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${exerciseIndex + 1}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _pickExercise(exerciseIndex),
                                child: exercise.nameController.text
                                        .trim()
                                        .isEmpty
                                    ? Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color:
                                                accent.withValues(alpha: 0.30),
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.add_circle_outline,
                                                size: 16, color: accent),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Выберите упражнение',
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      color: accent,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    exercise.nameController.text
                                                        .trim(),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  if (lastSetState?.loading ==
                                                      true)
                                                    Text(
                                                      'Загружаем прошлый рабочий подход...',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: scheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    )
                                                  else if (lastSetState
                                                          ?.lastSet !=
                                                      null)
                                                    Text(
                                                      'Последний рабочий: ${formatWeight(lastSetState!.lastSet!.weight)}\u00A0кг\u00A0×\u00A0${lastSetState.lastSet!.reps}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: scheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    )
                                                  else
                                                    Text(
                                                      'Подходов: ${exercise.sets.length}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: scheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: scheme.onSurfaceVariant
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _openExerciseNoteDialog(exerciseIndex),
                              tooltip: 'Заметка к упражнению',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                exercise.noteController.text.isNotEmpty
                                    ? Icons.sticky_note_2
                                    : Icons.sticky_note_2_outlined,
                                size: 20,
                                color: exercise.noteController.text.isNotEmpty
                                    ? scheme.secondary
                                    : scheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(
                                () => exercise.isCollapsed =
                                    !exercise.isCollapsed,
                              ),
                              tooltip: exercise.isCollapsed
                                  ? 'Развернуть упражнение'
                                  : 'Свернуть упражнение',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                exercise.isCollapsed
                                    ? Icons.expand_more_rounded
                                    : Icons.expand_less_rounded,
                              ),
                            ),
                            if (isEmpty && canDelete)
                              IconButton(
                                onPressed: () =>
                                    _removeExercise(exerciseIndex),
                                tooltip: 'Удалить упражнение',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                        ),
                        if (exercise.noteController.text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () =>
                                _openExerciseNoteDialog(exerciseIndex),
                            child: Container(
                              margin: const EdgeInsets.only(left: 2, right: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    scheme.secondary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.secondary
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.sticky_note_2_outlined,
                                    size: 13,
                                    color: scheme.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      exercise.noteController.text,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (!exercise.isCollapsed) ...[
                          const SizedBox(height: 10),
                          Builder(builder: (context) {
                            final isMobile =
                                MediaQuery.sizeOf(context).width < 600;
                            final labelStyle = Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                );
                            return Padding(
                              padding:
                                  const EdgeInsets.only(left: 38, bottom: 2),
                              child: Row(
                                children: [
                                  if (isMobile) ...[
                                    Expanded(
                                      child: Center(
                                          child: Text('кг', style: labelStyle)),
                                    ),
                                    const SizedBox(width: 26),
                                    Expanded(
                                      child: Center(
                                          child:
                                              Text('раз', style: labelStyle)),
                                    ),
                                    const SizedBox(width: 72),
                                  ] else ...[
                                    SizedBox(
                                      width: 110,
                                      child: Center(
                                          child: Text('кг', style: labelStyle)),
                                    ),
                                    const SizedBox(width: 26),
                                    SizedBox(
                                      width: 110,
                                      child: Center(
                                          child:
                                              Text('раз', style: labelStyle)),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          ...List.generate(exercise.sets.length, (setIndex) {
                            final set = exercise.sets[setIndex];
                            return Padding(
                              key: set.containerKey,
                              padding: EdgeInsets.only(
                                bottom: setIndex == exercise.sets.length - 1
                                    ? 0
                                    : 4,
                              ),
                              child: _WorkoutSetRow(
                                index: setIndex,
                                set: set,
                                onChanged: _handleDraftChanged,
                                onDelete: exercise.sets.length == 1
                                    ? null
                                    : () => _removeSet(exerciseIndex, setIndex),
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _addSet(exerciseIndex),
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondary
                                    .withValues(alpha: 0.18),
                                foregroundColor:
                                    Theme.of(context).colorScheme.secondary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 20),
                              label: const Text(
                                'Добавить подход',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          Text(
                            'Подходов: ${exercise.sets.length}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                );
              }),
              FilledButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Добавить упражнение'),
              ),
              const SizedBox(height: 12),
              MuscleHeatmapCard(
                title: '',
                subtitle: '',
                rawLoads: rawLoads,
                normalizedLoads: normalizedLoads,
                showHeader: false,
                emptyMessage:
                    'Добавьте упражнения с подходами, чтобы увидеть тепловую карту.',
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Тоннаж: ${formatTonnage(
                    _exercises.fold<double>(
                      0,
                      (sum, exercise) =>
                          sum +
                          calculateExerciseTonnage({
                            'sets': exercise.sets.map((set) {
                              return {
                                'reps':
                                    int.tryParse(set.repsController.text) ?? 0,
                                'weight':
                                    _parseWeight(set.weightController.text) ??
                                        0,
                              };
                            }).toList(),
                          }),
                    ),
                  )}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SaveStatus {
  saved,
  unsaved,
  saving,
  error,
}

class _ExerciseDraft {
  _ExerciseDraft({
    required this.nameController,
    required this.noteController,
    required this.catalogExerciseId,
    required this.sets,
    required this.isCollapsed,
    required this.containerKey,
  });

  factory _ExerciseDraft.empty() {
    return _ExerciseDraft(
      nameController: TextEditingController(),
      noteController: TextEditingController(),
      catalogExerciseId: null,
      sets: [_SetDraft.empty()],
      isCollapsed: false,
      containerKey: GlobalKey(),
    );
  }

  factory _ExerciseDraft.fromMap(Map<String, dynamic> map) {
    final rawSets = (map['sets'] as List?)?.cast<dynamic>() ?? const [];
    final sets = rawSets.isEmpty
        ? [_SetDraft.empty()]
        : rawSets
            .map(
              (set) => _SetDraft.fromMap((set as Map).cast<String, dynamic>()),
            )
            .toList();
    return _ExerciseDraft(
      nameController:
          TextEditingController(text: (map['exercise_name'] ?? '').toString()),
      noteController:
          TextEditingController(text: (map['notes'] ?? '').toString()),
      catalogExerciseId: map['catalog_exercise_id'] as int?,
      sets: sets,
      isCollapsed: false,
      containerKey: GlobalKey(),
    );
  }

  final TextEditingController nameController;
  final TextEditingController noteController;
  int? catalogExerciseId;
  final List<_SetDraft> sets;
  bool isCollapsed;
  final GlobalKey containerKey;

  void dispose() {
    nameController.dispose();
    noteController.dispose();
    for (final set in sets) {
      set.dispose();
    }
  }
}

class _SetDraft {
  _SetDraft({
    required this.repsController,
    required this.weightController,
    required this.containerKey,
  });

  factory _SetDraft.empty() {
    return _SetDraft(
      repsController: TextEditingController(text: '8'),
      weightController: TextEditingController(),
      containerKey: GlobalKey(),
    );
  }

  factory _SetDraft.copyOf(_SetDraft source) {
    return _SetDraft(
      repsController: TextEditingController(text: source.repsController.text),
      weightController:
          TextEditingController(text: source.weightController.text),
      containerKey: GlobalKey(),
    );
  }

  factory _SetDraft.fromMap(Map<String, dynamic> map) {
    return _SetDraft(
      repsController:
          TextEditingController(text: (map['reps'] ?? 0).toString()),
      weightController: TextEditingController(
        text: map['weight'] == null ? '' : map['weight'].toString(),
      ),
      containerKey: GlobalKey(),
    );
  }

  final TextEditingController repsController;
  final TextEditingController weightController;
  final GlobalKey containerKey;

  void dispose() {
    repsController.dispose();
    weightController.dispose();
  }
}

class _ExerciseCatalogSheet extends StatefulWidget {
  const _ExerciseCatalogSheet({
    required this.catalog,
    required this.initialExerciseId,
  });

  final List<Map<String, dynamic>> catalog;
  final int? initialExerciseId;

  @override
  State<_ExerciseCatalogSheet> createState() => _ExerciseCatalogSheetState();
}

class _ExerciseCatalogSheetState extends State<_ExerciseCatalogSheet> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = widget.catalog.where((exercise) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final name = (exercise['name'] ?? '').toString().toLowerCase();
      final primaryMuscle = capitalizeRu(
        (exercise['primary_muscle'] ?? '').toString().replaceAll('_', ' '),
      ).toLowerCase();
      return name.contains(normalizedQuery) ||
          primaryMuscle.contains(normalizedQuery);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  labelText: 'Поиск упражнения',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Ничего не найдено.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final exercise = filtered[index];
                          final id = exercise['id'] as int?;
                          final selected =
                              id != null && id == widget.initialExerciseId;
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.fitness_center,
                            ),
                            title: Text((exercise['name'] ?? '').toString()),
                            subtitle: Text(
                              capitalizeRu(
                                (exercise['primary_muscle'] ?? '')
                                    .toString()
                                    .replaceAll('_', ' '),
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(exercise),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutSetRow extends StatelessWidget {
  const _WorkoutSetRow({
    required this.index,
    required this.set,
    required this.onChanged,
    this.onDelete,
  });

  final int index;
  final _SetDraft set;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    Widget weightField = _CompactSetField(
      controller: set.weightController,
      hint: '0',
      suffix: 'кг',
      onChanged: (_) => onChanged(),
    );
    Widget repsField = _CompactSetField(
      controller: set.repsController,
      hint: '0',
      onChanged: (_) => onChanged(),
    );

    if (!isMobile) {
      weightField = SizedBox(width: 110, child: weightField);
      repsField = SizedBox(width: 110, child: repsField);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            if (isMobile) Expanded(child: weightField) else weightField,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '×',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (isMobile) Expanded(child: repsField) else repsField,
            if (!isMobile) const Spacer(),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                tooltip: 'Удалить подход',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 36, height: 36),
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              )
            else
              const SizedBox(width: 36),
          ],
        ),
      ],
    );
  }
}

class _CompactSetField extends StatelessWidget {
  const _CompactSetField({
    required this.controller,
    required this.hint,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
        controller: controller,
        onChanged: onChanged,
        onTap: () {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        },
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        decoration: InputDecoration(
          hintText: hint,
          suffixText: suffix,
          suffixStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: scheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
    );
  }
}

class _MiniActionChip extends StatelessWidget {
  const _MiniActionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      backgroundColor: scheme.secondary.withValues(alpha: 0.1),
      side: BorderSide(color: scheme.secondary.withValues(alpha: 0.14)),
      label: Text(
        label,
        style: TextStyle(
          color: scheme.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onTap,
    );
  }
}

Color _exerciseAccentColor(ColorScheme scheme, int index) {
  const palette = <Color>[
    Color(0xFF4CAF50), // зелёный
    Color(0xFF2196F3), // синий
    Color(0xFFFF9800), // оранжевый
    Color(0xFFE91E63), // малиновый
    Color(0xFF9C27B0), // фиолетовый
    Color(0xFF00BCD4), // бирюзовый
  ];
  return palette[index % palette.length];
}

class _ExerciseLastSetState {
  const _ExerciseLastSetState.loading()
      : loading = true,
        lastSet = null;

  const _ExerciseLastSetState.loaded(this.lastSet) : loading = false;

  final bool loading;
  final _WorkingSetSummary? lastSet;
}

class _WorkingSetSummary {
  const _WorkingSetSummary({
    required this.reps,
    required this.weight,
  });

  final int reps;
  final double weight;
}
