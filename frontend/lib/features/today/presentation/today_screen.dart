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
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../progression/application/progression_controller.dart';
import '../../wellness/data/wellness_repository.dart';
import '../../wellness/domain/wellness_entry.dart';
import '../../wellness/presentation/wellness_widgets.dart';
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
  _MotivationQuote? _motivationQuote;
  _TodayFocus? _todayFocus;
  _TodaySummary _summary = const _TodaySummary.empty();
  WellnessEntry? _todayWellness;
  _DailyInsight? _dailyInsight;
  int _weeklyTargetFromProfile = _defaultWeeklyTarget;
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
      _loadTodayWellness(),
      _loadDraft(),
      _loadMotivationQuote(),
      _loadFitnessProfile().then((_) => _loadSummary()),
      _loadTodayFocus(),
    ]);
    // Инсайт обновляется в фоне — не блокирует основной экран
    unawaited(_loadDailyInsight());
  }

  /// Загружает брифинг коуча с кэшированием на 6 часов.
  /// При наличии кэша показывает его мгновенно, обновляет в фоне.
  Future<void> _loadDailyInsight() async {
    // 1. Мгновенно показываем кэш если есть
    final cached = LocalCache.get<Map>(CacheKeys.coachDailyInsight);
    if (cached != null) {
      final cachedAt = cached['cached_at'] as int?;
      final headline = cached['headline'] as String?;
      final insight = cached['insight'] as String?;
      if (headline != null && insight != null) {
        if (mounted) {
          setState(() => _dailyInsight = _DailyInsight(
                headline: headline,
                insight: insight,
              ));
        }
        // Кэш актуален если он за сегодня — обновляем только после полуночи
        if (cachedAt != null) {
          final cachedDay = DateTime.fromMillisecondsSinceEpoch(cachedAt);
          final today = DateTime.now();
          final isSameDay = cachedDay.year == today.year &&
              cachedDay.month == today.month &&
              cachedDay.day == today.day;
          if (isSameDay) return;
        }
      }
    }

    // 2. Запрашиваем свежий инсайт
    try {
      final data = await BackendApi.getDailyInsight();
      if (!mounted || data == null) return;
      final headline = (data['headline'] as String?)?.trim() ?? '';
      final insight = (data['insight'] as String?)?.trim() ?? '';
      if (headline.isEmpty && insight.isEmpty) return;
      await LocalCache.put(CacheKeys.coachDailyInsight, {
        'headline': headline,
        'insight': insight,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (mounted) {
        setState(() => _dailyInsight = _DailyInsight(
              headline: headline,
              insight: insight,
            ));
      }
    } catch (_) {
      // Не блокируем экран — инсайт опциональный
    }
  }

  Future<void> _loadTodayWellness() async {
    final entry = WellnessRepository.loadForDate(DateTime.now());
    if (mounted) setState(() => _todayWellness = entry);
    try {
      final syncedEntry = await WellnessRepository.fetchForDate(DateTime.now());
      if (mounted) setState(() => _todayWellness = syncedEntry);
    } catch (_) {
      // Keep the local cache visible when the server is temporarily unavailable.
    }
  }

  List<Map<String, dynamic>> _collectRecentWellnessEntries() {
    final result = <Map<String, dynamic>>[];
    final today = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      final entry = WellnessRepository.loadForDate(date);
      if (entry != null) {
        final map = <String, dynamic>{
          'date':
              DateUtils.dateOnly(entry.date).toIso8601String().substring(0, 10),
          'sleep': entry.sleep,
          'energy': entry.energy,
          'stress': entry.stress,
          'mood': entry.mood,
        };
        if (entry.comment != null) map['comment'] = entry.comment;
        result.add(map);
      }
    }
    return result;
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

  Future<void> _loadTodayFocus() async {
    try {
      final results = await Future.wait([
        _loadWorkoutsForAiCoach().catchError((_) => <Map<String, dynamic>>[]),
        _loadExerciseCatalogForAiCoach()
            .catchError((_) => <Map<String, dynamic>>[]),
        BackendApi.getFitnessProfile().catchError((_) => <String, dynamic>{}),
      ]);

      final workouts = results[0] as List<Map<String, dynamic>>;
      final exerciseCatalog = results[1] as List<Map<String, dynamic>>;
      final profile = results[2] as Map<String, dynamic>;

      final goals =
          ((profile['goals'] as List?)?.cast<String>()) ?? const <String>[];
      final gender = profile['gender'] as String?;

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

      if (!mounted) return;

      if (thisWeek.isEmpty) {
        final lastWeekStart = weekStart.subtract(const Duration(days: 7));
        final lastWeekCount = workouts.where((w) {
          final startedAt =
              DateTime.tryParse((w['started_at'] ?? '').toString())?.toLocal();
          return startedAt != null &&
              !startedAt.isBefore(lastWeekStart) &&
              startedAt.isBefore(weekStart);
        }).length;

        final headline = _goalMotivationHeadline(goals);
        final subtext = lastWeekCount > 0
            ? 'На прошлой неделе: $lastWeekCount ${_workoutsPlural(lastWeekCount)}'
            : null;

        setState(() => _todayFocus = _TodayFocus.startOfWeek(
              motivationHeadline: headline,
              motivationSubtext: subtext,
            ));
        return;
      }

      final tier1 = _buildTier1Muscles(gender: gender, goals: goals);

      final candidateMuscles = <String>{};
      for (final exercise in exerciseCatalog) {
        final primary = (exercise['primary_muscle'] ?? '').toString().trim();
        if (primary.isNotEmpty && !_excludedMuscles.contains(primary)) {
          candidateMuscles.add(primary);
        }
      }

      if (candidateMuscles.isEmpty || !mounted) return;

      final rawLoads = const MuscleLoadCalculator().calculate(
        workouts: thisWeek,
        exerciseCatalog: exerciseCatalog,
      );

      final eligibleMuscles =
          candidateMuscles.where((m) => _muscleTier(m, tier1) <= 3).toList()
            ..sort((a, b) {
              final tA = _muscleTier(a, tier1);
              final tB = _muscleTier(b, tier1);
              if (tA != tB) return tA.compareTo(tB);
              return (rawLoads[a] ?? 0).compareTo(rawLoads[b] ?? 0);
            });

      if (!mounted) return;

      final recommendedLabel =
          _buildRecommendedLabel(eligibleMuscles.take(4).toList());

      setState(() {
        _todayFocus =
            _TodayFocus.recommendation(recommendedLabel: recommendedLabel);
      });
    } catch (_) {}
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
    final weeklyTarget = max(_weeklyTargetFromProfile, thisWeek.length);

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
        wellnessEntries: _collectRecentWellnessEntries(),
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
    final today = DateTime.now();
    final showQuote =
        _motivationQuote != null && !_draftLoading && _draftWorkout == null;
    final height = MediaQuery.sizeOf(context).height;
    final isTall = height >= 760;
    return AppBackdrop(
      child: RefreshIndicator(
        onRefresh: _refreshScreen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final verticalPadding = EdgeInsets.fromLTRB(
              16,
              isTall ? 18 : 12,
              16,
              isTall ? 48 : 96,
            );
            final minContentHeight = max(
              0.0,
              constraints.maxHeight -
                  verticalPadding.top -
                  verticalPadding.bottom,
            );

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: verticalPadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minContentHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TodayHeadline(
                        dateLabel: _todayDateLabel(today),
                        headline: _dailyInsight?.headline.isNotEmpty == true
                            ? _dailyInsight!.headline
                            : (_todayFocus != null &&
                                    !_todayFocus!.isStartState)
                                ? _todayFocus!.recommendedLabel
                                : _todayFocus?.motivationHeadline,
                      ),
                      SizedBox(height: isTall ? 16 : 10),
                      _WorkoutDayCard(
                        focus: _todayFocus,
                        dailyInsight: _dailyInsight,
                        templatesLoading: _templatesLoading,
                        aiCoachLoading: _aiCoachLoading,
                        onStartWorkout: () =>
                            _openWorkout(date: DateTime.now()),
                        onStartTemplate: _startFromTemplate,
                        onStartAiCoach: _startFromAiCoach,
                      ),
                      const SizedBox(height: 10),
                      _WeekSummaryCard(summary: _summary),
                      const SizedBox(height: 10),
                      const _NextGoalCard(),
                      WellnessCard(
                        entry: _todayWellness,
                        date: DateUtils.dateOnly(DateTime.now()),
                        onChanged: () => unawaited(_loadTodayWellness()),
                      ),
                      const SizedBox(height: 10),
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
                          onOpenDraft: () =>
                              _openWorkout(workout: _draftWorkout),
                          onDelete: _deleteDraft,
                        ),
                      if (showQuote) const Spacer(flex: 2) else const Spacer(),
                      if (showQuote) ...[
                        _TodayQuote(
                          quote: _motivationQuote!.quote,
                          author: _motivationQuote!.author,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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

  // ── Мышечные тиры ─────────────────────────────────────────────────────────

  static const Set<String> _excludedMuscles = {
    'предплечья',
    'кор',
    'голень',
  };

  static const Set<String> _tier2Muscles = {
    'трицепс',
    'бицепс',
    'задние_дельты',
    'трапеции',
    'пресс',
  };

  static const Set<String> _tier3Muscles = {'икры'};

  static const Map<String, String> _muscleGroupLabels = {
    'грудь': 'ГРУДЬ',
    'широчайшие': 'СПИНА',
    'трапеции': 'СПИНА',
    'квадрицепсы': 'НОГИ',
    'бицепс_бедра': 'НОГИ',
    'ягодицы': 'НОГИ',
    'икры': 'НОГИ',
    'средние_дельты': 'ПЛЕЧИ',
    'задние_дельты': 'ПЛЕЧИ',
    'передние_дельты': 'ПЛЕЧИ',
    'трицепс': 'РУКИ',
    'бицепс': 'РУКИ',
    'пресс': 'ПРЕСС',
  };

  static Set<String> _buildTier1Muscles({
    String? gender,
    List<String> goals = const [],
  }) {
    final base = <String>{
      'грудь',
      'широчайшие',
      'квадрицепсы',
      'бицепс_бедра',
      'ягодицы',
      'средние_дельты',
    };
    if (gender == 'женский' || goals.contains('похудение')) {
      base.add('пресс');
    }
    return base;
  }

  static int _muscleTier(String muscle, Set<String> tier1) {
    if (tier1.contains(muscle)) return 1;
    if (_tier2Muscles.contains(muscle)) return 2;
    if (_tier3Muscles.contains(muscle)) return 3;
    return 99;
  }

  static String _buildRecommendedLabel(List<String> muscles) {
    final groups = <String>[];
    final seen = <String>{};
    for (final muscle in muscles) {
      final group = _muscleGroupLabels[muscle];
      if (group != null && seen.add(group)) {
        groups.add(group);
        if (groups.length == 2) break;
      }
    }
    return groups.isEmpty ? 'ТРЕНИРОВКА' : groups.join(' И ');
  }

  // ── Мотивация для старта недели ───────────────────────────────────────────

  static String _goalMotivationHeadline(List<String> goals) {
    if (goals.contains('масса')) return 'ВРЕМЯ РАСТИ';
    if (goals.contains('сила')) return 'НЕДЕЛЯ СИЛЫ';
    if (goals.contains('похудение')) return 'ДВИГАЙСЯ';
    if (goals.contains('поддержание')) return 'ДЕРЖИ РИТМ';
    return 'НАЧНИ НЕДЕЛЮ';
  }

  static String _workoutsPlural(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'тренировка';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'тренировки';
    }
    return 'тренировок';
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
  const _TodayHeadline({required this.dateLabel, required this.headline});

  final String dateLabel;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          headline ?? 'ТРЕНИРОВКА',
          style: TextStyle(
            fontFamily: 'Bebas Neue Cyrillic',
            fontSize: 44,
            height: 1.0,
            letterSpacing: 0.5,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _WorkoutDayCard extends StatelessWidget {
  const _WorkoutDayCard({
    required this.focus,
    required this.dailyInsight,
    required this.templatesLoading,
    required this.aiCoachLoading,
    required this.onStartWorkout,
    required this.onStartTemplate,
    required this.onStartAiCoach,
  });

  final _TodayFocus? focus;
  final _DailyInsight? dailyInsight;
  final bool templatesLoading;
  final bool aiCoachLoading;
  final VoidCallback onStartWorkout;
  final VoidCallback onStartTemplate;
  final VoidCallback onStartAiCoach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final text = dailyInsight?.insight.isNotEmpty == true
        ? dailyInsight!.insight
        : (focus?.isStartState == true ? focus?.motivationSubtext : null);

    return DashboardCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (text != null && text.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 16, color: scheme.secondary),
                const SizedBox(width: 6),
                Text(
                  dailyInsight != null ? 'AI-КОУЧ' : 'РЕКОМЕНДУЕМ',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onStartWorkout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 54),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Начать тренировку', maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _IconActionButton(
                icon: templatesLoading ? null : Icons.library_books_outlined,
                loading: templatesLoading,
                tooltip: 'Из шаблона',
                onTap: templatesLoading ? null : onStartTemplate,
              ),
              const SizedBox(width: 10),
              _IconActionButton(
                icon: aiCoachLoading ? null : Icons.auto_awesome_outlined,
                loading: aiCoachLoading,
                tooltip: 'Собрать с AI',
                onTap: aiCoachLoading ? null : onStartAiCoach,
              ),
            ],
          ),
        ],
      ),
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

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.loading = false,
  });

  final IconData? icon;
  final bool loading;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.secondary),
                  )
                : Icon(icon, size: 20, color: scheme.secondary),
          ),
        ),
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
      quote: _trimQuoteEnding(line.substring(0, separator).trim()),
      author: line.substring(separator + 3).trim(),
    );
  }

  static String _trimQuoteEnding(String value) {
    return value.replaceFirst(RegExp(r'[\s.…。]+$'), '');
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

class _TodayFocus {
  const _TodayFocus.startOfWeek({
    required this.motivationHeadline,
    this.motivationSubtext,
  }) : recommendedLabel = null;

  const _TodayFocus.recommendation({required String this.recommendedLabel})
      : motivationHeadline = null,
        motivationSubtext = null;

  final String? recommendedLabel;
  final String? motivationHeadline;
  final String? motivationSubtext;

  bool get isStartState => recommendedLabel == null;
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
    final isNarrow = MediaQuery.sizeOf(context).width < 380;

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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«$quote»',
                    style:
                        (isNarrow ? textTheme.bodyMedium : textTheme.bodyLarge)
                            ?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                      height: 1.28,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
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

class _DailyInsight {
  const _DailyInsight({required this.headline, required this.insight});
  final String headline;
  final String insight;
}

String _normalizeExerciseLookupName(String value) {
  return value.trim().toLowerCase().replaceAll('ё', 'е');
}
