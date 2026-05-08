import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../data/wellness_repository.dart';
import '../domain/wellness_entry.dart';

// ── Zone helpers ──────────────────────────────────────────────────────────────

Color wellnessZoneAccent(WellnessZone zone) {
  switch (zone) {
    case WellnessZone.green:
      return const Color(0xFF4CAF50);
    case WellnessZone.yellow:
      return const Color(0xFFFFC107);
    case WellnessZone.red:
      return const Color(0xFFF44336);
  }
}

/// Semi-transparent fill for the calendar cell background (50 %).
Color wellnessZoneCellColor(WellnessZone zone) =>
    wellnessZoneAccent(zone).withValues(alpha: 0.50);

Color _zoneBg(WellnessZone zone) =>
    wellnessZoneAccent(zone).withValues(alpha: 0.15);

String _zoneTitle(WellnessZone zone) {
  switch (zone) {
    case WellnessZone.green:
      return 'Отличная форма';
    case WellnessZone.yellow:
      return 'Средняя форма';
    case WellnessZone.red:
      return 'Нужен отдых';
  }
}

// ── Unified wellness card ─────────────────────────────────────────────────────
//
// Used on both the Today screen and the Calendar day detail.
// Empty state  → one compact row  [🌡] <emptyLabel>  [+]
// Filled state → two-row card with zone colour accent strip + tinted background

class WellnessCard extends StatelessWidget {
  const WellnessCard({
    super.key,
    required this.entry,
    required this.date,
    required this.onChanged,
    this.emptyLabel = 'Как самочувствие?',
  });

  final WellnessEntry? entry;
  final DateTime date;
  final VoidCallback onChanged;

  /// Label shown in the empty (unfilled) state.
  final String emptyLabel;

  Future<void> _open(BuildContext context) async {
    await showWellnessSheet(context, date: date, existing: entry);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) {
      return _EmptyWellnessCard(
        label: emptyLabel,
        onTap: () => _open(context),
      );
    }
    return _FilledWellnessCard(
      entry: e,
      onTap: () => _open(context),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyWellnessCard extends StatelessWidget {
  const _EmptyWellnessCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Icon(
                Icons.add_circle_outline_rounded,
                size: 22,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filled state ──────────────────────────────────────────────────────────────

class _FilledWellnessCard extends StatelessWidget {
  const _FilledWellnessCard({required this.entry, required this.onTap});

  final WellnessEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zone = entry.zone;
    final accent = wellnessZoneAccent(zone);
    final bg = _zoneBg(zone);

    final paramsLine = 'сон ${entry.sleep} · энергия ${entry.energy} · '
        'стресс ${entry.stress} · настроение ${entry.mood}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent strip
                Container(width: 4, color: accent),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _zoneTitle(zone),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color:
                                    accent.withValues(alpha: 0.85).withValues(
                                          alpha: Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? 1.0
                                              : 0.85,
                                        ),
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          paramsLine,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.70),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

Future<WellnessEntry?> showWellnessSheet(
  BuildContext context, {
  required DateTime date,
  WellnessEntry? existing,
}) {
  return showModalBottomSheet<WellnessEntry>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _WellnessSheet(date: date, existing: existing),
  );
}

class _WellnessSheet extends StatefulWidget {
  const _WellnessSheet({required this.date, this.existing});

  final DateTime date;
  final WellnessEntry? existing;

  @override
  State<_WellnessSheet> createState() => _WellnessSheetState();
}

class _WellnessSheetState extends State<_WellnessSheet> {
  late int _sleep;
  late int _energy;
  late int _stress;
  late int _mood;
  late TextEditingController _commentController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _sleep = e?.sleep ?? 3;
    _energy = e?.energy ?? 3;
    _stress = e?.stress ?? 3;
    _mood = e?.mood ?? 3;
    _commentController = TextEditingController(text: e?.comment ?? '');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _dateLabel() {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    final d = widget.date;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = WellnessEntry(
      date: widget.date,
      sleep: _sleep,
      energy: _energy,
      stress: _stress,
      mood: _mood,
      comment: _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );
    try {
      await WellnessRepository.save(entry);
      if (mounted) Navigator.of(context).pop(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              e,
              fallback: 'Не удалось сохранить самочувствие.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'САМОЧУВСТВИЕ · ${_dateLabel()}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
              ),
              const SizedBox(height: 20),
              _SliderRow(
                emoji: '😴',
                label: 'Сон',
                value: _sleep,
                onChanged: (v) => setState(() => _sleep = v),
                scheme: scheme,
              ),
              const SizedBox(height: 12),
              _SliderRow(
                emoji: '⚡',
                label: 'Энергия',
                value: _energy,
                onChanged: (v) => setState(() => _energy = v),
                scheme: scheme,
              ),
              const SizedBox(height: 12),
              _SliderRow(
                emoji: '😰',
                label: 'Стресс',
                value: _stress,
                onChanged: (v) => setState(() => _stress = v),
                scheme: scheme,
              ),
              const SizedBox(height: 12),
              _SliderRow(
                emoji: '😊',
                label: 'Настроение',
                value: _mood,
                onChanged: (v) => setState(() => _mood = v),
                scheme: scheme,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Добавить заметку...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.emoji,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.scheme,
  });

  final String emoji;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: List.generate(5, (i) {
              final filled = i < value;
              return GestureDetector(
                onTap: () => onChanged(i + 1),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.10),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$value/5',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
