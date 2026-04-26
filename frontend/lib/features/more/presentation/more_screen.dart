import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/theme/theme_notifier.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../body/presentation/body_screen.dart';
import '../../coach/presentation/ai_coach_screen.dart';
import '../../programs/presentation/programs_screen.dart';
import '../../templates/presentation/templates_screen.dart';
import 'admin_functions_screen.dart';

class MoreScreen extends StatefulWidget {
  static const _ownerEmail = 'ialeonov@yandex.ru';

  const MoreScreen({
    super.key,
    required this.onLogout,
    required this.onOpenSocialHub,
  });

  final Future<void> Function() onLogout;
  final Future<void> Function() onOpenSocialHub;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _currentUserEmail = LocalCache.get<String>(CacheKeys.currentUserEmail)
        ?.trim()
        .toLowerCase();
    if (_currentUserEmail == null || _currentUserEmail!.isEmpty) {
      _restoreCurrentUserEmail();
    }
  }

  Future<void> _restoreCurrentUserEmail() async {
    try {
      final user = await BackendApi.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUserEmail = user['email']?.toString().trim().toLowerCase();
      });
    } catch (_) {
      // Quietly ignore: the owner-only tile should stay hidden if the profile
      // couldn't be restored.
    }
  }

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
    final isOwner = _currentUserEmail == MoreScreen._ownerEmail;

    return AppBackdrop(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          const ScreenHeader(
            title: 'Инструменты',
          ),
          const SizedBox(height: 10),
          _MoreTile(
            title: 'AI-коуч',
            icon: Icons.smart_toy_rounded,
            iconColor: const Color(0xFF1A8F6D),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiCoachScreen()),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(height: 8),
            _MoreTile(
              title: 'Админ функции',
              icon: Icons.admin_panel_settings_rounded,
              iconColor: const Color(0xFF7A5A0A),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminFunctionsScreen(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _MoreTile(
            title: 'Упражнения',
            icon: Icons.fitness_center_rounded,
            iconColor: scheme.tertiary,
            onTap: () => _openPage(
              context,
              title: 'Упражнения',
              child: const TemplatesScreen(section: TemplatesSection.exercises),
            ),
          ),
          const SizedBox(height: 8),
          _MoreTile(
            title: 'Шаблоны',
            icon: Icons.library_books_rounded,
            iconColor: scheme.secondary,
            onTap: () => _openPage(
              context,
              title: 'Шаблоны',
              child: const TemplatesScreen(section: TemplatesSection.templates),
            ),
          ),
          const SizedBox(height: 8),
          _MoreTile(
            title: 'Программы',
            icon: Icons.auto_stories_rounded,
            iconColor: const Color(0xFF7C5CBF),
            onTap: () => _openPage(
              context,
              title: 'Программы',
              child: const ProgramsScreen(),
            ),
          ),
          const SizedBox(height: 8),
          _MoreTile(
            title: 'Параметры тела',
            icon: Icons.monitor_weight_rounded,
            iconColor: scheme.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BodyScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _ThemeToggleTile(),
          const SizedBox(height: 12),
          const DashboardSectionLabel('Социальные функции'),
          const SizedBox(height: 8),
          _MoreTile(
            title: 'Профиль и сообщество',
            icon: Icons.groups_2_rounded,
            iconColor: scheme.secondary,
            onTap: () => widget.onOpenSocialHub(),
          ),
          const SizedBox(height: 6),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: widget.onLogout,
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
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: accentColor,
            size: 20,
          ),
        ),
        title: Text(
          isDark ? 'Тёмная тема' : 'Светлая тема',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        trailing: Switch(
          value: !isDark,
          onChanged: (_) => ThemeNotifier.instance.toggleTheme(),
          activeThumbColor: accentColor,
        ),
        onTap: () => ThemeNotifier.instance.toggleTheme(),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final String title;
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
          horizontal: 16,
          vertical: isCompact ? 0 : 1,
        ),
        leading: Container(
          width: isCompact ? 34 : 38,
          height: isCompact ? 34 : 38,
          decoration: BoxDecoration(
            color: (iconColor ?? Theme.of(context).colorScheme.secondary)
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: iconColor ?? Theme.of(context).colorScheme.secondary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
