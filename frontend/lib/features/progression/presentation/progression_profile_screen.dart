import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../../core/widgets/user_avatar.dart';
import '../application/progression_controller.dart';
import '../domain/progression_models.dart';

class ProgressionProfileScreen extends StatelessWidget {
  const ProgressionProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль и прогресс')),
      body: const ProgressionProfileContent(),
    );
  }
}

class ProgressionProfileContent extends StatefulWidget {
  const ProgressionProfileContent({super.key});

  @override
  State<ProgressionProfileContent> createState() =>
      _ProgressionProfileContentState();
}

class _ProgressionProfileContentState
    extends State<ProgressionProfileContent> {
  static const _sickLeaveReasons = [
    'болезнь',
    'травма',
    'восстановление',
    'командировка',
    'другое',
  ];

  @override
  void initState() {
    super.initState();
    if (ProgressionController.instance.profile == null) {
      Future.microtask(ProgressionController.instance.refresh);
    }
  }

  Future<void> _pickSickLeave() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, 1),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDateRange: DateTimeRange(
        start: now,
        end: now.add(const Duration(days: 2)),
      ),
      helpText: 'Пауза',
      saveText: 'Далее',
      locale: const Locale('ru'),
    );
    if (range == null || !mounted) return;

    String selectedReason = _sickLeaveReasons.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Оформить паузу'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Период: ${formatShortDate(range.start)} — ${formatShortDate(range.end)}',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(labelText: 'Причина'),
                items: _sickLeaveReasons
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(capitalizeRu(r)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedReason = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ProgressionController.instance.createSickLeave(
        startDate: range.start,
        endDate: range.end,
        reason: selectedReason,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(BackendApi.describeError(error,
            fallback: 'Не удалось оформить паузу.')),
      ));
    }
  }

  Future<void> _cancelSickLeave(int id) async {
    try {
      await ProgressionController.instance.cancelSickLeave(id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(BackendApi.describeError(error,
            fallback: 'Не удалось отменить паузу.')),
      ));
    }
  }

  Future<void> _refresh() => ProgressionController.instance.refresh();

  Future<void> _editDisplayName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Имя профиля'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Имя',
            hintText: 'Например, Иван',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final nextName = controller.text.trim();
    if (nextName.isEmpty || nextName == currentName) return;
    try {
      await ProgressionController.instance.updateDisplayName(nextName);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(BackendApi.describeError(error,
            fallback: 'Не удалось обновить имя пользователя.')),
      ));
    }
  }

  Future<void> _uploadAvatar() async {
    const typeGroup = XTypeGroup(
      label: 'Изображения',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Файл слишком большой. Максимум 5 МБ.')),
      );
      return;
    }

    try {
      await BackendApi.uploadAvatar(bytes: bytes, fileName: file.name);
      await ProgressionController.instance.refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(BackendApi.describeError(error,
            fallback: 'Не удалось загрузить аватар.')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: AnimatedBuilder(
        animation: ProgressionController.instance,
        builder: (context, _) {
          final ctrl = ProgressionController.instance;
          final profile = ctrl.profile;

          if (ctrl.isLoading && profile == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (profile == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ctrl.error ?? 'Не удалось загрузить профиль прогресса.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                // ── Шапка профиля ──────────────────────────────────────
                _ProfileHeader(
                  profile: profile,
                  isLoading: ctrl.isLoading,
                  onEditName: () => _editDisplayName(profile.displayName),
                  onUploadAvatar: _uploadAvatar,
                ),
                const SizedBox(height: 12),

                // ── Метрики ─────────────────────────────────────────────
                _MetricsGrid(
                  items: [
                    _MetricGridItem(
                      title: 'Всего тренировок',
                      value: '${profile.totalCompletedWorkouts}',
                      subtitle: 'Завершено за всё время',
                    ),
                    _MetricGridItem(
                      title: 'Текущая неделя',
                      value: '${profile.currentWeek.workoutCount} трен.',
                      subtitle: _weekStatusLabel(profile.currentWeek),
                      accent: profile.currentWeek.isFrozen
                          ? _MetricAccent.frozen
                          : profile.currentWeek.isIdeal
                              ? _MetricAccent.ideal
                              : profile.currentWeek.status == 'good'
                                  ? _MetricAccent.good
                                  : null,
                    ),
                    _MetricGridItem(
                      title: 'Текущий стрик',
                      value: '${profile.currentStreak} нед.',
                      subtitle: 'Недель с 2+ тренировками',
                      accent: profile.currentStreak >= 4
                          ? _MetricAccent.ideal
                          : profile.currentStreak >= 2
                              ? _MetricAccent.good
                              : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Рекорды ─────────────────────────────────────────────
                _RecordsCard(records: profile.allExerciseRecords),
                const SizedBox(height: 12),

                // ── Достижения ──────────────────────────────────────────
                _SectionCard(
                  title: 'Достижения',
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFFFFB300),
                  child: profile.recentAchievements.isEmpty
                      ? const _EmptyHint(
                          'Первые достижения появятся после тренировок и недель прогресса.')
                      : Column(
                          children: profile.recentAchievements
                              .map((item) => _AchievementRow(item: item))
                              .toList(),
                        ),
                ),

                // ── Последние XP ────────────────────────────────────────
                if (profile.recentRewards.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Последние XP',
                    icon: Icons.bolt_rounded,
                    iconColor: Theme.of(context).colorScheme.secondary,
                    child: Column(
                      children: profile.recentRewards
                          .take(5)
                          .map((r) => _RewardRow(reward: r))
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // ── Пауза ────────────────────────────────────────────────
                _SickLeaveCard(
                  sickLeave: profile.sickLeave,
                  isLoading: ctrl.isLoading,
                  onPickSickLeave: _pickSickLeave,
                  onCancelSickLeave: _cancelSickLeave,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Шапка профиля
// ─────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isLoading,
    required this.onEditName,
    required this.onUploadAvatar,
  });

  final ProgressionProfileData profile;
  final bool isLoading;
  final VoidCallback onEditName;
  final VoidCallback onUploadAvatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DashboardCard(
      color: Color.alphaBlend(
        scheme.secondary.withValues(alpha: 0.06),
        scheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Аватар + имя + звание
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Аватар — нажмите чтобы сменить
              GestureDetector(
                onTap: isLoading ? null : onUploadAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    UserAvatar(
                      radius: 34,
                      avatarUrl: profile.avatarUrl,
                      fallbackText: profile.avatarText,
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 12,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: isLoading ? null : onEditName,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          tooltip: 'Изменить имя',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusBadge(
                          label: profile.title,
                          color: scheme.secondary,
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${profile.totalXp} XP',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (profile.totalLikesReceived > 0) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: scheme.error.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${profile.totalLikesReceived}',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Прогресс уровня
          Row(
            children: [
              _LevelChip(level: profile.level),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: profile.levelProgress,
                    minHeight: 10,
                    color: scheme.secondary,
                    backgroundColor: scheme.secondary.withValues(alpha: 0.15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _LevelChip(level: profile.level + 1, muted: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${profile.xpInLevel} / ${profile.xpToDisplay} XP',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Ещё ${profile.xpRemainingToNextLevel} XP до следующего',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Email — мутный, в самом низу
          Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                size: 13,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 5),
              Text(
                profile.email,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, this.muted = false});

  final int level;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : scheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Lv.$level',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Метрики
// ─────────────────────────────────────────────────────────────────

enum _MetricAccent { ideal, good, frozen }

class _MetricGridItem {
  const _MetricGridItem({
    required this.title,
    required this.value,
    required this.subtitle,
    this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final _MetricAccent? accent;
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.items});

  final List<_MetricGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 1120
            ? 3
            : constraints.maxWidth >= 320
                ? (items.length == 3 ? 3 : 2)
                : 1;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((item) => SizedBox(
                    width: itemWidth,
                    child: _MetricTile(item: item),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.item});

  final _MetricGridItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final accentColor = switch (item.accent) {
      _MetricAccent.ideal => scheme.tertiary,
      _MetricAccent.good => scheme.secondary,
      _MetricAccent.frozen => scheme.onSurfaceVariant,
      null => null,
    };

    return DashboardCard(
      padding: const EdgeInsets.all(16),
      color: accentColor != null
          ? Color.alphaBlend(
              accentColor.withValues(alpha: 0.08),
              scheme.surfaceContainerLow,
            )
          : null,
      borderColor: accentColor?.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: accentColor ?? scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Секция-карточка
// ─────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: (iconColor ?? scheme.secondary)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: iconColor ?? scheme.secondary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Строки достижений, рекордов, наград
// ─────────────────────────────────────────────────────────────────

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.item});

  final AchievementData item;

  static IconData _iconFor(String code) {
    final c = code.toLowerCase();
    if (c.contains('streak')) return Icons.local_fire_department_rounded;
    if (c.contains('pr') || c.contains('record')) {
      return Icons.emoji_events_rounded;
    }
    if (c.contains('month')) return Icons.calendar_month_rounded;
    if (c.contains('week')) return Icons.date_range_rounded;
    if (c.contains('workout')) return Icons.fitness_center_rounded;
    return Icons.star_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconFor(item.code),
              size: 18,
              color: const Color(0xFFFFB300),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  formatShortDate(item.achievedAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.item, required this.showWeight});

  final ExerciseRecordData item;
  final bool showWeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = showWeight ? item.bestWeight : item.bestVolume;
    final label = showWeight ? 'Рекорд веса' : 'Рекорд объёма';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.tertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.trending_up_rounded,
              size: 18,
              color: scheme.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.exerciseName,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _MicroChip(label: label, color: scheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      formatWeight(value),
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${formatShortDate(item.updatedAt)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.reward});

  final RewardData reward;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: 18,
              color: scheme.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _rewardLabel(reward.eventType),
              style: textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '+${reward.xpAwarded} XP',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static String _rewardLabel(String eventType) {
    return switch (eventType) {
      'workout_completed' => 'Тренировка завершена',
      'ideal_week' => 'Идеальная неделя',
      'ideal_month' => 'Идеальный месяц',
      'streak_milestone' => 'Стрик-рекорд',
      'personal_record' => 'Личный рекорд',
      'pr_weight' => 'Рекорд веса',
      'pr_volume' => 'Рекорд объёма',
      'pr_reps' => 'Рекорд повторений',
      _ => eventType,
    };
  }
}

// ─────────────────────────────────────────────────────────────────
// Рекорды с вкладками Вес / Объём
// ─────────────────────────────────────────────────────────────────

class _RecordsCard extends StatefulWidget {
  const _RecordsCard({required this.records});

  final List<ExerciseRecordData> records;

  @override
  State<_RecordsCard> createState() => _RecordsCardState();
}

class _RecordsCardState extends State<_RecordsCard> {
  bool _showWeight = true;

  List<ExerciseRecordData> get _sorted {
    final list = List<ExerciseRecordData>.from(widget.records);
    if (_showWeight) {
      list.sort((a, b) => b.bestWeight.compareTo(a.bestWeight));
    } else {
      list.sort((a, b) => b.bestVolume.compareTo(a.bestVolume));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final records = _sorted;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок + переключатель вкладок
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.trending_up_rounded,
                    size: 18, color: scheme.tertiary),
              ),
              const SizedBox(width: 10),
              Text(
                'Рекорды',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              // Переключатель
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TabChip(
                      label: 'Вес',
                      active: _showWeight,
                      onTap: () => setState(() => _showWeight = true),
                    ),
                    const SizedBox(width: 3),
                    _TabChip(
                      label: 'Объём',
                      active: !_showWeight,
                      onTap: () => setState(() => _showWeight = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Список — не более ~7 строк (~44px каждая)
          if (records.isEmpty)
            _EmptyHint(_showWeight
                ? 'Рекорды веса появятся после тренировок.'
                : 'Рекорды объёма появятся после тренировок.')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 308),
              child: ListView.builder(
                shrinkWrap: true,
                physics: records.length > 7
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: records.length,
                itemBuilder: (context, i) => _RecordRow(
                  item: records[i],
                  showWeight: _showWeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? scheme.tertiary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? scheme.onTertiary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Секция Пауза
// ─────────────────────────────────────────────────────────────────

class _SickLeaveCard extends StatelessWidget {
  const _SickLeaveCard({
    required this.sickLeave,
    required this.isLoading,
    required this.onPickSickLeave,
    required this.onCancelSickLeave,
  });

  final SickLeaveSectionData sickLeave;
  final bool isLoading;
  final VoidCallback onPickSickLeave;
  final ValueChanged<int> onCancelSickLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final active = sickLeave.active;
    final usedEpisodes =
        sickLeave.allowedEpisodesPerMonth - sickLeave.remainingEpisodesThisMonth;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.medical_services_rounded,
                  size: 18,
                  color: scheme.error,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Пауза',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Активная пауза или её отсутствие
          if (active != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: scheme.error.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_rounded,
                      color: scheme.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Активная пауза',
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${formatShortDate(active.startDate)} — ${formatShortDate(active.endDate)}'
                          ' · ${capitalizeRu(active.reason)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 8),
                Text(
                  'Активной паузы нет',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),

          // Квота эпизодов
          Row(
            children: [
              Text(
                'Эпизоды в этом месяце: ',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              ...List.generate(
                sickLeave.allowedEpisodesPerMonth,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < usedEpisodes
                          ? scheme.error
                          : scheme.error.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$usedEpisodes / ${sickLeave.allowedEpisodesPerMonth}',
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sickLeave.remainingEpisodesThisMonth == 0
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Кнопки
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isLoading ||
                        sickLeave.remainingEpisodesThisMonth <= 0
                    ? null
                    : onPickSickLeave,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Взять паузу'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  disabledBackgroundColor:
                      scheme.error.withValues(alpha: 0.3),
                ),
              ),
              if (active != null)
                OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () => onCancelSickLeave(active.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.4)),
                  ),
                  child: const Text('Отменить'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Вспомогательные виджеты
// ─────────────────────────────────────────────────────────────────

class _MicroChip extends StatelessWidget {
  const _MicroChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Хелперы
// ─────────────────────────────────────────────────────────────────

String _weekStatusLabel(WeekProgressData week) {
  if (week.isFrozen) return 'Неделя заморожена паузой';
  return switch (week.status) {
    'ideal' => 'Идеальная неделя',
    'good' => 'Хорошая неделя',
    _ => 'Обычная неделя',
  };
}
