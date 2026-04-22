import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../workouts/presentation/workout_form_screen.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  static const int _defaultWeeklyTarget = 3;

  Map<String, dynamic>? _draftWorkout;
  _MotivationQuote? _motivationQuote;
  _TodaySummary _summary = const _TodaySummary.empty();
  bool _draftLoading = true;
  bool _templatesLoading = false;
  bool _aiCoachLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshScreen();
  }

  Future<void> _refreshScreen() async {
    await Future.wait([
      _loadDraft(),
      _loadMotivationQuote(),
      _loadSummary(),
    ]);
  }

  Future<void> _loadMotivationQuote() async {
    try {
      final rawQuotes =
          await rootBundle.loadString('assets/content/motivational_quotes.txt');
      final parsedQuotes = rawQuotes
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map(_MotivationQuote.tryParse)
          .whereType<_MotivationQuote>()
          .toList();
      if (!mounted || parsedQuotes.isEmpty) {
        return;
      }

      final random = Random();
      setState(() {
        _motivationQuote = parsedQuotes[random.nextInt(parsedQuotes.length)];
      });
    } catch (_) {}
  }

  Future<void> _loadSummary() async {
    List<Map<String, dynamic>> workouts =
        LocalCache.get<List>(CacheKeys.workoutsCache)
                ?.cast<Map>()
                .map((entry) => entry.cast<String, dynamic>())
                .toList() ??
            const [];

    if (workouts.isEmpty) {
      try {
        workouts = await BackendApi.getWorkouts();
      } catch (_) {}
    }

    final now = DateTime.now();
    final weekStart = DateUtils.dateOnly(
      now.subtract(Duration(days: now.weekday - 1)),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));

    final thisWeek = workouts.where((workout) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      return startedAt != null &&
          !startedAt.isBefore(weekStart) &&
          startedAt.isBefore(weekEnd);
    }).toList();

    final activeDateSet = <DateTime>{};
    final activeWeekdaySet = <int>{};
    for (final workout in thisWeek) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      if (startedAt != null) {
        activeDateSet.add(DateUtils.dateOnly(startedAt));
        activeWeekdaySet.add(startedAt.weekday);
      }
    }

    final activeDays = activeDateSet.length;
    final weeklyTarget = max(_defaultWeeklyTarget, thisWeek.length);

    if (!mounted) {
      return;
    }

    setState(() {
      _summary = _TodaySummary(
        weekCount: thisWeek.length,
        activeDays: activeDays,
        weeklyTarget: weeklyTarget,
        activeWeekdays: activeWeekdaySet,
      );
    });
  }

  Future<void> _loadDraft() async {
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

    // Fallback: ищем незавершённую тренировку в кэше/API,
    // если локальный черновик не нашли
    draftWorkout ??= await _findUnfinishedWorkout();

    draftWorkout = await _pruneOrphanedDraft(
      draftWorkout: draftWorkout,
      activeDraftKey: activeDraftKey,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _draftWorkout = draftWorkout;
      _draftLoading = false;
    });
  }

  Future<Map<String, dynamic>?> _findUnfinishedWorkout() async {
    try {
      // Всегда берём свежие данные с сервера, чтобы не показывать черновик
      // уже завершённой тренировки из устаревшего кэша.
      final workouts = await BackendApi.getWorkouts();
      // Берём самую свежую незавершённую тренировку
      final unfinished =
          workouts.where((w) => w['finished_at'] == null).toList();
      if (unfinished.isEmpty) return null;
      return unfinished.last;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _pruneOrphanedDraft({
    required Map<String, dynamic>? draftWorkout,
    required String? activeDraftKey,
  }) async {
    if (draftWorkout == null || activeDraftKey == null) {
      return draftWorkout;
    }

    final draftWorkoutId = draftWorkout['id'] as int?;
    if (draftWorkoutId == null) {
      return draftWorkout;
    }

    var knownWorkouts = LocalCache.get<List>(CacheKeys.workoutsCache)
            ?.cast<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    var exists = knownWorkouts.any((item) => item['id'] == draftWorkoutId);

    if (!exists) {
      // Кэш может быть устаревшим (например, тренировка только что создана).
      // Всегда перепроверяем через API, прежде чем удалять черновик.
      try {
        knownWorkouts = await BackendApi.getWorkouts();
        exists = knownWorkouts.any((item) => item['id'] == draftWorkoutId);
      } catch (_) {
        return draftWorkout;
      }
    }

    if (exists) {
      return draftWorkout;
    }

    await LocalCache.remove(activeDraftKey);
    await LocalCache.remove(CacheKeys.activeWorkoutDraft);
    return null;
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

      final workouts = await BackendApi.getWorkouts();
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

    final result = await showModalBottomSheet<({_AiCoachIntensity intensity, String notes})>(
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
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
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
                      hintText: 'Например: хочу больше ног, устал — сделай легче...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      counterStyle: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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

      await _openWorkout(
        date: DateTime.now(),
        name: plan.name,
        exercises: initialExercises,
      );
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

  Future<List<Map<String, dynamic>>> _loadWorkoutsForAiCoach() async {
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
    final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
    if (cached != null) {
      return cached
          .cast<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
    }
    return BackendApi.getExercises();
  }

  String _buildAiCoachWorkoutPrompt(
    _AiCoachIntensity intensity,
    List<Map<String, dynamic>> workouts,
  ) {
    final recentWorkoutSummary = _buildRecentWorkoutSummary(workouts);
    return [
      'ОБЯЗАТЕЛЬНО учитывай последние тренировки, недавнюю нагрузку и восстановление.',
      'Не повторяй один в один упражнения и структуру последней и предпоследней тренировки, если только это не необходимо по логике программы.',
      'Если какая-то группа мышц или движение были сильно нагружены в последних 1-2 тренировках, снизь повторение этой нагрузки или смести акцент.',
      if (recentWorkoutSummary.isNotEmpty)
        'Последние тренировки: $recentWorkoutSummary.',
      'Составь тренировку от AI-коуча на сегодня.',
      'Используй историю моих прошлых тренировок и доступные мне упражнения.',
      'Интенсивность: ${intensity.title}.',
      'Нужно ${intensity.rangeLabel} упражнений.',
      'Верни только JSON без markdown и без пояснений вне JSON.',
      'Для тяжёлых базовых упражнений добавляй подводящие подходы в отдельном поле warmup_sets.',
      'Формат ответа:',
      '{"name":"Название тренировки","exercises":[{"exercise_name":"Жим лёжа","sets":4,"reps":"6-8","notes":"короткая подсказка","warmup_sets":[{"reps":"10","notes":"лёгкий разминочный"},{"reps":"6","notes":"подводящий"},{"reps":"3","notes":"выход на рабочий вес"}]}]}',
      'Поле name обязательно.',
      'В exercises должно быть только ${intensity.minExercises}-${intensity.maxExercises} упражнений.',
      'exercise_name должен быть строкой.',
      'sets должен быть целым числом от 1 до 6.',
      'reps должен быть строкой, например "6-8", "8-10" или "12".',
      'warmup_sets можно добавлять только там, где они реально нужны.',
      'В warmup_sets не указывай рабочие подходы, только подводящие.',
      'notes можно оставить пустым.',
    ].join(' ');
  }

  String _buildRecentWorkoutSummary(List<Map<String, dynamic>> workouts) {
    if (workouts.isEmpty) {
      return '';
    }

    final sorted = [...workouts]..sort((a, b) {
        final aDate = DateTime.tryParse((a['started_at'] ?? '').toString()) ??
            DateTime(1970);
        final bDate = DateTime.tryParse((b['started_at'] ?? '').toString()) ??
            DateTime(1970);
        return bDate.compareTo(aDate);
      });

    final recent = sorted.take(3).map((workout) {
      final startedAt =
          DateTime.tryParse((workout['started_at'] ?? '').toString())
              ?.toLocal();
      final name = (workout['name'] ?? 'Тренировка').toString().trim();
      final exerciseNames =
          ((workout['exercises'] as List?)?.cast<dynamic>() ?? const [])
              .whereType<Map>()
              .map((item) => (item['exercise_name'] ?? '').toString().trim())
              .where((name) => name.isNotEmpty)
              .take(6)
              .toList();
      final dateLabel = startedAt == null
          ? ''
          : '${startedAt.day.toString().padLeft(2, '0')}.${startedAt.month.toString().padLeft(2, '0')}';
      final exercisesLabel =
          exerciseNames.isEmpty ? 'без упражнений' : exerciseNames.join(', ');
      return '$dateLabel $name: $exercisesLabel';
    }).toList();

    return recent.join(' | ');
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
    return AppBackdrop(
      child: RefreshIndicator(
        onRefresh: _refreshScreen,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            _WeekSummaryCard(summary: _summary),
            const SizedBox(height: 14),
            _PrimaryWorkoutCard(
              templatesLoading: _templatesLoading,
              aiCoachLoading: _aiCoachLoading,
              onStartWorkout: () => _openWorkout(date: DateTime.now()),
              onStartTemplate: _startFromTemplate,
              onStartAiCoach: _startFromAiCoach,
            ),
            const SizedBox(height: 12),
            if (_draftLoading)
              const DashboardCard(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_draftWorkout != null)
              _DraftCard(
                draftWorkout: _draftWorkout!,
                onOpenDraft: () => _openWorkout(workout: _draftWorkout),
                onDelete: _deleteDraft,
              ),
            if (_motivationQuote != null) ...[
              const SizedBox(height: 28),
              _TodayQuote(
                quote: _motivationQuote!.quote,
                author: _motivationQuote!.author,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeekSummaryCard extends StatelessWidget {
  const _WeekSummaryCard({required this.summary});

  final _TodaySummary summary;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now().weekday; // 1=Mon

    return DashboardCard(
      color: Color.alphaBlend(
        scheme.secondary.withValues(alpha: 0.08),
        scheme.surfaceContainerLow,
      ),
      borderColor: scheme.outlineVariant.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Эта неделя',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _workoutCountLabel(summary.weekCount),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                                color: _workoutCountColor(summary.weekCount,
                                    summary.weeklyTarget, scheme),
                              ),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: '🔥 ${summary.activeDays}',
                color: summary.weekCount >= summary.weeklyTarget
                    ? scheme.tertiary
                    : scheme.primary,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(7, (index) {
              final weekday = index + 1;
              final isActive = summary.activeWeekdays.contains(weekday);
              final isToday = weekday == today;
              final isPast = weekday < today;

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _dayLabels[index],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isToday
                                ? scheme.secondary
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                            fontWeight:
                                isToday ? FontWeight.w800 : FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: isActive ? 32 : 28,
                      height: isActive ? 32 : 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? scheme.secondary
                            : isToday
                                ? scheme.secondary.withValues(alpha: 0.15)
                                : isPast
                                    ? scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.4)
                                    : Colors.transparent,
                        border: isToday && !isActive
                            ? Border.all(
                                color: scheme.secondary.withValues(alpha: 0.5),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Center(
                        child: isActive
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: scheme.onSecondary,
                              )
                            : null,
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

  static String _workoutCountLabel(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '$count тренировка';
    if (count % 10 >= 2 &&
        count % 10 <= 4 &&
        (count % 100 < 10 || count % 100 >= 20)) {
      return '$count тренировки';
    }
    return '$count тренировок';
  }

  static Color _workoutCountColor(int count, int target, ColorScheme scheme) {
    if (count == 0) return scheme.onSurfaceVariant;
    if (count >= target) return scheme.tertiary;
    return scheme.primary;
  }
}

class _PrimaryWorkoutCard extends StatelessWidget {
  const _PrimaryWorkoutCard({
    required this.templatesLoading,
    required this.aiCoachLoading,
    required this.onStartWorkout,
    required this.onStartTemplate,
    required this.onStartAiCoach,
  });

  final bool templatesLoading;
  final bool aiCoachLoading;
  final VoidCallback onStartWorkout;
  final VoidCallback onStartTemplate;
  final VoidCallback onStartAiCoach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 720;
    final isCompact = screenWidth < 420;
    final useStackedActions = screenWidth < 520;

    return DashboardCard(
      color: Color.alphaBlend(
        scheme.secondary.withValues(alpha: 0.06),
        scheme.surfaceContainerLow,
      ),
      borderColor: scheme.secondary.withValues(alpha: 0.18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.add, color: scheme.secondary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\u041d\u043e\u0432\u0430\u044f \u0442\u0440\u0435\u043d\u0438\u0440\u043e\u0432\u043a\u0430',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '\u0411\u044b\u0441\u0442\u0440\u044b\u0439 \u0441\u0442\u0430\u0440\u0442 \u0432\u0440\u0443\u0447\u043d\u0443\u044e, \u043f\u043e \u0448\u0430\u0431\u043b\u043e\u043d\u0443 \u0438\u043b\u0438 \u043e\u0442 AI-\u043a\u043e\u0443\u0447\u0430.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 14),
                isWide
                    ? Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton(
                            onPressed: onStartWorkout,
                            child: const Text(
                              '\u041d\u0430\u0447\u0430\u0442\u044c \u0442\u0440\u0435\u043d\u0438\u0440\u043e\u0432\u043a\u0443',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                templatesLoading ? null : onStartTemplate,
                            icon: templatesLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.library_books_outlined),
                            label: const Text(
                              '\u0418\u0437 \u0448\u0430\u0431\u043b\u043e\u043d\u0430',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: aiCoachLoading ? null : onStartAiCoach,
                            icon: aiCoachLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome_outlined),
                            label: const Text('От AI-коуча'),
                          ),
                        ],
                      )
                    : useStackedActions
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton(
                                onPressed: onStartWorkout,
                                child: const Text(
                                  '\u041d\u0430\u0447\u0430\u0442\u044c \u0442\u0440\u0435\u043d\u0438\u0440\u043e\u0432\u043a\u0443',
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed:
                                    templatesLoading ? null : onStartTemplate,
                                icon: templatesLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.library_books_outlined),
                                label: const Text(
                                  '\u0418\u0437 \u0448\u0430\u0431\u043b\u043e\u043d\u0430',
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed:
                                    aiCoachLoading ? null : onStartAiCoach,
                                icon: aiCoachLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.auto_awesome_outlined,
                                      ),
                                label: const Text('От AI-коуча'),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                flex: isCompact ? 6 : 5,
                                child: FilledButton(
                                  onPressed: onStartWorkout,
                                  child: const Text(
                                    '\u041d\u0430\u0447\u0430\u0442\u044c \u0442\u0440\u0435\u043d\u0438\u0440\u043e\u0432\u043a\u0443',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: isCompact ? 5 : 3,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      templatesLoading ? null : onStartTemplate,
                                  icon: templatesLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.library_books_outlined),
                                  label: const Text(
                                    '\u0418\u0437 \u0448\u0430\u0431\u043b\u043e\u043d\u0430',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: isCompact ? 5 : 4,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      aiCoachLoading ? null : onStartAiCoach,
                                  icon: aiCoachLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.auto_awesome_outlined,
                                        ),
                                  label: const Text(
                                    'От AI-коуча',
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
              ],
            ),
          ),
        ],
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Dismissible(
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
                Icon(Icons.delete_outline, color: scheme.onErrorContainer),
              ],
            ),
          ),
          child: DashboardCard(
            color: Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.07),
              scheme.surfaceContainerLow,
            ),
            borderColor: scheme.primary.withValues(alpha: 0.22),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ЧЕРНОВИК',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.primary.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (draftWorkout['name'] ?? 'Тренировка').toString(),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatShortDate(
                          DateTime.tryParse(
                                (draftWorkout['started_at'] ?? '').toString(),
                              )?.toLocal() ??
                              DateTime.now(),
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onOpenDraft,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    foregroundColor: scheme.primary,
                  ),
                  child: const Text('Продолжить'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              Icons.swipe_left_outlined,
              size: 13,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            Text(
              'Смахните влево, чтобы удалить',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MotivationQuote {
  const _MotivationQuote({
    required this.quote,
    required this.author,
  });

  final String quote;
  final String author;

  static _MotivationQuote? tryParse(String line) {
    final separator = line.lastIndexOf(' — ');
    if (separator <= 0 || separator >= line.length - 3) {
      return null;
    }

    return _MotivationQuote(
      quote: line.substring(0, separator).trim(),
      author: line.substring(separator + 3).trim(),
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

class _TodayQuote extends StatelessWidget {
  const _TodayQuote({
    required this.quote,
    required this.author,
  });

  final String quote;
  final String author;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            color: scheme.primary,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«$quote»',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      height: 1.45,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '— $author',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}
