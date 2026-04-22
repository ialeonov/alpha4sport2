import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../application/progress_analysis_service.dart';
import '../domain/progress_models.dart';

// ── Decision colors ──────────────────────────────────────────────────────────

const _colorIncrease = Color(0xFF2E7D32);
const _colorAttention = Color(0xFFE65100);
const _colorKeep = Color(0xFF546E7A);

Color _decisionColor(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) return _colorIncrease;
  if (a.decision == ProgressDecision.decrease ||
      a.decision == ProgressDecision.insufficientData ||
      a.isStalled) return _colorAttention;
  return _colorKeep;
}

int _decisionPriority(ExerciseProgressAnalysis a) {
  if (a.decision == ProgressDecision.increase) return 0;
  if (a.decision == ProgressDecision.decrease ||
      a.decision == ProgressDecision.insufficientData ||
      a.isStalled) return 1;
  return 2;
}

// ── Combined load result ─────────────────────────────────────────────────────

class _ProgressData {
  const _ProgressData({required this.report, required this.muscleMap});
  final ProgressAnalysisReport report;
  // exerciseName.toLowerCase() → primary_muscle
  final Map<String, String> muscleMap;
}

// ── Stats ────────────────────────────────────────────────────────────────────

class _ProgressStats {
  const _ProgressStats({
    required this.totalExercises,
    required this.totalWorkouts,
    required this.readyCount,
    required this.attentionCount,
    required this.keepCount,
    required this.overallTrendPct,
  });

  final int totalExercises;
  final int totalWorkouts;
  final int readyCount;
  final int attentionCount;
  final int keepCount;
  final double overallTrendPct;
}

_ProgressStats _computeStats(ProgressAnalysisReport report) {
  final allDates = <String>{};
  var trendSum = 0.0;
  var trendCount = 0;
  for (final ex in report.allExercises) {
    for (final s in ex.sessions) {
      allDates.add(
          '${s.performedAt.year}-${s.performedAt.month}-${s.performedAt.day}');
    }
    if (ex.sessions.length >= 2) {
      final first = ex.sessions.first.workingSet.estimated1rm;
      final last = ex.sessions.last.workingSet.estimated1rm;
      if (first > 0) {
        trendSum += (last - first) / first * 100;
        trendCount++;
      }
    }
  }
  return _ProgressStats(
    totalExercises: report.allExercises.length,
    totalWorkouts: allDates.length,
    readyCount: report.readyToIncrease.length,
    attentionCount: report.attentionNeeded.length,
    keepCount: report.keepWorking.length,
    overallTrendPct: trendCount > 0 ? trendSum / trendCount : 0,
  );
}

// ── Top growth ───────────────────────────────────────────────────────────────

class _ExerciseGrowth {
  const _ExerciseGrowth({
    required this.name,
    required this.growthPct,
    required this.firstRm,
    required this.lastRm,
    required this.sessionCount,
  });
  final String name;
  final double growthPct;
  final double firstRm;
  final double lastRm;
  final int sessionCount;
}

List<_ExerciseGrowth> _computeTopGrowth(ProgressAnalysisReport report,
    {int count = 3}) {
  final list = <_ExerciseGrowth>[];
  for (final ex in report.allExercises) {
    if (ex.sessions.length < 2) continue;
    final first = ex.sessions.first.workingSet.estimated1rm;
    final last = ex.sessions.last.workingSet.estimated1rm;
    if (first <= 0) continue;
    final pct = (last - first) / first * 100;
    if (pct <= 0) continue;
    list.add(_ExerciseGrowth(
      name: ex.exerciseName,
      growthPct: pct,
      firstRm: first,
      lastRm: last,
      sessionCount: ex.sessions.length,
    ));
  }
  list.sort((a, b) => b.growthPct.compareTo(a.growthPct));
  return list.take(count).toList();
}

// ── Personal records ─────────────────────────────────────────────────────────

class _RecordEntry {
  const _RecordEntry({
    required this.rm1,
    required this.weight,
    required this.reps,
    required this.date,
  });
  final double rm1;
  final double weight;
  final int reps;
  final DateTime date;
}

class _ExerciseRecords {
  const _ExerciseRecords({required this.name, required this.history});
  final String name;
  // history[0] = current record, history[1..2] = previous PRs
  final List<_RecordEntry> history;
}

List<_ExerciseRecords> _computeRecords(ProgressAnalysisReport report) {
  final result = <_ExerciseRecords>[];
  for (final ex in report.allExercises) {
    if (ex.sessions.isEmpty) continue;
    final prs = <_RecordEntry>[];
    double maxWeight = 0;
    for (final s in ex.sessions) {
      final w = s.workingSet.weight;
      if (w > maxWeight) {
        maxWeight = w;
        prs.add(_RecordEntry(
          rm1: s.workingSet.estimated1rm,
          weight: w,
          reps: s.workingSet.reps,
          date: s.performedAt,
        ));
      }
    }
    if (prs.isEmpty) continue;
    final recent = prs.reversed.take(3).toList();
    result.add(_ExerciseRecords(name: ex.exerciseName, history: recent));
  }
  result.sort((a, b) => b.history.first.date.compareTo(a.history.first.date));
  return result;
}

