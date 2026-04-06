import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../data/programs_repository.dart';
import 'program_detail_screen.dart';

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  List<Program> _programs = const [];
  List<CustomProgram> _customPrograms = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final programs = await ProgramsRepository.loadAll();
      final custom = _loadCustomPrograms();
      if (!mounted) return;
      setState(() {
        _programs = programs;
        _customPrograms = custom;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<CustomProgram> _loadCustomPrograms() {
    final raw = LocalCache.get<List>(CacheKeys.customPrograms);
    if (raw == null) return [];
    return raw
        .cast<Map>()
        .map((e) => CustomProgram.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> _saveCustomPrograms(List<CustomProgram> programs) async {
    await LocalCache.put(
      CacheKeys.customPrograms,
      programs.map((p) => p.toJson()).toList(),
    );
  }

  Future<void> _deleteCustomProgram(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить программу?'),
        content: const Text('Программа будет удалена. Шаблоны останутся.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated =
        _customPrograms.where((p) => p.id != id).toList();
    await _saveCustomPrograms(updated);
    setState(() => _customPrograms = updated);
  }

  Future<void> _openByCode() async {
    final codeController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Открыть программу'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Код программы',
            hintText: 'например, program_001',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );

    final code = codeController.text.trim();
    codeController.dispose();

    if (confirmed != true || code.isEmpty || !mounted) return;

    // Resolve share code → program id
    final programId = programIdByShareCode[code];
    final found = programId != null
        ? _programs.where((p) => p.id == programId).firstOrNull
        : null;

    if (!mounted) return;

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Программа с кодом «$code» не найдена.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramDetailScreen(program: found),
      ),
    );
  }

  Future<void> _createFromTemplates() async {
    // Load templates from backend / cache
    List<Map<String, dynamic>> templates;
    try {
      templates = await BackendApi.getTemplates();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.templatesCache);
      if (cached != null) {
        templates = cached
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не удалось загрузить шаблоны. Создайте шаблоны сначала.')),
        );
        return;
      }
    }

    if (templates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('У вас нет шаблонов. Создайте шаблоны в разделе «Шаблоны».')),
      );
      return;
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<CustomProgram>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateCustomProgramScreen(templates: templates),
      ),
    );

    if (result == null || !mounted) return;
    final updated = [..._customPrograms, result];
    await _saveCustomPrograms(updated);
    if (!mounted) return;
    setState(() => _customPrograms = updated);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Программа «${result.name}» создана.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 40),
            const SizedBox(height: 12),
            Text('Не удалось загрузить программы',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }

    final beginners =
        _programs.where((p) => p.level == ProgramLevel.beginner).toList();
    final intermediates =
        _programs.where((p) => p.level == ProgramLevel.intermediate).toList();
    final advanced =
        _programs.where((p) => p.level == ProgramLevel.advanced).toList();

    return AppBackdrop(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          // ── Мои программы ───────────────────────────────────────────
          if (_customPrograms.isNotEmpty) ...[
            const DashboardSectionLabel('Мои программы'),
            const SizedBox(height: 10),
            ..._customPrograms.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CustomProgramCard(
                  program: p,
                  onDelete: () => _deleteCustomProgram(p.id),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // ── Кнопки действий ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _createFromTemplates,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Из шаблонов'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openByCode,
                icon: const Icon(Icons.qr_code_rounded),
                label: const Text('По коду'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Новичок ─────────────────────────────────────────────────
          _LevelSection(
            label: 'Новичок',
            emoji: '🌱',
            color: Colors.green,
            programs: beginners,
          ),
          const SizedBox(height: 8),

          // ── Средний ─────────────────────────────────────────────────
          _LevelSection(
            label: 'Средний',
            emoji: '⚡',
            color: Colors.orange,
            programs: intermediates,
          ),
          const SizedBox(height: 8),

          // ── Продвинутый ──────────────────────────────────────────────
          _LevelSection(
            label: 'Продвинутый',
            emoji: '🔥',
            color: scheme.error,
            programs: advanced,
          ),
        ],
      ),
    );
  }
}

// ─── Level section ────────────────────────────────────────────────────────────

class _LevelSection extends StatefulWidget {
  const _LevelSection({
    required this.label,
    required this.emoji,
    required this.color,
    required this.programs,
  });

