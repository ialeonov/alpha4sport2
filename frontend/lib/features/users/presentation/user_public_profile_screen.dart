import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../progression/domain/progression_models.dart';

class UserPublicProfileScreen extends StatefulWidget {
  const UserPublicProfileScreen({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final int userId;
  final String displayName;
  final String? avatarUrl;

  @override
  State<UserPublicProfileScreen> createState() =>
      _UserPublicProfileScreenState();
}

class _UserPublicProfileScreenState extends State<UserPublicProfileScreen> {
  late Future<ProgressionProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ProgressionProfileData> _load() async {
    final json = await BackendApi.getUserPublicProfile(widget.userId);
    return ProgressionProfileData.fromJson(json);
  }

  Future<void> _refresh() {
    setState(() => _future = _load());
    return _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              radius: 16,
              avatarUrl: widget.avatarUrl,
              fallbackText: widget.displayName.isNotEmpty
                  ? widget.displayName[0].toUpperCase()
                  : 'A',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<ProgressionProfileData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      BackendApi.describeError(
                        snapshot.error!,
                        fallback: 'Не удалось загрузить профиль.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }

          final profile = snapshot.data!;
          return AppBackdrop(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Шапка ──────────────────────────────────────────────
                  _PublicProfileHeader(profile: profile),
                  const SizedBox(height: 12),

                  // ── Метрики ────────────────────────────────────────────
                  _PublicMetricsRow(profile: profile),
                  const SizedBox(height: 12),

                  // ── Рекорды ────────────────────────────────────────────
                  _PublicRecordsCard(records: profile.allExerciseRecords),
                  const SizedBox(height: 12),

                  // ── Достижения ─────────────────────────────────────────
                  _PublicSectionCard(
                    title: 'Достижения',
                    icon: Icons.emoji_events_rounded,
                    iconColor: const Color(0xFFFFB300),
                    child: profile.recentAchievements.isEmpty
                        ? const _Hint('Достижений пока нет.')
                        : Column(
                            children: profile.recentAchievements
                                .map((a) => _AchievementRow(item: a))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Шапка публичного профиля
// ─────────────────────────────────────────────────────────────────

class _PublicProfileHeader extends StatelessWidget {
  const _PublicProfileHeader({required this.profile});

  final ProgressionProfileData profile;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                radius: 34,
                avatarUrl: profile.avatarUrl,
                fallbackText: profile.avatarText,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
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
          const SizedBox(height: 6),
          Text(
            '${profile.xpInLevel} / ${profile.xpToDisplay} XP',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
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
// Метрики (горизонтальная строка из 3 тайлов)
// ─────────────────────────────────────────────────────────────────

class _PublicMetricsRow extends StatelessWidget {
  const _PublicMetricsRow({required this.profile});

  final ProgressionProfileData profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final items = [
      (
        label: 'Тренировок',
        value: '${profile.totalCompletedWorkouts}',
        color: null as Color?,
      ),
      (
        label: 'Эта неделя',
        value: '${profile.currentWeek.workoutCount} трен.',
        color: profile.currentWeek.isIdeal ? scheme.tertiary : null,
      ),
      (
        label: 'Стрик',
        value: '${profile.currentStreak} нед.',
        color: profile.currentStreak >= 2 ? scheme.secondary : null,
      ),
    ];

    return Row(
      children: items
          .map((item) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: item == items.last ? 0 : 8,
                  ),
                  child: DashboardCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    color: item.color != null
                        ? Color.alphaBlend(
                            item.color!.withValues(alpha: 0.08),
                            scheme.surfaceContainerLow,
                          )
                        : null,
                    borderColor: item.color?.withValues(alpha: 0.25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.value,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: item.color ?? scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Секция-карточка
// ─────────────────────────────────────────────────────────────────

class _PublicSectionCard extends StatelessWidget {
  const _PublicSectionCard({
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
                  child: Icon(icon, size: 18,
                      color: iconColor ?? scheme.secondary),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
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
// Рекорды с вкладками Вес / Объём
// ─────────────────────────────────────────────────────────────────

class _PublicRecordsCard extends StatefulWidget {
  const _PublicRecordsCard({required this.records});

  final List<ExerciseRecordData> records;

  @override
  State<_PublicRecordsCard> createState() => _PublicRecordsCardState();
}

class _PublicRecordsCardState extends State<_PublicRecordsCard> {
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
                      color: scheme.tertiary,
                      onTap: () => setState(() => _showWeight = true),
                    ),
                    const SizedBox(width: 3),
                    _TabChip(
                      label: 'Объём',
                      active: !_showWeight,
                      color: scheme.tertiary,
                      onTap: () => setState(() => _showWeight = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (records.isEmpty)
            _Hint(_showWeight
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
                itemBuilder: (context, i) =>
                    _RecordRow(item: records[i], showWeight: _showWeight),
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
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
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
          color: active ? color : Colors.transparent,
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
// Строки списков
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
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(item.code), size: 18,
                color: const Color(0xFFFFB300)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(formatShortDate(item.achievedAt),
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
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
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.tertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.trending_up_rounded, size: 18,
                color: scheme.tertiary),
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
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MicroChip(label: label, color: scheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      formatWeight(value),
                      style: textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${formatShortDate(item.updatedAt)}',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
    );
  }
}