// ── Filter tab ───────────────────────────────────────────────────────────────

enum _FilterTab { all, increase, keep, attention }

// ── Screen ──────────────────────────────────────────────────────────────────

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  static const _service = ProgressAnalysisService();

  late Future<_ProgressData> _future;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  _FilterTab _activeFilter = _FilterTab.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _future = _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<_ProgressData> _loadData() async {
    final results = await Future.wait([
      _loadWorkouts(),
      _loadTemplates(),
      _loadCatalog(),
    ]);
    final workouts = results[0] as List<Map<String, dynamic>>;
    final templates = results[1] as List<Map<String, dynamic>>;
    final catalog = results[2] as List<Map<String, dynamic>>;

    final report =
        _service.buildReport(workouts: workouts, templates: templates);
    final muscleMap = {
      for (final ex in catalog)
        (ex['name'] as String? ?? '').trim().toLowerCase():
            (ex['primary_muscle'] as String? ?? '').trim(),
    };
    return _ProgressData(report: report, muscleMap: muscleMap);
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

  Future<List<Map<String, dynamic>>> _loadTemplates() async {
    try {
      return await BackendApi.getTemplates();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.templatesCache);
      if (cached != null) {
        return cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadCatalog() async {
    try {
      return await BackendApi.getExercises();
    } catch (_) {
      final cached =
          LocalCache.get<List>(CacheKeys.exerciseCatalogCache);
      if (cached != null) {
        return cached.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
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

  List<ExerciseProgressAnalysis> _applyFilter(
      ProgressAnalysisReport report, String query) {
    final sorted = _sorted(report);
    final afterFilter = switch (_activeFilter) {
      _FilterTab.all => sorted,
      _FilterTab.increase =>
        sorted.where((a) => a.decision == ProgressDecision.increase).toList(),
      _FilterTab.keep => sorted
          .where((a) => a.decision == ProgressDecision.keep && !a.isStalled)
          .toList(),
      _FilterTab.attention => sorted
          .where((a) =>
              a.decision == ProgressDecision.decrease ||
              a.decision == ProgressDecision.insufficientData ||
              a.isStalled)
          .toList(),
    };
    if (query.isEmpty) return afterFilter;
    return afterFilter
        .where((a) => a.exerciseName.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: FutureBuilder<_ProgressData>(
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
                  BackendApi.describeError(snapshot.error!,
                      fallback: 'Не удалось загрузить прогресс.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final report = data.report;
          final stats = _computeStats(report);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fixed header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: ScreenTitle('Прогресс'),
                ),
              ),
              const SizedBox(height: 10),
              // ── Tab bar ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _StyledTabBar(controller: _tabController),
              ),
              const SizedBox(height: 10),
              // ── Tab content ───────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _RecommendationsTab(
                      report: report,
                      stats: stats,
                      searchController: _searchController,
                      activeFilter: _activeFilter,
                      onFilterChanged: (tab) => setState(() {
                        _activeFilter = tab;
                        _searchController.clear();
                      }),
                      onSearchChanged: () => setState(() {}),
                      applyFilter: _applyFilter,
                      onRefresh: _refresh,
                    ),
                    _StatisticsTab(
                      report: report,
                      stats: stats,
                      onRefresh: _refresh,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: scheme.primary.withValues(alpha: 0.18),
          border: Border.all(
              color: scheme.primary.withValues(alpha: 0.45)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
        unselectedLabelStyle:
            Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
        tabs: const [
          Tab(text: 'Рекомендации'),
          Tab(text: 'Статистика'),
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
    required this.searchController,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.applyFilter,
    required this.onRefresh,
  });

  final ProgressAnalysisReport report;
  final _ProgressStats stats;
  final TextEditingController searchController;
  final _FilterTab activeFilter;
  final ValueChanged<_FilterTab> onFilterChanged;
  final VoidCallback onSearchChanged;
  final List<ExerciseProgressAnalysis> Function(
      ProgressAnalysisReport, String) applyFilter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();
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

// ── Statistics tab ────────────────────────────────────────────────────────────

class _StatisticsTab extends StatelessWidget {
  const _StatisticsTab({
    required this.report,
    required this.stats,
    required this.onRefresh,
  });

  final ProgressAnalysisReport report;
  final _ProgressStats stats;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final topGrowth = _computeTopGrowth(report);
    final records = _computeRecords(report);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (topGrowth.isNotEmpty) ...[
            const DashboardSectionLabel('Топ прогресса'),
            const SizedBox(height: 10),
            ...topGrowth.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TopGrowthCard(
                      rank: entry.key + 1,
                      growth: entry.value,
                    ),
                  ),
                ),
            const SizedBox(height: 6),
          ],
          if (records.isNotEmpty) ...[
            const DashboardSectionLabel('Личные рекорды'),
            const SizedBox(height: 10),
            ...records.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecordCard(record: r),
              ),
            ),
          ],
          if (report.allExercises.isEmpty)
            DashboardCard(
              child: Text(
                'Недостаточно истории для статистики.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}


// ── Distribution bar ──────────────────────────────────────────────────────────

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
                    color: _colorKeep,
                    label: '${stats.keepCount} норма'),
                const SizedBox(width: 14),
              ],
              if (stats.attentionCount > 0)
                _DistLegend(
                    color: _colorAttention,
                    label: '${stats.attentionCount} внимание'),
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
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
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
            label: 'Внимание',
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
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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

// ── Top growth card ───────────────────────────────────────────────────────────

class _TopGrowthCard extends StatelessWidget {
  const _TopGrowthCard({required this.rank, required this.growth});
  final int rank;
  final _ExerciseGrowth growth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rankColors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : scheme.onSurfaceVariant;

    return DashboardCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rankColor.withValues(alpha: 0.15),
              border: Border.all(color: rankColor.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: rankColor,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  growth.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatWeight(growth.firstRm)} → ${_formatWeight(growth.lastRm)} кг · ${growth.sessionCount} трен',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _colorIncrease.withValues(alpha: 0.15),
              border: Border.all(
                  color: _colorIncrease.withValues(alpha: 0.35)),
            ),
            child: Text(
              '+${growth.growthPct.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _colorIncrease,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Record card ───────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final _ExerciseRecords record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = record.history.first;
    final prev = record.history.skip(1).toList();
    const gold = Color(0xFFFFD700);

    return DashboardCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatShortDate(current.date),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: gold.withValues(alpha: 0.12),
                  border: Border.all(color: gold.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatWeight(current.weight),
                      style: const TextStyle(
                        fontFamily: 'Bebas Neue Cyrillic',
                        fontSize: 42,
                        color: Color(0xFFFFD700),
                        height: 1,
                        letterSpacing: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        'кг × ${current.reps}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: gold.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (prev.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...prev.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 13,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatWeight(e.weight)} кг × ${e.reps}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${formatShortDate(e.date)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Exercise detail card ──────────────────────────────────────────────────────

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

    final weightPrefix = isIncrease ? '↑ ' : (isDecrease ? '↓ ' : '');
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
          color: Color.alphaBlend(
            scheme.secondary.withValues(alpha: 0.07),
            scheme.surfaceContainerLow,
          ),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.22)),
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
                  tilePadding: const EdgeInsets.fromLTRB(22, 10, 14, 10),
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
                                    value:
                                        '${_formatWeight(latest.workingSet.normalizedWeight)} кг',
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 14),
                                  _InlineMetric(
                                    label: '1ПМ',
                                    value:
                                        '${_formatWeight(latest.workingSet.estimated1rm)} кг',
                                    color: scheme.tertiary,
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

// ── Inline metric ─────────────────────────────────────────────────────────────

class _InlineMetric extends StatelessWidget {
  const _InlineMetric(
      {required this.label, required this.value, required this.color});
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

// ── Combined chart ────────────────────────────────────────────────────────────

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
    final surfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

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
    final minY = allValues.reduce((a, b) => a < b ? a : b) * 0.94;
    final maxY = allValues.reduce((a, b) => a > b ? a : b) * 1.06;
    final yInterval = (maxY - minY) / 4;

    LineChartBarData buildLine(
        {required List<double> values, required Color color}) {
      final lastIndex = values.length - 1;
      return LineChartBarData(
        isCurved: true,
        curveSmoothness: 0.35,
        barWidth: 2.5,
        color: color,
        shadow: Shadow(color: color.withValues(alpha: 0.38), blurRadius: 10),
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) {
            final isTouched = _touchedIndex == index;
            final isLast = index == lastIndex;
            return FlDotCirclePainter(
              radius: isTouched ? 6.5 : (isLast ? 5.0 : 3.0),
              color: color,
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
            values.length, (i) => FlSpot(i.toDouble(), values[i])),
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
                _ChartLegendItem(color: colorNorm, label: 'Норм. вес'),
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
                    final idx =
                        response?.lineBarSpots?.firstOrNull?.spotIndex;
                    if (_touchedIndex != idx) {
                      setState(() => _touchedIndex = idx);
                    }
                  },
                  getTouchedSpotIndicator: (barData, spotIndexes) =>
                      spotIndexes
                          .map((_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.18),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4],
                                ),
                                const FlDotData(show: false),
                              ))
                          .toList(),
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        Theme.of(context).colorScheme.inverseSurface,
                    getTooltipItems: (spots) => spots.map((spot) {
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
                        final isEdge =
                            index == 0 || index == sessions.length - 1;
                        if (!showAll && !isEdge) return const SizedBox.shrink();
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
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

String _formatWeight(double value) => formatWeight(value);
