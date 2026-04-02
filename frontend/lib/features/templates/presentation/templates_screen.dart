import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';

enum TemplatesSection { exercises, templates }

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, this.section});

  final TemplatesSection? section;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  static const List<String> _defaultMuscleGroups = [
    'грудь',
    'спина',
    'ноги',
    'плечи',
    'бицепс',
    'трицепс',
    'кор',
    'ягодицы',
    'икры',
    'предплечья',
  ];

  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _catalog = const [];
  bool _loading = true;
  String? _templatesError;
  String? _catalogError;
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
        return cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
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
        return cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _loading = true;
      _templatesError = null;
      _catalogError = null;
    });

    List<Map<String, dynamic>> templates = _templates;
    List<Map<String, dynamic>> catalog = _catalog;
    String? templatesError;
    String? catalogError;

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

    if (!mounted) return;
    setState(() {
      _templates = templates;
      _catalog = catalog;
      _templatesError = templatesError;
      _catalogError = catalogError;
      _loading = false;
    });
  }

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
              exercise == null
                  ? 'Новое упражнение'
                  : 'Редактировать упражнение',
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
                          .map(
                            (group) => DropdownMenuItem<String>(
                              value: group,
                              child: Text(_displayMuscle(group)),
                            ),
                          )
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
                                .map(
                                  (group) => FilterChip(
                                    label: Text(_displayMuscle(group)),
                                    selected: selectedSecondary.contains(group),
                                    onSelected: (isSelected) {
                                      setLocalState(() {
                                        if (isSelected) {
                                          selectedSecondary.add(group);
                                        } else {
                                          selectedSecondary.remove(group);
                                        }
                                      });
                                    },
                                  ),
                                )
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
          content: Text(
            BackendApi.describeError(
              e,
              fallback: exercise == null
                  ? 'Не удалось создать упражнение.'
                  : 'Не удалось обновить упражнение.',
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Упражнение удалено.')),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось удалить упражнение.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _upsertTemplateDialog({Map<String, dynamic>? template}) async {
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

    final nameController =
        TextEditingController(text: (template?['name'] ?? '').toString());
    final searchController = TextEditingController();
    final selectedExerciseIds = <int>{};
    final initialExercises =
        (template?['exercises'] as List?)?.cast<dynamic>() ?? const [];
    var query = '';

    for (final exercise in initialExercises) {
      final map = (exercise as Map).cast<String, dynamic>();
      final catalogId = map['catalog_exercise_id'];
      if (catalogId is int) {
        selectedExerciseIds.add(catalogId);
        continue;
      }
      final exerciseName = (map['exercise_name'] ?? '').toString();
      final matched = _catalog.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['name']?.toString() == exerciseName,
            orElse: () => null,
          );
      final matchedId = matched?['id'];
      if (matchedId is int) {
        selectedExerciseIds.add(matchedId);
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final media = MediaQuery.of(context);
          final isCompact = media.size.width < 430;
          final filteredCatalog = _catalog.where(
            (exercise) => _matchesExerciseQuery(exercise, query),
          );
          final groupedCatalog = _groupExercises(filteredCatalog);
          final selectedExercises = _catalog
              .where((exercise) => selectedExerciseIds.contains(exercise['id']))
              .toList()
            ..sort((a, b) => (a['name'] ?? '')
                .toString()
                .compareTo((b['name'] ?? '').toString()));

          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 24,
              vertical: isCompact ? 12 : 24,
            ),
            title: Text(
              template == null ? 'Новый шаблон' : 'Редактировать шаблон',
            ),
            content: SizedBox(
              width: media.size.width < 680 ? media.size.width * 0.92 : 640,
              height: media.size.height * (isCompact ? 0.72 : 0.64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration:
                        const InputDecoration(labelText: 'Название шаблона'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    onChanged: (value) => setLocalState(() => query = value),
                    decoration: const InputDecoration(
                      labelText: 'Поиск упражнений',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  if (selectedExercises.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Выбрано: ${selectedExercises.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: isCompact ? 44 : 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedExercises.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final exercise = selectedExercises[index];
                          return InputChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isCompact ? 170 : 220,
                              ),
                              child: Text(
                                (exercise['name'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: () => setLocalState(
                              () => selectedExerciseIds.remove(exercise['id']),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Упражнения'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: groupedCatalog.isEmpty
                        ? const Center(child: Text('Ничего не найдено.'))
                        : ListView(
                            children: groupedCatalog.map((entry) {
                              final groupName = entry.key;
                              final items = entry.value;
                              return ExpansionTile(
                                tilePadding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 4 : 8,
                                ),
                                childrenPadding: EdgeInsets.only(
                                  bottom: isCompact ? 6 : 8,
                                ),
                                initiallyExpanded: query.isNotEmpty,
                                title: Text(_displayMuscle(groupName)),
                                subtitle: Text('${items.length} упражнений'),
                                children: items.map((exercise) {
                                  final exerciseId = exercise['id'] as int;
                                  final selected =
                                      selectedExerciseIds.contains(exerciseId);
                                  final secondary =
                                      (exercise['secondary_muscles'] as List?)
                                              ?.cast<dynamic>() ??
                                          const [];
                                  final secondaryText = secondary.isEmpty
                                      ? null
                                      : secondary
                                          .map((item) =>
                                              _displayMuscle(item.toString()))
                                          .join(', ');
                                  return CheckboxListTile(
                                    value: selected,
                                    dense: true,
                                    visualDensity: isCompact
                                        ? const VisualDensity(
                                            horizontal: -2,
                                            vertical: -2,
                                          )
                                        : VisualDensity.standard,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                        (exercise['name'] ?? '').toString()),
                                    subtitle: secondaryText == null
                                        ? null
                                        : Text('Доп.: $secondaryText'),
                                    onChanged: (value) {
                                      setLocalState(() {
                                        if (value == true) {
                                          selectedExerciseIds.add(exerciseId);
                                        } else {
                                          selectedExerciseIds
                                              .remove(exerciseId);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              );
                            }).toList(),
                          ),
                  ),
                ],
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
    if (name.isEmpty || selectedExerciseIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите название и выберите хотя бы одно упражнение.'),
        ),
      );
      return;
    }

    final selectedExercises = _catalog
        .where((exercise) => selectedExerciseIds.contains(exercise['id']))
        .map((exercise) => {'id': exercise['id'], 'name': exercise['name']})
        .toList();

    try {
      if (template == null) {
        await BackendApi.createTemplate(
            name: name, exercises: selectedExercises);
      } else {
        await BackendApi.updateTemplate(
          templateId: template['id'] as int,
          name: name,
          exercises: selectedExercises,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(template == null ? 'Шаблон создан.' : 'Шаблон обновлён.'),
        ),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: template == null
                  ? 'Не удалось создать шаблон.'
                  : 'Не удалось обновить шаблон.',
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шаблон удалён.')),
      );
      await _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось удалить шаблон.',
            ),
          ),
        ),
      );
    }
  }

  List<String> _resolveMuscleGroups({Map<String, dynamic>? exercise}) {
    final values = <String>{..._defaultMuscleGroups};

    for (final item in _catalog) {
      final primary = (item['primary_muscle'] ?? '').toString().trim();
      if (primary.isNotEmpty) {
        values.add(primary);
      }

      final secondary =
          (item['secondary_muscles'] as List?)?.cast<dynamic>() ?? const [];
      for (final muscle in secondary) {
        final normalized = muscle.toString().trim();
        if (normalized.isNotEmpty) {
          values.add(normalized);
        }
      }
    }

    if (exercise != null) {
      final primary = (exercise['primary_muscle'] ?? '').toString().trim();
      if (primary.isNotEmpty) {
        values.add(primary);
      }
    }

    final groups = values.toList()
      ..sort((a, b) => _displayMuscle(a).compareTo(_displayMuscle(b)));
    return groups;
  }

  bool _matchesExerciseQuery(Map<String, dynamic> exercise, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;

    final name = (exercise['name'] ?? '').toString().toLowerCase();
    final primary = (exercise['primary_muscle'] ?? '').toString().toLowerCase();
    final secondary =
        ((exercise['secondary_muscles'] as List?)?.cast<dynamic>() ?? const [])
            .map((item) => item.toString().toLowerCase())
            .join(' ');
    return name.contains(normalizedQuery) ||
        primary.contains(normalizedQuery) ||
        secondary.contains(normalizedQuery);
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupExercises(
    Iterable<Map<String, dynamic>> exercises,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final exercise in exercises) {
      final group = (exercise['primary_muscle'] ?? 'другое').toString().trim();
      grouped.putIfAbsent(group, () => []).add(exercise);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) => _displayMuscle(a.key).compareTo(_displayMuscle(b.key)));
    for (final entry in entries) {
      entry.value.sort(
        (a, b) => (a['name'] ?? '')
            .toString()
            .compareTo((b['name'] ?? '').toString()),
      );
    }
    return entries;
  }

  String _displayMuscle(String value) {
    final normalized = value.trim().replaceAll('_', ' ');
    if (normalized.isEmpty) {
      return normalized;
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

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
        .where((e) => _matchesExerciseQuery(e, _catalogSearchQuery))
        .toList();
    final groupedCatalog = _groupExercises(filteredCatalog);

    return AppBackdrop(
      child: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
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
            if (widget.section != TemplatesSection.exercises) ...[
            const SizedBox(height: 14),
            _SectionHeader(
              title: 'Шаблоны',
              actionLabel: 'Шаблон',
              onPressed: () => _upsertTemplateDialog(),
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
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () =>
                                _upsertTemplateDialog(template: template),
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
            ], // end templates section
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
              onChanged: (v) =>
                  setState(() => _catalogSearchQuery = v),
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
                        _displayMuscle(groupName),
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
                                .map((item) => _displayMuscle(item.toString()))
                                .join(', ');
                        return ListTile(
                          dense: true,
                          title: Text((exercise['name'] ?? '').toString()),
                          subtitle: Text(secondaryText),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _upsertExerciseDialog(exercise: exercise),
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
            ], // end exercises section
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionLabel(title),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
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
