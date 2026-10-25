import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Ввод следующего подхода: крупные числа, которые можно набрать с
/// клавиатуры или поправить кнопками ±, и RPE в один тап.
class SetQuickEntry extends StatefulWidget {
  const SetQuickEntry({
    super.key,
    required this.setNumber,
    required this.initialWeight,
    required this.initialReps,
    required this.onSubmit,
    this.restSeconds,
    this.hint = '',
  });

  final int setNumber;
  final double initialWeight;
  final int initialReps;

  /// Длительность отдыха, которая запустится после записи (для подписи).
  final int? restSeconds;
  final void Function(double weight, int reps, double? rpe) onSubmit;

  /// Подсказка справа от номера подхода (например, «рекорд 100 кг»).
  final String hint;

  @override
  State<SetQuickEntry> createState() => _SetQuickEntryState();
}

class _SetQuickEntryState extends State<SetQuickEntry> {
  static const _rpeValues = [6.0, 7.0, 8.0, 9.0, 10.0];

  late final TextEditingController _weight =
      TextEditingController(text: formatWeight(widget.initialWeight));
  late final TextEditingController _reps =
      TextEditingController(text: '${widget.initialReps}');
  double? _rpe;

  @override
  void didUpdateWidget(covariant SetQuickEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    // После записи подхода предлагаем те же значения для следующего.
    if (oldWidget.setNumber != widget.setNumber) {
      _weight.text = formatWeight(widget.initialWeight);
      _reps.text = '${widget.initialReps}';
      _rpe = null;
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  double get _weightValue =>
      double.tryParse(_weight.text.trim().replaceAll(',', '.')) ?? 0;
  int get _repsValue => int.tryParse(_reps.text.trim()) ?? 0;

  void _changeWeight(double delta) {
    HapticFeedback.selectionClick();
    final next = (_weightValue + delta).clamp(0, 1500).toDouble();
    setState(() => _weight.text = formatWeight(next));
  }

  void _changeReps(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _reps.text = '${(_repsValue + delta).clamp(1, 999)}');
  }

  void _submit() {
    if (_repsValue <= 0) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    widget.onSubmit(_weightValue, _repsValue, _rpe);
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
          Row(
            children: [
              Text(
                'Подход ${widget.setNumber}',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (widget.hint.isNotEmpty)
                Text(
                  widget.hint,
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberStepper(
                  controller: _weight,
                  unit: 'кг',
                  decimal: true,
                  onMinus: () => _changeWeight(-2.5),
                  onPlus: () => _changeWeight(2.5),
                  minusLabel: 'Минус 2,5 кг',
                  plusLabel: 'Плюс 2,5 кг',
                  fieldLabel: 'Вес, кг',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberStepper(
                  controller: _reps,
                  unit: 'повт.',
                  decimal: false,
                  onMinus: () => _changeReps(-1),
                  onPlus: () => _changeReps(1),
                  minusLabel: 'Минус повтор',
                  plusLabel: 'Плюс повтор',
                  fieldLabel: 'Повторы',
                  onSubmitted: _submit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  'RPE',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
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

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.controller,
    required this.unit,
    required this.decimal,
    required this.onMinus,
    required this.onPlus,
    required this.minusLabel,
    required this.plusLabel,
    required this.fieldLabel,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String unit;
  final bool decimal;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final String minusLabel;
  final String plusLabel;
  final String fieldLabel;
  final VoidCallback? onSubmitted;

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
                // Число вводится и с клавиатуры: тап — выделяется целиком.
                TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: decimal),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
                    ),
                  ],
                  textInputAction: onSubmitted == null
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onSubmitted: (_) => onSubmitted?.call(),
                  onTap: () => controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  ),
                  style: TextStyle(
                    fontFamily: 'Bebas Neue Cyrillic',
                    fontSize: 30,
                    height: 1,
                    color: scheme.onSurface,
                    fontFeatures: _tabular,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
                  ),
                ),
                Text(
                  unit,
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
      width: 34,
      height: 52,
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLow,
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
        icon: Icon(icon, size: 20, color: scheme.onSurface),
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
      height: 42,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor:
              selected ? scheme.primary : scheme.surfaceContainerLow,
          foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        child: Text(value.toStringAsFixed(0)),
      ),
    );
  }
}