  final String label;
  final String emoji;
  final Color color;
  final List<Program> programs;

  @override
  State<_LevelSection> createState() => _LevelSectionState();
}

class _LevelSectionState extends State<_LevelSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(widget.emoji,
                        style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${widget.programs.length} программ',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ...widget.programs.map(
              (p) => _ProgramListTile(program: p),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Program list tile ────────────────────────────────────────────────────────

class _ProgramListTile extends StatelessWidget {
  const _ProgramListTile({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProgramDetailScreen(program: program),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    program.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              program.author,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _InfoChip(
                  icon: Icons.flag_rounded,
                  label: programGoalLabel(program.goal),
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                _InfoChip(
                  icon: Icons.calendar_today_rounded,
                  label:
                      '${program.daysPerWeek} д/нед · ${program.durationWeeks} нед',
                  color: scheme.secondary,
                ),
                const SizedBox(width: 6),
                _InfoChip(
                  label: programGenderLabel(program.gender),
                  color: scheme.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Custom program card ──────────────────────────────────────────────────────

class _CustomProgramCard extends StatelessWidget {
  const _CustomProgramCard({
    required this.program,
    required this.onDelete,
  });

  final CustomProgram program;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_rounded,
                      color: scheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        program.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Моя программа · ${program.days.length} дн.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      color: scheme.error, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Удалить',
                ),
              ],
            ),
          ),
          if (program.days.isNotEmpty) ...[
            Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ...program.days.map(
              (d) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: scheme.secondary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${d.day}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.templateName,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ─── Info chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Create custom program screen ─────────────────────────────────────────────

class _CreateCustomProgramScreen extends StatefulWidget {
  const _CreateCustomProgramScreen({required this.templates});

  final List<Map<String, dynamic>> templates;

  @override
  State<_CreateCustomProgramScreen> createState() =>
      _CreateCustomProgramScreenState();
}

class _CreateCustomProgramScreenState
    extends State<_CreateCustomProgramScreen> {
  final _nameController = TextEditingController();

  // Ordered list of selected template IDs (one per day slot)
  final List<int?> _selectedTemplateIds = [null];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addDay() {
    if (_selectedTemplateIds.length >= 7) return;
    setState(() => _selectedTemplateIds.add(null));
  }

  void _removeDay(int index) {
    if (_selectedTemplateIds.length <= 1) return;
    setState(() => _selectedTemplateIds.removeAt(index));
  }

  Map<String, dynamic>? _templateById(int id) =>
      widget.templates.firstWhere(
        (t) => (t['id'] as int?) == id,
        orElse: () => const {},
      );

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название программы.')),
      );
      return;
    }

    final days = <CustomProgramDay>[];
    for (var i = 0; i < _selectedTemplateIds.length; i++) {
      final id = _selectedTemplateIds[i];
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Выберите шаблон для дня ${i + 1}.')),
        );
        return;
      }
      final tpl = _templateById(id);
      days.add(CustomProgramDay(
        day: i + 1,
        templateId: id,
        templateName:
            (tpl?['name'] ?? 'Шаблон $id').toString(),
      ));
    }

    final program = CustomProgram(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      days: days,
      createdAt: DateTime.now().toIso8601String().substring(0, 10),
    );

    Navigator.of(context).pop(program);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать программу'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Название программы',
              hintText: 'например, Моя силовая программа',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          Text(
            'Тренировочные дни',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Выберите шаблон для каждого тренировочного дня.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ..._selectedTemplateIds.asMap().entries.map((entry) {
            final i = entry.key;
            final selectedId = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DashboardCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: scheme.secondary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Д${i + 1}',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: selectedId,
                        hint: const Text('Выберите шаблон'),
                        underline: const SizedBox.shrink(),
                        items: widget.templates.map((t) {
                          final id = (t['id'] as int?) ?? 0;
                          final name = (t['name'] ?? '').toString();
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) => setState(
                            () => _selectedTemplateIds[i] = val),
                      ),
                    ),
                    if (_selectedTemplateIds.length > 1)
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline_rounded,
                            color: scheme.error, size: 20),
                        onPressed: () => _removeDay(i),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_selectedTemplateIds.length < 7)
            OutlinedButton.icon(
              onPressed: _addDay,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить день'),
            ),
        ],
      ),
    );
  }
}
