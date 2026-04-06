import 'package:flutter/material.dart';

import '../../../core/theme/theme_notifier.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../body/presentation/body_screen.dart';
import '../../programs/presentation/programs_screen.dart';
import '../../templates/presentation/templates_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.onLogout,
    required this.onOpenSocialHub,
  });

  final Future<void> Function() onLogout;
  final Future<void> Function() onOpenSocialHub;

  void _openPage(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBackdrop(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          DashboardSummaryCard(
            subtitle: 'Инструменты и разделы',
            title: 'Инструменты',
          ),
          const SizedBox(height: 16),
          const DashboardSectionLabel('Инструменты'),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'Упражнения',
            subtitle: 'Каталог упражнений с группировкой по мышцам.',
            icon: Icons.fitness_center_rounded,
            iconColor: scheme.tertiary,
            onTap: () => _openPage(
              context,
              title: 'Упражнения',
              child: const TemplatesScreen(
                  section: TemplatesSection.exercises),
            ),
          ),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'Шаблоны',
            subtitle: 'Шаблоны тренировок для быстрого старта.',
            icon: Icons.library_books_rounded,
            iconColor: scheme.secondary,
            onTap: () => _openPage(
              context,
              title: 'Шаблоны',
              child: const TemplatesScreen(
                  section: TemplatesSection.templates),
            ),
          ),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'Программы',
            subtitle:
                'Готовые программы тренировок по уровням сложности.',
            icon: Icons.auto_stories_rounded,
            iconColor: const Color(0xFF7C5CBF),
            onTap: () => _openPage(
              context,
              title: 'Программы',
              child: const ProgramsScreen(),
            ),
          ),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'Параметры тела',
            subtitle: 'Вес, обхваты и заметки по форме с возможностью правки.',
            icon: Icons.monitor_weight_rounded,
            iconColor: scheme.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BodyScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ThemeToggleTile(),
          const SizedBox(height: 18),
          const DashboardSectionLabel('Социальные функции'),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'Профиль и сообщество',
            subtitle: 'Профиль, пользователи и лента событий в одном разделе.',
            icon: Icons.groups_2_rounded,
            iconColor: scheme.secondary,
            onTap: () => onOpenSocialHub(),
          ),
          const SizedBox(height: 8),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Выйти из аккаунта'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggleTile extends StatefulWidget {
  @override
  State<_ThemeToggleTile> createState() => _ThemeToggleTileState();
}

class _ThemeToggleTileState extends State<_ThemeToggleTile> {
  @override
  void initState() {
    super.initState();
    ThemeNotifier.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    ThemeNotifier.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.instance.isDark;
    final scheme = Theme.of(context).colorScheme;
    final accentColor = isDark ? scheme.secondary : const Color(0xFF1A6B75);

    return DashboardCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: accentColor,
            size: 22,
          ),
        ),
        title: Text(
          isDark ? 'Тёмная тема' : 'Светлая тема',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(isDark ? 'Переключить на светлую' : 'Переключить на тёмную'),
        ),
        trailing: Switch(
          value: !isDark,
          onChanged: (_) => ThemeNotifier.instance.toggleTheme(),
          activeColor: accentColor,
        ),
        onTap: () => ThemeNotifier.instance.toggleTheme(),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;

    return DashboardCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: 0,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: isCompact ? 2 : 4,
        ),
        leading: Container(
          width: isCompact ? 38 : 42,
          height: isCompact ? 38 : 42,
          decoration: BoxDecoration(
            color: (iconColor ?? Theme.of(context).colorScheme.secondary)
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: iconColor ?? Theme.of(context).colorScheme.secondary,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: isCompact ? 4 : 6),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
