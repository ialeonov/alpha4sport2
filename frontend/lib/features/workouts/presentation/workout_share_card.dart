import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/utils/formatters.dart';
import '../../workouts/domain/workout_metrics.dart';

// ── User data passed into the card ───────────────────────────────────────────

class ShareUserInfo {
  const ShareUserInfo({
    this.displayName,
    this.resolvedAvatarUrl,
    this.totalWorkouts,
  });

  final String? displayName;

  /// Full resolved URL (http/https), ready for Image.network.
  final String? resolvedAvatarUrl;

  final int? totalWorkouts;

  String get initials {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String get levelLabel {
    final n = totalWorkouts ?? 0;
    if (n < 10) return 'Новичок';
    if (n < 30) return 'Атлет';
    if (n < 75) return 'Ветеран';
    return 'Мастер';
  }
}

// ── Main card widget ──────────────────────────────────────────────────────────

/// Fixed-size branded share card: 540×960 logical px (→ 1080×1920 at pixelRatio 2.0).
/// All async work must be done by the caller; this widget is fully synchronous.
class WorkoutShareCard extends StatelessWidget {
  const WorkoutShareCard({
    super.key,
    required this.workout,
    required this.coloredSvgSource,
    this.userInfo,
    this.records = const [],
  });

  final Map<String, dynamic> workout;
  final String coloredSvgSource;
  final ShareUserInfo? userInfo;
  final List<String> records;

  static const double cardWidth = 540.0;
  static const double cardHeight = 960.0;

  // ── Brand palette (matches logo: #161D27 bg / #FDEFD8 cream) ────────
  static const _bg1 = Color(0xFF161D27);
  static const _bg2 = Color(0xFF1C3848);
  static const _bg3 = Color(0xFF14222F);
  static const _accent = Color(0xFF74C2CB);
  static const _warm = Color(0xFFFDEFD8);
  static const _sage = Color(0xFFADC58C);
  static const _textPrimary = Color(0xFFFDEFD8);
  static const _textSecondary = Color(0xFF7FA0AE);
  static const _surface = Color(0x18FFFFFF);
  static const _divider = Color(0x1AFFFFFF);
  static const _recordGold = Color(0xFFFFD166);

