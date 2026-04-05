import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';

enum TemplatesSection { exercises, templates }

// ─── Top-level helpers ───────────────────────────────────────────────────────

String _displayMuscleName(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return normalized;
  return normalized[0].toUpperCase() + normalized.substring(1);
}

bool _matchesExerciseSearch(Map<String, dynamic> exercise, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name = (exercise['name'] ?? '').toString().toLowerCase();
  final primary = (exercise['primary_muscle'] ?? '').toString().toLowerCase();
  final secondary =
      ((exercise['secondary_muscles'] as List?)?.cast<dynamic>() ?? const [])
          .map((item) => item.toString().toLowerCase())
          .join(' ');
  return name.contains(q) || primary.contains(q) || secondary.contains(q);
}

List<MapEntry<String, List<Map<String, dynamic>>>> _groupByCatalog(
  Iterable<Map<String, dynamic>> exercises,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final exercise in exercises) {
    final group = (exercise['primary_muscle'] ?? 'другое').toString().trim();
    grouped.putIfAbsent(group, () => []).add(exercise);
  }
  final entries = grouped.entries.toList()
    ..sort((a, b) =>
        _displayMuscleName(a.key).compareTo(_displayMuscleName(b.key)));
  for (final entry in entries) {
    entry.value.sort((a, b) =>
        (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
  }
  return entries;
}

// ─── Template exercise entry ──────────────────────────────────────────────────

class _TplExercise {
  _TplExercise({
    required this.name,
    this.catalogId,
    this.sets = 3,
    this.reps = '8',
    this.weight,
  }) : key = UniqueKey();

  final UniqueKey key;
  int? catalogId;
  String name;
  int sets;
  String reps;
  double? weight;
}

// ─── TemplatesScreen ──────────────────────────────────────────────────────────

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, this.section});

  final TemplatesSection? section;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  static const List<String> _defaultMuscleGroups = [
    'грудь', 'спина', 'ноги', 'плечи', 'бицепс',
    'трицепс', 'кор', 'ягодицы', 'икры', 'предплечья',
  ];

  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _workouts = const [];
  bool _loading = true;
  String? _templatesError;
  String? _catalogError;
  String? _workoutsError;
  final TextEditingController _catalogSearchController =
      TextEditingController();
  String _catalogSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _catalogSearchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTemplates() async {
    try {
      return await BackendApi.getTemplates();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.templatesCache);
      if (cached != null) {
        return cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadCatalog() async {
    try {
      return await BackendApi.getExercises();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null) {
        return cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadWorkouts() async {
    try {
      return await BackendApi.getWorkouts();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
      if (cached != null) {
        return cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      rethrow;
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _loading = true;
      _templatesError = null;
      _catalogError = null;
      _workoutsError = null;
    });

    List<Map<String, dynamic>> templates = _templates;
    List<Map<String, dynamic>> catalog = _catalog;
    List<Map<String, dynamic>> workouts = _workouts;
    String? templatesError;
    String? catalogError;
    String? workoutsError;

    try {
      templates = await _loadTemplates();
    } catch (e) {
      templatesError = e.toString();
    }
    try {
      catalog = await _loadCatalog();
    } catch (e) {
      catalogError = e.toString();
    }
    try {
      workouts = await _loadWorkouts();
    } catch (e) {
      workoutsError = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _catalog = catalog;
      _workouts = workouts;
      _templatesError = templatesError;
      _catalogError = catalogError;
      _workoutsError = workoutsError;
      _loading = false;
    });
  }

  // ─── Exercise CRUD ────────────────────────────────────────────────────────

  Future<void> _upsertExerciseDialog({Map<String, dynamic>? exercise}) async {
    if (_catalogError != null && exercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Каталог упражнений пока недоступен на сервере.'),
        ),
      );
      return;
    }

    final muscleGroups = _resolveMuscleGroups(exercise: exercise);
    final nameController =
        TextEditingController(text: (exercise?['name'] ?? '').toString());
    String selectedPrimary =
        (exercise?['primary_muscle'] ?? muscleGroups.first).toString();
    final selectedSecondary = <String>{
      ...((exercise?['secondary_muscles'] as List?)?.map((e) => e.toString()) ??
          const []),
    };
    selectedSecondary.remove(selectedPrimary);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final media = MediaQuery.of(context);
          final isCompact = media.size.width < 430;
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 24,
              vertical: isCompact ? 16 : 24,
            ),
            title: Text(
              exercise == null ? 'Новое упражнение' : 'Редактировать упражнение',
            ),
            content: SizedBox(
              width: isCompact ? media.size.width * 0.92 : 460,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: media.size.height * (isCompact ? 0.62 : 0.72),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                          labelText: 'Название упражнения'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPrimary,
                      decoration: const InputDecoration(
                          labelText: 'Основная группа мышц'),
                      items: muscleGroups
                          .map((group) => DropdownMenuItem<String>(
                                value: group,
                                child: Text(_displayMuscleName(group)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedPrimary = value;
                          selectedSecondary.remove(value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Дополнительные группы мышц'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: muscleGroups
                                .where((group) => group != selectedPrimary)
                                .map((group) => FilterChip(
                                      label: Text(_displayMuscleName(group)),
                                      selected:
                                          selectedSecondary.contains(group),
                                      onSelected: (isSelected) {
                                        setLocalState(() {
                                          if (isSelected) {
                                            selectedSecondary.add(group);
                                          } else {
                                            selectedSecondary.remove(group);
                                          }
                                        });
                                      },
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название упражнения.')),
      );
      return;
    }

    try {
      if (exercise == null) {
        await BackendApi.createExercise(
          name: name,
          primaryMuscle: selectedPrimary,
          secondaryMuscles: selectedSecondary.toList(),
        );
      } else {
        await BackendApi.updateExercise(
          exerciseId: exercise['id'] as int,
          name: name,
          primaryMuscle: selectedPrimary,
          secondaryMuscles: selectedSecondary.toList(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exercise == null
              ? 'Упражнение создано.'
              : 'Упражнение обновлено.'),
        ),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(BackendApi.describeError(
            e,
            fallback: exercise == null
                ? 'Не удалось создать упражнение.'
                : 'Не удалось обновить упражнение.',
          )),
        ),
      );
    }
  }

  Future<void> _deleteExercise(Map<String, dynamic> exercise) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить упражнение?'),
        content: Text(
          'Упражнение "${(exercise['name'] ?? '').toString()}" будет удалено из каталога.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await BackendApi.deleteExercise(exercise['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Упражнение удалено.')));
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(BackendApi.describeError(
            e,
            fallback: 'Не удалось удалить упражнение.',
          )),
        ),
      );
    }
  }

  // ─── Template CRUD ────────────────────────────────────────────────────────

  Future<void> _openTemplateEditor({
    Map<String, dynamic>? template,
    List<_TplExercise>? initialExercises,
    String? initialName,
  }) async {
    if (_catalogError != null || _catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            template == null
                ? 'Для создания шаблона нужен каталог упражнений.'
                : 'Для редактирования шаблона нужен каталог упражнений.',
          ),
        ),
      );
      return;
    }

    // Build initial exercise list from existing template
    final List<_TplExercise> preloaded;
    if (initialExercises != null) {
      preloaded = initialExercises;
    } else if (template != null) {
      final rawExercises =
          (template['exercises'] as List?)?.cast<dynamic>() ?? const [];
      preloaded = rawExercises.map((raw) {
        final map = (raw as Map).cast<String, dynamic>();
        final name = (map['exercise_name'] ?? '').toString();
        final catalogId = map['catalog_exercise_id'];
        final sets = (map['target_sets'] as int?) ?? 3;
        final reps = (map['target_reps'] ?? '8').toString();
        final weight = (map['target_weight'] as num?)?.toDouble();
        return _TplExercise(
          name: name,
          catalogId: catalogId is int ? catalogId : null,
          sets: sets,
          reps: reps,
          weight: weight,
        );
      }).toList();
    } else {
      preloaded = [];
    }

    final result = await Navigator.of(context).push<_TemplateEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TemplateEditorScreen(
          catalog: _catalog,
          initialName: initialName ?? (template?['name'] ?? '').toString(),
          initialExercises: preloaded,
          isEditing: template != null,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final name = result.name;
    final tplExercises = result.exercises;

    if (name.isEmpty || tplExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите название и выберите хотя бы одно упражнение.'),
        ),
      );
      return;
    }

    final payload = tplExercises.asMap().entries.map((entry) {
      final i = entry.key;
      final ex = entry.value;
      return {
        'catalog_exercise_id': ex.catalogId,
        'exercise_name': ex.name,
        'position': i + 1,
        'target_sets': ex.sets,
        'target_reps': ex.reps,
        'target_weight': ex.weight,
      };
    }).toList();

    try {
      if (template == null) {
        await BackendApi.createTemplate(
          name: name,
          exercises: const [],
          templateExercises: payload,
        );
      } else {
        await BackendApi.updateTemplate(
          templateId: template['id'] as int,
          name: name,
          exercises: const [],
          templateExercises: payload,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              template == null ? 'Шаблон создан.' : 'Шаблон обновлён.'),
        ),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(BackendApi.describeError(
            e,
            fallback: template == null
                ? 'Не удалось создать шаблон.'
                : 'Не удалось обновить шаблон.',
          )),
        ),
      );
    }
  }

  Future<void> _shareTemplate(Map<String, dynamic> template) async {
    final templateId = template['id'] as int;
    final existingToken = template['share_token'] as String?;

    // If already shared, just show the share sheet
    if (existingToken != null) {
      if (!mounted) return;
      await _showShareSheet(templateId, existingToken, template['name']?.toString() ?? '');
      return;
    }

    // Generate token
    try {
      final token = await BackendApi.shareTemplate(templateId);
      if (!mounted) return;
      await _showShareSheet(templateId, token, template['name']?.toString() ?? '');
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(BackendApi.describeError(e))),
      );
    }
  }

  Future<void> _showShareSheet(
    int templateId,
    String token,
    String templateName,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TemplateShareSheet(
        templateId: templateId,
        token: token,
        templateName: templateName,
        onRevoke: () async {
          Navigator.of(ctx).pop();
          try {
            await BackendApi.revokeTemplateShare(templateId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Доступ к шаблону закрыт.')),
            );
            await _refreshData();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(BackendApi.describeError(e))),
            );
          }
        },
      ),
    );
  }

  Future<void> _importTemplateDialog() async {
    final tokenController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импорт шаблона'),
        content: TextField(
          controller: tokenController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Код шаблона',
            hintText: 'Вставьте код, полученный от другого пользователя',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );

    final token = tokenController.text.trim();
    tokenController.dispose();

    if (confirmed != true || token.isEmpty || !mounted) return;

    try {
      await BackendApi.importSharedTemplate(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шаблон импортирован.')),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(BackendApi.describeError(
            e,
            fallback: 'Не удалось импортировать шаблон.',
          )),
        ),
      );
    }
  }

  Future<void> _deleteTemplate(Map<String, dynamic> template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: Text(
          'Шаблон "${(template['name'] ?? 'Шаблон').toString()}" будет удалён без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await BackendApi.deleteTemplate(template['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Шаблон удалён.')));
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(BackendApi.describeError(
            e,
            fallback: 'Не удалось удалить шаблон.',
          )),
        ),
      );
    }
  }

  // ─── Save workout as template ─────────────────────────────────────────────

  Future<void> _saveWorkoutAsTemplate() async {
    if (_workoutsError != null && _workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Список тренировок пока недоступен.')),
      );
      return;
    }

    if (_workouts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Сначала создайте хотя бы одну тренировку.')),
      );
      return;
    }

    final selectedWorkout = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _WorkoutPickerSheet(workouts: _workouts),
    );
    if (selectedWorkout == null || !mounted) return;

    final exercises = _extractTemplateExercises(selectedWorkout);
    if (exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('В этой тренировке нет упражнений для шаблона.')),
      );
      return;
    }

    await _openTemplateEditor(
      initialExercises: exercises,
      initialName: (selectedWorkout['name'] ?? '').toString(),
    );
  }

  /// Extracts exercises from a completed workout, preserving actual sets count.
  List<_TplExercise> _extractTemplateExercises(Map<String, dynamic> workout) {
    final rawExercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final result = <_TplExercise>[];

    for (final raw in rawExercises) {
      final exercise = (raw as Map).cast<String, dynamic>();
      final name = (exercise['exercise_name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final catalogId = exercise['catalog_exercise_id'];
      final sets = (exercise['sets'] as List?)?.length ?? 3;

      // Compute median reps from actual sets
      final rawSets =
          (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
      int repsVal = 8;
      if (rawSets.isNotEmpty) {
        final repsList = rawSets
            .map((s) => (s as Map)['reps'])
            .whereType<int>()
            .toList();
        if (repsList.isNotEmpty) {
          repsList.sort();
          repsVal = repsList[repsList.length ~/ 2];
        }
      }

      result.add(_TplExercise(
        name: name,
        catalogId: catalogId is int ? catalogId : null,
        sets: sets,
        reps: repsVal.toString(),
      ));
    }

    return result;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<String> _resolveMuscleGroups({Map<String, dynamic>? exercise}) {
    final values = <String>{..._defaultMuscleGroups};

    for (final item in _catalog) {
      final primary = (item['primary_muscle'] ?? '').toString().trim();
      if (primary.isNotEmpty) values.add(primary);

      final secondary =
          (item['secondary_muscles'] as List?)?.cast<dynamic>() ?? const [];
      for (final muscle in secondary) {
        final normalized = muscle.toString().trim();
        if (normalized.isNotEmpty) values.add(normalized);
      }
    }

    if (exercise != null) {
      final primary = (exercise['primary_muscle'] ?? '').toString().trim();
      if (primary.isNotEmpty) values.add(primary);
    }

    return values.toList()
      ..sort((a, b) =>
          _displayMuscleName(a).compareTo(_displayMuscleName(b)));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_templatesError != null && _templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Не удалось загрузить шаблоны: $_templatesError'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _refreshData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final filteredCatalog = _catalog
        .where((e) => _matchesExerciseSearch(e, _catalogSearchQuery))
        .toList();
    final groupedCatalog = _groupByCatalog(filteredCatalog);

    return AppBackdrop(
      child: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      scheme.secondary.withValues(alpha: 0.14),
                      scheme.surfaceContainer,
                    ),
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.14),
                      scheme.surfaceContainerLow,
                    ),
                  ],
                ),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personal',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Упражнений: ${_catalog.length}. Шаблонов: ${_templates.length}.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),

            // ─── Templates section ───────────────────────────────────────
            if (widget.section != TemplatesSection.exercises) ...[
              const SizedBox(height: 14),
              _SectionHeader(
                title: 'Шаблоны',
                actionLabel: 'Шаблон',
                onPressed: () => _openTemplateEditor(),
                secondaryActionLabel: 'Из тренировки',
                onSecondaryPressed: _saveWorkoutAsTemplate,
                tertiaryActionLabel: 'Импорт',
                onTertiaryPressed: _importTemplateDialog,
              ),
              const SizedBox(height: 10),
              if (_templates.isEmpty)
                const Card(
                  child: ListTile(title: Text('Шаблонов пока нет.')),
                )
              else
                ..._templates.map((template) {
                  final exercises =
                      (template['exercises'] as List?)?.cast<dynamic>() ??
                          const [];
                  final names = exercises
                      .take(4)
                      .map((exercise) =>
                          ((exercise as Map)['exercise_name'] ?? '').toString())
                      .where((name) => name.isNotEmpty)
                      .join(', ');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        title: Text(
                          (template['name'] ?? 'Шаблон').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            exercises.isEmpty ? 'Упражнений нет' : names,
                          ),
                        ),
                        trailing: Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () => _shareTemplate(template),
                              tooltip: template['share_token'] != null
                                  ? 'Поделиться (активно)'
                                  : 'Поделиться',
                              icon: Icon(
                                Icons.share_outlined,
                                color: template['share_token'] != null
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _openTemplateEditor(template: template),
                              tooltip: 'Редактировать',
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () => _deleteTemplate(template),
                              tooltip: 'Удалить',
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],

            // ─── Exercise catalog section ─────────────────────────────────
            if (widget.section != TemplatesSection.templates) ...[
              const SizedBox(height: 18),
              _SectionHeader(
                title: 'Каталог упражнений',
                actionLabel: 'Упражнение',
                onPressed: () => _upsertExerciseDialog(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catalogSearchController,
                onChanged: (v) => setState(() => _catalogSearchQuery = v),
                decoration: const InputDecoration(
                  hintText: 'Поиск упражнений',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (_catalogError != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: const Text('Каталог недоступен'),
                    subtitle: Text(_catalogError!),
                  ),
                ),
              if (_catalogError != null) const SizedBox(height: 10),
              if (_catalog.isEmpty)
                const Card(
                  child: ListTile(title: Text('Каталог пуст.')),
                )
              else
                ...groupedCatalog.map((entry) {
                  final groupName = entry.key;
                  final exercises = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ExpansionTile(
                        title: Text(
                          _displayMuscleName(groupName),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${exercises.length} упражнений'),
                        children: exercises.map((exercise) {
                          final secondary =
                              (exercise['secondary_muscles'] as List?)
                                      ?.cast<dynamic>() ??
                                  const [];
                          final secondaryText = secondary.isEmpty
                              ? 'Без доп. групп'
                              : secondary
                                  .map((item) =>
                                      _displayMuscleName(item.toString()))
                                  .join(', ');
                          return ListTile(
                            dense: true,
                            title: Text((exercise['name'] ?? '').toString()),
                            subtitle: Text(secondaryText),
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  onPressed: () => _upsertExerciseDialog(
                                      exercise: exercise),
                                  tooltip: 'Редактировать',
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  onPressed: () => _deleteExercise(exercise),
                                  tooltip: 'Удалить',
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── _SectionHeader ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
    this.secondaryActionLabel,
    this.onSecondaryPressed,
    this.tertiaryActionLabel,
    this.onTertiaryPressed,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onPressed;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryPressed;
  final String? tertiaryActionLabel;
  final VoidCallback? onTertiaryPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionLabel(title),
        const SizedBox(height: 6),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (tertiaryActionLabel != null && onTertiaryPressed != null)
              OutlinedButton.icon(
                onPressed: onTertiaryPressed,
                icon: const Icon(Icons.download_rounded),
                label: Text(tertiaryActionLabel!),
              ),
            if (secondaryActionLabel != null && onSecondaryPressed != null)
              OutlinedButton.icon(
                onPressed: onSecondaryPressed,
                icon: const Icon(Icons.history_rounded),
                label: Text(secondaryActionLabel!),
              ),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── _WorkoutPickerSheet ──────────────────────────────────────────────────────

class _WorkoutPickerSheet extends StatefulWidget {
  const _WorkoutPickerSheet({required this.workouts});

  final List<Map<String, dynamic>> workouts;

  @override
  State<_WorkoutPickerSheet> createState() => _WorkoutPickerSheetState();
}

class _WorkoutPickerSheetState extends State<_WorkoutPickerSheet> {
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

  DateTime? _parseWorkoutDate(Map<String, dynamic> workout) {
    return DateTime.tryParse((workout['started_at'] ?? '').toString())
        ?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = widget.workouts.where((workout) {
      if (normalizedQuery.isEmpty) return true;
      final name = (workout['name'] ?? '').toString().toLowerCase();
      final exercises =
          (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
      final exerciseText = exercises
          .map((exercise) =>
              ((exercise as Map)['exercise_name'] ?? '').toString().toLowerCase())
          .join(' ');
      return name.contains(normalizedQuery) ||
          exerciseText.contains(normalizedQuery);
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
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                'Выберите тренировку',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  labelText: 'Поиск тренировки',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('Подходящих тренировок не найдено.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final workout = filtered[index];
                          final exercises =
                              (workout['exercises'] as List?)?.length ?? 0;
                          final date = _parseWorkoutDate(workout);
                          final dateText = date == null
                              ? 'Без даты'
                              : '${date.day.toString().padLeft(2, '0')}.'
                                  '${date.month.toString().padLeft(2, '0')}.'
                                  '${date.year}';
                          return ListTile(
                            leading: const Icon(Icons.fitness_center_rounded),
                            title: Text(
                                (workout['name'] ?? 'Тренировка').toString()),
                            subtitle: Text('$dateText • Упражнений: $exercises'),
                            onTap: () => Navigator.of(context).pop(workout),
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

// ─── Template editor result ───────────────────────────────────────────────────

class _TemplateEditorResult {
  const _TemplateEditorResult({required this.name, required this.exercises});
  final String name;
  final List<_TplExercise> exercises;
}

// ─── _TemplateEditorScreen ────────────────────────────────────────────────────

class _TemplateEditorScreen extends StatefulWidget {
  const _TemplateEditorScreen({
    required this.catalog,
    required this.initialExercises,
    required this.isEditing,
    this.initialName,
  });

  final List<Map<String, dynamic>> catalog;
  final List<_TplExercise> initialExercises;
  final bool isEditing;
  final String? initialName;

  @override
  State<_TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<_TemplateEditorScreen> {
  late final TextEditingController _nameController;
  late final List<_TplExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _exercises = List.of(widget.initialExercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, item);
    });
  }

  void _removeExercise(int index) {
    setState(() => _exercises.removeAt(index));
  }

  void _updateSets(int index, int delta) {
    setState(() {
      final current = _exercises[index].sets;
      _exercises[index].sets = (current + delta).clamp(1, 20);
    });
  }

  void _updateReps(int index, String value) {
    _exercises[index].reps = value;
  }

  void _updateWeight(int index, String value) {
    _exercises[index].weight = double.tryParse(value.replaceAll(',', '.'));
  }

  Future<void> _addExercises() async {
    final alreadyIds = _exercises.map((e) => e.catalogId).whereType<int>().toSet();
    final alreadyNames = _exercises.map((e) => e.name).toSet();

    final picked = await showModalBottomSheet<List<_TplExercise>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExercisePickerSheet(
        catalog: widget.catalog,
        alreadySelectedIds: alreadyIds,
        alreadySelectedNames: alreadyNames,
      ),
    );

    if (picked == null || picked.isEmpty) return;
    setState(() => _exercises.addAll(picked));
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название шаблона.')),
      );
      return;
    }
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно упражнение.')),
      );
      return;
    }
    Navigator.of(context).pop(
      _TemplateEditorResult(name: name, exercises: List.of(_exercises)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Редактировать шаблон' : 'Новый шаблон'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Name field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название шаблона',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Exercises header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _exercises.isEmpty
                  ? 'Упражнения'
                  : 'Упражнения (${_exercises.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),

          const SizedBox(height: 8),

          // Exercise list or empty state
          Expanded(
            child: _exercises.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fitness_center_rounded,
                          size: 48,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Нет упражнений',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _addExercises,
                          icon: const Icon(Icons.add),
                          label: const Text('Добавить упражнение'),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    buildDefaultDragHandles: false,
                    itemCount: _exercises.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final ex = _exercises[index];
                      return _ExerciseEditorTile(
                        key: ex.key,
                        exercise: ex,
                        index: index,
                        onRemove: () => _removeExercise(index),
                        onSetsChanged: (delta) => _updateSets(index, delta),
                        onRepsChanged: (val) => _updateReps(index, val),
                        onWeightChanged: (val) => _updateWeight(index, val),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _exercises.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addExercises,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
    );
  }
}

// ─── _ExerciseEditorTile ──────────────────────────────────────────────────────

class _ExerciseEditorTile extends StatefulWidget {
  const _ExerciseEditorTile({
    super.key,
    required this.exercise,
    required this.index,
    required this.onRemove,
    required this.onSetsChanged,
    required this.onRepsChanged,
    required this.onWeightChanged,
  });

  final _TplExercise exercise;
  final int index;
  final VoidCallback onRemove;
  final void Function(int delta) onSetsChanged;
  final void Function(String value) onRepsChanged;
  final void Function(String value) onWeightChanged;

  @override
  State<_ExerciseEditorTile> createState() => _ExerciseEditorTileState();
}

class _ExerciseEditorTileState extends State<_ExerciseEditorTile> {
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _repsController = TextEditingController(text: widget.exercise.reps);
    _weightController = TextEditingController(
      text: widget.exercise.weight != null
          ? widget.exercise.weight!
              .toStringAsFixed(
                widget.exercise.weight! % 1 == 0 ? 0 : 1,
              )
          : '',
    );
  }

  @override
  void dispose() {
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sets = widget.exercise.sets;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: name + delete
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.exercise.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 20,
                  color: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Row 2: sets | reps | weight + drag handle
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Sets
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Подходы',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SmallIconButton(
                          icon: Icons.remove,
                          onPressed:
                              sets > 1 ? () => widget.onSetsChanged(-1) : null,
                        ),
                        Container(
                          width: 30,
                          alignment: Alignment.center,
                          child: Text(
                            '$sets',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _SmallIconButton(
                          icon: Icons.add,
                          onPressed:
                              sets < 20 ? () => widget.onSetsChanged(1) : null,
                        ),
                      ],
                    ),
                  ],
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    height: 40,
                    child: VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant,
                    ),
                  ),
                ),

                // Reps
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Повт.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _repsController,
                        onChanged: widget.onRepsChanged,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
                          hintText: '8',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.text,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                          LengthLimitingTextInputFormatter(6),
                        ],
                      ),
                    ),
                  ],
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                    height: 40,
                    child: VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant,
                    ),
                  ),
                ),

                // Weight (optional)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Вес, кг',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _weightController,
                        onChanged: widget.onWeightChanged,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
                          hintText: '—',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[\d\.,]')),
                          LengthLimitingTextInputFormatter(7),
                        ],
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Drag handle
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

// ─── _ExercisePickerSheet ─────────────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({
    required this.catalog,
    required this.alreadySelectedIds,
    required this.alreadySelectedNames,
  });

  final List<Map<String, dynamic>> catalog;
  final Set<int> alreadySelectedIds;
  final Set<String> alreadySelectedNames;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _pickedIds = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = widget.catalog
        .where((e) => _matchesExerciseSearch(e, _query))
        .toList();
    final grouped = _groupByCatalog(filtered);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Добавить упражнения',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (_pickedIds.isNotEmpty)
                        FilledButton(
                          onPressed: _confirmPick,
                          child:
                              Text('Добавить (${_pickedIds.length})'),
                        ),
                    ],
                  ),
                ),

                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Поиск упражнений',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),

                // List
                Expanded(
                  child: grouped.isEmpty
                      ? const Center(child: Text('Ничего не найдено.'))
                      : ListView(
                          controller: scrollController,
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: grouped.map((entry) {
                            final groupName = entry.key;
                            final items = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                title: Text(
                                  _displayMuscleName(groupName),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle:
                                    Text('${items.length} упражнений'),
                                initiallyExpanded: _query.isNotEmpty,
                                children: items.map((exercise) {
                                  final id = exercise['id'] as int;
                                  final alreadyIn =
                                      widget.alreadySelectedIds.contains(id) ||
                                          widget.alreadySelectedNames.contains(
                                              (exercise['name'] ?? '')
                                                  .toString());
                                  final picked = _pickedIds.contains(id);
                                  return CheckboxListTile(
                                    value: alreadyIn || picked,
                                    dense: true,
                                    enabled: !alreadyIn,
                                    title: Text(
                                        (exercise['name'] ?? '').toString()),
                                    secondary: alreadyIn
                                        ? Icon(Icons.check_circle_rounded,
                                            color: scheme.primary, size: 20)
                                        : null,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: alreadyIn
                                        ? null
                                        : (val) {
                                            setState(() {
                                              if (val == true) {
                                                _pickedIds.add(id);
                                              } else {
                                                _pickedIds.remove(id);
                                              }
                                            });
                                          },
                                  );
                                }).toList(),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _confirmPick() {
    final picked = widget.catalog
        .where((e) => _pickedIds.contains(e['id'] as int))
        .map((e) => _TplExercise(
              name: (e['name'] ?? '').toString(),
              catalogId: e['id'] as int,
            ))
        .toList();
    Navigator.of(context).pop(picked);
  }
}

// ─── _TemplateShareSheet ──────────────────────────────────────────────────────

class _TemplateShareSheet extends StatelessWidget {
  const _TemplateShareSheet({
    required this.templateId,
    required this.token,
    required this.templateName,
    required this.onRevoke,
  });

  final int templateId;
  final String token;
  final String templateName;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Поделиться шаблоном',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              templateName,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            Text(
              'Код шаблона',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),

            // Token display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      token,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Код скопирован.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Копировать',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Отправьте этот код другому пользователю.\nОн сможет импортировать шаблон через кнопку «Импорт».',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Закрыть доступ'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
