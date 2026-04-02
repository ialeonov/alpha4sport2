import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/muscle_heatmap_card.dart';
import '../../progression/application/progression_controller.dart';
import '../../workouts/application/workout_export_service.dart';
import '../../workouts/application/workout_share_service.dart';
import '../../workouts/domain/workout_metrics.dart';
import '../../workouts/presentation/workout_form_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _calendarCellHeight = 62.0;
  static const _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _monthLabels = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const _monthGenitive = [
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

  late Future<List<Map<String, dynamic>>> _future;
  late Future<List<Map<String, dynamic>>> _catalogFuture;
  late DateTime _displayedMonth;
  late DateTime _selectedDay;
  final WorkoutExportService _workoutExportService =
      const WorkoutExportService();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
    _selectedDay = DateUtils.dateOnly(now);
    _future = _loadWorkouts();
    _catalogFuture = _loadExerciseCatalog();
  }

  Future<List<Map<String, dynamic>>> _loadWorkouts() async {
    try {
      return await BackendApi.getWorkouts();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadTemplates() =>
      _workoutExportService.loadTemplates();

  Future<void> _refresh() async {
    setState(() {
      _future = _loadWorkouts();
      _catalogFuture = _loadExerciseCatalog();
    });
    await Future.wait([_future, _catalogFuture]);
  }

  Future<List<Map<String, dynamic>>> _loadExerciseCatalog() async {
    try {
      return await BackendApi.getExercises();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      return const [];
    }
  }

  Future<void> _openCreateWorkout() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormScreen(initialDate: _selectedDay),
      ),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _openAddWorkoutOptions() async {
    final action = await showModalBottomSheet<_CalendarCreateAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Вручную'),
                subtitle: const Text(
                  'Пустая тренировка с ручным добавлением упражнений.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_CalendarCreateAction.manual),
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('Из шаблона'),
                subtitle: const Text(
                  'Подставить упражнения и, если есть, ваши прошлые подходы.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_CalendarCreateAction.template),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Из JSON файла'),
                subtitle: const Text(
                  'Загрузить тренировку из того же JSON, который приложение экспортирует.',
                ),
                onTap: () =>
                    Navigator.of(context).pop(_CalendarCreateAction.json),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == _CalendarCreateAction.manual) {
      await _openCreateWorkout();
      return;
    }
    if (action == _CalendarCreateAction.template) {
      await _openCreateFromTemplate();
      return;
    }
    if (action == _CalendarCreateAction.json) {
      await _openCreateFromJson();
    }
  }

  Future<void> _openCreateFromTemplate() async {
    try {
      final templates = await _loadTemplates();
      if (!mounted) return;
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
              height: MediaQuery.of(context).size.height * 0.72,
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

      if (selectedTemplate == null || !mounted) return;

      final workouts = await _future;
      if (!mounted) return;

      final initialExercises =
          _buildExercisesFromTemplate(selectedTemplate, workouts);

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WorkoutFormScreen(
            initialDate: _selectedDay,
            initialName: (selectedTemplate['name'] ?? 'Тренировка').toString(),
            initialExercises: initialExercises,
          ),
        ),
      );

      if (changed == true) {
        await _refresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось загрузить шаблоны.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openCreateFromJson() async {
    try {
      final exerciseCatalog = await _loadExerciseCatalog();
      if (!mounted) return;

      final importedWorkouts = await _workoutExportService.pickImportWorkouts(
        exerciseCatalog: exerciseCatalog,
      );
      if (!mounted || importedWorkouts.isEmpty) return;

      final selectedWorkout = importedWorkouts.length == 1
          ? importedWorkouts.first
          : await showModalBottomSheet<ImportedWorkoutDraft>(
              context: context,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выберите тренировку из файла',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.separated(
                            itemCount: importedWorkouts.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final workout = importedWorkouts[index];
                              return ListTile(
                                leading: const Icon(Icons.upload_file_outlined),
                                title: Text(workout.name),
                                subtitle: Text(
                                  '${workout.sourceLabel} · упражнений: ${workout.exercises.length}',
                                ),
                                onTap: () => Navigator.of(context).pop(workout),
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

      if (selectedWorkout == null || !mounted) return;

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WorkoutFormScreen(
            initialDate: _selectedDay,
            initialName: selectedWorkout.name,
            initialExercises: selectedWorkout.exercises,
          ),
        ),
      );

      if (changed == true) {
        await _refresh();
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось загрузить тренировку из JSON.',
            ),
          ),
        ),
      );
    }
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

      prepared.add({
        'catalog_exercise_id': templateExercise['catalog_exercise_id'],
        'exercise_name': (templateExercise['exercise_name'] ?? '').toString(),
        'position': index + 1,
        'notes': null,
        'sets': lastSets.isEmpty
            ? [
                {
                  'position': 1,
                  'reps': '',
                  'weight': null,
                  'rpe': null,
                  'notes': null,
                },
              ]
            : List.generate(lastSets.length, (setIndex) {
                final set = (lastSets[setIndex] as Map).cast<String, dynamic>();
                return {
                  'position': setIndex + 1,
                  'reps': set['reps'] ?? '',
                  'weight': set['weight'],
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
        final aDate = _parseWorkoutDay(a) ?? DateTime(1970);
        final bDate = _parseWorkoutDay(b) ?? DateTime(1970);
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

  Future<void> _shareWorkout(
    Map<String, dynamic> workout,
    List<Map<String, dynamic>> catalog,
  ) async {
    await WorkoutShareService.share(
      context: context,
      workout: workout,
      exerciseCatalog: catalog,
    );
  }

  Future<void> _openEditWorkout(Map<String, dynamic> workout) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutFormScreen(initialWorkout: workout),
      ),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  Future<void> _exportSelectedDayWorkouts(
    List<Map<String, dynamic>> workouts,
  ) async {
    if (workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('На выбранный день нет тренировок для экспорта.'),
        ),
      );
      return;
    }

    try {
      final exerciseCatalog = await _workoutExportService.loadExerciseCatalog();
      final templates = await _workoutExportService.loadTemplates();
      final exportData = _workoutExportService.buildExport(
        workouts: workouts,
        rangeFrom: _selectedDay,
        rangeTo: _selectedDay,
        exerciseCatalog: exerciseCatalog,
        templates: templates,
      );
      final saved = await _workoutExportService.saveExportJson(
        exportData: exportData,
        suggestedFileName: 'workout_${formatExportFileDate(_selectedDay)}.json',
      );
      if (!mounted || !saved) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Экспорт тренировки сохранён.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось экспортировать тренировку.',
            ),
          ),
        ),
      );
    }
  }

  Future<DateTimeRange?> _showExportPresets(
    DateTime today,
    DateTime? firstWorkoutDate,
  ) {
    final presets = <(String, DateTimeRange)>[
      (
        'Последние 14 дней',
        DateTimeRange(
            start: today.subtract(const Duration(days: 13)), end: today),
      ),
      (
        'Последние 30 дней',
        DateTimeRange(
            start: today.subtract(const Duration(days: 29)), end: today),
      ),
      (
        'Последние 3 месяца',
        DateTimeRange(
            start: DateTime(today.year, today.month - 2, today.day), end: today),
      ),
      (
        'Этот год',
        DateTimeRange(start: DateTime(today.year, 1, 1), end: today),
      ),
      if (firstWorkoutDate != null)
        (
          'Весь период',
          DateTimeRange(start: firstWorkoutDate, end: today),
        ),
    ];

    // Sentinel: start.year == 0 → open manual date picker
    final manualSentinel =
        DateTimeRange(start: DateTime(0), end: DateTime(0));

    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Экспорт диапазона',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите период для выгрузки тренировок в JSON',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ...presets.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(p.$1),
                  onTap: () => Navigator.of(ctx).pop(p.$2),
                ),
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Выбрать точный диапазон'),
                subtitle: const Text('Указать даты начала и конца вручную'),
                onTap: () => Navigator.of(ctx).pop(manualSentinel),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportWorkoutRange(List<Map<String, dynamic>> workouts) async {
    if (workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет тренировок для экспорта.')),
      );
      return;
    }

    final today = DateUtils.dateOnly(DateTime.now());
    DateTime? firstWorkoutDate;
    for (final w in workouts) {
      final d = _parseWorkoutDay(w);
      if (d != null &&
          (firstWorkoutDate == null || d.isBefore(firstWorkoutDate))) {
        firstWorkoutDate = d;
      }
    }

    DateTimeRange? pickedRange =
        await _showExportPresets(today, firstWorkoutDate);
    if (!mounted || pickedRange == null) return;

    // Sentinel → open manual date picker with wide range
    if (pickedRange.start.year == 0) {
      pickedRange = await showDateRangePicker(
        context: context,
        firstDate: DateTime(today.year - 3),
        lastDate: today,
        initialDateRange: DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        ),
        locale: const Locale('ru'),
      );
      if (!mounted || pickedRange == null) return;
    }

    final selectedWorkouts = _workoutExportService.filterWorkoutsByDateRange(
      workouts: workouts,
      from: pickedRange.start,
      to: pickedRange.end,
    );
    if (selectedWorkouts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('В выбранном диапазоне нет тренировок для экспорта.'),
        ),
      );
      return;
    }

    try {
      final exerciseCatalog =
          await _workoutExportService.loadExerciseCatalog();
      final templates = await _workoutExportService.loadTemplates();
      final exportData = _workoutExportService.buildExport(
        workouts: selectedWorkouts,
        rangeFrom: pickedRange.start,
        rangeTo: pickedRange.end,
        exerciseCatalog: exerciseCatalog,
        templates: templates,
      );
      final saved = await _workoutExportService.saveExportJson(
        exportData: exportData,
        suggestedFileName:
            'workouts_${formatExportFileDate(pickedRange.start)}__${formatExportFileDate(pickedRange.end)}.json',
      );
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Экспорт диапазона сохранён.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось экспортировать диапазон тренировок.',
            ),
          ),
        ),
      );
    }
  }

  void _showWeekHeatmap(
    DateTime weekStart,
    DateTime weekEnd,
    List<Map<String, dynamic>> allWorkouts,
    List<Map<String, dynamic>> exerciseCatalog,
  ) {
    final weekWorkouts = allWorkouts.where((w) {
      final d = _parseWorkoutDay(w);
      return d != null && !d.isBefore(weekStart) && !d.isAfter(weekEnd);
    }).toList();

    final calculator = const MuscleLoadCalculator();
    final rawLoads = calculator.calculateForWorkouts(
      workouts: weekWorkouts,
      exerciseCatalog: exerciseCatalog,
    );
    final normalizedLoads = calculator.normalizer.normalize(rawLoads);

    final weekLabel =
        '${weekStart.day}–${weekEnd.day} ${_monthGenitive[weekStart.month - 1]}';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Неделя $weekLabel',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                weekWorkouts.isEmpty
                    ? 'Тренировок нет'
                    : 'Тренировок: ${weekWorkouts.length}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              MuscleHeatmapCard(
                title: '',
                subtitle: '',
                rawLoads: rawLoads,
                normalizedLoads: normalizedLoads,
                showCard: false,
                showHeader: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWorkout(Map<String, dynamic> workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: Text(
          'Тренировка "${(workout['name'] ?? 'Тренировка').toString()}" будет удалена без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final workoutId = workout['id'] as int;
      await BackendApi.deleteWorkout(workoutId);
      await LocalCache.remove('workout_draft_$workoutId');
      final activeDraft = LocalCache.get<String>(CacheKeys.activeWorkoutDraft);
      if (activeDraft == 'workout_draft_$workoutId') {
        await LocalCache.remove(CacheKeys.activeWorkoutDraft);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тренировка удалена.')),
      );
      await ProgressionController.instance.refresh();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
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

  void _changeMonth(int delta) {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + delta);
    });
  }

  DateTime? _parseWorkoutDay(Map<String, dynamic> workout) {
    final startedAt = workout['started_at']?.toString();
    if (startedAt == null) return null;
    final parsed = DateTime.tryParse(startedAt);
    if (parsed == null) return null;
    return DateUtils.dateOnly(parsed.toLocal());
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupByDay(
    List<Map<String, dynamic>> workouts,
  ) {
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final workout in workouts) {
      final day = _parseWorkoutDay(workout);
      if (day == null) continue;
      byDay.putIfAbsent(day, () => []).add(workout);
    }
    return byDay;
  }

  int _workoutsInDisplayedMonth(
      Map<DateTime, List<Map<String, dynamic>>> byDay) {
    return byDay.entries
        .where(
          (entry) =>
              entry.key.year == _displayedMonth.year &&
              entry.key.month == _displayedMonth.month,
        )
        .fold(0, (sum, entry) => sum + entry.value.length);
  }

  List<Widget> _buildWeekRows(
    Map<DateTime, List<Map<String, dynamic>>> byDay,
    double cellHeight,
    bool compact,
    List<Map<String, dynamic>> allWorkouts,
    List<Map<String, dynamic>> exerciseCatalog,
  ) {
    final first = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingEmpty = first.weekday - 1;
    final scheme = Theme.of(context).colorScheme;
    final buttonWidth = compact ? 28.0 : 36.0;

    final cellDates = <DateTime?>[];
    final cellWidgets = <Widget>[];

    for (var i = 0; i < leadingEmpty; i++) {
      cellDates.add(null);
      cellWidgets.add(SizedBox(height: cellHeight));
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
      final dayWorkouts = byDay[date] ?? const <Map<String, dynamic>>[];
      final hasWorkouts = dayWorkouts.isNotEmpty;
      final isSelected = DateUtils.isSameDay(date, _selectedDay);
      final isToday = DateUtils.isSameDay(date, DateTime.now());
      final dotCount = dayWorkouts.length.clamp(1, 3);

      cellDates.add(date);
      cellWidgets.add(
        InkWell(
          onTap: () => setState(() => _selectedDay = date),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: cellHeight,
            margin: EdgeInsets.all(compact ? 1.5 : 2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
              color: isSelected
                  ? scheme.primary
                  : hasWorkouts
                      ? scheme.primaryContainer.withValues(
                          alpha: scheme.brightness == Brightness.dark
                              ? 0.22
                              : 0.60,
                        )
                      : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isToday && !isSelected
                        ? Border.all(color: scheme.tertiary, width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: compact ? 12 : 13,
                            color: isSelected
                                ? scheme.onPrimary
                                : isToday
                                    ? scheme.tertiary
                                    : null,
                            fontWeight: isToday || isSelected
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 3 : 4),
                if (hasWorkouts)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      dotCount,
                      (_) => Container(
                        width: compact ? 4 : 5,
                        height: compact ? 4 : 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? scheme.onPrimary.withValues(alpha: 0.85)
                              : scheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(height: compact ? 4 : 5),
              ],
            ),
          ),
        ),
      );
    }

    while (cellDates.length % 7 != 0) {
      cellDates.add(null);
      cellWidgets.add(SizedBox(height: cellHeight));
    }

    final rows = <Widget>[];
    for (var i = 0; i < cellWidgets.length; i += 7) {
      final weekCells = cellWidgets.sublist(i, i + 7);
      final weekDates = cellDates.sublist(i, i + 7);

      DateTime? weekStart;
      for (final d in weekDates) {
        if (d != null) {
          weekStart = d.subtract(Duration(days: d.weekday - 1));
          break;
        }
      }
      final weekEnd = weekStart?.add(const Duration(days: 6));

      rows.add(Row(
        children: [
          ...weekCells.map((cell) => Expanded(child: cell)),
          SizedBox(
            width: buttonWidth,
            height: cellHeight,
            child: weekStart != null && exerciseCatalog.isNotEmpty
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: buttonWidth,
                      minHeight: cellHeight,
                    ),
                    iconSize: compact ? 14 : 16,
                    icon: Icon(
                      Icons.accessibility_new_rounded,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    onPressed: () => _showWeekHeatmap(
                      weekStart!,
                      weekEnd!,
                      allWorkouts,
                      exerciseCatalog,
                    ),
                  )
                : null,
          ),
        ],
      ));
    }
    return rows;
  }

  String _selectedDayLabel() {
    final month = _monthGenitive[_selectedDay.month - 1];
    return '${_selectedDay.day} $month ${_selectedDay.year}';
  }

  String _workoutSubtitle(Map<String, dynamic> workout) {
    final exercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final tonnage = formatTonnage(calculateWorkoutTonnage(workout));
    if (exercises.isEmpty) {
      return 'Тоннаж: $tonnage';
    }
    final names = exercises
        .take(3)
        .map(
            (exercise) => ((exercise as Map)['exercise_name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
    final suffix = exercises.length > 3 ? ' +' : '';
    return '${names.join(', ')}$suffix • тоннаж: $tonnage';
  }

  String _workoutTonnageLabel(Map<String, dynamic> workout) {
    return 'Тоннаж: ${formatTonnage(calculateWorkoutTonnage(workout))}';
  }

  Widget _buildWorkoutHeatmapPreview(BuildContext context,
      Map<String, dynamic> workout, List<Map<String, dynamic>> exerciseCatalog,
      {double? width}) {
    if (exerciseCatalog.isEmpty) {
      return const SizedBox.shrink();
    }

    final calculator = const MuscleLoadCalculator();
    final rawLoads = calculator.calculateForWorkout(
      workout: workout,
      exerciseCatalog: exerciseCatalog,
    );
    final normalizedLoads = calculator.normalizer.normalize(rawLoads);

    return WorkoutHeatmapPreview(
      rawLoads: rawLoads,
      normalizedLoads: normalizedLoads,
      emptyMessage: 'Нет данных',
      width: width,
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel =
        '${_monthLabels[_displayedMonth.month - 1]} ${_displayedMonth.year}';
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final compactCalendar = screenWidth < 420;
    final cellHeight = compactCalendar ? 46.0 : _calendarCellHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  BackendApi.describeError(
                    snapshot.error!,
                    fallback: 'Не удалось загрузить тренировки.',
                  ),
                ),
              );
            }

            final workouts = snapshot.data ?? [];
            final byDay = _groupByDay(workouts);
            final selectedDayWorkouts =
                byDay[_selectedDay] ?? const <Map<String, dynamic>>[];
            final monthCount = _workoutsInDisplayedMonth(byDay);

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _catalogFuture,
              builder: (context, catalogSnapshot) {
                final exerciseCatalog = catalogSnapshot.data ?? const [];
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: DashboardCard(
                            color: Color.alphaBlend(
                              scheme.surface.withValues(alpha: 0.36),
                              scheme.surfaceContainerHigh,
                            ),
                            borderColor:
                                scheme.outlineVariant.withValues(alpha: 0.28),
                            child: Padding(
                              padding:
                                  EdgeInsets.all(compactCalendar ? 10 : 14),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => _changeMonth(-1),
                                        icon: const Icon(
                                            Icons.chevron_left_rounded),
                                      ),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text(
                                              monthLabel,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800),
                                            ),
                                            if (monthCount > 0) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Тренировок: $monthCount',
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: scheme.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _changeMonth(1),
                                        icon: const Icon(
                                            Icons.chevron_right_rounded),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: compactCalendar ? 6 : 8),
                                  Row(
                                    children: [
                                      ..._weekdayLabels
                                          .map(
                                            (label) => Expanded(
                                              child: Text(
                                                label,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontSize: compactCalendar
                                                          ? 11
                                                          : null,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      SizedBox(
                                          width: compactCalendar ? 28.0 : 36.0),
                                    ],
                                  ),
                                  SizedBox(height: compactCalendar ? 4 : 6),
                                  ..._buildWeekRows(
                                    byDay,
                                    cellHeight,
                                    compactCalendar,
                                    workouts,
                                    exerciseCatalog,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      DashboardSectionLabel(
                          'Тренировки за ${_selectedDayLabel()}'),
                      const SizedBox(height: 12),
                      if (selectedDayWorkouts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event_busy_outlined,
                                size: 18,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'На этот день тренировок нет',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.65),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ...selectedDayWorkouts.map(
                        (workout) {
                          final isActive = workout['finished_at'] == null;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(workout['id']),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _deleteWorkout(workout);
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                decoration: BoxDecoration(
                                  color: scheme.error.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Icon(Icons.delete_rounded,
                                        color: scheme.error, size: 22),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Удалить',
                                      style: TextStyle(
                                        color: scheme.error,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                  ],
                                ),
                              ),
                              child: DashboardCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                onTap: () => _openEditWorkout(workout),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final showSideHeatmap =
                                        constraints.maxWidth >= 640 &&
                                            exerciseCatalog.isNotEmpty;
                                    final showHeatmapLeft =
                                        constraints.maxWidth < 640 &&
                                            exerciseCatalog.isNotEmpty;

                                    final details = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (workout['name'] ??
                                                        'Тренировка')
                                                    .toString(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                            ),
                                            if (isActive) ...[
                                              const SizedBox(width: 8),
                                              StatusBadge(
                                                label: 'Активна',
                                                color: scheme.secondary,
                                                compact: true,
                                              ),
                                            ],
                                            const SizedBox(width: 4),
                                            SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: Icon(
                                                  Icons.ios_share_rounded,
                                                  size: 18,
                                                  color: scheme.onSurfaceVariant
                                                      .withValues(alpha: 0.65),
                                                ),
                                                tooltip: 'Поделиться карточкой',
                                                onPressed: () => _shareWorkout(
                                                  workout,
                                                  exerciseCatalog,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _workoutSubtitle(workout),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                height: 1.35,
                                              ),
                                        ),
                                      ],
                                    );

                                    if (showHeatmapLeft) {
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildWorkoutHeatmapPreview(
                                            context,
                                            workout,
                                            exerciseCatalog,
                                            width: 132,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  minHeight: 132),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    (workout['name'] ??
                                                            'Тренировка')
                                                        .toString(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  Text(
                                                    _workoutTonnageLabel(
                                                        workout),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                  if (isActive)
                                                    StatusBadge(
                                                      label: 'Активна',
                                                      color: scheme.secondary,
                                                      compact: true,
                                                    ),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: SizedBox(
                                                      width: 32,
                                                      height: 32,
                                                      child: IconButton(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        icon: Icon(
                                                          Icons
                                                              .ios_share_rounded,
                                                          size: 18,
                                                          color: scheme
                                                              .onSurfaceVariant
                                                              .withValues(
                                                                  alpha: 0.65),
                                                        ),
                                                        tooltip:
                                                            'Поделиться карточкой',
                                                        onPressed: () =>
                                                            _shareWorkout(
                                                          workout,
                                                          exerciseCatalog,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: details),
                                        if (showSideHeatmap) ...[
                                          const SizedBox(width: 16),
                                          _buildWorkoutHeatmapPreview(
                                            context,
                                            workout,
                                            exerciseCatalog,
                                            width: 148,
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _openAddWorkoutOptions,
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить тренировку'),
                            ),
                            OutlinedButton.icon(
                              onPressed: selectedDayWorkouts.isEmpty
                                  ? null
                                  : () => _exportSelectedDayWorkouts(
                                        selectedDayWorkouts,
                                      ),
                              icon: const Icon(Icons.file_download_outlined),
                              label: const Text('Экспорт тренировки'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _exportWorkoutRange(workouts),
                              icon: const Icon(Icons.download_for_offline_outlined),
                              label: const Text('Экспорт диапазона'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum _CalendarCreateAction {
  manual,
  template,
  json,
}
