import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/athletic_ui.dart';

class FitnessProfileScreen extends StatefulWidget {
  const FitnessProfileScreen({super.key});

  @override
  State<FitnessProfileScreen> createState() => _FitnessProfileScreenState();
}

class _FitnessProfileScreenState extends State<FitnessProfileScreen> {
  static const _goals = ['масса', 'сила', 'похудение', 'поддержание'];
  static const _goalLabels = [
    'Набор массы',
    'Развитие силы',
    'Похудение',
    'Поддержание формы'
  ];
  static const _experiences = ['новичок', 'средний', 'продвинутый'];
  static const _experienceLabels = ['Новичок', 'Средний', 'Продвинутый'];
  static const _genders = ['мужской', 'женский'];
  static const _genderLabels = ['Мужской', 'Женский'];

  bool _loading = true;
  bool _saving = false;

  final Set<String> _selectedGoals = {};
  String? _experience;
  String? _gender;
  int? _daysPerWeek;
  final _injuriesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _injuriesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await BackendApi.getFitnessProfile();
      if (!mounted) return;
      setState(() {
        final rawGoals = data['goals'];
        _selectedGoals.clear();
        if (rawGoals is List) {
          _selectedGoals.addAll(rawGoals.cast<String>());
        }
        _experience = data['experience'] as String?;
        _gender = data['gender'] as String?;
        _daysPerWeek = data['daysPerWeek'] as int?;
        _injuriesController.text = (data['injuries'] as String?) ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _toggleGoal(String value) {
    setState(() {
      if (_selectedGoals.contains(value)) {
        _selectedGoals.remove(value);
      } else if (_selectedGoals.length < 2) {
        _selectedGoals.add(value);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BackendApi.updateFitnessProfile(
        goals: _selectedGoals.toList(),
        experience: _experience,
        gender: _gender,
        injuries: _injuriesController.text.trim().isEmpty
            ? null
            : _injuriesController.text.trim(),
        daysPerWeek: _daysPerWeek,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль сохранён')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Фитнес профиль'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _SectionLabel('Основное'),
          const SizedBox(height: 8),
          DashboardCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MultiChipRow(
                  label: 'Цель',
                  hint: 'можно выбрать до 2',
                  icon: Icons.flag_rounded,
                  values: _goals,
                  labels: _goalLabels,
                  selected: _selectedGoals,
                  onToggle: _toggleGoal,
                  maxReached: _selectedGoals.length >= 2,
                ),
                Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.3)),
                _ChipRow(
                  label: 'Опыт',
                  icon: Icons.trending_up_rounded,
                  values: _experiences,
                  labels: _experienceLabels,
                  selected: _experience,
                  onChanged: (v) => setState(() => _experience = v),
                ),
                Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.3)),
                _ChipRow(
                  label: 'Пол',
                  icon: Icons.person_rounded,
                  values: _genders,
                  labels: _genderLabels,
                  selected: _gender,
                  onChanged: (v) => setState(() => _gender = v),
                ),
                Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.3)),
                _DaysPicker(
                  value: _daysPerWeek,
                  onChanged: (v) => setState(() => _daysPerWeek = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Ограничения и травмы'),
          const SizedBox(height: 8),
          DashboardCard(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _injuriesController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'Например: боль в правом плече, исключить жим вверх; проблемы с коленом',
                hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                border: InputBorder.none,
                counterStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI-коуч будет учитывать эти данные при рекомендациях.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
      ),
    );
  }
}

class _MultiChipRow extends StatelessWidget {
  const _MultiChipRow({
    required this.label,
    required this.hint,
    required this.icon,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onToggle,
    required this.maxReached,
  });

  final String label;
  final String hint;
  final IconData icon;
  final List<String> values;
  final List<String> labels;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool maxReached;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 6),
              Text(
                hint,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(values.length, (i) {
              final isSelected = selected.contains(values[i]);
              final isDisabled = maxReached && !isSelected;
              return FilterChip(
                label: Text(labels[i]),
                selected: isSelected,
                onSelected: isDisabled ? null : (_) => onToggle(values[i]),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? scheme.onPrimary
                      : isDisabled
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
                          : scheme.onSurfaceVariant,
                ),
                selectedColor: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                disabledColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                side: BorderSide(
                  color: isSelected
                      ? scheme.primary
                      : scheme.outlineVariant
                          .withValues(alpha: isDisabled ? 0.2 : 0.4),
                ),
                checkmarkColor: scheme.onPrimary,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.icon,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<String> values;
  final List<String> labels;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(values.length, (i) {
              final isSelected = selected == values[i];
              return ChoiceChip(
                label: Text(labels[i]),
                selected: isSelected,
                onSelected: (_) => onChanged(isSelected ? null : values[i]),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                selectedColor: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                side: BorderSide(
                  color: isSelected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DaysPicker extends StatelessWidget {
  const _DaysPicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Дней в неделю',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: List.generate(7, (i) {
              final day = i + 1;
              final isSelected = value == day;
              return ChoiceChip(
                label: Text('$day'),
                selected: isSelected,
                onSelected: (_) => onChanged(isSelected ? null : day),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                selectedColor: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
                side: BorderSide(
                  color: isSelected
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
