import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../coach/presentation/ai_coach_screen.dart';
import '../../heatmap/presentation/muscle_volume_view.dart';
import '../application/progress_analysis_service.dart';
import '../domain/progress_models.dart';
import '../domain/working_weight_trend.dart';
import '../../../core/utils/search.dart';

// ── Decision colors ──────────────────────────────────────────────────────────

const _colorIncrease = Color(0xFF2E7D32);
const _colorAttention = Color(0xFFE65100);
const _colorKeep = Color(0xFF546E7A);

bool _needsAttention(ExerciseProgressAnalysis a) =>
    a.decision == ProgressDecision.decrease ||
    a.decision == ProgressDecision.insufficientData ||
    a.isStalled;

Color _decisionColor(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) return _colorIncrease;
  if (_needsAttention(a)) return _colorAttention;
  return _colorKeep;
}

int _decisionPriority(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) return 0;
  if (_needsAttention(a)) return 1;
  return 2;
}

// ── Loaded data ──────────────────────────────────────────────────────────────

class _ProgressData {
  const _ProgressData({
    required this.report,
    required this.workouts,
    required this.catalog,
  });
  final ProgressAnalysisReport report;
  final List<Map<String, dynamic>> workouts;
  final List<Map<String, dynamic>> catalog;
}

// ── Stats ────────────────────────────────────────────────────────────────────

class _ProgressStats {
  const _ProgressStats({
    required this.totalExercises,
    required this.readyCount,
    required this.attentionCount,
    required this.keepCount,
  });

  final int totalExercises;
  final int readyCount;
  final int attentionCount;
  final int keepCount;
}

_ProgressStats _computeStats(ProgressAnalysisReport report) {
  return _ProgressStats(
    totalExercises: report.allExercises.length,
    readyCount: report.readyToIncrease.length,
    attentionCount: report.attentionNeeded.length,
    keepCount: report.keepWorking.length,
  );
}

// ── Filter tab ───────────────────────────────────────────────────────────────

enum _FilterTab { all, increase, keep, attention }

/// Вкладки экрана «Прогресс».
enum ProgressTab { recommendations, muscles }

// ── Screen ──────────────────────────────────────────────────────────────────

/// Единый экран прогресса: рекомендации по весам и объём по мышцам.
/// Рекорды — в профиле.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    this.initialTab = ProgressTab.recommendations,
  });

  final ProgressTab initialTab;

  @override
  State<ProgressScreen> createState() => ProgressScreenState();
}

class ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  static const _service = ProgressAnalysisService();

  late Future<_ProgressData> _future;
  // Общий комментарий коуча грузится отдельно и не блокирует экран.
  late Future<String> _summaryFuture;
  late final TabController _tabController = TabController(
    length: ProgressTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );
  final TextEditingController _searchController = TextEditingController();
  _FilterTab _activeFilter = _FilterTab.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _future = _loadData();
    _summaryFuture = _future.then((data) => _fetchSummary(data.report));
  }

  /// Перезагружает данные, например при переключении на вкладку в навигации.
  Future<void> refresh() async {
    setState(_reload);
    await _future;
  }

  Future<_ProgressData> _loadData() async {
    final results = await Future.wait([
      BackendApi.getWorkouts(),
      _loadOptional(BackendApi.getTemplates),
      _loadOptional(BackendApi.getExercises),
    ]);
    return _ProgressData(
      report: _service.buildReport(workouts: results[0], templates: results[1]),
      workouts: results[0],
      catalog: results[2],
    );
  }

  static Future<List<Map<String, dynamic>>> _loadOptional(
    Future<List<Map<String, dynamic>>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return const [];
    }
  }

  Future<String> _fetchSummary(ProgressAnalysisReport report) async {
    if (report.allExercises.isEmpty) return '';

    final cached = LocalCache.get<Map>(CacheKeys.progressInsightsCache);
    final cachedAt = cached?['cached_at'] as int?;
    if (cachedAt != null &&
        DateTime.now().millisecondsSinceEpoch - cachedAt <
            const Duration(hours: 24).inMilliseconds) {
      return (cached!['summary'] as String? ?? '').trim();
    }

    try {
      final exercises = report.allExercises
          .map((a) {
            final sessions = a.sessions.reversed
                .take(3)
                .map((s) => {
                      'date': s.performedAt.toIso8601String().split('T').first,
                      'weight': s.workingSet.weight,
                      'reps': s.workingSet.reps,
                      'estimated_1rm': s.workingSet.estimated1rm,
                    })
                .toList();
            final decisionKey = a.isStalled
                ? 'stalled'
                : switch (a.decision) {
                    ProgressDecision.increase => 'increase',
                    ProgressDecision.decrease => 'decrease',
                    ProgressDecision.keep => 'keep',
                    ProgressDecision.insufficientData => 'insufficient_data',
                  };
            return {
              'name': a.exerciseName,
              'decision': decisionKey,
              'rep_range': a.repRange.label,
              'recommended_weight': a.recommendedNextWeight,
              'delta_weight': a.deltaWeight,
              'confidence': a.confidenceScore,
              'sessions': sessions,
            };
          })
          .take(50)
          .toList();

      final result = await BackendApi.getProgressInsights(exercises);
      final summary = (result?['summary'] as String? ?? '').trim();
      await LocalCache.put(CacheKeys.progressInsightsCache, {
        'summary': summary,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      });
      return summary;
    } catch (_) {
      return '';
    }
  }

  List<ExerciseProgressAnalysis> _applyFilter(
      ProgressAnalysisReport report, String query) {
    final sorted = List<ExerciseProgressAnalysis>.from(report.allExercises)
      ..sort((a, b) {
        final p = _decisionPriority(a) - _decisionPriority(b);
        if (p != 0) return p;
        return a.exerciseName.compareTo(b.exerciseName);
      });
    final afterFilter = switch (_activeFilter) {
      _FilterTab.all => sorted,
      _FilterTab.increase =>
        sorted.where((a) => a.decision == ProgressDecision.increase).toList(),
      _FilterTab.keep => sorted
          .where((a) => a.decision == ProgressDecision.keep && !a.isStalled)
          .toList(),
      _FilterTab.attention => sorted.where(_needsAttention).toList(),
    };
    if (query.isEmpty) return afterFilter;
    return afterFilter
        .where((a) => normalizeForSearch(a.exerciseName).contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: ScreenHeader(title: 'Прогресс'),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _StyledTabBar(controller: _tabController),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<_ProgressData>(
              future: _future,
              builder: (context, snapshot) {
                // При обновлении показываем прежние данные, пока грузятся новые.
                if (snapshot.hasData) {
                  return _buildTabs(snapshot.data!);
                }
                if (!snapshot.hasError) {
                  return const Center(child: CircularProgressIndicator());
                }
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(_ProgressData data) {
    return TabBarView(
      controller: _tabController,
      children: [
        _RecommendationsTab(
          report: data.report,
          stats: _computeStats(data.report),
          summaryFuture: _summaryFuture,
          searchController: _searchController,
          activeFilter: _activeFilter,
          onFilterChanged: (tab) => setState(() {
            _activeFilter = tab;
            _searchController.clear();
          }),
          onSearchChanged: () => setState(() {}),
          applyFilter: _applyFilter,
          onRefresh: refresh,
        ),
        MuscleVolumeView(
          workouts: data.workouts,
          catalog: data.catalog,
          onRefresh: refresh,
        ),
      ],
    );
  }
}

// ── Styled tab bar ────────────────────────────────────────────────────────────

class _StyledTabBar extends StatelessWidget {
  const _StyledTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: scheme.primary,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
        unselectedLabelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        tabs: const [
          Tab(text: 'Веса'),
          Tab(text: 'Мышцы'),
        ],
      ),
    );
  }
}

// ── Recommendations tab ───────────────────────────────────────────────────────

class _RecommendationsTab extends StatelessWidget {
  const _RecommendationsTab({
    required this.report,
    required this.stats,
    required this.summaryFuture,
    required this.searchController,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.applyFilter,
    required this.onRefresh,
  });

