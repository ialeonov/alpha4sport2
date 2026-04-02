import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/utils/formatters.dart';
import '../../workouts/domain/workout_metrics.dart';

/// Fixed-size branded share card: 540×960 logical px (renders as 1080×1920 at pixelRatio 2.0).
///
/// All async work (heatmap coloring, asset loading) must be done by the
/// caller — this widget is fully synchronous so RepaintBoundary can capture
/// it reliably.
class WorkoutShareCard extends StatelessWidget {
  const WorkoutShareCard({
    super.key,
    required this.workout,
    required this.coloredSvgSource,
    this.topMuscleLabels = const [],
    this.records = const [],
  });

  final Map<String, dynamic> workout;

  /// Pre-colorized SVG string (output of BodySvgColorizer).
  final String coloredSvgSource;

  /// Up to 3 top muscle group labels, shown in the heatmap section.
  final List<String> topMuscleLabels;

  /// Exercise names that hit a personal record — shown with a gold badge.
  final List<String> records;

  static const double cardWidth = 540.0;
  static const double cardHeight = 960.0;

  // ── Brand palette (hardcoded — independent of app Theme) ────────────
  static const _bg1 = Color(0xFF0B141E);
  static const _bg2 = Color(0xFF173545);
  static const _bg3 = Color(0xFF0F2030);
  static const _accent = Color(0xFF74C2CB); // teal
  static const _warm = Color(0xFFE8C7AA); // cream
  static const _sage = Color(0xFFADC58C); // green accent
  static const _textPrimary = Color(0xFFF5F1EC);
  static const _textSecondary = Color(0xFF8FA8B4);
  static const _surface = Color(0x1AFFFFFF); // 10% white
  static const _divider = Color(0x25FFFFFF);
  static const _recordGold = Color(0xFFFFD166);

  @override
  Widget build(BuildContext context) {
    final name = (workout['name'] ?? 'Тренировка').toString();
    final startedAt = _parseDateTime(workout['started_at']);
    final finishedAt = _parseDateTime(workout['finished_at']);
    final exercises = (workout['exercises'] as List?)?.cast<dynamic>() ?? const [];
    final tonnage = calculateWorkoutTonnage(workout);
    final durationMin = _durationMinutes(startedAt, finishedAt);

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bg1, _bg2, _bg3],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative blobs
            Positioned(
              top: -90,
              right: -70,
              child: _Blob(diameter: 300, color: _accent.withValues(alpha: 0.08)),
            ),
            Positioned(
              top: 280,
              left: -120,
              child: _Blob(diameter: 260, color: _warm.withValues(alpha: 0.05)),
            ),
            Positioned(
              bottom: 120,
              right: -80,
              child: _Blob(diameter: 220, color: _sage.withValues(alpha: 0.06)),
            ),
            // Main content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 56),
                  _buildHeader(),
                  const SizedBox(height: 36),
                  _buildHero(name, startedAt, durationMin),
                  const SizedBox(height: 28),
                  _buildStatsRow(exercises.length, tonnage, durationMin),
                  const SizedBox(height: 32),
                  _buildSectionLabel('УПРАЖНЕНИЯ'),
                  const SizedBox(height: 14),
                  _buildExerciseList(exercises),
                  const SizedBox(height: 28),
                  _buildSectionLabel('КАРТА НАГРУЗКИ'),
                  const SizedBox(height: 14),
                  _buildHeatmapRow(),
                  const Expanded(child: SizedBox()),
                  _buildFooter(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        // Logo (PNG — reliable for off-screen rendering)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/branding/logo-full.png',
            width: 38,
            height: 38,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(width: 38, height: 38),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'alpha4sport',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _accent.withValues(alpha: 0.3), width: 1),
          ),
          child: const Text(
            'тренировка',
            style: TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero (name + date) ───────────────────────────────────────────────

  Widget _buildHero(String name, DateTime? startedAt, int? durationMin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.toUpperCase(),
          style: const TextStyle(
            color: _warm,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            height: 1.1,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (startedAt != null) ...[
              _Pill(
                icon: Icons.calendar_today_rounded,
                label: _formatDate(startedAt),
                color: _accent,
              ),
              const SizedBox(width: 10),
            ],
            if (durationMin != null && durationMin > 0)
              _Pill(
                icon: Icons.timer_rounded,
                label: '$durationMin мин',
                color: _textSecondary,
              ),
          ],
        ),
      ],
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────

  Widget _buildStatsRow(int exerciseCount, double tonnage, int? durationMin) {
    final items = <_StatItem>[
      _StatItem(value: '$exerciseCount', label: 'упражнений'),
      if (tonnage > 0) _StatItem(value: formatTonnage(tonnage), label: 'тоннаж'),
      if (durationMin != null && durationMin > 0)
        _StatItem(value: '$durationMin', label: 'минут'),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) _StatDivider(),
          Flexible(child: _buildStatCell(items[i])),
        ],
      ],
    );
  }

  Widget _buildStatCell(_StatItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Column(
        children: [
          Text(
            item.value,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: _accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(color: _divider, thickness: 1, height: 1),
        ),
      ],
    );
  }

  // ── Exercise list ────────────────────────────────────────────────────

  Widget _buildExerciseList(List<dynamic> exercises) {
    // Cap at 6 to keep the card from overflowing
    final shown = exercises.take(6).toList();
    final remaining = exercises.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0)
            const Divider(color: _divider, thickness: 1, height: 12),
          _buildExerciseRow(shown[i] as Map),
        ],
        if (remaining > 0) ...[
          const Divider(color: _divider, thickness: 1, height: 12),
          Text(
            '+ ещё $remaining упражнений',
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
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
      if (w is num && w > max) return w.toDouble();
      return max;
    });

    final setLabel = setCount > 0 ? '$setCount×' : '';
    final weightLabel = maxWeight > 0 ? formatWeight(maxWeight) + ' кг' : 'б/в';
    final isRecord = records.contains(name);

    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        if (isRecord)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _recordGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _recordGold.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'РЕК',
                style: TextStyle(
                  color: _recordGold,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        Text(
          '$setLabel$weightLabel',
          style: const TextStyle(
            color: _accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Heatmap ──────────────────────────────────────────────────────────

  Widget _buildHeatmapRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // SVG body diagram
        SizedBox(
          width: 160,
          child: AspectRatio(
            aspectRatio: 597.8 / 608.2,
            child: SvgPicture.string(coloredSvgSource, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 24),
        // Muscle labels
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Основная нагрузка',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              if (topMuscleLabels.isEmpty)
                const Text(
                  'Нет данных',
                  style: TextStyle(color: _textSecondary, fontSize: 13),
                )
              else
                for (var i = 0; i < topMuscleLabels.take(3).length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _muscleColor(i),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          topMuscleLabels[i],
                          style: TextStyle(
                            color: _textPrimary.withValues(alpha: 0.85 - i * 0.15),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Color _muscleColor(int index) {
    const colors = [_warm, _accent, _sage];
    return colors[index % colors.length];
  }

  // ── Footer ───────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _divider, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Сгенерировано в alpha4sport',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

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

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Blob extends StatelessWidget {
  const _Blob({required this.diameter, required this.color});
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

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 8);
  }
}

class _StatItem {
  const _StatItem({required this.value, required this.label});
  final String value;
  final String label;
}
