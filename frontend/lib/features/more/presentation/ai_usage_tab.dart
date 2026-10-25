import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/athletic_ui.dart';

const _featureLabels = {
  'chat': 'Чат с коучем',
  'generate_workout': 'Генерация тренировки',
  'generate_workout_retry': 'Генерация (повтор)',
  'daily_insight': 'Брифинг на главной',
  'progress_summary': 'Комментарий к прогрессу',
  'memory': 'Память коуча',
};

/// Расход токенов AI по функциям — чтобы видеть, что стоит денег.
class AiUsageTab extends StatefulWidget {
  const AiUsageTab({super.key});

  @override
  State<AiUsageTab> createState() => _AiUsageTabState();
}

class _AiUsageTabState extends State<AiUsageTab> {
  int _days = 30;
  late Future<Map<String, dynamic>> _future = BackendApi.getOwnerAiUsage(days: _days);

  void _setDays(int days) {
    setState(() {
      _days = days;
      _future = BackendApi.getOwnerAiUsage(days: days);
    });
  }

  static String _fmt(num value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} млн';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} тыс.';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<Map<String, dynamic>>(
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
                    fallback: 'Не удалось загрузить расход AI.'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final rows = (data['by_feature'] as List? ?? const [])
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        final requests = (data['requests'] as num?) ?? 0;
        final cacheHits = (data['cache_hits'] as num?) ?? 0;
        final prompt = (data['prompt_tokens'] as num?) ?? 0;
        final completion = (data['completion_tokens'] as num?) ?? 0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 дней')),
                ButtonSegment(value: 30, label: Text('30 дней')),
                ButtonSegment(value: 90, label: Text('90 дней')),
              ],
              selected: {_days},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _setDays(v.first),
            ),
            const SizedBox(height: 12),
            DashboardCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_fmt(prompt + completion)} токенов',
                    style: textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Запросов: $requests · из кэша: $cacheHits · '
                    'вход ${_fmt(prompt)} / выход ${_fmt(completion)}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (data['estimated'] == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Часть значений оценена по длине текста: провайдер не '
                      'вернул точный расход.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const DashboardCard(child: Text('За этот период запросов не было.'))
            else
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DashboardCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _featureLabels[row['feature']] ??
                                    row['feature'].toString(),
                                style: textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'запросов ${row['requests']}, из кэша ${row['cache_hits']}',
                                style: textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _fmt((row['prompt_tokens'] as num) +
                              (row['completion_tokens'] as num)),
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
