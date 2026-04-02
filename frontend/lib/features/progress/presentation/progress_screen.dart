import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../application/progress_analysis_service.dart';
import '../domain/progress_models.dart';

// ── Decision styling ────────────────────────────────────────────────────────

const _colorIncrease = Color(0xFF2E7D32);
const _colorAttention = Color(0xFFE65100);
const _colorKeep = Color(0xFF546E7A);

Color _decisionColor(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) { return _colorIncrease; }
  if (a.decision == ProgressDecision.decrease ||
      a.decision == ProgressDecision.insufficientData ||
      a.isStalled) { return _colorAttention; }
  return _colorKeep;
}

int _decisionPriority(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) { return 0; }
  if (a.decision == ProgressDecision.decrease ||
      a.decision == ProgressDecision.insufficientData ||
      a.isStalled) { return 1; }
  return 2;
}

// ── Screen ──────────────────────────────────────────────────────────────────

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const _service = ProgressAnalysisService();

  late Future<ProgressAnalysisReport> _future;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<ProgressAnalysisReport> _loadData() async {
    final workouts = await _loadWorkouts();
    final templates = await _loadTemplates();
    return _service.buildReport(workouts: workouts, templates: templates);
  }

  Future<List<Map<String, dynamic>>> _loadWorkouts() async {
    try {
      return await BackendApi.getWorkouts();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadTemplates() async {
    try {
      return await BackendApi.getTemplates();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.templatesCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
      return const [];
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadData());
    await _future;
  }

  List<ExerciseProgressAnalysis> _sorted(ProgressAnalysisReport report) {
    return List<ExerciseProgressAnalysis>.from(report.allExercises)
      ..sort((a, b) {
        final p = _decisionPriority(a) - _decisionPriority(b);
        if (p != 0) return p;
        return a.exerciseName.compareTo(b.exerciseName);
      });
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: FutureBuilder<ProgressAnalysisReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  BackendApi.describeError(
                    snapshot.error!,
                    fallback: 'Не удалось загрузить прогресс.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final report = snapshot.data ??
              const ProgressAnalysisReport(
                readyToIncrease: [],
                keepWorking: [],
                attentionNeeded: [],
                allExercises: [],
              );

          final query = _searchController.text.trim().toLowerCase();
          final sorted = _sorted(report);
          final exercises = query.isEmpty
              ? sorted
              : sorted
                  .where((a) =>
                      a.exerciseName.toLowerCase().contains(query))
                  .toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                DashboardSummaryCard(
                  subtitle: 'Аналитический обзор',
                  title: 'Что делать дальше',
                  bottom: _buildSummaryChips(report),
                ),
                const SizedBox(height: 14),
                AppSearchField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  hintText: 'Поиск упражнения',
                ),
                const SizedBox(height: 12),
                if (report.allExercises.isEmpty)
                  DashboardCard(
                    child: Text(
                      'Недостаточно истории. Добавьте несколько тренировок с весом и повторениями.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                else if (exercises.isEmpty)
                  DashboardCard(
                    child: Text(
                      'По запросу ничего не найдено.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                else
                  ...exercises.map(
                    (analysis) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExerciseDetailCard(analysis: analysis),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget? _buildSummaryChips(ProgressAnalysisReport report) {
    final ready = report.readyToIncrease.length;
    final attention = report.attentionNeeded.length;
    if (ready == 0 && attention == 0) return null;
    return Row(
      children: [
        if (ready > 0)
          StatusBadge(
            label: '$ready к росту',
            color: _colorIncrease,
            icon: Icons.trending_up_rounded,
            compact: true,
          ),
        if (ready > 0 && attention > 0) const SizedBox(width: 8),
        if (attention > 0)
          StatusBadge(
            label: '$attention корректировок',
            color: _colorAttention,
            icon: Icons.warning_amber_rounded,
            compact: true,
          ),
      ],
    );
  }
}

// ── Exercise card ────────────────────────────────────────────────────────────

class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({required this.analysis});

  final ExerciseProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _decisionColor(analysis);
    final latest = analysis.latestSession;
    final recentSessions = analysis.sessions.reversed.take(3).toList();

    final isIncrease = analysis.decision == ProgressDecision.increase;
    final isDecrease = analysis.decision == ProgressDecision.decrease;
    final isAttention = isDecrease ||
        analysis.decision == ProgressDecision.insufficientData ||
        analysis.isStalled;

    final weightPrefix = isIncrease
        ? '↑ '
        : (isDecrease ? '↓ ' : '');
    final weightColor =
        (isIncrease || isAttention) ? color : scheme.onSurface;
    final hasDelta = analysis.deltaWeight.abs() > 0.01;

    final subtitleParts = [
      '${analysis.repRange.label} повт',
      if (latest != null) formatShortDate(latest.performedAt),
      '${(analysis.confidenceScore * 100).round()}%',
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: scheme.surfaceContainerLow.withValues(alpha: 0.96),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.09),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Цветная левая полоска = статус упражнения
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: color),
              ),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.fromLTRB(22, 10, 14, 10),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(22, 0, 18, 18),
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              analysis.exerciseName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (latest != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  _InlineMetric(
                                    label: 'Норм.',
                                    value: '${_formatWeight(latest.workingSet.normalizedWeight)} кг',
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 14),
                                  _InlineMetric(
                                    label: '1ПМ',
                                    value: '${_formatWeight(latest.workingSet.estimated1rm)} кг',
                                    color: Theme.of(context).colorScheme.tertiary,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$weightPrefix${_formatWeight(analysis.recommendedNextWeight)} кг',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: weightColor,
                                ),
                          ),
                          if (hasDelta)
                            Text(
                              '${analysis.deltaWeight > 0 ? '+' : ''}${_formatWeight(analysis.deltaWeight)} кг',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitleParts.join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  children: [
                    Text(
                      analysis.reason,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    _CombinedProgressChart(sessions: analysis.sessions),
                    if (recentSessions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ...recentSessions.map(
                        (session) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${formatShortDate(session.performedAt)} · '
                                  '${_formatWeight(session.workingSet.weight)} кг'
                                  ' × ${session.workingSet.reps}',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '1ПМ ${_formatWeight(session.workingSet.estimated1rm)} кг',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inline metric label ──────────────────────────────────────────────────────

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

// ── Combined chart ───────────────────────────────────────────────────────────

class _CombinedProgressChart extends StatefulWidget {
  const _CombinedProgressChart({required this.sessions});
  final List<ExerciseSessionPerformance> sessions;

  @override
  State<_CombinedProgressChart> createState() =>
      _CombinedProgressChartState();
}

class _CombinedProgressChartState extends State<_CombinedProgressChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final colorNorm = Theme.of(context).colorScheme.primary;
    final color1rm = Theme.of(context).colorScheme.tertiary;
    final surfaceVariant =
        Theme.of(context).colorScheme.onSurfaceVariant;

    if (sessions.length < 2) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.25),
        ),
        child: Center(
          child: Text(
            'Мало данных для графика',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: surfaceVariant),
          ),
        ),
      );
    }

    final normValues =
        sessions.map((s) => s.workingSet.normalizedWeight).toList();
    final rmValues =
        sessions.map((s) => s.workingSet.estimated1rm).toList();
    final allValues = [...normValues, ...rmValues];
    final minY =
        allValues.reduce((a, b) => a < b ? a : b) * 0.94;
    final maxY =
        allValues.reduce((a, b) => a > b ? a : b) * 1.06;
    final yInterval = (maxY - minY) / 4;

    LineChartBarData buildLine({
      required List<double> values,
      required Color color,
    }) {
      final lastIndex = values.length - 1;
      return LineChartBarData(
        isCurved: true,
        curveSmoothness: 0.35,
        barWidth: 2.5,
        color: color,
        shadow: Shadow(
          color: color.withValues(alpha: 0.38),
          blurRadius: 10,
        ),
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) {
            final isTouched = _touchedIndex == index;
            final isLast = index == lastIndex;
            return FlDotCirclePainter(
              radius: isTouched ? 6.5 : (isLast ? 5.0 : 3.0),
              color: isLast && !isTouched
                  ? color
                  : color,
              strokeWidth: isTouched || isLast ? 2.5 : 1.5,
              strokeColor: Theme.of(context).colorScheme.surface,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.04),
            ],
          ),
        ),
        spots: List.generate(
          values.length,
          (i) => FlSpot(i.toDouble(), values[i]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorNorm.withValues(alpha: 0.06),
            color1rm.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 10),
            child: Row(
              children: [
                _ChartLegendItem(
                    color: colorNorm, label: 'Норм. вес'),
                const SizedBox(width: 18),
                _ChartLegendItem(color: color1rm, label: '1ПМ'),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  touchCallback: (event, response) {
                    final idx = response
                        ?.lineBarSpots?.firstOrNull?.spotIndex;
                    if (_touchedIndex != idx) {
                      setState(() => _touchedIndex = idx);
                    }
                  },
                  getTouchedSpotIndicator: (barData, spotIndexes) =>
                      spotIndexes
                          .map(
                            (_) => TouchedSpotIndicatorData(
                              FlLine(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.18),
                                strokeWidth: 1.5,
                                dashArray: [4, 4],
                              ),
                              const FlDotData(show: false),
                            ),
                          )
                          .toList(),
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Theme.of(context)
                        .colorScheme
                        .inverseSurface,
                    getTooltipItems: (spots) =>
                        spots.map((spot) {
                      final isNorm = spot.barIndex == 0;
                      return LineTooltipItem(
                        '${isNorm ? 'Норм' : '1ПМ'}: ${_formatWeight(spot.y)} кг',
                        TextStyle(
                          color: isNorm ? colorNorm : color1rm,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.07),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _formatWeight(value),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: surfaceVariant),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= sessions.length ||
                            value != value.roundToDouble()) {
                          return const SizedBox.shrink();
                        }
                        final showAll = sessions.length <= 5;
                        final isEdge = index == 0 ||
                            index == sessions.length - 1;
                        if (!showAll && !isEdge) {
                          return const SizedBox.shrink();
                        }
                        final d = sessions[index].performedAt;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${d.day}.${d.month.toString().padLeft(2, '0')}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: surfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  buildLine(values: normValues, color: colorNorm),
                  buildLine(values: rmValues, color: color1rm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

String _formatWeight(double value) => formatWeight(value);
