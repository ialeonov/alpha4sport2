import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../data/programs_repository.dart';

// "Тренировка А — Акцент на квадрицепс и ягодицы" → "Тренировка А"
String _shortWorkoutName(String fullName) {
  final idx = fullName.indexOf(' — ');
  return idx > 0 ? fullName.substring(0, idx) : fullName;
}

// "ФулБоди для новичков (Вейдер)"  → "ФулБоди для"
// "Женский старт: ноги и ягодицы"  → "Женский старт"
// "Пауэрлифтинг — продвинутый"     → "Пауэрлифтинг"
String _programShortName(String name) {
  var s = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  final colonIdx = s.indexOf(':');
  if (colonIdx > 0) s = s.substring(0, colonIdx).trim();
  final dashIdx = s.indexOf(' — ');
  if (dashIdx > 0) s = s.substring(0, dashIdx).trim();
  final words = s.split(' ');
  return words.take(2).join(' ');
}

class ProgramDetailScreen extends StatelessWidget {
  const ProgramDetailScreen({super.key, required this.program});

  final Program program;

  // ─── Share program ──────────────────────────────────────────────────────────

  void _shareProgram(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProgramShareSheet(program: program),
    );
  }

  // ─── Create templates from program ─────────────────────────────────────────

  Future<void> _createTemplates(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Создать шаблоны?'),
        content: Text(
          'Будет создано ${program.workouts.length} шаблона(ов) в разделе «Шаблоны»:\n\n'
          '${program.workouts.map((w) => '• ${_programShortName(program.name)} — ${_shortWorkoutName(w.name)}').join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Создание шаблонов…'),
          ],
        ),
      ),
    );

    int created = 0;
    String? errorMsg;

    for (final workout in program.workouts) {
      final templateName = '${_programShortName(program.name)} — ${_shortWorkoutName(workout.name)}';
      final exercisesPayload = workout.exercises.asMap().entries.map((entry) {
        final i = entry.key;
        final ex = entry.value;
        return {
          'exercise_name': ex.name,
          'catalog_exercise_id': null,
          'position': i + 1,
          'target_sets': ex.sets,
          'target_reps': ex.reps,
          'target_weight': null,
        };
      }).toList();

      try {
        await BackendApi.createTemplate(
          name: templateName,
          exercises: const [],
          templateExercises: exercisesPayload,
        );
        created++;
      } catch (e) {
        errorMsg = BackendApi.describeError(e,
            fallback: 'Ошибка при создании шаблона «$templateName».');
        break;
      }
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close progress dialog

    if (errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Создано $created из ${program.workouts.length}. $errorMsg'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Создано $created шаблон(ов) из программы «${program.name}».'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          program.name,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Поделиться программой',
            onPressed: () => _shareProgram(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // ── Header info ─────────────────────────────────────────
              _ProgramHeader(program: program),
              const SizedBox(height: 16),

              // ── Description ─────────────────────────────────────────
              DashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Описание',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      program.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),

              // ── Notes ───────────────────────────────────────────────
              if (program.notes != null && program.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                DashboardCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Рекомендации',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        program.notes!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Text(
                'Тренировки',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),

              // ── Workouts ─────────────────────────────────────────────
              ...program.workouts.asMap().entries.map((entry) {
                final i = entry.key;
                final workout = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WorkoutCard(
                    workout: workout,
                    index: i,
                  ),
                );
              }),
            ],
          ),

          // ── Bottom button ───────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              decoration: BoxDecoration(
                color: scheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: () => _createTemplates(context),
                icon: const Icon(Icons.library_add_rounded),
                label: Text(
                    'Создать шаблоны из программы (${program.workouts.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Program header ───────────────────────────────────────────────────────────

class _ProgramHeader extends StatelessWidget {
  const _ProgramHeader({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final levelColor = switch (program.level) {
      ProgramLevel.beginner => Colors.green,
      ProgramLevel.intermediate => Colors.orange,
      ProgramLevel.advanced => scheme.error,
    };

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level + Goal badges
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(
                label: programLevelLabel(program.level),
                color: levelColor,
              ),
              _Badge(
                label: programGoalLabel(program.goal),
                color: scheme.primary,
              ),
              _Badge(
                label: programGenderLabel(program.gender),
                color: scheme.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stat row
          Row(
            children: [
              _StatItem(
                icon: Icons.calendar_today_rounded,
                label: '${program.daysPerWeek} дн/нед',
                color: scheme.secondary,
              ),
              const SizedBox(width: 16),
              _StatItem(
                icon: Icons.timer_outlined,
                label: '${program.durationWeeks} недель',
                color: scheme.secondary,
              ),
              const SizedBox(width: 16),
              _StatItem(
                icon: Icons.fitness_center_rounded,
                label: '${program.workouts.fold<int>(0, (sum, w) => sum + w.exercises.length)} упр.',
                color: scheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Автор: ${program.author}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

// ─── Workout card ─────────────────────────────────────────────────────────────

class _WorkoutCard extends StatefulWidget {
  const _WorkoutCard({required this.workout, required this.index});

  final ProgramWorkout workout;
  final int index;

  @override
  State<_WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<_WorkoutCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final workout = widget.workout;
    final letters = ['А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж'];
    final letter = widget.index < letters.length
        ? letters[widget.index]
        : '${widget.index + 1}';

    return DashboardCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workout.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${workout.exercises.length} упражнений',
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

          // Exercises list
          if (_expanded) ...[
            Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.3)),
            _ExercisesList(exercises: workout.exercises),
          ],
        ],
      ),
    );
  }
}

// ─── Exercises list ───────────────────────────────────────────────────────────

class _ExercisesList extends StatelessWidget {
  const _ExercisesList({required this.exercises});

  final List<ProgramExercise> exercises;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Group by superset if applicable
    int? lastSuperset;

    return Column(
      children: exercises.asMap().entries.map((entry) {
        final i = entry.key;
        final ex = entry.value;
        final isNewSuperset =
            ex.supersetGroup != null && ex.supersetGroup != lastSuperset;
        lastSuperset = ex.supersetGroup;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNewSuperset) ...[
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Text(
                  'Суперсет ${ex.supersetGroup}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
            _ExerciseTile(exercise: ex, index: i),
            if (i < exercises.length - 1)
              Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ],
        );
      }).toList(),
    );
  }
}

class _ExerciseTile extends StatefulWidget {
  const _ExerciseTile({required this.exercise, required this.index});

  final ProgramExercise exercise;
  final int index;

  @override
  State<_ExerciseTile> createState() => _ExerciseTileState();
}

class _ExerciseTileState extends State<_ExerciseTile> {
  bool _showNotes = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ex = widget.exercise;

    return InkWell(
      onTap: ex.notes != null && ex.notes!.isNotEmpty
          ? () => setState(() => _showNotes = !_showNotes)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${widget.index + 1}.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ex.name,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // Sets × Reps
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${ex.sets}×${ex.reps}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
                if (ex.rpe != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RPE ${ex.rpe}',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                  ),
                ],
                if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _showNotes
                        ? Icons.info_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            if (_showNotes && ex.notes != null && ex.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text(
                  ex.notes!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Program share sheet ──────────────────────────────────────────────────────

class _ProgramShareSheet extends StatelessWidget {
  const _ProgramShareSheet({required this.program});

  final Program program;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = programShareCodes[program.id] ?? program.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Поделиться программой',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              program.name,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              'Код программы',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
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
              'Отправьте этот код другому пользователю.\nОн сможет открыть программу через кнопку «Открыть по коду» в разделе «Программы».',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Готово'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
