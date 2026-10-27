import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../progression/application/progression_controller.dart';
import '../domain/today_plan.dart';
import '../../workouts/presentation/workout_form_screen.dart';
import '../../progression/presentation/gamification_widgets.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  static const int _defaultWeeklyTarget = 3;

  Map<String, dynamic>? _draftWorkout;
  List<Map<String, dynamic>>? _workouts;
  List<Map<String, dynamic>>? _catalog;
  TodayPlan? _plan;
  _TodaySummary _summary = const _TodaySummary.empty();
  int _weeklyTargetFromProfile = _defaultWeeklyTarget;
  bool _templatesLoading = false;
  bool _aiCoachLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshScreen();
  }

  Future<void> _refreshScreen() async {
    _catalog ??= _cachedList(CacheKeys.exerciseCatalogCache);
    final cached = _cachedList(CacheKeys.workoutsCache);
    if (cached != null && cached.isNotEmpty) {
      _applyWorkouts(cached);
      // Черновик показываем сразу; удалять его по устаревшему кэшу нельзя.
      unawaited(_loadDraft(cached, fromServer: false));
    }

    await Future.wait([
      _loadFitnessProfile(),
      _loadCatalog(),
      _loadWorkouts(),
    ]);
    // Профиль и каталог могли прийти позже истории — пересчитываем.
    final workouts = _workouts;
    if (workouts != null) _applyWorkouts(workouts);
  }

  List<Map<String, dynamic>>? _cachedList(String key) {
    return LocalCache.get<List>(key)
        ?.cast<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
  }

  /// История загружается один раз на весь экран: неделя, план и черновик
  /// считаются из неё.
  Future<void> _loadWorkouts() async {
    List<Map<String, dynamic>>? workouts;
    try {
      workouts = await BackendApi.getWorkouts();
    } catch (_) {
      workouts = _cachedList(CacheKeys.workoutsCache);
    }
    if (!mounted) return;
    _applyWorkouts(workouts ?? const []);
    await _loadDraft(workouts ?? const [], fromServer: true);
  }

  Future<void> _loadCatalog() async {
    if (_catalog != null && _catalog!.isNotEmpty) return;
    try {
      _catalog = await BackendApi.getExercises();
    } catch (_) {}
  }

  void _applyWorkouts(List<Map<String, dynamic>> workouts) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _workouts = workouts;
      _plan = buildTodayPlan(
        workouts: workouts,
        exerciseCatalog: _catalog ?? const [],
        now: now,
      );
      _summary = _buildSummary(workouts, now);
    });
  }

  _TodaySummary _buildSummary(
    List<Map<String, dynamic>> workouts,
    DateTime now,
  ) {
    final weekStart = DateUtils.dateOnly(
      now.subtract(Duration(days: now.weekday - 1)),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));

    var weekCount = 0;
    final activeDateSet = <DateTime>{};
    final activeWeekdaySet = <int>{};
    for (final workout in workouts) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      if (startedAt == null ||
          startedAt.isBefore(weekStart) ||
          !startedAt.isBefore(weekEnd)) {
        continue;
      }
      weekCount++;
      activeDateSet.add(DateUtils.dateOnly(startedAt));
      activeWeekdaySet.add(startedAt.weekday);
    }

    return _TodaySummary(
      weekCount: weekCount,
      activeDays: activeDateSet.length,
      weeklyTarget: max(_weeklyTargetFromProfile, weekCount),
      activeWeekdays: activeWeekdaySet,
    );
  }

  Future<void> _loadFitnessProfile() async {
    try {
      final data = await BackendApi.getFitnessProfile();
      final days = data['daysPerWeek'];
      if (days is int && days >= 1 && days <= 7 && mounted) {
        setState(() => _weeklyTargetFromProfile = days);
      }
    } catch (_) {}
  }

  Future<void> _loadDraft(
    List<Map<String, dynamic>> workouts, {
    required bool fromServer,
  }) async {
    final activeDraftKey = LocalCache.get<String>(CacheKeys.activeWorkoutDraft);
    Map<String, dynamic>? draftWorkout;
    if (activeDraftKey != null) {
      final cached = LocalCache.get<Map>(activeDraftKey);
      final nested = cached?['data'];
      if (nested is Map) {
        final parsedDraft = nested.cast<String, dynamic>();
        if (parsedDraft['finished_at'] == null) {
          draftWorkout = parsedDraft;
        } else {
          await LocalCache.remove(activeDraftKey);
          await LocalCache.remove(CacheKeys.activeWorkoutDraft);
        }
      }
    }

    // Локального черновика нет — берём самую свежую незавершённую
    // тренировку с сервера.
    if (draftWorkout == null) {
      final unfinished = workouts
          .where((w) => w['finished_at'] == null)
          .toList()
        ..sort((a, b) => (b['started_at'] ?? '')
            .toString()
            .compareTo((a['started_at'] ?? '').toString()));
      draftWorkout = unfinished.firstOrNull;
    }

    // Черновик тренировки, которую уже удалили на сервере, не показываем.
    final draftWorkoutId = draftWorkout?['id'] as int?;
    if (fromServer &&
        activeDraftKey != null &&
        draftWorkoutId != null &&
        workouts.isNotEmpty &&
        !workouts.any((item) => item['id'] == draftWorkoutId)) {
      await LocalCache.remove(activeDraftKey);
      await LocalCache.remove(CacheKeys.activeWorkoutDraft);
      draftWorkout = null;
    }

    if (!mounted) return;
    setState(() => _draftWorkout = draftWorkout);
  }

  Future<void> _deleteDraft() async {
    final workout = _draftWorkout;
    if (workout == null) return;

    setState(() => _draftWorkout = null);

    final workoutId = workout['id'] as int?;

    final activeDraftKey = LocalCache.get<String>(CacheKeys.activeWorkoutDraft);
    if (activeDraftKey != null) await LocalCache.remove(activeDraftKey);
    await LocalCache.remove(CacheKeys.activeWorkoutDraft);
    if (workoutId != null) {
      await LocalCache.remove('workout_draft_$workoutId');
    }

    if (workoutId != null) {
      try {
        await BackendApi.deleteWorkout(workoutId);
      } catch (e) {
        if (mounted) {
          setState(() => _draftWorkout = workout);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                BackendApi.describeError(
                  e,
                  fallback: 'Не удалось удалить тренировку.',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _openWorkout({
    Map<String, dynamic>? workout,
    DateTime? date,
    String? name,
    List<Map<String, dynamic>>? exercises,
  }) async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormScreen(
          initialWorkout: workout,
          initialDate: date,
          initialName: name,
          initialExercises: exercises,
        ),
      ),
    );
    if (mounted) {
      await _refreshScreen();
    }
  }

  Future<void> _startPlan() async {
    final plan = _plan;
    if (plan == null) {
      await _openWorkout(date: DateTime.now());
      return;
    }
    await _openWorkout(
      date: DateTime.now(),
      name: plan.workoutName,
      exercises: plan.toWorkoutExercises(),
    );
  }

  Future<void> _startFromTemplate() async {
    if (_templatesLoading) {
      return;
    }
    setState(() => _templatesLoading = true);
    try {
      final templates = await BackendApi.getTemplates();
      if (!mounted) {
        return;
      }
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Сначала создайте хотя бы один шаблон.')),
        );
        return;
      }

      final selectedTemplate = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Выберите шаблон',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: templates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final template = templates[index];
                        final exercises =
                            (template['exercises'] as List?)?.length ?? 0;
                        return ListTile(
                          leading: const Icon(Icons.library_books_outlined),
                          title:
                              Text((template['name'] ?? 'Шаблон').toString()),
                          subtitle: Text('Упражнений: $exercises'),
                          onTap: () => Navigator.of(context).pop(template),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (selectedTemplate == null || !mounted) {
        return;
      }

      final workouts = _workouts ?? await BackendApi.getWorkouts();
      if (!mounted) {
        return;
      }
      final initialExercises =
          _buildExercisesFromTemplate(selectedTemplate, workouts);
      await _openWorkout(
        date: DateTime.now(),
        name: (selectedTemplate['name'] ?? 'Тренировка').toString(),
        exercises: initialExercises,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось открыть список шаблонов.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _templatesLoading = false);
      }
    }
  }

  Future<void> _startFromAiCoach() async {
    if (_aiCoachLoading) {
      return;
    }

    final result = await showModalBottomSheet<
        ({_AiCoachIntensity intensity, String notes})>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final notesController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Какая нужна интенсивность?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI-коуч соберёт программу на основе истории тренировок.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ..._AiCoachIntensity.values.map(
                    (item) => ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      onTap: () => Navigator.of(context).pop(
                        (
                          intensity: item,
                          notes: notesController.text.trim(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Пожелания к тренировке',
                      hintText:
                          'Например: хочу больше ног, устал — сделай легче...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      counterStyle: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    final intensity = result.intensity;
    final userNotes = result.notes;

    setState(() => _aiCoachLoading = true);
    try {
      final workouts = await _loadWorkoutsForAiCoach()
          .catchError((_) => <Map<String, dynamic>>[]);
      final exerciseCatalog = await _loadExerciseCatalogForAiCoach()
          .catchError((_) => <Map<String, dynamic>>[]);
      final response = await BackendApi.generateCoachWorkout(
        intensityTitle: intensity.title,
        minExercises: intensity.minExercises,
        maxExercises: intensity.maxExercises,
        userNotes: userNotes.isEmpty ? null : userNotes,
      );
      final reply = (response['reply'] ?? '').toString().trim();
      final plan = _decodeAiCoachWorkoutPlan(reply);
      if (!mounted) {
        return;
      }

      final initialExercises = _buildExercisesFromAiCoachPlan(
        plan.exercises,
        workouts,
        exerciseCatalog,
      );
      if (initialExercises.isEmpty) {
        throw const FormatException('empty-plan');
      }

      final action = await _showAiWorkoutActionSheet(plan);
      if (!mounted || action == null) return;

      if (action == _AiWorkoutAction.saveTemplate) {
        await _saveAiWorkoutAsTemplate(plan, initialExercises);
      } else {
        await _openWorkout(
          date: DateTime.now(),
          name: plan.name,
          exercises: initialExercises,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final fallback = error is FormatException
          ? 'AI-коуч вернул программу в неожиданном формате. Попробуйте ещё раз.'
          : 'Не удалось собрать тренировку от AI-коуча.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(error, fallback: fallback),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _aiCoachLoading = false);
      }
    }
  }

  Future<_AiWorkoutAction?> _showAiWorkoutActionSheet(
    _AiCoachWorkoutPlan plan,
  ) {
    return showModalBottomSheet<_AiWorkoutAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.name,
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                plan.exercises.map((e) => e.exerciseName).join(' · '),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, _AiWorkoutAction.startNow),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Начать тренировку'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, _AiWorkoutAction.saveTemplate),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Сохранить как шаблон'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAiWorkoutAsTemplate(
    _AiCoachWorkoutPlan plan,
    List<Map<String, dynamic>> builtExercises,
  ) async {
    final templateExercises = List.generate(plan.exercises.length, (i) {
      final planEx = plan.exercises[i];
      final built = i < builtExercises.length ? builtExercises[i] : null;
      return {
        'catalog_exercise_id': built?['catalog_exercise_id'],
        'exercise_name':
            (built?['exercise_name'] ?? planEx.exerciseName).toString(),
        'position': i + 1,
        'target_sets': planEx.sets,
        'target_reps': planEx.reps,
        'target_weight': null,
      };
    });
    await BackendApi.createTemplate(
      name: plan.name,
      exercises: const [],
      templateExercises: templateExercises,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Шаблон «${plan.name}» сохранён')),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadWorkoutsForAiCoach() async {
    final loaded = _workouts;
    if (loaded != null) return loaded;
    final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
    if (cached != null) {
      return cached
          .cast<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
    }
    return BackendApi.getWorkouts();
  }

  Future<List<Map<String, dynamic>>> _loadExerciseCatalogForAiCoach() async {
    final loaded = _catalog;
    if (loaded != null && loaded.isNotEmpty) return loaded;
    final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
    if (cached != null) {
      return cached
          .cast<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
    }
    return BackendApi.getExercises();
  }

  _AiCoachWorkoutPlan _decodeAiCoachWorkoutPlan(String rawReply) {
    final normalized = rawReply.trim();
    if (normalized.isEmpty) {
      throw const FormatException('empty-reply');
    }

    final fencedMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(
      normalized,
    );
    final jsonSource =
        fencedMatch?.group(1)?.trim() ?? _extractFirstJsonObject(normalized);
    final decoded = jsonDecode(jsonSource);
    if (decoded is! Map) {
      throw const FormatException('invalid-root');
    }
    return _AiCoachWorkoutPlan.fromMap(decoded.cast<String, dynamic>());
  }

  String _extractFirstJsonObject(String value) {
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw const FormatException('json-not-found');
    }
    return value.substring(start, end + 1);
  }

  List<Map<String, dynamic>> _buildExercisesFromAiCoachPlan(
    List<_AiCoachExercisePlan> planExercises,
    List<Map<String, dynamic>> workouts,
    List<Map<String, dynamic>> exerciseCatalog,
  ) {
    final prepared = <Map<String, dynamic>>[];
    final catalogByNormalizedName = {
      for (final item in exerciseCatalog)
        _normalizeExerciseLookupName((item['name'] ?? '').toString()): item,
    };

    for (var index = 0; index < planExercises.length; index++) {
      final exercisePlan = planExercises[index];
      final matchedCatalog = catalogByNormalizedName[
          _normalizeExerciseLookupName(exercisePlan.exerciseName)];
      final templateExercise = {
        'catalog_exercise_id': matchedCatalog?['id'],
        'exercise_name':
            (matchedCatalog?['name'] ?? exercisePlan.exerciseName).toString(),
        'target_sets': exercisePlan.sets,
        'target_reps': exercisePlan.reps,
      };
      final lastExercise = _findLatestExercise(workouts, templateExercise);
      final lastSets =
          (lastExercise?['sets'] as List?)?.cast<dynamic>() ?? const [];
      final lastWeight = lastSets.isNotEmpty
          ? ((lastSets.last as Map).cast<String, dynamic>()['weight'] as num?)
              ?.toDouble()
          : null;
      final repsHint = _parseRepsHint(
        exercisePlan.reps,
        fallbackSets: lastSets,
      );
      final warmupSets =
          List.generate(exercisePlan.warmupSets.length, (warmupIndex) {
        final warmupPlan = exercisePlan.warmupSets[warmupIndex];
        return {
          'position': warmupIndex + 1,
          'reps': _parseRepsHint(
            warmupPlan.reps,
            fallbackSets: const [],
          ),
          'weight': null,
          'set_type': 'warmup',
          'rpe': null,
          'notes': warmupPlan.notes,
        };
      });
      final workingSets = List.generate(exercisePlan.sets, (setIndex) {
        return {
          'position': warmupSets.length + setIndex + 1,
          'reps': repsHint,
          'weight': lastWeight,
          'set_type': 'work',
          'rpe': null,
          'notes': null,
        };
      });

      prepared.add({
        'catalog_exercise_id': matchedCatalog?['id'] as int?,
        'exercise_name':
            (matchedCatalog?['name'] ?? exercisePlan.exerciseName).toString(),
        'position': index + 1,
        'notes': exercisePlan.notes,
        'sets': [...warmupSets, ...workingSets],
      });
    }

    return prepared;
  }

  int _parseRepsHint(String rawReps, {required List<dynamic> fallbackSets}) {
    final normalized = rawReps.trim();
    if (normalized.contains('-')) {
      final parts = normalized.split('-');
      return int.tryParse(parts.last.trim()) ?? 8;
    }
    final direct = int.tryParse(normalized);
    if (direct != null) {
      return direct;
    }
    if (fallbackSets.isNotEmpty) {
      final lastSet = (fallbackSets.last as Map).cast<String, dynamic>();
      return (lastSet['reps'] as int?) ?? 8;
    }
    return 8;
  }

  List<Map<String, dynamic>> _buildExercisesFromTemplate(
    Map<String, dynamic> template,
    List<Map<String, dynamic>> workouts,
  ) {
    final templateExercises =
        (template['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final prepared = <Map<String, dynamic>>[];

    for (var index = 0; index < templateExercises.length; index++) {
      final templateExercise =
          (templateExercises[index] as Map).cast<String, dynamic>();
      final lastExercise = _findLatestExercise(workouts, templateExercise);
      final lastSets =
          (lastExercise?['sets'] as List?)?.cast<dynamic>() ?? const [];

      final targetSets = (templateExercise['target_sets'] as int?) ?? 3;
      final targetWeight = templateExercise['target_weight'];

      // Determine reps hint: parse target_reps from template (e.g. "8" or "6-10")
      int repsHint = 8;
      final rawReps = (templateExercise['target_reps'] ?? '').toString().trim();
      if (rawReps.contains('-')) {
        final parts = rawReps.split('-');
        repsHint = int.tryParse(parts.last.trim()) ?? 8;
      } else if (rawReps.isNotEmpty) {
        repsHint = int.tryParse(rawReps) ?? 8;
      } else if (lastSets.isNotEmpty) {
        // Fall back to last session's reps as hint (but NOT weight)
        final lastSet = (lastSets.last as Map).cast<String, dynamic>();
        repsHint = (lastSet['reps'] as int?) ?? 8;
      }

      prepared.add({
        'catalog_exercise_id': templateExercise['catalog_exercise_id'],
        'exercise_name': (templateExercise['exercise_name'] ?? '').toString(),
        'position': index + 1,
        'notes': null,
        'sets': List.generate(targetSets, (setIndex) {
          return {
            'position': setIndex + 1,
            'reps': repsHint,
            'weight': targetWeight,
            'set_type': 'work',
            'rpe': null,
            'notes': null,
          };
        }),
      });
    }

    return prepared;
  }

  Map<String, dynamic>? _findLatestExercise(
    List<Map<String, dynamic>> workouts,
    Map<String, dynamic> templateExercise,
  ) {
    final templateCatalogId = templateExercise['catalog_exercise_id'];
    final templateName = (templateExercise['exercise_name'] ?? '').toString();

    final sorted = [...workouts]..sort((a, b) {
        final aDate = DateTime.tryParse((a['started_at'] ?? '').toString()) ??
            DateTime(1970);
        final bDate = DateTime.tryParse((b['started_at'] ?? '').toString()) ??
            DateTime(1970);
        return bDate.compareTo(aDate);
      });

    for (final workout in sorted) {
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      for (final exercise in exercises) {
        final map = (exercise as Map).cast<String, dynamic>();
        if (templateCatalogId != null &&
            map['catalog_exercise_id'] == templateCatalogId) {
          return map;
        }
        if ((map['exercise_name'] ?? '').toString() == templateName) {
          return map;
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draftWorkout;
    return AppBackdrop(
      child: RefreshIndicator(
        onRefresh: _refreshScreen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _TodayHeadline(dateLabel: _todayDateLabel(DateTime.now())),
            const SizedBox(height: 14),
            // Незавершённая тренировка важнее всего остального на экране.
            if (draft != null) ...[
              _DraftCard(
                draftWorkout: draft,
                onOpenDraft: () => _openWorkout(workout: draft),
                onDelete: _deleteDraft,
              ),
              const SizedBox(height: 10),
            ],
            _TodayPlanCard(
              plan: _plan,
              loading: _workouts == null,
              hasDraft: draft != null,
              templatesLoading: _templatesLoading,
              aiCoachLoading: _aiCoachLoading,
              onStartPlan: _startPlan,
              onStartEmpty: () => _openWorkout(date: DateTime.now()),
              onStartTemplate: _startFromTemplate,
              onStartAiCoach: _startFromAiCoach,
            ),
            const SizedBox(height: 10),
            _WeekSummaryCard(summary: _summary),
            const SizedBox(height: 10),
            const _NextGoalCard(),
          ],
        ),
      ),
    );
  }

  static String _todayDateLabel(DateTime date) {
    const weekdays = [
      'ПОНЕДЕЛЬНИК',
      'ВТОРНИК',
      'СРЕДА',
      'ЧЕТВЕРГ',
      'ПЯТНИЦА',
      'СУББОТА',
      'ВОСКРЕСЕНЬЕ',
    ];
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} '
        '${months[date.month - 1].toUpperCase()}';
  }
}

class _WeekSummaryCard extends StatelessWidget {
  const _WeekSummaryCard({required this.summary});

  final _TodaySummary summary;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final today = DateTime.now().weekday;
    final done = summary.weekCount;
    final target = summary.weeklyTarget;
    final remaining = max(0, target - done);

    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Неделя: $done из $target',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                remaining > 0
                    ? _remainingLabel(remaining, today)
                    : 'Цель выполнена',
                style: textTheme.bodySmall?.copyWith(
                  color:
                      remaining > 0 ? scheme.onSurfaceVariant : scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(7, (index) {
              final weekday = index + 1;
              final isActive = summary.activeWeekdays.contains(weekday);
              final isToday = weekday == today;
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? scheme.primary
                            : scheme.surfaceContainerHigh,
                        border: isToday && !isActive
                            ? Border.all(color: scheme.primary, width: 1.5)
                            : null,
                      ),
                      child: isActive
                          ? Icon(Icons.check_rounded,
                              size: 18, color: scheme.onPrimary)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayLabels[index],
                      style: textTheme.labelSmall?.copyWith(
                        color: isToday
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  static String _remainingLabel(int remaining, int todayWeekday) {
    if (remaining == 1 && todayWeekday >= 5) return 'осталась одна — сегодня?';
    if (remaining == 1) return 'осталась одна';
    if (remaining % 10 >= 2 &&
        remaining % 10 <= 4 &&
        (remaining % 100 < 10 || remaining % 100 >= 20)) {
      return 'осталось $remaining';
    }
    return 'осталось $remaining';
  }
}

class _TodayHeadline extends StatelessWidget {
  const _TodayHeadline({required this.dateLabel});

  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    // Тот же шрифт и цвет, что у заголовков экранов (ScreenHeader), но
    // всегда в одну строку: длинные дни недели ужимаются.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        dateLabel,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Bebas Neue Cyrillic',
          fontSize: 40,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          height: 0.94,
          color: isDark
              ? const Color(0xFFE8C7AA)
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// План на сегодня: фокус по группам мышц, упражнения с весом из прошлой
/// тренировки и запуск тренировки в один тап. Без LLM — всё считается из
/// истории.
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.plan,
    required this.loading,
    required this.hasDraft,
    required this.templatesLoading,
    required this.aiCoachLoading,
    required this.onStartPlan,
    required this.onStartEmpty,
    required this.onStartTemplate,
    required this.onStartAiCoach,
  });

  final TodayPlan? plan;
  final bool loading;

  /// Есть незавершённая тренировка — главная кнопка уходит на второй план.
  final bool hasDraft;
  final bool templatesLoading;
  final bool aiCoachLoading;
  final VoidCallback onStartPlan;
  final VoidCallback onStartEmpty;
  final VoidCallback onStartTemplate;
  final VoidCallback onStartAiCoach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final plan = this.plan;
    final headlineStyle = TextStyle(
      fontFamily: 'Bebas Neue Cyrillic',
      fontSize: 30,
      height: 1.0,
      letterSpacing: 0.5,
      color: scheme.onSurface,
    );

    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 54),
      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    );
    final buttonLabel =
        Text(plan != null ? 'Начать по плану' : 'Начать тренировку');
    final onPrimary = plan != null ? onStartPlan : onStartEmpty;

    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 16, color: scheme.secondary),
              const SizedBox(width: 6),
              Text(
                'ПЛАН НА СЕГОДНЯ',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.secondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (plan == null) ...[
            Text('ПЕРВАЯ ТРЕНИРОВКА', style: headlineStyle),
            const SizedBox(height: 6),
            Text(
              'Записывайте упражнения по ходу — после пары тренировок здесь '
              'появится план: что пора нагрузить и с каким весом.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ] else ...[
            Text(plan.headline, style: headlineStyle),
            const SizedBox(height: 4),
            Text(
              _reasonLine(plan.groups),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final exercise in plan.exercises)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _targetLabel(exercise),
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          if (hasDraft)
            OutlinedButton(
              onPressed: onPrimary,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                foregroundColor: scheme.primary,
                side: BorderSide(color: scheme.outlineVariant),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              child: buttonLabel,
            )
          else
            FilledButton(
              onPressed: onPrimary,
              style: buttonStyle,
              child: buttonLabel,
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (plan != null)
                Expanded(
                  child: _SecondaryStartButton(
                    icon: Icons.add_rounded,
                    label: 'Пустая',
                    onTap: onStartEmpty,
                  ),
                ),
              Expanded(
                child: _SecondaryStartButton(
                  icon: Icons.library_books_outlined,
                  label: 'Шаблон',
                  loading: templatesLoading,
                  onTap: onStartTemplate,
                ),
              ),
              Expanded(
                child: _SecondaryStartButton(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI-план',
                  loading: aiCoachLoading,
                  onTap: onStartAiCoach,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _reasonLine(List<PlannedGroup> groups) {
    final parts = groups
        .map((group) => '${group.label.toLowerCase()} — '
            '${_daysLabel(group.daysSince)}')
        .join(', ');
    return 'Без нагрузки: $parts';
  }

  static String _daysLabel(int days) {
    if (days == 0) return 'тренировали сегодня';
    final mod10 = days % 10;
    final mod100 = days % 100;
    if (mod10 == 1 && mod100 != 11) return '$days день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return '$days дня';
    }
    return '$days дней';
  }

  static String _targetLabel(PlannedExercise exercise) {
    final volume = '${exercise.sets} × ${exercise.reps}';
    final weight = exercise.weight;
    return weight == null ? volume : '$volume · ${formatWeight(weight)} кг';
  }
}

class _SecondaryStartButton extends StatelessWidget {
  const _SecondaryStartButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: loading ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: scheme.secondary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      ),
      icon: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.secondary,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label, maxLines: 1),
    );
  }
}

/// Ближайшее достижение с прогрессом — короткая цель на главном экране.
class _NextGoalCard extends StatelessWidget {
  const _NextGoalCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProgressionController.instance,
      builder: (context, _) {
        final profile = ProgressionController.instance.profile;
        // Задания недели важнее одиночной цели: если они есть — показываем их.
        if (profile != null && profile.weeklyQuests.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: WeeklyQuestsCard(
              quests: profile.weeklyQuests,
              bonusXp: profile.weeklyQuestBonusXp,
            ),
          );
        }
        final catalog = profile?.achievementCatalog ?? const [];
        final candidates = catalog
            .where((a) => !a.unlocked && a.target > 1 && a.progress > 0)
            .toList()
          ..sort((a, b) => b.ratio.compareTo(a.ratio));
        if (candidates.isEmpty) return const SizedBox.shrink();
        final goal = candidates.first;
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DashboardCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ближайшая цель · ${goal.title}',
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${goal.progress}/${goal.target}',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: goal.ratio,
                    minHeight: 6,
                    color: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _AiCoachIntensity {
  quick(
    title: 'Быстрая',
    subtitle: '5-6 упражнений',
    minExercises: 5,
    maxExercises: 6,
    icon: Icons.flash_on_outlined,
  ),
  standard(
    title: 'Стандартная',
    subtitle: '7-8 упражнений',
    minExercises: 7,
    maxExercises: 8,
    icon: Icons.fitness_center_outlined,
  ),
  intense(
    title: 'Усиленная',
    subtitle: '9-10 упражнений',
    minExercises: 9,
    maxExercises: 10,
    icon: Icons.whatshot_outlined,
  );

  const _AiCoachIntensity({
    required this.title,
    required this.subtitle,
    required this.minExercises,
    required this.maxExercises,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final int minExercises;
  final int maxExercises;
  final IconData icon;

  String get rangeLabel => '$minExercises-$maxExercises';
}

enum _AiWorkoutAction { startNow, saveTemplate }

class _AiCoachWorkoutPlan {
  const _AiCoachWorkoutPlan({
    required this.name,
    required this.exercises,
  });

  factory _AiCoachWorkoutPlan.fromMap(Map<String, dynamic> map) {
    final rawExercises =
        (map['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final exercises = rawExercises
        .whereType<Map>()
        .map(
          (item) => _AiCoachExercisePlan.fromMap(item.cast<String, dynamic>()),
        )
        .where((item) => item.exerciseName.isNotEmpty)
        .toList();
    final rawName = (map['name'] ?? '').toString().trim();
    return _AiCoachWorkoutPlan(
      name: rawName.isEmpty ? 'Тренировка от AI-коуча' : rawName,
      exercises: exercises,
    );
  }

  final String name;
  final List<_AiCoachExercisePlan> exercises;
}

class _AiCoachExercisePlan {
  const _AiCoachExercisePlan({
    required this.exerciseName,
    required this.sets,
    required this.reps,
    required this.notes,
    required this.warmupSets,
  });

  factory _AiCoachExercisePlan.fromMap(Map<String, dynamic> map) {
    final rawSets = map['sets'];
    final parsedSets = rawSets is int
        ? rawSets
        : rawSets is num
            ? rawSets.toInt()
            : int.tryParse(rawSets?.toString() ?? '');
    return _AiCoachExercisePlan(
      exerciseName: (map['exercise_name'] ?? '').toString().trim(),
      sets: (parsedSets ?? 3).clamp(1, 6),
      reps: (map['reps'] ?? '8-10').toString().trim(),
      notes: (map['notes'] ?? '').toString().trim().isEmpty
          ? null
          : (map['notes'] ?? '').toString().trim(),
      warmupSets: ((map['warmup_sets'] as List?)?.cast<dynamic>() ?? const [])
          .whereType<Map>()
          .map(
            (item) => _AiCoachWarmupSetPlan.fromMap(
              item.cast<String, dynamic>(),
            ),
          )
          .where((item) => item.reps.isNotEmpty)
          .toList(),
    );
  }

  final String exerciseName;
  final int sets;
  final String reps;
  final String? notes;
  final List<_AiCoachWarmupSetPlan> warmupSets;
}

class _AiCoachWarmupSetPlan {
  const _AiCoachWarmupSetPlan({
    required this.reps,
    required this.notes,
  });

  factory _AiCoachWarmupSetPlan.fromMap(Map<String, dynamic> map) {
    return _AiCoachWarmupSetPlan(
      reps: (map['reps'] ?? '').toString().trim(),
      notes: (map['notes'] ?? '').toString().trim().isEmpty
          ? null
          : (map['notes'] ?? '').toString().trim(),
    );
  }

  final String reps;
  final String? notes;
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draftWorkout,
    required this.onOpenDraft,
    required this.onDelete,
  });

  final Map<String, dynamic> draftWorkout;
  final VoidCallback? onOpenDraft;
  final VoidCallback onDelete;

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: const Text(
          'Черновик и все данные тренировки будут удалены безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final startedAt =
        DateTime.tryParse((draftWorkout['started_at'] ?? '').toString())
                ?.toLocal() ??
            DateTime.now();
    final isToday = DateUtils.isSameDay(startedAt, DateTime.now());
    final exercises = (draftWorkout['exercises'] as List?)?.length ?? 0;
    final details = [
      formatShortDate(startedAt),
      if (exercises > 0) 'упражнений: $exercises',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(draftWorkout['id'] ?? 'draft_new'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: DashboardCard(
        padding: const EdgeInsets.all(16),
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.10),
          scheme.surfaceContainerLow,
        ),
        borderColor: scheme.primary.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isToday ? Icons.timer_outlined : Icons.history_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isToday ? 'ТРЕНИРОВКА ИДЁТ' : 'НЕ ЗАВЕРШЕНА',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    if (await _confirmDelete(context) == true) onDelete();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              (draftWorkout['name'] ?? 'Тренировка').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              details,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onOpenDraft,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              child: Text(isToday ? 'Продолжить' : 'Продолжить и завершить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummary {
  const _TodaySummary({
    required this.weekCount,
    required this.activeDays,
    required this.weeklyTarget,
    this.activeWeekdays = const {},
  });

  const _TodaySummary.empty()
      : weekCount = 0,
        activeDays = 0,
        weeklyTarget = 3,
        activeWeekdays = const {};

  final int weekCount;
  final int activeDays;
  final int weeklyTarget;
  final Set<int> activeWeekdays; // 1=Mon .. 7=Sun
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}
