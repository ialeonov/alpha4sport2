import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';

class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key});

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends State<BodyScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadEntries();
  }

  Future<List<Map<String, dynamic>>> _loadEntries() async {
    try {
      return await BackendApi.getBodyEntries();
    } catch (_) {
      final cached = LocalCache.get<List>(CacheKeys.bodyEntriesCache);
      if (cached != null) {
        return cached
            .cast<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList();
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadEntries());
    await _future;
  }

  double? _parseNumber(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  Future<void> _openEntryDialog({Map<String, dynamic>? entry}) async {
    final existingDate =
        DateTime.tryParse((entry?['entry_date'] ?? '').toString())?.toLocal() ??
            DateTime.now();
    var selectedDate = DateUtils.dateOnly(existingDate);

    final weightController = TextEditingController(
      text: entry?['weight_kg']?.toString() ?? '',
    );
    final waistController = TextEditingController(
      text: entry?['waist_cm']?.toString() ?? '',
    );
    final chestController = TextEditingController(
      text: entry?['chest_cm']?.toString() ?? '',
    );
    final hipsController = TextEditingController(
      text: entry?['hips_cm']?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: (entry?['notes'] ?? '').toString(),
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(entry == null ? 'Новая запись' : 'Редактировать запись'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дата'),
                  subtitle: Text(formatShortDate(selectedDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setLocalState(
                          () => selectedDate = DateUtils.dateOnly(picked));
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Вес, кг'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: waistController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Талия, см'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: chestController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Грудь, см'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hipsController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Бёдра, см'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Заметка'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(entry == null ? 'Сохранить' : 'Обновить'),
            ),
          ],
        ),
      ),
    );

    if (save != true) {
      return;
    }

    try {
      await BackendApi.createBodyEntry(
        entryDate: selectedDate,
        weightKg: _parseNumber(weightController.text),
        waistCm: _parseNumber(waistController.text),
        chestCm: _parseNumber(chestController.text),
        hipsCm: _parseNumber(hipsController.text),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );

      if (entry != null) {
        await BackendApi.deleteBodyEntry(entry['id'] as int);
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entry == null
                ? 'Запись о параметрах сохранена.'
                : 'Запись о параметрах обновлена.',
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: entry == null
                  ? 'Не удалось сохранить запись.'
                  : 'Не удалось обновить запись.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteEntry(int entryId) async {
    try {
      await BackendApi.deleteBodyEntry(entryId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запись удалена.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось удалить запись.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Параметры тела')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEntryDialog(),
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Добавить запись'),
      ),
      body: AppBackdrop(
        child: FutureBuilder<List<Map<String, dynamic>>>(
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
                      fallback: 'Не удалось загрузить параметры тела.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer,
                            scheme.secondaryContainer,
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.monitor_weight_outlined,
                            size: 46,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Пока нет записей',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Добавьте первый замер, чтобы отслеживать вес и изменения тела по датам.',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                      height: 1.35,
                                    ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _openEntryDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Создать первую запись'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final prevEntry =
                      index + 1 < entries.length ? entries[index + 1] : null;
                  final entryDate = DateTime.tryParse(
                    (entry['entry_date'] ?? '').toString(),
                  )?.toLocal();

                  final currentWeight =
                      (entry['weight_kg'] as num?)?.toDouble();
                  final prevWeight =
                      (prevEntry?['weight_kg'] as num?)?.toDouble();
                  final weightDelta = (currentWeight != null &&
                          prevWeight != null)
                      ? currentWeight - prevWeight
                      : null;

                  return Dismissible(
                    key: ValueKey(entry['id']),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      await _deleteEntry(entry['id'] as int);
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(Icons.delete_outline, color: scheme.error),
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entryDate == null
                                            ? 'Без даты'
                                            : formatShortDate(entryDate),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            currentWeight == null
                                                ? '—'
                                                : '${entry['weight_kg']}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w900,
                                                  height: 1.0,
                                                ),
                                          ),
                                          if (currentWeight != null) ...[
                                            const SizedBox(width: 4),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 3),
                                              child: Text(
                                                'кг',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                          if (weightDelta != null) ...[
                                            const SizedBox(width: 10),
                                            _TrendBadge(delta: weightDelta),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _openEntryDialog(entry: entry),
                                  tooltip: 'Редактировать',
                                  icon: const Icon(
                                      Icons.edit_rounded,
                                      size: 20),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (entry['waist_cm'] != null)
                                  _MetricChip(
                                    label: 'Талия',
                                    value: '${entry['waist_cm']} см',
                                  ),
                                if (entry['chest_cm'] != null)
                                  _MetricChip(
                                    label: 'Грудь',
                                    value: '${entry['chest_cm']} см',
                                  ),
                                if (entry['hips_cm'] != null)
                                  _MetricChip(
                                    label: 'Бёдра',
                                    value: '${entry['hips_cm']} см',
                                  ),
                                if (entry['waist_cm'] == null &&
                                    entry['chest_cm'] == null &&
                                    entry['hips_cm'] == null)
                                  _MetricChip(
                                    label: 'Обхваты',
                                    value: 'не указаны',
                                    muted: true,
                                  ),
                              ],
                            ),
                            if ((entry['notes'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  (entry['notes'] ?? '').toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: muted
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUp = delta > 0.001;
    final isDown = delta < -0.001;
    final color = isDown
        ? scheme.tertiary
        : isUp
            ? scheme.error
            : scheme.onSurfaceVariant;
    final icon = isDown
        ? Icons.arrow_downward_rounded
        : isUp
            ? Icons.arrow_upward_rounded
            : Icons.remove_rounded;
    final sign = isUp ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            '$sign${delta.toStringAsFixed(1)} кг',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