  final ProgressAnalysisReport report;
  final _ProgressStats stats;
  final Future<String> summaryFuture;
  final TextEditingController searchController;
  final _FilterTab activeFilter;
  final ValueChanged<_FilterTab> onFilterChanged;
  final VoidCallback onSearchChanged;
  final List<ExerciseProgressAnalysis> Function(ProgressAnalysisReport, String)
      applyFilter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final query = normalizeForSearch(searchController.text);
    final exercises = applyFilter(report, query);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (stats.totalExercises > 0) ...[
            _DistributionBar(stats: stats),
            const SizedBox(height: 10),
          ],
          FutureBuilder<String>(
            future: summaryFuture,
            builder: (context, snapshot) {
              final summary = snapshot.data ?? '';
              if (summary.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AiSummaryCard(summary: summary),
              );
            },
          ),
          _CategoryFilter(
            active: activeFilter,
            stats: stats,
            onChanged: onFilterChanged,
          ),
          const SizedBox(height: 10),
          AppSearchField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
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
  }
}

// ── AI summary card ───────────────────────────────────────────────────────────

class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.summary});
  final String summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DashboardCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AiCoachScreen()),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Коуч говорит',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Спросить коуча →',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
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

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({required this.stats});
  final _ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = stats.totalExercises;
    if (total == 0) return const SizedBox.shrink();

    return DashboardCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats.attentionCount > 0) ...[
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                children: [
                  TextSpan(
                    text: '${stats.attentionCount} упражнений',
                    style: const TextStyle(
                      color: _colorAttention,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' давно не прогрессируют — пора добавить нагрузку или сменить схему.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            'РАСПРЕДЕЛЕНИЕ',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (stats.readyCount > 0)
                    Flexible(
                      flex: stats.readyCount,
                      child: Container(color: _colorIncrease),
                    ),
                  if (stats.keepCount > 0) ...[
                    if (stats.readyCount > 0)
                      Container(width: 2, color: scheme.surface),
                    Flexible(
                      flex: stats.keepCount,
                      child: Container(color: _colorKeep),
                    ),
                  ],
                  if (stats.attentionCount > 0) ...[
                    if (stats.readyCount > 0 || stats.keepCount > 0)
                      Container(width: 2, color: scheme.surface),
                    Flexible(
                      flex: stats.attentionCount,
                      child: Container(color: _colorAttention),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (stats.readyCount > 0) ...[
                _DistLegend(
                    color: _colorIncrease,
                    label: '${stats.readyCount} к росту'),
                const SizedBox(width: 14),
              ],
              if (stats.keepCount > 0) ...[
                _DistLegend(
                    color: _colorKeep, label: '${stats.keepCount} норма'),
                const SizedBox(width: 14),
              ],
              if (stats.attentionCount > 0)
                _DistLegend(
                    color: _colorAttention,
                    label: '${stats.attentionCount} застой'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistLegend extends StatelessWidget {
  const _DistLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ── Category filter ───────────────────────────────────────────────────────────

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.active,
    required this.stats,
    required this.onChanged,
  });

  final _FilterTab active;
  final _ProgressStats stats;
  final ValueChanged<_FilterTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'Все',
            count: stats.totalExercises,
            isActive: active == _FilterTab.all,
            onTap: () => onChanged(_FilterTab.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'К росту',
            count: stats.readyCount,
            isActive: active == _FilterTab.increase,
            activeColor: _colorIncrease,
            onTap: () => onChanged(_FilterTab.increase),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Держим',
            count: stats.keepCount,
            isActive: active == _FilterTab.keep,
            activeColor: _colorKeep,
            onTap: () => onChanged(_FilterTab.keep),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Застой',
            count: stats.attentionCount,
            isActive: active == _FilterTab.attention,
            activeColor: _colorAttention,
            onTap: () => onChanged(_FilterTab.attention),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
    this.activeColor,
  });

  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = activeColor ?? scheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isActive
              ? color.withValues(alpha: 0.18)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: isActive
                ? color.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isActive ? color : scheme.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive
                    ? color.withValues(alpha: 0.28)
                    : scheme.outlineVariant.withValues(alpha: 0.22),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isActive ? color : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Record card ───────────────────────────────────────────────────────────────

/// Карточка упражнения: рабочий вес, как он изменился за месяц и график
/// сразу. Расчётный максимум и разбор — по нажатию.
class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({required this.analysis});
  final ExerciseProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = _decisionColor(analysis);
    final history =
        analysis.history.isNotEmpty ? analysis.history : analysis.sessions;
    final latest = history.isEmpty ? null : history.last;
    final change = workingWeightChange(history);
    final recentSessions = history.reversed.take(3).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Color.alphaBlend(
            scheme.secondary.withValues(alpha: 0.07),
            scheme.surfaceContainerLow,
          ),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.22)),
        ),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
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
                  tilePadding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(20, 0, 18, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              analysis.exerciseName,
                              style: textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _DecisionChip(analysis: analysis, color: color),
                        ],
                      ),
                      if (latest != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${_formatWeight(latest.workingSet.weight)} кг',
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '× ${latest.workingSet.reps}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            if (change != null)
                              _MonthChange(delta: change.delta),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _WorkingWeightChart(sessions: chartSessions(history)),
                      ],
                    ],
                  ),
                  children: [
                    Text(
                      analysis.reason,
                      style: textTheme.bodyMedium,
                    ),
                    if (latest != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Расчётный максимум на 1 раз',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Text(
                            // Оценка — точнее 0,5 кг не бывает.
                            '${_formatWeight((latest.workingSet.estimated1rm * 2).round() / 2)} кг',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (recentSessions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final session in recentSessions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  formatShortDate(session.performedAt),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                '${_formatWeight(session.workingSet.weight)} кг'
                                ' × ${session.workingSet.reps}',
                                style: textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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

/// Что делать в следующий раз: «пора +2.5 кг», «держим вес», «застой»,
/// «снизить до 60 кг», «мало данных».
class _DecisionChip extends StatelessWidget {
  const _DecisionChip({required this.analysis, required this.color});

  final ExerciseProgressAnalysis analysis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = switch (analysis.decision) {
      ProgressDecision.increase =>
        'пора +${_formatWeight(analysis.deltaWeight)} кг',
      ProgressDecision.decrease =>
        'снизить до ${_formatWeight(analysis.recommendedNextWeight)} кг',
      ProgressDecision.insufficientData => 'мало данных',
      ProgressDecision.keep => analysis.isStalled ? 'застой' : 'держим вес',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _MonthChange extends StatelessWidget {
  const _MonthChange({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final flat = delta.abs() < 0.01;
    final up = delta > 0;
    final color = flat
        ? scheme.onSurfaceVariant
        : up
            ? _colorIncrease
            : _colorAttention;
    final value = flat
        ? 'без изменений'
        : '${up ? '+' : '−'}${_formatWeight(delta.abs())} кг';
    return Text(
      '$value за месяц',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// ── Working weight chart ──────────────────────────────────────────────────────

/// Рабочий вес по тренировкам: точка — самый тяжёлый подход дня.
class _WorkingWeightChart extends StatelessWidget {
  const _WorkingWeightChart({required this.sessions});
  final List<ExerciseSessionPerformance> sessions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    if (sessions.length < 2) {
      return SizedBox(
        height: 28,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'График появится после второй тренировки',
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(color: muted),
          ),
        ),
      );
    }

    final weights = sessions.map((s) => s.workingSet.weight).toList();
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final padding =
        maxWeight == minWeight ? 5.0 : (maxWeight - minWeight) * 0.2;
    final color = scheme.primary;
    final lastIndex = sessions.length - 1;
    String dayLabel(DateTime d) =>
        '${d.day}.${d.month.toString().padLeft(2, '0')}';

    return SizedBox(
      height: 96,
      child: LineChart(
        LineChartData(
          minY: minWeight - padding,
          maxY: maxWeight + padding,
          minX: 0,
          maxX: lastIndex.toDouble(),
          clipData: const FlClipData.none(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => spots.map((spot) {
                final session = sessions[spot.spotIndex];
                return LineTooltipItem(
                  '${dayLabel(session.performedAt)}: '
                  '${_formatWeight(session.workingSet.weight)} × '
                  '${session.workingSet.reps}',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (value != value.roundToDouble() ||
                      (index != 0 && index != lastIndex)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dayLabel(sessions[index].performedAt),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: muted, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: false,
              barWidth: 2.5,
              color: color,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: index == lastIndex ? 4.5 : 2.5,
                  color: color,
                  strokeWidth: index == lastIndex ? 2 : 0,
                  strokeColor: scheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.22),
                    color.withValues(alpha: 0.02),
                  ],
                ),
              ),
              spots: [
                for (var i = 0; i < weights.length; i++)
                  FlSpot(i.toDouble(), weights[i]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatWeight(double value) => formatWeight(value);
