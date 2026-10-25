import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Быстрый ввод следующего подхода: крупные цифры, ± в один тап, RPE.
/// Рассчитан на одну руку и телефон, лежащий на скамье.
class SetQuickEntry extends StatefulWidget {
  const SetQuickEntry({
    super.key,
    required this.setNumber,
    required this.initialWeight,
    required this.initialReps,
    required this.onSubmit,
    this.initialRpe,
    this.restSeconds,
  });

  final int setNumber;
  final double initialWeight;
  final int initialReps;
  final double? initialRpe;

  /// Длительность отдыха, которая запустится после записи (для подписи).
  final int? restSeconds;
  final void Function(double weight, int reps, double? rpe) onSubmit;

  @override
  State<SetQuickEntry> createState() => _SetQuickEntryState();
}

class _SetQuickEntryState extends State<SetQuickEntry> {
  static const _rpeValues = [6.0, 7.0, 8.0, 9.0, 10.0];

  late double _weight = widget.initialWeight;
  late int _reps = widget.initialReps;
  late double? _rpe = widget.initialRpe;

  @override
  void didUpdateWidget(covariant SetQuickEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    // После записи подхода предлагаем те же значения для следующего.
    if (oldWidget.setNumber != widget.setNumber) {
      _weight = widget.initialWeight;
      _reps = widget.initialReps;
      _rpe = null;
    }
  }

  void _changeWeight(double delta) {
    HapticFeedback.selectionClick();
    setState(() => _weight = (_weight + delta).clamp(0, 1500).toDouble());
  }

  void _changeReps(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _reps = (_reps + delta).clamp(1, 999));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rest = widget.restSeconds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Подход ${widget.setNumber}',
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Stepper(
                  label: 'кг',
                  value: formatWeight(_weight),
                  onMinus: () => _changeWeight(-2.5),
                  onPlus: () => _changeWeight(2.5),
                  minusLabel: 'Минус 2,5 кг',
                  plusLabel: 'Плюс 2,5 кг',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stepper(
                  label: 'повт.',
                  value: '$_reps',
                  onMinus: () => _changeReps(-1),
                  onPlus: () => _changeReps(1),
                  minusLabel: 'Минус повтор',
                  plusLabel: 'Плюс повтор',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Насколько тяжело (RPE)',
            style:
                textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final value in _rpeValues) ...[
                Expanded(
                  child: _RpeButton(
                    value: value,
                    selected: _rpe == value,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _rpe = _rpe == value ? null : value);
                    },
                  ),
                ),
                if (value != _rpeValues.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _reps > 0
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onSubmit(_weight, _reps, _rpe);
                  }
                : null,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
            child: Text(
              rest == null
                  ? 'Записать подход'
                  : 'Записать · отдых ${rest ~/ 60}:${(rest % 60).toString().padLeft(2, '0')}',
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    required this.minusLabel,
    required this.plusLabel,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final String minusLabel;
  final String plusLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StepButton(
              icon: Icons.remove_rounded, onTap: onMinus, label: minusLabel),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Bebas Neue Cyrillic',
                      fontSize: 36,
                      height: 1,
                      color: scheme.onSurface,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onPlus, label: plusLabel),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(
      {required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 48,
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLow,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        icon: Icon(icon, color: scheme.onSurface),
      ),
    );
  }
}

class _RpeButton extends StatelessWidget {
  const _RpeButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor:
              selected ? scheme.onSurface : scheme.surfaceContainerLow,
          foregroundColor: selected ? scheme.surface : scheme.onSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        child: Text(value.toStringAsFixed(0)),
      ),
    );
  }
}