  @override
  Widget build(BuildContext context) {
    final name = (workout['name'] ?? 'Тренировка').toString();
    final startedAt = _parseDateTime(workout['started_at']);
    final finishedAt = _parseDateTime(workout['finished_at']);
    final exercises =
        (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final tonnage = calculateWorkoutTonnage(workout);
    final durationMin = _durationMinutes(startedAt, finishedAt);
    final info = userInfo;

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bg1, _bg2, _bg3],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative blobs
            Positioned(
              top: -80,
              right: -60,
              child: _Blob(300, _accent.withValues(alpha: 0.07)),
            ),
            Positioned(
              top: 320,
              left: -110,
              child: _Blob(240, _warm.withValues(alpha: 0.04)),
            ),
            Positioned(
              bottom: 80,
              right: -70,
              child: _Blob(200, _sage.withValues(alpha: 0.05)),
            ),
            // ── Content ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 36),

                  // ── Logo (SVG, transparent bg, full width) ─────────
                  // AspectRatio ensures correct height from SVG viewBox 863:190
                  AspectRatio(
                    aspectRatio: 863 / 190,
                    child: SvgPicture.asset(
                      'assets/branding/head.svg',
                      fit: BoxFit.fill,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── User row ───────────────────────────────────────
                  if (info != null) ...[
                    _buildUserRow(info),
                    const SizedBox(height: 14),
                  ],

                  // ── Workout title + date/duration ──────────────────
                  _buildHero(name, startedAt, durationMin),

                  const SizedBox(height: 16),

                  // ── Stats ──────────────────────────────────────────
                  _buildStats(exercises.length, tonnage, durationMin),

                  const SizedBox(height: 16),

                  // ── Exercise list ──────────────────────────────────
                  _buildSectionLabel('УПРАЖНЕНИЯ'),
                  const SizedBox(height: 8),
                  _buildExerciseList(exercises),

                  // ── Spacer pushes heatmap to bottom ───────────────
                  const Expanded(child: SizedBox()),

                  // ── Heatmap (pinned to bottom) ─────────────────────
                  _buildSectionLabel('КАРТА НАГРУЗКИ'),
                  const SizedBox(height: 10),
                  _buildHeatmap(),

                  const SizedBox(height: 14),

                  // ── Footer ─────────────────────────────────────────
                  _buildFooter(),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── User row ──────────────────────────────────────────────────────────

  Widget _buildUserRow(ShareUserInfo info) {
    return Row(
      children: [
        // Avatar
        _buildAvatar(info),
        const SizedBox(width: 12),
        // Name + level
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info.displayName != null && info.displayName!.isNotEmpty)
                Text(
                  info.displayName!,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (info.totalWorkouts != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Text(
                        info.levelLabel,
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${info.totalWorkouts} тренировок',
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(ShareUserInfo info) {
    const size = 38.0;
    final url = info.resolvedAvatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(info.initials, size),
        ),
      );
    }
    return _avatarFallback(info.initials, size);
  }

  Widget _avatarFallback(String initials, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _accent.withValues(alpha: 0.18),
        border: Border.all(color: _accent.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: _accent,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────

  Widget _buildHero(String name, DateTime? startedAt, int? durationMin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.toUpperCase(),
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            if (startedAt != null) ...[
              const Icon(Icons.calendar_today_rounded,
                  size: 11, color: _textSecondary),
              const SizedBox(width: 4),
              Text(
                _formatDate(startedAt),
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (durationMin != null && durationMin > 0) ...[
              const SizedBox(width: 12),
              Container(
                width: 2,
                height: 2,
                decoration: const BoxDecoration(
                  color: _textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.timer_rounded,
                  size: 11, color: _textSecondary),
              const SizedBox(width: 4),
              Text(
                '$durationMin мин',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Stats row (3 equal cells) ─────────────────────────────────────────

  Widget _buildStats(int exerciseCount, double tonnage, int? durationMin) {
    final items = <_StatItem>[
      _StatItem('$exerciseCount', 'упражнений'),
      if (tonnage > 0) _StatItem(formatTonnage(tonnage), 'тоннаж'),
      if (durationMin != null && durationMin > 0)
        _StatItem('$durationMin', 'минут'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _buildStatCell(items[i])),
        ],
      ],
    );
  }

  Widget _buildStatCell(_StatItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.value,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Container(width: 2.5, height: 11, color: _accent),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Divider(color: _divider, thickness: 1, height: 1),
        ),
      ],
    );
  }

  // ── Exercise list (up to 10, ultra-compact) ───────────────────────────

  Widget _buildExerciseList(List<dynamic> exercises) {
    final shown = exercises.take(10).toList();
    final remaining = exercises.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(color: _divider, thickness: 1, height: 8),
          _buildExerciseRow(shown[i] as Map),
        ],
        if (remaining > 0) ...[
          const Divider(color: _divider, thickness: 1, height: 8),
          Text(
            '+ ещё $remaining',
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExerciseRow(Map exercise) {
    final name = (exercise['exercise_name'] ?? '').toString();
    final sets = (exercise['sets'] as List?)?.cast<dynamic>() ?? const [];
    final setCount = sets.where((s) {
      final reps = (s as Map?)?['reps'];
      return reps is num && reps > 0;
    }).length;
    final maxWeight = sets.fold<double>(0, (max, s) {
      final w = (s as Map?)?['weight'];
      if (w is num && w.toDouble() > max) return w.toDouble();
      return max;
    });

    final weightLabel = maxWeight > 0 ? '${formatWeight(maxWeight)} кг' : 'б/в';
    final setsLabel = setCount > 0 ? '$setCount×$weightLabel' : weightLabel;
    final isRecord = records.contains(name);

    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (isRecord)
          Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _recordGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: _recordGold.withValues(alpha: 0.35)),
            ),
            child: const Text(
              'РЕК',
              style: TextStyle(
                color: _recordGold,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        Text(
          setsLabel,
          style: const TextStyle(
            color: _accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Heatmap (pinned to bottom via Expanded above) ─────────────────────

  Widget _buildHeatmap() {
    return SizedBox(
      height: 200,
      child: Center(
        child: AspectRatio(
          aspectRatio: 597.8 / 608.2,
          child: SvgPicture.string(coloredSvgSource, fit: BoxFit.contain),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Фитнес трекер · Подсказки по тренировкам',
          style: TextStyle(
            color: _textSecondary.withValues(alpha: 0.45),
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Text(
          'fit.ileonov.ru',
          style: TextStyle(
            color: _textSecondary.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  int? _durationMinutes(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final diff = end.difference(start);
    return diff.isNegative ? null : diff.inMinutes;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Blob extends StatelessWidget {
  const _Blob(this.diameter, this.color);
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _StatItem {
  const _StatItem(this.value, this.label);
  final String value;
  final String label;
}
